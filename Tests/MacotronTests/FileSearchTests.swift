import Foundation
import Testing
@testable import MacotronEngine

@MainActor
@Suite("FileSearch")
struct FileSearchTests {
    /// The mock stands in for both the index and Spotlight. `__indexed` flips
    /// the indexer on: it answers `budget` with a file and a folder, and
    /// Spotlight keeps answering with two PDFs, so a test can tell which one
    /// served the rows.
    private static let mock = #"""
        var __query = null;
        var __resolver = null;
        var __rows = null;
        var __opened = [];
        var __commands = {};
        var __toasts = [];
        var __checks = [];
        var __store = {};
        var __opts = {};
        var __indexed = false;
        var __configured = null;
        var __reindexed = 0;
        var __now = 1;
        var __mdfind = [];
        var __searchRejects = false;
        var __configureError = null;
        Date.now = () => __now++;
        var localStorage = {
            getItem: (k) => (k in __store ? __store[k] : null),
            setItem: (k, v) => { __store[k] = String(v); },
            removeItem: (k) => { delete __store[k]; },
            clear: () => { __store = {}; }
        };
        var macotron = {
            plugin: () => __opts,
            command: (name, _desc, fn) => { __commands[name] = fn; },
            checks: (rows) => { __checks = rows; },
            every: () => () => {},
            notify: { toast: (...a) => { __toasts.push(a.join(" ")); } },
            launcher: { query: (_id, fn, opts) => { __query = fn; __resolver = opts && opts.run; } },
            files: {
                configure: async (o) => { if (__configureError) throw new Error(__configureError); __configured = o; },
                reindex: async () => { __reindexed++; },
                status: async () => ({ available: __indexed, indexing: false, watching: __indexed, entries: 12345 }),
                search: async (term) => __searchRejects ? Promise.reject(new Error("file indexer unavailable")) : [
                    { path: "/Users/alex/" + term + ".pdf", name: term + ".pdf", isDir: false, score: 900 },
                    { path: "/Users/alex/" + term, name: term, isDir: true, score: 900 }
                ]
            },
            spotlight: {
                search: async (term) => [
                    { path: "/Users/alex/" + term + ".pdf", name: term + ".pdf", kind: "pdf" },
                    { path: "/Users/alex/deep/older-" + term + ".pdf", name: "older-" + term + ".pdf", kind: "pdf" }
                ]
            },
            shell: { run: async (bin, args) => {
                if (bin === "/usr/bin/mdfind") {
                    __mdfind.push(args);
                    return { exitCode: 0, stdout: "/Users/alex/body.txt\n/Users/alex/budget.pdf\n", stderr: "" };
                }
                __opened.push(args[0]);
            } }
        };
        """#

    private func load(indexed: Bool = false, opts: String = "{}", extra: String = "", preload: String = "") throws -> Engine {
        try PluginHarness.load(
            plugin: "file-search.js",
            mock: Self.mock + "\n__indexed = \(indexed); __opts = \(opts);\n" + preload,
            extra: extra
        )
    }

    /// The query is async, so the rows land in a second evaluation: the first
    /// one only drains the promise on its way out.
    private func rows(_ query: String, indexed: Bool = false, opts: String = "{}") throws -> String {
        let engine = try load(
            indexed: indexed, opts: opts,
            extra: "__query(\(String(reflecting: query))).then((r) => { __rows = r; });"
        )
        return PluginHarness.run(engine, "JSON.stringify(__rows)")
    }

    @Test("two characters are enough to search, one is not")
    func lengthGate() throws {
        #expect(try rows("budget").contains("budget.pdf"))
        #expect(try rows("bu").contains("bu.pdf"))
        #expect(try rows("b") == "[]")
    }

    @Test("without the indexer every query goes to Spotlight")
    func spotlightFallback() throws {
        let out = try rows("budget")
        #expect(out.contains("older-budget.pdf"))
        let engine = try load()
        #expect(PluginHarness.run(engine, "__checks[0].message") == "Indexer unavailable, using Spotlight")
        #expect(PluginHarness.run(engine, "String(__checks[0].ok)") == "false")
    }

    @Test("with the indexer the rows come from it, folders marked as such")
    func indexRows() throws {
        // status() settles after the first evaluation, so the query that
        // should reach the index has to run in a second one.
        let engine = try load(indexed: true)
        #expect(PluginHarness.run(engine, "__checks[0].message") == "12,345 files indexed")
        _ = PluginHarness.run(engine, #"__query("budget").then((r) => { __rows = r; });"#)
        let out = PluginHarness.run(engine, "JSON.stringify(__rows)")
        #expect(out.contains(#""kind":"Folder""#))
        #expect(!out.contains("older-budget"))
    }

    @Test("a path query completes through Spotlight even with the indexer")
    func pathQueryUsesSpotlight() throws {
        #expect(try rows("~/bud", indexed: true).contains("older-~/bud"))
    }

    @Test("settings reach the indexer as roots, globs, and flags")
    func configure() throws {
        let engine = try load(opts: #"""
            { searchScopes: "~\n/Applications\n", ignorePatterns: "node_modules\n*.tmp\n",
              includeHidden: true, useIgnoreFiles: false }
            """#)
        #expect(PluginHarness.run(engine, "JSON.stringify(__configured)")
            == #"{"roots":["~","/Applications"],"ignore":["node_modules","*.tmp"],"hidden":true,"ignoreFiles":false}"#)
    }

    @Test("a row carries the path as its id, path, and action")
    func rowShape() throws {
        let engine = try load(extra: #"__query("budget").then((r) => { __rows = r; });"#)
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
        let engine = try load()
        let opened = PluginHarness.run(engine, #"__resolver("/tmp/a.pdf"); JSON.stringify(__opened)"#)
        #expect(opened == #"["/tmp/a.pdf"]"#)
    }

    @Test("a file you opened leads the next search for it")
    func openedFileClimbs() throws {
        let engine = try load(extra: #"__query("budget").then((r) => { __rows = r; });"#)
        #expect(PluginHarness.run(engine, "__rows[0].path") == "/Users/alex/budget.pdf")
        _ = PluginHarness.run(engine, #"""
            __rows[1].onClick();
            __query("budget").then((r) => { __rows = r; });
            """#)
        #expect(PluginHarness.run(engine, "__rows[0].path") == "/Users/alex/deep/older-budget.pdf")
    }

    @Test("resetting one path drops only that file back")
    func resetOnePath() throws {
        let engine = try load(extra: #"__query("budget").then((r) => { __rows = r; });"#)
        _ = PluginHarness.run(engine, #"""
            __rows[1].onClick();
            __commands["Reset File Ranking"]({ path: "/Users/alex/deep/older-budget.pdf" });
            __query("budget").then((r) => { __rows = r; });
            """#)
        #expect(PluginHarness.run(engine, "__rows[0].path") == "/Users/alex/budget.pdf")
    }

    @Test("resetting with no path forgets every file")
    func resetEverything() throws {
        let engine = try load(extra: #"__query("budget").then((r) => { __rows = r; });"#)
        _ = PluginHarness.run(engine, #"""
            __rows[1].onClick();
            __commands["Reset File Ranking"]({});
            __query("budget").then((r) => { __rows = r; });
            """#)
        #expect(PluginHarness.run(engine, "__rows[0].path") == "/Users/alex/budget.pdf")
        #expect(PluginHarness.run(engine, "__store['file-search:opens:v2']") == "{}")
    }

    @Test("content search appends Spotlight text hits below the name hits, escaped and scoped")
    func contentSearch() throws {
        let engine = try load(indexed: true, opts: #"{ contentSearch: true, searchScopes: "~\n/Applications" }"#)
        _ = PluginHarness.run(engine, #"__query("budget").then((r) => { __rows = r; });"#)
        // budget.pdf is both a name hit and a text hit, and shows once.
        #expect(PluginHarness.run(engine, "__rows.map((r) => r.path).join(',')")
            == "/Users/alex/budget.pdf,/Users/alex/budget,/Users/alex/body.txt")
        _ = PluginHarness.run(engine, #"__query('bud"get*').then((r) => { __rows = r; });"#)
        #expect(PluginHarness.run(engine, #"__mdfind[1].join(" ")"#)
            == #"-onlyin /Applications kMDItemTextContent == "bud\"get\*"cd"#)
    }

    @Test("content search waits for three characters")
    func contentSearchGate() throws {
        let engine = try load(indexed: true, opts: "{ contentSearch: true }")
        _ = PluginHarness.run(engine, #"__query("bu").then((r) => { __rows = r; });"#)
        #expect(PluginHarness.run(engine, "String(__mdfind.length)") == "0")
    }

    @Test("maxResults caps the rows")
    func maxResults() throws {
        let engine = try load(opts: "{ maxResults: 1 }", extra: #"__query("budget").then((r) => { __rows = r; });"#)
        #expect(PluginHarness.run(engine, "String(__rows.length)") == "1")
    }

    @Test("v1 open counts migrate to v2 with their weight and no date")
    func migrateV1() throws {
        let engine = try load(extra: "", preload: #"__store["file-search:opens:v1"] = JSON.stringify({ "/tmp/a.pdf": 3 });"#)
        #expect(PluginHarness.run(engine, "__store['file-search:opens:v2']") == #"{"/tmp/a.pdf":{"count":3,"last":0}}"#)
        #expect(PluginHarness.run(engine, "String('file-search:opens:v1' in __store)") == "false")
    }

    @Test("a rejected search falls back to Spotlight and flags the Checks row")
    func searchRejects() throws {
        let engine = try load(indexed: true)
        _ = PluginHarness.run(engine, #"__searchRejects = true; __query("budget").then((r) => { __rows = r; });"#)
        #expect(PluginHarness.run(engine, "JSON.stringify(__rows)").contains("older-budget.pdf"))
        #expect(PluginHarness.run(engine, "__checks[0].message") == "Indexer unavailable, using Spotlight")
        #expect(PluginHarness.run(engine, "String(__checks[0].ok)") == "false")
        // Later queries keep going to Spotlight without asking the indexer again.
        _ = PluginHarness.run(engine, #"__searchRejects = false; __query("budget").then((r) => { __rows = r; });"#)
        #expect(PluginHarness.run(engine, "JSON.stringify(__rows)").contains("older-budget.pdf"))
    }

    @Test("a rejected configure puts the error on the Checks row")
    func configureRejects() throws {
        let engine = try load(preload: #"__configureError = "bad glob: [";"#)
        #expect(PluginHarness.run(engine, "__checks[0].message") == "bad glob: [")
        #expect(PluginHarness.run(engine, "String(__checks[0].ok)") == "false")
    }

    @Test("Reindex Files asks the indexer and says so")
    func reindex() throws {
        let engine = try load(indexed: true)
        _ = PluginHarness.run(engine, #"__commands["Reindex Files"]();"#)
        #expect(PluginHarness.run(engine, "String(__reindexed)") == "1")
        #expect(PluginHarness.run(engine, "__toasts.join()").contains("Reindexing"))
    }
}
