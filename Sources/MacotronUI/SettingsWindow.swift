// SettingsWindow.swift — NSWindow wrapper for the settings panel
import AppKit
import SwiftUI

@MainActor
public final class SettingsWindow {
    private var window: NSWindow?
    private let settingsState: SettingsState
    private var closeObserver: Any?

    public init(state: SettingsState) {
        self.settingsState = state
    }

    public func show() {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }

        // Switch to regular activation policy so the Edit menu appears (enables Cmd+V paste)
        NSApp.setActivationPolicy(.regular)

        settingsState.load()

        let settingsView = SettingsView(state: settingsState)
        let hostingView = NSHostingView(rootView: settingsView)

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
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

        // Observe close to restore the correct activation policy
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: w,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                // Only revert to accessory mode if the user doesn't want a dock icon
                if !(self?.settingsState.showDockIcon ?? true) {
                    NSApp.setActivationPolicy(.accessory)
                }
                if let obs = self?.closeObserver {
                    NotificationCenter.default.removeObserver(obs)
                    self?.closeObserver = nil
                }
            }
        }

        self.window = w
    }

    public func showWithAPIKeyRequired() {
        settingsState.showAPIKeyRequired = true
        show()
    }
}
