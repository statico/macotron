import Testing
@testable import Modules

@Suite("DisplayAppearance")
struct DisplayAppearanceTests {
    @Test("setNightShift(true) enables without strength")
    func boolTrue() {
        #expect(DisplayAppearance.parseNightShift(true) == .init(on: true, strength: nil))
    }

    @Test("setNightShift(false) disables")
    func boolFalse() {
        #expect(DisplayAppearance.parseNightShift(false) == .init(on: false, strength: nil))
    }

    @Test("setNightShift({ strength: 0.6 }) enables at 0.6")
    func strengthObject() {
        #expect(DisplayAppearance.parseNightShift(["strength": 0.6]) == .init(on: true, strength: 0.6))
    }

    @Test("strength clamps to 0...1")
    func clamp() {
        #expect(DisplayAppearance.parseNightShift(["strength": 1.5]) == .init(on: true, strength: 1))
        #expect(DisplayAppearance.parseNightShift(["strength": -0.2]) == .init(on: true, strength: 0))
    }
}
