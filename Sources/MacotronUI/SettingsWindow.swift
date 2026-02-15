// SettingsWindow.swift — NSWindow wrapper for the settings panel
import AppKit
import SwiftUI

@MainActor
public final class SettingsWindow {
    private var window: NSWindow?
    private let settingsState: SettingsState

    public init(state: SettingsState) {
        self.settingsState = state
    }

    public func show() {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }

        settingsState.load()

        let settingsView = SettingsView(state: settingsState)
        let hostingView = NSHostingView(rootView: settingsView)

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 440),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = "Macotron Settings"
        w.contentView = hostingView
        w.center()
        w.isReleasedWhenClosed = false
        w.makeKeyAndOrderFront(nil)
        NSApp.activate()

        self.window = w
    }

    public func showWithAPIKeyRequired() {
        settingsState.showAPIKeyRequired = true
        show()
    }
}
