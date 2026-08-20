// SettingsView.swift — General prefs, plugins list, about
import AppKit
import MacotronEngine
import SwiftUI

/// One choice in a `dropdown` plugin option
public struct ModuleOptionChoice: Identifiable, Equatable {
    public let value: String
    public let label: String
    public var id: String { value }

    public init(value: String, label: String) {
        self.value = value
        self.label = label
    }
}

/// A configurable option exposed by a plugin
public struct ModuleOption: Identifiable {
    public let id: String
    public let key: String
    public let label: String
    public let type: String
    public let defaultValue: Any
    public var currentValue: Any
    public let required: Bool
    /// Whether the option currently has a usable value (Keychain secret for passwords).
    public let isSet: Bool
    public let choices: [ModuleOptionChoice]

    public init(key: String, label: String, type: String, defaultValue: Any, currentValue: Any,
                required: Bool = false, isSet: Bool = true, choices: [ModuleOptionChoice] = []) {
        self.id = key
        self.key = key
        self.label = label
        self.type = type
        self.defaultValue = defaultValue
        self.currentValue = currentValue
        self.required = required
        self.isSet = isSet
        self.choices = choices
    }

    /// Required but without a value — Settings surfaces a needs-setup hint.
    public var needsSetup: Bool { required && !isSet }
}

/// Summary info for a single plugin
public struct PluginCommandSummary: Identifiable, Equatable {
    public let id: String
    public let name: String
    public var shortcut: String

    public init(id: String, name: String, shortcut: String = "") {
        self.id = id
        self.name = name
        self.shortcut = shortcut
    }
}

public struct ModuleSummary: Identifiable {
    public let id: String
    public let filename: String
    public let title: String
    public let description: String
    public let options: [ModuleOption]
    public let events: [String]
    public let hotkeys: [PluginCommandSummary]
    public let help: String
    public let checks: [PluginCheck]
    public let hasErrors: Bool
    public let errorMessage: String?
    public let isEnabled: Bool
    public let commands: [PluginCommandSummary]
    public let permissions: [Permission]

    public var needsSetup: Bool { options.contains { $0.needsSetup } }
    public var hasFailedChecks: Bool { checks.contains { !$0.ok } }

    public init(filename: String, title: String = "", description: String,
                help: String = "", checks: [PluginCheck] = [],
                options: [ModuleOption] = [], events: [String] = [],
                hotkeys: [PluginCommandSummary] = [], hasErrors: Bool = false, errorMessage: String? = nil,
                isEnabled: Bool = true, commands: [PluginCommandSummary] = [],
                permissions: [Permission] = []) {
        self.id = filename
        self.filename = filename
        self.title = title.isEmpty ? String(filename.dropLast(3)) : title
        self.description = description
        self.help = help
        self.checks = checks
        self.options = options
        self.events = events
        self.hotkeys = hotkeys
        self.hasErrors = hasErrors
        self.errorMessage = errorMessage
        self.isEnabled = isEnabled
        self.commands = commands
        self.permissions = permissions
    }
}

public struct AppShortcutSummary: Identifiable {
    public let id: String
    public let name: String
    public let icon: NSImage?
    public var shortcut: String

    public init(id: String, name: String, icon: NSImage? = nil, shortcut: String = "") {
        self.id = id
        self.name = name
        self.icon = icon
        self.shortcut = shortcut
    }
}

@MainActor
public final class SettingsState: ObservableObject {
    @Published public var launcherHotkey: String = "cmd+space"
    @Published public var showDockIcon: Bool = true
    @Published public var showMenuBarIcon: Bool = true
    @Published public var launchAtLogin: Bool = false
    @Published public var appearance: AppearanceSetting = .system
    @Published public var textScale: Double = 1.0
    @Published public var launcherBackground: LauncherBackground = .translucent
    @Published public var moduleSummaries: [ModuleSummary] = []
    @Published public var appShortcuts: [AppShortcutSummary] = []
    @Published public var pluginsPath: String = ""
    @Published public var requestedTab: Int?
    @Published public var requestedPlugin: String?

