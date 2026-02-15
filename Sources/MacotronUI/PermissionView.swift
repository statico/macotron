// PermissionView.swift — First-run permission dialog with instructions
import SwiftUI
import AppKit

public struct PermissionView: View {
    public var onOpenSettings: () -> Void
    public var onDismiss: () -> Void

    public init(onOpenSettings: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.onOpenSettings = onOpenSettings
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 40))
                .foregroundStyle(.blue)

            Text("Macotron Needs Accessibility Permission")
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)

            Text("Macotron uses Accessibility to manage windows, register global hotkeys, and automate your Mac. Without this permission, most features won't work.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                instructionRow(number: "1", text: "Click \"Open System Settings\" below")
                instructionRow(number: "2", text: "Find Macotron in the list and toggle it on")
                instructionRow(number: "3", text: "If prompted, enter your password to confirm")
            }
            .padding(.vertical, 4)

            HStack(spacing: 12) {
                Button("Later") {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Open System Settings") {
                    onOpenSettings()
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    @ViewBuilder
    private func instructionRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.caption)
                .fontWeight(.bold)
                .frame(width: 20, height: 20)
                .background(Circle().fill(.blue.opacity(0.15)))
            Text(text)
                .font(.callout)
        }
    }
}

@MainActor
public final class PermissionWindow {
    private var window: NSWindow?

    public init() {}

    public func show(onOpenSettings: @escaping () -> Void) {
        let view = PermissionView(
            onOpenSettings: onOpenSettings,
            onDismiss: { [weak self] in
                self?.window?.close()
            }
        )
        let hostingView = NSHostingView(rootView: view)

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 340),
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
}
