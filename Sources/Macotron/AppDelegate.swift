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
