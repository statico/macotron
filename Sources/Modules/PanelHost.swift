// PanelHost.swift — WKWebView floating NSPanel (kept separate to avoid JSValue clash with QuickJS)
import AppKit
import WebKit

enum PanelGlass: Equatable {
    case none
    case regular
    case clear
    case translucent

    var isEnabled: Bool { self != .none }
    var usesLiquidGlass: Bool { self == .regular || self == .clear }

    static func parse(_ value: Any) -> PanelGlass {
        switch value {
        case let flag as Bool:
            return flag ? .regular : .none
        case let name as String:
            switch name.lowercased() {
            case "clear": return .clear
            case "regular": return .regular
            case "translucent": return .translucent
            case "false", "none", "": return .none
            default: return .regular
            }
        default:
            return .none
        }
    }
}

enum PanelChrome {
    static let cornerRadius: CGFloat = 12

    static func styleMask(frameless: Bool) -> NSWindow.StyleMask {
        frameless
            ? [.borderless, .fullSizeContentView, .nonactivatingPanel]
            : [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel]
    }
}

@MainActor
enum PanelShell {
    nonisolated static func css(glass: Bool) -> String {
        let pageBg = glass ? "transparent" : "light-dark(#f5f5f7, #1c1c1e)"
        let fieldBg = glass
            ? "light-dark(rgba(255,255,255,0.55), rgba(44,44,46,0.45))"
            : "light-dark(#ffffff, #2c2c2e)"
        return """
    html { color-scheme: light dark; background: \(pageBg); }
    :root {
      --macotron-accent: AccentColor;
      --macotron-accent-text: AccentColorText;
      --macotron-label: CanvasText;
      --macotron-secondary-label: GrayText;
      --macotron-fill: Canvas;
      --macotron-control: ButtonFace;
      --macotron-control-text: ButtonText;
      --macotron-control-border: ButtonBorder;
      --macotron-field: Field;
      --macotron-field-text: FieldText;
      --macotron-selected: Highlight;
      --macotron-selected-text: HighlightText;
      --macotron-link: LinkText;
    }
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
      background: \(pageBg);
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
      background: \(fieldBg);
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
    button.primary {
      background: var(--macotron-accent);
      color: var(--macotron-accent-text);
    }
    button.primary:hover {
      background: var(--macotron-accent);
      filter: brightness(1.08);
    }
    button.block { display: block; width: 100%; text-align: left; }
    pre, code, .mono { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
    pre { margin: 0; white-space: pre-wrap; }
    .muted { color: light-dark(#6e6e73, #98989d); }
    .ok { color: light-dark(#248a3d, #32d74b); }
    .bad { color: light-dark(#d70015, #ff6961); }
    .grow { flex: 1; min-height: 0; }
    .scroll { overflow: auto; }
    .toolbar { display: flex; gap: 8px; align-items: flex-end; }
    .toolbar input, .toolbar select, .toolbar button {
      height: 28px;
      padding-top: 0;
      padding-bottom: 0;
    }
    .toolbar input { width: 0; flex: 1; min-width: 0; }
    .toolbar input.inline { width: 4.5em; flex: none; }
    .toolbar textarea {
      width: 0;
      flex: 1;
      min-width: 0;
      min-height: 52px;
      height: auto;
      padding: 10px 12px;
      line-height: 1.35;
    }
    .toolbar select {
      width: auto;
      flex: none;
      min-width: 8.5em;
      appearance: none;
      padding-right: 22px;
      background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='10' height='6' viewBox='0 0 10 6'%3E%3Cpath fill='%236e6e73' d='M1 1l4 4 4-4'/%3E%3C/svg%3E");
      background-repeat: no-repeat;
      background-position: right 8px center;
    }
    @media (prefers-color-scheme: dark) {
      .toolbar select {
        background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='10' height='6' viewBox='0 0 10 6'%3E%3Cpath fill='%2398989d' d='M1 1l4 4 4-4'/%3E%3C/svg%3E");
      }
    }
    """
    }

    static func document(body: String, glass: Bool = false) -> String {
        "<!DOCTYPE html><html lang=\"en\"><head>"
            + "<meta charset=\"utf-8\">"
            + "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
            + "<meta name=\"color-scheme\" content=\"light dark\">"
            + "<style>" + css(glass: glass) + "</style>"
            + "</head><body>"
            + body
            + "</body></html>"
    }

