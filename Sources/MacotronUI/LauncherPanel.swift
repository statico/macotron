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
    private static let panelWidth: CGFloat = 720
    private static let minHeight: CGFloat = 52  // Search bar only
    private static let maxHeight: CGFloat = 520

    /// Set after toggle() to defer visibility until SwiftUI reports content height.
    private var pendingReveal = false
    /// Cached content height from the last layout pass — used to open at the right size.
    private var lastContentHeight: CGFloat = 0

    public init(contentView: NSView) {
        // Start at maxHeight so SwiftUI has room to lay out content
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: Self.maxHeight),
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

    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { false }

    /// Resize the panel to fit the given content height, keeping the top edge pinned.
    public func resizeToHeight(_ height: CGFloat) {
        let clamped = min(max(height, Self.minHeight), Self.maxHeight)
        lastContentHeight = clamped

        if pendingReveal {
            // First height report after toggle — snap to correct size and reveal.
            let topY = frame.maxY
            var newFrame = frame
            newFrame.size.height = clamped
            newFrame.origin.y = topY - clamped
            setFrame(newFrame, display: true)
            reveal()
            return
        }

        guard abs(frame.height - clamped) > 1 else { return }

        let topY = frame.maxY
        var newFrame = frame
        newFrame.size.height = clamped
        newFrame.origin.y = topY - clamped

        if isVisible && alphaValue > 0 {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                animator().setFrame(newFrame, display: true)
            }
        } else {
            setFrame(newFrame, display: true)
        }
    }

    private func reveal() {
        pendingReveal = false
        alphaValue = 1
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        if let textField = contentView?.firstEditableTextField() {
            makeFirstResponder(textField)
        }
    }

    /// Dismiss on Escape key
    public override func cancelOperation(_ sender: Any?) {
        toggle()
    }

    public func toggle() {
        if isVisible {
            orderOut(nil)
            pendingReveal = false
        } else {
            // Use cached height on subsequent opens to avoid the tall-then-shrink flash.
            // On first open, use maxHeight so SwiftUI has full space for layout.
            let initialHeight = lastContentHeight > 0 ? lastContentHeight : Self.maxHeight

            var f = frame
            f.size.height = initialHeight
            setFrame(f, display: false)

            // Raycast-style placement: centered horizontally, upper portion of screen.
            if let screen = NSScreen.main {
                let sf = screen.visibleFrame
                let x = sf.midX - Self.panelWidth / 2
                let topY = sf.minY + sf.height * 0.78
                let y = topY - initialHeight
                setFrameOrigin(NSPoint(x: x, y: y))
            } else {
                center()
            }

            if lastContentHeight > 0 {
                // We know the right height — show immediately at the cached size.
                // SwiftUI will animate-adjust if content changed since last close.
                NSApp.activate(ignoringOtherApps: true)
                makeKeyAndOrderFront(nil)
                if let textField = contentView?.firstEditableTextField() {
                    makeFirstResponder(textField)
                }
            } else {
                // First open — show invisible, wait for SwiftUI to report height.
                alphaValue = 0
                pendingReveal = true
                makeKeyAndOrderFront(nil)

                // Safety fallback if SwiftUI doesn't report height quickly.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    guard let self, self.pendingReveal else { return }
                    self.reveal()
                }
            }
        }
    }
}
