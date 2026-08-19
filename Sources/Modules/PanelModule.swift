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
                return QJS_ThrowTypeError(ctx, "panel module not available")
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

            let htmlVal = JSBridge.getProperty(ctx, opts, "html")
            let html = JSBridge.toString(ctx, htmlVal) ?? ""
            JS_FreeValue(ctx, htmlVal)

            let id = module.openPanel(
                title: title,
                width: width > 0 ? width : 420,
                height: height > 0 ? height : 520,
                html: html
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

    private func openPanel(title: String, width: Int, height: Int, html: String) -> String {
        let id = UUID().uuidString
        if engine?.dryRun == true {
            return id
        }
        let host = PanelHost(id: id, title: title, width: width, height: height, html: html) { [weak self] panelId, body in
            self?.dispatchMessage(panelId: panelId, body: body)
        }
        panels[id] = host
        host.show()
        return id
    }

    private func closePanel(_ id: String) {
        panels[id]?.close()
        panels.removeValue(forKey: id)
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
            var arg = JS_DupValue(ctx, payload)
            _ = JS_Call(ctx, cb, QJS_Undefined(), 1, &arg)
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
