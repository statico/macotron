# -Style Settings Features Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add four -inspired features to Macotron Settings: launch at login, launcher text-size boost, an appearance switcher (System/Dark/Light for Macotron's own windows, independent of the system), and a master-detail Plugins tab with per-plugin enable/disable.

**Architecture:** All new prefs live in `settings.json` (the workdir remains the source of truth; UserDefaults keeps only `pluginsDirectory`). Launch-at-login state is owned by the system (`SMAppService`), read fresh each time. Appearance applies app-wide via `NSApp.appearance`. Text scale flows to the launcher through a `LauncherPrefs` observable. Plugin enable/disable is a `disabledPlugins` filename array that `ModuleManager.reloadAll()` filters out before evaluation.

**Tech Stack:** Swift 6.2 (strict concurrency, MainActor default), SwiftUI + AppKit, ServiceManagement (`SMAppService`), Swift Testing.

**Interpretation note:** "Appearance switcher per app" = Macotron's own appearance override (System / Dark / Light), exactly like the  General settings pane in the reference screenshot. It does not change other apps.

## Global Constraints

- Min target macOS 15; `SMAppService` (macOS 13+) is allowed.
- `make build` must stay clean; `swift test --build-path /tmp/macotron-build` must pass after every task.
- Commit after every task. Message style: imperative sentence case, no prefix (e.g. `Add launch at login toggle to Settings`).
- The working tree has unrelated in-progress changes on `feature/plugin-api-expansion`. Stage ONLY the files each task lists.
- No code comments that narrate what code does; comments only for non-obvious intent.
- UI verification uses the debug server: run `make dev` in a background terminal, then `curl -s "http://localhost:7777/screenshot?tab=N" -o /tmp/shot.png` and inspect the PNG.
- `settings.json` schema additions: `ui.appearance` (`"system"|"dark"|"light"`), `ui.textScale` (`0.8|1.0|1.2`), top-level `disabledPlugins` (`[String]` of filenames).

---

### Task 1: Launch at login

**Files:**
- Create: `Sources/MacotronUI/LaunchAtLogin.swift`
- Modify: `Sources/MacotronUI/SettingsView.swift` (SettingsState + generalTab)
- Modify: `Sources/Macotron/AppDelegate.swift` (setupSettings wiring)

**Interfaces:**
- Produces: `LaunchAtLogin.isEnabled: Bool`, `LaunchAtLogin.setEnabled(_:) -> Bool`; `SettingsState.launchAtLogin`, `SettingsState.toggleLaunchAtLogin(_:)`; closures `readLaunchAtLogin` / `writeLaunchAtLogin` wired in AppDelegate.

No unit test: this is thin `SMAppService` glue over system state (the repo has no Settings UI tests). Verification is manual via System Settings → General → Login Items.

- [ ] **Step 1: Create the SMAppService wrapper**

```swift
// LaunchAtLogin.swift — Login-item registration via SMAppService
import ServiceManagement

@MainActor
public enum LaunchAtLogin {
    public static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns whether the system accepted the change. Callers re-read
    /// `isEnabled` afterwards so a failed registration reverts the toggle.
    @discardableResult
    public static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            NSLog("[Macotron] Launch at login failed: \(error.localizedDescription)")
            return false
        }
    }
}
```

- [ ] **Step 2: Add state to SettingsState**

In `Sources/MacotronUI/SettingsView.swift`, inside `SettingsState` next to `showMenuBarIcon`:

```swift
    @Published public var launchAtLogin: Bool = false
```

Next to the `writeShowMenuBarIcon` closure declarations:

```swift
    public var readLaunchAtLogin: (() -> Bool)?
    public var writeLaunchAtLogin: ((Bool) -> Void)?
```

In `load()`, after `showMenuBarIcon = ...`:

```swift
        launchAtLogin = readLaunchAtLogin?() ?? false
```

