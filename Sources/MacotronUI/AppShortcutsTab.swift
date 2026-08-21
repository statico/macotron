import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum AppShortcutDraft {
    static func canSubmit(appID: String?, combo: String, existing: Set<String>) -> Bool {
        guard let appID, !appID.isEmpty, !combo.isEmpty else { return false }
        return !existing.contains(appID)
    }

    static func summary(from url: URL) -> AppShortcutSummary? {
        let resolved = url.resolvingSymlinksInPath()
        guard let bundle = Bundle(url: resolved),
              let bundleID = bundle.bundleIdentifier else { return nil }
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? resolved.deletingPathExtension().lastPathComponent
        let icon = NSWorkspace.shared.icon(forFile: resolved.path(percentEncoded: false))
        return AppShortcutSummary(id: bundleID, name: name, icon: icon)
    }
}

struct AppShortcutsTab: View {
    @ObservedObject var state: SettingsState
    @State private var selection: AppShortcutSummary.ID?
    @State private var adding = false

    var body: some View {
        VStack(spacing: 0) {
            Table(state.appShortcuts, selection: $selection) {
                TableColumn("Application") { app in
                    HStack(spacing: 8) {
                        appIcon(app, size: 20)
                        Text(app.name)
                            .lineLimit(1)
                    }
                }
                TableColumn("Shortcut") { app in
                    ShortcutField(
                        shortcut: app.shortcut,
                        conflict: state.shortcutWarning(id: "app:\(app.id)", combo: app.shortcut)
                    ) { combo in
                        state.saveCommandShortcut?(app.id, combo)
                        state.refreshAppShortcuts()
                    }
                        .frame(minWidth: 180)
                }
                .width(ideal: 220, max: 280)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: false))
            .overlay {
                if state.appShortcuts.isEmpty {
                    VStack(spacing: 4) {
                        Text("No App Shortcuts")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("Click Add (+) to choose an application, then record a shortcut.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding()
                    .allowsHitTesting(false)
                }
            }
            .onDeleteCommand(perform: removeSelected)

            Divider()

            HStack(spacing: 10) {
                plusMinus
                Spacer(minLength: 8)
                Text("The same shortcut hides the app when it is already frontmost.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .onAppear { state.refreshAppShortcuts() }
        .sheet(isPresented: $adding) {
            AddAppShortcutSheet(state: state) { app, combo in
                state.saveCommandShortcut?(app.id, combo)
                state.refreshAppShortcuts()
                selection = app.id
                adding = false
            }
        }
    }

    private var plusMinus: some View {
        HStack(spacing: 0) {
            Button(action: { adding = true }) {
                Image(systemName: "plus")
                    .frame(width: 28, height: 22)
            }
            .help("Add")
            .accessibilityLabel("Add")

            Divider()
                .frame(height: 14)

            Button(action: removeSelected) {
                Image(systemName: "minus")
                    .frame(width: 28, height: 22)
            }
            .disabled(selection == nil)
            .help("Remove")
            .accessibilityLabel("Remove")
        }
        .buttonStyle(.borderless)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                }
        }
    }

    private func removeSelected() {
        guard let selection else { return }
        state.saveCommandShortcut?(selection, "")
        state.refreshAppShortcuts()
        self.selection = nil
    }
}

private struct AddAppShortcutSheet: View {
    @ObservedObject var state: SettingsState
    var onAdd: (AppShortcutSummary, String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var selectedID: String?
    @State private var picked: AppShortcutSummary?
    @State private var combo = ""

    private var existing: Set<String> {
        Set(state.appShortcuts.map(\.id))
    }

    private var results: [AppShortcutSummary] {
        var hits = state.searchInstalledApps?(query) ?? []
        if let picked, !hits.contains(where: { $0.id == picked.id }) {
            hits.insert(picked, at: 0)
        }
        return hits
    }

    private var selected: AppShortcutSummary? {
        results.first(where: { $0.id == selectedID }) ?? picked
    }

    private var canAdd: Bool {
        AppShortcutDraft.canSubmit(appID: selected?.id, combo: combo, existing: existing)
    }

    private var duplicateSelected: Bool {
        guard let id = selected?.id else { return false }
        return existing.contains(id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add App Shortcut")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Application")
                    .foregroundStyle(.secondary)
                TextField("Search", text: $query)
                    .textFieldStyle(.roundedBorder)
                List(results, selection: $selectedID) { app in
                    HStack(spacing: 8) {
                        appIcon(app, size: 24)
                        Text(app.name)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if existing.contains(app.id) {
                            Text("Added")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .tag(app.id)
                    .contentShape(Rectangle())
                }
                .listStyle(.inset)
                .frame(minHeight: 180)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                }

                HStack {
                    Button("Other…", action: pickFromPanel)
                    if duplicateSelected {
                        Text("This application already has a shortcut.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Keyboard Shortcut")
                    .foregroundStyle(.secondary)
                HotkeyRecorderView(combo: $combo, onSave: {})
                ShortcutConflictNote(message: state.shortcutWarning(id: "app-draft", combo: combo))
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    guard let selected, canAdd else { return }
                    onAdd(selected, combo)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canAdd)
            }
        }
        .padding(20)
        .frame(width: 440, height: 460)
    }

    private func pickFromPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.prompt = "Choose"
        panel.message = "Choose an application"
        guard panel.runModal() == .OK, let url = panel.url,
              let app = AppShortcutDraft.summary(from: url) else { return }
        picked = app
        selectedID = app.id
        query = app.name
    }
}

private func appIcon(_ app: AppShortcutSummary, size: CGFloat) -> some View {
    Group {
        if let icon = app.icon {
            Image(nsImage: icon)
                .resizable()
                .frame(width: size, height: size)
        } else {
            Image(systemName: "app")
                .frame(width: size, height: size)
                .foregroundStyle(.secondary)
        }
    }
}
