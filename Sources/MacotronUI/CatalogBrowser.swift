import AppKit
import MacotronEngine
import SwiftUI

public struct CatalogBrowser: View {
    let plugins: [CatalogPlugin]
    var installedNames: Set<String>
    var onAdd: (CatalogPlugin) -> Void
    var onDetails: (CatalogPlugin) -> Void
    @State private var query = ""

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search plugins", text: $query)
                .textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(filtered) { plugin in
                        CatalogRow(
                            plugin: plugin,
                            installed: installedNames.contains(plugin.filename),
                            onAdd: { onAdd(plugin) },
                            onDetails: { onDetails(plugin) }
                        )
                    }
                }
            }
        }
    }

    private var filtered: [CatalogPlugin] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return plugins }
        return plugins.filter {
            $0.title.lowercased().contains(q)
                || $0.filename.lowercased().contains(q)
                || $0.description.lowercased().contains(q)
        }
    }
}

private struct CatalogRow: View {
    let plugin: CatalogPlugin
    let installed: Bool
    var onAdd: () -> Void
    var onDetails: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(plugin.title)
                        .font(.system(size: 13, weight: .semibold))
                    if plugin.highlighted {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.yellow)
                            .accessibilityLabel("Featured")
                    }
                }
                Text(plugin.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Button("Details…", action: onDetails)
            .controlSize(.small)
            Button(installed ? "Added" : "Add", action: onAdd)
            .controlSize(.small)
            .disabled(installed)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
    }
}

private struct CatalogInstallSheet: View {
    @ObservedObject var state: SettingsState
    let plugin: CatalogPlugin

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(plugin.title)
                .font(.title3.weight(.semibold))
            Text(plugin.description)
                .foregroundStyle(.secondary)
            if let overwrite = state.overwrite {
                Text(overwrite == .modified
                     ? "This replaces a plugin you already edited."
                     : "This replaces the installed copy of this built-in plugin.")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }
            if !plugin.permissions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Permissions")
                        .font(.headline)
                    ForEach(plugin.permissions) { permission in
                        PermissionRow(
                            permission: permission,
                            granted: state.grantedPermissions.contains(permission),
                            onChange: state.refreshPermissions
                        )
                    }
                }
            }
            scanStatus
            HStack {
                Button("View Source…") {
                    NSWorkspace.shared.open(plugin.fileURL)
                }
                Spacer()
                Button("Cancel") {
                    state.installTarget = nil
                    state.isReviewing = false
                }
                    .keyboardShortcut(.cancelAction)
                primaryButton
            }
            .padding(.top, 4)
        }
        .padding(20)
        .padding(.bottom, 6)
        .frame(width: 540)
    }

    /// The scan decides between the plain and the override wording, so until a
    /// report lands this shows the plain action.
    private var primaryLabel: String {
        let override = state.scanReport?.needsOverride == true
        if state.isReviewing { return override ? "Run Anyway" : "Reload" }
        return override ? "Add Anyway" : "Add"
    }

    /// Waiting on the scan is a recommendation, not a gate: the button stays
    /// live and only stops looking like the obvious thing to press. It goes
    /// back to being the default action once the scan comes back clean, so a
    /// queue of reviews can be walked through on Return.
    @ViewBuilder
    private var primaryButton: some View {
        let button = Button(primaryLabel) {
            install(override: state.scanReport?.needsOverride ?? true)
        }
        if state.scanReport?.approved == true || (state.scanReport == nil && state.installIsBuiltIn) {
            button
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        } else {
            button
        }
    }

    @ViewBuilder
    private var scanStatus: some View {
        if state.scanning {
            HStack(alignment: .center, spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Scanning with Apple Intelligence…")
            }
        } else if state.scanReport == nil, state.installIsBuiltIn {
            HStack(alignment: .center, spacing: 8) {
                scanBanner(
                    "checkmark.circle.fill",
                    "Plugin distributed with Macotron, no scan needed.",
                    .green
                )
                Spacer(minLength: 8)
                Button("Scan Anyway") {
                    state.scanInstallTarget()
                }
                    .controlSize(.small)
            }
        } else if let report = state.scanReport {
            VStack(alignment: .leading, spacing: 8) {
                if report.approved {
                    scanBanner(
                        "checkmark.circle.fill",
                        "Scanned for safety by AI. Looks good.",
                        .green
                    )
                } else {
                    if !report.modelAvailable {
                        scanBanner(
                            "exclamationmark.triangle.fill",
                            report.unavailableReason ?? "Apple Intelligence is unavailable.",
                            .orange
                        )
                    }
                    if !report.staticFlags.isEmpty || !report.findings.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            scanBanner(
                                "xmark.circle.fill",
                                "Automated checks failed.",
                                .red
                            )
                            ForEach(report.staticFlags, id: \.self) { flag in
                                Text("• \(flag)")
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            ForEach(Array(report.findings.enumerated()), id: \.offset) { _, finding in
                                Text("• Pass \(finding.pass): \(finding.message)")
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .font(.callout)
                        .foregroundStyle(.red)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func scanBanner(_ symbol: String, _ text: String, _ color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.title3)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(color)
    }

    private func install(override: Bool) {
        state.onInstallCatalog?(plugin, override)
        if !state.isReviewing {
            state.installTarget = nil
        }
    }
}

private struct CatalogInstaller: ViewModifier {
    @ObservedObject var state: SettingsState
    let enabled: Bool

    func body(content: Content) -> some View {
        content.sheet(item: Binding(
            get: { enabled ? state.installTarget : nil },
            set: { state.installTarget = $0 }
        ), onDismiss: {
            state.isReviewing = false
        }) { plugin in
            CatalogInstallSheet(
                state: state,
                plugin: plugin
            )
        }
    }
}

extension View {
    func catalogInstaller(state: SettingsState, enabled: Bool = true) -> some View {
        modifier(CatalogInstaller(state: state, enabled: enabled))
    }
}
