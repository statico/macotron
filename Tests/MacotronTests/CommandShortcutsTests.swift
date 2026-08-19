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

    @Test("removeCombo drops every id using that combo")
    func removeCombo() {
        var table = CommandShortcuts()
        table.assign(commandId: "a", combo: "cmd+shift+l")
        table.removeCombo("Cmd+Shift+L")
        #expect(table.bindings.isEmpty)
    }
}
