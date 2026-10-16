import Foundation
import Testing
@testable import MacotronEngine

@MainActor
@Suite("Present Mode plugin")
struct PresentModeTests {
    private static let mock = #"""
        var __finder = {};
        var __toggle = null;
        var __killed = 0;
        var macotron = {
            plugin: () => ({}),
            command: (_name, _desc, fn) => { __toggle = fn; },
            prefs: {
                get: (domain, key) => domain === "com.apple.finder" && key in __finder ? __finder[key] : null,
                set: (domain, key, value) => { if (domain !== "com.apple.finder") return false; __finder[key] = value; return true; }
            },
            shell: { run: async (path) => { if (path === "/usr/bin/killall") __killed++; return { exitCode: 0 }; } },
            notify: { toast: () => {} }
        };
        """#

    @Test("absent or true hides the icons; false or a typeless \"false\" shows them")
    func toggles() throws {
        let engine = try PluginHarness.load(plugin: "present-mode.js", mock: Self.mock)
        for (before, after) in [("undefined", "false"), ("true", "false"), ("false", "true"), ("'false'", "true"), ("0", "true")] {
            // The toggle is async; evaluate drains the job queue before the read.
            PluginHarness.run(engine, """
                if (\(before) === undefined) delete __finder.CreateDesktop; else __finder.CreateDesktop = \(before);
                __toggle();
                """)
            #expect(PluginHarness.run(engine, "String(__finder.CreateDesktop)") == after, "CreateDesktop \(before)")
        }
        #expect(PluginHarness.run(engine, "String(__killed)") == "5")
    }
}
