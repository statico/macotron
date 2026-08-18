// SnippetsModule.swift — macotron.snippets: in-memory text snippets
import AppKit
import CQuickJS
import MacotronEngine

@MainActor
public final class SnippetsModule: NativeModule {
    public let name = "snippets"

    private var snippets: [String: String] = [:]

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        engine.configStore["__snippetsModule"] = self
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JSBridge.getProperty(ctx, global, "macotron")
        let snippets = JS_NewObject(ctx)

        JS_SetPropertyStr(ctx, snippets, "list", JS_NewCFunction(ctx, { ctx, _, _, _ in
            guard let ctx, let module = module(ctx) else { return QJS_Undefined() }
            let items: [Any] = module.snippets.sorted { $0.key < $1.key }.map {
                ["abbr": $0.key, "body": $0.value]
            }
            return JSBridge.newArray(ctx, items)
        }, "list", 0))

        JS_SetPropertyStr(ctx, snippets, "set", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 2, let module = module(ctx),
                  let abbr = JSBridge.toString(ctx, argv[0]),
                  let body = JSBridge.toString(ctx, argv[1]) else { return QJS_Undefined() }
            module.snippets[abbr] = body
            return QJS_Undefined()
        }, "set", 2))

        JS_SetPropertyStr(ctx, snippets, "remove", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 1, let module = module(ctx),
                  let abbr = JSBridge.toString(ctx, argv[0]) else { return QJS_Undefined() }
            module.snippets.removeValue(forKey: abbr)
            return QJS_Undefined()
        }, "remove", 1))

        JS_SetPropertyStr(ctx, snippets, "insert", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 1, let module = module(ctx),
                  let abbr = JSBridge.toString(ctx, argv[0]),
                  let body = module.snippets[abbr] else { return QJS_Undefined() }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(body, forType: .string)
            return QJS_Undefined()
        }, "insert", 1))

        JS_SetPropertyStr(ctx, macotron, "snippets", snippets)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)
    }
}

@MainActor
private func module(_ ctx: OpaquePointer) -> SnippetsModule? {
    guard let opaque = JS_GetContextOpaque(ctx) else { return nil }
    let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()
    return engine.configStore["__snippetsModule"] as? SnippetsModule
}
