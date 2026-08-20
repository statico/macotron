import Testing
@testable import MacotronEngine
import CoreGraphics
import Carbon.HIToolbox

@Suite("CarbonHotKeys")
struct CarbonHotKeysTests {
    @Test("maps CGEvent modifier flags to Carbon hotkey bits")
    func carbonModifiers() {
        #expect(CarbonHotKeys.modifiers(from: .maskCommand) == UInt32(cmdKey))
        #expect(CarbonHotKeys.modifiers(from: .maskShift) == UInt32(shiftKey))
        #expect(CarbonHotKeys.modifiers(from: .maskControl) == UInt32(controlKey))
        #expect(CarbonHotKeys.modifiers(from: .maskAlternate) == UInt32(optionKey))
        let combo: CGEventFlags = [.maskCommand, .maskShift]
        #expect(CarbonHotKeys.modifiers(from: combo) == UInt32(cmdKey | shiftKey))
        #expect(CarbonHotKeys.modifiers(from: []) == 0)
    }
}
