import Foundation
import Testing
@testable import MacotronEngine

@MainActor
@Suite("ScreenEffects")
struct ScreenEffectsTests {
    private func pluginURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Examples/plugins/screen-effects.js")
    }

    private func eval(_ extra: String) throws -> String {
        let demoURL = pluginURL()
        let demo = try String(contentsOf: demoURL, encoding: .utf8)
        let source = """
            var calls = [];
            var commands = {};
            var macotron = {
                plugin: () => ({}),
                display: {
                    setGamma: (white, black) => { calls.push({ op: "set", white: white, black: black }); },
                    restoreGamma: () => { calls.push({ op: "restore" }); },
                    nightShift: () => ({ available: true, on: false }),
                    setNightShift: (v) => ({ available: true, ok: true, on: typeof v === "boolean" ? v : true }),
                    trueTone: () => ({ available: true, on: false }),
                    setTrueTone: (v) => ({ available: true, ok: true, on: v }),
                    grayscale: () => ({ available: true, on: false }),
                    setGrayscale: (v) => ({ available: true, ok: true, on: v })
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

    @Test("night vision tints red then restores")
    func nightVision() throws {
        let result = try eval(#"""
            commands["Toggle Night Vision"]();
            commands["Toggle Night Vision"]();
            JSON.stringify(calls.map(c => c.op))
            """#)
        #expect(result.contains(#""set""#))
        #expect(result.contains(#""restore""#))
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

    @Test("registers all display mode commands")
    func displayModeCommands() throws {
        let result = try eval(#"""
            JSON.stringify(Object.keys(commands).sort())
            """#)
        #expect(result.contains("Toggle Night Shift"))
        #expect(result.contains("Night Shift 60%"))
        #expect(result.contains("Toggle True Tone"))
        #expect(result.contains("Toggle Grayscale"))
    }
}
