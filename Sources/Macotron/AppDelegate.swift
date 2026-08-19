// AppDelegate.swift — NSApplicationDelegate, app lifecycle
import AppKit
import SwiftUI
import MacotronEngine
import MacotronUI
import Modules

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var engine: Engine!
    private var moduleManager: ModuleManager!
    private var workspace: PluginWorkspace!
    private var menuBarManager: MenuBarManager!
    private var launcherPanel: LauncherPanel!
    private var launcherHotkey: GlobalHotkey?
    private var settingsWindow: SettingsWindow!
    private let settingsState = SettingsState()
    private let launcherPrefs = LauncherPrefs()
    private let launcherSession = LauncherSession()
    private var keyboardModule: KeyboardModule?
    private var wizardWindow: WizardWindow?
    private let wizardState = WizardState()
    private var appSearchProvider: AppSearchProvider!
    private var debugServer: DebugServer?
    private var didRegisterPermissions = false
    private var permissionTimer: Timer?
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
        observePermissionTriggers()

        if let root = PluginWorkspace.resolveFromDefaults() {
            bootstrap(workspaceRoot: root)
        }

        refreshPermissions()

        let wizardDone = UserDefaults.standard.bool(forKey: AppDelegate.wizardCompletedKey)
        if !wizardDone || PluginWorkspace.resolveFromDefaults() == nil {
            showSetupWizard()
        } else if !Permissions.missing(from: requiredPermissions()).isEmpty {
            showPermissionsWizard()
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
            self.settingsState.requestedTab = 0
            self.settingsState.refreshPermissions()
            self.settingsWindow.show()
        }
        menuBarManager.onMenuWillOpen = { [weak self] in
            self?.refreshPermissions()
        }
        menuBarManager.updateLauncherShortcut(resolveHotkey())
        menuBarManager.setVisible(readUIValue("showMenuBarIcon") as? Bool ?? true)

        appSearchProvider = AppSearchProvider()

        let launcherView = LauncherView(
            prefs: launcherPrefs,
            session: launcherSession,
            onExecuteCommand: { [weak self] id, args in
                self?.executeCommand(id, args: args)
            },
            onRevealInFinder: { [weak self] id in
                self?.appSearchProvider.revealInFinder(bundleID: id)
            },
            onSearch: { [weak self] query in
                self?.search(query) ?? []
            },
            onHeightChange: { [weak self] height in
                self?.launcherPanel.resizeToHeight(height)
            }
        )
        launcherPanel = LauncherPanel(contentView: NSHostingView(rootView: launcherView))

        registerModules()
        moduleManager.reloadAll()
        applyUIPrefsFromSettings()
        installLauncherHotkey()
        moduleManager.startWatching()
        installModuleManagerCallbacks()
        refreshPermissions()

        if CommandLine.arguments.contains("--debug-server") {
            debugServer = DebugServer(engine: engine, moduleManager: moduleManager)
            debugServer?.onOpenSettingsTab = { [weak self] tab in
                self?.settingsState.requestedTab = tab
                self?.settingsWindow.show()
            }
            debugServer?.onToggleLauncher = { [weak self] in
                self?.launcherPanel.toggle()
            }
            debugServer?.captureLauncher = { [weak self] in
                let prefs = self?.launcherPrefs ?? LauncherPrefs()
                let view = LauncherView(prefs: prefs).frame(width: 680, height: 480)
                return Self.renderViewToPNG(view, size: NSSize(width: 680, height: 480))
            }
            debugServer?.captureWizard = { [weak self] step in
                guard let self else { return nil }
                let preview = WizardState()
                preview.steps = WizardStep.allCases
                preview.stepIndex = WizardStep.allCases.firstIndex {
                    String(describing: $0) == step
                } ?? 0
                preview.pluginsPath = self.workspace?.root.path(percentEncoded: false) ?? ""
                let view = WizardView(state: preview, permissions: self.settingsState)
                    .frame(width: 560, height: 520)
                return Self.renderViewToPNG(view, size: NSSize(width: 560, height: 520))
            }
            debugServer?.captureWindow = { [weak self] tab in
                guard let self else { return nil }
                let view = SettingsView(state: self.settingsState, initialTab: tab ?? 0)
                    .frame(width: 760, height: 520)
                return Self.renderViewToPNG(view, size: NSSize(width: 760, height: 520))
            }
            debugServer?.start()
        }
    }

    private func rebootstrap(workspaceRoot: URL) {
        moduleManager?.stopWatching()
        launcherHotkey?.cleanup()
        launcherHotkey = nil

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
            self?.refreshPermissions()
            self?.applyUIPrefsFromSettings()
            self?.installCommandShortcuts()
            self?.rebindPluginHotkeys()
        }
    }

    // MARK: - Settings

    private func setupSettings() {
        settingsState.configDirURL = workspace.root

        settingsState.readHotkey = { [weak self] in
            self?.resolveHotkey() ?? "cmd+space"
        }
        settingsState.writeHotkey = { [weak self] combo in
            guard let self else { return }
            try? self.workspace.updateSettings { settings in
                var launcher = settings["launcher"] as? [String: Any] ?? [:]
                launcher["hotkey"] = combo
                settings["launcher"] = launcher
            }
            self.engine.configStore = self.workspace.readSettings()
            self.launcherHotkey?.updateHotkey(combo)
            self.menuBarManager.updateLauncherShortcut(combo)
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

        settingsState.loadModuleSummaries = { [weak self] in
            self?.buildPluginSummaries() ?? []
        }
        settingsState.deleteModule = { [weak self] filename in
            guard let self else { return false }
            if self.moduleManager.deleteModule(filename: filename) {
                self.moduleManager.reloadAll()
                return true
            }
            return false
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
        settingsWindow = SettingsWindow(state: settingsState)
    }

    private func buildPluginSummaries() -> [ModuleSummary] {
        let errorMap = Dictionary(
            moduleManager.lastReloadErrors.map { ($0.filename, $0.error) },
            uniquingKeysWith: { first, _ in first }
        )
        let metadata = engine.moduleMetadata
        let settings = moduleManager.loadModuleSettings()
        let disabled = moduleManager.disabledPlugins()
        let shortcuts = CommandShortcuts.load(from: workspace.readSettings()["commandShortcuts"])
        let keyboardShortcuts = CommandShortcuts.load(from: workspace.readSettings()["keyboardShortcuts"])
        var summaries: [ModuleSummary] = []

        let eventPattern = try? NSRegularExpression(pattern: #"macotron\.on\(\s*"([^"]+)""#)

        for file in moduleManager.listModules(directory: "plugins") {
            let isEnabled = !disabled.contains(file.filename)
            var events: [String] = []
            if isEnabled {
                let fullPath = moduleManager.configDir.appending(path: "plugins").appending(path: file.filename)
                let source = (try? String(contentsOf: fullPath, encoding: .utf8)) ?? ""
                let range = NSRange(source.startIndex..., in: source)

                if let regex = eventPattern {
                    for match in regex.matches(in: source, range: range) {
                        if let r = Range(match.range(at: 1), in: source) {
                            events.append(String(source[r]))
                        }
                    }
                }
            }

            let meta = metadata[file.filename] ?? [:]
            let title = meta["title"] as? String ?? ""
            let fileSettings = settings[file.filename] ?? [:]
            var options: [ModuleOption] = []

            if let optionsDefs = meta["options"] as? [String: [String: Any]] {
                for (key, def) in optionsDefs.sorted(by: { $0.key < $1.key }) {
                    let type = def["type"] as? String ?? "string"
                    let label = def["label"] as? String ?? key
                    let defaultValue = def["default"] ?? ""
                    let currentValue = fileSettings[key] ?? defaultValue
                    let required = def["required"] as? Bool ?? false

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
                        let ref = fileSettings[key] as? String ?? ""
                        let secret = ref.isEmpty ? nil : KeychainStore.read(account: ref)
                        isSet = !(secret?.isEmpty ?? true)
                    case "boolean", "number":
                        isSet = (fileSettings[key] ?? def["default"]) != nil
                    default:
                        isSet = !(((fileSettings[key] ?? def["default"]) as? String) ?? "").isEmpty
                    }

                    options.append(ModuleOption(
                        key: key, label: label, type: type,
                        defaultValue: defaultValue, currentValue: currentValue,
                        required: required, isSet: isSet, choices: choices
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
                        name: $0.key.replacingOccurrences(of: "-", with: " ").capitalized,
                        shortcut: keyboardShortcuts.bindings[$0.id] ?? $0.defaultCombo
                    )
                }

            let errorMsg = errorMap[file.filename]
            summaries.append(ModuleSummary(
                filename: file.filename,
                title: title,
                description: meta["description"] as? String ?? file.description,
                options: options,
                events: events,
                hotkeys: hotkeys,
                hasErrors: errorMsg != nil,
                errorMessage: errorMsg,
                isEnabled: isEnabled,
                commands: commands
            ))
        }

        return summaries
    }

    // MARK: - Wizard

    private func showSetupWizard() {
        wizardState.startFullSetup()
        configureWizard()
        presentWizard()
    }

    /// Shown at startup when setup is done but macOS permissions are missing.
    private func showPermissionsWizard() {
        wizardState.startPermissionsOnly()
        configureWizard()
        presentWizard()
    }

    private func presentWizard() {
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
        wizardState.openInFinder = { url in
            NSWorkspace.shared.open(url)
        }
        wizardState.onComplete = { [weak self] in
            guard let self else { return }
            self.wizardWindow?.close()
            self.wizardWindow = nil
            UserDefaults.standard.set(true, forKey: AppDelegate.wizardCompletedKey)
            self.installLauncherHotkey()
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
        guard moduleManager != nil else { return }
        let combo = resolveHotkey()
        launcherHotkey?.cleanup()
        let hotkey = GlobalHotkey(combo: combo) { [weak self] in
            self?.launcherPanel.toggle()
        }
        hotkey.onPermissionNeeded = { [weak self] in
            self?.refreshPermissions()
        }
        launcherHotkey = hotkey
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
        let required = requiredPermissions()
        let missing = Permissions.missing(from: required)

        if !didRegisterPermissions, !missing.isEmpty {
            didRegisterPermissions = true
            Permissions.registerWithSystem(required)
        }

        menuBarManager?.setMissingPermissions(missing)
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
           let hotkey = launcher["hotkey"] as? String, !hotkey.isEmpty {
            return hotkey
        }
        if let workspace,
           let launcher = workspace.readSettings()["launcher"] as? [String: Any],
           let hotkey = launcher["hotkey"] as? String, !hotkey.isEmpty {
            return hotkey
        }
        return "cmd+space"
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
        engine.addModule(ClipboardModule())
        engine.addModule(SnippetsModule())

        let keyboard = KeyboardModule()
        keyboard.onTrustFailure = { [weak self] in
            self?.refreshPermissions()
        }
        keyboard.onHostCommand = { [weak self] commandId in
            self?.handleCommandShortcut(commandId)
        }
        self.keyboardModule = keyboard
        engine.addModule(keyboard)

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
        engine.addModule(menuBarModule)

        engine.addModule(URLSchemeModule())
        engine.addModule(SpotlightModule())
        engine.addModule(AIModule())
        engine.addModule(PanelModule())
        engine.addModule(CalendarModule())
        engine.addModule(OCRModule())
        engine.addModule(PowerModule())
        engine.addModule(NetworkModule())
        engine.addModule(IdleModule())
    }

    private func executeCommand(_ id: String, args: [String: Any] = [:]) {
        if launcherPanel.isVisible {
            launcherPanel.toggle()
        }
        if engine.commandRegistry[id] != nil {
            _ = engine.invokeCommand(id, args: args)
            return
        }
        appSearchProvider.launchApp(bundleID: id)
    }

    private func handleCommandShortcut(_ commandId: String) {
        guard let cmd = engine.commandRegistry[commandId] else { return }
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

    private func saveShortcut(
        id: String,
        combo: String,
        tableKey: String,
        otherKey: String,
        defaultCombo: String? = nil
    ) {
        if !combo.isEmpty, combo.lowercased() == resolveHotkey().lowercased() {
            NSLog("[Macotron] Shortcut collides with the launcher hotkey")
            return
        }
        var stored = combo
        if let defaultCombo, combo.isEmpty || combo.lowercased() == defaultCombo.lowercased() {
            stored = ""
        }
        try? workspace.updateSettings { settings in
            var table = CommandShortcuts.load(from: settings[tableKey])
            table.assign(commandId: id, combo: stored)
            settings[tableKey] = table.jsonObject()
            if !stored.isEmpty {
                var other = CommandShortcuts.load(from: settings[otherKey])
                other.removeCombo(stored)
                settings[otherKey] = other.jsonObject()
            }
        }
        engine.configStore = workspace.readSettings()
        installCommandShortcuts()
        rebindPluginHotkeys()
    }

    private func installCommandShortcuts() {
        let table = CommandShortcuts.load(from: workspace.readSettings()["commandShortcuts"])
        let live = table.bindings.filter { engine.commandRegistry[$0.key] != nil }
        keyboardModule?.setHostBindings(live.map { (commandId: $0.key, combo: $0.value) })
    }

    private func rebindPluginHotkeys() {
        let table = CommandShortcuts.load(from: workspace.readSettings()["keyboardShortcuts"])
        keyboardModule?.setPluginBindings(
            engine.hotkeyRegistry.values.map { hotkey in
                (eventName: "keyboard:\(hotkey.id)", combo: table.bindings[hotkey.id] ?? hotkey.defaultCombo)
            }
        )
    }

    private func search(_ query: String) -> [SearchResult] {
        if query.isEmpty {
            return appSearchProvider.search("")
        }

        var results: [SearchResult] = []

        for (_, cmd) in engine.commandRegistry {
            if let score = FuzzyMatch.score(query: query, target: cmd.name), score > 0 {
                results.append(SearchResult(
                    id: cmd.id,
                    title: cmd.name,
                    subtitle: cmd.description,
                    type: .command,
                    commandArguments: cmd.arguments
                ))
            }
        }

        results.append(contentsOf: appSearchProvider.search(query))

        results.sort { r1, r2 in
            let s1 = FuzzyMatch.score(query: query, target: r1.title) ?? 0
            let s2 = FuzzyMatch.score(query: query, target: r2.title) ?? 0
            if s1 != s2 { return s1 > s2 }
            if r1.type == .command && r2.type != .command { return true }
            return false
        }

        return Array(results.prefix(20))
    }

    /// Render offscreen for screenshots. The view is hosted in a real window so
    /// materials and the system appearance resolve, and it gets an opaque
    /// backdrop so label colors stay readable.
    private static func renderViewToPNG<V: View>(_ view: V, size: NSSize) -> Data? {
        let root = view
            .frame(width: size.width, height: size.height)
            .background(Color(nsColor: .windowBackgroundColor))

        let hostingView = NSHostingView(rootView: root)
        hostingView.frame = NSRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSApp.effectiveAppearance
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else { return nil }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        return bitmap.representation(using: .png, properties: [:])
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

    public func menuBarSetTitle(text: String) {
        setTitle(text)
    }

    public func menuBarSetStatus(
        id: String,
        title: String,
        subtitle: String?,
        color: String?,
        bold: Bool,
        italic: Bool,
        sfSymbol: String?,
        imagePath: String?,
        onClick: (() -> Void)?,
        menu: [MenuBarEntry]
    ) {
        setStatus(
            id: id, title: title, subtitle: subtitle, color: color,
            bold: bold, italic: italic, sfSymbol: sfSymbol, imagePath: imagePath, onClick: onClick, menu: menu
        )
    }

    public func menuBarRemoveStatus(id: String) {
        removeStatus(id: id)
    }

    public func menuBarRemoveAllStatus() {
        removeAllStatus()
    }
}
