// ClipboardModule.swift — macotron.clipboard: read and write the system clipboard
import CQuickJS
import MacotronEngine
import AppKit
import os

private let logger = Logger(subsystem: "com.macotron", category: "clipboard")

@MainActor
public final class ClipboardModule: NativeModule {
    public let name = "clipboard"

    private weak var engine: Engine?

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        self.engine = engine
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JSBridge.getProperty(ctx, global, "macotron")

        let clipboardObj = JS_NewObject(ctx)

        // ---------- text() -> string ----------
        JS_SetPropertyStr(ctx, clipboardObj, "text", JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx else { return QJS_Undefined() }
            let pasteboard = NSPasteboard.general
            if let text = pasteboard.string(forType: .string) {
                return JSBridge.newString(ctx, text)
            }
            return JSBridge.newString(ctx, "")
        }, "text", 0))

        // ---------- set(text) -> void ----------
        JS_SetPropertyStr(ctx, clipboardObj, "set", JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 1 else { return QJS_Undefined() }
            guard let text = JSBridge.toString(ctx, argv[0]) else { return QJS_Undefined() }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            return QJS_Undefined()
        }, "set", 1))

        JS_SetPropertyStr(ctx, macotron, "clipboard", clipboardObj)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)
    }
}
