// WizardWindow.swift — NSWindow wrapper for the first-run wizard
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
    private static let contentSize = NSSize(width: 560, height: 520)

    public func show() {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
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
        w.makeKeyAndOrderFront(nil)

        // Force activation — necessary on first launch when the app starts as accessory
        NSApp.activate()
        DispatchQueue.main.async {
            w.level = .normal
            w.makeKeyAndOrderFront(nil)
            NSApp.activate()
        }

        self.window = w
    }

    public func close() {
        window?.close()
        window = nil
    }
}
