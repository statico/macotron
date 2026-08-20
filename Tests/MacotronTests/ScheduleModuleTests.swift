import Foundation
import Testing
@testable import MacotronEngine
@testable import Modules

@MainActor
@Suite("ScheduleModule")
struct ScheduleModuleTests {
    private func engineWithSchedule() -> Engine {
        let engine = Engine()
        engine.dryRun = true
        engine.addModule(ScheduleModule())
        engine.registerAllModules()
        return engine
    }

    @Test("every returns a stop function")
    func everyReturnsStopFunction() {
        let engine = engineWithSchedule()
        let (result, error) = engine.evaluate("""
            typeof macotron.every(1000, function() {})
            """)
        #expect(error == nil)
        #expect(result == "function")
    }

    @Test("at returns a stop function")
    func atReturnsStopFunction() {
        let engine = engineWithSchedule()
        let (result, error) = engine.evaluate("""
            typeof macotron.at("13:00", function() {})
            """)
        #expect(error == nil)
        #expect(result == "function")
    }

    @Test("stop cancels a numeric every job")
    func stopCancelsNumericEvery() {
        let engine = Engine()
        engine.addModule(ScheduleModule())
        engine.registerAllModules()
        engine.currentEvaluatingFile = "test.js"
        engine.evaluate("""
            var count = 0;
            var stop = macotron.every(10, function() { count++; });
            stop();
            """)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let (result, _) = engine.evaluate("count")
        #expect(result == "0")
        engine.reset()
    }

    @Test("reset cancels schedule jobs")
    func resetCancelsJobs() {
        let engine = Engine()
        engine.addModule(ScheduleModule())
        engine.registerAllModules()
        engine.currentEvaluatingFile = "test.js"
        engine.evaluate("macotron.every(10, function() {})")
        engine.reset()
        let module = engine.configStore["__scheduleModule"] as? ScheduleModule
        #expect(module?.activeJobCount == 0)
    }

    @Test("invalid every string throws TypeError")
    func invalidEveryThrows() {
        let engine = engineWithSchedule()
        let (_, error) = engine.evaluate("""
            macotron.every("not-a-schedule", function() {})
            """)
        #expect(error != nil)
        #expect(error?.lowercased().contains("typeerror") == true)
    }

    @Test("records schedule plugin events")
    func recordsPluginEvents() {
        let engine = engineWithSchedule()
        engine.currentEvaluatingFile = "weather.js"
        engine.evaluate("""
            macotron.every("1h", function() {});
            macotron.at("13:00", function() {});
            """)
        #expect(engine.pluginEvents["weather.js"]?.contains("schedule:every 1h") == true)
        #expect(engine.pluginEvents["weather.js"]?.contains("schedule:at 13:00") == true)
    }
}
