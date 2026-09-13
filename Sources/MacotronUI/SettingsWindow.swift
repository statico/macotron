// SettingsWindow.swift — NSWindow wrapper for the settings panel
import MacotronEngine
import AppKit
import SwiftUI

@MainActor
public final class SettingsWindow {
    private var window: NSWindow?
    private let settingsState: SettingsState

    public init(state: SettingsState) {
        self.settingsState = state
    }

    /// Default size. Resizable; the SwiftUI root fills the content view.
    private static let contentSize = NSSize(width: 760, height: 820)
    private static let minSize = NSSize(width: 640, height: 480)

    public func show() {
        // Regular activation policy so the Edit menu appears (enables Cmd+V paste)
        WindowActivationPolicy.borrowRegular()

        settingsState.load()

        // Reuse the window after a close. Its close observer is armed once, at
        // creation, and lives as long as the window does.
        if let window {
            bringToFront(window)
            return
        }

        let hostingView = NSHostingView(rootView: SettingsView(state: settingsState))
        hostingView.sizingOptions = []

        let w = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.title = "Macotron Settings"
        w.contentView = hostingView
        w.setContentSize(Self.contentSize)
        w.minSize = Self.minSize
        w.center()
        w.isReleasedWhenClosed = false
        bringToFront(w)

        WindowActivationPolicy.handBackWhenClosed(w)

        self.window = w
    }

    private func bringToFront(_ window: NSWindow) {
        AppActivation.activate("settings window")
        window.makeKeyAndOrderFront(nil)

        // The status bar menu is still closing on this pass and takes focus back
        // with it, so ask again once it has gone.
        DispatchQueue.main.async {
            AppActivation.activate("settings window")
            window.makeKeyAndOrderFront(nil)
        }
    }
}

/// Macotron is a menu bar app; .regular is borrowed for as long as a window of
/// ours is up, and handed back when that window closes.
@MainActor
enum WindowActivationPolicy {
    static func borrowRegular() {
        NSApp.setActivationPolicy(.regular)
    }

    /// Restores .accessory every time `window` closes. Arm it once per window:
    /// the observer holds nothing but the notification name, so it costs the
    /// same as the window it watches.
    static func handBackWhenClosed(_ window: NSWindow) {
        _ = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { _ = NSApp.setActivationPolicy(.accessory) }
        }
    }
}
