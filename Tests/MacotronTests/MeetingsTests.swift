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

    @Test("shows the soonest event even when the host returns them unsorted")
    func sortsUnsortedEvents() throws {
        let now = Int(Date().timeIntervalSince1970 * 1000)
        let result = try PluginHarness.evalSettled(plugin: "meetings.js", mock: """
            var statusConfig = null;
            var macotron = {
                plugin: () => ({ hours: 12, hide: "", time: "relative" }),
                system: { locale: () => ({ hour12: true }) },
                calendar: {
                    upcoming: () => Promise.resolve([
                        { id: "b", title: "Later", start: \(now + 7200000), end: \(now + 9000000), allDay: false, location: "", calendar: "Work" },
                        { id: "a", title: "Sooner", start: \(now + 600000), end: \(now + 1200000), allDay: false, location: "", calendar: "Work" }
                    ])
                },
                menubar: { status: (id, cfg) => { statusConfig = cfg; } },
                app: { launch: () => {} },
                url: { open: () => {} },
                every: () => {},
                command: () => {},
                notify: { toast: () => {} }
            };
            """, extra: "statusConfig.title")
        #expect(result.contains("Sooner"))
    }

    @Test("a failed fetch still repaints and drops ended meetings")
    func failedFetchStillPaints() throws {
        let now = Int(Date().timeIntervalSince1970 * 1000)
        // First paint sees one meeting already over and one rejection later:
        // the item must still paint, and the ended meeting must not linger.
        let engine = try PluginHarness.load(plugin: "meetings.js", mock: """
            var statusConfig = null;
            var paintCount = 0;
            var tick = null;
            var macotron = {
                plugin: () => ({ hours: 12, hide: "", time: "relative" }),
                system: { locale: () => ({ hour12: true }) },
                calendar: {
                    upcoming: () => Promise.reject(new Error("calendar down"))
                },
                menubar: { status: (id, cfg) => { paintCount++; statusConfig = cfg; } },
                app: { launch: () => {} },
                url: { open: () => {} },
                every: (ms, fn) => { tick = fn; },
                command: () => {},
                notify: { toast: () => {} }
            };
            """)
        #expect(PluginHarness.run(engine, "statusConfig.title") == "No meetings")
        // A later tick after the calendar recovers, then breaks again: the
        // cached events keep painting, minus anything that has since ended.
        PluginHarness.run(engine, """
            macotron.calendar.upcoming = () => Promise.resolve([
                { id: "gone", title: "Over", start: \(now - 3600000), end: \(now - 1000), allDay: false, location: "", calendar: "Work" },
                { id: "next", title: "Planning", start: \(now + 600000), end: \(now + 1200000), allDay: false, location: "", calendar: "Work" }
            ]);
            tick();
            """)
        #expect(PluginHarness.run(engine, "statusConfig.title").contains("Planning"))
        PluginHarness.run(engine, """
            macotron.calendar.upcoming = () => Promise.reject(new Error("down again"));
            tick();
            """)
        #expect(PluginHarness.run(engine, "statusConfig.title").contains("Planning"))
        #expect(engine.lastUnhandledRejection == nil)
    }
}
