// AppDelegate.swift — NSApplicationDelegate, app lifecycle
import AppKit
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

    public func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()

        engine = Engine()

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

        let wizardDone = UserDefaults.standard.bool(forKey: AppDelegate.wizardCompletedKey)
        if !wizardDone || PluginWorkspace.resolveFromDefaults() == nil {
            showSetupWizard()
        } else {
            nagAboutPermissionsIfStillMissing()
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
            self?.moduleManager.reloadAll()
        }
        menuBarManager.onHiddenStatusChange = { [weak self] _ in
            self?.settingsState.refreshModules()
        }
        menuBarManager.onOpenConfig = { [weak self] in
            guard let self else { return }
            NSWorkspace.shared.open(self.workspace.root)
        }
        menuBarManager.onToggleLauncher = { [weak self] in
            self?.launcherPanel.toggle()
        }
        menuBarManager.onOpenSettings = { [weak self] in
            self?.launcherPanel.orderOut(nil)
            self?.settingsWindow.show()
        }
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
                self.appSearchProvider.revealInFinder(bundleID: id)
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

        settingsState.readShowDockIcon = { [weak self] in
            self?.readUIValue("showDockIcon") as? Bool ?? true
        }
        settingsState.writeShowDockIcon = { [weak self] value in
            self?.writeUIValue("showDockIcon", value)
            NSApp.setActivationPolicy(value ? .regular : .accessory)
            if value { NSApp.activate(ignoringOtherApps: true) }
        }
        settingsState.readShowMenuBarIcon = { [weak self] in
            self?.readUIValue("showMenuBarIcon") as? Bool ?? true
        }
        settingsState.writeShowMenuBarIcon = { [weak self] value in
            self?.writeUIValue("showMenuBarIcon", value)
            self?.menuBarManager.setVisible(value)
        }
        settingsState.readLaunchAtLogin = { LaunchAtLogin.isEnabled }
        settingsState.writeLaunchAtLogin = { value in
            LaunchAtLogin.setEnabled(value)
        }
        settingsState.readAppearance = { [weak self] in
            AppearanceSetting.parse(self?.readUIValue("appearance"))
        }
        settingsState.writeAppearance = { [weak self] value in
            self?.writeUIValue("appearance", value.rawValue)
            value.apply()
        }
        settingsState.readTextScale = { [weak self] in
            let raw = self?.readUIValue("textScale") as? Double ?? 1.0
            return LauncherPrefs.snapTextScale(raw)
        }
        settingsState.writeTextScale = { [weak self] value in
            guard let self else { return }
            self.writeUIValue("textScale", value)
            self.launcherPrefs.textScale = CGFloat(value)
        }
        settingsState.readLauncherBackground = { [weak self] in
            LauncherBackground.parse(self?.readUIValue("launcherBackground"))
        }
        settingsState.writeLauncherBackground = { [weak self] value in
            guard let self else { return }
            self.writeUIValue("launcherBackground", value.rawValue)
            self.launcherPrefs.background = value
            self.launcherPanel?.applyBackground(value)
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
        settingsState.onReviewPending = { [weak self] in
            self?.reviewPendingPlugins()
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
    }

    private func nonEmptyString(_ value: Any?) -> String? {
        guard let s = value as? String, !s.isEmpty else { return nil }
        return s
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
        let settingsJSON = workspace.readSettings()
        let settings = settingsJSON["pluginSettings"] as? [String: [String: Any]] ?? [:]
        let disabled = Set(settingsJSON["disabledPlugins"] as? [String] ?? [])
        let shortcuts = CommandShortcuts.load(from: settingsJSON["commandShortcuts"])
        let keyboardShortcuts = CommandShortcuts.load(from: settingsJSON["keyboardShortcuts"])
        var summaries: [ModuleSummary] = []

        for file in moduleManager.listModules(directory: "plugins") {
            let isEnabled = !disabled.contains(file.filename)
            let events = isEnabled ? (engine.pluginEvents[file.filename] ?? []) : []

            let meta = metadata[file.filename] ?? [:]
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
                        key: key, label: label, type: type,
                        defaultValue: defaultValue, currentValue: currentValue,
                        required: required, isSet: isSet, choices: choices,
                        placeholder: placeholder
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
                permissions: (meta["permissions"] as? [Any] ?? []).compactMap {
                    ($0 as? String).flatMap(Permissions.parse)
                },
                hiddenStatusItems: hiddenStatusItems(of: file.filename)
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
                Task { @MainActor in self?.launcherPanel.toggle() }
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
            MainActor.assumeIsolated { self?.refreshPermissions() }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermissions() }
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
    }

    private func applyUIPrefsFromSettings() {
        let showDock = readUIValue("showDockIcon") as? Bool ?? true
        NSApp.setActivationPolicy(showDock ? .regular : .accessory)
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

    private var lastPendingReview: Set<String> = []

    private func refreshIntegrity() {
        let pending = moduleManager?.pendingReview ?? []
        settingsState.pendingReview = pending.sorted()
        // An edited plugin is quarantined and simply stops running, taking its
        // menu bar item with it. The badge on the icon is too quiet for that,
        // so say it out loud the first time each file lands in the queue.
        let fresh = Set(pending).subtracting(lastPendingReview)
        lastPendingReview = Set(pending)
        if !fresh.isEmpty {
            let names = fresh.sorted().joined(separator: ", ")
            ToastHost.shared.flash("Not running until reviewed: \(names)")
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

    private func installCatalogPlugin(_ plugin: CatalogPlugin, override: Bool) {
        let timer = StepTimer("install \(plugin.filename)", category: "app")
        guard let workspace else { return }
        guard settingsState.allowsInstall(of: plugin, override: override) else {
            appLogger.info("install \(plugin.filename, privacy: .public) blocked by allowsInstall")
            return
        }
        let dest = workspace.pluginsDir.appending(path: plugin.filename)
        do {
            try plugin.source.write(to: dest, atomically: true, encoding: .utf8)
            timer.step("write")
            PluginTrust.approve(filename: plugin.filename, source: plugin.source)
            timer.step("approve")
            PluginTrust.approveImports(
                in: plugin.source, importerDir: workspace.pluginsDir, baseDir: workspace.root)
            timer.step("approveImports")
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
                try plugin.source.write(to: dest, atomically: true, encoding: .utf8)
                PluginTrust.approve(filename: plugin.filename, source: plugin.source)
                PluginTrust.approveImports(
                    in: plugin.source, importerDir: workspace.pluginsDir, baseDir: workspace.root)
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
        let dest = workspace.pluginsDir.appending(path: filename)
        do {
            try source.write(to: dest, atomically: true, encoding: .utf8)
            PluginTrust.approve(filename: filename, source: source)
            PluginTrust.approveImports(
                in: source, importerDir: workspace.pluginsDir, baseDir: workspace.root)
            moduleManager.reloadAll()
            refreshIntegrity()
            settingsState.refreshModules()
            NSWorkspace.shared.open(dest)
        } catch {
            NSLog("[Macotron] Could not create \(filename): \(error)")
        }
    }

    private func reviewPendingPlugins() {
        guard let workspace else { return }
        settingsState.requestedTab = SettingsTab.plugins.rawValue
        settingsWindow?.show()
        presentNextReview(workspace: workspace)
    }

    private func presentNextReview(workspace: PluginWorkspace) {
        guard let name = settingsState.pendingReview.first ?? moduleManager?.pendingReview.sorted().first else {
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
        engine.addModule(ShellModule())
        engine.addModule(FileSystemModule())
        engine.addModule(NotifyModule())
        engine.addModule(DialogModule())
        engine.addModule(ClipboardModule())
        engine.addModule(SnippetsModule())

        let keyboard = KeyboardModule()
        keyboard.onHostCommand = { [weak self] commandId in
            self?.handleCommandShortcut(commandId)
        }
        self.keyboardModule = keyboard
        engine.addModule(keyboard)
        engine.addModule(EventModule())

        engine.addModule(WindowModule())
        engine.addModule(AppModule())
        engine.addModule(ScreenModule())
        engine.addModule(SystemModule())
        engine.addModule(DisplayModule())
        engine.addModule(HTTPModule())
        engine.addModule(LocalStorageModule())
        engine.addModule(KeychainModule())

        let menuBarModule = MenuBarModule()
        menuBarModule.delegate = menuBarManager
        menuBarPluginModule = menuBarModule
        engine.addModule(menuBarModule)

        engine.addModule(URLSchemeModule())
        engine.addModule(SpotlightModule())
        engine.addModule(AIModule())
        engine.addModule(PanelModule())
        engine.addModule(CalendarModule())
        engine.addModule(ContactsModule())
        engine.addModule(OCRModule())
        engine.addModule(QRModule())
        engine.addModule(PowerModule())
        engine.addModule(NetworkModule())
        engine.addModule(BonjourModule())
        engine.addModule(UDPModule())
        engine.addModule(AppleTVModule())
        engine.addModule(IdleModule())
        engine.addModule(ScheduleModule())
        engine.addModule(MediaModule())
        engine.addModule(AudioModule())
        engine.addModule(SpacesModule())
        engine.addModule(USBModule())
        engine.addModule(HIDModule())
        engine.addModule(AXModule())
        engine.addModule(CameraModule())
        engine.addModule(ShareModule())
        engine.addModule(ShortcutsModule())
        let launcher = LauncherModule()
        launcherModule = launcher
        engine.addModule(launcher)
        engine.addModule(NotesModule())
        engine.addModule(RemindersModule())
        engine.addModule(HomeKitModule())
        engine.addModule(DockModule())
    }

    private func executeCommand(_ id: String, args: [String: Any] = [:]) {
        StepTimer.measure("execute \(id)") { executeCommandBody(id, args: args) }
    }

    private func executeCommandBody(_ id: String, args: [String: Any]) {
        launcherPanel.dismiss()
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
        case HostCommands.fixPermissionsID:
            settingsState.requestedTab = SettingsTab.permissions.rawValue
            openSettingsAction()
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
        let favorites = Self.favoriteIDs(from: workspace.readSettings()["launcherFavorites"])
        let shortcuts = CommandShortcuts.load(from: workspace.readSettings()["commandShortcuts"])

        if q.isEmpty {
            return permissionResult() + favorites.compactMap { id in
                result(id: id, pluginHits: pluginHits, shortcuts: shortcuts, isFavorite: true)
            }
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

        results.append(contentsOf: appSearchProvider.matching(q, limit: 20).map { app in
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
                    nsImage: hit.image,
                    kind: hit.kind,
                    isFavorite: favorites.contains(hit.id)
                ))
            }
        }

        results.sort { r1, r2 in
            let s1 = FuzzyMatch.best(query: q, targets: [r1.title, r1.subtitle]) ?? 0
            let s2 = FuzzyMatch.best(query: q, targets: [r2.title, r2.subtitle]) ?? 0
            if s1 != s2 { return s1 > s2 }
            let action: (SearchResult.ResultType) -> Bool = { $0 == .command || $0 == .plugin }
            if action(r1.type) && !action(r2.type) { return true }
            return false
        }

        // Live providers answer the query itself rather than matching a name, so
        // they skip fuzzy ranking and lead. A calculator result belongs above a
        // list of apps that happen to share a letter with the sum.
        let live = (launcherModule?.liveHits(query: q) ?? []).map { hit in
            SearchResult(
                id: hit.id,
                title: hit.title,
                subtitle: hit.subtitle,
                type: .plugin,
                nsImage: hit.image,
                kind: hit.kind,
                isFavorite: favorites.contains(hit.id)
            )
        }

        return Array((live + results).prefix(20))
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
                nsImage: hit.image,
                kind: hit.kind,
                isFavorite: isFavorite
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

extension MenuBarManager: MenuBarModuleDelegate {
    public func menuBarAddItem(id: String, title: String, icon: String?, section: String?, onClick: (() -> Void)?, menu: [MenuBarEntry]) {
        addItem(id: id, config: MenuItemConfig(title: title, icon: icon, section: section, callback: onClick, menu: menu))
    }

    public func menuBarUpdateItem(id: String, title: String?, icon: String?) {
        updateItem(id: id, title: title, icon: icon)
    }

    public func menuBarRemoveItem(id: String) {
        removeItem(id: id)
    }

    public func menuBarSetIcon(sfSymbolName: String) {
        setIcon(sfSymbolName)
    }

    public func menuBarSetIconColor(color: String?) {
        setIconColor(color)
    }

    public func menuBarSetTitle(text: String) {
        setTitle(text)
    }

    public func menuBarSetStatus(
        id: String,
        title: String,
        subtitle: String?,
        color: String?,
        subtitleColor: String?,
        bold: Bool,
        italic: Bool,
        secondary: Bool,
        minWidth: Double?,
        sfSymbol: String?,
        imagePath: String?,
        onClick: (() -> Void)?,
        menu: [MenuBarEntry],
        required: Bool
    ) {
        setStatus(
            id: id, title: title, subtitle: subtitle, color: color, subtitleColor: subtitleColor,
            bold: bold, italic: italic, secondary: secondary, minWidth: minWidth, sfSymbol: sfSymbol, imagePath: imagePath, onClick: onClick, menu: menu, required: required
        )
    }

    public func menuBarRemoveStatus(id: String) {
        removeStatus(id: id)
    }

    public func menuBarRemoveAllStatus() {
        removeAllStatus()
    }

    public func menuBarBeginStatusReload() {
        beginStatusReload()
    }

    public func menuBarFinishStatusReload() {
        finishStatusReload()
    }
}
