// PanelHost.swift — WKWebView floating NSPanel (kept separate to avoid JSValue clash with QuickJS)
import AppKit
import WebKit

enum PanelShell {
    static func document(body: String) -> String {
        let head = """
        <!DOCTYPE html><html lang="en"><head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="light dark">
        <style>
        :root { color-scheme: light dark; }
        html, body { height: 100%; margin: 0; }
        body {
          display: flex;
          flex-direction: column;
          gap: 10px;
          box-sizing: border-box;
          padding: 16px;
          font: 13px/1.45 -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif;
          color: CanvasText;
          background: Canvas;
        }
        h1, h2, h3 { margin: 0; font-weight: 600; }
        h1 { font-size: 18px; }
        h2 { font-size: 15px; }
        h3 { font-size: 13px; }
        p { margin: 0; }
        a { color: LinkText; }
        input, textarea, select, button { font: inherit; color: inherit; }
        input, textarea, select {
          box-sizing: border-box;
          width: 100%;
          padding: 8px 10px;
          border: 1px solid color-mix(in srgb, CanvasText 18%, transparent);
          border-radius: 8px;
          background: Field;
          color: FieldText;
        }
        textarea { resize: vertical; }
        textarea.grow { resize: none; }
        input.inline { width: auto; }
        button {
          padding: 8px 12px;
          border: 0;
          border-radius: 8px;
          background: color-mix(in srgb, CanvasText 12%, Canvas);
          cursor: pointer;
        }
        button:hover { background: color-mix(in srgb, CanvasText 18%, Canvas); }
        button.secondary { background: color-mix(in srgb, CanvasText 8%, Canvas); }
        button.block { display: block; width: 100%; text-align: left; }
        pre, code, .mono { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
        pre { margin: 0; white-space: pre-wrap; }
        .muted { color: color-mix(in srgb, CanvasText 55%, Canvas); }
        .ok { color: #248a3d; }
        .bad { color: #d70015; }
        .grow { flex: 1; min-height: 0; }
        .scroll { overflow: auto; }
        .toolbar { display: flex; gap: 8px; align-items: center; }
        .toolbar input { width: 0; flex: 1; min-width: 0; }
        @media (prefers-color-scheme: dark) {
          .ok { color: #32d74b; }
          .bad { color: #ff6961; }
        }
        </style>
        </head><body>
        """
        return head + body + "</body></html>"
    }
}

private final class PluginPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

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
        wv.underPageBackgroundColor = NSColor.windowBackgroundColor
        self.webView = wv

        let p = PluginPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        p.title = title
        p.isFloatingPanel = true
        p.level = .floating
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = false
        p.contentView = wv
        p.isReleasedWhenClosed = false
        self.panel = p

        super.init()
        controller.add(self, name: "macotron")
        wv.loadHTMLString(html, baseURL: nil)
    }

    func show() {
        panel.center()
        bringToFront()
        // Launcher/menu-bar dismissal on this pass steals key; claim it again after.
        DispatchQueue.main.async { [weak self] in
            self?.bringToFront()
        }
    }

    private func bringToFront() {
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
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
