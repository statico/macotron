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
}
