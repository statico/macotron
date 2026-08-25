// DeadlineTests.swift — a runaway plugin must be interrupted, not wedge the app
import Testing
import CQuickJS
import Foundation
@testable import MacotronEngine

@MainActor
@Suite("Interrupt deadlines")
struct DeadlineTests {
    /// Register `globalThis.spin` as an endless loop and hand back the callback.
    private func spinner(_ engine: Engine) -> JSValue {
        engine.evaluate("globalThis.spin = function () { while (true) {} };")
        let global = JS_GetGlobalObject(engine.context)
        let fn = JSBridge.getProperty(engine.context, global, "spin")
        JS_FreeValue(engine.context, global)
        return fn
    }

    @Test("callJS interrupts an endless callback and reports it")
    func callbackIsInterrupted() {
        let engine = Engine()
        let fn = spinner(engine)
        let start = Date()
        let result = engine.callJS(fn, budget: 0.2, label: "test spin")
        let elapsed = Date().timeIntervalSince(start)

        #expect(result == nil, "an interrupted call must report failure, not a value")
        #expect(elapsed < 3, "budget of 0.2s should not take \(elapsed)s")
        JS_FreeValue(engine.context, fn)
    }

    @Test("a command that never returns still gives the app back")
    func commandIsInterrupted() {
        let engine = Engine()
        let fn = spinner(engine)
        engine.commandRegistry["spin"] = RegisteredCommand(
            id: "spin", name: "spin", description: "", pluginFile: "t.js",
            arguments: [], callback: fn
        )
        let start = Date()
        #expect(engine.invokeCommand("spin"))
        #expect(Date().timeIntervalSince(start) < Engine.callbackBudget + 3)
    }

    @Test("a self-rearming promise chain cannot drain forever")
    func jobQueueIsBounded() {
        let engine = Engine()
        // Each .then schedules another, so JS_ExecutePendingJob never returns 0.
        engine.evaluate("""
            globalThis.go = function () { Promise.resolve().then(globalThis.go); };
            globalThis.go();
        """)
        let start = Date()
        engine.drainJobQueue(budget: 0.2)
        #expect(Date().timeIntervalSince(start) < 3)
    }

    @Test("nested entries keep the tighter deadline")
    func nestedDeadlineKeepsTheTighterOne() {
        let engine = Engine()
        let start = Date()
        engine.withDeadline(0.2) {
            // An inner budget of 60s must not buy back time the outer one spent.
            let fn = spinner(engine)
            _ = engine.callJS(fn, budget: 60, label: "nested spin")
            JS_FreeValue(engine.context, fn)
        }
        #expect(Date().timeIntervalSince(start) < 3)
    }

    @Test("a normal callback still returns its value")
    func healthyCallbackIsUntouched() {
        let engine = Engine()
        engine.evaluate("globalThis.add = (a) => a + 1;")
        let global = JS_GetGlobalObject(engine.context)
        let fn = JSBridge.getProperty(engine.context, global, "add")
        JS_FreeValue(engine.context, global)

        let arg = JSBridge.newInt32(engine.context, 41)
        let result = engine.callJS(fn, [arg])
        #expect(result != nil)
        if let result {
            #expect(JSBridge.toInt32(engine.context, result) == 42)
            JS_FreeValue(engine.context, result)
        }
        JS_FreeValue(engine.context, arg)
        JS_FreeValue(engine.context, fn)
    }

    @Test("runaway allocation throws instead of taking the process with it")
    func memoryLimitIsEnforced() {
        let engine = Engine()
        let (_, error) = engine.evaluate("const a = []; while (true) { a.push(new Array(100000).fill(1)); }")
        #expect(error != nil)
    }

    @Test("deep recursion throws instead of segfaulting")
    func stackLimitIsEnforced() {
        let engine = Engine()
        let (_, error) = engine.evaluate("function f() { return f(); } f();")
        #expect(error != nil)
    }
}
