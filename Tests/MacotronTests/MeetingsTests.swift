import Foundation
import Testing
@testable import MacotronEngine

@MainActor
@Suite("Meetings")
struct MeetingsTests {
    @Test("hides personal and OOO, shows the next timed event")
    func hidesFilteredTitles() throws {
        let now = Int(Date().timeIntervalSince1970 * 1000)
        // paint() is async, so read the menu bar back only after the job queue
        // that settles it has drained -- which evalSettled's second pass does.
        let result = try PluginHarness.evalSettled(plugin: "meetings.js", mock: """
            var statusConfig = null;
            var macotron = {
                plugin: () => ({ hours: 12, hide: "personal\\nOOO", time: "relative" }),
                system: { locale: () => ({ hour12: true }) },
                calendar: {
                    upcoming: () => Promise.resolve([
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
            """, extra: "JSON.stringify({ title: statusConfig.title, count: statusConfig.menu.length })")
        #expect(result.contains("Standup"))
        #expect(!result.contains("Personal"))
    }
}
