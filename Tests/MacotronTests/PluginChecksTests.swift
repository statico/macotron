import Testing
@testable import MacotronEngine

@Suite("Plugin checks")
struct PluginChecksTests {
    @Test("parseList reads title, ok, and message")
    func parseRows() {
        let rows = PluginCheck.parseList([
            ["title": "Speed control", "ok": false, "message": "blocked"],
            ["title": "Fans", "ok": true, "message": "2 fans"],
        ])
        #expect(rows == [
            PluginCheck(title: "Speed control", ok: false, message: "blocked"),
            PluginCheck(title: "Fans", ok: true, message: "2 fans"),
        ])
    }

    @Test("parseList drops rows without a title and treats missing ok as failed")
    func parseSkipsAndDefaults() {
        let rows = PluginCheck.parseList([
            ["ok": true, "message": "no title"],
            ["title": "  ", "ok": true],
            ["title": "Ready"],
            ["title": "Numeric", "ok": 1],
            "skip me",
        ] as [Any])
        #expect(rows == [
            PluginCheck(title: "Ready", ok: false, message: ""),
            PluginCheck(title: "Numeric", ok: true, message: ""),
        ])
    }

    @Test("parseList of a non-array is empty")
    func parseNonArray() {
        #expect(PluginCheck.parseList(nil).isEmpty)
        #expect(PluginCheck.parseList("nope").isEmpty)
        #expect(PluginCheck.parseList(["title": "x"]).isEmpty)
    }
}

@MainActor
@Suite("Plugin checks JS")
struct PluginChecksJSTests {
    @Test("$$__checks stores rows for the current plugin file")
    func checksReplaceAndClear() {
        let engine = Engine()
        engine.currentEvaluatingFile = "fan.js"
        let (_, error) = engine.evaluate("""
            $$__checks([{ title: "Speed control", ok: false, message: "blocked" }]);
        """)
        #expect(error == nil)
        #expect(engine.pluginChecks["fan.js"] == [
            PluginCheck(title: "Speed control", ok: false, message: "blocked"),
        ])

        engine.evaluate("$$__checks([])")
        #expect(engine.pluginChecks["fan.js"] == nil)
    }

    @Test("$$__checks is ignored without a current plugin file")
    func checksNeedAFile() {
        let engine = Engine()
        engine.evaluate("$$__checks([{ title: 'x', ok: false, message: 'y' }])")
        #expect(engine.pluginChecks.isEmpty)
    }

    @Test("reset clears stored checks")
    func resetClearsChecks() {
        let engine = Engine()
        engine.currentEvaluatingFile = "fan.js"
        engine.evaluate("$$__checks([{ title: 'x', ok: true, message: '' }])")
        engine.reset()
        #expect(engine.pluginChecks.isEmpty)
    }
}
