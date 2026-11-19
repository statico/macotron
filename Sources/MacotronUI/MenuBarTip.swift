// MenuBarTip.swift — a callout under the notch, for items hidden behind it
import AppKit

/// Points at the place the hidden items went, says how to fix it, and fixes it
/// on click. An NSPopover gives the arrow and the system material for free;
/// it hangs off an invisible one-point window, because what it points at
/// (the notch) is not a view.
@MainActor
public final class MenuBarTip: NSObject {
    public static let shared = MenuBarTip()

    private var popover: NSPopover?
    private var anchor: NSPanel?
    private var hideWork: DispatchWorkItem?

    /// False when there is no notch to point at; the caller falls back to a toast.
    @discardableResult
    public func show(title: String, fix: String, onClick: @escaping () -> Void) -> Bool {
        guard let point = Self.notchEdge() else { return false }
        hide()

        let anchor = NSPanel(
            contentRect: NSRect(x: point.x, y: point.y, width: 1, height: 1),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        anchor.isOpaque = false
        anchor.backgroundColor = .clear
        anchor.level = .statusBar
        anchor.ignoresMouseEvents = true
        anchor.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        anchor.isReleasedWhenClosed = false
        anchor.orderFrontRegardless()
        self.anchor = anchor

        let content = TipView(title: title, fix: fix) { [weak self] in
            self?.hide()
            onClick()
        }
        let controller = NSViewController()
        controller.view = content
        let popover = NSPopover()
        popover.contentViewController = controller
        popover.contentSize = content.fittingSize
        // Stays until clicked or timed out; an outside click is not an answer.
        popover.behavior = .applicationDefined
        popover.animates = true
        popover.show(relativeTo: anchor.contentView!.bounds, of: anchor.contentView!, preferredEdge: .minY)
        self.popover = popover

        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: work)
        return true
    }

    public func hide() {
        hideWork?.cancel()
        hideWork = nil
        popover?.close()
        popover = nil
        anchor?.orderOut(nil)
        anchor = nil
    }

    /// Just under the menu bar, at the notch's right edge: the items that do
    /// not fit are the ones that would have sat there.
    private static func notchEdge() -> NSPoint? {
        guard let screen = NSScreen.screens.first(where: { $0.auxiliaryTopRightArea != nil }),
              let right = screen.auxiliaryTopRightArea else { return nil }
        // Measured from the screen's right edge, so it holds whichever
        // coordinate space the area is reported in.
        let x = screen.frame.maxX - right.width + 12
        let y = screen.frame.maxY - screen.safeAreaInsets.top - 1
        return NSPoint(x: x, y: y)
    }
}

/// Logo, what happened, and how to fix it. The whole tip is the button.
private final class TipView: NSView {
    private let action: () -> Void

    init(title: String, fix: String, action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)

        let logo = NSImageView(image: NSApp.applicationIconImage)
        logo.imageScaling = .scaleProportionallyUpOrDown
        NSLayoutConstraint.activate([
            logo.widthAnchor.constraint(equalToConstant: 32),
            logo.heightAnchor.constraint(equalToConstant: 32),
        ])

        let titleField = NSTextField(labelWithString: title)
        titleField.font = .systemFont(ofSize: 13, weight: .semibold)
        let fixField = NSTextField(labelWithString: fix)
        fixField.font = .systemFont(ofSize: 13)
        fixField.textColor = .linkColor

        let text = NSStackView(views: [titleField, fixField])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2

        let row = NSStackView(views: [logo, text])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            // Constraints, not edgeInsets: the popover sized itself as if the
            // stack's top and bottom insets were not there.
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("\(title) \(fix)")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // Labels would otherwise take the click.
    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { action() }
    }

    override func accessibilityPerformPress() -> Bool {
        action()
        return true
    }
}
