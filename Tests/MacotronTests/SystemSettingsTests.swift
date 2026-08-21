import Foundation
import Testing
@testable import MacotronEngine

@MainActor
@Suite("SystemSettings")
struct SystemSettingsTests {
    private func eval(_ extra: String) throws -> String {
        let pluginURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Examples/plugins/system-settings.js")
        let pluginSource = try String(contentsOf: pluginURL, encoding: .utf8)
        let harness = """
            var provider = "";
            var items = [];
            var opened = [];
            var macotron = {
                plugin: () => ({}),
                launcher: { set: (id, rows) => { provider = id; items = rows; } },
                url: { open: (u) => { opened.push(u); } }
            };
            \(pluginSource)
            \(extra)
            """
        let engine = Engine()
        let (result, error) = engine.evaluate(harness, filename: pluginURL.path)
        #expect(error == nil)
        return result ?? ""
    }

    @Test("registers searchable System Settings panes")
    func registersPanes() throws {
        let result = try eval(#"""
            JSON.stringify({
                provider: provider,
                count: items.length,
                titles: items.map(i => i.title),
                kind: items[0] && items[0].kind,
                app: items[0] && items[0].app
            })
            """#)
        #expect(result.contains(#""provider":"system-settings""#))
        #expect(result.contains(#""kind":"Settings""#))
        #expect(result.contains(#""app":"com.apple.systempreferences""#))
        for title in ["Wi-Fi", "Bluetooth", "Accessibility", "Privacy & Security", "Software Update", "Login Items", "Storage", "AirDrop"] {
            #expect(result.contains("\"\(title)\""), "missing \(title)")
        }
        let count = try #require(result.split(separator: "\"count\":").last?.split(separator: ",").first)
        #expect((Int(count) ?? 0) >= 40)
    }

    @Test("opening a pane uses the System Settings URL")
    func opensPane() throws {
        let result = try eval(#"""
            items.find(i => i.title === "Wi-Fi").onClick();
            items.find(i => i.title === "Location Services").onClick();
            JSON.stringify(opened)
            """#)
        #expect(result.contains("x-apple.systempreferences:com.apple.wifi-settings-extension"))
        #expect(result.contains("Privacy_LocationServices"))
    }

    @Test("aliases sit in the subtitle so launcher search can hit them")
    func aliases() throws {
        let result = try eval(#"""
            JSON.stringify(items.find(i => i.title === "Login Items").subtitle)
            """#)
        #expect(result.lowercased().contains("startup"))
    }
}
