// CatalogInstallWindow.swift — resizable window for catalog install and review
import AppKit
import SwiftUI

/// Closes on Escape, like the other Macotron dialogs.
private final class EscClosableWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        close()
    }
}

@MainActor
public final class CatalogInstallWindow: NSObject {
    private var window: NSWindow?
    private let state: SettingsState
    private var closeObserver: Any?

    /// Frame center held while the user drags an edge, so the dialog grows
    /// evenly on both sides instead of walking across the screen.
    private var resizeCenter: NSPoint?

    public init(state: SettingsState) {
        self.state = state
        super.init()
    }

    private static let contentSize = NSSize(width: 580, height: 540)
    private static let minSize = NSSize(width: 460, height: 320)

    public func show() {
        if let window {
            window.title = title
            bringToFront(window)
            return
        }

        let hostingView = NSHostingView(rootView: CatalogInstallView(state: state))
        hostingView.sizingOptions = []

        let w = EscClosableWindow(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.title = title
        w.contentView = hostingView
        w.setContentSize(Self.contentSize)
        w.contentMinSize = Self.minSize
        w.delegate = self
        w.isReleasedWhenClosed = false
        w.level = .floating
        w.center()
        bringToFront(w)

        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: w,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.teardown()
                self?.state.installTarget = nil
                self?.state.isReviewing = false
            }
        }

        window = w
    }

    public func close() {
        guard let w = window else { return }
        teardown()
        w.close()
    }

    private var title: String {
        state.isReviewing ? "Review Plugin" : "Install Plugin"
    }

    private func bringToFront(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Drops the window reference first, so closing does not re-enter through
    /// the willClose observer.
    private func teardown() {
        if let closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
        }
        closeObserver = nil
        window?.delegate = nil
        window = nil
    }
}

extension CatalogInstallWindow: NSWindowDelegate {
    public func windowWillStartLiveResize(_ notification: Notification) {
        guard let w = notification.object as? NSWindow else { return }
        resizeCenter = NSPoint(x: w.frame.midX, y: w.frame.midY)
    }

    public func windowDidResize(_ notification: Notification) {
        guard let w = notification.object as? NSWindow, let center = resizeCenter else { return }
        let origin = NSPoint(x: center.x - w.frame.width / 2, y: center.y - w.frame.height / 2)
        if origin != w.frame.origin {
            w.setFrameOrigin(origin)
        }
    }

    public func windowDidEndLiveResize(_ notification: Notification) {
        resizeCenter = nil
    }
}

/// Window contents. Reads the target from state so scan progress and findings
/// arrive without rebuilding the window.
struct CatalogInstallView: View {
    @ObservedObject var state: SettingsState

    var body: some View {
        if let plugin = state.installTarget {
            CatalogInstallSheet(
                plugin: plugin,
                overwrite: state.overwrite,
                report: state.scanReport,
                scanning: state.scanning,
                isReview: state.isReviewing,
                grantedPermissions: state.grantedPermissions,
                onPermissionChange: { state.refreshPermissions() },
                onInstall: { override in
                    state.onInstallCatalog?(plugin, override)
                    if !state.isReviewing {
                        state.installTarget = nil
                    }
                },
                onCancel: {
                    state.installTarget = nil
                    state.isReviewing = false
                }
            )
            .id(plugin.filename)
        } else {
            Color.clear
        }
    }
}
