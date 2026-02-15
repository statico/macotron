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

    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { false }

    /// Dismiss on Escape key
    public override func cancelOperation(_ sender: Any?) {
        toggle()
    }

    public func toggle() {
        if isVisible {
            orderOut(nil)
        } else {
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
