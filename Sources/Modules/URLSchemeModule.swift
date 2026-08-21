// URLSchemeModule.swift — macotron.url: URL scheme handling and opening
import AppKit
import CoreServices
import CQuickJS
import Foundation
import MacotronEngine

private let macotronBundleID = "io.statico.macotron"

enum URLOpen {
    static func open(_ url: URL, bundleID: String?, profile: String? = nil) -> Bool {
        if let bundleID {
            let config = NSWorkspace.OpenConfiguration()
            if let profile {
                config.arguments = ["--profile-directory=\(profile)"]
            }
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config)
                return true
            }
        }
        NSWorkspace.shared.open(url)
        return true
    }
}

@MainActor
public final class URLSchemeModule: NativeModule {
    public let name = "url"
    public let moduleVersion = 1

    private weak var engine: Engine?

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        self.engine = engine

        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotronObj = JSBridge.getProperty(ctx, global, "macotron")

        let urlObj = JS_NewObject(ctx)

        JS_SetPropertyStr(ctx, urlObj, "on",
                          JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 3 else { return QJS_Undefined() }
            let scheme = JSBridge.toString(ctx, argv[0]) ?? ""
            let host = JSBridge.toString(ctx, argv[1]) ?? ""
            let callback = argv[2]

            let opaque = JS_GetContextOpaque(ctx)
            guard let opaque else { return QJS_Undefined() }
            let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()

            URLSchemeEventReceiver.shared.install(engine: engine)
            URLSchemeEventReceiver.shared.rules.append((scheme, host))
            engine.eventBus.on("url:\(scheme):\(host)", callback: callback, ctx: ctx)

            return QJS_Undefined()
        }, "on", 3))

        JS_SetPropertyStr(ctx, urlObj, "open",
                          JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 1 else { return QJS_Undefined() }
            let urlString = JSBridge.toString(ctx, argv[0]) ?? ""
            var bundleID: String?
            var profile: String?
            if argc >= 2 {
                bundleID = JSBridge.toString(ctx, argv[1])
            }
            if argc >= 3 {
                profile = JSBridge.toString(ctx, argv[2])
            }

            guard let url = URL(string: urlString) else {
                return JSBridge.newBool(ctx, false)
            }
            return JSBridge.newBool(ctx, URLOpen.open(url, bundleID: bundleID, profile: profile))
        }, "open", 3))

        JS_SetPropertyStr(ctx, urlObj, "registerHandler",
                          JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx else { return QJS_Undefined() }
            let opaque = JS_GetContextOpaque(ctx)
            guard let opaque else { return QJS_Undefined() }
            let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()
            URLSchemeEventReceiver.shared.install(engine: engine)
            return JSBridge.newBool(ctx, true)
        }, "registerHandler", 1))

        JS_SetPropertyStr(ctx, urlObj, "setDefaultHandler",
                          JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx else { return QJS_Undefined() }
            guard let argv, argc >= 1 else { return JSBridge.newBool(ctx, false) }
            let scheme = JSBridge.toString(ctx, argv[0]) ?? ""
            guard !scheme.isEmpty else { return JSBridge.newBool(ctx, false) }

            let opaque = JS_GetContextOpaque(ctx)
            guard let opaque else { return JSBridge.newBool(ctx, false) }
            let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()
            URLSchemeEventReceiver.shared.install(engine: engine)
            if engine.dryRun { return JSBridge.newBool(ctx, true) }

            let status = LSSetDefaultHandlerForURLScheme(
                scheme as CFString,
                macotronBundleID as CFString
            )
            return JSBridge.newBool(ctx, status == noErr)
        }, "setDefaultHandler", 1))

        JS_SetPropertyStr(ctx, urlObj, "isDefaultHandler",
                          JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx else { return QJS_Undefined() }
            guard let argv, argc >= 1 else { return JSBridge.newBool(ctx, false) }
            let scheme = JSBridge.toString(ctx, argv[0]) ?? ""
            guard !scheme.isEmpty else { return JSBridge.newBool(ctx, false) }

            let opaque = JS_GetContextOpaque(ctx)
            if let opaque {
                let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()
                if engine.dryRun { return JSBridge.newBool(ctx, false) }
            }

            guard let probe = URL(string: "\(scheme):"),
                  let app = NSWorkspace.shared.urlForApplication(toOpen: probe),
                  let current = Bundle(url: app)?.bundleIdentifier
            else {
                return JSBridge.newBool(ctx, false)
            }
            return JSBridge.newBool(
                ctx,
                current.caseInsensitiveCompare(macotronBundleID) == .orderedSame
            )
        }, "isDefaultHandler", 1))

        JS_SetPropertyStr(ctx, urlObj, "onFallback",
                          JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 1 else { return QJS_Undefined() }
            let opaque = JS_GetContextOpaque(ctx)
            guard let opaque else { return QJS_Undefined() }
            let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()
            URLSchemeEventReceiver.shared.install(engine: engine)
            URLSchemeEventReceiver.shared.setFallback(argv[0], ctx: ctx)
            return QJS_Undefined()
        }, "onFallback", 1))

        JS_SetPropertyStr(ctx, macotronObj, "url", urlObj)
        JS_FreeValue(ctx, macotronObj)
        JS_FreeValue(ctx, global)
    }

    public func cleanup() {
        URLSchemeEventReceiver.shared.reset()
        engine = nil
    }
}

