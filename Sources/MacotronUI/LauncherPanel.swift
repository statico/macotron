// LauncherPanel.swift — Floating NSPanel for the launcher
import AppKit

private extension NSView {
    func firstEditableTextField() -> NSTextField? {
        if let tf = self as? NSTextField, tf.isEditable { return tf }
        for subview in subviews {
            if let found = subview.firstEditableTextField() { return found }
        }
        return nil
    }
}

@MainActor
public final class LauncherPanel: NSPanel {
    public init(contentView: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        animationBehavior = .utilityWindow
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        becomesKeyOnlyIfNeeded = false
        hidesOnDeactivate = true
        center()

        // Vibrancy background
        let visual = NSVisualEffectView(frame: .zero)
        visual.material = .hudWindow
        visual.state = .active
        visual.blendingMode = .behindWindow
        visual.wantsLayer = true
        visual.layer?.cornerRadius = 12
        visual.layer?.masksToBounds = true
        visual.autoresizingMask = [.width, .height]

        contentView.frame = visual.bounds
        contentView.autoresizingMask = [.width, .height]
        visual.addSubview(contentView)

        self.contentView = visual
    }

    private static let fullHeight: CGFloat = 480
    private static let compactHeight: CGFloat = 90

    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { false }

    /// Collapse to compact height (agent progress) or expand to full height (search mode).
    /// Keeps the panel centered horizontally at the same top edge.
    public func setCompact(_ compact: Bool) {
        let targetHeight = compact ? Self.compactHeight : Self.fullHeight
        guard frame.height != targetHeight else { return }
        let topY = frame.maxY
        var newFrame = frame
        newFrame.size.height = targetHeight
        newFrame.origin.y = topY - targetHeight
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().setFrame(newFrame, display: true)
        }
    }

    /// Dismiss on Escape key
    public override func cancelOperation(_ sender: Any?) {
        toggle()
    }

    public func toggle() {
        if isVisible {
            orderOut(nil)
        } else {
            // Ensure full height when opening fresh
            if frame.height != Self.fullHeight {
                var f = frame
                f.size.height = Self.fullHeight
                setFrame(f, display: false)
            }
            // Position in upper third of screen (like Raycast)
            if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                let panelSize = frame.size
                let x = screenFrame.midX - panelSize.width / 2
                let y = screenFrame.maxY - panelSize.height - (screenFrame.height * 0.2)
                setFrameOrigin(NSPoint(x: x, y: y))
            } else {
                center()
            }
            makeKeyAndOrderFront(nil)
            NSApp.activate()

            // Focus the search text field
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if let textField = self.contentView?.firstEditableTextField() {
                    self.makeFirstResponder(textField)
                }
            }
        }
    }
}
