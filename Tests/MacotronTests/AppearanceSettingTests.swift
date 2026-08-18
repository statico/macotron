// AppearanceSettingTests.swift — ui.appearance parsing and NSAppearance mapping
import AppKit
import Testing
@testable import MacotronUI

@Suite("AppearanceSetting")
struct AppearanceSettingTests {
    @Test("Parses known values")
    func parsesKnownValues() {
        #expect(AppearanceSetting.parse("dark") == .dark)
        #expect(AppearanceSetting.parse("light") == .light)
        #expect(AppearanceSetting.parse("system") == .system)
    }

    @Test("Unknown or missing values default to system")
    func defaultsToSystem() {
        #expect(AppearanceSetting.parse("blue") == .system)
        #expect(AppearanceSetting.parse(nil) == .system)
        #expect(AppearanceSetting.parse(42) == .system)
    }

    @Test("Maps to NSAppearance (nil means follow system)")
    func nsAppearanceMapping() {
        #expect(AppearanceSetting.system.nsAppearance == nil)
        #expect(AppearanceSetting.dark.nsAppearance?.name == .darkAqua)
        #expect(AppearanceSetting.light.nsAppearance?.name == .aqua)
    }
}
