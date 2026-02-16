// WizardWindow.swift — NSWindow wrapper for the first-run wizard
import AppKit
import SwiftUI

@MainActor
public final class WizardWindow {
    private var window: NSWindow?
    private let wizardState: WizardState

    public init(state: WizardState) {
        self.wizardState = state
    }

    public func show() {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }

        NSApp.setActivationPolicy(.regular)

        let wizardView = WizardView(state: wizardState)
        let hostingView = NSHostingView(rootView: wizardView)

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = "Macotron Setup"
        w.contentView = hostingView
        w.center()
        w.isReleasedWhenClosed = false
        w.makeKeyAndOrderFront(nil)
        NSApp.activate()

        self.window = w
    }

    public func close() {
        window?.close()
        window = nil
    }
}
