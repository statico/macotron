// SettingsView.swift — General prefs, plugins list
import AppKit
import MacotronEngine
import os
import SwiftUI
import UniformTypeIdentifiers

private let settingsLogger = Logger(subsystem: "io.statico.macotron", category: "settings")

enum PluginListNav {
    static func neighbor(of selected: String?, in filenames: [String], delta: Int) -> String? {
        guard !filenames.isEmpty else { return selected }
        guard let selected, let index = filenames.firstIndex(of: selected) else {
            return delta >= 0 ? filenames.first : filenames.last
        }
        return filenames[min(max(index + delta, 0), filenames.count - 1)]
    }
}

/// Finder-style type-select for the plugin list.
enum PluginFilter {
    static func matches(_ summary: ModuleSummary, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        return summary.title.localizedCaseInsensitiveContains(q)
            || summary.filename.localizedCaseInsensitiveContains(q)
            || summary.description.localizedCaseInsensitiveContains(q)
    }

    /// Characters worth starting a filter with. Space is only accepted once
    /// something has been typed, so it cannot start one on its own.
    static func accepts(_ characters: String, existing: String) -> Bool {
        guard characters.count == 1, let c = characters.first else { return false }
        if c == " " { return !existing.isEmpty }
        return c.isLetter || c.isNumber || c == "-" || c == "." || c == "_"
    }
}

