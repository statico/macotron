// AppDelegate.swift — NSApplicationDelegate, app lifecycle
import AppKit
import CQuickJS
import SwiftUI
import MacotronEngine
import MacotronUI
import Modules
import AI

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var engine: Engine!
    private var moduleManager: ModuleManager!
    private var menuBarManager: MenuBarManager!
    private var launcherPanel: LauncherPanel!
    private var launcherHotkey: GlobalHotkey?
    private var moduleAutoFixer: ModuleAutoFix?
    private let agentProgressState = AgentProgressState()
    private var agentTask: Task<Void, Never>?
    private var settingsWindow: SettingsWindow!
    private let settingsState = SettingsState()
    private var wizardWindow: WizardWindow?
    private let wizardState = WizardState()
    private var appSearchProvider: AppSearchProvider!

    private var debugServer: DebugServer?

    private let configDir: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appending(path: "Library/Application Support/Macotron")
    }()

    private static let hotkeyDefaultsKey = "launcherHotkey"
    private static let providerDefaultsKey = "aiProvider"
    private static let showDockIconKey = "showDockIcon"
    private static let showMenuBarIconKey = "showMenuBarIcon"
    private static let wizardCompletedKey = "wizardCompleted"

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Apply saved dock icon preference (default: show dock icon)
        let showDock = AppDelegate.readDefaultsBool(AppDelegate.showDockIconKey, default: true)
        NSApp.setActivationPolicy(showDock ? .regular : .accessory)

        // Install a standard main menu (required for Cmd+V paste in text fields)
        setupMainMenu()

        // Set up engine
        engine = Engine()
        moduleManager = ModuleManager(engine: engine, configDir: configDir)
        moduleManager.ensureDirectoryStructure()

        // Set up module auto-fix (bridges MacotronEngine → AI target)
        setupAutoFix()

        // Set up settings
        setupSettings()

        // Set up menubar
        menuBarManager = MenuBarManager()
        menuBarManager.onReload = { [weak self] in
            self?.moduleManager.reloadAll()
        }
        menuBarManager.onOpenConfig = { [weak self] in
            guard let self else { return }
            NSWorkspace.shared.open(self.configDir)
        }
        menuBarManager.onToggleLauncher = { [weak self] in
            self?.launcherPanel.toggle()
        }
        menuBarManager.onOpenSettings = { [weak self] in
            self?.launcherPanel.orderOut(nil)
            self?.settingsWindow.show()
        }

        // Set the launcher shortcut display on the menu bar
        menuBarManager.updateLauncherShortcut(resolveHotkey())

        // Apply saved menu bar visibility preference
        let showMenuBar = AppDelegate.readDefaultsBool(AppDelegate.showMenuBarIconKey, default: true)
        menuBarManager.setVisible(showMenuBar)

        // Set up app search
        appSearchProvider = AppSearchProvider()

        // Set up launcher panel
        let launcherView = LauncherView(
            agentState: agentProgressState,
            onExecuteCommand: { [weak self] id in
                self?.executeCommand(id)
            },
            onRevealInFinder: { [weak self] id in
                self?.appSearchProvider.revealInFinder(bundleID: id)
            },
            onSearch: { [weak self] query in
                self?.search(query) ?? []
            },
            onAgent: { [weak self] command in
                self?.handleAgentCommand(command)
            },
            onStopAgent: { [weak self] in
                self?.stopAgent()
            },
            onHeightChange: { [weak self] height in
                self?.launcherPanel.resizeToHeight(height)
            }
        )
        let hostingView = NSHostingView(rootView: launcherView)
        launcherPanel = LauncherPanel(contentView: hostingView)

        // Register all native modules
        registerModules()

        // Log handler
        engine.logHandler = { msg in
            // os_log output is handled in Engine.swift
        }

        // Initial load
        moduleManager.reloadAll()

        // Set up global hotkey for launcher toggle
        let launcherCombo = resolveHotkey()
        launcherHotkey = GlobalHotkey(combo: launcherCombo) { [weak self] in
            self?.launcherPanel.toggle()
        }

        moduleManager.startWatching()

        // Show permissions wizard on first launch (permission APIs are unreliable
        // when launched from Terminal/IDE — they inherit parent permissions)
        let wizardDone = UserDefaults.standard.bool(forKey: AppDelegate.wizardCompletedKey)
        if !wizardDone {
            showPermissionsWizard()
        }

        // Start debug server if requested
        if CommandLine.arguments.contains("--debug-server") {
            debugServer = DebugServer(engine: engine, moduleManager: moduleManager)
            debugServer?.onOpenSettings = { [weak self] in
                self?.settingsWindow.show()
            }
            debugServer?.onOpenSettingsTab = { [weak self] tab in
                self?.settingsState.requestedTab = tab
                self?.settingsWindow.show()
            }
            debugServer?.captureLauncher = { [weak self] in
                guard let self else { return nil }
                let view = LauncherView(agentState: self.agentProgressState)
                    .frame(width: 680, height: 480)
                return Self.renderViewToPNG(view, size: NSSize(width: 680, height: 480))
            }
            debugServer?.captureWindow = { [weak self] tab in
                guard let self else { return nil }
                let view = SettingsView(state: self.settingsState, initialTab: tab ?? 0)
                    .frame(width: 660, height: 460)
                return Self.renderViewToPNG(view, size: NSSize(width: 660, height: 460))
            }
            debugServer?.start()
        }
    }

    // MARK: - Settings

    private func setupSettings() {
        settingsState.configDirURL = configDir

        settingsState.readProvider = {
            UserDefaults.standard.string(forKey: AppDelegate.providerDefaultsKey) ?? "anthropic"
        }
        settingsState.writeProvider = { value in
            UserDefaults.standard.set(value, forKey: AppDelegate.providerDefaultsKey)
        }
        settingsState.readAPIKey = { [weak self] in
            let provider = self?.settingsState.selectedProvider ?? "anthropic"
            let keychainKey = AppDelegate.keychainKey(for: provider)
            return KeychainModule.readFromKeychain(key: keychainKey)
        }
        settingsState.writeAPIKey = { [weak self] value in
            let provider = self?.settingsState.selectedProvider ?? "anthropic"
            let keychainKey = AppDelegate.keychainKey(for: provider)
            KeychainModule.writeToKeychain(key: keychainKey, value: value)
        }
        settingsState.validateAPIKey = { key, provider in
            let result: AIKeyValidationResult
            switch provider {
            case "openai":
                result = await OpenAIProvider.validateKey(key)
            default:
                result = await ClaudeProvider.validateKey(key)
            }
            switch result {
            case .valid:
                return .valid
            case .invalidKey(let message):
                return .invalidKey(message)
            case .networkError(let message):
                return .invalidKey("Network error: \(message)")
            case .modelUnavailable:
                return .modelUnavailable
            }
        }
        settingsState.readHotkey = { [weak self] in
            self?.resolveHotkey() ?? "cmd+space"
        }
        settingsState.writeHotkey = { [weak self] combo in
            UserDefaults.standard.set(combo, forKey: AppDelegate.hotkeyDefaultsKey)
            self?.launcherHotkey?.updateHotkey(combo)
            self?.menuBarManager.updateLauncherShortcut(combo)
        }

        settingsState.readShowDockIcon = {
            AppDelegate.readDefaultsBool(AppDelegate.showDockIconKey, default: true)
        }
        settingsState.writeShowDockIcon = { value in
            UserDefaults.standard.set(value, forKey: AppDelegate.showDockIconKey)
            NSApp.setActivationPolicy(value ? .regular : .accessory)
            if value {
                // Re-activate so the dock icon appears immediately
                NSApp.activate()
            }
        }
        settingsState.readShowMenuBarIcon = {
            AppDelegate.readDefaultsBool(AppDelegate.showMenuBarIconKey, default: true)
        }
        settingsState.writeShowMenuBarIcon = { [weak self] value in
            UserDefaults.standard.set(value, forKey: AppDelegate.showMenuBarIconKey)
            self?.menuBarManager.setVisible(value)
        }

        settingsState.loadModuleSummaries = { [weak self] in
            self?.buildModuleSummaries() ?? []
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

        settingsWindow = SettingsWindow(state: settingsState)
    }

    /// Build module summaries by reading all modules and extracting metadata
    private func buildModuleSummaries() -> [ModuleSummary] {
        let errorMap = Dictionary(
            moduleManager.lastReloadErrors.map { ($0.filename, $0.error) },
            uniquingKeysWith: { first, _ in first }
        )
        let metadata = engine.moduleMetadata
        let settings = moduleManager.loadModuleSettings()
        var summaries: [ModuleSummary] = []

        let hotkeyPattern = try? NSRegularExpression(pattern: #"keyboard\.on\(\s*"([^"]+)""#)
        let eventPattern = try? NSRegularExpression(pattern: #"macotron\.on\(\s*"([^"]+)""#)

        for dir in ["modules", "commands"] {
            let files = moduleManager.listModules(directory: dir)
            for file in files {
                let fullPath = moduleManager.configDir.appending(path: dir).appending(path: file.filename)
                let source = (try? String(contentsOf: fullPath, encoding: .utf8)) ?? ""
                let range = NSRange(source.startIndex..., in: source)

                // Extract hotkeys from source
                var hotkeys: [String] = []
                if let regex = hotkeyPattern {
                    let matches = regex.matches(in: source, range: range)
                    for match in matches {
                        if let r = Range(match.range(at: 1), in: source) {
                            hotkeys.append(String(source[r]))
                        }
                    }
                }

                // Extract events from source
                var events: [String] = []
                if let regex = eventPattern {
                    let matches = regex.matches(in: source, range: range)
                    for match in matches {
                        if let r = Range(match.range(at: 1), in: source) {
                            events.append(String(source[r]))
                        }
                    }
                }

                // Extract title and options from engine metadata
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
                        options.append(ModuleOption(
                            key: key, label: label, type: type,
                            defaultValue: defaultValue, currentValue: currentValue
                        ))
                    }
                }

                let errorMsg = errorMap[file.filename]
                summaries.append(ModuleSummary(
                    filename: file.filename,
                    title: title,
                    description: file.description,
                    options: options,
                    events: events,
                    hotkeys: hotkeys,
                    hasErrors: errorMsg != nil,
                    errorMessage: errorMsg
                ))
            }
        }

        return summaries
    }

    // MARK: - Wizard

    private func showPermissionsWizard() {
        wizardState.permissionsOnly = true
        wizardState.currentStep = .permissions
        wizardState.checkAccessibility = { Permissions.isAccessibilityGranted }
        wizardState.checkInputMonitoring = { Permissions.isInputMonitoringGranted }
        wizardState.checkScreenRecording = { Permissions.isScreenRecordingGranted }
        wizardState.requestAccessibility = { Permissions.requestAccessibility() }
        wizardState.requestInputMonitoring = { Permissions.requestInputMonitoring() }
        wizardState.requestScreenRecording = { Permissions.requestScreenRecording() }
        wizardState.onComplete = { [weak self] in
            guard let self else { return }
            self.wizardWindow?.close()
            self.wizardWindow = nil

            // Mark wizard as completed so it doesn't show again
            UserDefaults.standard.set(true, forKey: AppDelegate.wizardCompletedKey)

            // Re-register the global hotkey now that accessibility may have been granted
            let combo = self.resolveHotkey()
            self.launcherHotkey?.cleanup()
            self.launcherHotkey = GlobalHotkey(combo: combo) { [weak self] in
                self?.launcherPanel.toggle()
            }
        }
        wizardState.refreshPermissions()

        wizardWindow = WizardWindow(state: wizardState)
        wizardWindow?.show()
    }

    /// Map provider name to its keychain key
    private static func keychainKey(for provider: String) -> String {
        switch provider {
        case "openai": return "openai-api-key"
        default: return "anthropic-api-key"
        }
    }

    /// Install a standard main menu so that Cmd+V (paste), Cmd+C, etc. work in text fields.
    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // Application menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Macotron", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings...", action: #selector(openSettingsAction), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Macotron", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // File menu (enables Close Window with Cmd+W)
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // Edit menu (enables Cut/Copy/Paste/Select All in text fields)
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
        launcherPanel.orderOut(nil)
        settingsWindow.show()
    }

    /// Read a Bool from UserDefaults, returning `defaultValue` if the key has never been set.
    private static func readDefaultsBool(_ key: String, default defaultValue: Bool) -> Bool {
        if UserDefaults.standard.object(forKey: key) == nil {
            return defaultValue
        }
        return UserDefaults.standard.bool(forKey: key)
    }

    /// Resolve the launcher hotkey from multiple sources:
    /// 1. UserDefaults (set via Settings UI)
    /// 2. Config store (set via config.js)
    /// 3. Default "cmd+space"
    private func resolveHotkey() -> String {
        if let saved = UserDefaults.standard.string(forKey: AppDelegate.hotkeyDefaultsKey), !saved.isEmpty {
            return saved
        }
        if let launcher = engine.configStore["launcher"] as? [String: Any],
           let hotkey = launcher["hotkey"] as? String {
            return hotkey
        }
        return "cmd+space"
    }

    private func registerModules() {
        // Core modules
        engine.addModule(ShellModule())
        engine.addModule(FileSystemModule())
        engine.addModule(TimerModule())
        engine.addModule(NotifyModule())
        engine.addModule(ClipboardModule())
        engine.addModule(KeyboardModule())
        engine.addModule(WindowModule())
        engine.addModule(AppModule())
        engine.addModule(ScreenModule())
        engine.addModule(SystemModule())
        engine.addModule(DisplayModule())
        engine.addModule(HTTPModule())

        // Storage
        engine.addModule(LocalStorageModule())
        engine.addModule(KeychainModule())

        // MenuBar (with delegate bridge to MenuBarManager)
        let menuBarModule = MenuBarModule()
        menuBarModule.delegate = menuBarManager
        engine.addModule(menuBarModule)

        // Platform integration
        engine.addModule(CameraModule())
        engine.addModule(USBModule())
        engine.addModule(URLSchemeModule())
        engine.addModule(SpotlightModule())

        // AI
        engine.addModule(AIModule())
    }

    private func executeCommand(_ id: String) {
        // Try as a registered JS command first
        if let cmd = engine.commandRegistry[id] {
            var undef = QJS_Undefined()
            _ = JS_Call(engine.context, cmd.callback, QJS_Undefined(), 0, &undef)
            engine.drainJobQueue()
            launcherPanel.toggle()
            return
        }

        // Try as an app bundle ID
        appSearchProvider.launchApp(bundleID: id)
        launcherPanel.toggle()
    }

    // MARK: - Module Auto-Fix

    /// Wire the module auto-fix handler. This bridges ModuleManager (MacotronEngine)
    /// to ModuleAutoFix (AI) via a closure, since MacotronEngine cannot import AI.
    private func setupAutoFix() {
        moduleManager.autoFixHandler = { @Sendable [weak self] filename, source, error in
            await self?.autoFixModule(filename: filename, source: source, error: error)
        }
    }

    /// Called by the auto-fix handler closure. Lazily creates the ModuleAutoFix instance
    /// (requires an API key) and delegates the fix attempt.
    private func autoFixModule(filename: String, source: String, error: String) async -> String? {
        // Lazily create the auto-fixer when first needed (requires API key)
        if moduleAutoFixer == nil {
            guard let apiKey = resolveAIAPIKey() else { return nil }
            let providerName = resolveSelectedProvider()
            let provider = AIProviderFactory.create(name: providerName, config: .init(apiKey: apiKey))
            moduleAutoFixer = ModuleAutoFix(provider: provider)
        }
        guard let fixer = moduleAutoFixer else { return nil }
        return await fixer.attemptFix(filename: filename, source: source, error: error)
    }

    // MARK: - Agent

    private func handleAgentCommand(_ command: String) {
        // Check API key
        guard let apiKey = resolveAIAPIKey() else {
            settingsWindow.showWithAPIKeyRequired()
            return
        }

        // Show inline progress (don't dismiss launcher)
        agentProgressState.start(topic: command)

        // Create agent session and run
        let provider = ClaudeProvider(apiKey: apiKey)
        let session = AgentSession(provider: provider, moduleManager: moduleManager)

        session.onProgress = { [weak self] progress in
            guard let state = self?.agentProgressState else { return }
            switch progress {
            case .planning:
                state.statusText = "Planning..."
            case .writing(let filename):
                state.statusText = "Writing \(filename)..."
            case .testing:
                state.statusText = "Testing..."
            case .repairing(let attempt):
                state.statusText = "Repairing (attempt \(attempt))..."
            case .done(let success, let summary):
                state.statusText = success ? "Done!" : String(summary.prefix(100))
                state.isComplete = true
                state.success = success
                // Auto-dismiss launcher and revert to search mode after delay
                let delay: UInt64 = success ? 1_000_000_000 : 5_000_000_000
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: delay)
                    guard !Task.isCancelled else { return }
                    self?.launcherPanel.orderOut(nil)
                    self?.agentProgressState.reset()
                }
            }
        }

        agentTask = Task {
            do {
                let _ = try await session.run(command: command)
            } catch is CancellationError {
                // Cancelled by stop button — state already reset
            } catch {
                agentProgressState.statusText = error.localizedDescription
                agentProgressState.isComplete = true
                agentProgressState.success = false
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    guard !Task.isCancelled else { return }
                    self?.agentProgressState.reset()
                }
            }
        }
    }

    private func stopAgent() {
        agentTask?.cancel()
        agentTask = nil
        agentProgressState.reset()
    }

    /// The currently selected AI provider name
    private func resolveSelectedProvider() -> String {
        UserDefaults.standard.string(forKey: AppDelegate.providerDefaultsKey) ?? "anthropic"
    }

    /// Resolve the AI API key from multiple sources (in priority order):
    /// 1. Config store (set via macotron.config({ ai: { apiKey: "..." } }))
    /// 2. Keychain (per-provider key)
    /// 3. Environment variable (ANTHROPIC_API_KEY or OPENAI_API_KEY)
    private func resolveAIAPIKey() -> String? {
        let provider = resolveSelectedProvider()

        // 1. Check config store
        if let aiConfig = engine.configStore["ai"] as? [String: Any],
           let key = aiConfig["apiKey"] as? String, !key.isEmpty {
            return key
        }

        // 2. Check Keychain — provider-specific key first, then fallbacks
        let primaryKey = AppDelegate.keychainKey(for: provider)
        if let key = KeychainModule.readFromKeychain(key: primaryKey), !key.isEmpty {
            return key
        }
        // Legacy fallback keys for Anthropic
        if provider == "anthropic" {
            for keyName in ["claude-api-key", "ai-api-key"] {
                if let key = KeychainModule.readFromKeychain(key: keyName), !key.isEmpty {
                    return key
                }
            }
        }

        // 3. Check environment variable
        let envVar = provider == "openai" ? "OPENAI_API_KEY" : "ANTHROPIC_API_KEY"
        if let key = ProcessInfo.processInfo.environment[envVar], !key.isEmpty {
            return key
        }

        return nil
    }

    private func search(_ query: String) -> [SearchResult] {
        // Show default app results when no query
        if query.isEmpty {
            return appSearchProvider.search("")
        }

        var results: [SearchResult] = []

        // Search commands (prioritized)
        for (_, cmd) in engine.commandRegistry {
            if let score = FuzzyMatch.score(query: query, target: cmd.name), score > 0 {
                results.append(SearchResult(
                    id: cmd.name,
                    title: cmd.name,
                    subtitle: cmd.description,
                    icon: "terminal.fill",
                    type: .command
                ))
            }
        }

        // Search installed apps with icons
        let appResults = appSearchProvider.search(query)
        results.append(contentsOf: appResults)

        // Sort by relevance (fuzzy score), commands first on tie
        results.sort { r1, r2 in
            let s1 = FuzzyMatch.score(query: query, target: r1.title) ?? 0
            let s2 = FuzzyMatch.score(query: query, target: r2.title) ?? 0
            if s1 != s2 { return s1 > s2 }
            // Commands rank above apps on tie
            if r1.type == .command && r2.type != .command { return true }
            return false
        }

        return Array(results.prefix(20))
    }

    /// Render a SwiftUI view to PNG data using NSHostingView (works without window server)
    private static func renderViewToPNG<V: View>(_ view: V, size: NSSize) -> Data? {
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.layoutSubtreeIfNeeded()
        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else { return nil }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        return bitmap.representation(using: .png, properties: [:])
    }
}

// MARK: - MenuBarManager + MenuBarModuleDelegate

// Bridge MenuBarManager (MacotronUI) to MenuBarModuleDelegate (Modules)
// This conformance lives here because the Macotron target imports both.
extension MenuBarManager: MenuBarModuleDelegate {
    public func menuBarAddItem(id: String, title: String, icon: String?, section: String?, onClick: (() -> Void)?) {
        addItem(id: id, config: MenuItemConfig(title: title, icon: icon, section: section, callback: onClick))
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
}
