import AppKit
import WebKit

/// A menu row that is a web page. NSMenuItem takes any view, so the page is
/// hosted in a plain container sized by the plugin.
///
/// The page keeps running while the menu is open, but menu tracking swallows
/// mouse events before the web content sees them, so treat it as a display:
/// put clickable things in ordinary rows above or below.
final class MenuWebView: NSView {
    private let webView: WKWebView
    private(set) var html: String

    init(html: String, size: NSSize) {
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: NSRect(origin: .zero, size: size), configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.setValue(false, forKey: "drawsBackground")
        self.html = html
        super.init(frame: NSRect(origin: .zero, size: size))
        addSubview(webView)
        webView.loadHTMLString(Self.page(html), baseURL: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// Reloading on every repaint would restart animations and refetch images,
    /// so only reload when the markup actually changed.
    func update(html: String, size: NSSize) {
        if frame.size != size {
            setFrameSize(size)
        }
        guard html != self.html else { return }
        self.html = html
        webView.loadHTMLString(Self.page(html), baseURL: nil)
    }

    static func page(_ html: String) -> String {
        """
        <meta name="color-scheme" content="light dark">
        <style>
        html, body { margin: 0; background: transparent; overflow: hidden;
            font: 13px -apple-system, system-ui; color: canvastext; }
        </style>
        \(html)
        """
    }
}
