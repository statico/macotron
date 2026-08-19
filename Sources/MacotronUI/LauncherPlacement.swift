import AppKit
import CoreGraphics

enum LauncherPlacement {
    static let minHeight: CGFloat = 56
    /// Inset from the top of the visible frame when the launcher opens.
    static let topFraction: CGFloat = 0.18
    static let maxWidth: CGFloat = 750
    static let maxPanelHeight: CGFloat = 500
    static let margin: CGFloat = 12

    /// Every section below has an explicit height in `LauncherView`, so the
    /// window height is exact rather than a guess at SwiftUI's own layout.
    /// Predicting it from font metrics is what left the list scrolling by a few
    /// points no matter how the row estimate was tuned.
    static let searchHeight: CGFloat = 52
    static let dividerHeight: CGFloat = 1
    /// `VStack(spacing:)` between result rows.
    static let rowSpacing: CGFloat = 1
    /// Vertical padding around the results list, inside the scroll view.
    static let listPadding: CGFloat = 8

    /// Visible frame of the display under the mouse, then main, then first.
    static func currentVisible() -> CGRect {
        let mouse = NSEvent.mouseLocation
        let underMouse = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
        return (underMouse ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    }

    /// Max height: `maxPanelHeight`, or the 18% band on a short display.
    static func maxHeight(in visible: CGRect) -> CGFloat {
        min(maxPanelHeight, max(minHeight, visible.height * (1 - 2 * topFraction)))
    }

    /// 750pt, or the visible width minus side margins if the display is narrower.
    static func width(in visible: CGRect) -> CGFloat {
        min(maxWidth, max(minHeight, visible.width - 2 * margin))
    }

    static func rowHeight(scale: CGFloat) -> CGFloat {
        20 * scale + 16
    }

    /// Footer holding the shortcut hints. Tall enough for the key glyph boxes at
    /// every supported text scale.
    static func footerHeight(scale: CGFloat) -> CGFloat {
        18 * scale + 16
    }

    /// The "No results" placeholder.
    static func emptyStateHeight(scale: CGFloat) -> CGFloat {
        16 * scale + 48
    }

    /// Height of the scroll view's content for `count` rows.
    static func listHeight(count: Int, scale: CGFloat) -> CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(count) * rowHeight(scale: scale)
            + CGFloat(count - 1) * rowSpacing
            + listPadding
    }

    /// Window height: search + results + footer, capped at `maxHeight`.
    /// Extra rows scroll inside the list; they must not grow the SwiftUI host.
    static func panelHeight(
        resultCount: Int,
        queryEmpty: Bool,
        argumentCount: Int?,
        textScale: CGFloat,
        visible: CGRect
    ) -> CGFloat {
        let maxH = maxHeight(in: visible)
        if let n = argumentCount {
            return min(maxH, max(minHeight, 48 + CGFloat(n) * 36))
        }
        if queryEmpty && resultCount == 0 {
            return minHeight
        }
        var height = searchHeight + dividerHeight
        if resultCount == 0 {
            height += emptyStateHeight(scale: textScale)
        } else {
            height += listHeight(count: resultCount, scale: textScale)
            height += dividerHeight + footerHeight(scale: textScale)
        }
        return min(maxH, max(minHeight, height))
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
