import CoreGraphics

enum LauncherPlacement {
    static let width: CGFloat = 720
    static let minHeight: CGFloat = 56
    static let maxHeight: CGFloat = 520
    static let margin: CGFloat = 12

    /// Frame for the launcher inside `visible`. Open (`pinTop` nil) is vertically
    /// centered. Pass the current maxY when resizing so the search field stays put
    /// and the list grows downward.
    static func frame(height: CGFloat, visible: CGRect, pinTop: CGFloat?) -> CGRect {
        let maxH = min(maxHeight, max(minHeight, visible.height - 2 * margin))
        let h = min(max(height, minHeight), maxH)
        let x = visible.midX - width / 2
        let desiredTop = pinTop ?? (visible.midY + h / 2)
        let top = min(desiredTop, visible.maxY - margin)
        var y = top - h
        if y < visible.minY + margin {
            y = visible.minY + margin
        }
        return CGRect(x: x, y: y, width: width, height: h)
    }
}