    /// Baseline permissions plus whatever the loaded plugins declared.
    @Published public var requiredPermissions: [Permission] = Permissions.baseline
    @Published public var grantedPermissions: Set<Permission> = []

    public var readHotkey: (() -> String)?
    public var writeHotkey: ((String) -> Void)?
    public var readShowDockIcon: (() -> Bool)?
    public var writeShowDockIcon: ((Bool) -> Void)?
    public var readShowMenuBarIcon: (() -> Bool)?
    public var writeShowMenuBarIcon: ((Bool) -> Void)?
    public var readLaunchAtLogin: (() -> Bool)?
    public var writeLaunchAtLogin: ((Bool) -> Void)?
    public var readAppearance: (() -> AppearanceSetting)?
    public var writeAppearance: ((AppearanceSetting) -> Void)?
    public var readTextScale: (() -> Double)?
    public var writeTextScale: ((Double) -> Void)?
    public var readLauncherBackground: (() -> LauncherBackground)?
    public var writeLauncherBackground: ((LauncherBackground) -> Void)?
    public var loadModuleSummaries: (() -> [ModuleSummary])?
    public var loadAppShortcuts: (() -> [AppShortcutSummary])?
    public var searchInstalledApps: ((String) -> [AppShortcutSummary])?
    public var saveModuleOption: ((_ filename: String, _ key: String, _ value: Any) -> Void)?
    public var saveModuleSecret: ((_ filename: String, _ key: String, _ secret: String) -> Void)?
    public var clearModuleSecret: ((_ filename: String, _ key: String) -> Void)?
    public var setModuleEnabled: ((_ filename: String, _ enabled: Bool) -> Void)?
    public var saveCommandShortcut: ((_ commandId: String, _ combo: String) -> Void)?
    public var saveKeyboardShortcut: ((_ hotkeyId: String, _ combo: String) -> Void)?
    public var deleteModule: ((_ filename: String) -> Bool)?
    public var openModuleFile: ((_ filename: String) -> Void)?
    public var changePluginsFolder: (() -> Void)?
    public var openPluginsFolder: (() -> Void)?
    public var loadRequiredPermissions: (() -> [Permission])?
    public var configDirURL: URL?

    public init() {}

    public func load() {
        launcherHotkey = readHotkey?() ?? "cmd+space"
        showDockIcon = readShowDockIcon?() ?? true
        showMenuBarIcon = readShowMenuBarIcon?() ?? true
        launchAtLogin = readLaunchAtLogin?() ?? false
        appearance = readAppearance?() ?? .system
        textScale = readTextScale?() ?? 1.0
        launcherBackground = readLauncherBackground?() ?? .translucent
        pluginsPath = configDirURL?.path(percentEncoded: false) ?? ""
        refreshModules()
        refreshAppShortcuts()
        refreshPermissions()
    }

    public var missingPermissions: [Permission] {
        requiredPermissions.filter { !grantedPermissions.contains($0) }
    }

    /// Called on a timer and on every app switch, so only publish real changes.
    public func refreshPermissions() {
        let required = loadRequiredPermissions?() ?? Permissions.baseline
        let granted = Set(required.filter(\.isGranted))
        if required != requiredPermissions { requiredPermissions = required }
        if granted != grantedPermissions { grantedPermissions = granted }
    }

    public func refreshModules() {
        moduleSummaries = loadModuleSummaries?() ?? []
    }

    public func refreshAppShortcuts() {
        appShortcuts = loadAppShortcuts?() ?? []
    }

    public func saveHotkey() {
        writeHotkey?(launcherHotkey)
    }

    public func toggleDockIcon(_ value: Bool) {
        showDockIcon = value
        writeShowDockIcon?(value)
    }

    public func toggleMenuBarIcon(_ value: Bool) {
        showMenuBarIcon = value
        writeShowMenuBarIcon?(value)
    }

