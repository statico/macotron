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
public struct ModuleSummary: Identifiable {
    public let id: String
    public let filename: String
    public let title: String
    public let description: String
    public let options: [ModuleOption]
    public let events: [String]
    public let hotkeys: [String]
    public let hasErrors: Bool
    public let errorMessage: String?
    public let isEnabled: Bool

    public init(filename: String, title: String = "", description: String,
                options: [ModuleOption] = [], events: [String] = [],
                hotkeys: [String] = [], hasErrors: Bool = false, errorMessage: String? = nil,
                isEnabled: Bool = true) {
        self.id = filename
        self.filename = filename
        self.title = title.isEmpty ? String(filename.dropLast(3)) : title
        self.description = description
        self.options = options
        self.events = events
        self.hotkeys = hotkeys
        self.hasErrors = hasErrors
        self.errorMessage = errorMessage
        self.isEnabled = isEnabled
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
    @Published public var moduleSummaries: [ModuleSummary] = []
    @Published public var pluginsPath: String = ""
    @Published public var requestedTab: Int?

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
    public var loadModuleSummaries: (() -> [ModuleSummary])?
    public var saveModuleOption: ((_ filename: String, _ key: String, _ value: Any) -> Void)?
    public var saveModuleSecret: ((_ filename: String, _ key: String, _ secret: String) -> Void)?
    public var clearModuleSecret: ((_ filename: String, _ key: String) -> Void)?
    public var setModuleEnabled: ((_ filename: String, _ enabled: Bool) -> Void)?
    public var deleteModule: ((_ filename: String) -> Bool)?
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
        pluginsPath = configDirURL?.path(percentEncoded: false) ?? ""
        refreshModules()
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
        launchAtLogin = readLaunchAtLogin?() ?? false
    }

    public func selectAppearance(_ value: AppearanceSetting) {
        appearance = value
        writeAppearance?(value)
    }

    public func selectTextScale(_ value: Double) {
        textScale = value
        writeTextScale?(value)
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

            switch selectedTab {
            case 1: pluginsTab
            case 2: aboutTab
            default: generalTab
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            state.load()
            if let tab = state.requestedTab {
                selectedTab = tab
                state.requestedTab = nil
            }
        }
        .onChange(of: state.requestedTab) {
            if let tab = state.requestedTab {
                selectedTab = tab
                state.requestedTab = nil
            }
        }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            Spacer()
            tabButton(icon: "gearshape", label: "General", tag: 0)
            tabButton(icon: "puzzlepiece.extension", label: "Plugins", tag: 1)
            tabButton(icon: "info.circle", label: "About", tag: 2)
            Spacer()
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
                .frame(width: 240)
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
                .frame(width: 240)
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

            Spacer()
        }
    }

    // MARK: - Permissions

    private var permissionsSection: some View {
        let missing = state.missingPermissions

        return VStack(spacing: 0) {
            formRow("Permissions") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(missing.isEmpty
                             ? "Macotron has everything it needs."
                             : "Macotron needs \(missing.count == 1 ? "1 permission" : "\(missing.count) permissions") to work.")
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
                            granted: state.grantedPermissions.contains(permission)
                        )
                    }
                }
            }
        }
        .background(missing.isEmpty ? Color.clear : Color.orange.opacity(0.08))
        .overlay(alignment: .bottom) { Divider() }
    }

    private var pluginsTab: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                if state.moduleSummaries.isEmpty {
                    emptyPluginsPlaceholder
                } else {
                    List(selection: $selectedPlugin) {
                        ForEach(state.moduleSummaries) { summary in
                            PluginListRow(summary: summary)
                                .tag(summary.filename)
                        }
                    }
                    .listStyle(.sidebar)
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
            .frame(width: 210)

            Divider()

            if let selected = state.moduleSummaries.first(where: { $0.filename == selectedPlugin }) {
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
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: labelWidth, alignment: .trailing)

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

struct PluginListRow: View {
    let summary: ModuleSummary

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(summary.filename)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            if summary.hasErrors {
                Circle().fill(.red).frame(width: 6, height: 6)
            } else if summary.options.contains(where: { $0.needsSetup }) {
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

    private var needsSetup: Bool {
        summary.options.contains { $0.needsSetup }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                if !summary.description.isEmpty {
                    Text(summary.description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if summary.hasErrors { errorBox }

                if !summary.isEnabled {
                    disabledHint
                } else {
                    if !summary.hotkeys.isEmpty || !summary.events.isEmpty { badges }
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
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.title)
                    .font(.system(size: 15, weight: .semibold))
                Text(summary.filename)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            if needsSetup && summary.isEnabled {
                Text("Needs setup")
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.12))
                    .foregroundStyle(.orange)
                    .cornerRadius(3)
            }

            Spacer()

            Toggle("Enabled", isOn: Binding(
                get: { summary.isEnabled },
                set: { state.setModuleEnabled?(summary.filename, $0) }
            ))
            .toggleStyle(.switch)
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
            ForEach(summary.hotkeys, id: \.self) { hotkey in
                detailBadge(text: hotkey, color: .blue)
            }
            ForEach(summary.events, id: \.self) { event in
                detailBadge(text: event, color: .purple)
            }
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Settings")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            ForEach(summary.options) { option in
                ModuleOptionRow(option: option, filename: summary.filename, state: state)
            }
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
        Group {
            switch option.type {
            case "boolean":
                Toggle(option.label, isOn: $boolValue)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
                    .onAppear { boolValue = (option.currentValue as? Bool) ?? false }
                    .onChange(of: boolValue) {
                        state.saveModuleOption?(filename, option.key, boolValue)
                        state.refreshModules()
                    }
            case "number":
                HStack(spacing: 8) {
                    labelText
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
                }
            case "keybinding":
                HStack(spacing: 8) {
                    labelText
                    HotkeyRecorderView(combo: $hotkeyValue) {
                        state.saveModuleOption?(filename, option.key, hotkeyValue)
                        state.refreshModules()
                    }
                    .onAppear { hotkeyValue = (option.currentValue as? String) ?? "" }
                }
            case "dropdown":
                HStack(spacing: 8) {
                    labelText
                    if option.choices.isEmpty {
                        // Invalid declaration — the host logs a metadata warning.
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
                        .fixedSize()
                    }
                }
            case "password":
                HStack(spacing: 8) {
                    labelText
                    SecureField("Enter value", text: $passwordValue)
                        .font(.system(size: 12, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
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
                    labelText
                    let path = (option.currentValue as? String) ?? ""
                    Text(path.isEmpty ? "Not set" : path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(path.isEmpty ? .tertiary : .secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 220, alignment: .leading)
                        .help(path)
                    Button("Choose…") {
                        choosePath()
                    }
                    .controlSize(.small)
                }
            default:
                HStack(spacing: 8) {
                    labelText
                    TextField("", text: $stringValue)
                        .font(.system(size: 12, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                        .onAppear { stringValue = (option.currentValue as? String) ?? "" }
                        .onSubmit {
                            state.saveModuleOption?(filename, option.key, stringValue)
                            state.refreshModules()
                        }
                }
            }
        }
    }

    private var labelText: some View {
        HStack(spacing: 6) {
            Text(option.label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
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
