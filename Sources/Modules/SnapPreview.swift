// SnapPreview.swift — translucent rounded box over the destination frame
import AppKit

private final class SnapPreviewPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class SnapPreview {
    static let shared = SnapPreview()
    static let fade: TimeInterval = 0.12

    private var panel: NSPanel?
    private var generation = 0

    func show(_ rect: CGRect) {
        generation += 1
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let appearing = !panel.isVisible || panel.alphaValue < 0.05
        panel.setFrame(rect, display: true)
        if appearing {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = Self.fade
                panel.animator().alphaValue = 1
            }
        } else {
            panel.orderFrontRegardless()
        }
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        generation += 1
        let token = generation
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Self.fade
            panel.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor in
                if token == self.generation {
                    panel.orderOut(nil)
                }
            }
        }
    }

    private func makePanel() -> NSPanel {
        let box = NSView(frame: .zero)
        box.wantsLayer = true
        box.layer?.cornerRadius = 12
        box.layer?.cornerCurve = .continuous
        box.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.28).cgColor
        box.layer?.borderWidth = 2
        box.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.8).cgColor
        box.autoresizingMask = [.width, .height]

        let panel = SnapPreviewPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
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