enum MacotronRepo {
    static let url = URL(string: "https://github.com/statico/macotron")!
}

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
    /// Grey hint shown in an empty field. Plugins compute it at load, so it can
    /// describe live state such as the current system locale.
    public let placeholder: String

    public init(key: String, label: String, type: String, defaultValue: Any, currentValue: Any,
                required: Bool = false, isSet: Bool = true, choices: [ModuleOptionChoice] = [],
                placeholder: String = "") {
        self.id = key
        self.key = key
        self.label = label
        self.type = type
        self.defaultValue = defaultValue
        self.currentValue = currentValue
        self.required = required
        self.isSet = isSet
        self.choices = choices
        self.placeholder = placeholder
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
    /// Menu bar items this plugin asked for that the user has dragged out.
    public let hiddenStatusItems: [String]

    public var needsSetup: Bool { options.contains { $0.needsSetup } }
    public var hasFailedChecks: Bool { checks.contains { !$0.ok } }

    public init(filename: String, title: String = "", description: String,
                help: String = "", checks: [PluginCheck] = [],
                options: [ModuleOption] = [], events: [String] = [],
                hotkeys: [PluginCommandSummary] = [], hasErrors: Bool = false, errorMessage: String? = nil,
                isEnabled: Bool = true, commands: [PluginCommandSummary] = [],
                permissions: [Permission] = [], hiddenStatusItems: [String] = []) {
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
        self.hiddenStatusItems = hiddenStatusItems
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

public enum SettingsTab: Int, CaseIterable {
    case general
    case permissions
    case plugins
    case shortcuts
}

@MainActor
public final class SettingsState: ObservableObject {
    @Published public var launcherHotkey: String = "opt+space" { didSet { claimsCache = nil } }
    @Published public var showHotkeysHotkey: String = "" { didSet { claimsCache = nil } }
    @Published public var showDockIcon: Bool = true
    @Published public var showMenuBarIcon: Bool = true
    @Published public var launchAtLogin: Bool = false
    @Published public var appearance: AppearanceSetting = .system
    @Published public var textScale: Double = 1.0
    @Published public var launcherBackground: LauncherBackground = .translucent
    @Published public var moduleSummaries: [ModuleSummary] = [] { didSet { claimsCache = nil } }
    @Published public var appShortcuts: [AppShortcutSummary] = [] { didSet { claimsCache = nil } }

    /// Building the claim table walks every plugin, hotkey, and app shortcut,
    /// and the plugin list asks for it once per row while it draws. Cache it and
    /// let the four inputs above clear it.
    var claimsCache: [ShortcutConflicts.Claim]?
    @Published public var requestedTab: Int?
    @Published public var requestedPlugin: String?
    @Published public var catalogPlugins: [CatalogPlugin] = []
    @Published public var installedPluginNames: Set<String> = []
    @Published public var pendingReview: [String] = []
    @Published public var hotReload = false
    @Published public var installTarget: CatalogPlugin?
    @Published public var scanReport: PluginScanReport?
    @Published public var scanning = false
    @Published public var overwrite: CatalogOverwrite?
    @Published public var isReviewing = false

    public var onSetHotReload: ((Bool) -> Void)?
    public var onScanCatalog: ((CatalogPlugin) -> Void)?
    public var onInstallCatalog: ((CatalogPlugin, Bool) -> Void)?
    public var onInstallAll: (([CatalogPlugin]) -> Void)?
    public var restoreStatusItem: ((String) -> Void)?
    public var onReviewPending: (() -> Void)?

    /// Baseline permissions plus whatever the loaded plugins declared.
    @Published public var requiredPermissions: [Permission] = Permissions.baseline
    @Published public var grantedPermissions: Set<Permission> = []

    public var readHotkey: (() -> String)?
    public var writeHotkey: ((String) -> Void)?
    public var readShowHotkeysHotkey: (() -> String)?
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
    public var revealModuleFile: ((_ filename: String) -> Void)?
    public var changePluginsFolder: (() -> Void)?
    public var openPluginsFolder: (() -> Void)?
    public var createPlugin: ((_ filename: String, _ source: String) -> Void)?
    public var loadRequiredPermissions: (() -> [Permission])?
    public var configDirURL: URL?
    public var pluginsPath: String { configDirURL?.path(percentEncoded: false) ?? "" }

    public init() {}

    public func load() {
        launcherHotkey = readHotkey?() ?? "opt+space"
        showHotkeysHotkey = readShowHotkeysHotkey?() ?? ""
        showDockIcon = readShowDockIcon?() ?? true
        showMenuBarIcon = readShowMenuBarIcon?() ?? true
        launchAtLogin = readLaunchAtLogin?() ?? false
        appearance = readAppearance?() ?? .system
        textScale = readTextScale?() ?? 1.0
        launcherBackground = readLauncherBackground?() ?? .translucent
        catalogPlugins = PluginCatalog.load()
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
        // A plugin page shows what its header declares, even while the plugin
        // is disabled or waiting to be reviewed -- and those permissions are
        // not in `required`, which only counts what is running. Check them too,
        // or an installed helper reads as missing and its Install does nothing.
        let shown = Set(moduleSummaries.flatMap(\.permissions)).subtracting(required)
        let granted = Set((required + shown).filter(\.isGranted))
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

    public func saveShowHotkeysHotkey() {
        saveCommandShortcut?(HostCommands.showHotkeysID, showHotkeysHotkey)
        showHotkeysHotkey = readShowHotkeysHotkey?() ?? ""
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

    public func setHotReload(_ value: Bool) {
        hotReload = value
        onSetHotReload?(value)
    }

    public func beginInstall(_ plugin: CatalogPlugin) {
        scanReport = nil
        scanning = false
        isReviewing = false
        let dest = configDirURL?
            .appending(path: "plugins")
            .appending(path: plugin.filename)
        if let dest, FileManager.default.fileExists(atPath: dest.path(percentEncoded: false)),
           let existing = PluginHash.sha256(file: dest) {
            overwrite = PluginCatalog.overwriteKind(existingHash: existing, bundledHash: plugin.bundleHash)
        } else {
            overwrite = nil
        }
        installTarget = plugin
    }

    public func addBuiltIn(_ plugin: CatalogPlugin) {
        let t0 = CFAbsoluteTimeGetCurrent()
        settingsLogger.info("addBuiltIn \(plugin.filename, privacy: .public)")
        let dest = configDirURL?
            .appending(path: "plugins")
            .appending(path: plugin.filename)
        if let dest, FileManager.default.fileExists(atPath: dest.path(percentEncoded: false)) {
            settingsLogger.info("addBuiltIn \(plugin.filename, privacy: .public) already on disk, opening details")
            beginInstall(plugin)
            return
        }
        scanReport = nil
        scanning = false
        overwrite = nil
        isReviewing = false
        installTarget = nil
        onInstallCatalog?(plugin, false)
        settingsLogger.info("addBuiltIn \(plugin.filename, privacy: .public) returned +\(Int((CFAbsoluteTimeGetCurrent() - t0) * 1000))ms")
    }

    /// Bulk add skips the per-plugin sheet: these bytes ship inside the signed
    /// app bundle, so there is nothing to review. Anything already on disk is
    /// left alone rather than overwritten.
    public var missingCatalogCount: Int {
        catalogPlugins.filter { !installedPluginNames.contains($0.filename) }.count
    }

    public func addAllBuiltIn() {
        let pending = catalogPlugins.filter { !installedPluginNames.contains($0.filename) }
        guard !pending.isEmpty else { return }
        settingsLogger.info("addAllBuiltIn \(pending.count, privacy: .public) plugins")
        scanReport = nil
        scanning = false
        overwrite = nil
        isReviewing = false
        installTarget = nil
        onInstallAll?(pending)
    }

    /// Catalog plugins ship inside the signed app bundle, so their bytes are already
    /// as trusted as Macotron itself. A review scans because those bytes came off
    /// the user's disk.
    public var installIsBuiltIn: Bool { !isReviewing }

    public func scanInstallTarget() {
        guard let plugin = installTarget else { return }
        onScanCatalog?(plugin)
    }

    /// Only accept a report that binds to the bytes still up for install; a scan
    /// that outlived a cancelled review is dropped.
    public func applyScanReport(_ report: PluginScanReport) {
        guard let target = installTarget, report.matches(source: target.source) else { return }
        scanReport = report
        scanning = false
    }

    /// A verdict approves only the exact bytes it scanned. No report is fine only
    /// for built-ins, whose bytes ship inside the signed bundle; reviewed bytes
    /// came off disk and always need one.
    public func allowsInstall(of plugin: CatalogPlugin, override: Bool) -> Bool {
        guard let report = scanReport else { return installIsBuiltIn }
        guard report.matches(source: plugin.source) else { return false }
        return !report.needsOverride || override
    }

    public func beginReview(filename: String, source: String, destHash: String?, fileURL: URL) {
        scanReport = nil
        scanning = false
        isReviewing = true
        overwrite = nil
        let header = PluginHeader.parse(source)
        installTarget = CatalogPlugin(
            filename: filename,
            highlighted: false,
            title: header.title ?? filename,
            description: header.description ?? "",
            permissions: header.permissions.compactMap(Permission.init(rawValue:)),
            source: source,
            bundleHash: destHash ?? PluginHash.sha256(source: source),
            fileURL: fileURL
        )
        scanInstallTarget()
    }
}

public struct SettingsView: View {
    @ObservedObject var state: SettingsState
    @State private var selectedTab: SettingsTab
    @State private var selectedPlugin: String?
    @State private var pluginFilter = ""
    @State private var pluginFilterHide: Task<Void, Never>?
    @State private var showCatalog = false
    @State private var showNewPlugin = false
    @FocusState private var pluginListFocused: Bool

    public init(state: SettingsState, initialTab: Int = 0) {
        self.state = state
        self._selectedTab = State(initialValue: SettingsTab(rawValue: initialTab) ?? .general)
    }

    public var body: some View {
        VStack(spacing: 0) {
            tabBar
                .padding(.top, 2)
                .padding(.bottom, 6)

            Divider()

            Group {
                switch selectedTab {
                case .general: generalTab
                case .permissions: permissionsTab
                case .plugins: pluginsTab
                case .shortcuts: shortcutsTab
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
        .sheet(isPresented: $showCatalog) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Plugin Catalog")
                    .font(.title2.weight(.semibold))
                CatalogBrowser(
                    plugins: state.catalogPlugins,
                    installedNames: state.installedPluginNames,
                    onAdd: { state.addBuiltIn($0) },
                    onDetails: { state.beginInstall($0) }
                )
                HStack {
                    if state.missingCatalogCount > 0 {
                        Button("I Feel Lucky, Add Everything!") {
                            state.addAllBuiltIn()
                        }
                            .help("Add all \(state.missingCatalogCount) plugins you do not have yet")
                    }
                    Spacer()
                    Button("Done") {
                        showCatalog = false
                    }
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding(16)
            .frame(width: 560, height: 480)
            .catalogInstaller(state: state)
        }
        .sheet(isPresented: $showNewPlugin) {
            NewPluginSheet(existing: existingPluginNames) { filename, source in
                state.createPlugin?(filename, source)
                selectedPlugin = filename
                showNewPlugin = false
            }
        }
        .catalogInstaller(state: state, enabled: !showCatalog)
    }

    private var existingPluginNames: Set<String> {
        state.installedPluginNames.union(state.moduleSummaries.map(\.filename))
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            Spacer()
            tabButton(icon: "gearshape", label: "General", tab: .general)
            tabButton(
                icon: "lock.shield",
                label: "Permissions",
                tab: .permissions,
                warn: !state.missingPermissions.isEmpty
            )
            tabButton(icon: "puzzlepiece.extension", label: "Plugins", tab: .plugins)
            tabButton(icon: "command", label: "Shortcuts", tab: .shortcuts)
            Spacer()
        }
    }

    private func applySettingsRequest() {
        if let raw = state.requestedTab, let tab = SettingsTab(rawValue: raw) {
            selectedTab = tab
            state.requestedTab = nil
        }
        if let file = state.requestedPlugin {
            selectedPlugin = file
            state.requestedPlugin = nil
        }
    }

    private func tabButton(icon: String, label: String, tab: SettingsTab, warn: Bool = false) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .frame(height: 24)
                Text(label)
                    .font(.system(size: 10, weight: .medium))
            }
            .frame(width: 78, height: 48)
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.primary.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(warn ? Color.orange : (isSelected ? Color.primary : Color.secondary))
    }

    private var generalTab: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    if let bannerURL = Bundle.main.url(forResource: "banner", withExtension: "png"),
                       let nsImage = NSImage(contentsOf: bannerURL) {
                        Button {
                            NSWorkspace.shared.open(MacotronRepo.url)
                        } label: {
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: 280)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open Macotron on GitHub")
                    }
                    Link("github.com/statico/macotron", destination: MacotronRepo.url)
                        .font(.caption)
                    Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
                .padding(.bottom, 16)

                Divider()
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)

                formRow("Plugins Folder") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(state.pluginsPath.isEmpty ? "(not set)" : state.pluginsPath)
                            .font(.body)
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

                formRow("Launcher Hotkey") {
                    VStack(alignment: .leading, spacing: 4) {
                        HotkeyRecorderView(combo: $state.launcherHotkey) {
                            state.saveHotkey()
                        }
                        .frame(width: PluginForm.recorderWidth)
                        ShortcutConflictNote(
                            message: state.shortcutWarning(id: ShortcutConflicts.launcherID, combo: state.launcherHotkey)
                        )
                    }
                }
                .zIndex(1)
                .padding(.top, 8)

                formRow("Show Hotkeys") {
                    VStack(alignment: .leading, spacing: 4) {
                        HotkeyRecorderView(combo: $state.showHotkeysHotkey) {
                            state.saveShowHotkeysHotkey()
                        }
                        .frame(width: PluginForm.recorderWidth)
                        ShortcutConflictNote(
                            message: state.shortcutWarning(
                                id: HostCommands.showHotkeysID,
                                combo: state.showHotkeysHotkey
                            )
                        )
                    }
                }
                .zIndex(1)

                formDivider

                formRow("Launch at Login") {
                    Toggle("Open Macotron when you log in", isOn: Binding(
                        get: { state.launchAtLogin },
                        set: { state.toggleLaunchAtLogin($0) }
                    ))
                    .toggleStyle(.checkbox)
                }

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

                formRow("Hot Reload") {
                    Toggle("Reload plugins on every save without a scan", isOn: Binding(
                        get: { state.hotReload },
                        set: { state.setHotReload($0) }
                    ))
                    .toggleStyle(.checkbox)
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
                    .labelsHidden()
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
                    .labelsHidden()
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
                    .labelsHidden()
                    .frame(width: 340, alignment: .leading)
                }
                .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Permissions

    private var permissionsTab: some View {
        let missing = state.missingPermissions

        return ScrollView {
            VStack {
                VStack(alignment: .leading, spacing: 16) {
                    Text(permissionsSummary(missing: missing))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    ForEach(state.requiredPermissions) { permission in
                        PermissionRow(
                            permission: permission,
                            granted: state.grantedPermissions.contains(permission),
                            onChange: { state.refreshPermissions() }
                        )
                    }

                    Button("Re-check") {
                        state.refreshPermissions()
                    }
                    .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
        .background(missing.isEmpty ? Color.clear : Color.orange.opacity(0.08))
    }

    /// Not everything in this list is needed for Macotron to run — a plugin can
    /// ask for the background helper — so the copy talks about approval, not working.
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
                pluginSidebarActions

                Divider()

                if state.moduleSummaries.isEmpty {
                    emptyPluginsPlaceholder
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 1) {
                                ForEach(filteredPlugins) { summary in
                                    let selected = selectedPlugin == summary.filename
                                    Button {
                                        selectedPlugin = summary.filename
                                        pluginListFocused = true
                                    } label: {
                                        PluginListRow(
                                            summary: summary,
                                            hasShortcutConflict: state.pluginHasShortcutConflict(summary.filename)
                                        )
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
                                    .id(summary.filename)
                                }
                            }
                            .padding(6)
                        }
                        .onChange(of: selectedPlugin) { _, file in
                            if let file { proxy.scrollTo(file, anchor: .center) }
                        }
                    }
                    .frame(maxHeight: .infinity)
                }

                if !state.pendingReview.isEmpty {
                    Divider()

                    Button("Review & Reload") {
                        state.onReviewPending?()
                    }
                    .controlSize(.small)
                    .padding(8)
                }
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
        .focusable()
        .focused($pluginListFocused)
        .focusEffectDisabled()
        .overlay(alignment: .bottom) { pluginFilterOverlay }
        .onKeyPress(.upArrow) { handlePluginArrow(-1) }
        .onKeyPress(.downArrow) { handlePluginArrow(1) }
        .onKeyPress(.escape) {
            guard !pluginFilter.isEmpty else { return .ignored }
            clearPluginFilter()
            return .handled
        }
        .onKeyPress(.delete) {
            guard !pluginFilter.isEmpty else { return .ignored }
            pluginFilter.removeLast()
            pluginFilter.isEmpty ? clearPluginFilter() : armPluginFilterHide()
            return .handled
        }
        .onKeyPress { press in typePluginFilter(press) }
        .onAppear {
            selectInitialPlugin()
            pluginListFocused = true
        }
        .onChange(of: state.moduleSummaries.map(\.filename)) {
            selectInitialPlugin()
        }
    }

    private var pluginSidebarActions: some View {
        HStack(spacing: 8) {
            Button("Catalog") {
                showCatalog = true
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
            .help("Browse and add plugins from the catalog")

            Menu {
                ForEach(PluginAuthoring.agents) { tool in
                    Button(tool.name) { launchAuthoringTool(tool) }
                }
                Divider()
                ForEach(PluginAuthoring.editors) { tool in
                    Button(tool.name) { launchAuthoringTool(tool) }
                }
                Divider()
                Button("Empty Plugin…") { showNewPlugin = true }
                Button("Open Plugins Folder") { state.openPluginsFolder?() }
            } label: {
                Text("Create")
                    .frame(maxWidth: .infinity)
            }
            .menuStyle(.borderedButton)
            .frame(maxWidth: .infinity)
            .help("Create a plugin with an editor or agent")
        }
        .padding(8)
    }

    private func launchAuthoringTool(_ tool: PluginAuthoringTool) {
        guard let dir = state.configDirURL else { return }
        guard !PluginAuthoring.launch(tool, in: dir) else { return }
        let alert = NSAlert()
        alert.messageText = "Could not open the plugins folder in \(tool.name)"
        alert.informativeText = "\(tool.name) does not look installed. Install it, or use Open Plugins Folder to work somewhere else."
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Open Plugins Folder")
        if alert.runModal() == .alertSecondButtonReturn {
            state.openPluginsFolder?()
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
            Text("Add plugins from the catalog, or drop .js files into the plugins folder.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var filteredPlugins: [ModuleSummary] {
        state.moduleSummaries.filter { PluginFilter.matches($0, query: pluginFilter) }
    }

    /// Finder-style: typing anywhere in the list floats a filter that fades on
    /// its own, so finding a plugin never costs a trip to a search field.
    @ViewBuilder
    private var pluginFilterOverlay: some View {
        if !pluginFilter.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(pluginFilter)
                    .font(.system(size: 13, weight: .medium))
                if filteredPlugins.isEmpty {
                    Text("no matches")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.separator))
            .shadow(radius: 8, y: 2)
            .padding(.bottom, 16)
            .transition(.opacity)
        }
    }

    private func typePluginFilter(_ press: KeyPress) -> KeyPress.Result {
        guard !press.modifiers.contains(.command), !press.modifiers.contains(.control),
              !(NSApp.keyWindow?.firstResponder is NSTextView),
              PluginFilter.accepts(press.characters, existing: pluginFilter) else { return .ignored }
        pluginFilter += press.characters
        if let first = filteredPlugins.first, !filteredPlugins.contains(where: { $0.filename == selectedPlugin }) {
            selectedPlugin = first.filename
        }
        armPluginFilterHide()
        return .handled
    }

    private func armPluginFilterHide() {
        pluginFilterHide?.cancel()
        pluginFilterHide = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            clearPluginFilter()
        }
    }

    private func clearPluginFilter() {
        pluginFilterHide?.cancel()
        pluginFilterHide = nil
        withAnimation(.easeOut(duration: 0.15)) { pluginFilter = "" }
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

    private func handlePluginArrow(_ delta: Int) -> KeyPress.Result {
        if NSApp.keyWindow?.firstResponder is NSTextView { return .ignored }
        guard movePluginSelection(delta) else { return .ignored }
        return .handled
    }

    @discardableResult
    private func movePluginSelection(_ delta: Int) -> Bool {
        let files = filteredPlugins.map(\.filename)
        guard let next = PluginListNav.neighbor(of: selectedPlugin, in: files, delta: delta) else {
            return false
        }
        selectedPlugin = next
        pluginListFocused = true
        return true
    }

    private var shortcutsTab: some View {
        AppShortcutsTab(state: state)
    }

    private func formRow<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: PluginForm.rowSpacing) {
            // Primary label colour, like every control label in System
            // Settings. Secondary is for the notes under a control.
            Text(label)
                .multilineTextAlignment(.trailing)
                .frame(width: PluginForm.labelWidth, alignment: .trailing)

            content()
                .frame(width: PluginForm.controlWidth, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var formDivider: some View {
        Divider()
            .frame(width: PluginForm.labelWidth + PluginForm.rowSpacing + PluginForm.controlWidth)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
    }
}

private enum PluginForm {
    static let labelWidth: CGFloat = 140
    static let controlWidth: CGFloat = 340
    static let rowSpacing: CGFloat = 20
    static let recorderWidth: CGFloat = 240
    static let fieldMaxWidth: CGFloat = 280
}

struct ShortcutField: View {
    var label: String?
    let shortcut: String
    var conflict: String?
    var onSave: (String) -> Void
    @State private var combo = ""

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let label {
                Text(label)
                    .font(.system(size: 12))
                    .lineLimit(2)
                    .frame(width: PluginForm.labelWidth, alignment: .leading)
                    .padding(.top, 6)
            }
            VStack(alignment: .leading, spacing: 4) {
                HotkeyRecorderView(combo: $combo) { onSave(combo) }
                    .frame(width: PluginForm.recorderWidth)
                ShortcutConflictNote(message: conflict)
            }
            if label != nil { Spacer(minLength: 0) }
        }
        .onAppear { combo = shortcut }
        .onChange(of: shortcut) { _, newValue in combo = newValue }
    }
}

struct PluginListRow: View {
    let summary: ModuleSummary
    var hasShortcutConflict = false

    var body: some View {
        HStack(spacing: 8) {
            Text(summary.title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)

            Spacer(minLength: 4)

            if summary.hasErrors {
                Image(systemName: "xmark.octagon.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            } else if summary.needsSetup || summary.hasFailedChecks || hasShortcutConflict {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
        .opacity(summary.isEnabled ? 1 : 0.45)
    }
}

final class CommandHeld: ObservableObject, @unchecked Sendable {
    @Published private(set) var isHeld = false
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []

    init() {
        sync()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .leftMouseUp, .rightMouseUp]) { [weak self] event in
            self?.sync()
            return event
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.sync()
        })
        observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.sync(appActive: false)
        })
        observers.append(center.addObserver(forName: ShortcutRecording.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.sync()
        })
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func sync(appActive: Bool = true) {
        let commandDown = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command)
        let held = appActive && !ShortcutRecording.isActive && commandDown
        if isHeld != held { isHeld = held }
    }
}

struct PluginDetailView: View {
    let summary: ModuleSummary
    @ObservedObject var state: SettingsState
    @State private var showDeleteAlert = false
    @StateObject private var command = CommandHeld()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if state.pendingReview.contains(summary.filename) { reviewBox }
                if summary.hasErrors { errorBox }
                if !summary.help.isEmpty { helpBox }
                if !summary.permissions.isEmpty { permissionsSection }
                if !summary.checks.isEmpty { checksSection }
                if !summary.hiddenStatusItems.isEmpty { hiddenStatusSection }

                if !summary.isEnabled {
                    disabledHint
                } else {
                    if !summary.hotkeys.isEmpty { hotkeysSection }
                    if !summary.commands.isEmpty { commandsSection }
                    if !summary.options.isEmpty { settingsSection }
                    if !summary.events.isEmpty { eventsSection }
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(summary.title)
                        .font(.system(size: 16, weight: .semibold))
                    if summary.needsSetup && summary.isEnabled {
                        detailBadge(text: "Needs setup", color: .orange)
                    }
                    if summary.hasFailedChecks && summary.isEnabled {
                        detailBadge(text: "Warning", color: .orange)
                    }
                    if summary.isEnabled && state.pluginHasShortcutConflict(summary.filename) {
                        detailBadge(text: "Shortcut conflict", color: .orange)
                    }
                }
                Spacer(minLength: 8)
                Toggle("Enabled", isOn: Binding(
                    get: { summary.isEnabled },
                    set: { state.setModuleEnabled?(summary.filename, $0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            if !summary.description.isEmpty {
                Text(summary.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button(command.isHeld ? "Reveal in Finder" : "Open Source File") {
                    if NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command) {
                        state.revealModuleFile?(summary.filename)
                    } else {
                        state.openModuleFile?(summary.filename)
                    }
                    command.sync()
                }
                .controlSize(.small)
                Spacer()
                Button("Delete…", role: .destructive) {
                    showDeleteAlert = true
                }
                .controlSize(.small)
            }

            Divider()
        }
    }

    /// The file on disk changed, so this plugin is parked until the source is
    /// reviewed. The sidebar says so for the whole set; say it here too, since
    /// this page is where someone lands wondering why nothing is running.
    private var reviewBox: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
            Text("The source file changed. This plugin stays stopped until you review it.")
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Review & Reload") { state.onReviewPending?() }
                .controlSize(.small)
        }
        .foregroundStyle(.orange)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(6)
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

    /// Command-dragging an item out of the menu bar is easy to do by accident,
    /// and macOS remembers it, so the item does not come back on its own.
    private var hiddenStatusSection: some View {
        pluginSection("Menu Bar") {
            ForEach(summary.hiddenStatusItems, id: \.self) { id in
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\u{201C}\(id)\u{201D} was removed from the menu bar")
                            .font(.system(size: 12, weight: .medium))
                        Text("Command-dragging an item out of the menu bar hides it for good.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Button("Restore") { state.restoreStatusItem?(id) }
                        .controlSize(.small)
                }
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

    private var eventsSection: some View {
        pluginSection("Listens for") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(summary.events, id: \.self) { event in
                    Text("•  \(EventLabel.displayName(event))")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var hotkeysSection: some View {
        pluginSection("Shortcuts") {
            ForEach(summary.hotkeys) { hotkey in
                ShortcutField(
                    label: hotkey.name,
                    shortcut: hotkey.shortcut,
                    conflict: state.shortcutWarning(id: "hotkey:\(hotkey.id)", combo: hotkey.shortcut)
                ) { combo in
                    state.saveKeyboardShortcut?(hotkey.id, combo)
                    state.refreshModules()
                }
            }
        }
    }

    private var commandsSection: some View {
        pluginSection("Commands") {
            ForEach(summary.commands) { command in
                ShortcutField(
                    label: command.name,
                    shortcut: command.shortcut,
                    conflict: state.shortcutWarning(id: "command:\(command.id)", combo: command.shortcut)
                ) { combo in
                    state.saveCommandShortcut?(command.id, combo)
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
            TextField("", text: $numberValue, prompt: promptText)
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
            VStack(alignment: .leading, spacing: 4) {
                HotkeyRecorderView(combo: $hotkeyValue) {
                    state.saveModuleOption?(filename, option.key, hotkeyValue)
                    state.refreshModules()
                }
                .frame(width: PluginForm.recorderWidth)
                ShortcutConflictNote(
                    message: state.shortcutWarning(
                        id: "option:\(filename)/\(option.key)",
                        combo: (option.currentValue as? String) ?? ""
                    )
                )
            }
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
                SecureField(option.placeholder.isEmpty ? "Enter value" : option.placeholder, text: $passwordValue)
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
                let empty = option.placeholder.isEmpty ? "Not set" : option.placeholder
                Text(path.isEmpty ? empty : path)
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
            TextField("", text: $stringValue, prompt: promptText)
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

    private var promptText: Text? {
        option.placeholder.isEmpty ? nil : Text(option.placeholder)
    }

    private var labelText: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(option.label)
                .font(.system(size: 12))
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

