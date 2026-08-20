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
            var confirms = [];
            var confirmResult = true;
            var commands = {};
            var macotron = {
                plugin: () => ({}),
                command: (name, desc, fn) => { commands[name] = fn; },
                power: { lock: () => { locked++; return true; } }
            };
            function confirm(message) {
                confirms.push(message);
                return confirmResult;
            }
            \(demo)
            \(extra)
            """
        let engine = Engine()
        let (result, error) = engine.evaluate(source, filename: demoURL.path)
        #expect(error == nil)
        return result ?? ""
    }

    @Test("lock screen command asks first")
    func confirmsThenLocks() throws {
        let result = try eval(#"""
            commands["Lock Screen"]();
            JSON.stringify({ locked: locked, message: confirms[0] })
            """#)
        #expect(result.contains(#""locked":1"#))
        #expect(result.lowercased().contains("lock"))
    }

    @Test("cancel skips lock")
    func cancel() throws {
        let result = try eval(#"""
            confirmResult = false;
            commands["Lock Screen"]();
            JSON.stringify({ locked: locked, confirms: confirms.length })
            """#)
        #expect(result.contains(#""locked":0"#))
        #expect(result.contains(#""confirms":1"#))
    }
}
