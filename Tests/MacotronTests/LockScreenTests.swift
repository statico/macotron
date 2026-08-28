import Foundation
import Testing
@testable import MacotronEngine

@MainActor
@Suite("LockScreen")
struct LockScreenTests {
    private static let mock = #"""
        var locked = 0;
        var commands = {};
        var macotron = {
            plugin: () => ({}),
            command: (name, desc, fn) => { commands[name] = fn; },
            power: { lock: () => { locked++; return true; } }
        };
        """#

    private func eval(_ extra: String) throws -> String {
        try PluginHarness.eval(plugin: "lock-screen.js", mock: Self.mock, extra: extra)
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
