// HIDReadInputTests.swift — readInput waits on the interrupt pipe
import CQuickJS
import Modules
import Testing
@testable import MacotronEngine

@MainActor
@Suite("HID readInput")
struct HIDReadInputTests {
    private func engine(dryRun: Bool) -> Engine {
        let engine = Engine()
        engine.dryRun = dryRun
        engine.addModule(HIDModule())
        engine.registerAllModules()
        return engine
    }

    @Test("a device that is not open rejects instead of hanging")
    func notOpen() async throws {
        let engine = engine(dryRun: false)
        var logs: [String] = []
        engine.logHandler = { logs.append($0) }

        engine.evaluate("""
            macotron.hid.readInput('nope').then(
                r => $$__log('resolved:' + JSON.stringify(r)),
                e => $$__log('rejected:' + e)
            );
        """)
        engine.drainJobQueue()

        #expect(logs.contains { $0.hasPrefix("rejected:") })
    }

    @Test("--check resolves null without touching a device")
    func dryRunResolvesNull() async throws {
        let engine = engine(dryRun: true)
        var logs: [String] = []
        engine.logHandler = { logs.append($0) }

        engine.evaluate("""
            macotron.hid.readInput('1', { timeout: 50 }).then(
                r => $$__log('resolved:' + JSON.stringify(r)),
                e => $$__log('rejected:' + e)
            );
        """)
        engine.drainJobQueue()

        #expect(logs.contains("resolved:null"))
    }
}
