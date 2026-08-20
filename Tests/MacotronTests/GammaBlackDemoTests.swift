import Foundation
import Testing
@testable import MacotronEngine

@MainActor
@Suite("GammaBlackDemo")
struct GammaBlackDemoTests {
    private func eval(_ extra: String) throws -> String {
        let demoURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Examples/plugins/demo-gamma-black.js")
        let demo = try String(contentsOf: demoURL, encoding: .utf8)
        let source = """
            var calls = [];
            var commands = {};
            var macotron = {
                plugin: () => ({}),
                display: {
                    setGamma: (white, black) => { calls.push({ op: "set", white: white, black: black }); },
                    restoreGamma: () => { calls.push({ op: "restore" }); }
                },
                command: (name, desc, fn) => { commands[name] = fn; },
                notify: { toast: () => {} }
            };
            \(demo)
            \(extra)
            """
        let engine = Engine()
        let (result, error) = engine.evaluate(source, filename: demoURL.path)
        #expect(error == nil)
        return result ?? ""
    }

    @Test("extra dark lowers the white point and keeps black at zero")
    func extraDark() throws {
        let result = try eval(#"""
            commands["Toggle Extra Dark"]();
            JSON.stringify({ white: calls[0].white.red, black: calls[0].black.red })
            """#)
        #expect(result.contains(#""white":0.35"#))
        #expect(result.contains(#""black":0"#))
    }

    @Test("invert swaps the gamma white and black points")
    func invert() throws {
        let result = try eval(#"""
            commands["Toggle Invert Display"]();
            JSON.stringify({ white: calls[0].white.red, black: calls[0].black.red })
            """#)
        #expect(result.contains(#""white":0"#))
        #expect(result.contains(#""black":1"#))
    }

    @Test("toggling extra dark again restores ColorSync")
    func restore() throws {
        let result = try eval(#"""
            commands["Toggle Extra Dark"]();
            commands["Toggle Extra Dark"]();
            JSON.stringify(calls.map(c => c.op))
            """#)
        #expect(result.contains(#""set""#))
        #expect(result.contains(#""restore""#))
    }
}
