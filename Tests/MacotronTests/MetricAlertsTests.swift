import Foundation
import Testing
@testable import MacotronEngine

/// The two pieces of these plugins that are worth testing are the ones with no
/// screen attached: when a threshold breach becomes a notification, and what a
/// developer's appcast says the newest version is.
@MainActor
@Suite("Metric alerts")
struct MetricAlertsTests {
    /// system-metrics paints on load, so the mock has to answer every sampled
    /// subsystem. The numbers are quiet ones: these tests drive `alertStep`
    /// directly rather than through the two-second timer.
    static let metricsMock = #"""
        var notes = [];
        var stored = {};
        var localStorage = {
            getItem: (key) => (key in stored ? stored[key] : null),
            setItem: (key, value) => { stored[key] = String(value); }
        };
        var macotron = {
            plugin: (cfg) => ({}),
            system: {
                cpu: () => ({ usage: 5 }),
                gpu: () => ({ usage: 2, name: "Test GPU" }),
                memory: () => ({ used: 8e9, total: 16e9 }),
                battery: () => ({ level: 90, charging: true, timeToFull: 10, timeRemaining: 0 }),
                disk: () => ({ used: 1e11, total: 5e11 })
            },
            menubar: { status: () => {}, add: () => {} },
            settings: { open: () => {} },
            every: () => {},
            command: () => {},
            notify: {
                toast: () => {},
                show: (title, body) => { notes.push(title); }
            }
        };
        """#

    /// Feeds a run of samples through `alertStep`, threading the state the way
    /// the plugin does, and reports which samples notified.
    static let driver = #"""
        function drive(seq, needed, start, step) {
            var state = {};
            var out = [];
            var t = start;
            for (var i = 0; i < seq.length; i++) {
                state = alertStep(state, seq[i], t, needed);
                out.push(state.notify);
                t += step;
            }
            return out;
        }
        """#

    @Test("a brief CPU spike stays quiet, a sustained one alerts")
    func spikeVersusSustained() throws {
        let engine = try PluginHarness.load(
            plugin: "system-metrics.js", mock: Self.metricsMock, extra: Self.driver)

        // Two samples over the line is four seconds of CPU: not news when the
        // user asked for three consecutive samples.
        let spike = PluginHarness.run(engine, "JSON.stringify(drive([true, true, false, true], 3, 0, 2000))")
        #expect(spike == "[false,false,false,false]")

        // The third consecutive sample is the one that earns a notification.
        let sustained = PluginHarness.run(engine, "JSON.stringify(drive([true, true, true], 3, 0, 2000))")
        #expect(sustained == "[false,false,true]")
    }

    @Test("a latched alert does not re-fire every tick")
    func latchHolds() throws {
        let engine = try PluginHarness.load(
            plugin: "system-metrics.js", mock: Self.metricsMock, extra: Self.driver)
        // Six breaching samples in a row are one problem, not four.
        let result = PluginHarness.run(engine, "JSON.stringify(drive([true, true, true, true, true, true], 3, 0, 2000))")
        #expect(result == "[false,false,true,false,false,false]")
    }

    @Test("the alert fires again once it has cleared")
    func refiresAfterClearing() throws {
        let engine = try PluginHarness.load(
            plugin: "system-metrics.js", mock: Self.metricsMock, extra: Self.driver)
        let result = PluginHarness.run(engine, #"""
            var state = {};
            [true, true, true].forEach((b) => { state = alertStep(state, b, 0, 3); });
            var first = state.notify;
            state = alertStep(state, false, 2000, 3);
            var cleared = state.latched;
            // Recovery re-arms the alert, but the cooldown still has to pass
            // before the same condition is allowed to speak up again.
            var later = 31 * 60 * 1000;
            var second = false;
            [true, true, true].forEach((b) => {
                state = alertStep(state, b, later, 3);
                second = second || state.notify;
            });
            JSON.stringify({ first: first, cleared: cleared, second: second });
            """#)
        #expect(result == #"{"first":true,"cleared":false,"second":true}"#)
    }

    @Test("a re-breach inside the cooldown stays quiet")
    func cooldownSuppresses() throws {
        let engine = try PluginHarness.load(
            plugin: "system-metrics.js", mock: Self.metricsMock, extra: Self.driver)
        let result = PluginHarness.run(engine, #"""
            var state = {};
            [true, true, true].forEach((b) => { state = alertStep(state, b, 0, 3); });
            state = alertStep(state, false, 2000, 3);
            var second = false;
            [true, true, true].forEach((b) => {
                state = alertStep(state, b, 60000, 3);
                second = second || state.notify;
            });
            String(second);
            """#)
        #expect(result == "false")
    }

    static let securityMock = #"""
        var macotron = {
            plugin: () => ({}),
            command: () => {},
            shell: { run: () => Promise.resolve({ stdout: "", stderr: "", exitCode: 1 }) },
            http: { get: () => Promise.resolve({ status: 0, body: "", headers: {} }) },
            app: { list: () => [] },
            fs: { read: () => "", exists: () => false },
            notify: { toast: () => {}, show: () => {} },
            panel: { open: () => 1, postMessage: () => {}, onMessage: () => {}, close: () => {} }
        };
        """#

    @Test("the newest appcast item decides the version")
    func appcastVersion() throws {
        let engine = try PluginHarness.load(plugin: "security-checklist.js", mock: Self.securityMock)

        // Sparkle's own field wins when the feed publishes one.
        let tagged = PluginHarness.run(engine, #"""
            newestAppcastVersion(`<rss><channel>
              <item><title>Fancy 2.1.0</title><sparkle:shortVersionString>2.1.0</sparkle:shortVersionString></item>
              <item><title>Fancy 2.0.0</title><sparkle:shortVersionString>2.0.0</sparkle:shortVersionString></item>
            </channel></rss>`)
            """#)
        #expect(tagged == "2.1.0")

        // Plenty of feeds only carry it as an attribute on the enclosure.
        let attribute = PluginHarness.run(engine, #"""
            newestAppcastVersion(`<rss><channel><item><title>Update</title>
              <enclosure url="https://example.com/a.zip" sparkle:shortVersionString="3.4.1"/>
            </item></channel></rss>`)
            """#)
        #expect(attribute == "3.4.1")

        // Falling back to the title is the common case for older feeds.
        let title = PluginHarness.run(engine, #"""
            newestAppcastVersion("<rss><channel><item><title>Version 3.4</title></item></channel></rss>")
            """#)
        #expect(title == "3.4")

        // A feed that never arrived must not read as "up to date".
        let empty = PluginHarness.run(engine, "String(newestAppcastVersion(\"<rss><channel></channel></rss>\"))")
        #expect(empty == "null")
    }

    @Test("versions compare by number, not by string")
    func versionOrdering() throws {
        let engine = try PluginHarness.load(plugin: "security-checklist.js", mock: Self.securityMock)
        // The one that matters: "1.10" sorts before "1.9" as text, and an app
        // told it is out of date when it is not is worse than silence.
        #expect(PluginHarness.run(engine, "String(compareVersions('1.10.0', '1.9.0'))") == "1")
        #expect(PluginHarness.run(engine, "String(compareVersions('2.0', '2.0.0'))") == "0")
        #expect(PluginHarness.run(engine, "String(compareVersions('1.2.3', '1.2.4'))") == "-1")
        // Build suffixes are common in Info.plist and must not throw.
        #expect(PluginHarness.run(engine, "String(compareVersions('1.2.3b4', '1.2.3'))") == "0")
    }
}
