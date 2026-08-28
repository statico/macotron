// PluginListNavTests.swift — plugin sidebar selection rules
import Testing
@testable import MacotronUI

@Suite("PluginListNav")
struct PluginListNavTests {
    private func summary(_ filename: String, needsSetup: Bool = false) -> ModuleSummary {
        ModuleSummary(
            filename: filename,
            description: "",
            options: needsSetup
                ? [ModuleOption(key: "k", label: "K", type: "text", currentValue: "",
                                required: true, isSet: false)]
                : []
        )
    }

    private var plugins: [ModuleSummary] {
        [summary("a.js"), summary("b.js", needsSetup: true), summary("c.js")]
    }

    @Test("an empty list selects nothing")
    func empty() {
        #expect(PluginListNav.initialSelection(current: nil, in: []) == nil)
        #expect(PluginListNav.initialSelection(current: "gone.js", in: []) == nil)
    }

    @Test("with no selection, the first plugin needing setup wins")
    func prefersNeedsSetup() {
        #expect(PluginListNav.initialSelection(current: nil, in: plugins) == "b.js")
    }

    @Test("with nothing needing setup, the first plugin wins")
    func fallsBackToFirst() {
        let all = [summary("a.js"), summary("c.js")]
        #expect(PluginListNav.initialSelection(current: nil, in: all) == "a.js")
    }

    @Test("a live selection is never yanked away, even by a needs-setup plugin")
    func keepsLiveSelection() {
        #expect(PluginListNav.initialSelection(current: "c.js", in: plugins) == "c.js")
    }

    @Test("a selection whose file is gone falls back to the rules")
    func droppedSelection() {
        #expect(PluginListNav.initialSelection(current: "gone.js", in: plugins) == "b.js")
    }

    @Test("a filter that still contains the selection keeps it")
    func filterKeepsSelection() {
        let filtered = [summary("b.js"), summary("c.js")]
        #expect(PluginListNav.selectionAfterFilter(current: "c.js", in: filtered) == "c.js")
    }

    @Test("a filter that drops the selection moves to the first match")
    func filterMovesSelection() {
        let filtered = [summary("b.js"), summary("c.js")]
        #expect(PluginListNav.selectionAfterFilter(current: "a.js", in: filtered) == "b.js")
    }

    @Test("a filter matching nothing leaves the selection alone")
    func filterMatchesNothing() {
        #expect(PluginListNav.selectionAfterFilter(current: "a.js", in: []) == "a.js")
    }
}
