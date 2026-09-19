import CoreGraphics
import Testing
@testable import Modules

@Suite("FocusFlash")
struct FocusFlashTests {
    @Test("the outline sits outside the window on every side")
    func outlineIsOutside() {
        let window = CGRect(x: 100, y: 200, width: 400, height: 300)
        let outline = FocusFlashGeometry.outline(around: window)
        #expect(outline.minX < window.minX)
        #expect(outline.minY < window.minY)
        #expect(outline.maxX > window.maxX)
        #expect(outline.maxY > window.maxY)
        #expect(outline.width == window.width + 2 * FocusFlashGeometry.margin)
        #expect(outline.height == window.height + 2 * FocusFlashGeometry.margin)
    }

    @Test("a normal window keeps the window corner, widened by the margin")
    func cornerOnNormalWindow() {
        let outline = FocusFlashGeometry.outline(around: CGRect(x: 0, y: 0, width: 800, height: 600))
        #expect(FocusFlashGeometry.corner(for: outline) == FocusFlashGeometry.windowCorner + FocusFlashGeometry.margin)
    }

    @Test("the corner never crosses itself on a thin window")
    func cornerClampsOnThinWindow() {
        let outline = FocusFlashGeometry.outline(around: CGRect(x: 0, y: 0, width: 800, height: 14))
        #expect(FocusFlashGeometry.corner(for: outline) == outline.height / 2)
    }
}
