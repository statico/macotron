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
        var macotron = {
            plugin: () => ({}),
            launcher: { query: (_id, fn, opts) => { __query = fn; __resolver = opts && opts.run; } },
            spotlight: {
                search: async (term) => [
                    { path: "/Users/alex/" + term + ".pdf", name: term + ".pdf", kind: "pdf" }
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
}
