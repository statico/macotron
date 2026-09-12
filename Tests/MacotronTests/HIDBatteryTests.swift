// HIDBatteryTests.swift — charge level coercion for hid.list()
import Foundation
import Testing
@testable import Modules

@Suite("HIDBattery")
struct HIDBatteryTests {
    @Test("coerces the shapes IOKit hands back")
    func coercion() {
        #expect(HIDDevices.batteryPercent(75) == 75)
        #expect(HIDDevices.batteryPercent(NSNumber(value: 42)) == 42)
        #expect(HIDDevices.batteryPercent("88") == 88)
        #expect(HIDDevices.batteryPercent(0) == 0)
        #expect(HIDDevices.batteryPercent(100) == 100)
    }

    // Absent is the common case, and a device reporting out of range is
    // reporting nonsense. Both read as "no battery" so a plugin never has to
    // draw a -1% or 255% reading.
    @Test("drops absent and out-of-range readings")
    func rejects() {
        #expect(HIDDevices.batteryPercent(nil) == nil)
        #expect(HIDDevices.batteryPercent(-1) == nil)
        #expect(HIDDevices.batteryPercent(101) == nil)
        #expect(HIDDevices.batteryPercent(255) == nil)
        #expect(HIDDevices.batteryPercent("not a number") == nil)
    }
}
