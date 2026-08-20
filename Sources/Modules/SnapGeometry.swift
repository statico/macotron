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

    static let slotAliases: [String: String] = [
        "left": "left", "right": "right", "top": "top", "bottom": "bottom",
        "tl": "tl", "tr": "tr", "bl": "bl", "br": "br",
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
}
