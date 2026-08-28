import Foundation
import Testing
@testable import MacotronEngine

@MainActor
@Suite("ScreenEffects")
struct ScreenEffectsTests {
    private static let mock = #"""
            var store = {};
            var localStorage = {
                getItem: (k) => (k in store ? store[k] : null),
                setItem: (k, v) => { store[k] = String(v); },
                removeItem: (k) => { delete store[k]; }
            };
            var calls = [];
            var commands = {};
            var toasts = [];
            var crtOn = false;
            var crtAvailable = true;
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
                    setGrayscale: (v) => ({ available: true, ok: true, on: v }),
                    isCRTEnabled: () => crtOn,
                    setCRTEnabled: (v) => { crtOn = v; calls.push({ op: "crt", on: v }); return crtAvailable; }
                },
                command: (name, desc, fn) => { commands[name] = fn; },
                notify: { toast: (title, body) => { toasts.push({ title: title, body: body }); } }
            };
        """#

    private func eval(_ extra: String) throws -> String {
        try PluginHarness.eval(plugin: "screen-effects.js", mock: Self.mock, extra: extra)
    }

    @Test(
        "toggling a gamma mode off restores ColorSync",
        arguments: ["Toggle Night Vision", "Toggle Extra Dark"])
    func gammaToggleRestores(command: String) throws {
        let result = try eval(#"""
            commands[\#(String(reflecting: command))]();
            commands[\#(String(reflecting: command))]();
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

    @Test("switching from night vision to extra dark to night vision applies red")
    func gammaModesAreMutuallyExclusive() throws {
        let result = try eval(#"""
            commands["Toggle Night Vision"]();
            commands["Toggle Extra Dark"]();
            commands["Toggle Night Vision"]();
            var last = calls[calls.length - 1];
            JSON.stringify({ op: last.op, red: last.white && last.white.red, green: last.white && last.white.green })
            """#)
        #expect(result.contains(#""op":"set""#))
        #expect(result.contains(#""red":1"#))
        #expect(result.contains(#""green":0"#))
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
        #expect(result.contains("Toggle CRT Effect"))
    }

    @Test("CRT toggles on then off")
    func crtToggles() throws {
        let result = try eval(#"""
            commands["Toggle CRT Effect"]();
            commands["Toggle CRT Effect"]();
            JSON.stringify({ calls: calls, toasts: toasts.map(t => t.body) })
            """#)
        #expect(result.contains(#"{"op":"crt","on":true}"#))
        #expect(result.contains(#"{"op":"crt","on":false}"#))
        #expect(result.contains(#"["On","Off"]"#))
    }

    @Test("a Mac without Metal reports the effect unavailable")
    func crtUnavailable() throws {
        let result = try eval(#"""
            crtAvailable = false;
            commands["Toggle CRT Effect"]();
            JSON.stringify(toasts)
            """#)
        #expect(result.contains("Unavailable"))
    }
}
