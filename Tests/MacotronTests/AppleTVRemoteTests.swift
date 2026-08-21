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
            var macotron = {
                plugin: () => ({}),
                command: (name, desc, fn) => { commands[name] = fn; },
                panel: {
                    open: (opts) => { panel = opts; return "p1"; },
                    onMessage: (id, fn) => { onMessage = fn; }
                },
                appletv: {
                    list: () => (\(tvs)),
                    send: (id, key) => { sent.push({ id: id, key: key }); return { ok: false, error: "not paired" }; }
                },
                menubar: { status: () => {} }
            };
            \(pluginSource)
            \(extra)
            """
        let engine = Engine()
        let (result, error) = engine.evaluate(harness, filename: pluginURL.path)
        #expect(error == nil)
        return result ?? ""
    }

    @Test("empty list tells the user the simulator cannot be controlled")
    func emptyList() throws {
        let result = try eval(#"""
            commands["Apple TV Remote"]();
            JSON.stringify({ html: panel.html, glass: panel.glass, width: panel.width, height: panel.height })
            """#, tvs: "[]")
        #expect(result.contains("No Apple TV found. The tvOS Simulator cannot be controlled."))
        #expect(result.contains(#""glass":true"#))
        #expect(result.contains(#""width":280"#))
        #expect(result.contains(#""height":480"#))
    }

    @Test("clicking a key sends it to the listed Apple TV")
    func clickSendsKey() throws {
        let tvs = #"""
            [{ id: "10.0.0.5:7000", name: "Living Room", host: "10.0.0.5", port: 7000, type: "_airplay._tcp" }]
            """#
        let result = try eval(#"""
            commands["Apple TV Remote"]();
            onMessage({ type: "key", key: "up" });
            JSON.stringify({ sent: sent, html: panel.html })
            """#, tvs: tvs)
        #expect(result.contains(#""id":"10.0.0.5:7000"#))
        #expect(result.contains(#""key":"up"#))
        #expect(result.contains("data-key"))
    }
}
