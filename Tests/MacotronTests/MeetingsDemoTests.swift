import Foundation
import Testing
@testable import MacotronEngine

@MainActor
@Suite("MeetingsDemoTests")
struct MeetingsDemoTests {
    @Test("hides personal and OOO, shows the next timed event")
    func hidesFilteredTitles() throws {
        let demoURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Examples/plugins/demo-meetings.js")
        let demo = try String(contentsOf: demoURL, encoding: .utf8)
        let now = Int(Date().timeIntervalSince1970 * 1000)
        let source = """
            var statusConfig = null;
            var macotron = {
                plugin: () => ({ hours: 12, hide: "personal\\nOOO" }),
                calendar: {
                    upcoming: () => ([
                        { id: "p", title: "Personal dentist", start: \(now + 600000), end: \(now + 1200000), allDay: false, location: "", calendar: "Home" },
                        { id: "o", title: "OOO", start: \(now), end: \(now + 86400000), allDay: true, location: "", calendar: "Work" },
                        { id: "s", title: "Standup", start: \(now + 3600000), end: \(now + 5400000), allDay: false, location: "", calendar: "Work" }
                    ])
                },
                menubar: { status: (id, cfg) => { statusConfig = cfg; } },
                app: { launch: () => {} },
                url: { open: () => {} },
                every: () => {},
                command: () => {},
                notify: { toast: () => {} }
            };
            \(demo)
            JSON.stringify({ title: statusConfig.title, count: statusConfig.menu.length })
            """
        let engine = Engine()
        let (result, error) = engine.evaluate(source, filename: demoURL.path)
        #expect(error == nil)
        #expect(result?.contains("Standup") == true)
        #expect(result?.contains("Personal") != true)
    }
}
