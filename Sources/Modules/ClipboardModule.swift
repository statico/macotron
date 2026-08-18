// ClipboardModule.swift — macotron.clipboard: read, write, and track text history
import AppKit
import CQuickJS
import Foundation
import MacotronEngine

@MainActor
public final class ClipboardModule: NativeModule {
    public let name = "clipboard"
    public let moduleVersion = 2

    private var history: [[String: Any]] = []
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var timer: Timer?

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        engine.configStore["__clipboardModule"] = self
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JSBridge.getProperty(ctx, global, "macotron")
        let clipboard = JS_NewObject(ctx)

        JS_SetPropertyStr(ctx, clipboard, "text", JS_NewCFunction(ctx, { ctx, _, _, _ in
            guard let ctx else { return QJS_Undefined() }
            return JSBridge.newString(ctx, NSPasteboard.general.string(forType: .string) ?? "")
        }, "text", 0))

        JS_SetPropertyStr(ctx, clipboard, "set", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 1, let text = JSBridge.toString(ctx, argv[0]) else {
                return QJS_Undefined()
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            return QJS_Undefined()
        }, "set", 1))

        JS_SetPropertyStr(ctx, clipboard, "history", JS_NewCFunction(ctx, { ctx, _, _, _ in
            guard let ctx, let opaque = JS_GetContextOpaque(ctx) else { return QJS_Undefined() }
            let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()
            let items = (engine.configStore["__clipboardModule"] as? ClipboardModule)?.history ?? []
            return JSBridge.newArray(ctx, items)
        }, "history", 0))

        JS_SetPropertyStr(ctx, clipboard, "clearHistory", JS_NewCFunction(ctx, { ctx, _, _, _ in
            guard let ctx, let opaque = JS_GetContextOpaque(ctx) else { return QJS_Undefined() }
            let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()
            (engine.configStore["__clipboardModule"] as? ClipboardModule)?.history.removeAll()
            return QJS_Undefined()
        }, "clearHistory", 0))

        JS_SetPropertyStr(ctx, macotron, "clipboard", clipboard)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)

        guard !engine.dryRun else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    public func cleanup() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else { return }
        history.insert([
            "id": UUID().uuidString,
            "text": text,
            "kind": "text",
            "ts": Date().timeIntervalSince1970 * 1000,
        ], at: 0)
        history = Array(history.prefix(50))
    }
}
