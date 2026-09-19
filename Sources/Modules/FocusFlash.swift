// FocusFlash.swift — a brief outline flash around a window, to show where the focus went
import AppKit

private final class FocusFlashPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The shape of the flash, kept free of AppKit so it can be tested without a screen.
enum FocusFlashGeometry {
    /// The line sits outside the window edge. A line drawn on the edge is half hidden by the window.
    static let margin: CGFloat = 3
    static let lineWidth: CGFloat = 2.5
    /// The pulse starts at this width and settles to `lineWidth`.
    static let pulseWidth: CGFloat = 5
    /// The corner of a macOS window. The outline is outside it, so it is rounder by `margin`.
    static let windowCorner: CGFloat = 12
    static let duration: TimeInterval = 0.5

    static func outline(around window: CGRect) -> CGRect {
        window.insetBy(dx: -margin, dy: -margin)
    }

    /// Never more than half the shorter side, or the corners cross and the shape breaks.
    static func corner(for outline: CGRect) -> CGFloat {
        min(windowCorner + margin, min(outline.width, outline.height) / 2)
    }
}

@MainActor final class FocusFlash {
    static let shared = FocusFlash()

    private var panel: NSPanel?
    private var generation = 0

    /// `frame` is in Cocoa coordinates, not AX coordinates.
    func show(_ frame: CGRect) {
        let rect = FocusFlashGeometry.outline(around: frame)
        guard rect.width > 1, rect.height > 1 else { return }

        let panel = self.panel ?? makePanel()
        self.panel = panel
        guard let layer = panel.contentView?.layer else { return }

        layer.cornerRadius = FocusFlashGeometry.corner(for: rect)
        layer.borderColor = NSColor.controlAccentColor.cgColor
        panel.setFrame(rect, display: false)
        panel.orderFrontRegardless()

        // The layer rests invisible. The flash is the whole animation, so a
        // dropped frame leaves nothing behind on screen.
        layer.removeAllAnimations()
        layer.opacity = 0
        layer.borderWidth = FocusFlashGeometry.lineWidth

        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 1, 0]
        fade.keyTimes = [0, 0.16, 0.5, 1]
        fade.duration = FocusFlashGeometry.duration
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(fade, forKey: "flash")

        // Width, not scale: a scale animation turns on the layer anchor point,
        // which AppKit owns for a view's backing layer.
        let pulse = CABasicAnimation(keyPath: "borderWidth")
        pulse.fromValue = FocusFlashGeometry.pulseWidth
        pulse.toValue = FocusFlashGeometry.lineWidth
        pulse.duration = FocusFlashGeometry.duration * 0.45
        pulse.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(pulse, forKey: "pulse")

        generation += 1
        let token = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + FocusFlashGeometry.duration) { [weak self] in
            guard let self, self.generation == token else { return }
            self.panel?.orderOut(nil)
        }
    }

    private func makePanel() -> NSPanel {
        let box = NSView(frame: .zero)
        box.wantsLayer = true
        box.layer?.cornerCurve = .continuous
        box.layer?.backgroundColor = NSColor.clear.cgColor
        box.autoresizingMask = [.width, .height]

        let panel = FocusFlashPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        panel.isReleasedWhenClosed = false
        panel.contentView = box
        return panel
    }
}
