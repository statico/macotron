// PowerModule.swift — macotron.power: prevent/allow system sleep via IOPM assertions
import CQuickJS
import Foundation
import IOKit.pwr_mgt
import MacotronEngine

@MainActor
public final class PowerModule: NativeModule {
    public let name = "power"
    public let moduleVersion = 3

    private var assertionID: IOPMAssertionID = 0
    private var active = false

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        engine.configStore["__powerModule"] = self
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JSBridge.getProperty(ctx, global, "macotron")
        let power = JS_NewObject(ctx)

        JS_SetPropertyStr(ctx, power, "preventSleep", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx else { return QJS_Undefined() }
            guard let module = powerModule(ctx) else { return JSBridge.newBool(ctx, false) }
            var display = false
            var reason = "Macotron"
            if let argv, argc >= 1, !JSBridge.isUndefined(argv[0]), !JS_IsNull(argv[0]) {
                let opts = argv[0]
                let displayVal = JSBridge.getProperty(ctx, opts, "display")
                if !JSBridge.isUndefined(displayVal) {
                    display = JSBridge.toBool(ctx, displayVal)
                }
                JS_FreeValue(ctx, displayVal)
                let reasonVal = JSBridge.getProperty(ctx, opts, "reason")
                if !JSBridge.isUndefined(reasonVal), let r = JSBridge.toString(ctx, reasonVal) {
                    reason = r
                }
                JS_FreeValue(ctx, reasonVal)
            }
            let opaque = JS_GetContextOpaque(ctx)
            let dryRun = opaque.map { Unmanaged<Engine>.fromOpaque($0).takeUnretainedValue().dryRun } ?? false
            return JSBridge.newBool(ctx, module.preventSleep(display: display, reason: reason, dryRun: dryRun))
        }, "preventSleep", 1))

        JS_SetPropertyStr(ctx, power, "allowSleep", JS_NewCFunction(ctx, { ctx, _, _, _ in
            guard let ctx, let module = powerModule(ctx) else { return QJS_Undefined() }
            module.allowSleep()
            return QJS_Undefined()
        }, "allowSleep", 0))

        JS_SetPropertyStr(ctx, power, "isPreventing", JS_NewCFunction(ctx, { ctx, _, _, _ in
            guard let ctx else { return QJS_Undefined() }
            guard let module = powerModule(ctx) else { return JSBridge.newBool(ctx, false) }
            return JSBridge.newBool(ctx, module.active)
        }, "isPreventing", 0))

        JS_SetPropertyStr(ctx, power, "lock", JS_NewCFunction(ctx, { ctx, _, _, _ in
            guard let ctx else { return JSBridge.newBool(ctx!, false) }
            return JSBridge.newBool(ctx, PowerActions.lock(dryRun: engineDryRun(ctx)))
        }, "lock", 0))

        JS_SetPropertyStr(ctx, power, "sleep", JS_NewCFunction(ctx, { ctx, _, _, _ in
            guard let ctx else { return JSBridge.newBool(ctx!, false) }
            return JSBridge.newBool(ctx, PowerActions.sleep(dryRun: engineDryRun(ctx)))
        }, "sleep", 0))

        JS_SetPropertyStr(ctx, power, "displaySleep", JS_NewCFunction(ctx, { ctx, _, _, _ in
            guard let ctx else { return JSBridge.newBool(ctx!, false) }
            return JSBridge.newBool(ctx, PowerActions.displaySleep(dryRun: engineDryRun(ctx)))
        }, "displaySleep", 0))

        JS_SetPropertyStr(ctx, power, "screensaver", JS_NewCFunction(ctx, { ctx, _, _, _ in
            guard let ctx else { return JSBridge.newBool(ctx!, false) }
            return JSBridge.newBool(ctx, PowerActions.screensaver(dryRun: engineDryRun(ctx)))
        }, "screensaver", 0))

        JS_SetPropertyStr(ctx, power, "logOut", JS_NewCFunction(ctx, { ctx, _, _, _ in
            guard let ctx else { return JSBridge.newBool(ctx!, false) }
            return JSBridge.newBool(ctx, PowerActions.logOut(dryRun: engineDryRun(ctx)))
        }, "logOut", 0))

        JS_SetPropertyStr(ctx, power, "restart", JS_NewCFunction(ctx, { ctx, _, _, _ in
            guard let ctx else { return JSBridge.newBool(ctx!, false) }
            return JSBridge.newBool(ctx, PowerActions.restart(dryRun: engineDryRun(ctx)))
        }, "restart", 0))

        JS_SetPropertyStr(ctx, power, "shutdown", JS_NewCFunction(ctx, { ctx, _, _, _ in
            guard let ctx else { return JSBridge.newBool(ctx!, false) }
            return JSBridge.newBool(ctx, PowerActions.shutdown(dryRun: engineDryRun(ctx)))
        }, "shutdown", 0))

        JS_SetPropertyStr(ctx, macotron, "power", power)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)

        guard !engine.dryRun else { return }
        PowerWatch.start(engine)
    }

    public func cleanup() {
        PowerWatch.stop()
        allowSleep()
    }

    private func preventSleep(display: Bool, reason: String, dryRun: Bool) -> Bool {
        allowSleep()
        if dryRun {
            active = true
            return true
        }
        let type = (display
            ? kIOPMAssertionTypeNoDisplaySleep
            : kIOPMAssertPreventUserIdleSystemSleep) as CFString
        var id: IOPMAssertionID = 0
        let status = IOPMAssertionCreateWithName(
            type,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &id
        )
        guard status == kIOReturnSuccess else { return false }
        assertionID = id
        active = true
        return true
    }

    private func allowSleep() {
        guard active else { return }
        if assertionID != 0 {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
        }
        active = false
    }
}

@MainActor
private func powerModule(_ ctx: OpaquePointer) -> PowerModule? {
    guard let opaque = JS_GetContextOpaque(ctx) else { return nil }
    let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()
    return engine.configStore["__powerModule"] as? PowerModule
}

@MainActor
private func engineDryRun(_ ctx: OpaquePointer) -> Bool {
    guard let opaque = JS_GetContextOpaque(ctx) else { return false }
    return Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue().dryRun
}
