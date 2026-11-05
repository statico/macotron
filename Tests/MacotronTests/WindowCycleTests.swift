import Foundation
import Testing
@testable import MacotronEngine

/// Presses windows.js hotkeys against a mock focused window and reads back the
/// fractions it handed to `moveToFraction`.
@MainActor
@Suite("Window cycle")
struct WindowCycleTests {
    /// One 1000×800 display. `moveToFraction` lands the window exactly on its
    /// tile, like a well-behaved app.
    static let mock = #"""
        var __keys = {}, __moves = [];
        var __win = { id: 1, number: 100, display: 1, frame: { x: 200, y: 200, width: 300, height: 300 } };
        var macotron = {
            plugin: () => ({}),
            keyboard: { on: (name, combo, cb) => { __keys[name] = cb; } },
            window: {
                snap: () => {},
                focused: () => JSON.parse(JSON.stringify(__win)),
                moveToFraction: (id, f) => {
                    __moves.push(id + ":" + [f.x, f.y, f.w, f.h].join(","));
                    __win.frame = { x: f.x * 1000, y: f.y * 800, width: f.w * 1000, height: f.h * 800 };
                    return true;
                },
            },
            command: () => {},
            notify: { toast: () => {} },
            display: { list: () => [{ id: 1 }] },
            panel: { open: () => 1, onMessage: () => {}, close: () => {} }
        };
        """#

    static func press(_ engine: Engine, _ key: String) -> String {
        PluginHarness.run(engine, "__keys[\(js(key))](); __moves[__moves.length - 1]")
    }

    @Test("a second press moves to the next tile")
    func repeatAdvances() throws {
        let e = try PluginHarness.load(plugin: "windows.js", mock: Self.mock)
        #expect(Self.press(e, "Left Half") == "1:0,0,0.5,1")
        #expect(Self.press(e, "Left Half") == "1:0.5,0,0.5,1")
    }

    @Test("a window moved by hand starts the cycle over")
    func movedByHand() throws {
        let e = try PluginHarness.load(plugin: "windows.js", mock: Self.mock)
        #expect(Self.press(e, "Left Half") == "1:0,0,0.5,1")
        _ = PluginHarness.run(e, "__win.frame.x += 40")
        #expect(Self.press(e, "Left Half") == "1:0,0,0.5,1")
    }

    @Test("the same window under a new id keeps cycling")
    func newIDSameNumber() throws {
        let e = try PluginHarness.load(plugin: "windows.js", mock: Self.mock)
        #expect(Self.press(e, "Left Half") == "1:0,0,0.5,1")
        _ = PluginHarness.run(e, "__win.id = 2")
        #expect(Self.press(e, "Left Half") == "2:0.5,0,0.5,1")
    }

    @Test("another window that inherited the id starts over")
    func sameIDNewNumber() throws {
        let e = try PluginHarness.load(plugin: "windows.js", mock: Self.mock)
        #expect(Self.press(e, "Left Half") == "1:0,0,0.5,1")
        _ = PluginHarness.run(e, "__win.number = 200")
        #expect(Self.press(e, "Left Half") == "1:0,0,0.5,1")
    }

    /// Display A is main (1000×800, a 25pt menu bar); B sits at `b`.
    static func moveToDisplay(window: String, b: String) throws -> String {
        let e = try PluginHarness.load(plugin: "windows.js", mock: Self.mock)
        return PluginHarness.run(e, """
            macotron.display.list = () => [
                { id: 1, frame: { x: 0, y: 0, width: 1000, height: 800 }, visibleFrame: { x: 0, y: 0, width: 1000, height: 775 } },
                { id: 2, frame: \(b), visibleFrame: \(b) },
            ];
            __win.frame = \(window);
            var __to = null;
            macotron.window.moveToFraction = (id, f) => { __to = [f.display, f.x, f.y, f.w, f.h].join(","); return true; };
            __keys["Next Display"](); __to
            """)
    }

    @Test("the left half of one display lands on the left half of the next")
    func sideBySide() throws {
        #expect(try Self.moveToDisplay(
            window: "{ x: 0, y: 25, width: 500, height: 775 }",
            b: "{ x: 1000, y: 0, width: 1000, height: 800 }") == "2,0,0,0.5,1")
    }

    @Test("a display stacked above keeps the quarter")
    func stacked() throws {
        #expect(try Self.moveToDisplay(
            window: "{ x: 0, y: 25, width: 500, height: 387.5 }",
            b: "{ x: 0, y: 800, width: 1000, height: 800 }") == "2,0,0,0.5,0.5")
    }

    @Test("a window bigger than its display is clamped to the whole screen")
    func clamped() throws {
        #expect(try Self.moveToDisplay(
            window: "{ x: -100, y: 0, width: 1200, height: 900 }",
            b: "{ x: 1000, y: 0, width: 1000, height: 800 }") == "2,0,0,1,1")
    }
}

private func js(_ string: String) -> String {
    String(data: try! JSONSerialization.data(withJSONObject: string, options: .fragmentsAllowed), encoding: .utf8)!
}
