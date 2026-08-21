import AppKit
import MacotronEngine
import SwiftUI

public struct CatalogBrowser: View {
    let plugins: [CatalogPlugin]
    var installedNames: Set<String>
    var onInstall: (CatalogPlugin) -> Void
    var onPreview: (CatalogPlugin) -> Void

    @State private var query = ""

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
    var onInstall: () -> Void
    var onPreview: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(plugin.title)
                        .font(.system(size: 13, weight: .semibold))
                    if plugin.highlighted {
                        Text("Featured")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.orange)
                    }
                    Text(plugin.isStock ? "Stock" : "Demo")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Text(plugin.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Button("Preview") { onPreview() }
                .controlSize(.small)
            Button(installed ? "Reinstall…" : "Install…") { onInstall() }
                .controlSize(.small)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
    }
}

public struct CatalogInstallSheet: View {
    let plugin: CatalogPlugin
    var overwrite: CatalogOverwrite?
    var modelNote: String?
    var report: PluginScanReport?
    var scanning: Bool
    var isReview: Bool
    var grantedPermissions: Set<Permission>
    var onPermissionChange: () -> Void
    var onScan: () -> Void
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
            if let modelNote {
                Text(modelNote)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if scanning {
                ProgressView("Scanning with Apple Intelligence…")
            } else if let report {
                if report.approved {
                    Text("Automated checks passed.")
                        .foregroundStyle(.green)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Automated checks flagged this plugin.")
                            .foregroundStyle(.orange)
                        ForEach(report.staticFlags, id: \.self) { Text("• \($0)") }
                        ForEach(Array(report.findings.enumerated()), id: \.offset) { _, finding in
                            Text("• Pass \(finding.pass): \(finding.message)")
                        }
                    }
                    .font(.system(size: 12))
                }
            }
            if showSource {
                ScrollView {
                    Text(plugin.source)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 220)
            }
            HStack {
                Button(showSource ? "Hide Source" : "Preview Source") {
                    showSource.toggle()
                }
                Spacer()
                Button("Cancel", action: onCancel)
                if report == nil, !scanning {
                    Button("Scan & Continue") { onScan() }
                        .keyboardShortcut(.defaultAction)
                } else if let report, report.needsOverride {
                    Button(isReview ? "Run Anyway" : "Install Anyway") { onInstall(true) }
                        .keyboardShortcut(.defaultAction)
                } else if report?.approved == true {
                    Button(isReview ? "Reload" : "Install") { onInstall(false) }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 560)
    }
}
