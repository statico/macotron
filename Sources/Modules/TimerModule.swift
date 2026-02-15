// TimerModule.swift — macotron.timer: scheduling helpers (thin wrapper)
//
// The core timer primitives (setTimeout, setInterval, clearTimeout, clearInterval)
// are registered directly by Engine.swift on the global object.
//
// This module exposes the `macotron.timer` namespace for higher-level scheduling
// helpers like `every` (human-readable interval) and future cron-like support.
import CQuickJS
import Foundation
import MacotronEngine
import os

private let logger = Logger(subsystem: "com.macotron", category: "timer")

@MainActor
public final class TimerModule: NativeModule {
    public let name = "timer"
    public let moduleVersion = 1

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JS_GetPropertyStr(ctx, global, "macotron")

        let timerObj = JS_NewObject(ctx)

        // -----------------------------------------------------------------
        // macotron.timer.every(intervalMs, callback) -> timerID
        //
        // Convenience wrapper around setInterval. Returns the timer ID
        // so it can be cancelled with clearInterval(id).
        // -----------------------------------------------------------------
        JS_SetPropertyStr(ctx, timerObj, "every", JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 2 else {
                return QJS_ThrowTypeError(ctx, "timer.every requires intervalMs and callback")
            }

            let ms = JSBridge.toInt32(ctx, argv[0])
            let callback = argv[1]

            // Delegate to the global setInterval already set up by Engine
            let globalObj = JS_GetGlobalObject(ctx)
            let setIntervalFn = JS_GetPropertyStr(ctx, globalObj, "setInterval")
            var args = [callback, JS_NewInt32(ctx, ms)]
            let result = JS_Call(ctx, setIntervalFn, QJS_Undefined(), 2, &args)
            JS_FreeValue(ctx, args[1])
            JS_FreeValue(ctx, setIntervalFn)
            JS_FreeValue(ctx, globalObj)

            logger.info("timer.every: \(ms)ms")
            return result
        }, "every", 2))

        // -----------------------------------------------------------------
        // macotron.timer.after(delayMs, callback) -> timerID
        //
        // Convenience wrapper around setTimeout. Returns the timer ID
        // so it can be cancelled with clearTimeout(id).
        // -----------------------------------------------------------------
        JS_SetPropertyStr(ctx, timerObj, "after", JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 2 else {
                return QJS_ThrowTypeError(ctx, "timer.after requires delayMs and callback")
            }

            let ms = JSBridge.toInt32(ctx, argv[0])
            let callback = argv[1]

            // Delegate to the global setTimeout already set up by Engine
            let globalObj = JS_GetGlobalObject(ctx)
            let setTimeoutFn = JS_GetPropertyStr(ctx, globalObj, "setTimeout")
            var args = [callback, JS_NewInt32(ctx, ms)]
            let result = JS_Call(ctx, setTimeoutFn, QJS_Undefined(), 2, &args)
            JS_FreeValue(ctx, args[1])
            JS_FreeValue(ctx, setTimeoutFn)
            JS_FreeValue(ctx, globalObj)

            logger.info("timer.after: \(ms)ms")
            return result
        }, "after", 2))

        // -----------------------------------------------------------------
        // macotron.timer.cancel(timerID) -> void
        //
        // Cancels a timer created by `every` or `after`.
        // -----------------------------------------------------------------
        JS_SetPropertyStr(ctx, timerObj, "cancel", JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 1 else {
                return QJS_ThrowTypeError(ctx, "timer.cancel requires a timerID")
            }

            let globalObj = JS_GetGlobalObject(ctx)
            let clearTimeoutFn = JS_GetPropertyStr(ctx, globalObj, "clearTimeout")
            var args = [argv[0]]
            _ = JS_Call(ctx, clearTimeoutFn, QJS_Undefined(), 1, &args)
            JS_FreeValue(ctx, clearTimeoutFn)
            JS_FreeValue(ctx, globalObj)

            return QJS_Undefined()
        }, "cancel", 1))

        JS_SetPropertyStr(ctx, macotron, "timer", timerObj)

        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)
    }

    public func cleanup() {
        // Timer cleanup is handled by Engine.cancelAllTimers()
    }
}
