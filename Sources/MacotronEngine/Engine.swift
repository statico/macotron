// Engine.swift — QuickJS runtime lifecycle, timers, module registration
import CQuickJS
import Foundation
import os

private let logger = Logger(subsystem: "io.statico.macotron", category: "engine")

public struct RegisteredCommand {
    public let id: String
    public let name: String
    public let description: String
    public let pluginFile: String
    public let arguments: [CommandArgumentSpec]
    public var callback: JSValue
}

public struct RegisteredHotkey {
    public let id: String
    public let pluginFile: String
    public let key: String
    public let defaultCombo: String

    public init(id: String, pluginFile: String, key: String, defaultCombo: String) {
        self.id = id
        self.pluginFile = pluginFile
        self.key = key
        self.defaultCombo = defaultCombo
    }
}

@MainActor
public final class Engine {
    /// Semver of the plugin-facing JS API (`macotron.version.api`).
    nonisolated public static let apiVersion = "1.1.0"

    public private(set) var runtime: OpaquePointer!
    public private(set) var context: OpaquePointer!
    public let eventBus = EventBus()

    private var modules: [NativeModule] = []
    private var timers: [UInt32: DispatchSourceTimer] = [:]
    private var nextTimerID: UInt32 = 1
    private var interruptDeadline: Date?

    /// Registered commands keyed by stable id
    public var commandRegistry: [String: RegisteredCommand] = [:]

    /// Plugin hotkeys from `keyboard.on(id, default, callback)`, keyed by `{plugin}/{id}`.
    public var hotkeyRegistry: [String: RegisteredHotkey] = [:]

    /// Config store (populated by macotron.config() calls)
    public var configStore: [String: Any] = [:]

    /// Permission names declared by plugins via `macotron.plugin({ permissions })`.
    /// Cleared on every reload.
    public var declaredPermissions: Set<String> = []

    /// Plugin metadata (populated by macotron.plugin() calls during execution).
    /// Keyed by filename → raw metadata dict from JS.
    public var moduleMetadata: [String: [String: Any]] = [:]

    /// Event names registered via `macotron.on`, keyed by plugin filename.
    public var pluginEvents: [String: [String]] = [:]

    /// Latest `macotron.checks()` rows, keyed by plugin filename.
    public var pluginChecks: [String: [PluginCheck]] = [:]

    /// Fired after `pluginChecks` actually change (not on a no-op replace).
    public var onPluginChecksChanged: (() -> Void)?

    /// Open Settings → Plugins on the calling plugin.
    public var onOpenPluginSettings: ((String) -> Void)?

    /// User overrides for module options, loaded from module-settings.json.
    /// Keyed by filename → option key → value.
    public var moduleSettings: [String: [String: Any]] = [:]

    /// The file currently being evaluated (set by ModuleManager during executeFile).
    public var currentEvaluatingFile: String?

    /// Log output handler
    public var logHandler: ((String) -> Void)?

    /// When true, modules stub side effects (hotkeys, panels, notifications).
    public var dryRun = false

    /// Base directory for resolving ES module imports (set by ModuleManager)
    public var moduleBaseDir: URL?

    public init() {
        runtime = JS_NewRuntime()
        context = JS_NewContext(runtime)
        setupInterruptHandler()
        setupModuleLoader()
        setupTimerGlobals()
        setupCoreGlobals()
    }

    // MARK: - ES Module Loader

