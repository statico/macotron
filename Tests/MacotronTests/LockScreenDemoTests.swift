import Foundation
import Testing
@testable import MacotronEngine

@MainActor
@Suite("LockScreenDemo")
struct LockScreenDemoTests {
    private func eval(_ extra: String) throws -> String {
        let demoURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Examples/plugins/demo-lock-screen.js")
        let demo = try String(contentsOf: demoURL, encoding: .utf8)
        let source = """
            var locked = 0;
            var commands = {};
            var macotron = {
                plugin: () => ({}),
                command: (name, desc, fn) => { commands[name] = fn; },
                power: { lock: () => { locked++; return true; } }
            };
            \(demo)
            \(extra)
            """
        let engine = Engine()
        let (result, error) = engine.evaluate(source, filename: demoURL.path)
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
