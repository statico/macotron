// PanelModule.swift — macotron.panel: floating WKWebView NSPanel API
import AppKit
import CQuickJS
import Foundation
import MacotronEngine

private final class PanelModuleState: @unchecked Sendable {
    static let shared = PanelModuleState()
    weak var module: PanelModule?
}

@MainActor
public final class PanelModule: NativeModule {
    public let name = "panel"

    private weak var engine: Engine?
    private var panels: [String: PanelHost] = [:]
    private var globalCallbacks: [JSValue] = []
    private var perIdCallbacks: [String: [JSValue]] = [:]

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        self.engine = engine
        PanelModuleState.shared.module = self

        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JSBridge.getProperty(ctx, global, "macotron")
        let panelObj = JS_NewObject(ctx)

        JS_SetPropertyStr(ctx, panelObj, "open", JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 1 else {
                return QJS_ThrowTypeError(ctx, "panel.open requires an options object")
            }
            guard let module = PanelModuleState.shared.module else {
                return QJS_ThrowTypeError(ctx, "panel not available")
            }

            let opts = argv[0]

            let titleVal = JSBridge.getProperty(ctx, opts, "title")
            let title = JSBridge.toString(ctx, titleVal) ?? "Macotron"
            JS_FreeValue(ctx, titleVal)

            let widthVal = JSBridge.getProperty(ctx, opts, "width")
            let width = Int(JSBridge.toInt32(ctx, widthVal))
            JS_FreeValue(ctx, widthVal)

            let heightVal = JSBridge.getProperty(ctx, opts, "height")
            let height = Int(JSBridge.toInt32(ctx, heightVal))
            JS_FreeValue(ctx, heightVal)

            let rawVal = JSBridge.getProperty(ctx, opts, "rawHtml")
            let rawHtml: String? = JSBridge.isUndefined(rawVal) || JSBridge.isNull(rawVal)
                ? nil : JSBridge.toString(ctx, rawVal)
            JS_FreeValue(ctx, rawVal)

            let htmlVal = JSBridge.getProperty(ctx, opts, "html")
            let html: String? = JSBridge.isUndefined(htmlVal) || JSBridge.isNull(htmlVal)
                ? nil : JSBridge.toString(ctx, htmlVal)
            JS_FreeValue(ctx, htmlVal)

            let glassVal = JSBridge.getProperty(ctx, opts, "glass")
            let glass: PanelGlass
            if JSBridge.isUndefined(glassVal) || JSBridge.isNull(glassVal) {
                glass = .none
            } else {
                glass = PanelGlass.parse(JSBridge.jsToSwift(ctx, glassVal))
            }
            JS_FreeValue(ctx, glassVal)

            let framelessVal = JSBridge.getProperty(ctx, opts, "frameless")
            let frameless = JSBridge.isUndefined(framelessVal) || JSBridge.isNull(framelessVal)
                ? false : JSBridge.toBool(ctx, framelessVal)
            JS_FreeValue(ctx, framelessVal)

            let blurVal = JSBridge.getProperty(ctx, opts, "closeOnBlur")
            let closeOnBlur = JSBridge.isUndefined(blurVal) || JSBridge.isNull(blurVal)
                ? false : JSBridge.toBool(ctx, blurVal)
            JS_FreeValue(ctx, blurVal)

            let escVal = JSBridge.getProperty(ctx, opts, "escapeCloses")
            let escapeCloses = JSBridge.isUndefined(escVal) || JSBridge.isNull(escVal)
                ? true : JSBridge.toBool(ctx, escVal)
            JS_FreeValue(ctx, escVal)

            let idVal = JSBridge.getProperty(ctx, opts, "id")
            let requestedId: String? = JSBridge.isUndefined(idVal) || JSBridge.isNull(idVal)
                ? nil : JSBridge.toString(ctx, idVal)
            JS_FreeValue(ctx, idVal)

            let fullscreenVal = JSBridge.getProperty(ctx, opts, "fullscreen")
            let fullscreen = JSBridge.isUndefined(fullscreenVal) || JSBridge.isNull(fullscreenVal)
                ? false : JSBridge.toBool(ctx, fullscreenVal)
            JS_FreeValue(ctx, fullscreenVal)

            let qrVal = JSBridge.getProperty(ctx, opts, "qr")
            let qr: String? = JSBridge.isUndefined(qrVal) || JSBridge.isNull(qrVal)
                ? nil : JSBridge.toString(ctx, qrVal)
            JS_FreeValue(ctx, qrVal)

            let useShell = rawHtml == nil || rawHtml?.isEmpty == true
            let body = PanelQR.append(to: html ?? "", qr: qr)
            let document = useShell ? PanelShell.document(body: body, glass: glass.isEnabled) : PanelQR.append(to: rawHtml!, qr: qr)

            let id = module.openPanel(
                title: title,
                width: width > 0 ? width : 420,
                height: height > 0 ? height : 520,
                html: document,
                hostChrome: useShell,
                glass: glass,
                frameless: frameless,
                fullscreen: fullscreen,
                closeOnBlur: closeOnBlur,
                escapeCloses: escapeCloses,
                id: requestedId
            )
            return JSBridge.newString(ctx, id)
        }, "open", 1))

        JS_SetPropertyStr(ctx, panelObj, "close", JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 1 else { return QJS_Undefined() }
            let id = JSBridge.toString(ctx, argv[0]) ?? ""
            PanelModuleState.shared.module?.closePanel(id)
            return QJS_Undefined()
        }, "close", 1))

        JS_SetPropertyStr(ctx, panelObj, "postMessage", JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 2 else { return QJS_Undefined() }
            let id = JSBridge.toString(ctx, argv[0]) ?? ""
            let data = JSBridge.jsToSwift(ctx, argv[1])
            PanelModuleState.shared.module?.postToPage(id: id, data: data)
            return QJS_Undefined()
        }, "postMessage", 2))

        JS_SetPropertyStr(ctx, panelObj, "onMessage", JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 1,
                  let module = PanelModuleState.shared.module else { return QJS_Undefined() }

            if argc >= 2 && JS_IsFunction(ctx, argv[1]) {
                let id = JSBridge.toString(ctx, argv[0]) ?? ""
                module.perIdCallbacks[id, default: []].append(JS_DupValue(ctx, argv[1]))
            } else if JS_IsFunction(ctx, argv[0]) {
                module.globalCallbacks.append(JS_DupValue(ctx, argv[0]))
            }
            return QJS_Undefined()
        }, "onMessage", 2))

        JS_SetPropertyStr(ctx, macotron, "panel", panelObj)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)
    }

    public func cleanup() {
        for id in Array(panels.keys) {
            closePanel(id)
        }
        freeCallbacks()
        PanelModuleState.shared.module = nil
    }

    private func openPanel(title: String, width: Int, height: Int, html: String, hostChrome: Bool, glass: PanelGlass, frameless: Bool, fullscreen: Bool, closeOnBlur: Bool, escapeCloses: Bool, id requestedId: String?) -> String {
        let id: String
        if let requestedId, !requestedId.isEmpty {
            closePanel(requestedId)
            id = requestedId
        } else {
            id = UUID().uuidString
        }
        if engine?.dryRun == true {
            return id
        }
        let host = PanelHost(id: id, title: title, width: width, height: height, html: html, hostChrome: hostChrome, glass: glass, frameless: frameless, fullscreen: fullscreen, escapeCloses: escapeCloses, closeOnBlur: closeOnBlur, onMessage: { [weak self] panelId, body in
            self?.dispatchMessage(panelId: panelId, body: body)
        }, onClosed: { [weak self] in
            self?.forgetPanel(id)
        })
        panels[id] = host
        host.show(fullscreen: fullscreen)
        return id
    }

    private func closePanel(_ id: String) {
        let host = panels.removeValue(forKey: id)
        host?.close()
        forgetCallbacks(id)
    }

    private func forgetPanel(_ id: String) {
        panels.removeValue(forKey: id)
        forgetCallbacks(id)
        guard let engine, let ctx = engine.context else { return }
        let data = JSBridge.newObject(ctx, ["id": id])
        engine.eventBus.emit("panel:closed", engine: engine, data: data)
        JS_FreeValue(ctx, data)
    }

    private func forgetCallbacks(_ id: String) {
        if let cbs = perIdCallbacks.removeValue(forKey: id), let ctx = engine?.context {
            for cb in cbs { JS_FreeValue(ctx, cb) }
        }
    }

    private func postToPage(id: String, data: Any) {
        guard let host = panels[id] else { return }
        host.evaluateJSON(data)
    }

    private func dispatchMessage(panelId: String, body: Any) {
        guard let engine, let ctx = engine.context else { return }
        let normalized = Self.normalizeMessageBody(body)
        let payload = JSBridge.anyToJS(ctx, normalized)

        for cb in globalCallbacks + (perIdCallbacks[panelId] ?? []) {
            let arg = JS_DupValue(ctx, payload)
            if let result = engine.callJS(cb, [arg], label: "panel.onMessage", drain: false) {
                JS_FreeValue(ctx, result)
            }
            JS_FreeValue(ctx, arg)
        }
        JS_FreeValue(ctx, payload)
        engine.drainJobQueue()
    }

    private static func normalizeMessageBody(_ body: Any) -> Any {
        if let dict = body as? [String: Any] { return dict }
        if let dict = body as? NSDictionary {
            var out: [String: Any] = [:]
            for (k, v) in dict {
                if let key = k as? String {
                    out[key] = normalizeMessageBody(v)
                }
            }
            return out
        }
        if let arr = body as? [Any] { return arr.map { normalizeMessageBody($0) } }
        if let arr = body as? NSArray { return arr.map { normalizeMessageBody($0) } }
        if let n = body as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                return n.boolValue
            }
            let d = n.doubleValue
            if d == Double(n.intValue) { return n.intValue }
            return d
        }
        if let s = body as? String { return s }
        return "\(body)"
    }

    private func freeCallbacks() {
        guard let ctx = engine?.context else {
            globalCallbacks.removeAll()
            perIdCallbacks.removeAll()
            return
        }
        for cb in globalCallbacks { JS_FreeValue(ctx, cb) }
        for (_, cbs) in perIdCallbacks {
            for cb in cbs { JS_FreeValue(ctx, cb) }
        }
        globalCallbacks.removeAll()
        perIdCallbacks.removeAll()
    }
}