    /// Re-reads the system status so a failed registration reverts the toggle.
    public func toggleLaunchAtLogin(_ value: Bool) {
        writeLaunchAtLogin?(value)
        let actual = readLaunchAtLogin?() ?? false
        launchAtLogin = actual
        if actual != value {
            Task { @MainActor in
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = "Macotron could not \(value ? "enable" : "disable") launch at login."
                alert.informativeText = "Check System Settings → General → Login Items to approve or remove Macotron."
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }

    public func selectAppearance(_ value: AppearanceSetting) {
        appearance = value
        writeAppearance?(value)
    }

    public func selectTextScale(_ value: Double) {
        textScale = value
        writeTextScale?(value)
    }

    public func selectLauncherBackground(_ value: LauncherBackground) {
        launcherBackground = value
        writeLauncherBackground?(value)
    }
}

public struct SettingsView: View {
    @ObservedObject var state: SettingsState
    @State private var selectedTab: Int
    @State private var selectedPlugin: String?

    public init(state: SettingsState, initialTab: Int = 0) {
        self.state = state
        self._selectedTab = State(initialValue: initialTab)
    }

    private let labelWidth: CGFloat = 140
    private let githubPluginsURL = URL(string: "https://github.com/search?q=topic%3Amacotron-plugin&type=repositories")!

    public var body: some View {
        VStack(spacing: 0) {
            tabBar
                .padding(.top, 2)
                .padding(.bottom, 6)

            Divider()

            Group {
                switch selectedTab {
                case 1: pluginsTab
                case 2: shortcutsTab
                case 3: aboutTab
                default: generalTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            state.load()
            applySettingsRequest()
        }
        .onChange(of: state.requestedTab) { applySettingsRequest() }
        .onChange(of: state.requestedPlugin) { applySettingsRequest() }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            Spacer()
            tabButton(icon: "gearshape", label: "General", tag: 0)
            tabButton(icon: "puzzlepiece.extension", label: "Plugins", tag: 1)
            tabButton(icon: "command", label: "Shortcuts", tag: 2)
            tabButton(icon: "info.circle", label: "About", tag: 3)
            Spacer()
        }
    }

    private func applySettingsRequest() {
        if let tab = state.requestedTab {
            selectedTab = tab
            state.requestedTab = nil
        }
        if let file = state.requestedPlugin {
            selectedPlugin = file
            state.requestedPlugin = nil
        }
    }

    private func tabButton(icon: String, label: String, tag: Int) -> some View {
        let isSelected = selectedTab == tag
        return Button {
            selectedTab = tag
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .frame(height: 24)
                Text(label)
                    .font(.system(size: 10, weight: .medium))
            }
            .frame(width: 70, height: 48)
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.primary.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? .primary : .secondary)
    }

    private var generalTab: some View {
        ScrollView {
            VStack(spacing: 0) {
                permissionsSection

                formRow("Launch at Login") {
                    Toggle("Open Macotron when you log in", isOn: Binding(
                        get: { state.launchAtLogin },
                        set: { state.toggleLaunchAtLogin($0) }
                    ))
                    .toggleStyle(.checkbox)
                }

                formRow("Launcher Hotkey") {
                    HotkeyRecorderView(combo: $state.launcherHotkey) {
                        state.saveHotkey()
                    }
                    .frame(width: PluginForm.recorderWidth)
                }
                .zIndex(1)
                .padding(.top, 8)

                formDivider

                formRow("Dock Icon") {
                    Toggle("Show Dock icon", isOn: Binding(
                        get: { state.showDockIcon },
                        set: { state.toggleDockIcon($0) }
                    ))
                    .toggleStyle(.checkbox)
                    .disabled(!state.showMenuBarIcon)
                }

                formRow("Menu Bar Icon") {
                    Toggle("Show in menu bar", isOn: Binding(
                        get: { state.showMenuBarIcon },
                        set: { state.toggleMenuBarIcon($0) }
                    ))
                    .toggleStyle(.checkbox)
                    .disabled(!state.showDockIcon)
                }

                formRow("Appearance") {
                    Picker("", selection: Binding(
                        get: { state.appearance },
                        set: { state.selectAppearance($0) }
                    )) {
                        ForEach(AppearanceSetting.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 280, alignment: .leading)
                }

                formRow("Text Size") {
                    Picker("", selection: Binding(
                        get: { state.textScale },
                        set: { state.selectTextScale($0) }
                    )) {
                        Text("80%").tag(0.8)
                        Text("100%").tag(1.0)
                        Text("120%").tag(1.2)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 280, alignment: .leading)
                }

                formRow("Quick Search") {
                    Picker("", selection: Binding(
                        get: { state.launcherBackground },
                        set: { state.selectLauncherBackground($0) }
                    )) {
                        ForEach(LauncherBackground.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 340, alignment: .leading)
                }

                formDivider

                formRow("Plugins Folder") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(state.pluginsPath.isEmpty ? "(not set)" : state.pluginsPath)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)

                        HStack(spacing: 8) {
                            Button("Change…") {
                                state.changePluginsFolder?()
                                state.load()
                            }
                            .controlSize(.small)

                            Button("Open Folder") {
                                state.openPluginsFolder?()
                            }
                            .controlSize(.small)
                        }
                    }
                }
                .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Permissions

    private var permissionsSection: some View {
        let missing = state.missingPermissions

        return VStack(spacing: 0) {
            formRow("Permissions") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(permissionsSummary(missing: missing))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        Spacer(minLength: 12)

                        Button("Re-check") {
                            state.refreshPermissions()
                        }
                        .controlSize(.small)
                        .frame(width: PermissionRow.actionWidth, alignment: .trailing)
                    }

                    ForEach(state.requiredPermissions) { permission in
                        PermissionRow(
                            permission: permission,
                            granted: state.grantedPermissions.contains(permission),
                            onChange: { state.refreshPermissions() }
                        )
                    }
                }
            }
        }
        .background(missing.isEmpty ? Color.clear : Color.orange.opacity(0.08))
        .overlay(alignment: .bottom) { Divider() }
    }

    /// Not everything in this list is needed for Macotron to run — a plugin can
    /// ask for the fan helper — so the copy talks about approval, not working.
    private func permissionsSummary(missing: [Permission]) -> String {
        switch missing.count {
        case 0: return "Macotron has everything it needs."
        case 1: return "1 permission still needs your approval."
        default: return "\(missing.count) permissions still need your approval."
        }
    }

    private var pluginsTab: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                if state.moduleSummaries.isEmpty {
                    emptyPluginsPlaceholder
                } else {
                    ScrollView {
                        VStack(spacing: 1) {
                            ForEach(state.moduleSummaries) { summary in
                                let selected = selectedPlugin == summary.filename
                                Button {
                                    selectedPlugin = summary.filename
                                } label: {
                                    PluginListRow(summary: summary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 5)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(
                                            RoundedRectangle(cornerRadius: 5)
                                                .fill(selected ? Color.accentColor.opacity(0.18) : Color.clear)
                                        )
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(6)
                    }
                    .frame(maxHeight: .infinity)
                }

                Divider()

                HStack {
                    Button("Browse plugins on GitHub") {
                        NSWorkspace.shared.open(githubPluginsURL)
                    }
                    .controlSize(.small)
                    Spacer()
                }
                .padding(8)
            }
            .frame(width: 240)
            .frame(maxHeight: .infinity)

            Divider()

            if state.moduleSummaries.isEmpty {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let selected = state.moduleSummaries.first(where: { $0.filename == selectedPlugin }) {
                PluginDetailView(summary: selected, state: state)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Select a plugin")
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            state.refreshModules()
            selectInitialPlugin()
        }
        .onChange(of: state.moduleSummaries.map(\.filename)) {
            selectInitialPlugin()
        }
    }

    private var emptyPluginsPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("No plugins installed")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Add .js files to the plugins/ folder, or browse GitHub.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Prefer the first plugin that needs setup; otherwise keep the current
    /// selection while it still exists on disk.
    private func selectInitialPlugin() {
        let filenames = state.moduleSummaries.map(\.filename)
        if let selectedPlugin, filenames.contains(selectedPlugin) { return }
        selectedPlugin = state.moduleSummaries.first { summary in
            summary.options.contains { $0.needsSetup }
        }?.filename ?? filenames.first
    }

    private var shortcutsTab: some View {
        AppShortcutsTab(state: state)
    }

    private var aboutTab: some View {
        VStack(spacing: 16) {
            Spacer()

            if let bannerURL = Bundle.main.url(forResource: "banner", withExtension: "png"),
               let nsImage = NSImage(contentsOf: bannerURL) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 360)
            }

            Text("A thin macOS host for JavaScript plugins. Edit plugins with your coding agent — Macotron loads and runs them.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            Link(destination: URL(string: "https://github.com/statico/macotron")!) {
                HStack(spacing: 4) {
                    Image(systemName: "link")
                    Text("github.com/statico/macotron")
                }
                .font(.callout)
            }

            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    private func formRow<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: labelWidth, alignment: .leading)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }

    private var formDivider: some View {
        Divider()
            .padding(.leading, 24 + labelWidth + 12)
            .padding(.vertical, 4)
    }
}

private enum PluginForm {
    static let labelWidth: CGFloat = 140
    static let recorderWidth: CGFloat = 240
    static let fieldMaxWidth: CGFloat = 280
}

struct AppShortcutsTab: View {
    @ObservedObject var state: SettingsState
    @State private var query = ""
    @State private var matches: [AppShortcutSummary] = []
    @State private var pending: AppShortcutSummary?
    @State private var combo = ""

