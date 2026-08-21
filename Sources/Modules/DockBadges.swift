import Foundation

enum DockBadges {
    static func badgeString(_ attributes: [String: Any]) -> String {
        for key in ["AXStatusLabel", "AXBadgeDescription"] {
            if let s = string(attributes[key]), !s.isEmpty { return s }
        }
        return ""
    }

    static func parse(_ tiles: [[String: Any]]) -> [[String: Any]] {
        tiles.compactMap { tile in
            let badge = badgeString(tile["attributes"] as? [String: Any] ?? [:])
            guard !badge.isEmpty else { return nil }
            var row: [String: Any] = [
                "app": tile["title"] as? String ?? "",
                "badge": badge,
            ]
            if let bid = tile["bundleID"] as? String, !bid.isEmpty {
                row["bundleID"] = bid
            }
            return row
        }
    }

    private static func string(_ value: Any?) -> String? {
        switch value {
        case let s as String: return s
        case let i as Int: return String(i)
        case let n as NSNumber: return n.stringValue
        default: return nil
        }
    }
}