    nonisolated static func jsonString(_ value: String) -> String {
        (try? JSONEncoder().encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
    }

    static func userScript(glass: Bool = false) -> WKUserScript {
        let source = "(function(){var s=document.createElement('style');s.textContent=\(jsonString(css(glass: glass)));"
            + "(document.head||document.documentElement).appendChild(s);})();"
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
    }

    static func closeScript() -> WKUserScript {
        WKUserScript(
            source: #"(function(){function c(){webkit.messageHandlers.macotron.postMessage({type:"__close"})}try{window.close=c}catch(e){}window.macotronClose=c})();"#,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
    }
}

private final class PluginPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private final class PluginWebView: WKWebView {
    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class PanelHost: NSObject, WKScriptMessageHandler, WKUIDelegate, WKNavigationDelegate {
    let id: String
    private let panel: NSPanel
    private let webView: WKWebView
    private let onMessage: (String, Any) -> Void
    private let onClosed: () -> Void
    private let frameless: Bool
    private let closeOnBlur: Bool
    private var blurArmed = false
    private var zoomMonitor: Any?
    private var dragMonitor: Any?
    private var dragJSBusy = false
    private var queuedMouseJS: String?
    private var trackingGrid = false

    init(
        id: String,
        title: String,
        width: Int,
        height: Int,
        html: String,
        hostChrome: Bool,
        glass: PanelGlass = .none,
        frameless: Bool = false,
        closeOnBlur: Bool = false,
        onMessage: @escaping (String, Any) -> Void,
        onClosed: @escaping () -> Void
    ) {
        self.id = id
        self.onMessage = onMessage
        self.onClosed = onClosed
        self.frameless = frameless
        self.closeOnBlur = closeOnBlur

        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.addUserScript(PanelShell.closeScript())
        if hostChrome {
            controller.addUserScript(PanelShell.userScript(glass: glass.isEnabled))
        }
        config.userContentController = controller

        let size = NSSize(width: width, height: height)
        let wv = PluginWebView(frame: NSRect(origin: .zero, size: size), configuration: config)
        wv.appearance = NSApp.effectiveAppearance
        wv.setValue(false, forKey: "drawsBackground")
        wv.underPageBackgroundColor = (glass.isEnabled || frameless) ? .clear : NSColor.windowBackgroundColor
        wv.addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .activeAlways, .inVisibleRect],
            owner: wv,
            userInfo: nil
        ))
        self.webView = wv

        let p = PluginPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: PanelChrome.styleMask(frameless: frameless),
            backing: .buffered,
            defer: false
        )
        p.title = title
        p.appearance = NSApp.effectiveAppearance
        p.isFloatingPanel = true
        p.level = .floating
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = false
        p.worksWhenModal = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        p.isReleasedWhenClosed = false
        if glass.isEnabled || frameless {
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
        }
        p.contentView = Self.embed(wv, glass: glass, size: size, frameless: frameless)
        self.panel = p