After `toggleMenuBarIcon(_:)`:

```swift
    /// Re-reads the system status so a failed registration reverts the toggle.
    public func toggleLaunchAtLogin(_ value: Bool) {
        writeLaunchAtLogin?(value)
        launchAtLogin = readLaunchAtLogin?() ?? false
    }
```

- [ ] **Step 3: Add the General tab row**

In `generalTab`, directly above the `formRow("Launcher Hotkey")` block:

```swift
            formRow("Launch at Login") {
                Toggle("Open Macotron when you log in", isOn: Binding(
                    get: { state.launchAtLogin },
                    set: { state.toggleLaunchAtLogin($0) }
                ))
                .toggleStyle(.checkbox)
            }
```

- [ ] **Step 4: Wire closures in AppDelegate**

In `setupSettings()` in `Sources/Macotron/AppDelegate.swift`, after the `writeShowMenuBarIcon` assignment:

```swift
        settingsState.readLaunchAtLogin = { LaunchAtLogin.isEnabled }
        settingsState.writeLaunchAtLogin = { value in
            LaunchAtLogin.setEnabled(value)
        }
```

- [ ] **Step 5: Build and verify**

Run: `make build`
Expected: build succeeds with no warnings.

Then `make dev` in a background terminal and:

```bash
curl -s "http://localhost:7777/screenshot?tab=0" -o /tmp/macotron-general.png
```

Inspect the PNG: the Launch at Login row renders above Launcher Hotkey. Then `make run`, toggle it on, and confirm "Macotron" appears under System Settings → General → Login Items → Open at Login. Toggle off and confirm it disappears.

- [ ] **Step 6: Commit**

```bash
git add Sources/MacotronUI/LaunchAtLogin.swift Sources/MacotronUI/SettingsView.swift Sources/Macotron/AppDelegate.swift
git commit -m "Add launch at login toggle to Settings"
```

---

### Task 2: Appearance switcher (System / Dark / Light)

**Files:**
- Create: `Sources/MacotronUI/AppearanceSetting.swift`
- Modify: `Sources/MacotronUI/SettingsView.swift` (SettingsState + generalTab)
- Modify: `Sources/Macotron/AppDelegate.swift` (generic UI-value helpers, wiring, apply at bootstrap)
- Test: `Tests/MacotronTests/AppearanceSettingTests.swift`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: `AppearanceSetting` enum (`system`/`dark`/`light`, `.parse(_:)`, `.apply()`); `SettingsState.appearance`, `selectAppearance(_:)`; AppDelegate `readUIValue(_:)` / `writeUIValue(_:_:)` (also used by Task 3).

- [ ] **Step 1: Write the failing test**

```swift
// AppearanceSettingTests.swift — ui.appearance parsing and NSAppearance mapping
import AppKit
import Testing
@testable import MacotronUI

@Suite("AppearanceSetting")
struct AppearanceSettingTests {
    @Test("Parses known values")
    func parsesKnownValues() {
        #expect(AppearanceSetting.parse("dark") == .dark)
        #expect(AppearanceSetting.parse("light") == .light)
        #expect(AppearanceSetting.parse("system") == .system)
    }

    @Test("Unknown or missing values default to system")
    func defaultsToSystem() {
        #expect(AppearanceSetting.parse("blue") == .system)
        #expect(AppearanceSetting.parse(nil) == .system)
        #expect(AppearanceSetting.parse(42) == .system)
    }

    @Test("Maps to NSAppearance (nil means follow system)")
    func nsAppearanceMapping() {
        #expect(AppearanceSetting.system.nsAppearance == nil)
        #expect(AppearanceSetting.dark.nsAppearance?.name == .darkAqua)
        #expect(AppearanceSetting.light.nsAppearance?.name == .aqua)
    }
}
```

