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

    /// Dismiss on Escape key
    public override func cancelOperation(_ sender: Any?) {
        toggle()
    }

    public func toggle() {
        if isVisible {
            orderOut(nil)
        } else {
            // Reset to maxHeight so SwiftUI can lay out content fully
            var f = frame
            f.size.height = Self.maxHeight
            setFrame(f, display: false)

            // Raycast-style placement: centered horizontally, upper portion of screen.
            // The top of the panel sits at roughly 78% up the visible area.
            if let screen = NSScreen.main {
                let sf = screen.visibleFrame
                let x = sf.midX - Self.panelWidth / 2
                let topY = sf.minY + sf.height * 0.78
                let y = topY - Self.maxHeight
                setFrameOrigin(NSPoint(x: x, y: y))
            } else {
                center()
            }

            // Show invisible so SwiftUI can compute content height,
            // then reveal on the next run loop tick after resize fires.
            alphaValue = 0
            NSApp.activate(ignoringOtherApps: true)
            makeKeyAndOrderFront(nil)

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.alphaValue = 1
                // Re-activate to ensure we keep focus after the panel is visible
                NSApp.activate(ignoringOtherApps: true)
                self.makeKeyAndOrderFront(nil)
                if let textField = self.contentView?.firstEditableTextField() {
                    self.makeFirstResponder(textField)
                }
            }
        }
    }
}
