import Foundation
import Testing
@testable import MacotronEngine
@testable import Modules

@MainActor
@Suite("ScheduleRepeat")
struct ScheduleRepeatTests {
    @Test("every keeps firing, not just once")
    func repeats() async throws {
        let engine = Engine()
        let mod = ScheduleModule()
        engine.addModule(mod)
        engine.registerAllModules()

        let (_, error) = engine.evaluate("globalThis.n = 0; macotron.every(50, () => { globalThis.n++; });")
        #expect(error == nil)

        try await Task.sleep(for: .milliseconds(400))

        let (count, err2) = engine.evaluate("String(globalThis.n)")
        #expect(err2 == nil)
        #expect((Int(count ?? "0") ?? 0) >= 3, "every fired \(count ?? "0") times in 400ms")
    }

    @Test("a job that stops itself from inside its own callback survives the call")
    func stopsItself() async throws {
        let engine = Engine()
        let mod = ScheduleModule()
        engine.addModule(mod)
        engine.registerAllModules()

        // The callback is an inline arrow: the scheduler's reference is the only
        // one there is, so stop() releasing it mid-call destroys the function
        // that is still running. Everything after stop() has to still happen.
        let (_, error) = engine.evaluate("""
            globalThis.log = "";
            const stop = macotron.every(50, () => {
                globalThis.log += "fired";
                stop();
                globalThis.log += ":returned";
            });
        """)
        #expect(error == nil)

        try await Task.sleep(for: .milliseconds(400))

        let (log, err) = engine.evaluate("globalThis.log")
        #expect(err == nil)
        #expect(log == "fired:returned")
    }

    @Test("stop() called from outside the callback halts the job")
    func stopsFromOutside() async throws {
        let engine = Engine()
        let mod = ScheduleModule()
        engine.addModule(mod)
        engine.registerAllModules()
        engine.evaluate("globalThis.n = 0; globalThis.stop = macotron.every(50, () => { globalThis.n++; });")
        let (kind, _) = engine.evaluate("typeof globalThis.stop")
        #expect(kind == "function")
        try await Task.sleep(for: .milliseconds(120))
        engine.evaluate("globalThis.stop();")
        let (mid, _) = engine.evaluate("String(globalThis.n)")
        try await Task.sleep(for: .milliseconds(300))
        let (after, _) = engine.evaluate("String(globalThis.n)")
        #expect(mid == after)
    }
}

