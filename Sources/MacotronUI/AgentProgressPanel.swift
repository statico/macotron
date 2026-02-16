// AgentProgressPanel.swift — Floating NSPanel for agent progress display
import AppKit
import SwiftUI

@MainActor
public final class AgentProgressPanel {
    private var panel: NSPanel?
    private let state = AgentProgressState()
    private var dismissTask: Task<Void, Never>?

    public init() {}

    /// Show the panel with a new topic, resetting state
    public func show(topic: String) {
        dismissTask?.cancel()
        state.reset(topic: topic)

        if let panel, panel.isVisible {
            // Already visible — just update state
            return
        }

        let hostingView = NSHostingView(rootView: AgentProgressView(state: state))

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 80),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        p.level = .floating
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.animationBehavior = .utilityWindow
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.becomesKeyOnlyIfNeeded = true
        p.hidesOnDeactivate = false

        // Vibrancy background
        let visual = NSVisualEffectView(frame: .zero)
        visual.material = .hudWindow
        visual.state = .active
        visual.blendingMode = .behindWindow
        visual.wantsLayer = true
        visual.layer?.cornerRadius = 12
        visual.layer?.masksToBounds = true
        visual.autoresizingMask = [.width, .height]

        hostingView.frame = visual.bounds
        hostingView.autoresizingMask = [.width, .height]
        visual.addSubview(hostingView)

        p.contentView = visual

        // Position bottom-right of screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.maxX - 320 - 16
            let y = screenFrame.minY + 16
            p.setFrameOrigin(NSPoint(x: x, y: y))
        }

        p.orderFront(nil)
        self.panel = p
    }

    /// Update the panel with agent progress
    public func update(_ statusText: String) {
        state.statusText = statusText
    }

    /// Mark as complete and schedule auto-dismiss
    public func complete(success: Bool, summary: String) {
        state.statusText = summary
        state.isComplete = true
        state.success = success

        let delay: UInt64 = success ? 3_000_000_000 : 5_000_000_000
        dismissTask = Task {
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            self.dismiss()
        }
    }

    /// Dismiss the panel immediately
    public func dismiss() {
        dismissTask?.cancel()
        panel?.orderOut(nil)
        panel = nil
    }
}
