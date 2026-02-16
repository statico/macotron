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
    private var snippetManager: SnippetManager!
    private var menuBarManager: MenuBarManager!
    private var launcherPanel: LauncherPanel!
    private var launcherHotkey: GlobalHotkey?
    private var snippetAutoFixer: SnippetAutoFix?
    private var agentProgressPanel: AgentProgressPanel?
    private var settingsWindow: SettingsWindow!
    private let settingsState = SettingsState()
    private var permissionWindow: PermissionWindow?
    private var wizardWindow: WizardWindow?
    private let wizardState = WizardState()
    private var appSearchProvider: AppSearchProvider!

    #if DEBUG
    private var debugServer: DebugServer?
    #endif

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
        snippetManager = SnippetManager(engine: engine, configDir: configDir)
        snippetManager.ensureDirectoryStructure()

        // Set up snippet auto-fix (bridges MacotronEngine → AI target)
        setupAutoFix()

        // Set up settings
        setupSettings()

        // Set up menubar
        menuBarManager = MenuBarManager()
        menuBarManager.onReload = { [weak self] in
            self?.snippetManager.reloadAll()
        }
        menuBarManager.onOpenConfig = { [weak self] in
            guard let self else { return }
            NSWorkspace.shared.open(self.configDir)
        }
        menuBarManager.onToggleLauncher = { [weak self] in
            self?.launcherPanel.toggle()
        }
        menuBarManager.onOpenSettings = { [weak self] in
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
        snippetManager.reloadAll()

        // Set up global hotkey for launcher toggle
        let launcherCombo = resolveHotkey()
        launcherHotkey = GlobalHotkey(combo: launcherCombo) { [weak self] in
            self?.launcherPanel.toggle()
        }

        snippetManager.startWatching()

        // First-run wizard or existing user flow
        let wizardDone = UserDefaults.standard.bool(forKey: AppDelegate.wizardCompletedKey)
        if !wizardDone {
            showWizard()
        } else {
            // Existing user: check permissions and API key
            if !Permissions.isAccessibilityGranted {
                permissionWindow = PermissionWindow()
                permissionWindow?.show {
                    Permissions.openAccessibilitySettings()
                }
            }
            if resolveAIAPIKey() == nil {
                settingsWindow.showWithAPIKeyRequired()
            }
        }

        // Start debug server if requested
        #if DEBUG
        if CommandLine.arguments.contains("--debug-server") {
            debugServer = DebugServer(engine: engine, snippetManager: snippetManager)
            debugServer?.start()
        }
        #endif
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

        settingsState.loadScriptSummaries = { [weak self] in
            self?.buildScriptSummaries() ?? []
        }

        settingsWindow = SettingsWindow(state: settingsState)
    }

    /// Build script summaries by reading all snippets and extracting metadata
    private func buildScriptSummaries() -> [ScriptSummary] {
        let errorFiles = Set(snippetManager.lastReloadErrors.map(\.filename))
        var summaries: [ScriptSummary] = []

        let hotkeyPattern = try? NSRegularExpression(pattern: #"keyboard\.on\(\s*"([^"]+)""#)
        let eventPattern = try? NSRegularExpression(pattern: #"macotron\.on\(\s*"([^"]+)""#)

        for dir in ["snippets", "commands"] {
            let files = snippetManager.listSnippets(directory: dir)
            for file in files {
                let fullPath = snippetManager.configDir.appending(path: dir).appending(path: file.filename)
                let source = (try? String(contentsOf: fullPath, encoding: .utf8)) ?? ""
                let range = NSRange(source.startIndex..., in: source)

                // Extract hotkeys
                var hotkeys: [String] = []
                if let regex = hotkeyPattern {
                    let matches = regex.matches(in: source, range: range)
                    for match in matches {
                        if let r = Range(match.range(at: 1), in: source) {
                            hotkeys.append(String(source[r]))
                        }
                    }
                }

                // Extract events
                var events: [String] = []
                if let regex = eventPattern {
                    let matches = regex.matches(in: source, range: range)
                    for match in matches {
                        if let r = Range(match.range(at: 1), in: source) {
                            events.append(String(source[r]))
                        }
                    }
                }

                summaries.append(ScriptSummary(
                    filename: file.filename,
                    description: file.description,
                    events: events,
                    hotkeys: hotkeys,
                    hasErrors: errorFiles.contains(file.filename)
                ))
            }
        }

        return summaries
    }

    // MARK: - Wizard

    private func showWizard() {
        // Check for dev config shortcut
        let devConfig = readDevConfig()

        wizardState.writeAPIKey = { [weak self] value in
            let provider = self?.wizardState.selectedProvider ?? "anthropic"
            let keychainKey = AppDelegate.keychainKey(for: provider)
            KeychainModule.writeToKeychain(key: keychainKey, value: value)
        }
        wizardState.writeProvider = { value in
            UserDefaults.standard.set(value, forKey: AppDelegate.providerDefaultsKey)
        }
        wizardState.validateAPIKey = { key, provider in
            let result: AIKeyValidationResult
            switch provider {
            case "openai":
                result = await OpenAIProvider.validateKey(key)
            default:
                result = await ClaudeProvider.validateKey(key)
            }
            switch result {
            case .valid: return .valid
            case .invalidKey(let msg): return .invalidKey(msg)
            case .networkError(let msg): return .invalidKey("Network error: \(msg)")
            case .modelUnavailable: return .modelUnavailable
            }
        }
        wizardState.checkAccessibility = { Permissions.isAccessibilityGranted }
        wizardState.checkInputMonitoring = { Permissions.isInputMonitoringGranted }
        wizardState.checkScreenRecording = { Permissions.isScreenRecordingGranted }
        wizardState.requestAccessibility = { Permissions.requestAccessibility() }
        wizardState.requestScreenRecording = { Permissions.requestScreenRecording() }
        wizardState.onComplete = { [weak self] in
            guard let self else { return }
            UserDefaults.standard.set(true, forKey: AppDelegate.wizardCompletedKey)
            self.wizardWindow?.close()
            self.wizardWindow = nil

            // Re-register the global hotkey now that accessibility may have been granted
            let combo = self.resolveHotkey()
            self.launcherHotkey?.cleanup()
            self.launcherHotkey = GlobalHotkey(combo: combo) { [weak self] in
                self?.launcherPanel.toggle()
            }

            // Open the launcher panel
            self.launcherPanel.toggle()
        }

        // Pre-fill from dev config if available
        if let devConfig {
            wizardState.selectedProvider = devConfig.provider
            wizardState.apiKey = devConfig.apiKey
        }

        wizardWindow = WizardWindow(state: wizardState)
        wizardWindow?.show()
    }

    /// Read developer config from ~/.macotron-dev.json for auto-filling the wizard
    private func readDevConfig() -> (provider: String, apiKey: String)? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let devFile = home.appending(path: ".macotron-dev.json")
        guard let data = try? Data(contentsOf: devFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let apiKey = json["apiKey"] as? String, !apiKey.isEmpty else {
            return nil
        }
        let provider = json["provider"] as? String ?? "anthropic"
        return (provider: provider, apiKey: apiKey)
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

    // MARK: - Snippet Auto-Fix

    /// Wire the snippet auto-fix handler. This bridges SnippetManager (MacotronEngine)
    /// to SnippetAutoFix (AI) via a closure, since MacotronEngine cannot import AI.
    private func setupAutoFix() {
        snippetManager.autoFixHandler = { @Sendable [weak self] filename, source, error in
            await self?.autoFixSnippet(filename: filename, source: source, error: error)
        }
    }

    /// Called by the auto-fix handler closure. Lazily creates the SnippetAutoFix instance
    /// (requires an API key) and delegates the fix attempt.
    private func autoFixSnippet(filename: String, source: String, error: String) async -> String? {
        // Lazily create the auto-fixer when first needed (requires API key)
        if snippetAutoFixer == nil {
            guard let apiKey = resolveAIAPIKey() else {
                return nil
            }
            let providerName = resolveSelectedProvider()
            let provider = AIProviderFactory.create(name: providerName, config: .init(apiKey: apiKey))
            snippetAutoFixer = SnippetAutoFix(provider: provider)
        }

        guard let fixer = snippetAutoFixer else { return nil }
        return await fixer.attemptFix(filename: filename, source: source, error: error)
    }

    // MARK: - Agent

    private func handleAgentCommand(_ command: String) {
        // Check API key
        guard let apiKey = resolveAIAPIKey() else {
            settingsWindow.showWithAPIKeyRequired()
            return
        }

        // Dismiss launcher
        launcherPanel.toggle()

        // Show progress panel
        if agentProgressPanel == nil {
            agentProgressPanel = AgentProgressPanel()
        }
        agentProgressPanel?.show(topic: command)

        // Create agent session and run
        let provider = ClaudeProvider(apiKey: apiKey)
        let session = AgentSession(provider: provider, snippetManager: snippetManager)

        session.onProgress = { [weak self] progress in
            guard let panel = self?.agentProgressPanel else { return }
            switch progress {
            case .planning:
                panel.update("Planning...")
            case .writing(let filename):
                panel.update("Writing \(filename)...")
            case .testing:
                panel.update("Testing...")
            case .repairing(let attempt):
                panel.update("Repairing (attempt \(attempt))...")
            case .done(let success, let summary):
                let displaySummary = String(summary.prefix(100))
                panel.complete(success: success, summary: success ? "Done!" : displaySummary)
            }
        }

        Task {
            do {
                let _ = try await session.run(command: command)
            } catch {
                agentProgressPanel?.complete(success: false, summary: error.localizedDescription)
            }
        }
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
