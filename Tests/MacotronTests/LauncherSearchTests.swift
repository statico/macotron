import Foundation
import Testing
@testable import MacotronEngine
@testable import MacotronUI
@testable import Modules

@MainActor
@Suite("LauncherSearch")
struct LauncherSearchTests {
    @Test("contacts email and phone clicks open mailto and tel")
    func contactsOpen() throws {
        let result = try PluginHarness.evalSettled(plugin: "contacts.js", mock: #"""
            var opened = [];
            var items = [];
            var macotron = {
                plugin: () => ({}),
                every: () => {},
                contacts: { list: () => Promise.resolve([
                    { id: "1", name: "Ada", emails: ["ada@example.com"], phones: [], organization: "" },
                    { id: "2", name: "Bob", emails: [], phones: ["555-0100"], organization: "Acme" }
                ]) },
                launcher: { set: (_, rows) => { items = rows; } },
                url: { open: (url) => { opened.push(url); } },
                notify: { toast: () => {} }
            };
            """#, extra: #"""
            items[0].onClick();
            items[1].onClick();
            JSON.stringify(opened)
            """#)
        #expect(result.contains("mailto:ada@example.com"))
        #expect(result.contains("tel:555-0100"))
    }

    @Test("Search Google opens a google URL with the query")
    func searchGoogle() throws {
        let result = try PluginHarness.evalSettled(plugin: "web-search.js", mock: #"""
            var opened = [];
            var commands = {};
            var macotron = {
                plugin: () => ({}),
                command: (name, desc, fn) => { commands[name] = fn; },
                url: { open: (url) => { opened.push(url); } },
                shell: { run: () => {} },
                notify: { toast: () => {} }
            };
            """#, extra: #"""
            commands["Search Google"]({ q: "macotron" });
            JSON.stringify(opened)
            """#)
        #expect(result.contains("google"))
        #expect(result.contains("macotron"))
    }

    @Test("Define opens dict:// for the word")
    func define() throws {
        let result = try PluginHarness.evalSettled(plugin: "web-search.js", mock: #"""
            var runs = [];
            var commands = {};
            var macotron = {
                plugin: () => ({}),
                command: (name, desc, fn) => { commands[name] = fn; },
                url: { open: () => {} },
                shell: { run: (cmd, args) => { runs.push({ cmd: cmd, args: args }); } },
                notify: { toast: () => {} }
            };
            """#, extra: #"""
            commands["Define"]({ q: "apple" });
            JSON.stringify(runs)
            """#)
        #expect(result.contains("dict://"))
        #expect(result.contains("apple"))
    }
}

@MainActor
@Suite("LauncherRowID")
struct LauncherRowIDTests {
    @Test("a row id splits at the first slash and drops the live bucket marker")
    func split() {
        let parsed = LauncherModule.split("launcher:file-search\u{1}live//Users/alex/a b.pdf")
        #expect(parsed?.provider == "file-search")
        #expect(parsed?.rowId == "/Users/alex/a b.pdf")
        #expect(LauncherModule.split("launcher:calc/1")?.provider == "calc")
        #expect(LauncherModule.split("com.apple.Safari") == nil)
    }
}

@MainActor
@Suite("LauncherLiveHits")
struct LauncherLiveHitsTests {
    /// The module only holds the engine weakly, so the engine has to outlive
    /// the body rather than be returned and dropped.
    private func withModule(_ js: String, _ body: (Engine, LauncherModule) -> Void) {
        let engine = Engine()
        engine.addModule(LauncherModule())
        engine.registerAllModules()
        let module = engine.configStore["__launcherModule"] as! LauncherModule
        let (_, error) = engine.evaluate(js, filename: "<test>")
        #expect(error == nil)
        body(engine, module)
    }

    @Test("a provider returning an array still answers directly")
    func plainArray() {
        withModule("""
            macotron.launcher.query("p", function (q) {
                return [{ id: "1", title: "plain " + q }];
            });
            """) { _, module in
            #expect(module.liveHits(query: "hi").map(\.title) == ["plain hi"])
        }
    }

    @Test("a provider that declares itself secondary marks its rows")
    func secondaryFlag() {
        withModule("""
            macotron.launcher.query("p", function () { return [{ id: "1", title: "row" }]; },
                                    { secondary: true });
            macotron.launcher.query("q", function () { return [{ id: "1", title: "row" }]; });
            """) { _, module in
            #expect(module.liveHits(query: "hi").map(\.secondary) == [true, false])
        }
    }

    @Test("a provider returning a settled promise answers the same keystroke")
    func settledPromise() {
        withModule("""
            macotron.launcher.query("p", async function (q) {
                return [{ id: "1", title: "async " + q }];
            });
            """) { _, module in
            #expect(module.liveHits(query: "hi").map(\.title) == ["async hi"])
        }
    }

    @Test("a late promise pushes results and asks the launcher to refresh")
    func latePromise() {
        withModule("""
            globalThis.__settle = null;
            macotron.launcher.query("p", function (q) {
                return new Promise(function (resolve) {
                    globalThis.__settle = function () {
                        resolve([{ id: "1", title: "late " + q }]);
                    };
                });
            });
            """) { engine, module in
            var refreshes = 0
            module.onLiveUpdate = { refreshes += 1 }

            #expect(module.liveHits(query: "hi").isEmpty)
            #expect(refreshes == 0)

            engine.evaluate("__settle()")
            #expect(refreshes == 1)
        }
    }

    @Test("a late answer survives the next keystroke instead of being cleared")
    func lateAnswerSurvives() {
        withModule("""
            globalThis.__settle = null;
            macotron.launcher.query("p", function (q) {
                return new Promise(function (resolve) {
                    globalThis.__settle = function () {
                        resolve([{ id: "1", title: "late " + q }]);
                    };
                });
            });
            """) { engine, module in
            #expect(module.liveHits(query: "hi").isEmpty)
            engine.evaluate("__settle()")

            // The launcher asks again the moment the answer lands. Clearing the
            // bucket for the new promise would drop the row that just arrived,
            // and a provider that never resolves synchronously would show nothing.
            #expect(module.liveHits(query: "hi").map(\.title) == ["late hi"])
        }
    }

    @Test("an answer to an abandoned keystroke is dropped")
    func staleAnswer() {
        withModule("""
            globalThis.__settles = [];
            macotron.launcher.query("p", function (q) {
                return new Promise(function (resolve) {
                    globalThis.__settles.push(function () {
                        resolve([{ id: "1", title: q }]);
                    });
                });
            });
            """) { engine, module in
            var refreshes = 0
            module.onLiveUpdate = { refreshes += 1 }

            _ = module.liveHits(query: "h")
            _ = module.liveHits(query: "hi")
            engine.evaluate("__settles[0]()")
            #expect(refreshes == 0)

            engine.evaluate("__settles[1]()")
            #expect(refreshes == 1)
        }
    }
}

@MainActor
@Suite("LauncherResultRanking")
struct LauncherResultRankingTests {
    private func row(_ id: String, _ title: String, _ type: SearchResult.ResultType) -> SearchResult {
        SearchResult(id: id, title: title, subtitle: "", type: type)
    }

    @Test("a folder the user named outranks a contact that shares a few letters")
    func fileBeatsWeakerPluginRow() {
        let file = row("/Applications", "Applications", .plugin)
        let ranked = SearchResult.ranked(
            query: "applic",
            rows: [row("c1", "Apple Inc.", .plugin), file],
            late: ["/Applications"]
        )
        #expect(ranked.first?.id == "/Applications")
    }

    @Test("an app whose name was typed still leads an equally good file")
    func appWinsTies() {
        let ranked = SearchResult.ranked(
            query: "safari",
            rows: [row("~/Safari", "Safari", .plugin), row("com.apple.Safari", "Safari", .app)],
            late: ["~/Safari"]
        )
        #expect(ranked.map(\.id) == ["com.apple.Safari", "~/Safari"])
    }

    @Test("a folder at the top of the disk beats a longer path with a shorter name")
    func shallowPathWins() {
        let file = { (path: String, title: String) in
            SearchResult(id: path, title: title, subtitle: path, type: .plugin, path: path)
        }
        let ranked = SearchResult.ranked(
            query: "applica",
            rows: [
                file("/Users/x/Library/Photos/Libraries/Application", "Application"),
                file("/Applications", "Applications"),
            ],
            late: ["/Users/x/Library/Photos/Libraries/Application", "/Applications"]
        )
        #expect(ranked.first?.id == "/Applications")
    }

    @Test("a frequently picked row rises above an otherwise equal one")
    func frequentRowRises() {
        let rows = [row("a", "Notes A", .app), row("b", "Notes B", .app)]
        #expect(SearchResult.ranked(query: "notes", rows: rows).first?.id == "a")
        #expect(SearchResult.ranked(query: "notes", rows: rows, uses: ["b": 3]).first?.id == "b")
    }

    @Test("the pick bonus caps, so a habit cannot outscore typing the name")
    func pickBonusCaps() {
        let rows = [row("exact", "Notes", .app), row("habit", "Nothing Else Studio", .app)]
        let ranked = SearchResult.ranked(query: "notes", rows: rows, uses: ["habit": 100])
        #expect(ranked.first?.id == "exact")
    }

    @Test("the list is capped at one screenful")
    func capped() {
        let rows = (0..<40).map { row("app\($0)", "Note \($0)", .app) }
        #expect(SearchResult.ranked(query: "note", rows: rows).count == 20)
    }
}
