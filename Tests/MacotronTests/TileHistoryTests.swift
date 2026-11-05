import CoreGraphics
import Testing
@testable import Modules

@Suite("TileHistory")
struct TileHistoryTests {
    let free = CGRect(x: 300, y: 200, width: 640, height: 480)
    let left = CGRect(x: 0, y: 25, width: 720, height: 875)
    let right = CGRect(x: 720, y: 25, width: 720, height: 875)

    @Test("the first tile records where the window was")
    func firstTile() {
        var h = TileHistory()
        h.tiled(1, from: free, to: left)
        #expect(h.entry(1, at: left) == .init(before: free, placed: left))
    }

    @Test("a second tile keeps the original place")
    func secondTile() {
        var h = TileHistory()
        h.tiled(1, from: free, to: left)
        h.tiled(1, from: left, to: right)
        #expect(h.entry(1, at: right)?.before == free)
    }

    @Test("a manual move and a new tile record the new place")
    func manualMove() {
        var h = TileHistory()
        h.tiled(1, from: free, to: left)
        let moved = CGRect(x: 500, y: 300, width: 720, height: 875)
        h.tiled(1, from: moved, to: right)
        #expect(h.entry(1, at: right)?.before == moved)
    }

    @Test("a window no longer at its tile has nothing to restore")
    func movedAway() {
        var h = TileHistory()
        h.tiled(1, from: free, to: left)
        #expect(h.entry(1, at: left.offsetBy(dx: 40, dy: 0)) == nil)
        #expect(h.entry(2, at: left) == nil)
    }

    @Test("the oldest window drops out past the limit")
    func limit() {
        var h = TileHistory()
        for id in 0...CGWindowID(TileHistory.limit) { h.tiled(id, from: free, to: left) }
        #expect(h.entry(0, at: left) == nil)
        #expect(h.entry(1, at: left) != nil)
    }
}

@Suite("DragRestore")
struct DragRestoreTests {
    let tile = CGRect(x: 0, y: 25, width: 1000, height: 875)
    let size = CGSize(width: 400, height: 300)

    @Test("a grab near the left edge keeps the left edge")
    func leftGrab() {
        let f = DragRestore.frame(from: tile, size: size, cursor: CGPoint(x: 60, y: 35))
        #expect(f == CGRect(x: 0, y: 25, width: 400, height: 300))
    }

    @Test("a grab near the right edge of a wide tile keeps the cursor on the window")
    func rightGrab() {
        let f = DragRestore.frame(from: tile, size: size, cursor: CGPoint(x: 900, y: 35))
        #expect(f.minX == 540)
        #expect(f.minX < 900 && 900 < f.maxX)
    }

    @Test("a restore size wider than the tile does not shift")
    func biggerRestore() {
        let small = CGRect(x: 100, y: 25, width: 300, height: 875)
        let f = DragRestore.frame(from: small, size: CGSize(width: 800, height: 600), cursor: CGPoint(x: 380, y: 35))
        #expect(f.minX == 100)
    }
}
