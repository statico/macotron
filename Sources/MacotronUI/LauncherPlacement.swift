import AppKit
import CoreGraphics

enum LauncherPlacement {
    static let minHeight: CGFloat = 56
    /// Inset from the top of the visible frame when the launcher opens.
    static let topFraction: CGFloat = 0.18
    static let phi: CGFloat = (1 + CGFloat(5).squareRoot()) / 2
    static let margin: CGFloat = 12

    /// Visible frame of the display under the mouse, then main, then first.
    static func currentVisible() -> CGRect {
        let mouse = NSEvent.mouseLocation
        let underMouse = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
        return (underMouse ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    }

    /// Max height: 18% top inset + 18% bottom inset.
    static func maxHeight(in visible: CGRect) -> CGFloat {
        max(minHeight, visible.height * (1 - 2 * topFraction))
    }

    /// Central column: `1 / φ²` of the visible width (~38%).
    static func width(in visible: CGRect) -> CGFloat {
        let column = visible.width / (phi * phi)
        let cap = max(minHeight, visible.width - 2 * margin)
        return min(column, cap)
    }

    /// Frame for the launcher inside `visible`. Open (`pinTop` nil) sits `topFraction`
    /// below the top. Pass the current maxY when resizing so the search field stays
    /// put and the list grows downward, up to 64% of the visible height.
    static func frame(height: CGFloat, visible: CGRect, pinTop: CGFloat?) -> CGRect {
        let inset = visible.height * topFraction
        let maxH = maxHeight(in: visible)
        let w = width(in: visible)
        let h = min(max(height, minHeight), maxH)
        let x = visible.midX - w / 2
        let bandTop = visible.maxY - inset
        let desiredTop = pinTop ?? bandTop
        let top = min(desiredTop, bandTop)
        var y = top - h
        let minY = visible.minY + inset
        if y < minY {
            y = minY
        }
        return CGRect(x: x, y: y, width: w, height: h)
    }
}
