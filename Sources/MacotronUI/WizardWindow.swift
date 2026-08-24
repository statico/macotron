// WizardWindow.swift — NSWindow wrapper for the first-run wizard
import MacotronEngine
import AppKit
import SwiftUI

/// NSWindow subclass that closes on Escape key
private class EscClosableWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        close()
    }
}

@MainActor
public final class WizardWindow {
    private var window: NSWindow?
    private let wizardState: WizardState
    private let permissionsState: SettingsState

    public init(state: WizardState, permissions: SettingsState) {
        self.wizardState = state
        self.permissionsState = permissions
    }

    public var isVisible: Bool { window?.isVisible ?? false }

    /// The window is not resizable, so the content is pinned to this size. The
    /// root view fills its parent, which would otherwise grow the window to the
    /// full height of the screen.
    private static let contentSize = NSSize(width: 640, height: 720)

    public func show() {
        if let window, window.isVisible {
            AppActivation.activate("setup wizard")
            window.makeKeyAndOrderFront(nil)
            return
        }

        // Must be .regular before creating the window so it can become key
        NSApp.setActivationPolicy(.regular)

        let wizardView = WizardView(state: wizardState, permissions: permissionsState)
            .frame(width: Self.contentSize.width, height: Self.contentSize.height)
        let hostingView = NSHostingView(rootView: wizardView)

        let w = EscClosableWindow(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = "Macotron Setup"
        w.contentView = hostingView
        w.setContentSize(Self.contentSize)
        w.center()
        w.isReleasedWhenClosed = false
        w.level = .floating
        AppActivation.activate("setup wizard")
        w.makeKeyAndOrderFront(nil)

        // First launch starts as accessory; drop the floating level once we are key.
        DispatchQueue.main.async {
            w.level = .normal
            AppActivation.activate("setup wizard")
            w.makeKeyAndOrderFront(nil)
        }

        self.window = w
    }

    public func close() {
        window?.close()
        window = nil
    }
}
