// AppDelegate.swift — NSApplicationDelegate, app lifecycle
import AppKit
import CoreServices
import SwiftUI
import MacotronEngine
import MacotronUI
import Modules
import AI
import os

private let appLogger = Logger(subsystem: "io.statico.macotron", category: "app")

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var engine: Engine!
    private var moduleManager: ModuleManager!
    private var workspace: PluginWorkspace!
    private var menuBarManager: MenuBarManager!
    private var launcherPanel: LauncherPanel!
    private var hotkeysOverlayPanel: HotkeysOverlayPanel!
    private var launcherHotKeyID: UInt32?
    private var settingsWindow: SettingsWindow!
    private let settingsState = SettingsState()
    private let launcherPrefs = LauncherPrefs()
    private let launcherSession = LauncherSession()
    private var keyboardModule: KeyboardModule?
    private var launcherModule: LauncherModule?
    private var menuBarPluginModule: MenuBarModule?
    private var wizardWindow: WizardWindow?
    private let wizardState = WizardState()
    private var appSearchProvider: AppSearchProvider!
    private var fileIconCache: [String: NSImage] = [:]
    /// Which permissions have already been asked for. The first refresh runs
    /// before the plugins are loaded, so at that point only the baseline is
    /// known — a one-shot latch here would mean camera and microphone, which
    /// only a plugin declares, are never requested and so never appear in the
    /// System Settings lists.
    private var registeredPermissions: Set<Permission> = []

    /// Last known missing set, refreshed by the permission poll. Checking is
    /// slow enough (tens of milliseconds) that the launcher reads it instead.
    private var missingPermissions: [Permission] = []
    private var permissionTimer: Timer?
    private var scanTask: Task<Void, Never>?
    private var didFinishLaunching = false

    private static let wizardCompletedKey = "wizardCompleted"

    public func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()

        engine = Engine()
        Updater.start()

        // Wired before bootstrap so the wizard can show permissions even when no
        // workspace exists yet.
        settingsState.loadRequiredPermissions = { [weak self] in
            self?.requiredPermissions() ?? Permissions.baseline
        }
        settingsState.onScanCatalog = { [weak self] plugin in
            self?.scanCatalogPlugin(plugin)
        }
        observePermissionTriggers()

        if let root = PluginWorkspace.resolveFromDefaults() {
            bootstrap(workspaceRoot: root)
        }

        refreshPermissions()

        // The kill switch. Off the launch path: plugins already loaded from the
        // cached list, and a plugin that turns out to be blocked is unloaded as
        // soon as the fresh list lands.
        Task { @MainActor [weak self] in
            guard await PluginBlocklist.refresh() else { return }
            guard let self, self.workspace != nil else { return }
            self.moduleManager?.reloadAll()
            self.refreshIntegrity()
        }

        // Off the launch path: this connects to the daemon, which launchd may
        // have to start, and waits on the reply.
        DispatchQueue.global(qos: .utility).async {
            FanController.shared.checkHelper()
        }

        let wizardDone = UserDefaults.standard.bool(forKey: AppDelegate.wizardCompletedKey)
        if !wizardDone || PluginWorkspace.resolveFromDefaults() == nil {
            showSetupWizard()
        } else {
            nagAboutPermissionsIfStillMissing()
            // Macotron has no window of its own, so a launch is otherwise
            // silent — show the launcher once as proof it is running.
            launcherPanel?.showReason = "app launch"
            launcherPanel?.toggle()
        }

        didFinishLaunching = true
    }

    /// AppKit sends this when the user clicks the Dock icon or re-launches an
    /// already-running Macotron from Spotlight or Finder. Ordinary app
    /// switches such as Cmd-Tab arrive as activation instead, so opening
    /// Settings here does not fight the user for focus.
    public func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        // Some launch paths deliver a reopen before the app is ready, and the
        // wizard owns the screen while it is up.
        guard didFinishLaunching, wizardWindow?.isVisible != true else { return true }
        openSettingsAction()
        return true
    }

    /// Finder sends .html files here when Macotron is the default browser.
    /// Route them like any link: the browser-picker fallback opens the file
    /// in whichever browser the user configured.
    public func application(_ application: NSApplication, open urls: [URL]) {
        URLSchemeModule.handle(urls)
    }

    @objc private func handleGetURL(
        _ event: NSAppleEventDescriptor,
        withReply reply: NSAppleEventDescriptor
    ) {
        guard let urlString = event.paramDescriptor(
            forKeyword: AEKeyword(keyDirectObject)
        )?.stringValue,
        let url = URL(string: urlString) else {
            appLogger.error("URL event dropped: no URL in event")
            return
        }
        URLSchemeModule.handle([url], sourceBundle: sourceBundle(from: event))
    }

    private func sourceBundle(from event: NSAppleEventDescriptor) -> String? {
        guard let descriptor = event.attributeDescriptor(
            forKeyword: AEKeyword(keySenderPIDAttr)
        ) else {
            return nil
        }
        let pid = pid_t(descriptor.int32Value)
        guard pid > 0 else { return nil }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }

    // MARK: - Bootstrap

    private func bootstrap(workspaceRoot: URL) {
        workspace = PluginWorkspace(root: workspaceRoot)
        do {
            try workspace.ensureReady()
        } catch {
            NSLog("[Macotron] Failed to init workspace: \(error)")
        }

        moduleManager = ModuleManager(engine: engine, workspace: workspace)
        applyUIPrefsFromSettings()
        setupSettings()

        menuBarManager = MenuBarManager()
        menuBarManager.onReload = { [weak self] in
            guard let self else { return }
            self.moduleManager.reloadAll()
            // A reload cannot clear a changed file on its own — the source still
            // needs approval — so go straight into the review the user meant.
            if !self.moduleManager.pendingReview.isEmpty {
                self.reviewPendingPlugins()
            }
        }
        menuBarManager.onHiddenStatusChange = { [weak self] _ in
            self?.settingsState.refreshModules()
            self?.refreshPermissions()
        }
        // Menu bar visibility reads like a permission: something outside
        // Macotron decides it, and the fix is a switch in System Settings.
        Permissions.menuBarItems = { [weak menuBarManager] in
            menuBarManager?.statusItemCounts() ?? (0, 0)
        }
        Permissions.restoreMenuBarItems = { [weak menuBarManager] in
            menuBarManager?.restoreAllStatus()
        }
        menuBarManager.onOpenConfig = { [weak self] in
            guard let self else { return }
            NSWorkspace.shared.open(self.workspace.root)
        }
        menuBarManager.onToggleLauncher = { [weak self] in
            self?.launcherPanel.showReason = "menu bar icon"
            self?.launcherPanel.toggle()
        }
        menuBarManager.onOpenSettings = { [weak self] in
            self?.launcherPanel.orderOut(nil)
            self?.settingsWindow.show()
        }
        menuBarManager.onCheckForUpdates = { Updater.checkForUpdates() }
        menuBarManager.onOpenPermissions = { [weak self] in
            guard let self else { return }
            self.launcherPanel.orderOut(nil)
            self.settingsState.requestedTab = SettingsTab.permissions.rawValue
            self.settingsState.refreshPermissions()
            self.settingsWindow.show()
        }
        menuBarManager.onMenuWillOpen = { [weak self] in
            self?.refreshPermissions()
        }
        menuBarManager.onToggleHotReload = { [weak self] value in
            self?.setHotReload(value)
        }
        menuBarManager.onReviewPending = { [weak self] in
            self?.reviewPendingPlugins()
        }
        menuBarManager.updateLauncherShortcut(resolveHotkey())
        menuBarManager.setVisible(readUIValue("showMenuBarIcon") as? Bool ?? true)

        appSearchProvider = AppSearchProvider()

        let launcherFrame = LauncherFrame()
        let launcherView = LauncherView(
            prefs: launcherPrefs,
            session: launcherSession,
            windowFrame: launcherFrame,
            onExecuteCommand: { [weak self] id, args in
                self?.executeCommand(id, args: args)
            },
            onRevealInFinder: { [weak self] id in
                guard let self, !id.hasPrefix("launcher:") else { return }
                appLogger.notice("launcher reveal \(id, privacy: .public)")
                // Finder cannot come forward while the floating launcher panel
                // still holds key focus, so hide it first, as Return does.
                self.launcherPanel.dismiss()
                if id.hasPrefix("/") {
                    NSWorkspace.shared.revealInFinder(URL(fileURLWithPath: id))
                } else {
                    self.appSearchProvider.revealInFinder(bundleID: id)
                }
            },
            onSearch: { [weak self] query in
                self?.search(query) ?? []
            },
            onAssignShortcut: { [weak self] id, combo, title in
                guard let self else { return }
                let saved = self.saveShortcut(
                    id: id,
                    combo: combo,
                    tableKey: "commandShortcuts",
                    otherKey: "keyboardShortcuts"
                )
                guard saved, !combo.isEmpty else { return }
                self.launcherPanel.dismiss()
                ToastHost.shared.flash("\(KeyCombo.glyphs(combo).joined()) will open \(title)")
            },
            onToggleFavorite: { [weak self] id in
                self?.toggleFavorite(id)
            },
            onOpenSettings: { [weak self] in
                guard let self else { return }
                self.launcherPanel.dismiss()
                self.openSettingsAction()
            },
            onHeightChange: { [weak self] height in
                self?.launcherPanel.requestHeight(height)
            }
        )
        let hostingView = PinnedHostingView(rootView: launcherView)
        hostingView.sizingOptions = []
        hostingView.safeAreaRegions = []
        launcherPanel = LauncherPanel(contentView: hostingView, windowFrame: launcherFrame)
        launcherPanel.onHide = { [weak self] in
            self?.launcherSession.reset()
        }
        hotkeysOverlayPanel = HotkeysOverlayPanel()

        registerModules()
        installModuleManagerCallbacks()
        moduleManager.reloadAll()
        applyUIPrefsFromSettings()
        installLauncherHotkey()
        moduleManager.startWatching()
        refreshPermissions()
    }

    private func rebootstrap(workspaceRoot: URL) {
        moduleManager?.stopWatching()
        if let id = launcherHotKeyID {
            CarbonHotKeys.shared.unregister(id)
            launcherHotKeyID = nil
        }

        PluginWorkspace.savePath(workspaceRoot)
        workspace = PluginWorkspace(root: workspaceRoot)
        do {
            try workspace.ensureReady()
        } catch {
            NSLog("[Macotron] Failed to init workspace: \(error)")
        }

        moduleManager = ModuleManager(engine: engine, workspace: workspace)
        installModuleManagerCallbacks()
        settingsState.configDirURL = workspaceRoot
        moduleManager.reloadAll()
        applyUIPrefsFromSettings()
        menuBarManager?.setVisible(readUIValue("showMenuBarIcon") as? Bool ?? true)
        menuBarManager?.updateLauncherShortcut(resolveHotkey())
        installLauncherHotkey()
        moduleManager.startWatching()
        settingsState.load()
    }

    private func installModuleManagerCallbacks() {
        moduleManager.onDidReload = { [weak self] in
            let timer = StepTimer("onDidReload", category: "app")
            self?.refreshPermissions()
            timer.step("refreshPermissions")
            self?.applyUIPrefsFromSettings()
            timer.step("applyUIPrefs")
            self?.installCommandShortcuts()
            timer.step("installCommandShortcuts")
            self?.rebindPluginHotkeys()
            timer.step("rebindPluginHotkeys")
            self?.settingsState.refreshModules()
            timer.step("refreshModules")
            self?.refreshIntegrity()
            timer.step("refreshIntegrity")
        }
        moduleManager.onPendingReviewChange = { [weak self] in
            self?.refreshIntegrity()
        }
    }

    // MARK: - Settings

    private func setupSettings() {
        settingsState.configDirURL = workspace.root

        settingsState.readHotkey = { [weak self] in
            self?.resolveHotkey() ?? "opt+space"
        }
        settingsState.writeHotkey = { [weak self] combo in
            guard let self else { return }
            try? self.workspace.updateSettings { settings in
                var launcher = settings["launcher"] as? [String: Any] ?? [:]
                launcher["hotkey"] = combo
                settings["launcher"] = launcher
            }
            self.engine.configStore = self.workspace.readSettings()
            self.installLauncherHotkey()
        }
        settingsState.readShowHotkeysHotkey = { [weak self] in
            guard let self else { return "" }
            let table = CommandShortcuts.load(from: self.workspace.readSettings()["commandShortcuts"])
            return table.combo(for: HostCommands.showHotkeysID)
        }

        settingsState.readUIValue = { [weak self] key in self?.readUIValue(key) }
        settingsState.writeUIValue = { [weak self] key, value in
            self?.writeUIValue(key, value)
        }
        settingsState.onSetHotReload = { [weak self] value in
            self?.setHotReload(value)
        }
        settingsState.onInstallCatalog = { [weak self] plugin, override in
            self?.installCatalogPlugin(plugin, override: override)
        }
        settingsState.restoreStatusItem = { [weak self] id in
            self?.menuBarManager?.restoreStatus(id: id)
        }
        settingsState.onInstallAll = { [weak self] plugins in
            self?.installCatalogPlugins(plugins)
        }
        settingsState.onReviewPending = { [weak self] only in
            self?.reviewPendingPlugins(only: only)
        }

        settingsState.loadModuleSummaries = { [weak self] in
            self?.buildPluginSummaries() ?? []
        }
        settingsState.loadAppShortcuts = { [weak self] in
            guard let self else { return [] }
            let table = CommandShortcuts.load(from: self.workspace.readSettings()["commandShortcuts"])
            return table.bindings.keys.compactMap { id -> AppShortcutSummary? in
                guard self.engine.commandRegistry[id] == nil,
                      HostCommands.definition(for: id) == nil,
                      let app = self.appSearchProvider.entry(bundleID: id) else { return nil }
                return AppShortcutSummary(
                    id: app.bundleID, name: app.name, icon: app.icon, shortcut: table.combo(for: id)
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        settingsState.searchInstalledApps = { [weak self] query in
            guard let self else { return [] }
            return self.appSearchProvider.matching(query, limit: query.isEmpty ? 40 : 24).map { app in
                AppShortcutSummary(id: app.bundleID, name: app.name, icon: app.icon)
            }
        }
        engine.onPluginChecksChanged = { [weak self] in
            self?.settingsState.refreshModules()
        }
        engine.onOpenPluginSettings = { [weak self] file in
            self?.settingsState.requestedTab = SettingsTab.plugins.rawValue
            self?.settingsState.requestedPlugin = file
            self?.settingsWindow.show()
        }
        settingsState.deleteModule = { [weak self] filename in
            guard let self else { return false }
            if self.moduleManager.deleteModule(filename: filename) {
                self.moduleManager.reloadAll()
                return true
            }
            return false
        }
        settingsState.openModuleFile = { [weak self] filename in
            guard let self else { return }
            let url = self.moduleManager.configDir.appending(path: "plugins").appending(path: filename)
            NSWorkspace.shared.open(url)
        }
        settingsState.revealModuleFile = { [weak self] filename in
            guard let self else { return }
            let url = self.moduleManager.configDir.appending(path: "plugins").appending(path: filename)
            NSWorkspace.shared.revealInFinder(url)
        }
        settingsState.saveModuleOption = { [weak self] filename, key, value in
            guard let self else { return }
            self.moduleManager.saveModuleOption(filename: filename, key: key, value: value)
            self.moduleManager.reloadAll()
        }
        settingsState.saveModuleSecret = { [weak self] filename, key, secret in
            guard let self else { return }
            self.moduleManager.saveModuleSecret(filename: filename, key: key, secret: secret)
            self.moduleManager.reloadAll()
        }
        settingsState.clearModuleSecret = { [weak self] filename, key in
            guard let self else { return }
            self.moduleManager.clearModuleSecret(filename: filename, key: key)
            self.moduleManager.reloadAll()
        }
        settingsState.saveCommandShortcut = { [weak self] commandId, combo in
            self?.saveShortcut(
                id: commandId,
                combo: combo,
                tableKey: "commandShortcuts",
                otherKey: "keyboardShortcuts"
            )
        }
        settingsState.saveKeyboardShortcut = { [weak self] hotkeyId, combo in
            guard let self else { return }
            let defaultCombo = self.engine.hotkeyRegistry[hotkeyId]?.defaultCombo ?? ""
            self.saveShortcut(
                id: hotkeyId,
                combo: combo,
                tableKey: "keyboardShortcuts",
                otherKey: "commandShortcuts",
                defaultCombo: defaultCombo
            )
        }
        settingsState.setModuleEnabled = { [weak self] filename, enabled in
            guard let self else { return }
            self.moduleManager.setModuleEnabled(filename: filename, enabled: enabled)
            self.moduleManager.reloadAll()
            self.settingsState.refreshModules()
        }
        settingsState.changePluginsFolder = { [weak self] in
            self?.pickAndSwitchPluginsFolder()
        }
        settingsState.openPluginsFolder = { [weak self] in
            guard let root = self?.workspace.root else { return }
            NSWorkspace.shared.open(root)
        }
        settingsState.createPlugin = { [weak self] filename, source in
            self?.createPlugin(filename: filename, source: source)
        }
        settingsWindow = SettingsWindow(state: settingsState)
        let review: () -> Void = { [weak self] in self?.reviewPendingPlugins() }
        NotifyModule.onTap["macotron.new-plugin"] = review
        NotifyModule.onTap["macotron.pending-review"] = review
    }

    private func nonEmptyString(_ value: Any?) -> String? {
        guard let s = value as? String, !s.isEmpty else { return nil }
        return s
    }

    private func declaredPermissions(meta: [String: Any], header: PluginHeader.Info) -> [Permission] {
        let running = (meta["permissions"] as? [Any] ?? []).compactMap {
            ($0 as? String).flatMap(Permissions.parse)
        }
        return running.isEmpty ? header.permissions.compactMap(Permissions.parse) : running
    }

    private func buildPluginSummaries() -> [ModuleSummary] {
        StepTimer.measure("buildPluginSummaries") { buildPluginSummariesBody() }
    }

    private func buildPluginSummariesBody() -> [ModuleSummary] {
        let errorMap = Dictionary(
            moduleManager.lastReloadErrors.map { ($0.filename, $0.error) },
            uniquingKeysWith: { first, _ in first }
        )
        let metadata = engine.moduleMetadata
        // A disabled plugin declares nothing this run; fall back to what it
        // declared last time so its options stay on the page.
        let remembered = moduleManager.rememberedMetadata()
        let settingsJSON = workspace.readSettings()
        let settings = settingsJSON["pluginSettings"] as? [String: [String: Any]] ?? [:]
        let disabled = Set(settingsJSON["disabledPlugins"] as? [String] ?? [])
        let shortcuts = CommandShortcuts.load(from: settingsJSON["commandShortcuts"])
        let keyboardShortcuts = CommandShortcuts.load(from: settingsJSON["keyboardShortcuts"])
        var summaries: [ModuleSummary] = []

        for file in moduleManager.listModules(directory: "plugins") {
            let isEnabled = !disabled.contains(file.filename)
            let events = isEnabled ? (engine.pluginEvents[file.filename] ?? []) : []

            let meta = metadata[file.filename] ?? remembered[file.filename] ?? [:]
            let metaTitle = nonEmptyString(meta["title"])
            let metaDescription = nonEmptyString(meta["description"])
            let header = (metaTitle == nil || metaDescription == nil)
                ? PluginHeader.parse(file: workspace.pluginsDir.appending(path: file.filename))
                : PluginHeader.Info()
            let title = metaTitle ?? header.title ?? file.filename
            let description = metaDescription ?? header.description ?? file.description
            let fileSettings = settings[file.filename] ?? [:]
            var options: [ModuleOption] = []

            if let optionsDefs = meta["options"] as? [String: [String: Any]] {
                for (key, def) in optionsDefs.sorted(by: { $0.key < $1.key }) {
                    let type = def["type"] as? String ?? "string"
                    let label = def["label"] as? String ?? key
                    let defaultValue = def["default"] ?? ""
                    let currentValue = fileSettings[key] ?? defaultValue
                    let required = def["required"] as? Bool ?? false
                    let placeholder = def["placeholder"] as? String ?? ""
                    let help = def["help"] as? String ?? ""

                    let choices = ((def["choices"] as? [[String: Any]]) ?? []).compactMap { choice -> ModuleOptionChoice? in
                        guard let value = choice["value"] as? String,
                              let choiceLabel = choice["label"] as? String else { return nil }
                        return ModuleOptionChoice(value: value, label: choiceLabel)
                    }
                    if type == "dropdown" && choices.isEmpty {
                        NSLog("[Macotron] \(file.filename): dropdown option '\(key)' is missing choices")
                    }

                    let isSet: Bool
                    switch type {
                    case "password":
                        isSet = !(fileSettings[key] as? String ?? "").isEmpty
                    case "boolean", "number":
                        isSet = (fileSettings[key] ?? def["default"]) != nil
                    default:
                        isSet = !(((fileSettings[key] ?? def["default"]) as? String) ?? "").isEmpty
                    }

                    options.append(ModuleOption(
                        key: key, label: label, type: type, currentValue: currentValue,
                        required: required, isSet: isSet, choices: choices,
                        placeholder: placeholder, help: help
                    ))
                }
            }

            let commands = engine.commandRegistry.values
                .filter { $0.pluginFile == file.filename }
                .sorted { $0.name < $1.name }
                .map {
                    PluginCommandSummary(
                        id: $0.id,
                        name: $0.name,
                        shortcut: shortcuts.combo(for: $0.id)
                    )
                }

            let hotkeys = engine.hotkeyRegistry.values
                .filter { $0.pluginFile == file.filename }
                .sorted { $0.key < $1.key }
                .map {
                    PluginCommandSummary(
                        id: $0.id,
                        name: $0.key,
                        shortcut: keyboardShortcuts.resolved($0.id, default: $0.defaultCombo)
                    )
                }

            let errorMsg = errorMap[file.filename]
            summaries.append(ModuleSummary(
                filename: file.filename,
                title: title,
                description: description,
                help: meta["help"] as? String ?? "",
                checks: engine.pluginChecks[file.filename] ?? [],
                options: options,
                events: events,
                hotkeys: hotkeys,
                hasErrors: errorMsg != nil,
                errorMessage: errorMsg,
                isEnabled: isEnabled,
                commands: commands,
                // A plugin that is disabled, or quarantined until its source is
                // reviewed, never runs and so declares nothing at runtime. Its
                // header still says what it needs, so read that instead.
                permissions: declaredPermissions(meta: meta, header: header),
                hiddenStatusItems: hiddenStatusItems(of: file.filename),
                sourceHash: PluginHash.sha256(
                    file: workspace.pluginsDir.appending(path: file.filename)) ?? ""
            ))
        }

        summaries.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        return summaries
    }

    // MARK: - Wizard

    private func showSetupWizard() {
        wizardState.startFullSetup()
        configureWizard()
        presentWizard()
    }

    /// AXIsProcessTrusted answers false for a moment after a login-item launch,
    /// before TCC has this process registered, so a check at t=0 puts the wizard
    /// on screen for a permission that is already granted. Ask a few times and
    /// only nag if it is still missing.
    private func nagAboutPermissionsIfStillMissing(attempt: Int = 0) {
        guard Permissions.missing(from: requiredPermissions())
            .contains(where: \.isAutoRequestable) else { return }
        guard attempt >= 2 else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.nagAboutPermissionsIfStillMissing(attempt: attempt + 1)
            }
            return
        }
        showPermissionsWizard()
    }

    /// Shown at startup when setup is done but macOS permissions are missing.
    private func showPermissionsWizard() {
        wizardState.startPermissionsOnly()
        configureWizard()
        presentWizard()
    }

    private func presentWizard() {
        settingsState.catalogPlugins = PluginCatalog.load()
        settingsState.refreshPermissions()
        wizardWindow = WizardWindow(state: wizardState, permissions: settingsState)
        wizardWindow?.show()
    }

    private func configureWizard() {
        wizardState.pickFolder = {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.allowsMultipleSelection = false
            panel.prompt = "Choose"
            panel.message = "Select a folder for Macotron plugins"
            guard panel.runModal() == .OK, let url = panel.url else { return nil }
            return url
        }
        wizardState.initWorkspace = { [weak self] url in
            guard let self else { return false }
            PluginWorkspace.savePath(url)
            let ws = PluginWorkspace(root: url)
            do {
                try ws.ensureReady()
            } catch {
                return false
            }
            if self.moduleManager == nil {
                self.bootstrap(workspaceRoot: url)
            } else {
                self.rebootstrap(workspaceRoot: url)
            }
            return true
        }
        wizardState.onComplete = { [weak self] in
            guard let self else { return }
            let openSettings = self.wizardState.currentStep == .ready
            self.wizardWindow?.close()
            self.wizardWindow = nil
            UserDefaults.standard.set(true, forKey: AppDelegate.wizardCompletedKey)
            self.installLauncherHotkey()
            if openSettings {
                self.settingsWindow?.show()
            }
        }
    }

    private func pickAndSwitchPluginsFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        PluginWorkspace.savePath(url)
        rebootstrap(workspaceRoot: url)
    }

    // MARK: - Hotkey / prefs

    private func installLauncherHotkey() {
        if let id = launcherHotKeyID {
            CarbonHotKeys.shared.unregister(id)
            launcherHotKeyID = nil
        }
        guard moduleManager != nil else { return }
        let combo = resolveHotkey()
        if let parsed = KeyCombo.parse(combo) {
            launcherHotKeyID = CarbonHotKeys.shared.register(
                keyCode: UInt32(parsed.keyCode),
                carbonModifiers: parsed.carbonModifiers
            ) { [weak self] in
                Task { @MainActor in
                    self?.launcherPanel.showReason = "hotkey \(combo)"
                    self?.launcherPanel.toggle()
                }
            }
        }
        menuBarManager.updateLauncherShortcut(combo)
    }

    // MARK: - Permissions

    /// Baseline plus whatever the loaded plugins declared.
    private func requiredPermissions() -> [Permission] {
        Permissions.required(declaredBy: engine?.declaredPermissions ?? [])
    }

    /// Re-check whenever the user comes back from System Settings. Macotron runs
    /// as an accessory app, so its own activation is not enough — watch every app
    /// switch, and refresh again right before the menu opens.
    private func observePermissionTriggers() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                AppActivation.noteBecameActive()
                Permissions.invalidate()
                self?.refreshPermissions()
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { AppActivation.noteResignedActive() }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                Permissions.invalidate()
                self?.refreshPermissions()
            }
        }
    }

    /// Re-check every required permission and update the menu bar and Settings.
    /// The first check also registers Macotron in the System Settings lists, so
    /// the user can find the toggles without hunting for the app.
    private func refreshPermissions() {
        StepTimer.measure("refreshPermissions") { refreshPermissionsBody() }
    }

    private func refreshPermissionsBody() {
        let required = requiredPermissions()
        let missing = Permissions.missing(from: required)

        missingPermissions = missing
        let unregistered = missing.filter { !registeredPermissions.contains($0) }
        if !unregistered.isEmpty {
            registeredPermissions.formUnion(unregistered)
            Permissions.registerWithSystem(unregistered)
        }

        menuBarManager?.setMissingPermissions(missing.filter(\.isAutoRequestable))
        settingsState.refreshPermissions()
        schedulePermissionPolling(active: !missing.isEmpty)
    }

    /// Poll while anything is missing, so the warning clears as soon as the user
    /// flips a toggle in System Settings.
    private func schedulePermissionPolling(active: Bool) {
        guard active else {
            permissionTimer?.invalidate()
            permissionTimer = nil
            return
        }
        guard permissionTimer == nil else { return }
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshPermissions() }
        }
        // .common so the check keeps running while a menu is open or a window drags.
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer
    }

    private func resolveHotkey() -> String {
        if let launcher = engine.configStore["launcher"] as? [String: Any],
           let hotkey = launcher["hotkey"] as? String {
            return hotkey
        }
        if let workspace,
           let launcher = workspace.readSettings()["launcher"] as? [String: Any],
           let hotkey = launcher["hotkey"] as? String {
            return hotkey
        }
        return "opt+space"
    }

    private func readUIValue(_ key: String) -> Any? {
        if let ui = engine?.configStore["ui"] as? [String: Any], let value = ui[key] {
            return value
        }
        if let workspace, let ui = workspace.readSettings()["ui"] as? [String: Any] {
            return ui[key]
        }
        return nil
    }

    private func writeUIValue(_ key: String, _ value: Any) {
        try? workspace.updateSettings { settings in
            var ui = settings["ui"] as? [String: Any] ?? [:]
            ui[key] = value
            settings["ui"] = ui
        }
        engine.configStore = workspace.readSettings()
        // Every ui.* pref drives something live. Re-apply the whole block
        // rather than keeping a side effect per key: the Settings pane writes
        // one at a time and re-reading a handful of values is free.
        applyUIPrefsFromSettings()
        menuBarManager?.setVisible(readUIValue("showMenuBarIcon") as? Bool ?? true)
    }

    private func applyUIPrefsFromSettings() {
        AppearanceSetting.parse(readUIValue("appearance")).apply()
        let rawScale = readUIValue("textScale") as? Double ?? 1.0
        launcherPrefs.textScale = CGFloat(LauncherPrefs.snapTextScale(rawScale))
        let background = LauncherBackground.parse(readUIValue("launcherBackground"))
        launcherPrefs.background = background
        launcherPanel?.applyBackground(background)
        refreshIntegrity()
    }

    private func setHotReload(_ value: Bool) {
        moduleManager?.hotReload = value
        settingsState.hotReload = value
        // Turning it on lifts the approval gate, so run the plugins that were
        // held back instead of leaving them quarantined until the next launch.
        if value {
            moduleManager?.reloadAll()
            settingsState.refreshModules()
        }
        refreshIntegrity()
    }

    private func hiddenStatusItems(of filename: String) -> [String] {
        let owners = menuBarPluginModule?.statusOwners ?? [:]
        return (menuBarManager?.hiddenStatusIDs ?? [])
            .filter { owners[$0] == filename }
            .sorted()
    }

    private var announcedPendingReview = false
    private var announcedNewPlugins: Set<String> = []

    private func refreshIntegrity() {
        let pending = moduleManager?.pendingReview ?? []
        settingsState.pendingReview = pending.sorted()
        // A plugin the ledger has never seen is new on disk, not an edit: it
        // has never run, so the wording is "load", not "reload".
        let added = pending.filter { !PluginTrust.isKnown(filename: $0) }
        settingsState.newPlugins = added
        let changed = pending.subtracting(added)
        // Nothing runs a new plugin until it is reviewed, and dropping a file
        // in the plugins folder is otherwise silent — say so as it lands.
        let unannounced = added.subtracting(announcedNewPlugins).sorted()
        if !unannounced.isEmpty {
            announcedNewPlugins.formUnion(unannounced)
            NotifyModule.post(
                title: "Macotron",
                body: unannounced.count == 1
                    ? "New plugin \(unannounced[0]) added — click to review"
                    : "\(unannounced.count) new plugins added — click to review",
                id: "macotron.new-plugin"
            )
        }
        // An edited plugin is quarantined and simply stops running, taking its
        // menu bar item with it. Say so once, at launch, where a notification
        // waits in Notification Centre -- a toast on every edit interrupts the
        // editing it is reporting on.
        if !announcedPendingReview {
            announcedPendingReview = true
            if !changed.isEmpty {
                NotifyModule.post(
                    title: "Macotron",
                    body: changed.count == 1
                        ? "1 plugin has updated and needs review"
                        : "\(changed.count) plugins have updated and need review",
                    id: "macotron.pending-review"
                )
            }
        }
        if let dir = workspace?.pluginsDir,
           let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            settingsState.installedPluginNames = Set(files.filter { $0.pathExtension == "js" }.map(\.lastPathComponent))
        }
        menuBarManager?.setIntegrityState(
            hotReload: moduleManager?.hotReload ?? false,
            pendingCount: pending.count
        )
    }

    private func scanCatalogPlugin(_ plugin: CatalogPlugin) {
        settingsState.scanning = true
        settingsState.scanReport = nil
        scanTask?.cancel()
        scanTask = Task { @MainActor in
            let report = await PluginScanner.scan(
                source: plugin.source,
                title: plugin.title,
                permissions: plugin.permissions.map(\.rawValue)
            )
            guard !Task.isCancelled else { return }
            settingsState.applyScanReport(report)
        }
    }

    /// Write a plugin into the workspace and trust it outright: every caller
    /// here is acting on something the user explicitly asked for, so it skips
    /// Review & Reload. Reloading is left to the caller so a bulk install can
    /// reload once instead of once per file.
    @discardableResult
    private func writePlugin(
        _ filename: String, source: String, in workspace: PluginWorkspace
    ) throws -> URL {
        let dest = workspace.pluginsDir.appending(path: filename)
        try source.write(to: dest, atomically: true, encoding: .utf8)
        PluginTrust.approve(filename: filename, source: source)
        PluginTrust.approveImports(
            in: source, importerDir: workspace.pluginsDir, baseDir: workspace.root)
        return dest
    }

    private func installCatalogPlugin(_ plugin: CatalogPlugin, override: Bool) {
        let timer = StepTimer("install \(plugin.filename)", category: "app")
        guard let workspace else { return }
        guard settingsState.allowsInstall(of: plugin, override: override) else {
            appLogger.info("install \(plugin.filename, privacy: .public) blocked by allowsInstall")
            return
        }
        do {
            try writePlugin(plugin.filename, source: plugin.source, in: workspace)
            timer.step("write")
            moduleManager.reloadAll()
            timer.step("reloadAll")
            refreshIntegrity()
            timer.step("refreshIntegrity")
            if settingsState.isReviewing {
                presentNextReview(workspace: workspace)
                timer.step("presentNextReview")
            }
            timer.total()
        } catch {
            NSLog("[Macotron] Catalog install failed: \(error)")
        }
    }

    /// Bulk add. One reload at the end: reloading per plugin would replay every
    /// other plugin once per file.
    private func installCatalogPlugins(_ plugins: [CatalogPlugin]) {
        let timer = StepTimer("install \(plugins.count) plugins", category: "app")
        guard let workspace else { return }
        var installed = 0
        for plugin in plugins {
            let dest = workspace.pluginsDir.appending(path: plugin.filename)
            guard !FileManager.default.fileExists(atPath: dest.path(percentEncoded: false)) else {
                continue
            }
            do {
                try writePlugin(plugin.filename, source: plugin.source, in: workspace)
                installed += 1
            } catch {
                NSLog("[Macotron] Catalog install failed for \(plugin.filename): \(error)")
            }
        }
        timer.step("wrote \(installed)")
        guard installed > 0 else { return }
        moduleManager.reloadAll()
        timer.step("reloadAll")
        refreshIntegrity()
        timer.total()
    }

    /// The user authored these bytes here, so trust them straight away instead of
    /// sending the new file to Review & Reload.
    private func createPlugin(filename: String, source: String) {
        guard let workspace else { return }
        do {
            let dest = try writePlugin(filename, source: source, in: workspace)
            moduleManager.reloadAll()
            refreshIntegrity()
            settingsState.refreshModules()
            NSWorkspace.shared.open(dest)
        } catch {
            NSLog("[Macotron] Could not create \(filename): \(error)")
        }
    }

    /// `only` reviews one plugin, for the button on that plugin's own page.
    private func reviewPendingPlugins(only: String? = nil) {
        guard let workspace else { return }
        settingsState.requestedTab = SettingsTab.plugins.rawValue
        settingsWindow?.show()
        reviewOnly = only
        presentNextReview(workspace: workspace)
    }

    private var reviewOnly: String?

    private func presentNextReview(workspace: PluginWorkspace) {
        let queue = settingsState.pendingReview.first ?? moduleManager?.pendingReview.sorted().first
        // Reviewing one plugin ends when that plugin does, rather than walking
        // on into the rest of the queue.
        let next = reviewOnly.map { settingsState.pendingReview.contains($0) ? $0 : nil } ?? queue
        guard let name = next else {
            reviewOnly = nil
            settingsState.installTarget = nil
            settingsState.isReviewing = false
            return
        }
        let file = workspace.pluginsDir.appending(path: name)
        guard let source = try? String(contentsOf: file, encoding: .utf8) else { return }
        settingsState.beginReview(filename: name, source: source, destHash: PluginHash.sha256(file: file), fileURL: file)
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Macotron", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings...", action: #selector(openSettingsAction), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Macotron", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        // A text field's undo stack is only reachable through these menu
        // items: the field editor never sees the key equivalent otherwise.
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func openSettingsAction() {
        launcherPanel?.orderOut(nil)
        settingsWindow?.show()
    }

    private func registerModules() {
        registerStandardModules(in: engine)

        let keyboard = KeyboardModule()
        keyboard.onHostCommand = { [weak self] commandId in
            self?.handleCommandShortcut(commandId)
        }
        self.keyboardModule = keyboard
        engine.addModule(keyboard)

        engine.addModule(LocalStorageModule(configDir: workspace.root.path(percentEncoded: false)))

        let menuBarModule = MenuBarModule()
        menuBarModule.delegate = menuBarManager
        menuBarPluginModule = menuBarModule
        engine.addModule(menuBarModule)

        let launcher = LauncherModule()
        launcher.onLiveUpdate = { [weak self] in
            guard let self, self.launcherPanel.isVisible else { return }
            self.launcherSession.refresh()
        }
        launcherModule = launcher
        engine.addModule(launcher)
    }

    private func executeCommand(_ id: String, args: [String: Any] = [:]) {
        StepTimer.measure("execute \(id)") { executeCommandBody(id, args: args) }
    }

    private func executeCommandBody(_ id: String, args: [String: Any]) {
        launcherPanel.dismiss()
        recordUse(id)
        if runHostCommand(id) {
            return
        }
        if engine.commandRegistry[id] != nil {
            _ = engine.invokeCommand(id, args: args)
            return
        }
        if launcherModule?.run(id) == true {
            return
        }
        appSearchProvider.launchApp(bundleID: id)
    }

    @discardableResult
    private func runHostCommand(_ id: String) -> Bool {
        switch id {
        case HostCommands.showHotkeysID:
            showHotkeysOverlay()
            return true
        case HostCommands.openSettingsID:
            openSettingsAction()
            return true
        case HostCommands.openPluginsID:
            settingsState.requestedTab = SettingsTab.plugins.rawValue
            openSettingsAction()
            return true
        case HostCommands.quitID:
            launcherPanel?.dismiss()
            NSApp.terminate(nil)
            return true
        case HostCommands.fixPermissionsID:
            settingsState.requestedTab = SettingsTab.permissions.rawValue
            openSettingsAction()
            return true
        case HostCommands.resetRankingID:
            try? workspace.updateSettings { $0["launcherUses"] = [String: Int]() }
            ToastHost.shared.flash("Launcher ranking reset")
            return true
        default:
            return false
        }
    }

    private func showHotkeysOverlay() {
        launcherPanel.dismiss()
        hotkeysOverlayPanel.toggle(rows: ShortcutConflicts.hotkeyRows(from: currentShortcutClaims()))
    }

    private func currentShortcutClaims() -> [ShortcutConflicts.Claim] {
        let table = CommandShortcuts.load(from: workspace.readSettings()["commandShortcuts"])
        let apps = table.bindings.keys.compactMap { id -> AppShortcutSummary? in
            guard engine.commandRegistry[id] == nil,
                  HostCommands.definition(for: id) == nil,
                  let app = appSearchProvider.entry(bundleID: id) else { return nil }
            return AppShortcutSummary(id: app.bundleID, name: app.name, icon: app.icon, shortcut: table.combo(for: id))
        }
        return ShortcutConflicts.claims(
            launcher: resolveHotkey(),
            apps: apps,
            modules: settingsState.moduleSummaries,
            commandShortcuts: table
        )
    }

    private func handleCommandShortcut(_ commandId: String) {
        StepTimer.measure("command shortcut \(commandId)") { handleCommandShortcutBody(commandId) }
    }

    private func handleCommandShortcutBody(_ commandId: String) {
        if runHostCommand(commandId) {
            return
        }
        guard let cmd = engine.commandRegistry[commandId] else {
            if launcherPanel.isVisible {
                launcherPanel.dismiss()
            }
            if launcherModule?.run(commandId) == true {
                return
            }
            appSearchProvider.launchApp(bundleID: commandId, hideIfFrontmost: true)
            return
        }
        switch CommandArgumentResolver.resolve(specs: cmd.arguments, raw: [:]) {
        case .success(let values):
            _ = engine.invokeCommand(commandId, args: values)
        case .failure:
            launcherSession.pendingArgs = .init(
                commandId: cmd.id,
                title: cmd.name,
                arguments: cmd.arguments
            )
            if !launcherPanel.isVisible {
                launcherPanel.showReason = "command \(cmd.id) needs arguments"
                launcherPanel.toggle()
            }
        }
    }

    @discardableResult
    private func saveShortcut(
        id: String,
        combo: String,
        tableKey: String,
        otherKey: String,
        defaultCombo: String? = nil
    ) -> Bool {
        if !combo.isEmpty, combo.lowercased() == resolveHotkey().lowercased() {
            NSLog("[Macotron] Shortcut collides with the launcher hotkey")
            return false
        }
        var stored = combo
        if let defaultCombo {
            if combo.isEmpty {
                stored = CommandShortcuts.unbound
            } else if combo.lowercased() == defaultCombo.lowercased() {
                stored = ""
            }
        }
        try? workspace.updateSettings { settings in
            var table = CommandShortcuts.load(from: settings[tableKey])
            table.assign(commandId: id, combo: stored)
            let pluginDefaults = Dictionary(
                uniqueKeysWithValues: engine.hotkeyRegistry.values.map { ($0.id, $0.defaultCombo) }
            )
            if tableKey == "keyboardShortcuts" {
                table.unbindMatching(combo: stored, defaults: pluginDefaults, except: id)
            }
            settings[tableKey] = table.jsonObject()
            if !stored.isEmpty, stored != CommandShortcuts.unbound {
                var other = CommandShortcuts.load(from: settings[otherKey])
                other.removeCombo(stored)
                if otherKey == "keyboardShortcuts" {
                    other.unbindMatching(combo: stored, defaults: pluginDefaults)
                }
                settings[otherKey] = other.jsonObject()
                stealKeybindingOptions(combo: stored, from: &settings)
            }
        }
        engine.configStore = workspace.readSettings()
        installCommandShortcuts()
        rebindPluginHotkeys()
        settingsState.refreshModules()
        settingsState.refreshAppShortcuts()
        return true
    }

    /// Plugin option hotkeys live in pluginSettings, not the shortcut tables.
    private func stealKeybindingOptions(combo: String, from settings: inout [String: Any]) {
        let wanted = combo.lowercased()
        let metadata = engine.moduleMetadata
        var pluginSettings = settings["pluginSettings"] as? [String: [String: Any]] ?? [:]
        var changed = false
        for (filename, defs) in metadata {
            guard let options = defs["options"] as? [String: [String: Any]] else { continue }
            var fileSettings = pluginSettings[filename] ?? [:]
            var fileChanged = false
            for (key, def) in options {
                guard (def["type"] as? String) == "keybinding" else { continue }
                let current = ((fileSettings[key] ?? def["default"]) as? String ?? "").lowercased()
                if current == wanted {
                    fileSettings[key] = ""
                    fileChanged = true
                }
            }
            if fileChanged {
                pluginSettings[filename] = fileSettings
                changed = true
            }
        }
        if changed {
            settings["pluginSettings"] = pluginSettings
        }
    }

    private func installCommandShortcuts() {
        let table = CommandShortcuts.load(from: workspace.readSettings()["commandShortcuts"])
        keyboardModule?.setHostBindings(table.bindings.map { (commandId: $0.key, combo: $0.value) })
    }

    private func rebindPluginHotkeys() {
        let table = CommandShortcuts.load(from: workspace.readSettings()["keyboardShortcuts"])
        keyboardModule?.setPluginBindings(
            engine.hotkeyRegistry.values.map { hotkey in
                (eventName: "keyboard:\(hotkey.id)", combo: table.resolved(hotkey.id, default: hotkey.defaultCombo))
            }
        )
    }

    private func search(_ query: String) -> [SearchResult] {
        StepTimer.measure("search") { searchBody(query) }
    }

    private func searchBody(_ query: String) -> [SearchResult] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let pluginHits = launcherModule?.allHits() ?? []
        let settings = workspace.readSettings()
        let favorites = Self.favoriteIDs(from: settings["launcherFavorites"])
        let shortcuts = CommandShortcuts.load(from: settings["commandShortcuts"])
        let uses = settings["launcherUses"] as? [String: Int] ?? [:]

        if q.isEmpty {
            // Favorites first, then what actually gets picked: the launcher
            // opens onto the usual suspects before a letter is typed.
            let frequent = uses
                .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
                .map(\.key)
                .filter { !favorites.contains($0) }
                .compactMap { id in
                    result(id: id, pluginHits: pluginHits, shortcuts: shortcuts, isFavorite: false)
                }
                .prefix(5)
            return permissionResult() + favorites.compactMap { id in
                result(id: id, pluginHits: pluginHits, shortcuts: shortcuts, isFavorite: true)
            } + frequent
        }

        var results: [SearchResult] = []

        for host in HostCommands.all {
            if let score = FuzzyMatch.score(query: q, target: host.name), score > 0 {
                results.append(SearchResult(
                    id: host.id,
                    title: host.name,
                    subtitle: host.description,
                    type: .command,
                    shortcut: shortcuts.combo(for: host.id),
                    isFavorite: favorites.contains(host.id)
                ))
            }
        }

        for (_, cmd) in engine.commandRegistry {
            if let score = FuzzyMatch.score(query: q, target: cmd.name), score > 0 {
                results.append(SearchResult(
                    id: cmd.id,
                    title: cmd.name,
                    subtitle: cmd.description,
                    type: .command,
                    commandArguments: cmd.arguments,
                    shortcut: shortcuts.combo(for: cmd.id),
                    isFavorite: favorites.contains(cmd.id)
                ))
            }
        }

        let apps = StepTimer.measure("search apps", threshold: 0.005) {
            appSearchProvider.matching(q, limit: 20)
        }
        results.append(contentsOf: apps.map { app in
            SearchResult(
                id: app.bundleID,
                title: app.name,
                subtitle: "",
                type: .app,
                nsImage: app.icon,
                shortcut: shortcuts.combo(for: app.bundleID),
                isFavorite: favorites.contains(app.bundleID)
            )
        })

        for hit in pluginHits {
            if FuzzyMatch.best(query: q, targets: [hit.title, hit.subtitle]) != nil {
                results.append(SearchResult(
                    id: hit.id,
                    title: hit.title,
                    subtitle: hit.subtitle,
                    type: .plugin,
                    nsImage: hit.image ?? fileIcon(hit.path),
                    kind: hit.kind,
                    isFavorite: favorites.contains(hit.id),
                    path: hit.path
                ))
            }
        }

        // A live row the typed text cannot find by name is answering the query
        // itself — a sum, a unit conversion — and leads, because "4" belongs
        // above every app sharing a letter with "2+2". A row that does match by
        // name is competing on that name, so it is ranked with everything else:
        // a symbol whose description happens to contain the word typed has no
        // claim on the top of the list. Providers that answer every query, not
        // only their own syntax, mark their rows secondary and lose ties.
        let live = StepTimer.measure("search live providers", threshold: 0.005) {
            launcherModule?.liveHits(query: q) ?? []
        }
        let row = { (hit: LauncherHit) in
            SearchResult(
                id: hit.id,
                title: hit.title,
                subtitle: hit.subtitle,
                type: .plugin,
                nsImage: hit.image ?? self.fileIcon(hit.path),
                kind: hit.kind,
                isFavorite: favorites.contains(hit.id),
                path: hit.path
            )
        }
        let answers = live.filter {
            !$0.secondary && FuzzyMatch.best(query: q, targets: [$0.title, $0.subtitle]) == nil
        }
        let answered = Set(answers.map(\.id))
        let rest = live.filter { !answered.contains($0.id) }

        return answers.map(row) + SearchResult.ranked(
            query: q,
            rows: results + rest.map(row),
            late: Set(rest.filter(\.secondary).map(\.id)),
            uses: uses,
            limit: max(0, 20 - answers.count)
        )
    }

    /// What gets picked is the best ranking signal there is, and the one the
    /// matcher cannot see. Counts persist in settings; the Reset Launcher
    /// Ranking command clears them.
    private func recordUse(_ id: String) {
        try? workspace.updateSettings { settings in
            var counts = settings["launcherUses"] as? [String: Int] ?? [:]
            counts[id, default: 0] += 1
            settings["launcherUses"] = counts
        }
    }

    /// Finder's icon for a row that lives on disk, so a folder looks like that
    /// folder. NSWorkspace resolves per call, so hits are kept for the panel's
    /// redraw rate.
    private func fileIcon(_ path: String) -> NSImage? {
        guard !path.isEmpty else { return nil }
        if let icon = fileIconCache[path] { return icon }
        // ponytail: drop the whole cache past 512 entries instead of LRU;
        // revisit if icon fetches ever show up in the search StepTimer.
        if fileIconCache.count > 512 { fileIconCache.removeAll() }
        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: 32, height: 32)
        fileIconCache[path] = icon
        return icon
    }

    /// Leads the empty-query list while Macotron is missing something it needs,
    /// so a half-working install says so instead of just misbehaving.
    private func permissionResult() -> [SearchResult] {
        guard !missingPermissions.isEmpty else { return [] }
        let names = missingPermissions.map(\.title).joined(separator: ", ")
        return [SearchResult(
            id: HostCommands.fixPermissionsID,
            title: "Fix Macotron Permissions...",
            subtitle: names,
            type: .command,
            warning: true
        )]
    }

    private func result(
        id: String,
        pluginHits: [LauncherHit],
        shortcuts: CommandShortcuts,
        isFavorite: Bool
    ) -> SearchResult? {
        if let hit = pluginHits.first(where: { $0.id == id }) {
            return SearchResult(
                id: hit.id,
                title: hit.title,
                subtitle: hit.subtitle,
                type: .plugin,
                nsImage: hit.image ?? fileIcon(hit.path),
                kind: hit.kind,
                isFavorite: isFavorite,
                path: hit.path
            )
        }
        if let host = HostCommands.definition(for: id) {
            return SearchResult(
                id: host.id,
                title: host.name,
                subtitle: host.description,
                type: .command,
                shortcut: shortcuts.combo(for: host.id),
                isFavorite: isFavorite
            )
        }
        if let cmd = engine.commandRegistry[id] {
            return SearchResult(
                id: cmd.id,
                title: cmd.name,
                subtitle: cmd.description,
                type: .command,
                commandArguments: cmd.arguments,
                shortcut: shortcuts.combo(for: cmd.id),
                isFavorite: isFavorite
            )
        }
        if let app = appSearchProvider.entry(bundleID: id) {
            return SearchResult(
                id: app.bundleID,
                title: app.name,
                subtitle: "",
                type: .app,
                nsImage: app.icon,
                shortcut: shortcuts.combo(for: app.bundleID),
                isFavorite: isFavorite
            )
        }
        return nil
    }

    private func toggleFavorite(_ id: String) {
        try? workspace.updateSettings { settings in
            var ids = Self.favoriteIDs(from: settings["launcherFavorites"])
            if let i = ids.firstIndex(of: id) { ids.remove(at: i) }
            else if !id.isEmpty { ids.append(id) }
            settings["launcherFavorites"] = ids
        }
        engine.configStore = workspace.readSettings()
    }

    private static func favoriteIDs(from object: Any?) -> [String] {
        let raw = (object as? [String]) ?? (object as? [Any])?.compactMap { $0 as? String } ?? []
        var seen = Set<String>()
        return raw.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

/// Every requirement but one is satisfied by MenuBarManager's own methods.
/// `addItem` is the exception: the protocol lives in Modules, which cannot see
/// MacotronUI's `MenuItemConfig`, so it passes the fields loose.
extension MenuBarManager: MenuBarModuleDelegate {
    public func menuBarAddItem(id: String, title: String, icon: String?, section: String?, onClick: (() -> Void)?, menu: [MenuBarEntry]) {
        addItem(id: id, config: MenuItemConfig(title: title, icon: icon, section: section, callback: onClick, menu: menu))
    }
}
