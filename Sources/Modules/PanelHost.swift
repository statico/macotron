// PanelHost.swift — WKWebView floating NSPanel (kept separate to avoid JSValue clash with QuickJS)
import AppKit
import WebKit

@MainActor
enum PanelShell {
    static let css = """
    html { color-scheme: light dark; }
    html, body { height: 100%; margin: 0; }
    body {
      display: flex;
      flex-direction: column;
      gap: 12px;
      box-sizing: border-box;
      padding: 16px;
      font-family: ui-sans-serif, -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
      font-size: 13px;
      line-height: 1.45;
      -webkit-font-smoothing: antialiased;
      color: light-dark(#1d1d1f, #f5f5f7);
      background: light-dark(#f5f5f7, #1c1c1e);
    }
    h1, h2, h3 { margin: 0; font-weight: 600; letter-spacing: -0.02em; }
    h1 { font-size: 18px; }
    h2 { font-size: 15px; }
    h3 { font-size: 13px; }
    p { margin: 0; }
    a { color: light-dark(#007aff, #0a84ff); }
    input, textarea, select, button {
      font-family: inherit;
      font-size: inherit;
      line-height: inherit;
      color: inherit;
    }
    input, textarea, select {
      box-sizing: border-box;
      width: 100%;
      padding: 8px 10px;
      border: 1px solid light-dark(rgba(0,0,0,0.12), rgba(255,255,255,0.14));
      border-radius: 8px;
      background: light-dark(#ffffff, #2c2c2e);
      color: light-dark(#1d1d1f, #f5f5f7);
      outline: none;
    }
    input:focus, textarea:focus, select:focus {
      border-color: light-dark(#007aff, #0a84ff);
      box-shadow: 0 0 0 3px light-dark(rgba(0,122,255,0.22), rgba(10,132,255,0.32));
    }
    textarea { resize: vertical; }
    textarea.grow { resize: none; }
    input.inline { width: auto; }
    button {
      padding: 8px 12px;
      border: 0;
      border-radius: 8px;
      background: light-dark(rgba(0,0,0,0.06), rgba(255,255,255,0.12));
      cursor: pointer;
    }
    button:hover { background: light-dark(rgba(0,0,0,0.10), rgba(255,255,255,0.18)); }
    button.secondary { background: light-dark(rgba(0,0,0,0.04), rgba(255,255,255,0.08)); }
    button.block { display: block; width: 100%; text-align: left; }
    pre, code, .mono { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
    pre { margin: 0; white-space: pre-wrap; }
    .muted { color: light-dark(#6e6e73, #98989d); }
    .ok { color: light-dark(#248a3d, #32d74b); }
    .bad { color: light-dark(#d70015, #ff6961); }
    .grow { flex: 1; min-height: 0; }
    .scroll { overflow: auto; }
    .toolbar { display: flex; gap: 8px; align-items: center; }
    .toolbar input { width: 0; flex: 1; min-width: 0; }
    .toolbar input.inline { width: 4.5em; flex: none; }
    """

    static func document(body: String) -> String {
        "<!DOCTYPE html><html lang=\"en\"><head>"
            + "<meta charset=\"utf-8\">"
            + "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
            + "<meta name=\"color-scheme\" content=\"light dark\">"
            + "<style>" + css + "</style>"
            + "</head><body>"
            + body
            + "</body></html>"
    }

    static func userScript() -> WKUserScript {
        let encoded = String(data: try! JSONSerialization.data(withJSONObject: css), encoding: .utf8)!
        let source = "(function(){var s=document.createElement('style');s.textContent=\(encoded);"
            + "(document.head||document.documentElement).appendChild(s);})();"
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
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

    init(id: String, title: String, width: Int, height: Int, html: String, hostChrome: Bool, onMessage: @escaping (String, Any) -> Void) {
        self.id = id
        self.onMessage = onMessage

        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        if hostChrome {
            controller.addUserScript(PanelShell.userScript())
        }
        config.userContentController = controller

        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: width, height: height), configuration: config)
        wv.appearance = NSApp.effectiveAppearance
        wv.setValue(false, forKey: "drawsBackground")
        wv.underPageBackgroundColor = NSColor.windowBackgroundColor
        self.webView = wv

        let p = PluginPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        p.title = title
        p.appearance = NSApp.effectiveAppearance
        p.isFloatingPanel = true
        p.level = .floating
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = false
        p.contentView = wv
        p.isReleasedWhenClosed = false
        self.panel = p

        super.init()
        controller.add(self, name: "macotron")
        wv.loadHTMLString(html, baseURL: URL(string: "about:blank"))
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
