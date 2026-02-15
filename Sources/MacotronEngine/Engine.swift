// Engine.swift — QuickJS runtime lifecycle, timers, module registration
import CQuickJS
import Foundation
import os

private let logger = Logger(subsystem: "com.macotron", category: "engine")

@MainActor
public final class Engine {
    public private(set) var runtime: OpaquePointer!
    public private(set) var context: OpaquePointer!
    public let eventBus = EventBus()

    private var modules: [NativeModule] = []
    private var timers: [UInt32: DispatchSourceTimer] = [:]
    private var nextTimerID: UInt32 = 1
    private var shouldInterrupt = false
    private var interruptDeadline: Date?

    /// Registered commands (name → callback)
    public var commandRegistry: [String: (name: String, description: String, callback: JSValue)] = [:]

    /// Config store (populated by macotron.config() calls)
    public var configStore: [String: Any] = [:]

    /// Log output handler
    public var logHandler: ((String) -> Void)?

    public init() {
        runtime = JS_NewRuntime()
        context = JS_NewContext(runtime)
        setupInterruptHandler()
        setupTimerGlobals()
        setupCoreGlobals()
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
            return engine.shouldInterrupt ? 1 : 0
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
                logger.info("\(msg)")
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
                if let opaque {
                    let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()
                    let callback = JS_DupValue(ctx, argv[2])
                    engine.commandRegistry[name] = (name: name, description: desc, callback: callback)
                }
                return QJS_Undefined()
            }, "$$__registerCommand", 3))

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

        JS_FreeValue(context, global)
    }

    // MARK: - Timer Management

    private func scheduleTimer(callback: JSValue, ms: Int32, repeats: Bool) -> UInt32 {
        let id = nextTimerID
        nextTimerID += 1
        let protectedCallback = JS_DupValue(context, callback)

        let timer = DispatchSource.makeTimerSource(queue: .main)
        let interval = DispatchTimeInterval.milliseconds(Int(max(ms, 1)))
        if repeats {
            timer.schedule(deadline: .now() + interval, repeating: interval)
        } else {
            timer.schedule(deadline: .now() + interval)
        }
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            _ = JS_Call(self.context, protectedCallback, QJS_Undefined(), 0, nil)
            self.drainJobQueue()
            if !repeats {
                JS_FreeValue(self.context, protectedCallback)
                self.cancelTimer(id)
            }
        }
        timers[id] = timer
        timer.resume()
        return id
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

    /// Evaluate JS code. Returns (result, error).
    @discardableResult
    public func evaluate(_ js: String, filename: String = "<eval>") -> (String?, String?) {
        // Set a 5-second interrupt deadline for user code
        interruptDeadline = Date().addingTimeInterval(5)
        defer { interruptDeadline = nil }

        let result = js.withCString { cStr in
            JS_Eval(context, cStr, js.utf8.count, filename, Int32(JS_EVAL_TYPE_GLOBAL))
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

        // Free old command callbacks
        for (_, cmd) in commandRegistry {
            JS_FreeValue(context, cmd.callback)
        }
        commandRegistry.removeAll()

        // Reset JS context
        JS_FreeContext(context)
        context = JS_NewContext(runtime)
        setupInterruptHandler()
        setupTimerGlobals()
        setupCoreGlobals()
        registerAllModules()
    }

    // No deinit needed — Engine lives for the app's entire lifetime.
    // The OS reclaims all resources on process exit.
}
