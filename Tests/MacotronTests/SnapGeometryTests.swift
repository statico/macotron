import CoreGraphics
import Testing
@testable import Modules

@Suite("SnapGeometry")
struct SnapGeometryTests {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)

    @Test("canonical slots pass through, other spellings fold in")
    func canonicalSlot() {
        for slot in ["left", "right", "top", "bottom", "tl", "tr", "bl", "br"] {
            #expect(SnapGeometry.canonicalSlot(slot) == slot)
            #expect(SnapGeometry.canonicalSlot(slot.uppercased()) == slot)
        }
        #expect(SnapGeometry.canonicalSlot("Top-Left") == "tl")
        #expect(SnapGeometry.canonicalSlot("nw") == "tl")
        #expect(SnapGeometry.canonicalSlot("se") == "br")
        #expect(SnapGeometry.canonicalSlot("maximize") == "top")
        #expect(SnapGeometry.canonicalSlot("nonsense") == "nonsense")
    }

    @Test("corners beat edges")
    func corners() {
        #expect(SnapGeometry.slot(at: CGPoint(x: 10, y: 790), screen: screen, corner: 48, threshold: 20) == "tl")
        #expect(SnapGeometry.slot(at: CGPoint(x: 990, y: 790), screen: screen, corner: 48, threshold: 20) == "tr")
        #expect(SnapGeometry.slot(at: CGPoint(x: 10, y: 10), screen: screen, corner: 48, threshold: 20) == "bl")
        #expect(SnapGeometry.slot(at: CGPoint(x: 990, y: 10), screen: screen, corner: 48, threshold: 20) == "br")
    }

    @Test("edges away from corners")
    func edges() {
        #expect(SnapGeometry.slot(at: CGPoint(x: 5, y: 400), screen: screen, corner: 48, threshold: 20) == "left")
        #expect(SnapGeometry.slot(at: CGPoint(x: 995, y: 400), screen: screen, corner: 48, threshold: 20) == "right")
        #expect(SnapGeometry.slot(at: CGPoint(x: 500, y: 795), screen: screen, corner: 48, threshold: 20) == "top")
        #expect(SnapGeometry.slot(at: CGPoint(x: 500, y: 5), screen: screen, corner: 48, threshold: 20) == "bottom")
    }

    @Test("center is not a slot")
    func center() {
        #expect(SnapGeometry.slot(at: CGPoint(x: 500, y: 400), screen: screen, corner: 48, threshold: 20) == nil)
    }

    @Test("a point just inside a visible top-left is a corner")
    func visibleTopLeft() {
        let visible = CGRect(x: 0, y: 0, width: 1000, height: 764)
        #expect(SnapGeometry.slot(at: CGPoint(x: 12, y: 760), screen: visible, corner: 80, threshold: 20) == "tl")
        #expect(SnapGeometry.slot(at: CGPoint(x: 500, y: 760), screen: visible, corner: 80, threshold: 20) == "top")
    }

    @Test("top-origin left half is the Cocoa left half")
    func cocoaLeft() {
        let rect = SnapGeometry.cocoaRect(
            zone: SnapZone(x: 0, y: 0, w: 0.5, h: 1),
            visible: screen,
            gap: 0
        )
        #expect(rect == CGRect(x: 0, y: 0, width: 500, height: 800))
    }

    @Test("top-origin top half is the Cocoa upper half")
    func cocoaTop() {
        let rect = SnapGeometry.cocoaRect(
            zone: SnapZone(x: 0, y: 0, w: 1, h: 0.5),
            visible: screen,
            gap: 0
        )
        #expect(rect == CGRect(x: 0, y: 400, width: 1000, height: 400))
    }

    @Test("aliases map to slots")
    func aliases() {
        let zones = SnapGeometry.parseZones([
            "top-left": ["x": 0, "y": 0, "w": 0.5, "h": 0.5],
        ])
        #expect(zones["tl"] == SnapZone(x: 0, y: 0, w: 0.5, h: 0.5))
    }

    @Test("shift selects the shift map")
    func shiftMap() {
        let halves = SnapGeometry.defaultZones
        let thirds = ["left": SnapZone(x: 0, y: 0, w: 1.0 / 3, h: 1)]
        let active = SnapGeometry.activeZones(
            default: halves,
            modifiers: [(flags: .maskShift, zones: thirds)],
            held: .maskShift
        )
        #expect(active["left"]?.w == 1.0 / 3)
    }

    @Test("cmd+shift beats shift")
    func moreSpecificModifier() {
        let shift = ["left": SnapZone(x: 0, y: 0, w: 1 / 3, h: 1)]
        let both = ["left": SnapZone(x: 0, y: 0, w: 0.25, h: 1)]
        let active = SnapGeometry.activeZones(
            default: SnapGeometry.defaultZones,
            modifiers: [
                (flags: .maskShift, zones: shift),
                (flags: [.maskCommand, .maskShift], zones: both),
            ],
            held: [.maskCommand, .maskShift]
        )
        #expect(active["left"]?.w == 0.25)
    }

    @Test("no modifier keeps the default map")
    func defaultMap() {
        let thirds = ["left": SnapZone(x: 0, y: 0, w: 1.0 / 3, h: 1)]
        let active = SnapGeometry.activeZones(
            default: SnapGeometry.defaultZones,
            modifiers: [(flags: .maskShift, zones: thirds)],
            held: []
        )
        #expect(active["left"]?.w == 0.5)
    }

    // MARK: - placeRefused (top-left coordinates, menu bar 25pt)

    let visible = CGRect(x: 0, y: 25, width: 1000, height: 775)

    func tile(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: visible.minX + x * visible.width, y: visible.minY + y * visible.height,
               width: w * visible.width, height: h * visible.height)
    }

    @Test("a too-wide half stays flush with its screen edge")
    func refusedHalves() {
        let size = CGSize(width: 700, height: 775)
        #expect(SnapGeometry.placeRefused(size: size, tile: tile(0, 0, 0.5, 1), visible: visible).x == 0)
        #expect(SnapGeometry.placeRefused(size: size, tile: tile(0.5, 0, 0.5, 1), visible: visible).x == 300)
    }

    @Test("a window that refused to grow hugs the edge and centres on the free axis")
    func refusedToGrow() {
        let p = SnapGeometry.placeRefused(size: CGSize(width: 300, height: 400), tile: tile(0.5, 0, 0.5, 1), visible: visible)
        #expect(p == CGPoint(x: 700, y: 212.5))
    }

    @Test("a tile equally far from both edges centres the window")
    func refusedCenterThird() {
        let p = SnapGeometry.placeRefused(size: CGSize(width: 434, height: 775), tile: tile(1.0 / 3, 0, 1.0 / 3, 1), visible: visible)
        #expect(abs(p.x - 283) < 0.01)
    }

    @Test("a window larger than the screen pins to the top-left, below the menu bar")
    func refusedHuge() {
        let p = SnapGeometry.placeRefused(size: CGSize(width: 1200, height: 900), tile: tile(0, 0, 1, 1), visible: visible)
        #expect(p == CGPoint(x: 0, y: 25))
    }

    @Test("a refused bottom-right quarter stays fully on screen")
    func refusedQuarter() {
        let p = SnapGeometry.placeRefused(size: CGSize(width: 600, height: 500), tile: tile(0.5, 0.5, 0.5, 0.5), visible: visible)
        #expect(p == CGPoint(x: 400, y: 300))
    }
}
