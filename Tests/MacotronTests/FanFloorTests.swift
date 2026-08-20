import Testing
import SMCKit
@testable import Modules

@Suite("FanFloor")
struct FanFloorTests {
    @Test("100% is the firmware max")
    func full() {
        #expect(FanFloor.rpm(percent: 100, min: 1350, max: 5349) == 5349)
    }

    @Test("50% is the midpoint of the firmware range")
    func half() {
        #expect(FanFloor.rpm(percent: 50, min: 1000, max: 5000) == 3000)
    }

    @Test("percent is clamped")
    func clamp() {
        #expect(FanFloor.rpm(percent: -10, min: 1000, max: 5000) == 1000)
        #expect(FanFloor.rpm(percent: 200, min: 1000, max: 5000) == 5000)
    }

    @Test("XPC helper errors stay short")
    func xpcCopy() {
        let long = "Couldn’t communicate with a helper application."
        #expect(FanController.helperUnreachable(long))
        #expect(FanController.displayError(long) == "Fan helper is not installed")
        #expect(FanController.displayError("macOS thermal manager held the fans") == "macOS thermal manager held the fans")
    }
}