    private func setupModuleLoader() {
        let opaque = Unmanaged.passUnretained(self).toOpaque()

        JS_SetModuleLoaderFunc(
            runtime,
            // Normalize: resolve module name relative to base
            { ctx, baseName, moduleName, opaque -> UnsafeMutablePointer<CChar>? in
                guard let moduleName else { return nil }
                let name = String(cString: moduleName)

                // Absolute paths pass through
                if name.hasPrefix("/") {
                    return strdup(moduleName)
                }

                // Resolve relative paths against the importing module's directory
                if name.hasPrefix("."), let baseName {
                    let base = String(cString: baseName)
                    let baseURL = URL(fileURLWithPath: base).deletingLastPathComponent()
                    var resolved = baseURL.appending(path: name).path()
                    if !resolved.hasSuffix(".js") { resolved += ".js" }
                    return strdup(resolved)
                }

                // Non-relative names: resolve against moduleBaseDir
                if let opaque {
                    let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()
                    if let baseDir = engine.moduleBaseDir {
                        var resolved = baseDir.appending(path: name).path()
                        if !resolved.hasSuffix(".js") { resolved += ".js" }
                        return strdup(resolved)
                    }
                }

                return strdup(moduleName)
            },
            // Loader: read file and compile as ES module
            { ctx, moduleName, opaque -> OpaquePointer? in
                guard let ctx, let moduleName else { return nil }
                let filePath = String(cString: moduleName)

                guard let source = try? String(contentsOfFile: filePath, encoding: .utf8) else {
                    logger.error("ES module not found: \(filePath)")
                    return nil
                }

                return source.withCString { cStr in
                    QJS_CompileModule(ctx, cStr, source.utf8.count, filePath)
                }
            },
            opaque
        )
    }

    // MARK: - Interrupt Handler

    private func setupInterruptHandler() {
        let opaque = Unmanaged.passUnretained(self).toOpaque()
        JS_SetInterruptHandler(runtime, { _, opaque -> Int32 in
            guard let opaque else { return 0 }
            let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()
            if let deadline = engine.interruptDeadline, Date() > deadline {
                return 1
            }
            return 0
        }, opaque)
    }

    // MARK: - Timer Globals

    private func setupTimerGlobals() {
        let global = JS_GetGlobalObject(context)
        let opaque = Unmanaged.passUnretained(self).toOpaque()

        // Store engine pointer on the context for C callbacks to retrieve
        JS_SetContextOpaque(context, opaque)

        // setTimeout
        JS_SetPropertyStr(context, global, "setTimeout",
            JS_NewCFunction(context, { ctx, thisVal, argc, argv -> JSValue in
                guard let ctx, let argv, argc >= 1 else { return QJS_Undefined() }
                let opaque = JS_GetContextOpaque(ctx)
                guard let opaque else { return QJS_Undefined() }
                let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()
                let callback = argv[0]
                var ms: Int32 = 0
                if argc > 1 { JS_ToInt32(ctx, &ms, argv[1]) }
                let id = engine.scheduleTimer(callback: callback, ms: ms, repeats: false)
                return JS_NewInt32(ctx, Int32(id))
            }, "setTimeout", 2))

        // setInterval
        JS_SetPropertyStr(context, global, "setInterval",
            JS_NewCFunction(context, { ctx, thisVal, argc, argv -> JSValue in
                guard let ctx, let argv, argc >= 2 else { return QJS_Undefined() }
                let opaque = JS_GetContextOpaque(ctx)
                guard let opaque else { return QJS_Undefined() }
                let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()
                let callback = argv[0]
                var ms: Int32 = 0
                JS_ToInt32(ctx, &ms, argv[1])
                let id = engine.scheduleTimer(callback: callback, ms: ms, repeats: true)
                return JS_NewInt32(ctx, Int32(id))
            }, "setInterval", 2))

        // clearTimeout / clearInterval (same function)
        let clearTimerFn = JS_NewCFunction(context, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 1 else { return QJS_Undefined() }
            let opaque = JS_GetContextOpaque(ctx)
            guard let opaque else { return QJS_Undefined() }
            let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()
            var id: Int32 = 0
            JS_ToInt32(ctx, &id, argv[0])
            engine.cancelTimer(UInt32(id))
            return QJS_Undefined()
        }, "clearTimeout", 1)
        JS_SetPropertyStr(context, global, "clearTimeout", clearTimerFn)
        JS_SetPropertyStr(context, global, "clearInterval", JS_DupValue(context, clearTimerFn))