Do not test `apply()` — `NSApp` does not exist under `swift test`.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --build-path /tmp/macotron-build --filter AppearanceSetting`
Expected: FAIL — `AppearanceSetting` does not exist.

- [ ] **Step 3: Create AppearanceSetting**

```swift
// AppearanceSetting.swift — ui.appearance: system, dark, or light
import AppKit

public enum AppearanceSetting: String, CaseIterable, Identifiable, Sendable {
    case system
    case dark
    case light

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .system: return "System"
        case .dark: return "Dark"
        case .light: return "Light"
        }
    }

    /// nil means follow the system appearance.
    public var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .dark: return NSAppearance(named: .darkAqua)
        case .light: return NSAppearance(named: .aqua)
        }
    }

    public static func parse(_ raw: Any?) -> AppearanceSetting {
        (raw as? String).flatMap(AppearanceSetting.init(rawValue:)) ?? .system
    }

    /// Applies app-wide: every window and panel, including plugin WKWebViews.
    @MainActor
    public func apply() {
        NSApp.appearance = nsAppearance
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --build-path /tmp/macotron-build --filter AppearanceSetting`
Expected: PASS (3 tests).

- [ ] **Step 5: Add state to SettingsState**

Next to `launchAtLogin`:

```swift
    @Published public var appearance: AppearanceSetting = .system
```

Next to the closures:

```swift
    public var readAppearance: (() -> AppearanceSetting)?
    public var writeAppearance: ((AppearanceSetting) -> Void)?
```

In `load()`:

```swift
        appearance = readAppearance?() ?? .system
```

After `toggleLaunchAtLogin(_:)`:

```swift
    public func selectAppearance(_ value: AppearanceSetting) {
        appearance = value
        writeAppearance?(value)
    }
```

- [ ] **Step 6: Add the General tab row**

In `generalTab`, between the Menu Bar Icon row and the second `formDivider`:

```swift
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
```

- [ ] **Step 7: Wire AppDelegate with generic UI-value helpers**

In `Sources/Macotron/AppDelegate.swift`, next to `readUIBool`:

```swift
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
```

In `setupSettings()`:

```swift
        settingsState.readAppearance = { [weak self] in
            AppearanceSetting.parse(self?.readUIValue("appearance"))
        }
        settingsState.writeAppearance = { [weak self] value in
            self?.writeUIValue("appearance", value.rawValue)
            value.apply()
        }
```

In `applyUIPrefsFromSettings()`, append:

```swift
        AppearanceSetting.parse(readUIValue("appearance")).apply()
```

- [ ] **Step 8: Build, test, screenshot**

Run: `make build && swift test --build-path /tmp/macotron-build`
Expected: clean build, all tests pass.

With `make dev` running:

```bash
curl -s "http://localhost:7777/screenshot?tab=0" -o /tmp/macotron-appearance.png
```

Inspect: segmented System/Dark/Light control renders. Toggle Dark and confirm the Settings window itself switches immediately.

- [ ] **Step 9: Commit**

```bash
git add Sources/MacotronUI/AppearanceSetting.swift Sources/MacotronUI/SettingsView.swift Sources/Macotron/AppDelegate.swift Tests/MacotronTests/AppearanceSettingTests.swift
git commit -m "Add appearance switcher for Macotron windows"
```

---

### Task 3: Launcher text size boost

**Files:**
- Create: `Sources/MacotronUI/LauncherPrefs.swift`
- Modify: `Sources/MacotronUI/LauncherView.swift` (take prefs, scale fonts)
- Modify: `Sources/MacotronUI/SettingsView.swift` (SettingsState + generalTab)
- Modify: `Sources/Macotron/AppDelegate.swift` (own LauncherPrefs, wire, apply at bootstrap)

**Interfaces:**
- Consumes: `readUIValue` / `writeUIValue` from Task 2.
- Produces: `LauncherPrefs` (`@Published textScale: CGFloat`); `LauncherView(prefs:onExecuteCommand:onRevealInFinder:onSearch:onHeightChange:)`; `SettingsState.textScale`, `selectTextScale(_:)`.

Scope: launcher only. The Settings window is fixed-size and plugin WKWebView panels are plugin-owned — both out of scope for v1.

- [ ] **Step 1: Create LauncherPrefs**

```swift
// LauncherPrefs.swift — Live display prefs pushed into the launcher view
import SwiftUI

@MainActor
public final class LauncherPrefs: ObservableObject {
    /// Font scale for the launcher: 0.8, 1.0, or 1.2 (settings.json ui.textScale).
    @Published public var textScale: CGFloat

    public init(textScale: CGFloat = 1.0) {
        self.textScale = textScale
    }
}
```

- [ ] **Step 2: Scale the launcher fonts**

In `LauncherView.swift`, add the stored property and update the init:

```swift
public struct LauncherView: View {
    @ObservedObject private var prefs: LauncherPrefs
    @State private var query = ""
    @State private var results: [SearchResult] = []
    @State private var selectedIndex = 0

    public var onExecuteCommand: ((String) -> Void)?
    public var onRevealInFinder: ((String) -> Void)?
    public var onSearch: ((String) -> [SearchResult])?
    public var onHeightChange: ((CGFloat) -> Void)?

    public init(
        prefs: LauncherPrefs = LauncherPrefs(),
        onExecuteCommand: ((String) -> Void)? = nil,
        onRevealInFinder: ((String) -> Void)? = nil,
        onSearch: ((String) -> [SearchResult])? = nil,
        onHeightChange: ((CGFloat) -> Void)? = nil
    ) {
        self._prefs = ObservedObject(wrappedValue: prefs)
        self.onExecuteCommand = onExecuteCommand
        self.onRevealInFinder = onRevealInFinder
        self.onSearch = onSearch
        self.onHeightChange = onHeightChange
    }
```

Then multiply every explicit font size by `prefs.textScale`:

| Location | Before | After |
|---|---|---|
| Search icon | `.font(.system(size: 20))` | `.font(.system(size: 20 * prefs.textScale))` |
| Search field | `.font(.system(size: 20, weight: .regular))` | `.font(.system(size: 20 * prefs.textScale, weight: .regular))` |
| Empty state | `.font(.callout)` | `.font(.system(size: 12 * prefs.textScale))` |
| Shortcut hint key | `.font(.system(size: 10, weight: .medium, design: .rounded))` | size `10 * prefs.textScale` |
| Shortcut hint label | `.font(.caption2)` | `.font(.system(size: 10 * prefs.textScale))` |

Pass the scale into rows — change the `ResultRow` call site:

```swift
                            ResultRow(result: result, isSelected: index == selectedIndex,
                                      textScale: prefs.textScale)
```

And in `ResultRow`, add `var textScale: CGFloat = 1.0` and scale: icon `.font(.system(size: 16 * textScale))`, icon frame `.frame(width: 32 * textScale, height: 32 * textScale)`, title `14 * textScale`, subtitle `11 * textScale`, type label `10 * textScale`.

- [ ] **Step 3: Add state to SettingsState**

```swift
    @Published public var textScale: Double = 1.0
```

```swift
    public var readTextScale: (() -> Double)?
    public var writeTextScale: ((Double) -> Void)?
```

In `load()`:

```swift
        textScale = readTextScale?() ?? 1.0
```

```swift
    public func selectTextScale(_ value: Double) {
        textScale = value
        writeTextScale?(value)
    }
```

- [ ] **Step 4: Add the General tab row**

Directly below the Appearance row from Task 2:

```swift
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
```

- [ ] **Step 5: Wire AppDelegate**

Add the property next to `settingsState`:

```swift
    private let launcherPrefs = LauncherPrefs()
```

In `bootstrap(workspaceRoot:)`, change the `LauncherView(` call to pass `prefs: launcherPrefs` as the first argument.

In `setupSettings()`:

```swift
        settingsState.readTextScale = { [weak self] in
            let raw = self?.readUIValue("textScale") as? Double ?? 1.0
            return min(max(raw, 0.8), 1.2)
        }
        settingsState.writeTextScale = { [weak self] value in
            guard let self else { return }
            self.writeUIValue("textScale", value)
            self.launcherPrefs.textScale = CGFloat(value)
        }
```

In `applyUIPrefsFromSettings()`, append:

```swift
        let rawScale = readUIValue("textScale") as? Double ?? 1.0
        launcherPrefs.textScale = CGFloat(min(max(rawScale, 0.8), 1.2))
```

- [ ] **Step 6: Build and screenshot**

Run: `make build`
Expected: clean.

With `make dev` running:

```bash
curl -s "http://localhost:7777/screenshot?view=launcher" -o /tmp/macotron-launcher.png
curl -s "http://localhost:7777/screenshot?tab=0" -o /tmp/macotron-textsize.png
```

Inspect both: the Text Size row renders; after selecting 120%, the launcher search field and result rows are visibly larger (toggle via the live Settings window, then re-screenshot the launcher).

- [ ] **Step 7: Commit**

```bash
git add Sources/MacotronUI/LauncherPrefs.swift Sources/MacotronUI/LauncherView.swift Sources/MacotronUI/SettingsView.swift Sources/Macotron/AppDelegate.swift
git commit -m "Add launcher text size boost"
```

---

### Task 4: Plugins tab master-detail with enable/disable

**Files:**
- Modify: `Sources/MacotronEngine/SnippetManager.swift` (ModuleManager: `disabledPlugins()`, `isModuleEnabled`, `setModuleEnabled`, filter in `reloadAll`)
- Modify: `Sources/MacotronEngine/PluginWorkspace.swift` (defaultSettings + AGENTS.md schema doc)
- Modify: `Sources/MacotronUI/SettingsView.swift` (`ModuleSummary.isEnabled`, SettingsState closure, pluginsTab rewrite, delete `ModuleSummaryRow`)
- Modify: `Sources/MacotronUI/SettingsWindow.swift` (content size 760×520)
- Modify: `Sources/Macotron/AppDelegate.swift` (wire `setModuleEnabled`, `isEnabled` in summaries, captureWindow size)
- Modify: `docs/10-plugins-workdir.md` (settings.json schema)
- Test: `Tests/MacotronTests/PluginEnableTests.swift`

**Interfaces:**
- Consumes: nothing from Tasks 1–3 (independent; lands in the same files, so run it last).
- Produces: `ModuleManager.disabledPlugins() -> Set<String>`, `isModuleEnabled(filename:) -> Bool`, `setModuleEnabled(filename:enabled:)`; `ModuleSummary.isEnabled: Bool`; `SettingsState.setModuleEnabled: ((String, Bool) -> Void)?`.

Layout: left column 210px — selectable list of plugin names (status dot: red = error, orange = needs setup; dimmed when disabled) with the GitHub browse button pinned at the bottom. Right column — detail pane with title, enabled switch, description, errors, hotkey/event badges, the existing `ModuleOptionRow` settings form, and the Delete button. Disabled plugins stay listed (they are still on disk) but are never evaluated, so their commands, hotkeys, and timers vanish; their detail pane shows an "enable to configure" hint because option metadata only exists after evaluation.

- [ ] **Step 1: Write the failing test**

```swift
// PluginEnableTests.swift — disabledPlugins filtering and persistence
import Foundation
import Testing
@testable import MacotronEngine

@MainActor
@Suite("Plugin enable/disable")
struct PluginEnableTests {
    private func makeWorkspace() throws -> (PluginWorkspace, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "macotron-ws-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ws = PluginWorkspace(root: dir)
        try ws.ensureReady()
        return (ws, dir)
    }

    @Test("setModuleEnabled persists to settings.json")
    func setModuleEnabledPersists() throws {
        let (ws, dir) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: dir) }
        let manager = ModuleManager(engine: Engine(), workspace: ws)

        #expect(manager.isModuleEnabled(filename: "a.js"))

        manager.setModuleEnabled(filename: "a.js", enabled: false)
        #expect(!manager.isModuleEnabled(filename: "a.js"))
        #expect(ws.readSettings()["disabledPlugins"] as? [String] == ["a.js"])

        manager.setModuleEnabled(filename: "a.js", enabled: true)
        #expect(manager.isModuleEnabled(filename: "a.js"))
        #expect((ws.readSettings()["disabledPlugins"] as? [String])?.isEmpty == true)
    }

    @Test("reloadAll skips disabled plugins")
    func reloadSkipsDisabled() throws {
        let (ws, dir) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: dir) }

        // macotron-runtime.js is not in the test bundle, so plugins under test
        // use the core global directly instead of macotron.command().
        try "$$__registerCommand('enabled-cmd', 'on', function(){});"
            .write(to: ws.pluginsDir.appending(path: "a-enabled.js"), atomically: true, encoding: .utf8)
        try "$$__registerCommand('disabled-cmd', 'off', function(){});"
            .write(to: ws.pluginsDir.appending(path: "b-disabled.js"), atomically: true, encoding: .utf8)

        let engine = Engine()
        let manager = ModuleManager(engine: engine, workspace: ws)
        manager.setModuleEnabled(filename: "b-disabled.js", enabled: false)
        manager.reloadAll()

        #expect(engine.commandRegistry["enabled-cmd"] != nil)
        #expect(engine.commandRegistry["disabled-cmd"] == nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --build-path /tmp/macotron-build --filter PluginEnableTests`
Expected: FAIL — `isModuleEnabled` / `setModuleEnabled` do not exist.

- [ ] **Step 3: Implement enable/disable in ModuleManager**

In `Sources/MacotronEngine/SnippetManager.swift`, in the Settings section after `clearModuleSecret`:

```swift
    /// Filenames the user disabled in Settings. Disabled plugins stay on disk
    /// but are never evaluated.
    public func disabledPlugins() -> Set<String> {
        Set(workspace.readSettings()["disabledPlugins"] as? [String] ?? [])
    }

    public func isModuleEnabled(filename: String) -> Bool {
        !disabledPlugins().contains(filename)
    }

    public func setModuleEnabled(filename: String, enabled: Bool) {
        do {
            try workspace.updateSettings { settings in
                var disabled = settings["disabledPlugins"] as? [String] ?? []
                if enabled {
                    disabled.removeAll { $0 == filename }
                } else if !disabled.contains(filename) {
                    disabled.append(filename)
                }
                settings["disabledPlugins"] = disabled
            }
        } catch {
            logger.error("Failed to save disabledPlugins: \(error)")
        }
    }
```

In `reloadAll()`, replace the `pluginFiles` computation:

```swift
        let disabled = disabledPlugins()
        let pluginFiles = listJSFiles(in: workspace.pluginsDir)
            .filter { !disabled.contains($0.lastPathComponent) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
```

In `PluginWorkspace.defaultSettings`, add a top-level entry:

```swift
        "disabledPlugins": [] as [String],
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --build-path /tmp/macotron-build --filter PluginEnableTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Extend ModuleSummary and SettingsState**

In `SettingsView.swift`, add to `ModuleSummary`:

```swift
    public let isEnabled: Bool
```

with init parameter `isEnabled: Bool = true` (assign in the init body).

Add to `SettingsState` closures:

```swift
    public var setModuleEnabled: ((_ filename: String, _ enabled: Bool) -> Void)?
```

- [ ] **Step 6: Wire AppDelegate**

In `setupSettings()`:

```swift
        settingsState.setModuleEnabled = { [weak self] filename, enabled in
            guard let self else { return }
            self.moduleManager.setModuleEnabled(filename: filename, enabled: enabled)
            self.moduleManager.reloadAll()
            self.settingsState.refreshModules()
        }
```

In `buildPluginSummaries()`, after `let settings = moduleManager.loadModuleSettings()`:

```swift
        let disabled = moduleManager.disabledPlugins()
```

Inside the file loop, wrap the hotkey/event regex scans so they only run when enabled (a disabled plugin's hotkeys are inactive — showing them would lie), and pass the flag:

```swift
            let isEnabled = !disabled.contains(file.filename)
            var hotkeys: [String] = []
            var events: [String] = []
            if isEnabled {
                // ... existing hotkeyPattern and eventPattern scans ...
            }
```

and in the `ModuleSummary(` call add `isEnabled: isEnabled`.

In the debug-server `captureWindow` closure, change both the `.frame(width: 660, height: 460)` and the `renderViewToPNG` size to `760` × `520`.

- [ ] **Step 7: Rebuild the Plugins tab as master-detail**

In `SettingsWindow.swift`, change `contentSize` to `NSSize(width: 760, height: 520)`.

In `SettingsView.swift`, delete the entire `ModuleSummaryRow` struct and replace `pluginsTab` with:

```swift
    @State private var selectedPlugin: String?

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
```

Add the two new view structs at the bottom of the file (`ModuleOptionRow` stays unchanged and is reused):

```swift
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
```

- [ ] **Step 8: Update the schema docs**

In `PluginWorkspace.swift` `agentsTemplate`, replace the settings.json schema block:

```json
        {
          "launcher": { "hotkey": "cmd+space" },
          "ui": {
            "showDockIcon": true,
            "showMenuBarIcon": true,
            "appearance": "system",
            "textScale": 1.0
          },
          "modules": {},
          "pluginSettings": {},
          "disabledPlugins": [],
          "security": { "shell": { "allow": [], "strict": false } }
        }
```

Add one line after the block: `Disabled plugins stay on disk but are not loaded; manage them in Settings → Plugins.`

In `docs/10-plugins-workdir.md`, make the same schema update to the example.

- [ ] **Step 9: Build, test, screenshot**

Run: `make build && swift test --build-path /tmp/macotron-build`
Expected: clean build, all tests pass (old + new).

With `make dev` running:

```bash
curl -s "http://localhost:7777/screenshot?tab=1" -o /tmp/macotron-plugins.png
```

Inspect: left name list, right detail pane, Enabled switch works (toggle a plugin off → its commands disappear from `curl -s http://localhost:7777/commands`, the list row dims, and `disabledPlugins` appears in the workdir's `settings.json`).

- [ ] **Step 10: Commit**

```bash
git add Sources/MacotronEngine/SnippetManager.swift Sources/MacotronEngine/PluginWorkspace.swift Sources/MacotronUI/SettingsView.swift Sources/MacotronUI/SettingsWindow.swift Sources/Macotron/AppDelegate.swift Tests/MacotronTests/PluginEnableTests.swift docs/10-plugins-workdir.md
git commit -m "Add plugin enable/disable with master-detail Plugins settings"
```

---

## Self-Review Notes

- **Spec coverage:** launch at login → Task 1; text size boost → Task 3; appearance switcher → Task 2; plugin list w/ info+settings sidebar + enable/disable → Task 4. All four covered.
- **Type consistency:** `readUIValue`/`writeUIValue` (Task 2) are consumed by Task 3 — signatures match. `LauncherPrefs` init param order in Task 3 matches the AppDelegate call site. `setModuleEnabled(filename:enabled:)` matches across ModuleManager, SettingsState closure, and tests.
- **Out of scope (v1):** per-plugin custom settings UIs, text scaling inside the Settings window and plugin WKWebView panels, blocking launcher commands while required options are unset (per the existing plugin-settings spec).
