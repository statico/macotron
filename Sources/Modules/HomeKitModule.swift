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

        JSBridge.fn(ctx, homekit, "available", 0) { ctx, _, _, _ in
            guard let ctx else { return JSBridge.newBool(ctx!, false) }
            return JSBridge.newBool(ctx, NSClassFromString("HMHomeManager") != nil)
        }

        JSBridge.fn(ctx, homekit, "homes", 0) { ctx, _, _, _ in
            guard let ctx else { return QJS_Undefined() }
            return JSBridge.newArray(ctx, [])
        }

        JSBridge.fn(ctx, homekit, "accessories", 1) { ctx, _, _, _ in
            guard let ctx else { return QJS_Undefined() }
            return JSBridge.newArray(ctx, [])
        }

        JSBridge.fn(ctx, homekit, "set", 2) { ctx, _, _, _ in
            guard let ctx else { return QJS_Undefined() }
            if homekitDryRun(ctx) { return JSBridge.newObject(ctx, ["ok": true]) }
            return JSBridge.newObject(ctx, ["ok": false, "error": "unavailable"])
        }

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
