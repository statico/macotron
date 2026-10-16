import Foundation
import Testing
@testable import MacotronEngine

@MainActor
@Suite("Pointer Tuning (hid.js)")
struct PointerTuningTests {
    /// `__prefs` stands in for the global domain; the panel's HTML and its
    /// message handler are kept so a test can read what was painted and send
    /// what the sliders would.
    private static let mock = #"""
        var __prefs = {};
        var __commands = {};
        var __html = null;
        var __onMessage = null;
        var macotron = {
            plugin: () => ({}),
            command: (name, _desc, fn) => { __commands[name] = fn; },
            hid: { list: () => [] },
            notify: { toast: () => {} },
            prefs: {
                get: (domain, key) => domain === "-g" && key in __prefs ? __prefs[key] : null,
                set: (domain, key, value) => {
                    if (domain !== "-g") return false;
                    if (value === null) delete __prefs[key]; else __prefs[key] = value;
                    return true;
                }
            },
            panel: { open: (o) => { __html = o.html; return 1; }, onMessage: (_id, fn) => { __onMessage = fn; } }
        };
        """#

    @Test("absent keys read as the system default; strings, numbers, and -1 read as written")
    func reads() throws {
        let engine = try PluginHarness.load(plugin: "hid.js", mock: Self.mock)
        #expect(PluginHarness.run(engine, #"""
            __prefs = { "com.apple.mouse.scaling": -1, "com.apple.trackpad.scaling": "1.5" };
            [readScaling("com.apple.mouse.scaling"), readScaling("com.apple.trackpad.scaling"),
             readScaling("com.apple.scrollwheel.scaling")].map(describeScaling).join("|")
            """#) == "acceleration off|1.5|system default")
    }

    @Test("natural scrolling is on unless the pref is false or 0")
    func natural() throws {
        let engine = try PluginHarness.load(plugin: "hid.js", mock: Self.mock)
        func checked(_ value: String) -> String {
            PluginHarness.run(engine, """
                __prefs = { "com.apple.swipescrolldirection": \(value) };
                __commands["Pointer Tuning"]();
                String(/type="checkbox" checked/.test(__html))
                """)
        }
        #expect(checked("false") == "false")
        #expect(checked("0") == "false")
        #expect(checked("true") == "true")
        #expect(PluginHarness.run(engine, #"__prefs = {}; __commands["Pointer Tuning"](); String(/type="checkbox" checked/.test(__html))"#) == "true")
    }

    @Test("panel messages write numbers and booleans to the global domain")
    func writes() throws {
        let engine = try PluginHarness.load(plugin: "hid.js", mock: Self.mock)
        #expect(PluginHarness.run(engine, #"""
            __commands["Pointer Tuning"]();
            __onMessage({ key: "com.apple.mouse.scaling", value: 2.5 });
            __onMessage({ key: "com.apple.swipescrolldirection", bool: false });
            JSON.stringify(__prefs)
            """#) == #"{"com.apple.mouse.scaling":2.5,"com.apple.swipescrolldirection":false}"#)
    }
}
