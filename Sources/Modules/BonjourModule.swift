import CQuickJS
import Foundation
import MacotronEngine

@MainActor
public final class BonjourModule: NativeModule {
    public let name = "bonjour"

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JSBridge.getProperty(ctx, global, "macotron")
        let obj = JS_NewObject(ctx)

        JS_SetPropertyStr(ctx, obj, "browse", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx else { return QJS_Undefined() }
            guard let argv, argc >= 1, let type = JSBridge.toString(ctx, argv[0]) else {
                return JSBridge.promise(ctx, dryRun: [Any]()) { .value([Any]()) }
            }
            var timeout = 1.5
            if argc >= 2, let opts = JSBridge.jsToSwift(ctx, argv[1]) as? [String: Any] {
                if let i = opts["timeout"] as? Int { timeout = Double(i) }
                else if let d = opts["timeout"] as? Double { timeout = d }
            }
            let seconds = timeout
            return JSBridge.promise(ctx, dryRun: [Any]()) {
                .value(BonjourBrowse.browse(type: type, timeout: seconds, dryRun: false).map { $0 as Any })
            }
        }, "browse", 2))

        JS_SetPropertyStr(ctx, macotron, "bonjour", obj)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)
    }
}
