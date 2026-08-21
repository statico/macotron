import Testing
@testable import MacotronEngine

@Suite("Command shortcuts")
struct CommandShortcutsTests {
    @Test("assigning a combo to a second command moves it")
    func reassignMovesCombo() {
        var table = CommandShortcuts()
        table.assign(commandId: "a", combo: "cmd+shift+l")
        table.assign(commandId: "b", combo: "cmd+shift+l")
        #expect(table.bindings["a"] == nil)
        #expect(table.bindings["b"] == "cmd+shift+l")
    }

    @Test("round-trips through a JSON object")
    func jsonRoundTrip() {
        var table = CommandShortcuts()
        table.assign(commandId: "lorem-ipsum", combo: "Cmd+Shift+L")
        let loaded = CommandShortcuts.load(from: table.jsonObject())
        #expect(loaded.bindings["lorem-ipsum"] == "cmd+shift+l")
    }

    @Test("empty combo is a clear")
    func emptyComboClears() {
        var table = CommandShortcuts()
        table.assign(commandId: "a", combo: "cmd+shift+l")
        table.assign(commandId: "a", combo: "")
        #expect(table.bindings["a"] == nil)
    }

    @Test("unbound stays cleared instead of falling back to the default")
    func unboundDoesNotUseDefault() {
        var table = CommandShortcuts()
        table.assign(commandId: "a", combo: CommandShortcuts.unbound)
        #expect(table.resolved("a", default: "ctrl+opt+k") == "")
        #expect(table.resolved("b", default: "ctrl+opt+k") == "ctrl+opt+k")
    }

    @Test("clearing a second hotkey leaves the first one cleared")
    func clearingTwoStaysCleared() {
        var table = CommandShortcuts()
        table.assign(commandId: "a", combo: CommandShortcuts.unbound)
        table.assign(commandId: "b", combo: CommandShortcuts.unbound)
        #expect(table.resolved("a", default: "ctrl+opt+a") == "")
        #expect(table.resolved("b", default: "ctrl+opt+b") == "")
    }

    @Test("removeCombo drops every id using that combo")
    func removeCombo() {
        var table = CommandShortcuts()
        table.assign(commandId: "a", combo: "cmd+shift+l")
        table.removeCombo("Cmd+Shift+L")
        #expect(table.bindings.isEmpty)
    }

    @Test("unbindMatching writes none for defaults that still own the combo")
    func unbindMatchingDefaults() {
        var table = CommandShortcuts()
        table.unbindMatching(
            combo: "ctrl+opt+left",
            defaults: ["win/left": "ctrl+opt+left", "win/right": "ctrl+opt+right"],
            except: nil
        )
        #expect(table.resolved("win/left", default: "ctrl+opt+left") == "")
        #expect(table.resolved("win/right", default: "ctrl+opt+right") == "ctrl+opt+right")
    }

    @Test("unbindMatching skips the id that is keeping the combo")
    func unbindMatchingKeepsAssignee() {
        var table = CommandShortcuts()
        table.assign(commandId: "win/left", combo: "ctrl+opt+left")
        table.unbindMatching(
            combo: "ctrl+opt+left",
            defaults: ["win/left": "ctrl+opt+left", "grid/left": "ctrl+opt+left"],
            except: "win/left"
        )
        #expect(table.combo(for: "win/left") == "ctrl+opt+left")
        #expect(table.resolved("grid/left", default: "ctrl+opt+left") == "")
    }

    @Test("app bundle ids store like command ids")
    func appIds() {
        var table = CommandShortcuts()
        table.assign(commandId: "com.apple.Safari", combo: "cmd+shift+s")
        #expect(table.combo(for: "com.apple.Safari") == "cmd+shift+s")
    }
}
