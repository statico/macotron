// SettingsWindow.swift — NSWindow wrapper for the settings panel
import MacotronEngine
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

    /// Default size. Resizable; the SwiftUI root fills the content view.
    private static let contentSize = NSSize(width: 760, height: 720)
    private static let minSize = NSSize(width: 640, height: 480)

    public func show() {
        // Switch to regular activation policy so the Edit menu appears (enables Cmd+V paste)
        NSApp.setActivationPolicy(.regular)

        settingsState.load()

        // Reuse the window after a close too, so it keeps one close observer.
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

        // Observe close to restore the correct activation policy
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: w,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                NSApp.setActivationPolicy(.accessory)
                if let obs = self?.closeObserver {
                    NotificationCenter.default.removeObserver(obs)
                    self?.closeObserver = nil
                }
            }
        }

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
