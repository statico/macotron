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

    @Test("a floor yields to macOS asking for more air, and holds otherwise")
    func floorIsNotACeiling() {
        #expect(FanFloor.shouldForce(demand: 2000, floor: 3000))
        #expect(!FanFloor.shouldForce(demand: 4200, floor: 3000))
        // Nothing readable: keep the floor the user asked for.
        #expect(FanFloor.shouldForce(demand: nil, floor: 3000))
    }

    @Test("only a reading macOS could have written counts as a demand")
    func systemDemandReadings() {
        // Our own floor, read back out of the register we wrote it to.
        #expect(!FanFloor.isSystemDemand(3000, floor: 3000, min: 1000))
        // A stopped fan is not a demand, it is an unwritten register.
        #expect(!FanFloor.isSystemDemand(0, floor: 3000, min: 1000))
        // Nor is anything the firmware itself could not turn.
        #expect(!FanFloor.isSystemDemand(400, floor: 3000, min: 1000))
        // An unreadable minimum must not make zero look legitimate.
        #expect(!FanFloor.isSystemDemand(0, floor: 3000, min: 0))
        // Real answers, on both sides of the floor.
        #expect(FanFloor.isSystemDemand(4200, floor: 3000, min: 1000))
        #expect(FanFloor.isSystemDemand(1800, floor: 3000, min: 1000))
    }

    @Test("a stale target register does not silently retire the floor")
    func staleTargetKeepsFloor() {
        // The bug this replaced: reading our own 4558 back out of Tg looked
        // like macOS asking for exactly the floor, so the fan was never forced
        // again and the floor quietly stopped being held.
        let stale = 4558.0
        #expect(!FanFloor.isSystemDemand(stale, floor: 4558, min: 1350))
        #expect(FanFloor.shouldForce(demand: nil, floor: 4558))
    }
}
