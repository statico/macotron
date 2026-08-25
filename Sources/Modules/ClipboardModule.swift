// ClipboardModule.swift — macotron.clipboard: read, write, and track text/image history
import AppKit
import Carbon.HIToolbox
import CoreGraphics
import CQuickJS
import Foundation
import MacotronEngine

private final class ClipboardPlainTapState: @unchecked Sendable {
    static let shared = ClipboardPlainTapState()
    private let lock = NSLock()
    private var eventTap: CFMachPort?

    var tap: CFMachPort? {
        get { lock.lock(); defer { lock.unlock() }; return eventTap }
        set { lock.lock(); eventTap = newValue; lock.unlock() }
    }
}

@MainActor
public final class ClipboardModule: NativeModule {
    public let name = "clipboard"
    public let moduleVersion = 4

    var history: [[String: Any]] = []
    var historyOptIn = false
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var timer: Timer?
    private weak var engine: Engine?
    private var pastePlain = false
    private var pasteTap: CFMachPort?
    private var pasteTapSource: CFRunLoopSource?
    var hasPasteTap: Bool { pasteTap != nil }

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        self.engine = engine
        historyOptIn = options["history"] as? Bool ?? false
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
            if Engine.isDryRun(ctx) { return QJS_Undefined() }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            return QJS_Undefined()
        }, "set", 1))

        JS_SetPropertyStr(ctx, clipboard, "setImage", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 1, let raw = JSBridge.toString(ctx, argv[0]) else {
                return JSBridge.newBool(ctx!, false)
            }
            if Engine.isDryRun(ctx) { return JSBridge.newBool(ctx, true) }
            let b64 = String(raw.split(separator: ",", maxSplits: 1).last ?? Substring(raw))
            guard let data = Data(base64Encoded: b64) else { return JSBridge.newBool(ctx, false) }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setData(data, forType: .png)
            return JSBridge.newBool(ctx, true)
        }, "setImage", 1))

        JS_SetPropertyStr(ctx, clipboard, "history", JS_NewCFunction(ctx, { ctx, _, _, _ in
            guard let ctx, let opaque = JS_GetContextOpaque(ctx) else { return QJS_Undefined() }
            let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()
            guard let module = engine.configStore["__clipboardModule"] as? ClipboardModule else {
                return JSBridge.newArray(ctx, [])
            }
            module.historyOptIn = true
            module.startPolling()
            return JSBridge.newArray(ctx, module.trimmedHistory())
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
            if engine.dryRun { return JSBridge.newBool(ctx, true) }
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
            if Engine.isDryRun(ctx) { return QJS_Undefined() }
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

        JS_SetPropertyStr(ctx, clipboard, "setPastePlain", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 1, let module = clipboardModule(ctx) else {
                return JSBridge.newBool(ctx!, false)
            }
            return JSBridge.newBool(ctx, module.setPastePlain(JSBridge.toBool(ctx, argv[0])))
        }, "setPastePlain", 1))

        JS_SetPropertyStr(ctx, clipboard, "isPastePlain", JS_NewCFunction(ctx, { ctx, _, _, _ in
            guard let ctx, let module = clipboardModule(ctx) else {
                return JSBridge.newBool(ctx!, false)
            }
            return JSBridge.newBool(ctx, module.pastePlain)
        }, "isPastePlain", 0))

        JS_SetPropertyStr(ctx, macotron, "clipboard", clipboard)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)

        guard !engine.dryRun else { return }
        startPolling()
    }

    var isPolling: Bool { timer != nil }

    func startPolling() {
        guard timer == nil, engine?.dryRun != true else { return }
        lastChangeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    fileprivate func trimmedHistory() -> [[String: Any]] {
        let cutoff = Date().timeIntervalSince1970 * 1000 - ClipboardHistoryPolicy.maxAgeMs
        history = history.filter { ($0["ts"] as? Double ?? 0) >= cutoff }
        if history.count > ClipboardHistoryPolicy.maxCount {
            history = Array(history.prefix(ClipboardHistoryPolicy.maxCount))
        }
        return history
    }

    public func cleanup() {
        timer?.invalidate()
        timer = nil
        removePasteTap()
        pastePlain = false
        historyOptIn = false
    }

    private func setPastePlain(_ on: Bool) -> Bool {
        if engine?.dryRun == true {
            pastePlain = on
            return true
        }
        if on {
            guard installPasteTap() else {
                pastePlain = false
                return false
            }
            pastePlain = true
            return true
        }
        removePasteTap()
        pastePlain = false
        return true
    }

    private func installPasteTap() -> Bool {
        guard pasteTap == nil else { return true }
        let callback: CGEventTapCallBack = { _, type, event, _ in
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = ClipboardPlainTapState.shared.tap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return Unmanaged.passRetained(event)
            }
            if type == .keyDown {
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                if keyCode == Int64(kVK_ANSI_V), event.flags.contains(.maskCommand) {
                    // NSPasteboard is not thread safe and the history poll owns it on main,
                    // so the rewrite goes there. It has to finish before the paste lands,
                    // hence sync; only the paste keystroke pays for a busy main thread.
                    DispatchQueue.main.sync { ClipboardPlain.applyCurrentText() }
                }
            }
            return Unmanaged.passRetained(event)
        }
        let mask: CGEventMask = 1 << CGEventType.keyDown.rawValue
        pasteTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: nil
        )
        guard let pasteTap else { return false }
        ClipboardPlainTapState.shared.tap = pasteTap
        pasteTapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, pasteTap, 0)
        if let pasteTapSource {
            EventTapThread.shared.add(pasteTapSource)
        }
        CGEvent.tapEnable(tap: pasteTap, enable: true)
        return true
    }

    private func removePasteTap() {
        if let pasteTap {
            CGEvent.tapEnable(tap: pasteTap, enable: false)
            CFMachPortInvalidate(pasteTap)
        }
        if let pasteTapSource {
            EventTapThread.shared.remove(pasteTapSource)
        }
        pasteTap = nil
        pasteTapSource = nil
        ClipboardPlainTapState.shared.tap = nil
    }

    private var historyEnabled: Bool {
        historyOptIn || engine?.eventBus.hasListeners("clipboard:changed") == true
    }

    func poll(_ pasteboard: NSPasteboard = .general) {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        emitChanged(pasteboard)
        guard historyEnabled, ClipboardHistoryPolicy.isRecordable(ClipboardPasteboard.types(pasteboard)) else { return }

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
        _ = trimmedHistory()
    }
}

@MainActor
private func clipboardModule(_ ctx: OpaquePointer) -> ClipboardModule? {
    guard let opaque = JS_GetContextOpaque(ctx) else { return nil }
    let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()
    return engine.configStore["__clipboardModule"] as? ClipboardModule
}

enum ClipboardHistoryPolicy {
    static let skipTypes: Set<String> = [
        "org.nspasteboard.ConcealedType",
        "org.nspasteboard.TransientType",
        "org.nspasteboard.AutoGeneratedType",
    ]
    static let maxCount = 50
    static let maxAgeMs = 24 * 60 * 60 * 1000.0

    static func isRecordable(_ types: [String]) -> Bool {
        !types.contains { skipTypes.contains($0) }
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
