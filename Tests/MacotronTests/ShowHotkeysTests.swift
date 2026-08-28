import Testing
import MacotronEngine
@testable import MacotronUI

@Suite("Show Hotkeys")
struct ShowHotkeysTests {
    @Test("host command has stable metadata")
    func hostCommandMetadata() {
        let cmd = HostCommands.definition(for: HostCommands.showHotkeysID)
        #expect(cmd?.id == "macotron.show-hotkeys")
        #expect(cmd?.name == "Show Hotkeys")
        #expect(!cmd!.description.isEmpty)
    }

    @Test("rows sort by label and skip unbound shortcuts")
    func hotkeyRows() {
        let plugin = ModuleSummary(
            filename: "demo.js",
            title: "Windows",
            description: "",
            options: [
                ModuleOption(
                    key: "toggle",
                    label: "Toggle Grid",
                    type: "keybinding",
                    currentValue: "ctrl+opt+g"
                ),
            ],
            hotkeys: [
                PluginCommandSummary(id: "demo.js/Left", name: "Left Half", shortcut: "ctrl+opt+left"),
                PluginCommandSummary(id: "demo.js/Right", name: "Right Half", shortcut: "none"),
            ],
            commands: [
                PluginCommandSummary(id: "cmd-z", name: "Zoom", shortcut: "cmd+shift+z"),
            ]
        )
        let claims = ShortcutConflicts.claims(
            launcher: "cmd+space",
            apps: [AppShortcutSummary(id: "com.apple.Safari", name: "Safari", shortcut: "cmd+shift+s")],
            modules: [plugin],
            commandShortcuts: CommandShortcuts()
        )
        let rows = ShortcutConflicts.hotkeyRows(from: claims)
        #expect(rows.map(\.label) == [
            "Launcher",
            "Safari",
            "Windows · Left Half",
            "Windows · Toggle Grid",
            "Windows · Zoom",
        ])
        #expect(rows.map(\.combo) == [
            "cmd+space",
            "cmd+shift+s",
            "ctrl+opt+left",
            "ctrl+opt+g",
            "cmd+shift+z",
        ])
    }

    @Test("disabled plugins are excluded from rows")
    func disabledPluginsExcluded() {
        let plugin = ModuleSummary(
            filename: "demo.js",
            title: "Windows",
            description: "",
            hotkeys: [PluginCommandSummary(id: "demo.js/Left", name: "Left Half", shortcut: "ctrl+opt+left")],
            isEnabled: false
        )
        let rows = ShortcutConflicts.hotkeyRows(from: ShortcutConflicts.claims(
            launcher: "cmd+space",
            apps: [],
            modules: [plugin],
            commandShortcuts: CommandShortcuts()
        ))
        #expect(rows.map(\.label) == ["Launcher"])
    }

    @Test("claims include bound host command shortcuts")
    func hostCommandInClaims() {
        var table = CommandShortcuts()
        table.assign(commandId: HostCommands.showHotkeysID, combo: "ctrl+opt+h")
        let rows = ShortcutConflicts.hotkeyRows(from: ShortcutConflicts.claims(
            launcher: "cmd+space",
            apps: [],
            modules: [],
            commandShortcuts: table
        ))
        #expect(rows.map(\.label) == ["Launcher", "Show Hotkeys"])
        #expect(rows.map(\.combo) == ["cmd+space", "ctrl+opt+h"])
    }

    @Test("saveShowHotkeysHotkey re-reads persisted combo after save")
    @MainActor
    func saveRejectsRefresh() {
        let state = SettingsState()
        state.showHotkeysHotkey = "cmd+shift+h"
        state.saveCommandShortcut = { id, combo in
            #expect(id == HostCommands.showHotkeysID)
            #expect(combo == "cmd+shift+h")
        }
        state.readShowHotkeysHotkey = { "" }
        state.saveShowHotkeysHotkey()
        #expect(state.showHotkeysHotkey == "")
    }

    @Test("duplicate labels sort deterministically by combo then id")
    func duplicateLabelOrdering() {
        let claims = [
            ShortcutConflicts.Claim(id: "app:b", combo: "cmd+shift+b", label: "Notes", pluginFile: nil),
            ShortcutConflicts.Claim(id: "app:a", combo: "cmd+shift+a", label: "Notes", pluginFile: nil),
            ShortcutConflicts.Claim(id: "app:c", combo: "cmd+shift+a", label: "Notes", pluginFile: nil),
        ]
        let rows = ShortcutConflicts.hotkeyRows(from: claims)
        #expect(rows.map(\.id) == ["app:a", "app:c", "app:b"])
    }
}
