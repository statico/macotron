// AppearanceSettingTests.swift — ui.appearance parsing and NSAppearance mapping
import AppKit
import Testing
@testable import MacotronUI

@Suite("AppearanceSetting")
struct AppearanceSettingTests {
    @Test("Parses known values, anything else is system", arguments: [
        ("dark", AppearanceSetting.dark),
        ("light", .light),
        ("system", .system),
        ("blue", .system),
    ])
    func parsesStrings(raw: String, expected: AppearanceSetting) {
        #expect(AppearanceSetting.parse(raw) == expected)
    }

    @Test("Missing or non-string values default to system")
    func defaultsToSystem() {
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
