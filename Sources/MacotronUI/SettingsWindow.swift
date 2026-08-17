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

    /// The window is not resizable, so the content is pinned to this size. The
    /// root view fills its parent, which would otherwise grow the window to the
    /// full height of the screen.
    private static let contentSize = NSSize(width: 660, height: 460)

    public func show() {
        // Switch to regular activation policy so the Edit menu appears (enables Cmd+V paste)
        NSApp.setActivationPolicy(.regular)

        settingsState.load()

        // Reuse the window after a close too, so it keeps one close observer.
        if let window {
            bringToFront(window)
            return
        }

        let settingsView = SettingsView(state: settingsState)
            .frame(width: Self.contentSize.width, height: Self.contentSize.height)
        let hostingView = NSHostingView(rootView: settingsView)

        let w = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = "Macotron Settings"
        w.contentView = hostingView
        w.setContentSize(Self.contentSize)
        w.center()
        w.isReleasedWhenClosed = false
        bringToFront(w)

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

    private func bringToFront(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        // The status bar menu is still closing on this pass and takes focus back
        // with it, so ask again once it has gone.
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }
}
