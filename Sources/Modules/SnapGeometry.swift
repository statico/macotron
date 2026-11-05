// SnapGeometry.swift — edge slots, zone maps, and Cocoa preview rects
import CoreGraphics

struct SnapZone: Equatable {
    var x: CGFloat
    var y: CGFloat
    var w: CGFloat
    var h: CGFloat
}

enum SnapGeometry {
    static let defaultZones: [String: SnapZone] = [
        "left": SnapZone(x: 0, y: 0, w: 0.5, h: 1),
        "right": SnapZone(x: 0.5, y: 0, w: 0.5, h: 1),
        "top": SnapZone(x: 0, y: 0, w: 1, h: 1),
        "bottom": SnapZone(x: 0, y: 0.5, w: 1, h: 0.5),
        "tl": SnapZone(x: 0, y: 0, w: 0.5, h: 0.5),
        "tr": SnapZone(x: 0.5, y: 0, w: 0.5, h: 0.5),
        "bl": SnapZone(x: 0, y: 0.5, w: 0.5, h: 0.5),
        "br": SnapZone(x: 0.5, y: 0.5, w: 0.5, h: 0.5),
    ]

    /// Only the spellings that differ from the canonical slot; `canonicalSlot`
    /// passes anything else straight through.
    static let slotAliases: [String: String] = [
        "top-left": "tl", "topleft": "tl", "nw": "tl",
        "top-right": "tr", "topright": "tr", "ne": "tr",
        "bottom-left": "bl", "bottomleft": "bl", "sw": "bl",
        "bottom-right": "br", "bottomright": "br", "se": "br",
        "maximize": "top", "full": "top",
    ]

    static func canonicalSlot(_ raw: String) -> String {
        slotAliases[raw.lowercased()] ?? raw.lowercased()
    }

    static func parseZones(_ dict: [String: Any]) -> [String: SnapZone] {
        var out: [String: SnapZone] = [:]
        for (rawKey, raw) in dict {
            guard let frame = raw as? [String: Any] else { continue }
            func num(_ k: String) -> CGFloat? {
                if let d = frame[k] as? Double { return CGFloat(d) }
                if let i = frame[k] as? Int { return CGFloat(i) }
                return nil
            }
            guard let x = num("x"), let y = num("y"), let w = num("w"), let h = num("h") else { continue }
            out[canonicalSlot(rawKey)] = SnapZone(x: x, y: y, w: w, h: h)
        }
        return out
    }

    static func parseModifierFlags(_ spec: String) -> CGEventFlags {
        EventPost.modifierFlags(
            spec.lowercased().split(separator: "+").map { String($0.trimmingCharacters(in: .whitespaces)) }
        )
    }

    static func parseModifierSets(_ dict: [String: Any]) -> [(flags: CGEventFlags, zones: [String: SnapZone])] {
        dict.compactMap { key, raw in
            guard let nested = raw as? [String: Any] else { return nil }
            let flags = parseModifierFlags(key)
            guard !flags.isEmpty else { return nil }
            let zones = parseZones(nested)
            guard !zones.isEmpty else { return nil }
            return (flags, zones)
        }
    }

    static func activeZones(
        default defaultZones: [String: SnapZone],
        modifiers: [(flags: CGEventFlags, zones: [String: SnapZone])],
        held: CGEventFlags
    ) -> [String: SnapZone] {
        let mask: CGEventFlags = [.maskCommand, .maskShift, .maskControl, .maskAlternate]
        let held = held.intersection(mask)
        let matches = modifiers.filter { set in
            let need = set.flags.intersection(mask)
            return !need.isEmpty && held.contains(need)
        }
        guard let best = matches.max(by: { a, b in
            let ac = a.flags.intersection(mask).rawValue.nonzeroBitCount
            let bc = b.flags.intersection(mask).rawValue.nonzeroBitCount
            if ac != bc { return ac < bc }
            let aExact = a.flags.intersection(mask) == held
            let bExact = b.flags.intersection(mask) == held
            if aExact != bExact { return bExact }
            return false
        }) else {
            return defaultZones
        }
        return best.zones
    }

