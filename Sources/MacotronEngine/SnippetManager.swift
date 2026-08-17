// SnippetManager.swift — Load, watch, execute plugins from the PluginWorkspace
import CQuickJS
import Foundation
import os

private let logger = Logger(subsystem: "com.macotron", category: "modules")

@MainActor
public final class ModuleManager {
    public let engine: Engine
    public let configDir: URL
    public let workspace: PluginWorkspace
    public let backup: ConfigBackup

    private var fsEventStream: FSEventStreamRef?
    private var reloadDebounceTask: Task<Void, Never>?

    /// Errors encountered during the last reload cycle.
    public private(set) var lastReloadErrors: [(filename: String, error: String)] = []

    private let cacheDir: URL

    public init(engine: Engine, workspace: PluginWorkspace) {
        self.engine = engine
        self.workspace = workspace
        self.configDir = workspace.root
        self.backup = ConfigBackup(configDir: workspace.root)
        self.cacheDir = workspace.cacheDir
        engine.moduleBaseDir = workspace.root
    }

    /// Convenience: create workspace from URL and ensure layout.
    public convenience init(engine: Engine, configDir: URL) {
        let ws = PluginWorkspace(root: configDir)
        try? ws.ensureReady()
        self.init(engine: engine, workspace: ws)
    }

    // MARK: - Directory Setup

    public func ensureDirectoryStructure() {
        do {
            try workspace.ensureReady()
        } catch {
            logger.error("Failed to ensure plugin workspace: \(error)")
        }
    }

    // MARK: - Settings

    /// Per-plugin option overrides from settings.json `pluginSettings`.
    public func loadModuleSettings() -> [String: [String: Any]] {
        let settings = workspace.readSettings()
        return settings["pluginSettings"] as? [String: [String: Any]] ?? [:]
    }

    public func saveModuleSettings(_ moduleSettings: [String: [String: Any]]) {
        do {
            try workspace.updateSettings { settings in
                settings["pluginSettings"] = moduleSettings
            }
            logger.info("Saved plugin settings")
        } catch {
            logger.error("Failed to save plugin settings: \(error)")
        }
    }

    public func saveModuleOption(filename: String, key: String, value: Any) {
        var settings = loadModuleSettings()
        var fileSettings = settings[filename] ?? [:]
        fileSettings[key] = value
        settings[filename] = fileSettings
        saveModuleSettings(settings)
    }

    // MARK: - Reload

    public func reloadAll() {
        logger.info("Reloading all plugins...")
        lastReloadErrors.removeAll()

        engine.reset()
        engine.moduleSettings = loadModuleSettings()

        if let runtimeURL = Bundle.main.url(forResource: "macotron-runtime", withExtension: "js"),
           let runtimeJS = try? String(contentsOf: runtimeURL, encoding: .utf8) {
            engine.evaluate(runtimeJS, filename: "macotron-runtime.js")
        }

        // Map settings.json into configStore (replaces config.js + macotron.config())
        engine.configStore = workspace.readSettings()

        engine.registerAllModules()

        let pluginFiles = listJSFiles(in: workspace.pluginsDir)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        for file in pluginFiles {
            executeFile(file)
        }

        logger.info("Loaded \(pluginFiles.count) plugins. Ready.")
    }

    private func executeFile(_ file: URL) {
        guard let source = try? String(contentsOf: file, encoding: .utf8) else {
            logger.error("Could not read file: \(file.lastPathComponent)")
            return
        }

        let filename = file.lastPathComponent
        let cachePath = cacheDir.appending(path: filename + ".bc")

        engine.currentEvaluatingFile = filename
        defer { engine.currentEvaluatingFile = nil }

        if let cacheData = try? Data(contentsOf: cachePath),
           let cacheDate = try? FileManager.default.attributesOfItem(
               atPath: cachePath.path(percentEncoded: false)
           )[.modificationDate] as? Date,
           let sourceDate = try? FileManager.default.attributesOfItem(
               atPath: file.path(percentEncoded: false)
           )[.modificationDate] as? Date,
           cacheDate >= sourceDate {
            let (_, error) = engine.evaluateBytecode(cacheData, filename: filename)
            if error == nil { return }
            logger.error("\(filename) (cached): \(error ?? "")")
        }

        let fullPath = file.path(percentEncoded: false)
        let (_, error) = engine.evaluate(source, filename: fullPath)
        if let error {
            logger.error("\(filename): \(error)")
            lastReloadErrors.append((filename: filename, error: error))
        } else if let bytecode = engine.compileToBytecode(source, filename: fullPath) {
            try? bytecode.write(to: cachePath)
        }
    }

    private func listJSFiles(in dir: URL) -> [URL] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ) else { return [] }
        return files.filter { $0.pathExtension == "js" }
    }

    // MARK: - File Operations

    @discardableResult
    public func writeModule(filename: String, content: String, directory: String = "plugins") -> Bool {
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

    @discardableResult
    public func deleteModule(filename: String, directory: String = "plugins") -> Bool {
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

    public func listModules(directory: String = "plugins") -> [(filename: String, description: String)] {
        let files = listJSFiles(in: configDir.appending(path: directory))
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        return files.map { file in
            let desc: String
            if let source = try? String(contentsOf: file, encoding: .utf8) {
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

    public func startWatching() {
        let path = configDir.path(percentEncoded: false)

        var context = FSEventStreamContext()
        let opaque = Unmanaged.passUnretained(self).toOpaque()
        context.info = opaque

        let pathCF = path as CFString
        let paths = [pathCF] as CFArray

        fsEventStream = FSEventStreamCreate(
            nil,
            { _, info, numEvents, eventPaths, _, _ in
                guard let info else { return }
                let manager = Unmanaged<ModuleManager>.fromOpaque(info).takeUnretainedValue()
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

    public func stopWatching() {
        if let stream = fsEventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            fsEventStream = nil
        }
    }
}
