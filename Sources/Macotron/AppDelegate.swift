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

    #if DEBUG
    private var debugServer: DebugServer?
    #endif

    private let configDir: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appending(path: ".macotron")
    }()

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Menubar-only app (no Dock icon)
        NSApp.setActivationPolicy(.accessory)

        // Set up engine
        engine = Engine()
        snippetManager = SnippetManager(engine: engine, configDir: configDir)
        snippetManager.ensureDirectoryStructure()

        // Set up snippet auto-fix (bridges MacotronEngine → AI target)
        setupAutoFix()

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

        // Set up launcher panel
        let launcherView = LauncherView(
            onExecuteCommand: { [weak self] id in
                self?.executeCommand(id)
            },
            onSearch: { [weak self] query in
                self?.search(query) ?? []
            },
            onChat: { @Sendable [weak self] message in
                guard let self else { return "Macotron is not available." }
                return await self.handleChatMessage(message)
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
        let launcherCombo: String
        if let launcher = engine.configStore["launcher"] as? [String: Any],
           let hotkey = launcher["hotkey"] as? String {
            launcherCombo = hotkey
        } else {
            launcherCombo = "cmd+space"
        }
        launcherHotkey = GlobalHotkey(combo: launcherCombo) { [weak self] in
            self?.launcherPanel.toggle()
        }

        snippetManager.startWatching()

        // Request accessibility on first launch
        if !Permissions.isAccessibilityGranted {
            Permissions.requestAccessibility()
        }

        // Start debug server if requested
        #if DEBUG
        if CommandLine.arguments.contains("--debug-server") {
            debugServer = DebugServer(engine: engine, snippetManager: snippetManager)
            debugServer?.start()
        }
        #endif
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
        if let cmd = engine.commandRegistry[id] {
            var undef = QJS_Undefined()
            _ = JS_Call(engine.context, cmd.callback, QJS_Undefined(), 0, &undef)
            engine.drainJobQueue()
        }
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
            let provider = ClaudeProvider(apiKey: apiKey)
            snippetAutoFixer = SnippetAutoFix(provider: provider)
        }

        guard let fixer = snippetAutoFixer else { return nil }
        return await fixer.attemptFix(filename: filename, source: source, error: error)
    }

    // MARK: - AI Chat

    private func handleChatMessage(_ message: String) async -> String {
        // Resolve the Claude API key: check config, then Keychain, then environment
        guard let apiKey = resolveAIAPIKey() else {
            return "No AI API key configured. Add one via:\n"
                + "  macotron.keychain.set(\"anthropic-api-key\", \"sk-ant-...\")\n"
                + "in your config.js, or set the ANTHROPIC_API_KEY environment variable."
        }

        let provider = ClaudeProvider(apiKey: apiKey)
        let session = ChatSession(provider: provider, snippetManager: snippetManager)

        do {
            return try await session.processMessage(message)
        } catch let error as AIProviderError {
            return "AI error: \(error.localizedDescription)"
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    /// Resolve the AI API key from multiple sources (in priority order):
    /// 1. Config store (set via macotron.config({ ai: { apiKey: "..." } }))
    /// 2. Keychain (set via macotron.keychain.set("anthropic-api-key", "..."))
    /// 3. Environment variable ANTHROPIC_API_KEY
    private func resolveAIAPIKey() -> String? {
        // 1. Check config store
        if let aiConfig = engine.configStore["ai"] as? [String: Any],
           let key = aiConfig["apiKey"] as? String, !key.isEmpty {
            return key
        }

        // 2. Check Keychain via the engine's KeychainModule
        let keychainKeys = ["anthropic-api-key", "claude-api-key", "ai-api-key"]
        for keyName in keychainKeys {
            if let key = KeychainModule.readFromKeychain(key: keyName), !key.isEmpty {
                return key
            }
        }

        // 3. Check environment variable
        if let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !key.isEmpty {
            return key
        }

        return nil
    }

    private func search(_ query: String) -> [SearchResult] {
        guard !query.isEmpty else { return [] }
        var results: [SearchResult] = []

        // Search commands
        for (_, cmd) in engine.commandRegistry {
            if let score = FuzzyMatch.score(query: query, target: cmd.name), score > 0 {
                results.append(SearchResult(
                    id: cmd.name,
                    title: cmd.name,
                    subtitle: cmd.description,
                    icon: "command",
                    type: .command
                ))
            }
        }

        // Search running apps
        for app in NSWorkspace.shared.runningApplications {
            guard let name = app.localizedName, !name.isEmpty else { continue }
            if let score = FuzzyMatch.score(query: query, target: name), score > 0 {
                results.append(SearchResult(
                    id: app.bundleIdentifier ?? name,
                    title: name,
                    subtitle: app.bundleIdentifier ?? "",
                    icon: "app",
                    type: .app
                ))
            }
        }

        // Sort by relevance (fuzzy score)
        results.sort { r1, r2 in
            let s1 = FuzzyMatch.score(query: query, target: r1.title) ?? 0
            let s2 = FuzzyMatch.score(query: query, target: r2.title) ?? 0
            return s1 > s2
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
