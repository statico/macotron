import Foundation
import Testing
@testable import MacotronEngine
@testable import Modules

@MainActor
@Suite("LauncherRepeatQuery")
struct LauncherRepeatQueryTests {
    @Test("a repeated query's answer replaces the previous query's rows")
    func repeatQuery() {
        let engine = Engine()
        engine.addModule(LauncherModule())
        engine.registerAllModules()
        let module = engine.configStore["__launcherModule"] as! LauncherModule
        // An async provider like file-search: echoes the query when told to.
        let (_, error) = engine.evaluate("""
            globalThis.__settles = [];
            macotron.launcher.query("files", async function (q) {
                return new Promise(function (resolve) {
                    globalThis.__settles.push(function () {
                        resolve([{ id: q, title: "hit " + q }]);
                    });
                });
            }, { secondary: true });
            """, filename: "<test>")
        #expect(error == nil)
        var refreshes = 0
        module.onLiveUpdate = { refreshes += 1 }

        // applications #1
        #expect(module.liveHits(query: "applications").isEmpty)
        engine.evaluate("__settles[0]()")
        #expect(refreshes == 1)
        #expect(module.liveHits(query: "applications").map(\.title) == ["hit applications"])
        engine.evaluate("__settles[1]()")  // round 2, same rows, no refresh

        // desktop: the old rows answered an unrelated query, so they hide
        // instead of dressing up as desktop results.
        #expect(module.liveHits(query: "desktop").isEmpty)
        engine.evaluate("__settles[2]()")
        #expect(module.liveHits(query: "desktop").map(\.title) == ["hit desktop"])
        engine.evaluate("__settles[3]()")

        // applications #2 — the bug report: desktop rows must not linger.
        #expect(module.liveHits(query: "applications").isEmpty)
        let before = refreshes
        engine.evaluate("__settles[4]()")
        #expect(refreshes == before + 1)
        #expect(module.liveHits(query: "applications").map(\.title) == ["hit applications"])
    }

    @Test("typing forward keeps the previous answer's rows on screen")
    func typingForwardKeepsRows() {
        let engine = Engine()
        engine.addModule(LauncherModule())
        engine.registerAllModules()
        let module = engine.configStore["__launcherModule"] as! LauncherModule
        engine.evaluate("""
            globalThis.__settles = [];
            macotron.launcher.query("files", async function (q) {
                return new Promise(function (resolve) {
                    globalThis.__settles.push(function () {
                        resolve([{ id: q, title: "hit " + q }]);
                    });
                });
            }, { secondary: true });
            """, filename: "<test>")
        _ = module.liveHits(query: "desk")
        engine.evaluate("__settles[0]()")
        #expect(module.liveHits(query: "deskt").map(\.title) == ["hit desk"])
        #expect(module.liveHits(query: "des").map(\.title) == ["hit desk"])
    }

    @Test("a lost settle is healed by the watchdog asking again")
    func watchdogHeals() {
        let engine = Engine()
        engine.addModule(LauncherModule())
        engine.registerAllModules()
        let module = engine.configStore["__launcherModule"] as! LauncherModule
        // A promise that never settles: the shape a budget-interrupted
        // reaction leaves behind.
        engine.evaluate("""
            macotron.launcher.query("files", function () {
                return new Promise(function () {});
            });
            """, filename: "<test>")
        var refreshes = 0
        module.onLiveUpdate = { refreshes += 1 }
        #expect(module.liveHits(query: "stuck").isEmpty)
        #expect(refreshes == 0)
        RunLoop.main.run(until: Date().addingTimeInterval(1.3))
        #expect(refreshes == 1)
    }
}
