import Foundation
import Testing
@testable import MacotronEngine

@MainActor
@Suite("FileSearch")
struct FileSearchTests {
    private static let mock = #"""
        var __query = null;
        var __resolver = null;
        var __rows = null;
        var __opened = [];
        var __commands = {};
        var __toasts = [];
        var __store = {};
        var localStorage = {
            getItem: (k) => (k in __store ? __store[k] : null),
            setItem: (k, v) => { __store[k] = String(v); },
            removeItem: (k) => { delete __store[k]; },
            clear: () => { __store = {}; }
        };
        var macotron = {
            plugin: () => ({}),
            command: (name, _desc, fn) => { __commands[name] = fn; },
            notify: { toast: (m) => { __toasts.push(m); } },
            launcher: { query: (_id, fn, opts) => { __query = fn; __resolver = opts && opts.run; } },
            spotlight: {
                search: async (term) => [
                    { path: "/Users/alex/" + term + ".pdf", name: term + ".pdf", kind: "pdf" },
                    { path: "/Users/alex/deep/older-" + term + ".pdf", name: "older-" + term + ".pdf", kind: "pdf" }
                ]
            },
            shell: { run: async (_bin, args) => { __opened.push(args[0]); } }
        };
        """#

    /// The query is async, so the rows land in a second evaluation: the first
    /// one only drains the promise on its way out.
    private func rows(_ query: String) throws -> String {
        let engine = try PluginHarness.load(
            plugin: "file-search.js", mock: Self.mock,
            extra: "__query(\(String(reflecting: query))).then((r) => { __rows = r; });"
        )
        return PluginHarness.run(engine, "JSON.stringify(__rows)")
    }

    @Test("any query of three characters searches")
    func lengthGate() throws {
        #expect(try rows("budget").contains("budget.pdf"))
        #expect(try rows("bud").contains("bud.pdf"))
        #expect(try rows("bu") == "[]")
    }

    @Test("a row carries the spotlight path as its id, path, and action")
    func rowShape() throws {
        let engine = try PluginHarness.load(
            plugin: "file-search.js", mock: Self.mock,
            extra: #"__query("budget").then((r) => { __rows = r; });"#
        )
        let shape = PluginHarness.run(engine, #"""
            JSON.stringify({
                id: __rows[0].id,
                path: __rows[0].path,
                click: typeof __rows[0].onClick
            })
            """#)
        #expect(shape.contains(#""id":"/Users/alex/budget.pdf""#))
        #expect(shape.contains(#""path":"/Users/alex/budget.pdf""#))
        #expect(shape.contains(#""click":"function""#))
    }

    @Test("the resolver opens a path with no row on screen")
    func resolver() throws {
        let engine = try PluginHarness.load(plugin: "file-search.js", mock: Self.mock)
        let opened = PluginHarness.run(engine, #"__resolver("/tmp/a.pdf"); JSON.stringify(__opened)"#)
        #expect(opened == #"["/tmp/a.pdf"]"#)
    }

    @Test("a file you opened leads the next search for it")
    func openedFileClimbs() throws {
        let engine = try PluginHarness.load(
            plugin: "file-search.js", mock: Self.mock,
            extra: #"__query("budget").then((r) => { __rows = r; });"#
        )
        #expect(PluginHarness.run(engine, "__rows[0].path") == "/Users/alex/budget.pdf")
        _ = PluginHarness.run(engine, #"""
            __rows[1].onClick();
            __query("budget").then((r) => { __rows = r; });
            """#)
        #expect(PluginHarness.run(engine, "__rows[0].path") == "/Users/alex/deep/older-budget.pdf")
    }

    @Test("resetting one path drops only that file back")
    func resetOnePath() throws {
        let engine = try PluginHarness.load(
            plugin: "file-search.js", mock: Self.mock,
            extra: #"__query("budget").then((r) => { __rows = r; });"#
        )
        _ = PluginHarness.run(engine, #"""
            __rows[1].onClick();
            __commands["Reset File Ranking"]({ path: "/Users/alex/deep/older-budget.pdf" });
            __query("budget").then((r) => { __rows = r; });
            """#)
        #expect(PluginHarness.run(engine, "__rows[0].path") == "/Users/alex/budget.pdf")
    }

    @Test("resetting with no path forgets every file")
    func resetEverything() throws {
        let engine = try PluginHarness.load(
            plugin: "file-search.js", mock: Self.mock,
            extra: #"__query("budget").then((r) => { __rows = r; });"#
        )
        _ = PluginHarness.run(engine, #"""
            __rows[1].onClick();
            __commands["Reset File Ranking"]({});
            __query("budget").then((r) => { __rows = r; });
            """#)
        #expect(PluginHarness.run(engine, "__rows[0].path") == "/Users/alex/budget.pdf")
        #expect(PluginHarness.run(engine, "__store['file-search:opens:v1']") == "{}")
    }
}