        super.init()
        controller.add(self, name: "macotron")
        wv.uiDelegate = self
        wv.navigationDelegate = self
        wv.loadHTMLString(html, baseURL: URL(string: "about:blank"))
        zoomMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            return self.handleKey(event) ? nil : event
        }
        dragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            self?.forwardMouseButton(event)
            return event
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose),
            name: NSWindow.willCloseNotification,
            object: p
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey),
            name: NSWindow.didBecomeKeyNotification,
            object: p
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResignKey),
            name: NSWindow.didResignKeyNotification,
            object: p
        )
    }

    private static func embed(_ webView: WKWebView, glass: PanelGlass, size: NSSize, frameless: Bool) -> NSView {
        let frame = NSRect(origin: .zero, size: size)
        webView.frame = frame
        webView.autoresizingMask = [.width, .height]
        let radius = frameless ? PanelChrome.cornerRadius : 0
        if glass.usesLiquidGlass {
            if #available(macOS 26.0, *) {
                let view = NSGlassEffectView(frame: frame)
                view.style = glass == .clear ? .clear : .regular
                view.contentView = webView
                view.autoresizingMask = [.width, .height]
                if radius > 0 {
                    view.cornerRadius = radius
                    view.clipsToBounds = true
                }
                return view
            }
            return Self.roundedVisual(frame: frame, webView: webView, clear: glass == .clear, radius: radius)
        }
        if glass == .translucent || frameless {
            return Self.roundedVisual(frame: frame, webView: webView, clear: false, radius: radius)
        }
        return webView
    }

    private static func roundedVisual(frame: NSRect, webView: WKWebView, clear: Bool, radius: CGFloat) -> NSVisualEffectView {
        let view = NSVisualEffectView(frame: frame)
        view.material = clear ? .fullScreenUI : .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.autoresizingMask = [.width, .height]
        if radius > 0 {
            view.wantsLayer = true
            view.layer?.cornerRadius = radius
            view.layer?.masksToBounds = true
        }
        view.addSubview(webView)
        return view
    }

    func show() {
        blurArmed = false
        panel.center()
        bringToFront()
        // Launcher/menu-bar dismissal on this pass steals key; claim it again after.
        DispatchQueue.main.async { [weak self] in
            self?.bringToFront()
            self?.focusDefaultField()
            DispatchQueue.main.async { self?.blurArmed = true }
        }
    }

    private func bringToFront() {
        panel.orderFrontRegardless()
        panel.makeKey()
        webView.becomeFirstResponder()
    }

    /// WKWebView on a nonactivating panel often swallows button-down events.
    /// Replay down/drag/up; hover uses native mousemove.
    private func forwardMouseButton(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            guard pointInPanel(event) else { return }
            trackingGrid = true
            enqueuePointer(event, type: "mousedown", buttons: 1)
        case .leftMouseDragged:
            guard trackingGrid else { return }
            enqueuePointer(event, type: "mousemove", buttons: 1)
        case .leftMouseUp:
            guard trackingGrid else { return }
            trackingGrid = false
            enqueuePointer(event, type: "mouseup", buttons: 0)
        default:
            return
        }
    }

    private func pointInPanel(_ event: NSEvent) -> Bool {
        event.window === panel || panel.frame.contains(NSEvent.mouseLocation)
    }

    private func enqueuePointer(_ event: NSEvent, type: String, buttons: Int) {
        let p = webPoint(from: event)
        queuedMouseJS =
            "window.dispatchEvent(new MouseEvent('\(type)',{clientX:\(p.x),clientY:\(p.y),button:0,buttons:\(buttons),bubbles:true}))"
        flushMouseJS()
    }

    private func webPoint(from event: NSEvent) -> CGPoint {
        let winPoint = event.window === panel
            ? event.locationInWindow
            : panel.convertPoint(fromScreen: NSEvent.mouseLocation)
        var p = webView.convert(winPoint, from: nil)
        if !webView.isFlipped { p.y = webView.bounds.height - p.y }
        return p
    }

    private func flushMouseJS() {
        guard !dragJSBusy, let js = queuedMouseJS else { return }
        queuedMouseJS = nil
        dragJSBusy = true
        webView.evaluateJavaScript(js) { [weak self] _, _ in
            Task { @MainActor in
                self?.dragJSBusy = false
                self?.flushMouseJS()
            }
        }
    }

    private func focusDefaultField() {
        webView.evaluateJavaScript(
            #"(function(){var el=document.querySelector("[autofocus],#input,textarea,input:not([type=hidden])");if(el)el.focus();})();"#
        )
    }

    func close() {
        panel.close()
    }

    func webViewDidClose(_ webView: WKWebView) {
        panel.close()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        focusDefaultField()
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        focusDefaultField()
    }

    @objc private func windowDidResignKey(_ notification: Notification) {
        guard closeOnBlur, blurArmed else { return }
        close()
    }

    @objc private func windowWillClose(_ notification: Notification) {
        tearDown()
        onClosed()
    }

    private func tearDown() {
        if let zoomMonitor {
            NSEvent.removeMonitor(zoomMonitor)
            self.zoomMonitor = nil
        }
        if let dragMonitor {
            NSEvent.removeMonitor(dragMonitor)
            self.dragMonitor = nil
        }
        trackingGrid = false
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "macotron")
        webView.uiDelegate = nil
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: panel)
        NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: panel)
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: panel)
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        if frameless, event.keyCode == 53 {
            close()
            return true
        }
        return handleZoomKey(event)
    }

    private func handleZoomKey(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard mods.contains(.command), !mods.contains(.control), !mods.contains(.option) else {
            return false
        }
        switch event.charactersIgnoringModifiers {
        case "=", "+":
            webView.pageZoom = min(webView.pageZoom + 0.1, 2.5)
            return true
        case "-":
            webView.pageZoom = max(webView.pageZoom - 0.1, 0.5)
            return true
        case "0":
            webView.pageZoom = 1
            return true
        default:
            return false
        }
    }

    func evaluateJSON(_ data: Any) {
        let json: String
        if JSONSerialization.isValidJSONObject(data),
           let raw = try? JSONSerialization.data(withJSONObject: data),
           let s = String(data: raw, encoding: .utf8) {
            json = s
        } else if let s = data as? String {
            json = PanelShell.jsonString(s)
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
            if Self.isCloseMessage(message.body) {
                self.close()
                return
            }
            self.onMessage(self.id, message.body)
        }
    }

    private static func isCloseMessage(_ body: Any) -> Bool {
        if let dict = body as? [String: Any] { return dict["type"] as? String == "__close" }
        if let dict = body as? NSDictionary { return dict["type"] as? String == "__close" }
        return false
    }
}
