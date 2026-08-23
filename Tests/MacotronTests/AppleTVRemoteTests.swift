import Foundation
import Testing
@testable import MacotronEngine
@testable import Modules

@Suite("AppleTVRemote")
struct AppleTVRemoteTests {
    private let living = [
        "name": "Living Room",
        "type": "_airplay._tcp",
        "host": "10.0.0.5",
        "port": 7000,
    ] as [String: Any]

    @Test("ids devices as host:port and drops duplicates")
    func merge() {
        let extra = [
            "name": "Living Room",
            "type": "_companion-link._tcp",
            "host": "10.0.0.5",
            "port": 7000,
        ] as [String: Any]
        let bedroom = [
            "name": "Bedroom",
            "type": "_airplay._tcp",
            "host": "10.0.0.8",
            "port": 7000,
        ] as [String: Any]
        let devices = AppleTVRemote.merge([living, extra, bedroom])
        #expect(devices.count == 2)
        #expect(devices[0]["id"] as? String == "10.0.0.5:7000")
        #expect(devices[0]["name"] as? String == "Living Room")
        #expect(devices[1]["id"] as? String == "10.0.0.8:7000")
    }

    @Test("send without a matching device reports No Apple TV")
    func missing() {
        let result = AppleTVRemote.send(id: "none", command: "up", devices: AppleTVRemote.merge([living]), dryRun: false)
        #expect(result["ok"] as? Bool == false)
        #expect(result["error"] as? String == "No Apple TV")
    }

    @Test("send to a found device does not pair")
    func notPaired() {
        let devices = AppleTVRemote.merge([living])
        let result = AppleTVRemote.send(id: "10.0.0.5:7000", command: "select", devices: devices, dryRun: false)
        #expect(result["ok"] as? Bool == false)
        #expect(result["error"] as? String == "not paired")
    }

    @Test("dry-run send is ok")
    func dryRun() {
        let result = AppleTVRemote.send(id: "none", command: "up", devices: [], dryRun: true)
        #expect(result["ok"] as? Bool == true)
    }
}

@MainActor
@Suite("Apple TV plugin")
struct AppleTVPluginTests {
    private func eval(_ extra: String, tvs: String) throws -> String {
        let pluginURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Examples/plugins/apple-tv.js")
        let pluginSource = try String(contentsOf: pluginURL, encoding: .utf8)
        let harness = """
            var commands = {};
            var sent = [];
            var panel = {};
            var onMessage = null;
            var toasts = [];
            var listCalls = 0;
            var posted = [];
            // The plugin defers discovery so the window can draw first. Hold the
            // callbacks so a test can run them when it wants to.
            var timers = [];
            globalThis.setTimeout = (fn) => { timers.push(fn); return timers.length; };
            function runTimers() { var due = timers; timers = []; due.forEach((fn) => fn()); }
            var macotron = {
                plugin: () => ({}),
                command: (name, desc, fn) => { commands[name] = fn; },
                panel: {
                    open: (opts) => { panel = opts; return "p1"; },
                    onMessage: (id, fn) => { onMessage = fn; },
                    postMessage: (id, data) => { posted.push(data); }
                },
                appletv: {
                    list: () => { listCalls++; return (\(tvs)); },
                    send: (id, key) => { sent.push({ id: id, key: key }); return { ok: false, error: "not paired" }; }
                },
                menubar: { status: () => {} },
                notify: { toast: (title, body) => { toasts.push(body); } }
            };
            \(pluginSource)
            \(extra)
            """
        let engine = Engine()
        let (result, error) = engine.evaluate(harness, filename: pluginURL.path)
        #expect(error == nil)
        return result ?? ""
    }

    /// The window has to be up before discovery runs, otherwise the 1.5s browse
    /// blocks the main thread inside the click that opened it.
    @Test("the panel opens before discovery runs")
    func opensBeforeDiscovery() throws {
        let result = try eval(#"""
            commands["Apple TV Remote"]();
            JSON.stringify({
                listCalls: listCalls, posted: posted.length,
                html: panel.html, glass: panel.glass, width: panel.width, height: panel.height
            })
            """#, tvs: "[]")
        #expect(result.contains(#""listCalls":0"#))
        #expect(result.contains(#""posted":0"#))
        #expect(result.contains("Looking for Apple TVs"))
        #expect(result.contains(#""glass":true"#))
        #expect(result.contains(#""width":280"#))
        #expect(result.contains(#""height":480"#))
    }

    @Test("an empty result posts no devices, and the page says so")
    func emptyList() throws {
        let result = try eval(#"""
            commands["Apple TV Remote"]();
            runTimers();
            JSON.stringify({ listCalls: listCalls, posted: posted, html: panel.html })
            """#, tvs: "[]")
        #expect(result.contains(#""listCalls":1"#))
        #expect(result.contains(#""tvs":[]"#))
        #expect(result.contains("No Apple TV found. The tvOS Simulator cannot be controlled."))
    }

    @Test("clicking a key sends it to the listed Apple TV")
    func clickSendsKey() throws {
        let tvs = #"""
            [{ id: "10.0.0.5:7000", name: "Living Room", host: "10.0.0.5", port: 7000, type: "_airplay._tcp" }]
            """#
        let result = try eval(#"""
            commands["Apple TV Remote"]();
            runTimers();
            onMessage({ type: "key", key: "up" });
            JSON.stringify({ sent: sent, posted: posted, html: panel.html })
            """#, tvs: tvs)
        #expect(result.contains(#""id":"10.0.0.5:7000"#))
        #expect(result.contains(#""key":"up"#))
        #expect(result.contains("Living Room"))
        #expect(result.contains("data-key"))
    }

    /// Discovery parks the main thread in a nested run loop for its whole
    /// timeout. One browse per key press is what made the remote beachball.
    @Test("key presses do not re-run discovery")
    func keysDoNotRediscover() throws {
        let tvs = #"""
            [{ id: "10.0.0.5:7000", name: "Living Room", host: "10.0.0.5", port: 7000, type: "_airplay._tcp" }]
            """#
        let result = try eval(#"""
            commands["Apple TV Remote"]();
            runTimers();
            for (var i = 0; i < 8; i++) onMessage({ type: "key", key: "up" });
            JSON.stringify({ listCalls: listCalls, sent: sent.length, toasts: toasts })
            """#, tvs: tvs)
        #expect(result.contains(#""listCalls":1"#))
        #expect(result.contains(#""sent":8"#))
        // The failure is reported once, not once per press.
        #expect(result.contains(#"["not paired"]"#))
    }
}
