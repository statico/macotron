import AppKit
import MacotronEngine
import SwiftUI

public struct CatalogBrowser: View {
    let plugins: [CatalogPlugin]
    var installedNames: Set<String>
    var onInstall: (CatalogPlugin) -> Void
    var onPreview: (CatalogPlugin) -> Void

    @State private var query = ""
    @StateObject private var command = CommandHeld()

    public init(
        plugins: [CatalogPlugin],
        installedNames: Set<String>,
        onInstall: @escaping (CatalogPlugin) -> Void,
        onPreview: @escaping (CatalogPlugin) -> Void
    ) {
        self.plugins = plugins
        self.installedNames = installedNames
        self.onInstall = onInstall
        self.onPreview = onPreview
    }

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
                            commandHeld: command.isHeld,
                            onInstall: { onInstall(plugin) },
                            onPreview: { onPreview(plugin) }
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
    let commandHeld: Bool
    var onInstall: () -> Void
    var onPreview: () -> Void

    private var canReinstall: Bool { installed && commandHeld }

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
            Button("View Source") { onPreview() }
                .controlSize(.small)
            Button(canReinstall ? "Reinstall…" : installed ? "Installed" : "Install…") {
                onInstall()
            }
            .controlSize(.small)
            .disabled(installed && !canReinstall)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
    }
}

public struct CatalogInstallSheet: View {
    let plugin: CatalogPlugin
    var overwrite: CatalogOverwrite?
    var report: PluginScanReport?
    var scanning: Bool
    var isReview: Bool
    var grantedPermissions: Set<Permission>
    var onPermissionChange: () -> Void
    var onInstall: (Bool) -> Void
    var onCancel: () -> Void
    @State private var showSource = false

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(plugin.title)
                .font(.title3.weight(.semibold))
            Text(plugin.description)
                .foregroundStyle(.secondary)
            if let overwrite {
                Text(overwrite == .modified
                     ? "This replaces a plugin you already edited."
                     : "This replaces the installed copy of this stock plugin.")
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
                            granted: grantedPermissions.contains(permission),
                            onChange: onPermissionChange
                        )
                    }
                }
            }
            scanStatus
            if showSource {
                ScrollView {
                    Text(plugin.source)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Spacer(minLength: 0)
            }
            HStack {
                Button(showSource ? "Hide Source Code" : "Show Source Code") {
                    showSource.toggle()
                }
                Spacer()
                Button("Cancel", action: onCancel)
                if let report, report.needsOverride {
                    Button(isReview ? "Run Anyway" : "Install Anyway") { onInstall(true) }
                        .keyboardShortcut(.defaultAction)
                } else if report?.approved == true {
                    Button(isReview ? "Reload" : "Install") { onInstall(false) }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var scanStatus: some View {
        if scanning {
            ProgressView("Scanning with Apple Intelligence…")
        } else if let report {
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
                            ForEach(report.staticFlags, id: \.self) { Text("• \($0)") }
                            ForEach(Array(report.findings.enumerated()), id: \.offset) { _, finding in
                                Text("• Pass \(finding.pass): \(finding.message)")
                            }
                        }
                        .font(.callout)
                        .foregroundStyle(.red)
                    }
                }
            }
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
}
