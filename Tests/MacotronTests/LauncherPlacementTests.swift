import CoreGraphics
import Testing
@testable import MacotronUI

@Suite("LauncherPlacement")
struct LauncherPlacementTests {
    let visible = CGRect(x: 0, y: 80, width: 1440, height: 820)

    @Test("open hangs 18 percent from the top")
    func open() {
        let f = LauncherPlacement.frame(height: 56, visible: visible, pinTop: nil)
        let expectedTop = visible.maxY - visible.height * LauncherPlacement.topFraction
        #expect(abs(f.maxY - expectedTop) < 0.5)
        #expect(f.height == 56)
        #expect(abs(f.midX - visible.midX) < 0.5)
        #expect(f.midY != visible.midY)
    }

    @Test("resize pins the top and grows down")
    func pinTop() {
        let open = LauncherPlacement.frame(height: 56, visible: visible, pinTop: nil)
        let f = LauncherPlacement.frame(height: 300, visible: visible, pinTop: open.maxY)
        #expect(abs(f.maxY - open.maxY) < 0.5)
        #expect(f.height == 300)
    }

    @Test("max height is the visible frame minus 18 percent top and bottom")
    func maxHeightBand() {
        let maxH = LauncherPlacement.maxHeight(in: visible)
        #expect(abs(maxH - visible.height * (1 - 2 * LauncherPlacement.topFraction)) < 0.5)
    }

    @Test("width is the golden central column of the visible frame")
    func goldenWidth() {
        let w = LauncherPlacement.width(in: visible)
        let expected = visible.width / (LauncherPlacement.phi * LauncherPlacement.phi)
        #expect(abs(w - expected) < 0.5)
        #expect(w < visible.width * 0.5)
    }

    @Test("tall content stays in the 18 percent band")
    func clamp() {
        let f = LauncherPlacement.frame(height: 5000, visible: visible, pinTop: nil)
        let inset = visible.height * LauncherPlacement.topFraction
        #expect(abs(f.height - visible.height * (1 - 2 * LauncherPlacement.topFraction)) < 0.5)
        #expect(f.minY >= visible.minY + inset - 0.5)
        #expect(f.maxY <= visible.maxY - inset + 0.5)
    }

    @Test("tiny displays still fit inside the visible frame")
    func tiny() {
        let tiny = CGRect(x: 0, y: 0, width: 800, height: 200)
        let f = LauncherPlacement.frame(height: 520, visible: tiny, pinTop: nil)
        #expect(f.maxY <= tiny.maxY)
        #expect(f.minY >= tiny.minY)
        #expect(f.height <= tiny.height)
        #expect(f.width <= tiny.width)
    }
}