    /// `screen` and `point` are Cocoa (`NSEvent.mouseLocation`).
    static func slot(at point: CGPoint, screen: CGRect, corner: CGFloat, threshold: CGFloat) -> String? {
        let c = corner
        let t = threshold
        let leftC = point.x <= screen.minX + c
        let rightC = point.x >= screen.maxX - c
        let bottomC = point.y <= screen.minY + c
        let topC = point.y >= screen.maxY - c
        if leftC && topC { return "tl" }
        if rightC && topC { return "tr" }
        if leftC && bottomC { return "bl" }
        if rightC && bottomC { return "br" }
        if point.x <= screen.minX + t { return "left" }
        if point.x >= screen.maxX - t { return "right" }
        if point.y >= screen.maxY - t { return "top" }
        if point.y <= screen.minY + t { return "bottom" }
        return nil
    }

    /// Zone fractions are top-origin (same as `moveToFraction`). `visible` is Cocoa.
    static func cocoaRect(zone: SnapZone, visible: CGRect, gap: CGFloat) -> CGRect {
        let g = gap
        let width = max(1, zone.w * visible.width - 2 * g)
        let height = max(1, zone.h * visible.height - 2 * g)
        let x = visible.minX + zone.x * visible.width + g
        let y = visible.minY + (1 - zone.y - zone.h) * visible.height + g
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Where to put a window that kept its own size instead of the tile's.
    /// Each axis stays flush with the tile side nearer the screen edge, so a
    /// too-wide left half still hugs the left edge and spills toward the
    /// middle; a tile equally far from both edges centres the window. The
    /// result never leaves `visible`. All rects share one coordinate space.
    static func placeRefused(size: CGSize, tile: CGRect, visible: CGRect) -> CGPoint {
        func axis(_ length: CGFloat, _ tileMin: CGFloat, _ tileMax: CGFloat, _ visMin: CGFloat, _ visMax: CGFloat) -> CGFloat {
            let toMin = tileMin - visMin
            let toMax = visMax - tileMax
            let origin: CGFloat
            if abs(toMin - toMax) < 1 {
                origin = (tileMin + tileMax - length) / 2
            } else if toMin < toMax {
                origin = tileMin
            } else {
                origin = tileMax - length
            }
            // Larger than the screen: pin to the top-left, never above the menu bar.
            return max(visMin, min(origin, visMax - length))
        }
        return CGPoint(
            x: axis(size.width, tile.minX, tile.maxX, visible.minX, visible.maxX),
            y: axis(size.height, tile.minY, tile.maxY, visible.minY, visible.maxY)
        )
    }
}

/// Where each tiled window sat before its first tile, so it can go back.
/// Keyed by window number. A second tile keeps the first `before`; a window
/// moved by hand since its last tile starts a new entry.
struct TileHistory {
    struct Entry: Equatable {
        var before: CGRect
        var placed: CGRect
    }

    /// Apps settle a few points off the requested frame; Electron can settle late.
    static let slack: CGFloat = 8
    // ponytail: fixed cap with linear eviction, prune on window close if it ever matters.
    static let limit = 300

    private var entries: [CGWindowID: Entry] = [:]
    private var order: [CGWindowID] = []

    static func same(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= slack && abs(a.minY - b.minY) <= slack
            && abs(a.width - b.width) <= slack && abs(a.height - b.height) <= slack
    }

    mutating func tiled(_ id: CGWindowID, from: CGRect, to: CGRect) {
        if let entry = entries[id], Self.same(from, entry.placed) {
            entries[id]?.placed = to
        } else {
            entries[id] = Entry(before: from, placed: to)
        }
        order.removeAll { $0 == id }
        order.append(id)
        if order.count > Self.limit { entries[order.removeFirst()] = nil }
    }

    /// The entry, only while the window still sits where it was tiled.
    func entry(_ id: CGWindowID, at frame: CGRect) -> Entry? {
        guard let entry = entries[id], Self.same(frame, entry.placed) else { return nil }
        return entry
    }

    mutating func remove(_ id: CGWindowID) {
        entries[id] = nil
        order.removeAll { $0 == id }
    }
}

enum DragRestore {
    /// A tiled window dragged out takes back `size`. The top edge stays put;
    /// the left edge stays put too unless the grab point would fall off the
    /// narrower window, in which case it keeps its place along the width.
    /// Top-left coordinates.
    static func frame(from frame: CGRect, size: CGSize, cursor: CGPoint) -> CGRect {
        let grab = cursor.x - frame.minX
        var x = frame.minX
        if grab > size.width - 20 {
            x = cursor.x - size.width * (grab / frame.width)
        }
        return CGRect(origin: CGPoint(x: x, y: frame.minY), size: size)
    }
}
