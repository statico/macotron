import Foundation
import Testing
@testable import MacotronEngine

@MainActor
@Suite("RemindersMenu")
struct RemindersMenuTests {
    private func eval(_ extra: String) throws -> String {
        let pluginURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Examples/plugins/reminders.js")
        let pluginSource = try String(contentsOf: pluginURL, encoding: .utf8)
        let harness = """
            var statusConfig = null;
            var completed = [];
            var added = [];
            var promptText = "Eggs";
            var macotron = {
                plugin: () => ({}),
                reminders: {
                    list: () => Promise.resolve([
                        { id: "1", title: "Buy milk", due: Date.now() + 3600000, completed: false, list: "Groceries" },
                        { id: "2", title: "Call dentist", due: null, completed: false, list: "Personal" }
                    ]),
                    complete: (id) => { completed.push(id); return { ok: true }; },
                    add: (row) => { added.push(row.title); return { ok: true, id: "n" }; }
                },
                menubar: { status: (id, cfg) => { statusConfig = cfg; } },
                every: () => {},
            };
            function prompt() { return promptText; }
            \(pluginSource)
            """
        let engine = Engine()
        // paint() is async now, so the harness has to settle before the
        // assertion reads what it painted: evaluate() drains the job queue.
        let (_, error) = engine.evaluate(harness, filename: pluginURL.path)
        #expect(error == nil)
        let (result, extraError) = engine.evaluate(extra, filename: pluginURL.path)
        #expect(extraError == nil)
        return result ?? ""
    }

    @Test("status title is the next reminder")
    func statusTitle() throws {
        let result = try eval("JSON.stringify({ title: statusConfig.title, symbol: statusConfig.sfSymbol, secondary: statusConfig.secondary })")
        #expect(result.contains("Buy milk"))
        #expect(result.contains("checklist"))
        #expect(result.contains(#""secondary":true"#))
    }

    @Test("menu complete and add")
    func menuActions() throws {
        let result = try eval("""
            statusConfig.menu[0].onClick();
            statusConfig.menu[statusConfig.menu.length - 1].onClick();
            JSON.stringify({ completed: completed, added: added })
            """)
        #expect(result.contains(#""1"#))
        #expect(result.contains("Eggs"))
    }
}
