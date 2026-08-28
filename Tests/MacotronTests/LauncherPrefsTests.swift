// LauncherPrefsTests.swift — snapTextScale clamps to supported stops
import Testing
@testable import MacotronEngine
@testable import MacotronUI

@MainActor
@Suite("LauncherPrefs.snapTextScale")
struct LauncherPrefsTests {
    @Test("snaps to the nearest supported stop", arguments: [
        (0.8, 0.8), (1.0, 1.0), (1.2, 1.2),
        (1.1, 1.2),
        (0.9, 0.8),
        (0.85, 0.8),  // tie breaks to the lower stop via <
        (-5, 0.8),  // garbage low
        (99, 1.2),  // garbage high
    ])
    func snaps(value: Double, expected: Double) {
        #expect(LauncherPrefs.snapTextScale(value) == expected)
    }
}

@Suite("LauncherBackground")
struct LauncherBackgroundTests {
    @Test("parses known values")
    func parses() {
        #expect(LauncherBackground.parse("glass") == .glass)
        #expect(LauncherBackground.parse("opaque") == .opaque)
        #expect(LauncherBackground.parse("translucent") == .translucent)
    }

    @Test("unknown defaults to translucent")
    func defaults() {
        #expect(LauncherBackground.parse("crystal") == .translucent)
        #expect(LauncherBackground.parse(nil) == .translucent)
    }
}

@Suite("KeyCombo")
struct KeyComboTests {
    @Test("glyphs maps combo parts")
    func glyphs() {
        #expect(KeyCombo.glyphs("cmd+shift+a") == ["\u{2318}", "\u{21E7}", "A"])
    }
}
