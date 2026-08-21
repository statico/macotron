import Foundation
import Testing
@testable import MacotronEngine

@MainActor
@Suite("LockScreen")
struct LockScreenTests {
    private func eval(_ extra: String) throws -> String {
        let pluginURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Examples/plugins/lock-screen.js")
        let pluginSource = try String(contentsOf: pluginURL, encoding: .utf8)
        let harness = """
            var locked = 0;
            var commands = {};
            var macotron = {
                plugin: () => ({}),
                command: (name, desc, fn) => { commands[name] = fn; },
                power: { lock: () => { locked++; return true; } }
            };
            \(pluginSource)
            \(extra)
            """
        let engine = Engine()
        let (result, error) = engine.evaluate(harness, filename: pluginURL.path)
        #expect(error == nil)
        return result ?? ""
    }

    @Test("lock screen command locks right away")
    func locks() throws {
        let result = try eval(#"""
            commands["Lock Screen"]();
            JSON.stringify({ locked: locked })
            """#)
        #expect(result.contains(#""locked":1"#))
    }
}
