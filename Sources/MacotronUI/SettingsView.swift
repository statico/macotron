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
    /// A sentence under the field. Keeps the label short enough to read as a
    /// label instead of turning the form into prose.
    public let help: String

    public init(key: String, label: String, type: String, defaultValue: Any, currentValue: Any,
                required: Bool = false, isSet: Bool = true, choices: [ModuleOptionChoice] = [],
                placeholder: String = "", help: String = "") {
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
        self.help = help
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
    /// Hash of the file on disk, to compare against the catalog copy.
    public let sourceHash: String

    public var needsSetup: Bool { options.contains { $0.needsSetup } }
    public var hasFailedChecks: Bool { checks.contains { !$0.ok } }

    public init(filename: String, title: String = "", description: String,
                help: String = "", checks: [PluginCheck] = [],
                options: [ModuleOption] = [], events: [String] = [],
                hotkeys: [PluginCommandSummary] = [], hasErrors: Bool = false, errorMessage: String? = nil,
                isEnabled: Bool = true, commands: [PluginCommandSummary] = [],
                permissions: [Permission] = [], hiddenStatusItems: [String] = [],
                sourceHash: String = "") {
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
        self.sourceHash = sourceHash
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
    @Published public var showMenuBarIcon: Bool = true
    @Published public var launchAtLogin: Bool = false
    @Published public var automaticUpdates: Bool = true
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

    // Community plugins, found through the GitHub topic. No index file and no
    // server: see CommunityCatalog.
    @Published public var communityEntries: [CommunityEntry] = []
    @Published public var communityLoading = false
    @Published public var communityError: String?
    /// Repository ids whose published bytes differ from the installed copy.
    @Published public var communityUpdates: Set<String> = []
    @Published public var installingRepo: String?
    private var communityFetchedAt: Date?
    private var communityTask: Task<Void, Never>?

    public var onSetHotReload: ((Bool) -> Void)?
    public var onScanCatalog: ((CatalogPlugin) -> Void)?
    public var onInstallCatalog: ((CatalogPlugin, Bool) -> Void)?
    public var onInstallAll: (([CatalogPlugin]) -> Void)?
    public var restoreStatusItem: ((String) -> Void)?
    /// nil reviews the whole queue; a filename reviews just that plugin.
    public var onReviewPending: ((String?) -> Void)?

    /// Baseline permissions plus whatever the loaded plugins declared.
    @Published public var requiredPermissions: [Permission] = Permissions.baseline
    @Published public var grantedPermissions: Set<Permission> = []

    public var readHotkey: (() -> String)?
    public var writeHotkey: ((String) -> Void)?
    public var readShowHotkeysHotkey: (() -> String)?
    public var readShowMenuBarIcon: (() -> Bool)?
    public var writeShowMenuBarIcon: ((Bool) -> Void)?
    public var readLaunchAtLogin: (() -> Bool)?
    public var writeLaunchAtLogin: ((Bool) -> Void)?
    public var readAutomaticUpdates: (() -> Bool)?
    public var writeAutomaticUpdates: ((Bool) -> Void)?
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
        showMenuBarIcon = readShowMenuBarIcon?() ?? true
        launchAtLogin = readLaunchAtLogin?() ?? false
        automaticUpdates = readAutomaticUpdates?() ?? true
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
        // The app bundle can be replaced under a running app, and a catalog
        // read once at launch then hands "Update" the copy that shipped with
        // the old bundle.
        catalogPlugins = PluginCatalog.load()
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

    public func setAutomaticUpdates(_ value: Bool) {
        writeAutomaticUpdates?(value)
        automaticUpdates = readAutomaticUpdates?() ?? value
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
    /// the user's disk, and so does a download, which came off someone else's.
    public var installIsBuiltIn: Bool { !isReviewing && installTarget?.origin == nil }

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
    /// The catalog copy of an installed plugin whose file no longer matches it,
    /// so someone who copied a plugin out of the catalog can take a newer one.
    public func catalogUpdate(for summary: ModuleSummary) -> CatalogPlugin? {
        guard !summary.sourceHash.isEmpty,
              let plugin = catalogPlugins.first(where: { $0.filename == summary.filename }),
              plugin.bundleHash != summary.sourceHash else { return nil }
        return plugin
    }

    public func allowsInstall(of plugin: CatalogPlugin, override: Bool) -> Bool {
        guard PluginBlocklist.reason(hash: plugin.bundleHash) == nil else { return false }
        guard let report = scanReport else {
            // The scan is advice, not a gate. Someone who presses the button
            // before it lands has approved these bytes themselves, which is
            // what the review asks of them in the first place.
            return installIsBuiltIn || override
        }
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

    // MARK: - Community

    /// Cached for an hour. Unauthenticated GitHub search allows 10 calls each
    /// minute for an IP address, which one person browsing never reaches, but
    /// there is no reason to spend a call on every sheet that opens.
    public func loadCommunity(force: Bool = false) {
        if !force, let at = communityFetchedAt, Date.now.timeIntervalSince(at) < 3600 { return }
        guard communityTask == nil else { return }
        communityLoading = true
        communityError = nil
        communityTask = Task { @MainActor in
            defer {
                communityLoading = false
                communityTask = nil
            }
            do {
                communityEntries = try await CommunityCatalog.search()
                communityFetchedAt = .now
                await refreshCommunityUpdates()
            } catch {
                communityError = error.localizedDescription
            }
        }
    }

    public func communityStatus(_ entry: CommunityEntry) -> CommunityStatus {
        guard installedPluginNames.contains(entry.filename) else { return .available }
        return communityUpdates.contains(entry.repo) ? .updatable : .installed
    }

    /// Only installed plugins are checked, so this is a handful of CDN requests
    /// and no API quota at all.
    private func refreshCommunityUpdates() async {
        let installed = communityEntries.filter { installedPluginNames.contains($0.filename) }
        guard !installed.isEmpty, let dir = configDirURL?.appending(path: "plugins") else { return }
        var stale: Set<String> = []
        for entry in installed {
            let local = PluginHash.sha256(file: dir.appending(path: entry.filename))
            guard let local else { continue }
            guard let fetched = try? await CommunityCatalog.fetchSource(entry) else { continue }
            if PluginHash.sha256(source: fetched.source) != local { stale.insert(entry.repo) }
        }
        communityUpdates = stale
    }

    /// Downloads the source and hands it to the same sheet a changed plugin on
    /// disk goes through: scan first, then approve.
    public func beginCommunityInstall(_ entry: CommunityEntry) {
        guard installingRepo == nil else { return }
        installingRepo = entry.repo
        communityError = nil
        Task { @MainActor in
            defer { installingRepo = nil }
            do {
                let fetched = try await CommunityCatalog.fetchSource(entry)
                let header = PluginHeader.parse(fetched.source)
                let plugin = CatalogPlugin(
                    filename: entry.filename,
                    highlighted: false,
                    title: header.title ?? entry.title,
                    description: header.description ?? entry.summary,
                    permissions: header.permissions.compactMap(Permission.init(rawValue:)),
                    source: fetched.source,
                    bundleHash: PluginHash.sha256(source: fetched.source),
                    fileURL: nil,
                    origin: CommunityOrigin(
                        repo: entry.repo,
                        stars: entry.stars,
                        pushedAt: entry.pushedAt,
                        homepage: entry.homepage,
                        sourceURL: fetched.url
                    )
                )
                scanReport = nil
                scanning = false
                isReviewing = false
                overwrite = overwriteForCommunity(plugin)
                installTarget = plugin
                scanInstallTarget()
            } catch {
                communityError = error.localizedDescription
            }
        }
    }

    /// A download that lands on an existing filename is a replacement, and the
    /// user is told so before it is written.
    private func overwriteForCommunity(_ plugin: CatalogPlugin) -> CatalogOverwrite? {
        guard let dest = configDirURL?
            .appending(path: "plugins")
            .appending(path: plugin.filename),
            FileManager.default.fileExists(atPath: dest.path(percentEncoded: false)) else { return nil }
        return .modified
    }
}

public struct SettingsView: View {
    @ObservedObject var state: SettingsState
    @State private var selectedTab: SettingsTab
    @State private var selectedPlugin: String?
    @State private var pluginFilter = ""
    @State private var showCatalog = false
    @State private var catalogSection: CatalogSection = .builtIn
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
        .sheet(isPresented: $showCatalog) { catalogSheet }
        .sheet(isPresented: $showNewPlugin) {
            NewPluginSheet(existing: existingPluginNames) { filename, source in
                state.createPlugin?(filename, source)
                selectedPlugin = filename
                showNewPlugin = false
            }
        }
        .catalogInstaller(state: state, enabled: !showCatalog)
    }

    private var catalogSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Plugin Catalog")
                    .font(.title2.weight(.semibold))
                Spacer()
                Picker("", selection: $catalogSection) {
                    ForEach(CatalogSection.allCases) { section in
                        Text(section.label).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            switch catalogSection {
            case .builtIn:
                CatalogBrowser(
                    plugins: state.catalogPlugins,
                    installedNames: state.installedPluginNames,
                    onAdd: { state.addBuiltIn($0) },
                    onDetails: { state.beginInstall($0) }
                )
            case .community:
                CommunityBrowser(state: state)
            }

            HStack {
                switch catalogSection {
                case .builtIn:
                    if state.missingCatalogCount > 0 {
                        Button("I Feel Lucky, Add Everything!") {
                            state.addAllBuiltIn()
                        }
                            .help("Add all \(state.missingCatalogCount) plugins you do not have yet")
                    }
                case .community:
                    Button {
                        NSWorkspace.shared.open(CommunityCatalog.topicURL)
                    } label: {
                        Text("Publish your own")
                    }
                    .buttonStyle(.link)
                    .help("Add the macotron-plugin topic to your repository and it shows up here")
                }
                Spacer()
                Button("Done") {
                    showCatalog = false
                }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(width: 620, height: 520)
        .catalogInstaller(state: state)
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

                formRow("Updates") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Check for updates automatically", isOn: Binding(
                            get: { state.automaticUpdates },
                            set: { state.setAutomaticUpdates($0) }
                        ))
                        .toggleStyle(.checkbox)
                        Button(Updater.pendingVersion.map { "Update to \($0)..." }
                            ?? "Check Now") {
                            Updater.checkForUpdates()
                        }
                    }
                }

                formRow("Menu Bar Icon") {
                    Toggle("Show in menu bar", isOn: Binding(
                        get: { state.showMenuBarIcon },
                        set: { state.toggleMenuBarIcon($0) }
                    ))
                    .toggleStyle(.checkbox)
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
                                            hasShortcutConflict: state.pluginHasShortcutConflict(summary.filename),
                                            hasUpdate: state.catalogUpdate(for: summary) != nil
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
                        state.onReviewPending?(nil)
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
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button("Catalog") {
                    showCatalog = true
                }
                .buttonStyle(.bordered)
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
                }
                .menuStyle(.borderedButton)
                .fixedSize()
                .help("Create a plugin with an editor or agent")

                Spacer(minLength: 0)
            }

            PluginSearchField(text: $pluginFilter)
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

    private func typePluginFilter(_ press: KeyPress) -> KeyPress.Result {
        guard !press.modifiers.contains(.command), !press.modifiers.contains(.control),
              !(NSApp.keyWindow?.firstResponder is NSTextView),
              PluginFilter.accepts(press.characters, existing: pluginFilter) else { return .ignored }
        pluginFilter += press.characters
        if let first = filteredPlugins.first, !filteredPlugins.contains(where: { $0.filename == selectedPlugin }) {
            selectedPlugin = first.filename
        }
        return .handled
    }

    private func clearPluginFilter() {
        pluginFilter = ""
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
    var hasUpdate = false

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
            } else if hasUpdate {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.blue)
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
    @State private var showUpdateAlert = false
    @StateObject private var command = CommandHeld()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if state.pendingReview.contains(summary.filename) { reviewBox }
                if let update = state.catalogUpdate(for: summary) { updateBox(update) }
                if summary.hasErrors { errorBox }
                if !summary.help.isEmpty { helpBox }
                if !summary.permissions.isEmpty { permissionsSection }
                if !summary.checks.isEmpty { checksSection }
                if !summary.hiddenStatusItems.isEmpty { hiddenStatusSection }

                if !summary.isEnabled { disabledHint }
                if summary.isEnabled {
                    if !summary.hotkeys.isEmpty { hotkeysSection }
                    if !summary.commands.isEmpty { commandsSection }
                }
                // Settings stay editable while a plugin is off: they are the
                // user's, not the plugin's, and a switched-off plugin is often
                // switched off precisely to be set up before it runs.
                if !summary.options.isEmpty { settingsSection }
                if summary.isEnabled, !summary.events.isEmpty { eventsSection }
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
        .alert("Update \(summary.title)?", isPresented: $showUpdateAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Update", role: .destructive) {
                guard let plugin = state.catalogUpdate(for: summary) else { return }
                state.onInstallCatalog?(plugin, true)
                state.refreshModules()
            }
        } message: {
            Text("This replaces \(summary.filename) with the copy that ships with Macotron. Any changes you made to the file are lost.")
        }
    }

    /// The file differs from the copy in the catalog -- either the user edited
    /// it, or Macotron shipped a newer one. Either way the fix is the same.
    private func updateBox(_ plugin: CatalogPlugin) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 11))
            Text("This copy differs from the one built into Macotron.")
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Update…") { showUpdateAlert = true }
                .controlSize(.small)
        }
        .foregroundStyle(.blue)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.08))
        .cornerRadius(6)
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
            Button("Review & Reload") { state.onReviewPending?(summary.filename) }
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
    @FocusState private var editing: Bool
    /// Pending debounced save. Typing used to be committed on Return alone, so
    /// a value typed and then clicked away from was simply dropped.
    @State private var pendingSave: DispatchWorkItem?

    var body: some View {
        HStack(alignment: option.type == "text" || !option.help.isEmpty ? .top : .center, spacing: 12) {
            labelText
                .frame(width: PluginForm.labelWidth, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                control
                if !option.help.isEmpty {
                    Text(option.help)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: PluginForm.fieldMaxWidth, alignment: .leading)
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// Save `value`, once the user has stopped typing for `after` seconds.
    /// Every save reloads every plugin, so an unchanged value saves nothing.
    private func commit(_ value: Any, after delay: TimeInterval = 0) {
        pendingSave?.cancel()
        pendingSave = nil
        if let text = value as? String, text == (option.currentValue as? String) ?? "" { return }
        // Through JSON and JS a number arrives as Int, Double or NSNumber, and
        // a mismatch here would save on every appearance -- and every save
        // reloads, which brings the field straight back round.
        if let number = value as? Double,
           let current = option.currentValue as? NSNumber,
           current.doubleValue == number { return }
        let work = DispatchWorkItem {
            state.saveModuleOption?(filename, option.key, value)
            state.refreshModules()
        }
        guard delay > 0 else {
            work.perform()
            return
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
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
                .focused($editing)
                .onChange(of: numberValue) {
                    if let num = Double(numberValue) { commit(num, after: 1.2) }
                }
                .onChange(of: editing) {
                    guard !editing, let num = Double(numberValue) else { return }
                    commit(num)
                }
                .onSubmit {
                    if let num = Double(numberValue) { commit(num) }
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
        case "text":
            // A TextEditor takes Return as a newline, so there is no onSubmit to
            // save on. Commit when the field loses focus instead.
            TextEditor(text: $stringValue)
                .font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(4)
                .frame(maxWidth: PluginForm.fieldMaxWidth, minHeight: 76)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.3)))
                .onAppear { stringValue = (option.currentValue as? String) ?? "" }
                .focused($editing)
                .onChange(of: editing) {
                    guard !editing else { return }
                    commit(stringValue)
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
                .focused($editing)
                // Typing settles into a save, so a changed value takes effect
                // without a trip to the keyboard's Return key.
                .onChange(of: stringValue) { commit(stringValue, after: 1.2) }
                .onChange(of: editing) {
                    guard !editing else { return }
                    commit(stringValue)
                }
                .onSubmit { commit(stringValue) }
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


/// NSSearchField, not a TextField: the clear button, the magnifier, and the
/// Escape-clears behaviour are what the HIG asks for and all of it ships.
struct PluginSearchField: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = "Filter plugins"
        field.controlSize = .small
        field.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        field.sendsSearchStringImmediately = true
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.text = $text
        if field.stringValue != text { field.stringValue = text }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) { self.text = text }

        func controlTextDidChange(_ note: Notification) {
            guard let field = note.object as? NSSearchField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}
