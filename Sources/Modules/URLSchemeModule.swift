// URLSchemeModule.swift — macotron.url: URL scheme handling and opening
import AppKit
import CQuickJS
import Foundation
import MacotronEngine

@MainActor
public final class URLSchemeModule: NativeModule {
    public let name = "url"
    public let moduleVersion = 1

    private weak var engine: Engine?

    /// Registered scheme handlers: "scheme:host" → JS callback
    private var handlers: [String: JSValue] = [:]

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        self.engine = engine

        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotronObj = JSBridge.getProperty(ctx, global, "macotron")

        let urlObj = JS_NewObject(ctx)

        // macotron.url.on(scheme, host, callback) — register handler for URLs
        JS_SetPropertyStr(ctx, urlObj, "on",
                          JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 3 else { return QJS_Undefined() }
            let scheme = JSBridge.toString(ctx, argv[0]) ?? ""
            let host = JSBridge.toString(ctx, argv[1]) ?? ""
            let callback = argv[2]

            let opaque = JS_GetContextOpaque(ctx)
            guard let opaque else { return QJS_Undefined() }
            let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()

            // Register the callback on the event bus for "url:{scheme}:{host}"
            let eventName = "url:\(scheme):\(host)"
            engine.eventBus.on(eventName, callback: callback, ctx: ctx)

            return QJS_Undefined()
        }, "on", 3))

        // macotron.url.open(url, bundleID?) — open URL in browser or specific app
        JS_SetPropertyStr(ctx, urlObj, "open",
                          JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 1 else { return QJS_Undefined() }
            let urlString = JSBridge.toString(ctx, argv[0]) ?? ""
            var bundleID: String?
            if argc >= 2 {
                bundleID = JSBridge.toString(ctx, argv[1])
            }

            guard let url = URL(string: urlString) else {
                return JSBridge.newBool(ctx, false)
            }

            if let bundleID {
                // Open with specific application
                let config = NSWorkspace.OpenConfiguration()
                if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                    NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config)
                } else {
                    NSWorkspace.shared.open(url)
                }
            } else {
                NSWorkspace.shared.open(url)
            }

            return JSBridge.newBool(ctx, true)
        }, "open", 2))

        // macotron.url.registerHandler(scheme) — claim a URL scheme
        JS_SetPropertyStr(ctx, urlObj, "registerHandler",
                          JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 1 else { return QJS_Undefined() }
            let _ = JSBridge.toString(ctx, argv[0]) ?? ""

            let opaque = JS_GetContextOpaque(ctx)
            guard let opaque else { return QJS_Undefined() }
            let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()

            // Install an Apple Event handler for GetURL events.
            // When macOS dispatches a URL with the registered scheme,
            // we parse it and emit "url:{scheme}:{host}" on the event bus.
            let eventManager = NSAppleEventManager.shared()
            eventManager.setEventHandler(
                URLSchemeEventReceiver.shared,
                andSelector: #selector(URLSchemeEventReceiver.handleGetURL(_:withReply:)),
                forEventClass: AEEventClass(kInternetEventClass),
                andEventID: AEEventID(kAEGetURL)
            )

            // Store the engine reference so the receiver can emit events
            URLSchemeEventReceiver.shared.engine = engine

            // Note: To actually claim the scheme at the OS level, the app's
            // Info.plist must declare CFBundleURLTypes with the scheme.
            // This call sets up the runtime handler for when URLs arrive.
            return JSBridge.newBool(ctx, true)
        }, "registerHandler", 1))

        JS_SetPropertyStr(ctx, macotronObj, "url", urlObj)
        JS_FreeValue(ctx, macotronObj)
        JS_FreeValue(ctx, global)
    }

    public func cleanup() {
        handlers.removeAll()
        engine = nil
    }
}

// MARK: - Apple Event Receiver

/// Singleton NSObject that receives Apple Events for URL scheme handling.
/// Must be an NSObject subclass so it can be used as an Apple Event handler target.
@MainActor
final class URLSchemeEventReceiver: NSObject {
    static let shared = URLSchemeEventReceiver()
    weak var engine: Engine?

    private override init() {
        super.init()
    }

    @objc func handleGetURL(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard let engine else { return }
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: urlString) else {
            return
        }

        let scheme = url.scheme ?? ""
        let host = url.host ?? ""
        let eventName = "url:\(scheme):\(host)"

        // Build a data object with URL components
        let ctx = engine.context!
        let data = JSBridge.newObject(ctx, [
            "url": urlString,
            "scheme": scheme,
            "host": host,
            "path": url.path,
            "query": url.query ?? ""
        ])

        engine.eventBus.emit(eventName, engine: engine, data: data)
        JS_FreeValue(ctx, data)
    }
}
