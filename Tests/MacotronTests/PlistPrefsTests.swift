import Foundation
import Testing
@testable import MacotronEngine
@testable import Modules

@MainActor
@Suite("plist and prefs")
struct PlistPrefsTests {
    @Test("dates become epoch ms and data becomes base64, nested too")
    func conversion() throws {
        let value = PlistValue.toJS([
            "when": Date(timeIntervalSince1970: 1.5),
            "list": [Data([1, 2, 3]), "x", 4] as [Any],
            "inner": ["flag": true] as [String: Any],
        ] as [String: Any]) as? [String: Any]
        #expect(value?["when"] as? Double == 1500)
        let list = try #require(value?["list"] as? [Any])
        #expect(list[0] as? String == "AQID")
        #expect(list[1] as? String == "x")
        #expect((value?["inner"] as? [String: Any])?["flag"] as? Bool == true)
    }

    @Test("read parses a binary plist and its nested Data parses again from base64")
    func readBinary() throws {
        let inner = try PropertyListSerialization.data(
            fromPropertyList: ["connectionDetails": ["a": ["address": "host.local"]]],
            format: .binary, options: 0)
        let outer = try PropertyListSerialization.data(
            fromPropertyList: ["connectionsStore": inner, "count": 2], format: .binary, options: 0)
        let path = NSTemporaryDirectory() + "macotron-plist-\(UUID().uuidString).plist"
        try outer.write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let engine = Engine()
        engine.addModule(PlistModule())
        engine.registerAllModules()
        let (result, error) = engine.evaluate("""
            const p = macotron.plist.read('\(path)');
            const store = macotron.plist.parse({ base64: p.connectionsStore });
            [p.count, store.connectionDetails.a.address,
             macotron.plist.read('/nonexistent/x.plist'),
             macotron.plist.parse('{ a = 1; }').a,
             macotron.plist.parse('{ a = ')].join('|')
            """)
        #expect(error == nil)
        #expect(result == "2|host.local||1|")
    }

    @Test("-g and NSGlobalDomain mean the global domain")
    func domainMapping() {
        #expect(Prefs.domain("-g") as String == kCFPreferencesAnyApplication as String)
        #expect(Prefs.domain("NSGlobalDomain") as String == kCFPreferencesAnyApplication as String)
        #expect(Prefs.domain("com.apple.finder") as String == "com.apple.finder")
    }

    @Test("set, get, and delete round-trip in a scratch domain")
    func roundTrip() {
        let domain = "io.statico.macotron.test-\(UUID().uuidString)"
        defer {
            _ = Prefs.set(domain, "b", nil)
            let file = FileManager.default.homeDirectoryForCurrentUser.path + "/Library/Preferences/\(domain).plist"
            try? FileManager.default.removeItem(atPath: file)
        }
        #expect(Prefs.set(domain, "n", 1.25))
        #expect(Prefs.set(domain, "b", false))
        #expect(Prefs.get(domain, "n") as? Double == 1.25)
        #expect(Prefs.get(domain, "b") as? Bool == false)
        #expect((Prefs.get(domain, nil) as? [String: Any])?.count == 2)
        #expect(Prefs.set(domain, "n", nil))
        #expect(Prefs.get(domain, "n") == nil)
        // A null inside an array is not a property list.
        #expect(!Prefs.set(domain, "bad", [NSNull()]))
    }
}

@MainActor
@Suite("app.info")
struct AppInfoTests {
    @Test("reads a bundle's id and version; a non-bundle is nil")
    func info() {
        let info = AppModule.info("/System/Applications/Calculator.app")
        #expect(info?["bundleID"] as? String == "com.apple.calculator")
        #expect(info?["version"] is String)
        #expect(AppModule.info("/tmp") == nil)
    }
}
