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

    /// The size the plugin asked for. AppKit widens a menu row to the widest
    /// item in the menu, and a page pinned to the left edge of that row reads
    /// as misaligned, so keep the page its own width and centre it.
    private var pageSize: NSSize

    init(html: String, size: NSSize) {
        webView = WKWebView(frame: NSRect(origin: .zero, size: size))
        webView.setValue(false, forKey: "drawsBackground")
        self.html = html
        self.pageSize = size
        super.init(frame: NSRect(origin: .zero, size: size))
        // AppKit widens a menu to its widest row but leaves a custom view at
        // the width it was made with, so the page sat against the left edge of
        // a wider menu. Track the width and centre the page inside it.
        autoresizingMask = [.width]
        addSubview(webView)
        webView.loadHTMLString(Self.page(html), baseURL: nil)
    }

    override func layout() {
        super.layout()
        let width = min(pageSize.width, bounds.width)
        webView.frame = NSRect(
            x: ((bounds.width - width) / 2).rounded(),
            y: 0,
            width: width,
            height: bounds.height
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// Reloading on every repaint would restart animations and refetch images,
    /// so only reload when the markup actually changed.
    func update(html: String, size: NSSize) {
        if pageSize != size {
            pageSize = size
            setFrameSize(size)
            needsLayout = true
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

/// A menu row of buttons. A web row cannot do this: menu tracking runs its own
/// run loop and the web process never sees the click. A plain view does get
/// mouse events, and acting on them here instead of handing them to NSButton
/// is what keeps the menu open afterwards.
final class MenuButtonRow: NSView {
    private var titles: [String] = []
    private var actions: [() -> Void] = []
    private var pressed: Int?

    init(titles: [String], actions: [() -> Void], width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 26))
        // Spread the buttons across the menu's real width, not the width the
        // plugin guessed (see MenuWebView).
        autoresizingMask = [.width]
        update(titles: titles, actions: actions, width: width)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func update(titles: [String], actions: [() -> Void], width: CGFloat) {
        self.titles = titles
        self.actions = actions
        if frame.width != width { setFrameSize(NSSize(width: width, height: 26)) }
        needsDisplay = true
    }

    private var cells: [NSRect] {
        guard !titles.isEmpty else { return [] }
        // Match the inset AppKit gives an ordinary menu row.
        let inset: CGFloat = 10
        let usable = max(bounds.width - inset * 2, 1)
        let step = usable / CGFloat(titles.count)
        return titles.indices.map {
            NSRect(x: inset + step * CGFloat($0), y: 2, width: step, height: bounds.height - 4)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        for (index, cell) in cells.enumerated() {
            let hot = pressed == index
            if hot {
                NSColor.selectedContentBackgroundColor.setFill()
                NSBezierPath(roundedRect: cell.insetBy(dx: 1, dy: 0), xRadius: 5, yRadius: 5).fill()
            }
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.menuFont(ofSize: 0),
                .foregroundColor: hot ? NSColor.selectedMenuItemTextColor : NSColor.labelColor,
            ]
            let text = titles[index] as NSString
            let size = text.size(withAttributes: attrs)
            text.draw(
                at: NSPoint(x: cell.midX - size.width / 2, y: cell.midY - size.height / 2),
                withAttributes: attrs
            )
        }
    }

    private func index(at point: NSPoint) -> Int? {
        cells.firstIndex { $0.contains(convert(point, from: nil)) }
    }

    override func mouseDown(with event: NSEvent) {
        pressed = index(at: event.locationInWindow)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let hit = index(at: event.locationInWindow)
        pressed = nil
        needsDisplay = true
        if let hit, hit < actions.count { actions[hit]() }
    }
}
