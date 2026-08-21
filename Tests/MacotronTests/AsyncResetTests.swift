// AsyncResetTests.swift — reload while native async work is in flight
import CQuickJS
import Modules
import Testing
@testable import MacotronEngine

@MainActor
@Suite("Async reset")
struct AsyncResetTests {
    @Test("reset during shell.run rejects the promise and stale completion is dropped")
    func resetDuringShellRun() async throws {
        let engine = Engine()
        engine.addModule(ShellModule())
        engine.registerAllModules()

        var logs: [String] = []
        engine.logHandler = { logs.append($0) }

        engine.evaluate("""
            macotron.shell.run('sleep', ['0.3']).then(
                r => $$__log('settled:resolved'),
                e => $$__log('settled:rejected:' + e)
            );
        """)
        engine.reset()

        // The in-flight promise must reject before the old context is freed.
        #expect(logs.contains { $0.hasPrefix("settled:rejected") })

        // Let the shell completion land on the main queue after the reload.
        // It must not touch the freed context (crash) or resolve the promise.
        try await Task.sleep(for: .seconds(1))
        let (result, error) = engine.evaluate("1 + 1")
        #expect(error == nil)
        #expect(result == "2")
        #expect(!logs.contains { $0.hasPrefix("settled:resolved") })
    }
}