        JS_FreeValue(context, global)
    }

    // MARK: - Core Globals

    private func setupCoreGlobals() {
        let global = JS_GetGlobalObject(context)

        // $$__log — called by macotron.log / console.log
        JS_SetPropertyStr(context, global, "$$__log",
            JS_NewCFunction(context, { ctx, thisVal, argc, argv -> JSValue in
                guard let ctx, let argv, argc >= 1 else { return QJS_Undefined() }
                let msg = JSBridge.toString(ctx, argv[0]) ?? ""
                let opaque = JS_GetContextOpaque(ctx)
                if let opaque {
                    let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()
                    engine.logHandler?(msg)
                }
                logger.info("\(msg, privacy: .public)")
                return QJS_Undefined()
            }, "$$__log", 1))

        // $$__on — event bus subscribe
        JS_SetPropertyStr(context, global, "$$__on",
            JS_NewCFunction(context, { ctx, thisVal, argc, argv -> JSValue in
                guard let ctx, let argv, argc >= 2 else { return QJS_Undefined() }
                let event = JSBridge.toString(ctx, argv[0]) ?? ""
                let opaque = JS_GetContextOpaque(ctx)
                if let opaque {
                    let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()
                    engine.eventBus.on(event, callback: argv[1], ctx: ctx)
                    engine.recordPluginEvent(event)
                }
                return QJS_Undefined()
            }, "$$__on", 2))

        // $$__off — event bus unsubscribe
        JS_SetPropertyStr(context, global, "$$__off",
            JS_NewCFunction(context, { ctx, thisVal, argc, argv -> JSValue in
                guard let ctx, let argv, argc >= 2 else { return QJS_Undefined() }
                let event = JSBridge.toString(ctx, argv[0]) ?? ""
                let opaque = JS_GetContextOpaque(ctx)
                if let opaque {
                    let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()
                    engine.eventBus.off(event, callback: argv[1], ctx: ctx)
                }
                return QJS_Undefined()
            }, "$$__off", 2))

        // $$__registerCommand — command registration
        JS_SetPropertyStr(context, global, "$$__registerCommand",
            JS_NewCFunction(context, { ctx, thisVal, argc, argv -> JSValue in
                guard let ctx, let argv, argc >= 3 else { return QJS_Undefined() }
                let name = JSBridge.toString(ctx, argv[0]) ?? ""
                let desc = JSBridge.toString(ctx, argv[1]) ?? ""
                let opaque = JS_GetContextOpaque(ctx)
                guard let opaque else { return QJS_Undefined() }
                let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()
                let callback = JS_DupValue(ctx, argv[2])

                var opts: [String: Any] = [:]
                if argc >= 4, !JSBridge.isUndefined(argv[3]), !JSBridge.isNull(argv[3]) {
                    opts = JSBridge.jsToSwift(ctx, argv[3]) as? [String: Any] ?? [:]
                }

                let pluginFile = engine.currentEvaluatingFile ?? ""
                var commandID = pluginFile.isEmpty ? name : "\(pluginFile)/\(name)"
                if let explicit = opts["id"] as? String, !explicit.isEmpty {
                    commandID = explicit
                }
                let arguments = CommandArgumentSpec.parseList(opts["arguments"])

                if engine.commandRegistry[commandID] != nil {
                    NSLog("[Macotron] command id '%@' overwritten", commandID)
                }

                engine.commandRegistry[commandID] = RegisteredCommand(
                    id: commandID,
                    name: name,
                    description: desc,
                    pluginFile: pluginFile,
                    arguments: arguments,
                    callback: callback
                )
                return QJS_Undefined()
            }, "$$__registerCommand", 4))

        // $$__requirePermissions — called by macotron.requirePermissions()
        JS_SetPropertyStr(context, global, "$$__requirePermissions",
            JS_NewCFunction(context, { ctx, thisVal, argc, argv -> JSValue in
                guard let ctx, let argv, argc >= 1 else { return QJS_Undefined() }
                let opaque = JS_GetContextOpaque(ctx)
                guard let opaque else { return QJS_Undefined() }
                let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()

                engine.addDeclaredPermissions(JSBridge.jsToSwift(ctx, argv[0]))
                return QJS_Undefined()
            }, "$$__requirePermissions", 1))

        // $$__config — called by macotron.config() to store user options
        JS_SetPropertyStr(context, global, "$$__config",
            JS_NewCFunction(context, { ctx, thisVal, argc, argv -> JSValue in
                guard let ctx, let argv, argc >= 1 else { return QJS_Undefined() }
                let opaque = JS_GetContextOpaque(ctx)
                guard let opaque else { return QJS_Undefined() }
                let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()

                // Parse the JS object into configStore
                let opts = argv[0]
                engine.configStore = JSBridge.jsToSwift(ctx, opts) as? [String: Any] ?? [:]
                return QJS_Undefined()
            }, "$$__config", 1))

        // $$__module — called by macotron.plugin() to declare metadata & options.
        // Stores metadata, returns resolved options (defaults merged with user overrides).
        JS_SetPropertyStr(context, global, "$$__module",
            JS_NewCFunction(context, { ctx, thisVal, argc, argv -> JSValue in
                guard let ctx, let argv, argc >= 1 else { return QJS_Undefined() }
                let opaque = JS_GetContextOpaque(ctx)
                guard let opaque else { return QJS_Undefined() }
                let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()

                let metadata = JSBridge.jsToSwift(ctx, argv[0]) as? [String: Any] ?? [:]
                let filename = engine.currentEvaluatingFile ?? "<unknown>"

                engine.moduleMetadata[filename] = metadata
                engine.addDeclaredPermissions(metadata["permissions"])

                // Build resolved options: defaults merged with user overrides.
                // Password options store a Keychain account ref in settings.json;
                // the plugin always sees the resolved secret (or ""), never the ref.
                let optionDefs = metadata["options"] as? [String: [String: Any]] ?? [:]
                let userOverrides = engine.moduleSettings[filename] ?? [:]
                var resolved: [String: Any] = [:]
                for (key, def) in optionDefs {
                    let type = def["type"] as? String ?? "string"
                    if type == "password" {
                        if let ref = userOverrides[key] as? String, !ref.isEmpty,
                           let secret = KeychainStore.read(account: ref), !secret.isEmpty {
                            resolved[key] = secret
                        } else {
                            resolved[key] = ""
                        }
                    } else if let userVal = userOverrides[key] {
                        resolved[key] = userVal
                    } else if let defaultVal = def["default"] {
                        resolved[key] = defaultVal
                    }
                }

                return JSBridge.anyToJS(ctx, resolved)
            }, "$$__module", 1))

        JS_SetPropertyStr(context, global, "$$__checks",
            JS_NewCFunction(context, { ctx, thisVal, argc, argv -> JSValue in
                guard let ctx, let argv, argc >= 1 else { return QJS_Undefined() }
                let opaque = JS_GetContextOpaque(ctx)
                guard let opaque else { return QJS_Undefined() }
                let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()
                engine.replaceChecks(JSBridge.jsToSwift(ctx, argv[0]))
                return QJS_Undefined()
            }, "$$__checks", 1))

        JS_SetPropertyStr(context, global, "$$__openSettings",
            JS_NewCFunction(context, { ctx, thisVal, argc, argv -> JSValue in
                guard let ctx else { return QJS_Undefined() }
                let opaque = JS_GetContextOpaque(ctx)
                guard let opaque else { return QJS_Undefined() }
                let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()
                engine.openPluginSettings()
                return QJS_Undefined()
            }, "$$__openSettings", 0))

        JS_FreeValue(context, global)
    }

    func openPluginSettings() {
        guard let file = currentEvaluatingFile, !file.isEmpty else { return }
        let open = onOpenPluginSettings
        DispatchQueue.main.async { open?(file) }
    }

    func recordPluginEvent(_ event: String) {
        guard let file = currentEvaluatingFile, !file.isEmpty, !event.isEmpty else { return }
        var events = pluginEvents[file] ?? []
        if !events.contains(event) {
            events.append(event)
            pluginEvents[file] = events
        }
    }

    func replaceChecks(_ value: Any?) {
        guard let file = currentEvaluatingFile, !file.isEmpty else { return }
        let rows = PluginCheck.parseList(value)
        let next: [PluginCheck]? = rows.isEmpty ? nil : rows
        if pluginChecks[file] == next { return }
        pluginChecks[file] = next
        onPluginChecksChanged?()
    }

    func addDeclaredPermissions(_ value: Any?) {
        if let list = value as? [Any] {
            for item in list {
                if let name = item as? String { declaredPermissions.insert(name) }
            }
        } else if let name = value as? String {
            declaredPermissions.insert(name)
        }
    }

    // MARK: - Timer Management

    private func scheduleTimer(callback: JSValue, ms: Int32, repeats: Bool) -> UInt32 {
        let id = nextTimerID
        nextTimerID += 1
        let protectedCallback = JS_DupValue(context, callback)
        let pluginFile = currentEvaluatingFile

        let timer = DispatchSource.makeTimerSource(queue: .main)
        let interval = DispatchTimeInterval.milliseconds(Int(max(ms, 1)))
        if repeats {
            timer.schedule(deadline: .now() + interval, repeating: interval)
        } else {
            timer.schedule(deadline: .now() + interval)
        }
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.withEvaluatingFile(pluginFile) {
                _ = JS_Call(self.context, protectedCallback, QJS_Undefined(), 0, nil)
                self.drainJobQueue()
            }
            if !repeats {
                JS_FreeValue(self.context, protectedCallback)
                self.cancelTimer(id)
            }
        }
        timers[id] = timer
        timer.resume()
        return id
    }

    public func withEvaluatingFile(_ file: String?, _ body: () -> Void) {
        let previous = currentEvaluatingFile
        if let file, !file.isEmpty {
            currentEvaluatingFile = file
        }
        defer { currentEvaluatingFile = previous }
        body()
    }

    public func cancelTimer(_ id: UInt32) {
        timers[id]?.cancel()
        timers.removeValue(forKey: id)
    }

    public func cancelAllTimers() {
        for (_, timer) in timers {
            timer.cancel()
        }
        timers.removeAll()
    }

    // MARK: - Job Queue

    /// Drain the QuickJS microtask/Promise queue
    public func drainJobQueue() {
        var ctx: OpaquePointer?
        while true {
            let ret = JS_ExecutePendingJob(runtime, &ctx)
            if ret <= 0 { break }
        }
    }

    // MARK: - Evaluate

    /// Plugins share one context; wrap so `const opts` in two files does not collide.
    public static func isolatedPlugin(_ source: String) -> String {
        "(function(){\n\(source)\n})();"
    }

    /// Evaluate JS code, auto-detecting ES modules. Returns (result, error).
    @discardableResult
    public func evaluate(_ js: String, filename: String = "<eval>") -> (String?, String?) {
        // Set a 5-second interrupt deadline for user code
        interruptDeadline = Date().addingTimeInterval(5)
        defer { interruptDeadline = nil }

        let result = js.withCString { cStr in
            QJS_EvalAutoDetect(context, cStr, js.utf8.count, filename)
        }
        drainJobQueue()

        if JS_IsException(result) {
            let errStr = JSBridge.getExceptionString(context)
            logger.error("JS error in \(filename): \(errStr)")
            return (nil, errStr)
        }

        let str = JS_ToCString(context, result)
        let output = str != nil ? String(cString: str!) : nil
        if let str { JS_FreeCString(context, str) }
        JS_FreeValue(context, result)
        return (output, nil)
    }

    @discardableResult
    public func invokeCommand(_ id: String, args: [String: Any] = [:]) -> Bool {
        guard let cmd = commandRegistry[id] else { return false }
        withEvaluatingFile(cmd.pluginFile) {
            var arg = JSBridge.newObject(context, args)
            let result = JS_Call(context, cmd.callback, QJS_Undefined(), 1, &arg)
            JS_FreeValue(context, arg)
            if JS_IsException(result) {
                let errStr = JSBridge.getExceptionString(context)
                logger.error("Command \(id): \(errStr, privacy: .public)")
            } else {
                JS_FreeValue(context, result)
            }
            drainJobQueue()
        }
        return true
    }

    /// Compile JS source to bytecode for caching.
    public func compileToBytecode(_ js: String, filename: String) -> Data? {
        var outLen: Int = 0
        let buf = js.withCString { cStr in
            QJS_CompileToBytecode(context, cStr, js.utf8.count, filename, &outLen)
        }
        guard let buf, outLen > 0 else { return nil }
        let data = Data(bytes: buf, count: outLen)
        js_free(context, buf)
        return data
    }

    /// Evaluate cached bytecode. Returns (result, error).
    @discardableResult
    public func evaluateBytecode(_ data: Data, filename: String = "<bytecode>") -> (String?, String?) {
        interruptDeadline = Date().addingTimeInterval(5)
        defer { interruptDeadline = nil }

        let result = data.withUnsafeBytes { rawBuf in
            QJS_EvalBytecode(context, rawBuf.baseAddress!.assumingMemoryBound(to: UInt8.self), data.count)
        }
        drainJobQueue()

        if JS_IsException(result) {
            let errStr = JSBridge.getExceptionString(context)
            logger.error("Bytecode error in \(filename): \(errStr)")
            return (nil, errStr)
        }

        let str = JS_ToCString(context, result)
        let output = str != nil ? String(cString: str!) : nil
        if let str { JS_FreeCString(context, str) }
        JS_FreeValue(context, result)
        return (output, nil)
    }

    // MARK: - Module Registration

    /// Register a native module
    public func addModule(_ module: NativeModule) {
        modules.append(module)
    }

    /// Register all modules with current options from configStore
    public func registerAllModules() {
        let userOptions = configStore["modules"] as? [String: [String: Any]] ?? [:]

        // Create macotron global object
        let global = JS_GetGlobalObject(context)
        let macotronObj = JS_NewObject(context)

        // Version info
        let versionObj = JS_NewObject(context)
        JS_SetPropertyStr(context, versionObj, "app", JSBridge.newString(context, "1.0.0"))
        JS_SetPropertyStr(context, versionObj, "api", JSBridge.newString(context, Self.apiVersion))

        let modulesVersion = JS_NewObject(context)
        for module in modules {
            JS_SetPropertyStr(context, modulesVersion, module.name,
                              JSBridge.newInt32(context, Int32(module.moduleVersion)))
        }
        JS_SetPropertyStr(context, versionObj, "modules", modulesVersion)
        JS_SetPropertyStr(context, macotronObj, "version", versionObj)

        JS_SetPropertyStr(context, global, "macotron", macotronObj)
        JS_FreeValue(context, global)

        // Register each module
        for module in modules {
            let opts = module.defaultOptions.merging(
                userOptions[module.name] ?? [:],
                uniquingKeysWith: { _, user in user }
            )
            module.register(in: self, options: opts)
        }
    }

    /// Called after plugins have been evaluated following a reset.
    public func notifyModulesDidReload() {
        for module in modules {
            module.didReload()
        }
    }

    // MARK: - Reset

    /// Full reset for reload
    public func reset() {
        // Cleanup modules
        for module in modules {
            module.cleanup()
        }

        // Clear state
        cancelAllTimers()
        eventBus.removeAllListeners()
        moduleMetadata.removeAll()
        declaredPermissions.removeAll()
        pluginChecks.removeAll()
        pluginEvents.removeAll()

        // Free old command callbacks
        for (_, cmd) in commandRegistry {
            JS_FreeValue(context, cmd.callback)
        }
        commandRegistry.removeAll()
        hotkeyRegistry.removeAll()

        // Reset JS context
        JS_FreeContext(context)
        context = JS_NewContext(runtime)
        setupInterruptHandler()
        setupModuleLoader()
        setupTimerGlobals()
        setupCoreGlobals()
        registerAllModules()
    }

    // No deinit needed — Engine lives for the app's entire lifetime.
    // The OS reclaims all resources on process exit.
}