// MARK: - Apple Event Receiver

@MainActor
final class URLSchemeEventReceiver: NSObject {
    static let shared = URLSchemeEventReceiver()
    weak var engine: Engine?
    var rules: [(scheme: String, host: String)] = []
    private var fallback: JSValue?
    private var fallbackCtx: OpaquePointer?

    private override init() {
        super.init()
    }

    func install(engine: Engine) {
        self.engine = engine
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func setFallback(_ callback: JSValue, ctx: OpaquePointer) {
        if let fallbackCtx, let fallback {
            JS_FreeValue(fallbackCtx, fallback)
        }
        fallback = JS_DupValue(ctx, callback)
        fallbackCtx = ctx
    }

    func reset() {
        rules.removeAll()
        if let fallbackCtx, let fallback {
            JS_FreeValue(fallbackCtx, fallback)
        }
        fallback = nil
        fallbackCtx = nil
        engine = nil
    }

    @objc func handleGetURL(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard let engine, !engine.dryRun else { return }
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: urlString) else {
            return
        }

        let scheme = url.scheme ?? ""
        let host = url.host ?? ""
        let source = sourceBundle(from: event)

        if URLEventGate.needsConfirmation(scheme: scheme), !confirmEvent(url: url, source: source) {
            return
        }

        var payload: [String: Any] = [
            "url": urlString,
            "scheme": scheme,
            "host": host,
            "path": url.path,
            "query": url.query ?? ""
        ]
        if let source {
            payload["sourceBundle"] = source
        }

        let ctx = engine.context!
        let data = JSBridge.newObject(ctx, payload)

        switch URLRoute.pick(rules, url: url) {
        case .match(let ruleHost):
            let ruleScheme = rules.first {
                $0.host == ruleHost && $0.scheme.caseInsensitiveCompare(scheme) == .orderedSame
            }?.scheme ?? scheme
            engine.eventBus.emit("url:\(ruleScheme):\(ruleHost)", engine: engine, data: data)
        case .wildcard:
            let ruleScheme = rules.first {
                $0.host == "*" && $0.scheme.caseInsensitiveCompare(scheme) == .orderedSame
            }?.scheme ?? scheme
            engine.eventBus.emit("url:\(ruleScheme):*", engine: engine, data: data)
        case .fallback:
            if let fallback {
                var args = [data]
                _ = JS_Call(ctx, fallback, QJS_Undefined(), 1, &args)
                engine.drainJobQueue()
            } else {
                URLFallbackPicker.show(url: url) { dest, bundleID in
                    _ = URLOpen.open(dest, bundleID: bundleID)
                }
            }
        }
        JS_FreeValue(ctx, data)
    }

    private func confirmEvent(url: URL, source: String?) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Allow URL Event?"
        var info = url.absoluteString
        if let source {
            info += "\n\nSent by \(source)"
        }
        info += "\n\nThis link can trigger plugin actions. Only allow it if you expected it."
        alert.informativeText = info
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func sourceBundle(from event: NSAppleEventDescriptor) -> String? {
        guard let pidDesc = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr)) else {
            return nil
        }
        let pid = pid_t(pidDesc.int32Value)
        guard pid > 0 else { return nil }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }
}