    var body: some View {
        VStack(spacing: 0) {
            addSection
            Divider()
            if state.appShortcuts.isEmpty {
                Text("No app shortcuts yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(state.appShortcuts) { app in
                        shortcutRow(app)
                    }
                }
                .listStyle(.inset)
            }
        }
        .onAppear { state.refreshAppShortcuts() }
    }

    private var addSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Launch or hide an app with a global hotkey. The same shortcut hides the app when it is already frontmost.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                TextField("Add an app…", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                    .onChange(of: query) { _, value in
                        if pending != nil, value != pending?.name {
                            pending = nil
                            combo = ""
                        }
                        matches = query.isEmpty ? [] : (state.searchInstalledApps?(query) ?? [])
                    }

                HotkeyRecorderView(combo: $combo) {}
                    .frame(width: PluginForm.recorderWidth)
                    .disabled(pending == nil)

                Button("Add") { addPending() }
                    .controlSize(.small)
                    .disabled(pending == nil || combo.isEmpty)
            }

            if let pending {
                HStack(spacing: 8) {
                    appIcon(pending)
                    Text(pending.name)
                        .font(.system(size: 12, weight: .medium))
                    Text("Record a shortcut, then Add.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            } else if !matches.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(matches.prefix(8)) { app in
                        Button {
                            pending = app
                            query = app.name
                            matches = []
                        } label: {
                            HStack(spacing: 8) {
                                appIcon(app)
                                Text(app.name)
                                    .font(.system(size: 12))
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .padding(16)
    }

    private func shortcutRow(_ app: AppShortcutSummary) -> some View {
        HStack(spacing: 10) {
            appIcon(app)
            Text(app.name)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 8)
            AppShortcutRecorder(app: app, state: state)
            Button("Remove") {
                state.saveCommandShortcut?(app.id, "")
                state.refreshAppShortcuts()
            }
            .controlSize(.small)
        }
        .padding(.vertical, 2)
    }

    private func addPending() {
        guard let pending, !combo.isEmpty else { return }
        state.saveCommandShortcut?(pending.id, combo)
        state.refreshAppShortcuts()
        self.pending = nil
        query = ""
        combo = ""
        matches = []
    }

    private func appIcon(_ app: AppShortcutSummary) -> some View {
        Group {
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "app")
                    .frame(width: 20, height: 20)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct AppShortcutRecorder: View {
    let app: AppShortcutSummary
    @ObservedObject var state: SettingsState
    @State private var combo = ""

    var body: some View {
        HotkeyRecorderView(combo: $combo) {
            state.saveCommandShortcut?(app.id, combo)
            state.refreshAppShortcuts()
        }
        .frame(width: PluginForm.recorderWidth)
        .onAppear { combo = app.shortcut }
        .onChange(of: app.shortcut) { _, newValue in
            combo = newValue
        }
    }
}

struct PluginListRow: View {
    let summary: ModuleSummary

    var body: some View {
        HStack(spacing: 8) {
            Text(summary.title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)

            Spacer(minLength: 4)

            if summary.hasErrors {
                Circle().fill(.red).frame(width: 6, height: 6)
            } else if summary.needsSetup || summary.hasFailedChecks {
                Circle().fill(.orange).frame(width: 6, height: 6)
            }
        }
        .padding(.vertical, 2)
        .opacity(summary.isEnabled ? 1 : 0.45)
    }
}

struct PluginDetailView: View {
    let summary: ModuleSummary
    @ObservedObject var state: SettingsState
    @State private var showDeleteAlert = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if summary.hasErrors { errorBox }
                if !summary.help.isEmpty { helpBox }
                if !summary.permissions.isEmpty { permissionsSection }
                if !summary.checks.isEmpty { checksSection }

                if !summary.isEnabled {
                    disabledHint
                } else {
                    if !summary.events.isEmpty { badges }
                    if !summary.hotkeys.isEmpty { hotkeysSection }
                    if !summary.commands.isEmpty { commandsSection }
                    if !summary.options.isEmpty { settingsSection }
                }

                Divider()

                HStack {
                    Spacer()
                    Button("Delete Plugin…", role: .destructive) {
                        showDeleteAlert = true
                    }
                    .controlSize(.small)
                }
            }
            .padding(20)
        }
        .alert("Delete Plugin?", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if state.deleteModule?(summary.filename) == true {
                    state.refreshModules()
                }
            }
        } message: {
            Text("Delete \(summary.title)? This cannot be undone.")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(summary.title)
                        .font(.system(size: 16, weight: .semibold))
                    if summary.needsSetup && summary.isEnabled {
                        detailBadge(text: "Needs setup", color: .orange)
                    }
                    if summary.hasFailedChecks && summary.isEnabled {
                        detailBadge(text: "Warning", color: .orange)
                    }
                }
                if !summary.description.isEmpty {
                    Text(summary.description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            Toggle("Enabled", isOn: Binding(
                get: { summary.isEnabled },
                set: { state.setModuleEnabled?(summary.filename, $0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)

            Button("Open") {
                state.openModuleFile?(summary.filename)
            }
            .controlSize(.small)
        }
    }

    private var errorBox: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
            Text(summary.errorMessage ?? "Plugin has errors")
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.red)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08))
        .cornerRadius(6)
    }

    private var helpBox: some View {
        Text(summary.help)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var permissionsSection: some View {
        pluginSection("Permissions") {
            ForEach(summary.permissions) { permission in
                PermissionRow(
                    permission: permission,
                    granted: state.grantedPermissions.contains(permission),
                    onChange: { state.refreshPermissions() }
                )
            }
        }
    }

    private var checksSection: some View {
        pluginSection("Checks") {
            ForEach(Array(summary.checks.enumerated()), id: \.offset) { _, check in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: check.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(check.ok ? Color.green : Color.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(check.title)
                            .font(.system(size: 12, weight: .medium))
                        if !check.message.isEmpty {
                            Text(check.message)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private var disabledHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "pause.circle")
            Text("This plugin is disabled. Enable it to run its commands and edit its settings.")
                .font(.system(size: 11))
        }
        .foregroundStyle(.secondary)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(6)
    }

    private var badges: some View {
        HStack(spacing: 4) {
            ForEach(summary.events, id: \.self) { event in
                detailBadge(text: event, color: .purple)
            }
        }
    }

    private var hotkeysSection: some View {
        pluginSection("Shortcuts") {
            ForEach(summary.hotkeys) { hotkey in
                CommandShortcutRow(command: hotkey) { id, combo in
                    state.saveKeyboardShortcut?(id, combo)
                    state.refreshModules()
                }
            }
        }
    }

    private var commandsSection: some View {
        pluginSection("Commands") {
            ForEach(summary.commands) { command in
                CommandShortcutRow(command: command) { id, combo in
                    state.saveCommandShortcut?(id, combo)
                    state.refreshModules()
                }
            }
        }
    }

    private var settingsSection: some View {
        pluginSection("Settings") {
            ForEach(summary.options) { option in
                ModuleOptionRow(option: option, filename: summary.filename, state: state)
            }
        }
    }

    private func pluginSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func detailBadge(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .cornerRadius(3)
    }
}

struct ModuleOptionRow: View {
    let option: ModuleOption
    let filename: String
    @ObservedObject var state: SettingsState

    @State private var stringValue: String = ""
    @State private var boolValue: Bool = false
    @State private var numberValue: String = ""
    @State private var hotkeyValue: String = ""
    @State private var passwordValue: String = ""

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            labelText
                .frame(width: PluginForm.labelWidth, alignment: .leading)
            control
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var control: some View {
        switch option.type {
        case "boolean":
            Toggle("", isOn: $boolValue)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .onAppear { boolValue = (option.currentValue as? Bool) ?? false }
                .onChange(of: boolValue) {
                    state.saveModuleOption?(filename, option.key, boolValue)
                    state.refreshModules()
                }
        case "number":
            TextField("", text: $numberValue)
                .font(.system(size: 12, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
                .onAppear { numberValue = "\(option.currentValue)" }
                .onSubmit {
                    if let num = Double(numberValue) {
                        state.saveModuleOption?(filename, option.key, num)
                        state.refreshModules()
                    }
                }
        case "keybinding":
            HotkeyRecorderView(combo: $hotkeyValue) {
                state.saveModuleOption?(filename, option.key, hotkeyValue)
                state.refreshModules()
            }
            .frame(width: PluginForm.recorderWidth)
            .onAppear { hotkeyValue = (option.currentValue as? String) ?? "" }
        case "dropdown":
            if option.choices.isEmpty {
                Text("No choices defined")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            } else {
                Picker("", selection: Binding(
                    get: { (option.currentValue as? String) ?? "" },
                    set: { newValue in
                        guard !newValue.isEmpty else { return }
                        state.saveModuleOption?(filename, option.key, newValue)
                        state.refreshModules()
                    }
                )) {
                    ForEach(option.choices) { choice in
                        Text(choice.label).tag(choice.value)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
            }
        case "password":
            HStack(spacing: 8) {
                SecureField("Enter value", text: $passwordValue)
                    .font(.system(size: 12, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                Button("Set") {
                    state.saveModuleSecret?(filename, option.key, passwordValue)
                    passwordValue = ""
                    state.refreshModules()
                }
                .controlSize(.small)
                .disabled(passwordValue.isEmpty)
                if option.isSet {
                    Button("Clear") {
                        state.clearModuleSecret?(filename, option.key)
                        state.refreshModules()
                    }
                    .controlSize(.small)
                }
                Text(option.isSet ? "Set" : "Not set")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(option.isSet ? .green : .secondary)
            }
        case "file", "directory":
            HStack(spacing: 8) {
                let path = (option.currentValue as? String) ?? ""
                Text(path.isEmpty ? "Not set" : path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(path.isEmpty ? .tertiary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: PluginForm.fieldMaxWidth, alignment: .leading)
                    .help(path)
                Button("Choose…") {
                    choosePath()
                }
                .controlSize(.small)
            }
        default:
            TextField("", text: $stringValue)
                .font(.system(size: 12, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: PluginForm.fieldMaxWidth)
                .onAppear { stringValue = (option.currentValue as? String) ?? "" }
                .onSubmit {
                    state.saveModuleOption?(filename, option.key, stringValue)
                    state.refreshModules()
                }
        }
    }

    private var labelText: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(option.label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if option.needsSetup {
                Text("Required")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.orange)
            }
        }
    }

    private func choosePath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = option.type == "file"
        panel.canChooseDirectories = option.type == "directory"
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        state.saveModuleOption?(filename, option.key, url.path(percentEncoded: false))
        state.refreshModules()
    }
}

struct CommandShortcutRow: View {
    let command: PluginCommandSummary
    var onSave: (String, String) -> Void
    @State private var combo: String = ""

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(command.name)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(width: PluginForm.labelWidth, alignment: .leading)
            HotkeyRecorderView(combo: $combo) {
                onSave(command.id, combo)
            }
            .frame(width: PluginForm.recorderWidth)
            Spacer(minLength: 0)
        }
        .onAppear { combo = command.shortcut }
        .onChange(of: command.shortcut) { _, newValue in
            combo = newValue
        }
    }
}
