// SnippetManager.swift — Load, watch, execute snippets from ~/Library/Application Support/Macotron/
import CQuickJS
import Foundation
import os

private let logger = Logger(subsystem: "com.macotron", category: "snippets")

@MainActor
public final class SnippetManager {
    public let engine: Engine
    public let configDir: URL
    public let backup: ConfigBackup

    private var fsEventStream: FSEventStreamRef?
    private var reloadDebounceTask: Task<Void, Never>?

    /// Optional handler for auto-fixing broken snippets via AI.
    /// Parameters: (filename, source, errorMessage) -> fixed source or nil.
    /// Set by the app target to bridge SnippetManager (MacotronEngine) to SnippetAutoFix (AI).
    public var autoFixHandler: (@Sendable (String, String, String) async -> String?)?

    /// Tracks how many auto-fix attempts each file has had during the current reload cycle.
    /// Reset at the start of each `reloadAll()`.
    private var autoFixAttempts: [String: Int] = [:]

    /// Maximum auto-fix retry attempts per file per reload cycle.
    private let maxAutoFixAttemptsPerFile = 2

    /// Bytecode cache directory
    private let cacheDir: URL

    public init(engine: Engine, configDir: URL) {
        self.engine = engine
        self.configDir = configDir
        self.backup = ConfigBackup(configDir: configDir)
        self.cacheDir = configDir.appending(path: ".cache")

        // Set the module base dir so ES module imports resolve relative to config
        engine.moduleBaseDir = configDir
    }

    // MARK: - Directory Setup

    /// Create the ~/Library/Application Support/Macotron/ directory structure if it doesn't exist
    public func ensureDirectoryStructure() {
        let fm = FileManager.default
        let dirs = ["snippets", "commands", "plugins", "data", "backups", "logs", ".cache"]
        for dir in dirs {
            let url = configDir.appending(path: dir)
            if !fm.fileExists(atPath: url.path()) {
                try? fm.createDirectory(at: url, withIntermediateDirectories: true)
            }
        }

        // Create starter config.js if it doesn't exist
        let configFile = configDir.appending(path: "config.js")
        if !fm.fileExists(atPath: configFile.path()) {
            let starterConfig = """
            // Macotron configuration
            // API keys are stored in macOS Keychain — use macotron.keychain.get("key-name")

            macotron.config({
                launcher: { hotkey: "cmd+space" },
                modules: {
                    // Module options (all have sensible defaults)
                    // camera:   { pollInterval: 5000 },
                    // shell:    { timeout: 30000 },
                    // keyboard: { swallowMatched: true },
                },
                security: {
                    shell: {
                        allow: [],
                        strict: false,
                    }
                }
            });
            """
            try? starterConfig.write(to: configFile, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Reload

    /// Full reload: backup, clear state, re-execute everything from disk
    public func reloadAll() {
        logger.info("Reloading all snippets...")

        // Clear per-file auto-fix attempt counts for this reload cycle
        autoFixAttempts.removeAll()

        // Reset engine (clears timers, events, commands, JS context)
        engine.reset()

        // Load runtime JS first (adds macotron.config, macotron.on, console, etc.)
        if let runtimeURL = Bundle.main.url(forResource: "macotron-runtime", withExtension: "js") {
            if let runtimeJS = try? String(contentsOf: runtimeURL, encoding: .utf8) {
                engine.evaluate(runtimeJS, filename: "macotron-runtime.js")
            }
        }

        // Load config.js (calls macotron.config() to populate configStore)
        let configFile = configDir.appending(path: "config.js")
        if FileManager.default.fileExists(atPath: configFile.path()) {
            executeFile(configFile)
        }

        // Re-register modules with config options now that config is loaded
        engine.registerAllModules()

        // Load snippets in alphabetical order
        let snippetFiles = listJSFiles(in: configDir.appending(path: "snippets"))
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        for file in snippetFiles {
            executeFile(file)
        }

        // Load commands
        let commandFiles = listJSFiles(in: configDir.appending(path: "commands"))
        for file in commandFiles {
            executeFile(file)
        }

        logger.info("Loaded \(snippetFiles.count) snippets, \(commandFiles.count) commands. Ready.")
    }

    /// Execute a single JS file with error isolation and bytecode caching.
    /// If execution fails and an `autoFixHandler` is set, attempts to auto-fix
    /// the snippet (up to `maxAutoFixAttemptsPerFile` times per reload cycle).
    private func executeFile(_ file: URL) {
        guard let source = try? String(contentsOf: file, encoding: .utf8) else {
            logger.error("Could not read file: \(file.lastPathComponent)")
            return
        }

        let filename = file.lastPathComponent
        let cachePath = cacheDir.appending(path: filename + ".bc")

        // Try bytecode cache (skip if source is newer)
        if let cacheData = try? Data(contentsOf: cachePath),
           let cacheDate = try? FileManager.default.attributesOfItem(atPath: cachePath.path())[.modificationDate] as? Date,
           let sourceDate = try? FileManager.default.attributesOfItem(atPath: file.path())[.modificationDate] as? Date,
           cacheDate >= sourceDate {
            let (_, error) = engine.evaluateBytecode(cacheData, filename: filename)
            if let error {
                logger.error("\(filename) (cached): \(error)")
                // Cache might be stale, fall through to source evaluation
            } else {
                return
            }
        }

        // Evaluate from source
        let fullPath = file.path()
        let (_, error) = engine.evaluate(source, filename: fullPath)
        if let error {
            logger.error("\(filename): \(error)")
            scheduleAutoFix(file: file, source: source, error: error)
        } else {
            // Cache the bytecode for next time
            if let bytecode = engine.compileToBytecode(source, filename: fullPath) {
                try? bytecode.write(to: cachePath)
            }
        }
    }

    /// Schedule an async auto-fix attempt for a failed snippet.
    /// Respects the per-file attempt limit and writes the fix back to disk if successful.
    private func scheduleAutoFix(file: URL, source: String, error: String) {
        let filename = file.lastPathComponent

        guard let handler = autoFixHandler else { return }

        let attempts = autoFixAttempts[filename, default: 0]
        guard attempts < maxAutoFixAttemptsPerFile else {
            logger.warning("Auto-fix: exhausted \(self.maxAutoFixAttemptsPerFile) attempts for \(filename)")
            return
        }
        autoFixAttempts[filename] = attempts + 1

        // Auto-fix is async (calls the AI), so we fire a detached task that hops back
        // to MainActor when it needs to write and re-execute.
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let fixedSource = await handler(filename, source, error) else {
                logger.info("Auto-fix: no fix returned for \(filename)")
                return
            }

            // Write the fixed code (triggers backup)
            guard self.writeSnippet(
                filename: filename,
                content: fixedSource,
                directory: file.deletingLastPathComponent().lastPathComponent
            ) else {
                logger.error("Auto-fix: failed to write fixed code for \(filename)")
                return
            }

            // Re-execute the fixed snippet
            let (_, retryError) = self.engine.evaluate(fixedSource, filename: filename)
            if let retryError {
                logger.warning("Auto-fix: fixed \(filename) still has errors: \(retryError)")
                // Will not recurse — this is a direct evaluate, not executeFile
            } else {
                logger.info("Auto-fix: successfully repaired \(filename)")
            }
        }
    }

    /// List .js files in a directory
    private func listJSFiles(in dir: URL) -> [URL] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ) else { return [] }
        return files.filter { $0.pathExtension == "js" }
    }

