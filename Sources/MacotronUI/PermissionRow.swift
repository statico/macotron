// PermissionRow.swift — Shared permission status row for Settings and the wizard
import MacotronEngine
import SwiftUI

/// One permission with its status and a single action. The fixed status and
/// action widths keep every row aligned in a column.
struct PermissionRow: View {
    let permission: Permission
    let granted: Bool
    var showsReason: Bool = true

    /// Shared so every trailing control lines up on the same right edge.
    static let actionWidth: CGFloat = 104

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(granted ? Color.green : Color.orange)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 2) {
                Text(permission.title)
                    .font(.system(size: 12, weight: .medium))

                if showsReason {
                    Text(permission.reason)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 12)

            if granted {
                Text("Granted")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: Self.actionWidth, alignment: .trailing)
            } else {
                Button("Grant…") {
                    permission.request()
                    permission.openSystemSettings()
                }
                .controlSize(.small)
                .frame(width: Self.actionWidth, alignment: .trailing)
            }
        }
    }
}
