// SnippetManager.swift — Load, watch, execute snippets from ~/.macotron/
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

    public init(engine: Engine, configDir: URL) {
        self.engine = engine
        self.configDir = configDir
        self.backup = ConfigBackup(configDir: configDir)
    }

    // MARK: - Directory Setup

    /// Create the ~/.macotron/ directory structure if it doesn't exist
    public func ensureDirectoryStructure() {
        let fm = FileManager.default
        let dirs = ["snippets", "commands", "plugins", "data", "backups", "logs"]
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

        // Reset engine (clears timers, events, commands, JS context)
        engine.reset()

        // Load config.js first
        let configFile = configDir.appending(path: "config.js")
        if FileManager.default.fileExists(atPath: configFile.path()) {
            executeFile(configFile)
        }

        // Load runtime JS
        if let runtimeURL = Bundle.main.url(forResource: "macotron-runtime", withExtension: "js") {
            if let runtimeJS = try? String(contentsOf: runtimeURL, encoding: .utf8) {
                engine.evaluate(runtimeJS, filename: "macotron-runtime.js")
            }
        }

        // Re-register modules with config options
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

    /// Execute a single JS file with error isolation
    private func executeFile(_ file: URL) {
        guard let source = try? String(contentsOf: file, encoding: .utf8) else {
            logger.error("Could not read file: \(file.lastPathComponent)")
            return
        }

        let (_, error) = engine.evaluate(source, filename: file.lastPathComponent)
        if let error {
            logger.error("\(file.lastPathComponent): \(error)")
            // Auto-fix could be triggered here (Phase 3)
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

    /// Watch ~/.macotron/ for changes, auto-reload
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
        FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
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
