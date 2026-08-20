// ClipboardModule.swift — macotron.clipboard: read, write, and track text/image history
import AppKit
import CQuickJS
import Foundation
import MacotronEngine

@MainActor
public final class ClipboardModule: NativeModule {
    public let name = "clipboard"
    public let moduleVersion = 3

    private var history: [[String: Any]] = []
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var timer: Timer?
    private weak var engine: Engine?

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        self.engine = engine
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

        JS_SetPropertyStr(ctx, clipboard, "setImage", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 1, let raw = JSBridge.toString(ctx, argv[0]) else {
                return JSBridge.newBool(ctx!, false)
            }
            let b64 = String(raw.split(separator: ",", maxSplits: 1).last ?? Substring(raw))
            guard let data = Data(base64Encoded: b64) else { return JSBridge.newBool(ctx, false) }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setData(data, forType: .png)
            return JSBridge.newBool(ctx, true)
        }, "setImage", 1))

        JS_SetPropertyStr(ctx, clipboard, "history", JS_NewCFunction(ctx, { ctx, _, _, _ in
            guard let ctx, let opaque = JS_GetContextOpaque(ctx) else { return QJS_Undefined() }
            let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()
            let items = (engine.configStore["__clipboardModule"] as? ClipboardModule)?.history ?? []
            return JSBridge.newArray(ctx, items)
        }, "history", 0))

        JS_SetPropertyStr(ctx, clipboard, "paste", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 1, let id = JSBridge.toString(ctx, argv[0]),
                  let opaque = JS_GetContextOpaque(ctx) else {
                return JSBridge.newBool(ctx!, false)
            }
            let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()
            guard let module = engine.configStore["__clipboardModule"] as? ClipboardModule,
                  let item = module.history.first(where: { ($0["id"] as? String) == id }),
                  let kind = item["kind"] as? String,
                  let text = item["text"] as? String else {
                return JSBridge.newBool(ctx, false)
            }
            let pb = NSPasteboard.general
            pb.clearContents()
            if kind == "image" {
                guard let data = Data(base64Encoded: text) else { return JSBridge.newBool(ctx, false) }
                pb.setData(data, forType: .png)
            } else {
                pb.setString(text, forType: .string)
            }
            return JSBridge.newBool(ctx, true)
        }, "paste", 1))

        JS_SetPropertyStr(ctx, clipboard, "remove", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 1, let id = JSBridge.toString(ctx, argv[0]),
                  let opaque = JS_GetContextOpaque(ctx) else {
                return JSBridge.newBool(ctx!, false)
            }
            let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()
            guard let module = engine.configStore["__clipboardModule"] as? ClipboardModule else {
                return JSBridge.newBool(ctx, false)
            }
            let before = module.history.count
            module.history.removeAll { ($0["id"] as? String) == id }
            return JSBridge.newBool(ctx, module.history.count < before)
        }, "remove", 1))

        JS_SetPropertyStr(ctx, clipboard, "clearHistory", JS_NewCFunction(ctx, { ctx, _, _, _ in
            guard let ctx, let opaque = JS_GetContextOpaque(ctx) else { return QJS_Undefined() }
            let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()
            (engine.configStore["__clipboardModule"] as? ClipboardModule)?.history.removeAll()
            return QJS_Undefined()
        }, "clearHistory", 0))

        JS_SetPropertyStr(ctx, clipboard, "clear", JS_NewCFunction(ctx, { ctx, _, _, _ in
            NSPasteboard.general.clearContents()
            return QJS_Undefined()
        }, "clear", 0))

        JS_SetPropertyStr(ctx, clipboard, "types", JS_NewCFunction(ctx, { ctx, _, _, _ in
            guard let ctx else { return QJS_Undefined() }
            return JSBridge.newArray(ctx, ClipboardPasteboard.types())
        }, "types", 0))

        JS_SetPropertyStr(ctx, clipboard, "data", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 1, let uti = JSBridge.toString(ctx, argv[0]) else {
                return QJS_Undefined()
            }
            guard let raw = ClipboardPasteboard.data(uti) else { return QJS_Null() }
            return JSBridge.newString(ctx, raw.base64EncodedString())
        }, "data", 1))

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
        emitChanged(pasteboard)

        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            push(kind: "text", text: text)
            return
        }
        var png: Data?
        if let data = pasteboard.data(forType: .png) {
            png = data
        } else if let data = pasteboard.data(forType: .tiff),
                  let rep = NSBitmapImageRep(data: data),
                  let converted = rep.representation(using: .png, properties: [:]) {
            png = converted
        }
        guard let png else { return }
        push(kind: "image", text: png.base64EncodedString())
    }

    private func emitChanged(_ pasteboard: NSPasteboard) {
        guard let engine, let ctx = engine.context else { return }
        let data = JSBridge.newObject(ctx, [
            "changeCount": lastChangeCount,
            "types": ClipboardPasteboard.types(pasteboard),
        ])
        engine.eventBus.emit("clipboard:changed", engine: engine, data: data)
        JS_FreeValue(ctx, data)
    }

    private func push(kind: String, text: String) {
        history.insert([
            "id": UUID().uuidString,
            "text": text,
            "kind": kind,
            "ts": Date().timeIntervalSince1970 * 1000,
        ], at: 0)
        history = Array(history.prefix(50))
    }
}

enum ClipboardPasteboard {
    static func types(_ pasteboard: NSPasteboard = .general) -> [String] {
        names(pasteboard.types ?? [])
    }

    static func names(_ types: [NSPasteboard.PasteboardType]) -> [String] {
        types.map(\.rawValue)
    }

    static func data(_ uti: String, _ pasteboard: NSPasteboard = .general) -> Data? {
        pasteboard.data(forType: NSPasteboard.PasteboardType(uti))
    }
}
