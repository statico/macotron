import AppKit
import CQuickJS
import Foundation
import MacotronEngine

enum SharePath {
    static func expand(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    static func urls(_ paths: [String]) -> [URL] {
        paths.map { URL(fileURLWithPath: expand($0)) }
    }
}

@MainActor
private final class SharePickerHost: NSObject, @preconcurrency NSSharingServicePickerDelegate {
    var window: NSWindow?
    var picker: NSSharingServicePicker?

    func show(_ items: [Any]) {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 8, height: 8))
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 8, height: 8),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.contentView = view
        var origin = NSEvent.mouseLocation
        origin.x -= 4
        origin.y -= 4
        window.setFrameOrigin(origin)
        window.orderFront(nil)

        let picker = NSSharingServicePicker(items: items)
        picker.delegate = self
        self.window = window
        self.picker = picker
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        window?.close()
        window = nil
        picker = nil
    }
}

@MainActor
public final class ShareModule: NativeModule {
    public let name = "share"
    public let moduleVersion = 1

    private let host = SharePickerHost()

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        engine.configStore["__shareModule"] = self
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JSBridge.getProperty(ctx, global, "macotron")
        let share = JS_NewObject(ctx)

        JS_SetPropertyStr(ctx, share, "open", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx else { return JSBridge.newBool(ctx!, false) }
            if ShareModule.dryRun(ctx) { return JSBridge.newBool(ctx, false) }
            return JSBridge.newBool(ctx, ShareModule.module(ctx)?.open(ctx, argc: argc, argv: argv) ?? false)
        }, "open", 1))

        JS_SetPropertyStr(ctx, share, "airDrop", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx else { return JSBridge.newBool(ctx!, false) }
            if ShareModule.dryRun(ctx) { return JSBridge.newBool(ctx, false) }
            guard let argv, argc >= 1, let raw = JSBridge.jsToSwift(ctx, argv[0]) as? [Any] else {
                return JSBridge.newBool(ctx, false)
            }
            let paths = raw.compactMap { $0 as? String }
            guard !paths.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else {
                return JSBridge.newBool(ctx, false)
            }
            service.perform(withItems: SharePath.urls(paths))
            return JSBridge.newBool(ctx, true)
        }, "airDrop", 1))

        JS_SetPropertyStr(ctx, macotron, "share", share)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)
    }

    public func cleanup() {
        host.window?.close()
        host.window = nil
        host.picker = nil
    }

    private func open(_ ctx: OpaquePointer, argc: Int32, argv: UnsafePointer<JSValue>?) -> Bool {
        guard let argv, argc >= 1 else { return false }
        let opts = argv[0]
        var items: [Any] = []

        let filesVal = JSBridge.getProperty(ctx, opts, "files")
        if let raw = JSBridge.jsToSwift(ctx, filesVal) as? [Any] {
            items.append(contentsOf: SharePath.urls(raw.compactMap { $0 as? String }))
        }
        JS_FreeValue(ctx, filesVal)

        let textVal = JSBridge.getProperty(ctx, opts, "text")
        if !JSBridge.isUndefined(textVal), !JSBridge.isNull(textVal), let text = JSBridge.toString(ctx, textVal), !text.isEmpty {
            items.append(text)
        }
        JS_FreeValue(ctx, textVal)

        let urlVal = JSBridge.getProperty(ctx, opts, "url")
        if !JSBridge.isUndefined(urlVal), !JSBridge.isNull(urlVal), let raw = JSBridge.toString(ctx, urlVal),
           let url = URL(string: raw) {
            items.append(url)
        }
        JS_FreeValue(ctx, urlVal)

        guard !items.isEmpty else { return false }
        NSApp.activate(ignoringOtherApps: true)
        host.show(items)
        return true
    }

    fileprivate static func module(_ ctx: OpaquePointer) -> ShareModule? {
        guard let opaque = JS_GetContextOpaque(ctx) else { return nil }
        let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()
        return engine.configStore["__shareModule"] as? ShareModule
    }

    fileprivate static func dryRun(_ ctx: OpaquePointer) -> Bool {
        guard let opaque = JS_GetContextOpaque(ctx) else { return false }
        return Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue().dryRun
    }
}
