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
            var store = {};
            var localStorage = {
                getItem: (k) => (k in store ? store[k] : null),
                setItem: (k, v) => { store[k] = String(v); },
                removeItem: (k) => { delete store[k]; }
            };
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
            var store = {};
            var localStorage = {
                getItem: (k) => (k in store ? store[k] : null),
                setItem: (k, v) => { store[k] = String(v); },
                removeItem: (k) => { delete store[k]; }
            };
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

    @Test("a failed fetch still repaints and moves past ended meetings")
    func failedFetchStillPaints() throws {
        let now = Int(Date().timeIntervalSince1970 * 1000)
        // First paint sees one meeting already over and one rejection later:
        // the item must still paint, and the ended meeting must not take the title.
        let engine = try PluginHarness.load(plugin: "meetings.js", mock: """
            var store = {};
            var localStorage = {
                getItem: (k) => (k in store ? store[k] : null),
                setItem: (k, v) => { store[k] = String(v); },
                removeItem: (k) => { delete store[k]; }
            };
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
        // def2dd4 made the empty state icon-only, so an empty title is the
        // paint. What this test is really about is that a paint happened.
        #expect(PluginHarness.run(engine, "statusConfig.title") == "")
        #expect(PluginHarness.run(engine, "paintCount") != "0")
        // A later tick after the calendar recovers, then breaks again: the
        // cached events keep painting, with ended ones no longer the next.
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

    @Test("dims past and ignored events, and dismissing moves on to the next")
    func dimsAndDismisses() throws {
        let now = Int(Date().timeIntervalSince1970 * 1000)
        let engine = try PluginHarness.load(plugin: "meetings.js", mock: """
            var store = {};
            var localStorage = {
                getItem: (k) => (k in store ? store[k] : null),
                setItem: (k, v) => { store[k] = String(v); },
                removeItem: (k) => { delete store[k]; }
            };
            var statusConfig = null;
            var tick = null;
            var macotron = {
                plugin: () => ({ hours: 12, hide: "lunch", time: "relative", overlay: false }),
                system: { locale: () => ({ hour12: true }) },
                calendar: {
                    upcoming: () => Promise.resolve([
                        { id: "r", title: "Standup", start: \(now - 3600000), end: \(now - 1800000), allDay: false, location: "", calendar: "Work" },
                        { id: "l", title: "Lunch", start: \(now + 300000), end: \(now + 900000), allDay: false, location: "", calendar: "Work" },
                        { id: "a", title: "Planning", start: \(now + 600000), end: \(now + 1200000), allDay: false, location: "", calendar: "Work", url: "https://meet.example/x" },
                        { id: "b", title: "Review", start: \(now + 3600000), end: \(now + 5400000), allDay: false, location: "", calendar: "Home" }
                    ])
                },
                menubar: { status: (id, cfg) => { statusConfig = cfg; } },
                app: { launch: () => {} },
                url: { open: () => {} },
                every: (ms, fn) => { tick = fn; },
                command: () => {},
                notify: { toast: () => {} }
            };
            function row(text) { return statusConfig.menu.find((r) => r.title && r.title.includes(text) && !r.title.startsWith("Join") && !r.title.startsWith("Dismiss")); }
            """)
        #expect(PluginHarness.run(engine, "statusConfig.title") == "Planning")
        #expect(PluginHarness.run(engine, "row('Standup').dimmed") == "true")
        #expect(PluginHarness.run(engine, "row('Lunch').dimmed") == "true")
        #expect(PluginHarness.run(engine, "row('Planning').dimmed") == "false")
        PluginHarness.run(engine, "statusConfig.menu.find((r) => r.title === 'Dismiss Planning').onClick()")
        PluginHarness.run(engine, "tick()")
        #expect(PluginHarness.run(engine, "statusConfig.title") == "Review")
        #expect(PluginHarness.run(engine, "row('Planning').dimmed") == "true")
        PluginHarness.run(engine, "statusConfig.menu.find((r) => r.title === 'Restore Dismissed Meetings').onClick()")
        PluginHarness.run(engine, "tick()")
        #expect(PluginHarness.run(engine, "statusConfig.title") == "Planning")
        #expect(engine.lastUnhandledRejection == nil)
    }

    @Test("a meeting in progress shows the time left")
    func showsTimeLeft() throws {
        let now = Int(Date().timeIntervalSince1970 * 1000)
        let result = try PluginHarness.evalSettled(plugin: "meetings.js", mock: """
            var store = {};
            var localStorage = {
                getItem: (k) => (k in store ? store[k] : null),
                setItem: (k, v) => { store[k] = String(v); },
                removeItem: (k) => { delete store[k]; }
            };
            var statusConfig = null;
            var macotron = {
                plugin: () => ({ hours: 12, hide: "", time: "relative", overlay: false }),
                system: { locale: () => ({ hour12: true }) },
                calendar: {
                    upcoming: () => Promise.resolve([
                        { id: "s", title: "Standup", start: \(now - 600000), end: \(now + 720000), allDay: false, location: "", calendar: "Work" }
                    ])
                },
                menubar: { status: (id, cfg) => { statusConfig = cfg; } },
                app: { launch: () => {} },
                url: { open: () => {} },
                every: () => {},
                command: () => {},
                notify: { toast: () => {} }
            };
            """, extra: "statusConfig.subtitle")
        #expect(result == "Now · 12m left")
    }
}
