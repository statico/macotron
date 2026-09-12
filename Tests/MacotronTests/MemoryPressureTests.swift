// MemoryPressureTests.swift — kern.memorystatus_vm_pressure_level mapping
import Foundation
import Testing
@testable import Modules

@Suite("MemoryPressure")
struct MemoryPressureTests {
    @Test("maps the three levels the kernel actually reports")
    func levels() {
        #expect(MemoryPressure.name(1) == "normal")
        #expect(MemoryPressure.name(2) == "warning")
        #expect(MemoryPressure.name(4) == "critical")
    }

    // The sysctl is a bitfield with only three values defined, so anything else
    // is a level this build does not know. Guessing "critical" there would nag
    // the user over nothing; normal is the safe reading.
    @Test("unknown levels read as normal")
    func unknown() {
        #expect(MemoryPressure.name(0) == "normal")
        #expect(MemoryPressure.name(3) == "normal")
        #expect(MemoryPressure.name(-1) == "normal")
    }

    @Test("the live sysctl answers with a known level")
    func live() {
        #expect(["normal", "warning", "critical"].contains(MemoryPressure.current()))
    }
}
