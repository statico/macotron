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

    /// One row per plain power action: the JS name and the thing it runs.
    private static let actions: [(name: String, run: @MainActor (Bool) -> Bool)] = [
        ("lock", { PowerActions.lock(dryRun: $0) }),
        ("sleep", { PowerActions.sleep(dryRun: $0) }),
        ("displaySleep", { PowerActions.displaySleep(dryRun: $0) }),
        ("screensaver", { PowerActions.screensaver(dryRun: $0) }),
        ("logOut", { PowerActions.logOut(dryRun: $0) }),
        ("restart", { PowerActions.restart(dryRun: $0) }),
        ("shutdown", { PowerActions.shutdown(dryRun: $0) }),
    ]

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        engine.configStore["__powerModule"] = self
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JSBridge.getProperty(ctx, global, "macotron")
        let power = JS_NewObject(ctx)

        JS_SetPropertyStr(ctx, power, "preventSleep", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx else { return QJS_Undefined() }
            guard let module: PowerModule = Engine.module(ctx, "__powerModule") else {
                return JSBridge.newBool(ctx, false)
            }
            var display = false
            var reason = "Macotron"
            if let argv, argc >= 1, !JSBridge.isUndefined(argv[0]), !JS_IsNull(argv[0]) {
                display = JSBridge.bool(ctx, argv[0], "display") ?? display
                reason = JSBridge.string(ctx, argv[0], "reason") ?? reason
            }
            return JSBridge.newBool(ctx, module.preventSleep(
                display: display, reason: reason, dryRun: Engine.isDryRun(ctx)
            ))
        }, "preventSleep", 1))

        JS_SetPropertyStr(ctx, power, "allowSleep", JS_NewCFunction(ctx, { ctx, _, _, _ in
            guard let ctx else { return QJS_Undefined() }
            let module: PowerModule? = Engine.module(ctx, "__powerModule")
            module?.allowSleep()
            return QJS_Undefined()
        }, "allowSleep", 0))

        JS_SetPropertyStr(ctx, power, "isPreventing", JS_NewCFunction(ctx, { ctx, _, _, _ in
            guard let ctx else { return QJS_Undefined() }
            let module: PowerModule? = Engine.module(ctx, "__powerModule")
            return JSBridge.newBool(ctx, module?.active ?? false)
        }, "isPreventing", 0))

        // The rest differ only in which PowerActions function they call, so the
        // name and the action come off one row and the magic index picks the row.
        for (index, entry) in PowerModule.actions.enumerated() {
            JS_SetPropertyStr(ctx, power, entry.name, JS_NewCFunctionMagic(ctx, { ctx, _, _, _, magic in
                guard let ctx else { return QJS_Undefined() }
                let action = PowerModule.actions[Int(magic)].run
                return JSBridge.newBool(ctx, action(Engine.isDryRun(ctx)))
            }, entry.name, 0, JS_CFUNC_generic_magic, Int32(index)))
        }

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
