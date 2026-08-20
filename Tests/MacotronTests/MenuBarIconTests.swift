import AppKit
import Testing
@testable import MacotronUI

@Suite("MenuBarIcon")
struct MenuBarIconTests {
    @Test("tinted glyph is drawn as an original image")
    func tintedIsNotTemplate() {
        #expect(MenuBarIcon.makeImage().isTemplate)
        #expect(!MenuBarIcon.makeImage(tint: .systemRed).isTemplate)
    }
}
