import Testing
@testable import Modules

@Suite("DisplayAppearance")
struct DisplayAppearanceTests {
    @Test("setNightShift(bool) toggles without a strength", arguments: [true, false])
    func boolForm(on: Bool) {
        #expect(DisplayAppearance.parseNightShift(on) == .init(on: on, strength: nil))
    }

    @Test("setNightShift({ strength }) enables and clamps to 0...1", arguments: [
        (0.6, 0.6), (1.5, 1.0), (-0.2, 0.0),
    ])
    func strengthObject(strength: Double, expected: Double) {
        #expect(DisplayAppearance.parseNightShift(["strength": strength])
            == .init(on: true, strength: expected))
    }
}
