import CQuickJS
import Foundation
import MacotronEngine

// ponytail: no public HomeKit.framework on native macOS (Mac Catalyst only; no com.apple.developer.homekit). Empty homes.

@MainActor
public final class HomeKitModule: NativeModule {
    public let name = "homekit"

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JSBridge.getProperty(ctx, global, "macotron")
        let homekit = JS_NewObject(ctx)

        JS_SetPropertyStr(ctx, homekit, "available", JS_NewCFunction(ctx, { ctx, _, _, _ in
            guard let ctx else { return JSBridge.newBool(ctx!, false) }
            return JSBridge.newBool(ctx, NSClassFromString("HMHomeManager") != nil)
        }, "available", 0))

        JS_SetPropertyStr(ctx, homekit, "homes", JS_NewCFunction(ctx, { ctx, _, _, _ in
            guard let ctx else { return QJS_Undefined() }
            return JSBridge.newArray(ctx, [])
        }, "homes", 0))

        JS_SetPropertyStr(ctx, homekit, "accessories", JS_NewCFunction(ctx, { ctx, _, _, _ in
            guard let ctx else { return QJS_Undefined() }
            return JSBridge.newArray(ctx, [])
        }, "accessories", 1))

        JS_SetPropertyStr(ctx, homekit, "set", JS_NewCFunction(ctx, { ctx, _, _, _ in
            guard let ctx else { return QJS_Undefined() }
            if homekitDryRun(ctx) { return JSBridge.newObject(ctx, ["ok": true]) }
            return JSBridge.newObject(ctx, ["ok": false, "error": "unavailable"])
        }, "set", 2))

        JS_SetPropertyStr(ctx, macotron, "homekit", homekit)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)
    }

    public func cleanup() {}
}

@MainActor
private func homekitDryRun(_ ctx: OpaquePointer) -> Bool {
    Engine.isDryRun(ctx)
}
