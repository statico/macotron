// HexColor.swift — shared #RGB / #RRGGBB parsing for plugin-supplied colors
import AppKit

public enum HexColor {
    /// Expects an already-trimmed string. Callers keep their own named-color
    /// tables, which accept different names.
    public static func parse(_ value: String) -> NSColor? {
        guard value.hasPrefix("#") else { return nil }
        var hex = String(value.dropFirst())
        if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
        guard hex.count == 6, let n = UInt32(hex, radix: 16) else { return nil }
        return NSColor(
            srgbRed: CGFloat((n >> 16) & 0xff) / 255,
            green: CGFloat((n >> 8) & 0xff) / 255,
            blue: CGFloat(n & 0xff) / 255,
            alpha: 1
        )
    }
}
