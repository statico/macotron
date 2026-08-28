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
        #expect(FanController.displayError(long) == "Macotron helper is not installed")
        #expect(FanController.displayError("macOS thermal manager held the fans") == "macOS thermal manager held the fans")
    }

    @Test("a floor yields only when the machine is actually in trouble")
    func floorIsNotACeiling() {
        // Ordinary work, including merely warm: the floor is what the user
        // asked for, so it holds.
        #expect(FanFloor.shouldForce(thermalState: .nominal, floor: 3000, max: 5000))
        #expect(FanFloor.shouldForce(thermalState: .fair, floor: 3000, max: 5000))
        // In trouble the floor is a ceiling, so macOS takes the fan back.
        #expect(!FanFloor.shouldForce(thermalState: .serious, floor: 3000, max: 5000))
        #expect(!FanFloor.shouldForce(thermalState: .critical, floor: 3000, max: 5000))
    }

    @Test("a floor at full speed is never released")
    func fullFloorIsNeverACeiling() {
        // Nothing macOS could want is above the firmware maximum, so handing
        // the fan back could only ever slow it down.
        #expect(FanFloor.shouldForce(thermalState: .critical, floor: 5000, max: 5000))
        #expect(FanFloor.shouldForce(thermalState: .serious, floor: 5349, max: 5349))
    }
}
