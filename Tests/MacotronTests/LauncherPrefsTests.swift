// LauncherPrefsTests.swift — snapTextScale clamps to supported stops
import Testing
@testable import MacotronUI

@MainActor
@Suite("LauncherPrefs.snapTextScale")
struct LauncherPrefsTests {
    @Test("exact stops snap to themselves")
    func exactStops() {
        #expect(LauncherPrefs.snapTextScale(0.8) == 0.8)
        #expect(LauncherPrefs.snapTextScale(1.0) == 1.0)
        #expect(LauncherPrefs.snapTextScale(1.2) == 1.2)
    }

    @Test("1.1 snaps to 1.2")
    func onePointOne() {
        #expect(LauncherPrefs.snapTextScale(1.1) == 1.2)
    }

    @Test("0.9 snaps to 0.8")
    func zeroPointNine() {
        #expect(LauncherPrefs.snapTextScale(0.9) == 0.8)
    }

    @Test("0.85 snaps to 0.8 (tie breaks to lower via <)")
    func zeroPointEightFive() {
        #expect(LauncherPrefs.snapTextScale(0.85) == 0.8)
    }

    @Test("garbage low snaps to 0.8")
    func garbageLow() {
        #expect(LauncherPrefs.snapTextScale(-5) == 0.8)
    }

    @Test("garbage high snaps to 1.2")
    func garbageHigh() {
        #expect(LauncherPrefs.snapTextScale(99) == 1.2)
    }
}
