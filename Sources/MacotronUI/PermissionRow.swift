// PermissionRow.swift — Shared permission status row for Settings and the wizard
import MacotronEngine
import SwiftUI

/// One permission with its status and a single action. A fixed text column
/// keeps every row the same width so the action lines up without a spacer.
struct PermissionRow: View {
    let permission: Permission
    let granted: Bool
    /// Called after the row changes anything, so the status refreshes at once
    /// instead of waiting for the next poll.
    var onChange: (() -> Void)?

    static let textWidth: CGFloat = 240
    static let actionWidth: CGFloat = 104

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(granted ? Color.green : Color.orange)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 2) {
                Text(permission.title)
                    .font(.system(size: 12, weight: .medium))

                Text(permission.reason)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: Self.textWidth, alignment: .leading)

            if granted, permission.canRevoke {
                Menu("Installed") {
                    if permission.canReinstall {
                        Button("Reinstall…") {
                            if permission.reinstall() { permission.openSystemSettings() }
                            onChange?()
                        }
                    }
                    Button("Remove") {
                        permission.revoke()
                        onChange?()
                    }
                }
                .menuStyle(.button)
                .controlSize(.small)
                .fixedSize()
                .frame(width: Self.actionWidth, alignment: .leading)
            } else if granted {
                Text("Granted")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: Self.actionWidth, alignment: .leading)
            } else {
                Button(permission.actionTitle) {
                    if permission.request() { permission.openSystemSettings() }
                    onChange?()
                }
                .controlSize(.small)
                .frame(width: Self.actionWidth, alignment: .leading)
            }
        }
    }
}
