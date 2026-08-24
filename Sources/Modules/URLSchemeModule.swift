// URLSchemeModule.swift — macotron.url: URL scheme handling and opening
import AppKit
import CoreServices
import CQuickJS
import Foundation
import MacotronEngine
import OSLog

private let macotronBundleID = "io.statico.macotron"
private let logger = Logger(subsystem: "io.statico.macotron", category: "url")

enum URLOpen {
    static func applicationURL(bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    static func open(_ url: URL, bundleID: String?, profile: String? = nil) -> Bool {
        if let bundleID {
            let config = NSWorkspace.OpenConfiguration()
            if let profile {
                config.arguments = ["--profile-directory=\(profile)"]
            }
            guard let appURL = applicationURL(bundleID: bundleID) else { return false }
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config)
            return true
        }
        NSWorkspace.shared.open(url)
        return true
    }
}

@MainActor
public final class URLSchemeModule: NativeModule {
    public let name = "url"
    public let moduleVersion = 1

    public init() {}

    public static func handle(_ urls: [URL], sourceBundle: String? = nil) {
        for url in urls {
            URLSchemeEventReceiver.shared.receive(url, sourceBundle: sourceBundle)
        }
    }

    public func register(in engine: Engine, options: [String: Any]) {
        URLSchemeEventReceiver.shared.configure(engine: engine)

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

            let receiver = URLSchemeEventReceiver.shared
            if JS_IsRegExp(argv[1]) {
                let event = "url:\(scheme):regex:\(receiver.regexRules.count)"
                receiver.regexRules.append(JSRegexRule(
                    scheme: scheme,
                    event: event,
                    regex: JS_DupValue(ctx, argv[1]),
                    ctx: ctx
                ))
                engine.eventBus.on(event, callback: callback, ctx: ctx)
            } else {
                let event = "url:\(scheme):\(host)"
                receiver.rules.append((scheme, host))
                engine.eventBus.on(event, callback: callback, ctx: ctx)
            }

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
            if Engine.isDryRun(ctx) { return JSBridge.newBool(ctx, true) }
            return JSBridge.newBool(ctx, URLOpen.open(url, bundleID: bundleID, profile: profile))
        }, "open", 3))

        JS_SetPropertyStr(ctx, urlObj, "registerHandler",
                          JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx else { return QJS_Undefined() }
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
            URLSchemeEventReceiver.shared.setFallback(argv[0], ctx: ctx)
            return QJS_Undefined()
        }, "onFallback", 1))

        JS_SetPropertyStr(ctx, macotronObj, "url", urlObj)
        JS_FreeValue(ctx, macotronObj)
        JS_FreeValue(ctx, global)
    }

    public func cleanup() {
        URLSchemeEventReceiver.shared.reset()
    }

    public func didReload() {
        URLSchemeEventReceiver.shared.finishLoading()
    }
}

@MainActor
fileprivate struct JSRegexRule {
    let scheme: String
    let event: String
    let regex: JSValue
    let ctx: OpaquePointer

    func matches(_ url: URL) -> Bool {
        guard scheme.caseInsensitiveCompare(url.scheme ?? "") == .orderedSame else { return false }
        JS_SetPropertyStr(ctx, regex, "lastIndex", JS_NewInt32(ctx, 0))
        let test = JSBridge.getProperty(ctx, regex, "test")
        let host = JSBridge.newString(ctx, url.host ?? "")
        var args = [host]
        let result = JS_Call(ctx, test, regex, 1, &args)
        let matched = !JS_IsException(result) && JSBridge.toBool(ctx, result)
        JS_FreeValue(ctx, result)
        JS_FreeValue(ctx, host)
        JS_FreeValue(ctx, test)
        JS_SetPropertyStr(ctx, regex, "lastIndex", JS_NewInt32(ctx, 0))
        return matched
    }
}

