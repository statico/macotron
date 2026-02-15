// LauncherPanel.swift — Floating NSPanel for the launcher
import AppKit

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
    }

    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { false }

    public func toggle() {
        if isVisible {
            orderOut(nil)
            NSApp.hide(nil)
        } else {
            center()
            makeKeyAndOrderFront(nil)
            NSApp.activate()
        }
    }
}
