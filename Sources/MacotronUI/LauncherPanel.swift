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
    public var onHide: (() -> Void)?

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
        // No .transient and no hidesOnDeactivate: both auto-hide the panel the
        // instant this accessory app loses active status, which races with the
        // global-hotkey activation and makes the launcher flash and vanish.
        // Dismissal is handled explicitly via windowDidResignKey instead.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        becomesKeyOnlyIfNeeded = false
        hidesOnDeactivate = false
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
        self.delegate = self
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
        setFrame(newFrame, display: true)
    }

    private func reveal() {
        pendingReveal = false
        alphaValue = 1
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        if let textField = contentView?.firstEditableTextField() {
            makeFirstResponder(textField)
        }
        isShown = true
    }

    public override func orderOut(_ sender: Any?) {
        let wasVisible = isVisible || isShown
        super.orderOut(sender)
        pendingReveal = false
        isShown = false
        if wasVisible {
            onHide?()
        }
    }

    /// Dismiss on Escape key
    public override func cancelOperation(_ sender: Any?) {
        toggle()
    }

    /// True once the panel is fully shown, so the resign-key handler ignores the
    /// transient key changes that happen while it is still being revealed.
    private var isShown = false

    public func toggle() {
        if isVisible {
            orderOut(nil)
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
                isShown = true
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

extension LauncherPanel: NSWindowDelegate {
    /// Dismiss when the launcher loses key focus — clicking another app or
    /// window, or switching away. This replaces the activation-based auto-hide
    /// that was racing with the global hotkey.
    public func windowDidResignKey(_ notification: Notification) {
        guard isShown, isVisible else { return }
        orderOut(nil)
    }
}
