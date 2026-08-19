import CoreGraphics

enum LauncherPlacement {
    static let minHeight: CGFloat = 56
    /// Inset from the top of the visible frame when the launcher opens.
    static let topFraction: CGFloat = 0.18
    /// Landscape golden-rectangle ratio (width / height).
    static let phi: CGFloat = (1 + CGFloat(5).squareRoot()) / 2
    static let margin: CGFloat = 12

    static func maxHeight(in visible: CGRect) -> CGFloat {
        max(minHeight, visible.height * (1 - 2 * topFraction))
    }

    static func width(in visible: CGRect) -> CGFloat {
        let golden = maxHeight(in: visible) * phi
        let cap = max(minHeight, visible.width - 2 * margin)
        return min(golden, cap)
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
