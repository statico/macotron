// PanelHost.swift — WKWebView floating NSPanel (kept separate to avoid JSValue clash with QuickJS)
import AppKit
import WebKit

@MainActor
final class PanelHost: NSObject, WKScriptMessageHandler {
    let id: String
    private let panel: NSPanel
    private let webView: WKWebView
    private let onMessage: (String, Any) -> Void

    init(id: String, title: String, width: Int, height: Int, html: String, onMessage: @escaping (String, Any) -> Void) {
        self.id = id
        self.onMessage = onMessage

        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        config.userContentController = controller

        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: width, height: height), configuration: config)
        self.webView = wv

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        p.title = title
        p.isFloatingPanel = true
        p.level = .floating
        p.contentView = wv
        p.isReleasedWhenClosed = false
        self.panel = p

        super.init()
        controller.add(self, name: "macotron")
        wv.loadHTMLString(html, baseURL: nil)
    }

    func show() {
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func close() {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "macotron")
        panel.close()
    }

    func evaluateJSON(_ data: Any) {
        let json: String
        if JSONSerialization.isValidJSONObject(data),
           let raw = try? JSONSerialization.data(withJSONObject: data),
           let s = String(data: raw, encoding: .utf8) {
            json = s
        } else if let s = data as? String,
                  let raw = try? JSONSerialization.data(withJSONObject: s),
                  let encoded = String(data: raw, encoding: .utf8) {
            json = encoded
        } else if data is NSNull {
            json = "null"
        } else {
            json = "null"
        }
        webView.evaluateJavaScript(
            "(typeof window.__macotronReceive==='function'&&window.__macotronReceive(\(json)));"
            + "window.dispatchEvent(new MessageEvent('message',{data:\(json)}));"
        )
    }

    nonisolated func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        Task { @MainActor in
            self.onMessage(self.id, message.body)
        }
    }
}
