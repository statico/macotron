// SnippetManager.swift — Load, watch, execute plugins from the PluginWorkspace
import CQuickJS
import Foundation
import os

private let logger = Logger(subsystem: "io.statico.macotron", category: "modules")

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

    /// Plugin filenames whose on-disk bytes are not the last approved hash.
    public private(set) var pendingReview: Set<String> = []

    /// When true, disk changes reload immediately with no hash gate.
    public var hotReload = false {
        didSet { engine.bypassImportTrust = hotReload }
    }

    /// Called after every reload, so the app can re-check plugin declarations.
    public var onDidReload: (() -> Void)?

    /// Called when pendingReview changes without a full reload.
    public var onPendingReviewChange: (() -> Void)?

    private let cacheDir: URL

    public init(engine: Engine, workspace: PluginWorkspace) {
        self.engine = engine
        self.workspace = workspace
        self.configDir = workspace.root
        self.backup = ConfigBackup(configDir: workspace.root)
        self.cacheDir = workspace.cacheDir
        engine.moduleBaseDir = workspace.root
        PluginTrust.grandfatherIfEmpty(pluginsDir: workspace.pluginsDir)
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

    /// Store a password option: secret goes to the Keychain, settings.json gets the ref.
    public func saveModuleSecret(filename: String, key: String, secret: String) {
        let account = KeychainStore.pluginOptionAccount(filename: filename, key: key)
        KeychainStore.write(account: account, value: secret)
        saveModuleOption(filename: filename, key: key, value: account)
    }

    /// Clear a password option: delete the Keychain item and remove the JSON ref.
    public func clearModuleSecret(filename: String, key: String) {
        var settings = loadModuleSettings()
        var fileSettings = settings[filename] ?? [:]
        // Delete whatever ref is stored — it may differ from the computed account
        // if the plugin file was renamed since the secret was set.
        if let ref = fileSettings[key] as? String, !ref.isEmpty {
            KeychainStore.delete(account: ref)
        }
        fileSettings.removeValue(forKey: key)
        settings[filename] = fileSettings
        saveModuleSettings(settings)
    }

    /// Filenames the user disabled in Settings. Disabled plugins stay on disk
    /// but are never evaluated.
    public func disabledPlugins() -> Set<String> {
        Set(workspace.readSettings()["disabledPlugins"] as? [String] ?? [])
    }

    public func setModuleEnabled(filename: String, enabled: Bool) {
        do {
            try workspace.updateSettings { settings in
                var disabled = settings["disabledPlugins"] as? [String] ?? []
                if enabled {
                    disabled.removeAll { $0 == filename }
                } else if !disabled.contains(filename) {
                    disabled.append(filename)
                }
                settings["disabledPlugins"] = disabled
            }
        } catch {
            logger.error("Failed to save disabledPlugins: \(error)")
        }
    }

    // MARK: - Reload

    public func reloadAll() {
        logger.info("Reloading all plugins...")
        lastReloadErrors.removeAll()

        engine.reset()
        engine.moduleSettings = loadModuleSettings()

        // Map settings.json into configStore (replaces config.js + macotron.config())
        engine.configStore = workspace.readSettings()

        engine.registerAllModules()

        // Evaluate the runtime after the final registerAllModules: registration
        // replaces the global macotron object, so helpers must land on it last.
        if let runtimeURL = Bundle.main.url(forResource: "macotron-runtime", withExtension: "js"),
           let runtimeJS = try? String(contentsOf: runtimeURL, encoding: .utf8) {
            engine.evaluate(runtimeJS, filename: "macotron-runtime.js")
        }

        let disabled = disabledPlugins()
        let pluginFiles = listJSFiles(in: workspace.pluginsDir)
            .filter { !disabled.contains($0.lastPathComponent) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        pendingReview.removeAll()
        for file in pluginFiles {
            executeFile(file)
        }

        engine.notifyModulesDidReload()
        logger.info("Loaded \(pluginFiles.count) plugins. Ready.")
        onDidReload?()
        onPendingReviewChange?()
    }

    private func executeFile(_ file: URL) {
        guard let source = try? String(contentsOf: file, encoding: .utf8) else {
            logger.error("Could not read file: \(file.lastPathComponent)")
            return
        }

        let filename = file.lastPathComponent
        if !hotReload, !PluginTrust.matches(filename: filename, source: source) {
            pendingReview.insert(filename)
            logger.error("\(filename): on-disk source is not approved")
            return
        }
        pendingReview.remove(filename)

        // Cache name embeds the source hash: any planted or stale bytecode
        // whose name doesn't match the current source is never read.
        let sourceHash = PluginHash.sha256(source: source)
        let cachePath = cacheDir.appending(path: "\(filename).\(sourceHash).iife.bc")

        switch PluginNeeds.parse(source) {
        case .failure(let error):
            logger.error("\(filename): \(error.message)")
            lastReloadErrors.append((filename: filename, error: error.message))
            return
        case .success(let needs):
            let host = SemVer(Engine.apiVersion) ?? SemVer(major: 1, minor: 0, patch: 0)
            if needs > host {
                let message = PluginNeeds.unmetMessage(needs: needs, host: host)
                logger.error("\(filename): \(message)")
                lastReloadErrors.append((filename: filename, error: message))
                return
            }
        }

        engine.currentEvaluatingFile = filename
        defer { engine.currentEvaluatingFile = nil }

        let isolated = Engine.isolatedPlugin(source)
        if let cacheData = try? Data(contentsOf: cachePath) {
            let (_, error) = engine.evaluateBytecode(cacheData, filename: filename)
            if error == nil { return }
            logger.error("\(filename) (cached): \(error ?? "")")
        }

        let fullPath = file.path(percentEncoded: false)
        let (_, error) = engine.evaluate(isolated, filename: fullPath)
        if let error {
            logger.error("\(filename): \(error)")
            lastReloadErrors.append((filename: filename, error: error))
        } else if let bytecode = engine.compileToBytecode(isolated, filename: fullPath) {
            deleteStaleCaches(filename: filename, keeping: cachePath.lastPathComponent)
            try? bytecode.write(to: cachePath)
        }
    }

    private func deleteStaleCaches(filename: String, keeping: String) {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: cacheDir, includingPropertiesForKeys: nil
        )) ?? []
        for file in files {
            let name = file.lastPathComponent
            if name.hasPrefix(filename + "."), name.hasSuffix(".iife.bc"), name != keeping {
                try? FileManager.default.removeItem(at: file)
            }
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
    public func deleteModule(filename: String, directory: String = "plugins") -> Bool {
        backup.createBackup()
        let file = configDir.appending(path: directory).appending(path: filename)
        do {
            try FileManager.default.removeItem(at: file)
            if directory == "plugins" {
                setModuleEnabled(filename: filename, enabled: true)
            }
            return true
        } catch {
            logger.error("Failed to delete \(filename): \(error)")
            return false
        }
    }

    public func listModules(directory: String = "plugins") -> [(filename: String, description: String)] {
        listJSFiles(in: configDir.appending(path: directory))
            .map { (filename: $0.lastPathComponent, description: "") }
            .sorted { $0.filename < $1.filename }
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
                let paths: [String]
                if let array = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] {
                    paths = array
                } else {
                    paths = []
                }
                manager.reloadDebounceTask?.cancel()
                manager.reloadDebounceTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    manager.handleDiskChange(paths)
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

    public func handleDiskChange(_ paths: [String]) {
        if hotReload {
            reloadAll()
            return
        }
        let pluginChanges = paths.filter {
            $0.hasSuffix(".js") && $0.contains("/plugins/")
        }
        if !pluginChanges.isEmpty {
            var added = false
            for path in pluginChanges {
                let url = URL(fileURLWithPath: path)
                let name = url.lastPathComponent
                guard let source = try? String(contentsOf: url, encoding: .utf8),
                      !PluginTrust.matches(filename: name, source: source) else { continue }
                if pendingReview.insert(name).inserted { added = true }
            }
            if added { onPendingReviewChange?() }
        }
        let settingsChanged = paths.contains { $0.hasSuffix("settings.json") }
        if settingsChanged {
            engine.configStore = workspace.readSettings()
            onDidReload?()
        }
        if pluginChanges.isEmpty, !settingsChanged, !paths.isEmpty {
            reloadAll()
        }
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
