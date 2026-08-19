import CoreGraphics
import Testing
@testable import MacotronUI

@Suite("LauncherPlacement")
struct LauncherPlacementTests {
    let visible = CGRect(x: 0, y: 80, width: 1440, height: 820)

    @Test("open sits just under the menu bar")
    func open() {
        let f = LauncherPlacement.frame(height: 56, visible: visible, pinTop: nil)
        #expect(f.maxY == visible.maxY - 12)
        #expect(f.height == 56)
        #expect(f.midX == visible.midX)
        #expect(f.minY > visible.minY)
    }

    @Test("resize pins the top and grows down")
    func pinTop() {
        let top = visible.maxY - 12
        let f = LauncherPlacement.frame(height: 300, visible: visible, pinTop: top)
        #expect(f.maxY == top)
        #expect(f.height == 300)
    }

    @Test("tall content stays inside the visible frame")
    func clamp() {
        let tiny = CGRect(x: 0, y: 0, width: 800, height: 200)
        let f = LauncherPlacement.frame(height: 520, visible: tiny, pinTop: tiny.maxY)
        #expect(f.maxY <= tiny.maxY - 12)
        #expect(f.minY >= tiny.minY + 12)
        #expect(f.height <= tiny.height - 24)
    }
}