    // MARK: - File Operations (with backup)

    /// Write a snippet file, creating a backup first
    public func writeSnippet(filename: String, content: String, directory: String = "snippets") -> Bool {
        backup.createBackup()
        let file = configDir.appending(path: directory).appending(path: filename)
        do {
            try content.write(to: file, atomically: true, encoding: .utf8)
            logger.info("Wrote \(directory)/\(filename)")
            return true
        } catch {
            logger.error("Failed to write \(filename): \(error)")
            return false
        }
    }

    /// Delete a snippet file, creating a backup first
    public func deleteSnippet(filename: String, directory: String = "snippets") -> Bool {
        backup.createBackup()
        let file = configDir.appending(path: directory).appending(path: filename)
        do {
            try FileManager.default.removeItem(at: file)
            logger.info("Deleted \(directory)/\(filename)")
            return true
        } catch {
            logger.error("Failed to delete \(filename): \(error)")
            return false
        }
    }

    /// List all snippet files with their first comment line as description
    public func listSnippets(directory: String = "snippets") -> [(filename: String, description: String)] {
        let files = listJSFiles(in: configDir.appending(path: directory))
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        return files.map { file in
            let desc: String
            if let source = try? String(contentsOf: file, encoding: .utf8) {
                // Extract first comment as description
                let lines = source.components(separatedBy: .newlines)
                let commentLine = lines.first { $0.hasPrefix("//") }
                desc = commentLine?.trimmingCharacters(in: .whitespaces)
                    .dropFirst(2).trimmingCharacters(in: .whitespaces) ?? ""
            } else {
                desc = ""
            }
            return (filename: file.lastPathComponent, description: String(desc))
        }
    }

    // MARK: - File Watching

    /// Watch ~/Library/Application Support/Macotron/ for changes, auto-reload
    public func startWatching() {
        let path = configDir.path()

        var context = FSEventStreamContext()
        let opaque = Unmanaged.passUnretained(self).toOpaque()
        context.info = opaque

        let pathCF = path as CFString
        let paths = [pathCF] as CFArray

        fsEventStream = FSEventStreamCreate(
            nil,
            { _, info, numEvents, eventPaths, _, _ in
                guard let info else { return }
                let manager = Unmanaged<SnippetManager>.fromOpaque(info).takeUnretainedValue()
                // Debounce reload
                manager.reloadDebounceTask?.cancel()
                manager.reloadDebounceTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    manager.reloadAll()
                }
            },
            &context,
            paths,
            UInt64(kFSEventStreamEventIdSinceNow),
            0.5,
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        )

        guard let stream = fsEventStream else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        logger.info("Watching \(path) for changes")
    }

    /// Stop watching for file changes
    public func stopWatching() {
        if let stream = fsEventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            fsEventStream = nil
        }
    }
}
