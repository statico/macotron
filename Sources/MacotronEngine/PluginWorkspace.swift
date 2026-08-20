// PluginWorkspace.swift — User-chosen plugins directory (git workdir for external agents)
import Foundation
import os

private let logger = Logger(subsystem: "io.statico.macotron", category: "workspace")

@MainActor
public final class PluginWorkspace {
    public static let directoryDefaultsKey = "pluginsDirectory"

    public let root: URL

    public var pluginsDir: URL { root.appending(path: "plugins") }
    public var cacheDir: URL { root.appending(path: ".cache") }
    public var settingsFile: URL { root.appending(path: "settings.json") }

    public init(root: URL) {
        self.root = root
    }

    // MARK: - Resolve

    /// Resolve the plugins directory from UserDefaults (bookmark Data or path String).
    /// Returns nil if unset or invalid.
    public static func resolveFromDefaults(
        defaults: UserDefaults = .standard
    ) -> URL? {
        let value = defaults.object(forKey: directoryDefaultsKey)
        if let data = value as? Data {
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else { return nil }
            _ = url.startAccessingSecurityScopedResource()
            if isStale {
                savePath(url, defaults: defaults)
            }
            return url
        }
        if let path = value as? String, !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return nil
    }

    /// Persist a directory path (and security-scoped bookmark when possible).
    public static func savePath(_ url: URL, defaults: UserDefaults = .standard) {
        if let bookmark = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            defaults.set(bookmark, forKey: directoryDefaultsKey)
        } else {
            defaults.set(url.path(percentEncoded: false), forKey: directoryDefaultsKey)
        }
    }

    // MARK: - Ensure ready

    /// Create layout, git repo, seed README once, always rewrite AGENTS.md + CLAUDE.md.
    public func ensureReady() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: pluginsDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        try seedTypecheckCache()
        migrateLegacyModulesIfNeeded()

        let gitignore = root.appending(path: ".gitignore")
        try Self.gitignoreContents.write(to: gitignore, atomically: true, encoding: .utf8)

        let gitDir = root.appending(path: ".git")
        if !fm.fileExists(atPath: gitDir.path(percentEncoded: false)), Self.gitIsUsable() {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            proc.arguments = ["init"]
            proc.currentDirectoryURL = root
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            do {
                try proc.run()
                proc.waitUntilExit()
                if proc.terminationStatus != 0 {
                    logger.error("git init failed with status \(proc.terminationStatus)")
                }
            } catch {
                logger.error("git init skipped: \(error.localizedDescription)")
            }
        }

        let readme = root.appending(path: "README.md")
        if !fm.fileExists(atPath: readme.path(percentEncoded: false)) {
            try Self.readmeTemplate.write(to: readme, atomically: true, encoding: .utf8)
        }

        try Self.agentsTemplate.write(
            to: root.appending(path: "AGENTS.md"),
            atomically: true,
            encoding: .utf8
        )
        try Self.claudeTemplate.write(
            to: root.appending(path: "CLAUDE.md"),
            atomically: true,
            encoding: .utf8
        )

        if !fm.fileExists(atPath: settingsFile.path(percentEncoded: false)) {
            try writeSettings(Self.defaultSettings)
        }
    }

    /// Real git, not the Xcode CLT stub. Workdir still works without it.
    private static func gitIsUsable() -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        proc.arguments = ["-p"]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Copy bundle `macotron.d.ts` and seed `.cache/jsconfig.json` for agent typecheck.
    private func seedTypecheckCache() throws {
        let dtsDest = cacheDir.appending(path: "macotron.d.ts")
        if let src = Bundle.main.url(forResource: "macotron", withExtension: "d.ts") {
            try? FileManager.default.removeItem(at: dtsDest)
            do {
                try FileManager.default.copyItem(at: src, to: dtsDest)
            } catch {
                logger.error("Failed to copy macotron.d.ts: \(error.localizedDescription)")
            }
        } else {
            logger.info("macotron.d.ts not in bundle; skipping copy")
        }

        let jsconfig = """
        {
          "compilerOptions": {
            "checkJs": true,
            "noEmit": true,
            "strict": true,
            "target": "ES2020",
            "module": "ESNext",
            "types": []
          },
          "files": ["macotron.d.ts"],
          "include": ["../plugins/**/*.js"]
        }
        """
        try jsconfig.write(
            to: cacheDir.appending(path: "jsconfig.json"),
            atomically: true,
            encoding: .utf8
        )
    }

    /// One-time move of legacy modules/ into plugins/ when plugins/ is empty.
    private func migrateLegacyModulesIfNeeded() {
        let fm = FileManager.default
        let legacy = root.appending(path: "modules")
        guard fm.fileExists(atPath: legacy.path(percentEncoded: false)) else { return }

        let existing = (try? fm.contentsOfDirectory(
            at: pluginsDir, includingPropertiesForKeys: nil
        )) ?? []
        let hasPlugins = existing.contains { $0.pathExtension == "js" }
        guard !hasPlugins else { return }

        guard let files = try? fm.contentsOfDirectory(
            at: legacy, includingPropertiesForKeys: nil
        ) else { return }

        for file in files where file.pathExtension == "js" {
            let dest = pluginsDir.appending(path: file.lastPathComponent)
            try? fm.moveItem(at: file, to: dest)
            logger.info("Migrated \(file.lastPathComponent) to plugins/")
        }
    }

    // MARK: - Settings

    public func readSettings() -> [String: Any] {
        guard let data = try? Data(contentsOf: settingsFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return Self.defaultSettings
        }
        return json
    }

    public func writeSettings(_ settings: [String: Any]) throws {
        let data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: settingsFile, options: .atomic)
    }

    public func updateSettings(_ mutate: (inout [String: Any]) -> Void) throws {
        var settings = readSettings()
        mutate(&settings)
        try writeSettings(settings)
    }

    // MARK: - Defaults & templates

    public static let defaultSettings: [String: Any] = [
        "launcher": ["hotkey": "cmd+space"],
        "ui": [
            "showDockIcon": true,
            "showMenuBarIcon": true,
            "appearance": "system",
            "textScale": 1.0,
            "launcherBackground": "translucent",
        ],
        "modules": [:] as [String: Any],
        "pluginSettings": [:] as [String: Any],
        "disabledPlugins": [] as [String],
        "commandShortcuts": [:] as [String: String],
        "keyboardShortcuts": [:] as [String: String],
        "launcherFavorites": [] as [String],
        "security": ["shell": ["allow": [] as [String], "strict": false]],
    ]

    public static let gitignoreContents = """
    AGENTS.md
    CLAUDE.md
    .cache/
    """

    public static let agentsBanner = "<!-- DO NOT EDIT — Macotron overwrites this file. -->"

    public static var agentsTemplate: String {
        """
        \(agentsBanner)

        # Macotron plugins directory

        This directory is the Macotron workdir. External coding agents edit plugins here.
        Macotron loads the plugins and runs them. The app does not write plugin code.

        ## Layout

        - `plugins/*.js` — plugin scripts. Macotron loads every `.js` file in alphabetical order.
        - `settings.json` — launcher hotkey, UI prefs, module options. Do not put secrets here.
        - `.cache/` — bytecode cache and typecheck config. Gitignored. Do not edit.
        - `AGENTS.md` / `CLAUDE.md` — owned by Macotron. Overwritten on every launch.

        ## API version

        Current plugin API version is `\(Engine.apiVersion)` (`macotron.version.api`).
        Bump only when the plugin-facing JS contract changes.

        ## Built-in macOS only

        Plugins must run on a stock Mac with only Macotron installed. Use `macotron.*`
        APIs and Apple-shipped tools (`/usr/bin/open`, `/usr/bin/defaults`, `/bin/mv`).
        Do not call Homebrew, npm, pip, ffmpeg, Chrome-only binaries, or other
        third-party installs. Optional cloud AI keys are fine; they are not required
        for the host or demo plugins to load.

        ## API compatibility pragma

        Optional. Put at the top of a plugin when you need a minimum API version:

        ```js
        // @macotron needs 1.2
        // also accepted: 1.2.0
        ```

        - Missing `needs` means `needs 1.0.0`.
        - Short forms normalize (`1.2` → `1.2.0`) before compare.
        - Host loads only if `host.api >= plugin.needs`.

        ## Validate after edits

        Load-check from this workdir:

        `~/Applications/Macotron.app/Contents/MacOS/Macotron --check plugins/your-file.js`

        Do not edit `AGENTS.md` / `CLAUDE.md`.

        ## Plugins

        Put one `.js` file per plugin under `plugins/`. Each file runs in its own
        function scope, so `const opts` in two plugins does not collide.

        Register hotkeys at load time:

        ```js
        macotron.keyboard.on("Hello", "cmd+shift+h", () => {
          macotron.notify.toast("Hello", "From a Macotron plugin");
        });
        ```

        The id is the Settings label. Ids are unique per plugin. Users override the combo in Settings → Plugins.

        `macotron.notify.toast(title, body?, { position, duration, sfSymbol, color })` is a
        one-line HUD on the screen under the cursor (3s default). `color` is `info`,
        `success` (green check), `error` (red x), or `warning` (orange triangle).
        `macotron.notify.show` is a system banner.
        `macotron.screen.pickColor()` opens the system magnifier and returns
        `{ hex, r, g, b, x, y }` or `null`.

        ## Launcher commands

        ```js
        macotron.command("Generate Lorem Ipsum", "Placeholder text", (args) => {
          macotron.clipboard.set(String(args.count) + " " + args.unit);
        }, {
          id: "lorem-ipsum",
          arguments: [
            { name: "count", type: "number", placeholder: "Count", default: 3 },
            { name: "unit", type: "dropdown", placeholder: "Unit", default: "paragraphs",
              choices: [
                { title: "Words", value: "words" },
                { title: "Lines", value: "lines" },
                { title: "Paragraphs", value: "paragraphs" },
              ],
            },
          ],
        });
        ```

        The three-argument form still works. `id` is optional; the default is `{filename}/{name}`.
        Set `id` if the user will assign a shortcut. Users set shortcuts in Settings → Plugins
        or in the launcher with ⌘K on the selected result (apps too). Do not call `keyboard.on`
        for launcher commands. `keyboard.on(id, default, callback)` is for global hotkeys;
        those combos are also overridable in Settings → Plugins.

        ## Panel API (stub)

        ```js
        const id = macotron.panel.open({ title: "Chat", width: 420, height: 520, html: "<p>Hi</p>", glass: true });
        macotron.panel.close(id);
        macotron.panel.postMessage(id, { hello: true });
        macotron.panel.onMessage(id, (data) => { /* ... */ });
        ```

        `html` is inserted into a host document (system font, padding, light/dark).
        `rawHtml` is a full document. `glass: true` (or `"regular"`) uses Liquid Glass
        with a transparent page background; `glass: "clear"` is the clearer variant.
        Host CSS exposes `--macotron-accent` (and related `--macotron-*` system colors);
        `button.primary` uses the accent color. In the page, `close()` closes the panel.
        The page may also call `webkit.messageHandlers.macotron.postMessage(data)`.

        ## Plugin metadata and settings

        Every plugin must declare a title and description so they appear in
        Settings → Plugins. Put macOS permissions on the same call:

        ```js
        const opts = macotron.plugin({
          title: "Chat",
          description: "Talk to a model",
          help: "Set an API key below for cloud models.",
          permissions: ["accessibility"],
        });
        ```

        Valid permission names: `accessibility`, `inputMonitoring`, `screenRecording`,
        `fanControl`. Window control needs `accessibility`. Screen capture needs
        `screenRecording`. Holding a fan-speed floor needs `fanControl`, which the
        user installs from this plugin's Settings page.

        Add `options` on the same call to expose configurable settings. The user
        edits values in Settings → Plugins; the plugin reads the resolved values
        from the `macotron.plugin()` return value. Do not hand-edit
        `pluginSettings` to configure plugins — use the Settings UI.

        ```js
        const opts = macotron.plugin({
          title: "Chat",
          description: "Talk to a model",
          options: {
            model: {
              type: "dropdown",
              label: "Model",
              default: "sonnet",
              choices: [
                { value: "sonnet", label: "Claude Sonnet" },
                { value: "opus", label: "Claude Opus" },
              ],
            },
            apiKey: { type: "password", label: "Anthropic API key", required: true },
            openHotkey: { type: "keybinding", label: "Open chat", default: "cmd+shift+c" },
            notesFile: { type: "file", label: "Notes file" },
            workspace: { type: "directory", label: "Workspace folder" },
          },
        });
        // opts.apiKey === resolved secret string (or "")
        ```

        Option types: `string`, `boolean`, `number`, `keybinding`, `dropdown`
        (requires `choices: [{ value, label }]`), `password`, `file`, `directory`.
        Every option takes `label`, optional `default`, and optional `required`
        (Settings shows a "Needs setup" hint while a required option is unset).

        `password` options: the secret lives in the macOS Keychain. `settings.json`
        stores only a Keychain ref like `macotron.plugin.chat.js.apiKey`. Refs may
        be committed; real secrets must never appear in JSON or plugin source.
        `macotron.plugin()` returns the resolved secret string, never the ref.
        `file` / `directory` store absolute path strings.

        Report host problems with `macotron.checks([{ title, ok, message }])`.
        Replace the list each call; `[]` clears it. A failed check (`ok: false`)
        shows an orange warning on the plugin in Settings → Plugins.
        `macotron.settings.open()` opens that plugin's page.

        ```js
        macotron.checks([
          { title: "Speed control", ok: false, message: "This Mac blocked fan-speed writes." },
        ]);
        ```

        ## settings.json schema

        ```json
        {
          "launcher": { "hotkey": "cmd+space" },
          "ui": {
            "showDockIcon": true,
            "showMenuBarIcon": true,
            "appearance": "system",
            "textScale": 1.0,
            "launcherBackground": "translucent"
          },
          "modules": {},
          "pluginSettings": {},
          "disabledPlugins": [],
          "commandShortcuts": {},
          "keyboardShortcuts": {},
          "launcherFavorites": [],
          "security": { "shell": { "allow": [], "strict": false } }
        }
        ```
        Disabled plugins stay on disk but are not loaded; manage them in Settings → Plugins.

        ## Git

        Commit often on `main`. Never commit secrets (API keys, tokens, passwords).
        Declare `password` options and let the user set them in Settings, or store
        secrets with `macotron.keychain`. Macotron runs `git init` only when Apple
        developer tools are already installed. Git is optional.

        ## AI from plugins

        Plugins may call `macotron.ai.claude()`, `macotron.ai.anthropic()`,
        `macotron.ai.gemini()`, `macotron.ai.openai()`, or `macotron.ai.local()`.
        Prefer a `password` option for API keys (the user sets it in Settings);
        `macotron.keychain.get("anthropic-api-key")` also works for shared keys.
        `ai.chat` / `ai.stream` accept a string or `[{role, content}]`. Use `stream` with
        `onChunk` for token updates. Save chat history yourself via `localStorage`.
        """
    }

    public static var claudeTemplate: String {
        """
        \(agentsBanner)

        See AGENTS.md in this directory. Macotron overwrites both files.
        """
    }

    public static let readmeTemplate = """
    # Macotron plugins

    This folder is your Macotron workdir. Add JavaScript plugins under `plugins/`.

    Open this folder in Cursor or Claude Code to edit plugins. Macotron reloads on save.

    See `AGENTS.md` for API notes (that file is rewritten by the app — do not edit it).
    """
}