@MainActor
final class URLSchemeEventReceiver {
    static let shared = URLSchemeEventReceiver()
    weak var engine: Engine?
    var rules: [(scheme: String, host: String)] = []
    fileprivate var regexRules: [JSRegexRule] = []
    private var fallback: JSValue?
    private var fallbackCtx: OpaquePointer?
    private var pendingEvents: [(url: URL, sourceBundle: String?)] = []
    private var isLoading = true

    private init() {}

    func configure(engine: Engine) {
        self.engine = engine
    }

    func finishLoading() {
        isLoading = false
        let events = pendingEvents
        pendingEvents.removeAll()
        logger.info("URL receiver ready, \(self.rules.count) rules, \(events.count) queued")
        for event in events {
            dispatch(event.url, sourceBundle: event.sourceBundle)
        }
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
        for rule in regexRules {
            JS_FreeValue(rule.ctx, rule.regex)
        }
        regexRules.removeAll()
        if let fallbackCtx, let fallback {
            JS_FreeValue(fallbackCtx, fallback)
        }
        fallback = nil
        fallbackCtx = nil
        engine = nil
        isLoading = true
    }

    func receive(_ url: URL, sourceBundle: String?) {
        if isLoading || engine == nil {
            pendingEvents.append((url, sourceBundle))
            logger.info("URL queued while plugins load: \(url.absoluteString, privacy: .public)")
            return
        }
        dispatch(url, sourceBundle: sourceBundle)
    }

    private func dispatch(_ url: URL, sourceBundle: String?) {
        guard let engine, !engine.dryRun else {
            logger.error("URL event dropped: no live engine")
            return
        }
        let urlString = url.absoluteString
        logger.debug(
            "URL event \(urlString, privacy: .public), \(self.rules.count + self.regexRules.count) rules"
        )

        let scheme = url.scheme ?? ""
        let host = url.host ?? ""

        if URLEventGate.needsConfirmation(scheme: scheme),
           !confirmEvent(url: url, sourceBundle: sourceBundle) {
            return
        }

        var payload: [String: Any] = [
            "url": urlString,
            "scheme": scheme,
            "host": host,
            "path": url.path,
            "query": url.query ?? ""
        ]
        if let sourceBundle {
            payload["sourceBundle"] = sourceBundle
        }

        let ctx = engine.context!
        let data = JSBridge.newObject(ctx, payload)

        switch URLRoute.pick(rules.filter { $0.host != "*" }, url: url) {
        case .match(let ruleHost):
            let ruleScheme = rules.first {
                $0.host == ruleHost && $0.scheme.caseInsensitiveCompare(scheme) == .orderedSame
            }?.scheme ?? scheme
            engine.eventBus.emit("url:\(ruleScheme):\(ruleHost)", engine: engine, data: data)
        case .fallback, .wildcard:
            if let rule = regexRules.first(where: { $0.matches(url) }) {
                engine.eventBus.emit(rule.event, engine: engine, data: data)
            } else if let wildcard = rules.first(where: {
                $0.host == "*" && $0.scheme.caseInsensitiveCompare(scheme) == .orderedSame
            }) {
                engine.eventBus.emit(
                    "url:\(wildcard.scheme):*",
                    engine: engine,
                    data: data
                )
            } else if let fallback {
                var args = [data]
                _ = JS_Call(ctx, fallback, QJS_Undefined(), 1, &args)
                engine.drainJobQueue()
            } else {
                logger.error("URL event has no route: \(urlString, privacy: .public)")
            }
        }
        JS_FreeValue(ctx, data)
    }

    private func confirmEvent(url: URL, sourceBundle: String?) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Allow URL Event?"
        var info = url.absoluteString
        if let sourceBundle {
            info += "\n\nSent by \(sourceBundle)"
        }
        info += "\n\nThis link can trigger plugin actions. Only allow it if you expected it."
        alert.informativeText = info
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Cancel")
        AppActivation.activate("url scheme handler")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
