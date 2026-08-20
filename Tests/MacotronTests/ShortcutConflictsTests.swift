import Testing
@testable import MacotronUI

@Suite("ShortcutConflicts")
struct ShortcutConflictsTests {
    @Test("empty and unbound combos are ignored")
    func normalize() {
        #expect(ShortcutConflicts.normalize("") == nil)
        #expect(ShortcutConflicts.normalize("  ") == nil)
        #expect(ShortcutConflicts.normalize("none") == nil)
        #expect(ShortcutConflicts.normalize("Cmd+Space") == "cmd+space")
    }

    @Test("launcher vs plugin hotkey is a conflict")
    func launcherVsPlugin() {
        let plugin = ModuleSummary(
            filename: "demo.js",
            title: "Windows",
            description: "",
            hotkeys: [PluginCommandSummary(id: "demo.js/Left", name: "Left Half", shortcut: "cmd+space")]
        )
        let claims = ShortcutConflicts.claims(launcher: "cmd+space", apps: [], modules: [plugin])
        #expect(ShortcutConflicts.pluginHasConflict("demo.js", in: claims))
        #expect(ShortcutConflicts.warning(for: ShortcutConflicts.launcherID, combo: "cmd+space", in: claims) == "Also used by Windows · Left Half")
    }

    @Test("disabled plugins do not count")
    func disabledIgnored() {
        let plugin = ModuleSummary(
            filename: "demo.js",
            title: "Windows",
            description: "",
            hotkeys: [PluginCommandSummary(id: "demo.js/Left", name: "Left Half", shortcut: "cmd+space")],
            isEnabled: false
        )
        let claims = ShortcutConflicts.claims(launcher: "cmd+space", apps: [], modules: [plugin])
        #expect(!ShortcutConflicts.pluginHasConflict("demo.js", in: claims))
        #expect(ShortcutConflicts.warning(for: ShortcutConflicts.launcherID, combo: "cmd+space", in: claims) == nil)
    }

    @Test("app shortcut vs command is a conflict")
    func appVsCommand() {
        let plugin = ModuleSummary(
            filename: "demo.js",
            title: "Notes",
            description: "",
            commands: [PluginCommandSummary(id: "cmd-1", name: "New Note", shortcut: "ctrl+opt+n")]
        )
        let app = AppShortcutSummary(id: "com.apple.Notes", name: "Notes", shortcut: "ctrl+opt+n")
        let claims = ShortcutConflicts.claims(launcher: "cmd+space", apps: [app], modules: [plugin])
        #expect(ShortcutConflicts.warning(for: "command:cmd-1", combo: "ctrl+opt+n", in: claims) == "Also used by Notes")
        #expect(ShortcutConflicts.pluginHasConflict("demo.js", in: claims))
    }

    @Test("two plugins sharing a combo both conflict")
    func twoPlugins() {
        let a = ModuleSummary(
            filename: "a.js",
            title: "Windows",
            description: "",
            hotkeys: [PluginCommandSummary(id: "a/left", name: "Left", shortcut: "ctrl+opt+left")]
        )
        let b = ModuleSummary(
            filename: "b.js",
            title: "Grid",
            description: "",
            hotkeys: [PluginCommandSummary(id: "b/left", name: "Left", shortcut: "ctrl+opt+left")]
        )
        let claims = ShortcutConflicts.claims(launcher: "cmd+space", apps: [], modules: [a, b])
        #expect(ShortcutConflicts.pluginHasConflict("a.js", in: claims))
        #expect(ShortcutConflicts.pluginHasConflict("b.js", in: claims))
        #expect(ShortcutConflicts.warning(for: "hotkey:a/left", combo: "ctrl+opt+left", in: claims) == "Also used by Grid · Left")
    }

    @Test("cleared plugin shortcuts are ignored")
    func unboundIgnored() {
        let plugin = ModuleSummary(
            filename: "demo.js",
            title: "Windows",
            description: "",
            hotkeys: [PluginCommandSummary(id: "demo.js/Left", name: "Left Half", shortcut: "none")]
        )
        let claims = ShortcutConflicts.claims(launcher: "cmd+space", apps: [], modules: [plugin])
        #expect(!ShortcutConflicts.pluginHasConflict("demo.js", in: claims))
    }
}
