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

    @Test("scheduling returns a stop function", arguments: [
        "macotron.every(1000, function() {})",
        #"macotron.at("13:00", function() {})"#,
    ])
    func returnsStopFunction(js: String) {
        let engine = engineWithSchedule()
        let (result, error) = engine.evaluate("typeof \(js)")
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

    @Test("records schedule plugin events")
    func recordsPluginEvents() {
        let engine = engineWithSchedule()
        engine.currentEvaluatingFile = "weather.js"
        engine.evaluate("""
            macotron.every("1h", function() {});
            macotron.every(1000, function() {});
            macotron.at("13:00", function() {});
            """)
        #expect(engine.pluginEvents["weather.js"]?.contains("schedule:every 1h") == true)
        #expect(engine.pluginEvents["weather.js"]?.contains("schedule:at 13:00") == true)
        #expect(engine.pluginEvents["weather.js"]?.contains(where: { $0.hasPrefix("schedule:every 1000") }) != true)
    }

    @Test("invalid schedule arguments throw TypeError", arguments: [
        #"macotron.every("not-a-schedule", function() {})"#,
        #"macotron.at("09:00", { weekdays: [7] }, function() {})"#,
    ])
    func invalidScheduleThrows(js: String) {
        let engine = engineWithSchedule()
        let (_, error) = engine.evaluate(js)
        #expect(error != nil)
        #expect(error?.lowercased().contains("typeerror") == true)
    }

    @Test("runtime.js does not overwrite native every")
    func runtimeDoesNotOverwriteEvery() throws {
        let runtimeURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources/Macotron/Resources/macotron-runtime.js")
        let runtimeJS = try String(contentsOf: runtimeURL, encoding: .utf8)

        let engine = Engine()
        engine.dryRun = true
        engine.addModule(ScheduleModule())
        engine.registerAllModules()
        engine.evaluate(runtimeJS, filename: "macotron-runtime.js")

        engine.currentEvaluatingFile = "test.js"
        let (_, error) = engine.evaluate("""
            macotron.every("1h", function() {});
            """)
        #expect(error == nil)
        #expect(engine.pluginEvents["test.js"]?.contains("schedule:every 1h") == true)
    }
}
