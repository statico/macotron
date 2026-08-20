import Foundation
import Testing
@testable import MacotronEngine
@testable import Modules

@Suite("PowerActions")
struct PowerActionsTests {
    @Test("dry run reports success without putting the Mac to sleep")
    func dryRun() {
        #expect(PowerActions.lock(dryRun: true))
        #expect(PowerActions.sleep(dryRun: true))
        #expect(PowerActions.displaySleep(dryRun: true))
        #expect(PowerActions.screensaver(dryRun: true))
        #expect(PowerActions.logOut(dryRun: true))
        #expect(PowerActions.restart(dryRun: true))
        #expect(PowerActions.shutdown(dryRun: true))
    }
}

@MainActor
@Suite("PowerModule")
struct PowerModuleTests {
    @Test("JS power methods exist and no-op in dry run")
    func jsDryRun() {
        let engine = Engine()
        engine.dryRun = true
        engine.addModule(PowerModule())
        engine.registerAllModules()
        let (result, error) = engine.evaluate("""
            JSON.stringify({
                lock: macotron.power.lock(),
                sleep: macotron.power.sleep(),
                displaySleep: macotron.power.displaySleep(),
                screensaver: macotron.power.screensaver(),
                logOut: macotron.power.logOut(),
                restart: macotron.power.restart(),
                shutdown: macotron.power.shutdown()
            })
            """)
        #expect(error == nil)
        #expect(result == #"{"lock":true,"sleep":true,"displaySleep":true,"screensaver":true,"logOut":true,"restart":true,"shutdown":true}"#)
    }
}
