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

    @Test("open at max height starts at the 18 percent band")
    func openMaxHeight() {
        let maxH = LauncherPlacement.maxHeight(in: visible)
        let f = LauncherPlacement.frame(height: maxH, visible: visible, pinTop: nil)
        let inset = visible.height * LauncherPlacement.topFraction
        #expect(abs(f.height - maxH) < 0.5)
        #expect(abs(f.maxY - (visible.maxY - inset)) < 0.5)
        #expect(f.minY >= visible.minY + inset - 0.5)
    }

    @Test("max height caps at 500 on a tall display")
    func maxHeightCap() {
        #expect(LauncherPlacement.maxHeight(in: visible) == LauncherPlacement.maxPanelHeight)
        let ultrawide = CGRect(x: 0, y: 0, width: 3440, height: 1410)
        #expect(LauncherPlacement.maxHeight(in: ultrawide) == LauncherPlacement.maxPanelHeight)
    }

    @Test("short displays fall back to the 18 percent band")
    func maxHeightShortDisplay() {
        let short = CGRect(x: 0, y: 0, width: 1280, height: 600)
        let band = short.height * (1 - 2 * LauncherPlacement.topFraction)
        #expect(band < LauncherPlacement.maxPanelHeight)
        #expect(abs(LauncherPlacement.maxHeight(in: short) - band) < 0.5)
    }

    @Test("width is 750 unless the display is narrower")
    func maxWidth() {
        let w = LauncherPlacement.width(in: visible)
        #expect(w == LauncherPlacement.maxWidth)
        let narrow = CGRect(x: 0, y: 0, width: 400, height: 300)
        let nw = LauncherPlacement.width(in: narrow)
        #expect(nw == 400 - 2 * LauncherPlacement.margin)
    }

    @Test("tall content clamps to the max height inside the band")
    func clamp() {
        let f = LauncherPlacement.frame(height: 5000, visible: visible, pinTop: nil)
        let inset = visible.height * LauncherPlacement.topFraction
        #expect(abs(f.height - LauncherPlacement.maxHeight(in: visible)) < 0.5)
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

    @Test("panel height grows with rows then caps at max")
    func panelHeight() {
        let empty = LauncherPlacement.panelHeight(
            resultCount: 0, queryEmpty: true, argumentCount: nil,
            textScale: 1, visible: visible
        )
        #expect(empty == 48)
        #expect(empty == LauncherPlacement.minHeight)
        #expect(LauncherPlacement.searchBarHeight(showingList: false) == empty)
        #expect(LauncherPlacement.searchBarHeight(showingList: true) == 52)
        #expect(LauncherPlacement.searchHeight == 52)

        let one = LauncherPlacement.panelHeight(
            resultCount: 1, queryEmpty: false, argumentCount: nil,
            textScale: 1, visible: visible
        )
        let two = LauncherPlacement.panelHeight(
            resultCount: 2, queryEmpty: false, argumentCount: nil,
            textScale: 1, visible: visible
        )
        #expect(two - one == LauncherPlacement.rowHeight(scale: 1) + LauncherPlacement.rowSpacing)

        let many = LauncherPlacement.panelHeight(
            resultCount: 50, queryEmpty: false, argumentCount: nil,
            textScale: 1, visible: visible
        )
        #expect(abs(many - LauncherPlacement.maxHeight(in: visible)) < 0.5)
    }

    /// Ground truth measured from the live scroll view's document height at
    /// textScale 1: 1 row 44pt, 2 rows 81pt, 17 rows 636pt, 20 rows 747pt.
    @Test("list height matches the real scroll view content")
    func listHeightMatchesMeasured() {
        #expect(LauncherPlacement.listHeight(count: 0, scale: 1) == 0)
        #expect(LauncherPlacement.listHeight(count: 1, scale: 1) == 44)
        #expect(LauncherPlacement.listHeight(count: 2, scale: 1) == 81)
        #expect(LauncherPlacement.listHeight(count: 17, scale: 1) == 636)
        #expect(LauncherPlacement.listHeight(count: 20, scale: 1) == 747)
    }

    /// Below the cap the window must be the exact sum of the sections, or the
    /// list scrolls even though everything fits.
    @Test("panel height leaves the list exactly enough room")
    func panelHeightIsExact() {
        for scale in [0.8, 1.0, 1.2] as [CGFloat] {
            for count in 1...5 {
                let height = LauncherPlacement.panelHeight(
                    resultCount: count, queryEmpty: false, argumentCount: nil,
                    textScale: scale, visible: visible
                )
                let sections = LauncherPlacement.searchHeight
                    + LauncherPlacement.dividerHeight
                    + LauncherPlacement.listHeight(count: count, scale: scale)
                    + LauncherPlacement.dividerHeight
                    + LauncherPlacement.footerHeight(scale: scale)
                #expect(height < LauncherPlacement.maxHeight(in: visible))
                #expect(abs(height - sections) < 0.001)
            }
        }
    }
}
