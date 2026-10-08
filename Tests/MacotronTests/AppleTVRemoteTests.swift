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

    /// An in-memory stand-in for the Keychain, which can hang under test.
    private static func memoryStore() -> AppleTVRemote.CredentialStore {
        final class Box: @unchecked Sendable { var items: [String: String] = [:] }
        let box = Box()
        return .init(read: { box.items[$0] }, write: { box.items[$0] = $1 }, delete: { box.items[$0] = nil })
    }

    private let companion = [
        "name": "Living Room",
        "type": "_companion-link._tcp",
        "host": "10.0.0.5",
        "port": 49153,
    ] as [String: Any]

    @Test("send to a TV with no stored pairing reports not paired")
    func notPaired() {
        let devices = AppleTVRemote.merge([living])
        let result = AppleTVRemote.send(id: "10.0.0.5:7000", command: "select", devices: devices,
                                        dryRun: false, store: Self.memoryStore())
        #expect(result["ok"] as? Bool == false)
        #expect(result["error"] as? String == "not paired")
    }

    @Test("send rejects an unknown key before touching the network")
    func unknownKey() {
        let result = AppleTVRemote.send(id: "10.0.0.5:7000", command: "jump", devices: AppleTVRemote.merge([living]),
                                        dryRun: false, store: Self.memoryStore())
        #expect(result["error"] as? String == "Unknown command: jump")
    }

    @Test("an airplay row resolves to the same TV's companion service")
    func target() {
        let target = AppleTVRemote.target(id: "10.0.0.5:7000", devices: AppleTVRemote.merge([living, companion]))
        #expect(target?.name == "Living Room")
        #expect(target?.port == 49153)
        #expect(AppleTVRemote.target(id: "10.0.0.5:7000", devices: AppleTVRemote.merge([living]))?.port == nil)
    }

    @Test("paired and unpair follow the stored pairing, keyed by name")
    func pairedState() {
        let store = Self.memoryStore()
        let devices = AppleTVRemote.merge([living])
        #expect(!AppleTVRemote.paired(id: "10.0.0.5:7000", devices: devices, store: store))
        let creds = CompanionCredentials(deviceKey: Array(repeating: 1, count: 32), clientSecret: Array(repeating: 2, count: 32),
                                         deviceID: [3], clientID: [4])
        store.write("Living Room", creds.string)
        #expect(AppleTVRemote.paired(id: "10.0.0.5:7000", devices: devices, store: store))
        AppleTVRemote.unpair(id: "10.0.0.5:7000", devices: devices, store: store)
        #expect(!AppleTVRemote.paired(id: "10.0.0.5:7000", devices: devices, store: store))
    }

    @Test("a PIN without a started pairing, or a bad PIN, fails cleanly")
    func pairErrors() {
        let devices = AppleTVRemote.merge([living, companion])
        let store = Self.memoryStore()
        #expect(AppleTVRemote.pair(id: "10.0.0.5:7000", pin: "12a4", devices: devices, store: store)["error"] as? String
            == "The PIN is the 4 numbers on the TV")
        #expect(AppleTVRemote.pair(id: "10.0.0.5:7000", pin: "1234", devices: devices, store: store)["error"] as? String
            == "Call pair(id) first so the TV shows a PIN")
        #expect(AppleTVRemote.pair(id: "10.0.0.5:7000", pin: nil, devices: AppleTVRemote.merge([living]), store: store)["error"]
            as? String == "No Companion service")
    }

    @Test("PINs pad to four digits")
    func pins() {
        #expect(AppleTVRemote.normalizePIN(" 42 ") == "0042")
        #expect(AppleTVRemote.normalizePIN("1234") == "1234")
        #expect(AppleTVRemote.normalizePIN("12345") == nil)
        #expect(AppleTVRemote.normalizePIN("") == nil)
        #expect(AppleTVRemote.normalizePIN("١٢") == nil)
    }

    @Test("keys map to pyatv's HID codes and media commands")
    func keys() {
        #expect(AppleTVRemote.Key("select") == .hid(6))
        #expect(AppleTVRemote.Key("playpause") == .hid(14))
        #expect(AppleTVRemote.Key("pause") == .media(2))
        #expect(AppleTVRemote.Key("jump") == nil)
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
    /// Discovery answers with a promise, and a promise only settles when the
    /// engine drains its job queue at the end of an evaluate. So every step the
    /// plugin has to react to before the next one gets its own evaluate.
    @MainActor
    private final class Harness {
        let engine = Engine()

        init(tvs: String) throws {
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
                var macotron = {
                    plugin: () => ({}),
                    command: (name, desc, fn) => { commands[name] = fn; },
                    panel: {
                        open: (opts) => { panel = opts; return "p1"; },
                        onMessage: (id, fn) => { onMessage = fn; },
                        postMessage: (id, data) => { posted.push(data); }
                    },
                    appletv: {
                        list: () => { listCalls++; return Promise.resolve(\(tvs)); },
                        send: (id, key) => {
                            sent.push({ id: id, key: key });
                            return Promise.resolve({ ok: false, error: "not paired" });
                        }
                    },
                    menubar: { status: () => {} },
                    notify: { toast: (title, body) => { toasts.push(body); } }
                };
                \(pluginSource)
                """
            let (_, error) = engine.evaluate(harness, filename: pluginURL.path)
            if let error { throw HarnessError.evaluation(error) }
        }

        @discardableResult
        func run(_ js: String) throws -> String {
            let (result, error) = engine.evaluate(js)
            if let error { throw HarnessError.evaluation(error) }
            return result ?? ""
        }
    }

    private enum HarnessError: Error {
        case evaluation(String)
    }

    /// The window has to be up before discovery starts, otherwise the remote is
    /// blank for a second after the click that opened it. The page asks for the
    /// list when its script runs, so a slow load cannot miss the answer.
    @Test("the panel opens before discovery runs")
    func opensBeforeDiscovery() throws {
        let harness = try Harness(tvs: "[]")
        try harness.run(#"commands["Apple TV Remote"]();"#)
        let result = try harness.run(#"""
            JSON.stringify({
                listCalls: listCalls, posted: posted.length,
                html: panel.html, glass: panel.glass, width: panel.width, height: panel.height
            })
            """#)
        #expect(result.contains(#""listCalls":0"#))
        #expect(result.contains(#""posted":0"#))
        #expect(result.contains("Looking for Apple TVs"))
        #expect(result.contains(#""glass":true"#))
        #expect(result.contains(#""width":280"#))
        #expect(result.contains(#""height":480"#))
    }

    @Test("an empty result posts no devices, and the page says so")
    func emptyList() throws {
        let harness = try Harness(tvs: "[]")
        try harness.run(#"commands["Apple TV Remote"]();"#)
        try harness.run(#"onMessage({ type: "ready" });"#)
        let result = try harness.run(
            "JSON.stringify({ listCalls: listCalls, posted: posted, html: panel.html })"
        )
        #expect(result.contains(#""listCalls":1"#))
        #expect(result.contains(#""tvs":[]"#))
        #expect(result.contains("No Apple TV found. The tvOS Simulator cannot be controlled."))
    }

    private static let livingRoom = #"""
        [{ id: "10.0.0.5:7000", name: "Living Room", host: "10.0.0.5", port: 7000, type: "_airplay._tcp" }]
        """#

    @Test("clicking a key sends it to the listed Apple TV")
    func clickSendsKey() throws {
        let harness = try Harness(tvs: Self.livingRoom)
        try harness.run(#"commands["Apple TV Remote"]();"#)
        try harness.run(#"onMessage({ type: "ready" });"#)
        try harness.run(#"onMessage({ type: "key", key: "up" });"#)
        let result = try harness.run(
            "JSON.stringify({ sent: sent, posted: posted, html: panel.html })"
        )
        #expect(result.contains(#""id":"10.0.0.5:7000"#))
        #expect(result.contains(#""key":"up"#))
        #expect(result.contains("Living Room"))
        #expect(result.contains("data-key"))
    }

    /// A browse runs for its whole timeout, so one per key press would leave the
    /// remote unresponsive between presses.
    @Test("key presses do not re-run discovery")
    func keysDoNotRediscover() throws {
        let harness = try Harness(tvs: Self.livingRoom)
        try harness.run(#"commands["Apple TV Remote"]();"#)
        try harness.run(#"onMessage({ type: "ready" });"#)
        try harness.run(#"for (var i = 0; i < 8; i++) onMessage({ type: "key", key: "up" });"#)
        let result = try harness.run(
            "JSON.stringify({ listCalls: listCalls, sent: sent.length, toasts: toasts })"
        )
        #expect(result.contains(#""listCalls":1"#))
        #expect(result.contains(#""sent":8"#))
        // The failure is reported once, not once per press.
        #expect(result.contains(#"["not paired"]"#))
    }
}
