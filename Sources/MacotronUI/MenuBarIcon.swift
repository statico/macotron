// MenuBarIcon.swift — template image for the status item, derived from the app icon
import AppKit

enum MenuBarIcon {
    /// Glyph is authored on a 16x16 grid and scaled to the menu bar's 18pt slot.
    private static let designSize: CGFloat = 16
    private static let pointSize: CGFloat = 18

    static func makeImage(tint: NSColor? = nil) -> NSImage {
        let size = NSSize(width: pointSize, height: pointSize)
        let fill = tint ?? .black
        let image = NSImage(size: size, flipped: true) { _ in
            let path = glyphPath()
            path.transform(using: AffineTransform(scale: pointSize / designSize))
            path.windingRule = .evenOdd
            fill.setFill()
            path.fill()
            return true
        }
        image.isTemplate = tint == nil
        image.accessibilityDescription = "Macotron"
        return image
    }

    private static func glyphPath() -> NSBezierPath {
        let path = NSBezierPath()

        path.move(to: NSPoint(x: 8, y: 1.2))
        path.curve(to: NSPoint(x: 3, y: 6.1),
                   controlPoint1: NSPoint(x: 5.2, y: 1.2), controlPoint2: NSPoint(x: 3, y: 3.3))
        path.curve(to: NSPoint(x: 3.9, y: 11.2),
                   controlPoint1: NSPoint(x: 3, y: 8.1), controlPoint2: NSPoint(x: 3.2, y: 9.8))
        path.curve(to: NSPoint(x: 6.2, y: 13.6),
                   controlPoint1: NSPoint(x: 4.4, y: 12.2), controlPoint2: NSPoint(x: 5.2, y: 13))
        path.curve(to: NSPoint(x: 8, y: 14.5),
                   controlPoint1: NSPoint(x: 6.7, y: 13.9), controlPoint2: NSPoint(x: 7.3, y: 14.2))
        path.curve(to: NSPoint(x: 9.8, y: 13.6),
                   controlPoint1: NSPoint(x: 8.7, y: 14.2), controlPoint2: NSPoint(x: 9.3, y: 13.9))
        path.curve(to: NSPoint(x: 12.1, y: 11.2),
                   controlPoint1: NSPoint(x: 10.8, y: 13), controlPoint2: NSPoint(x: 11.6, y: 12.2))
        path.curve(to: NSPoint(x: 13, y: 6.1),
                   controlPoint1: NSPoint(x: 12.8, y: 9.8), controlPoint2: NSPoint(x: 13, y: 8.1))
        path.curve(to: NSPoint(x: 8, y: 1.2),
                   controlPoint1: NSPoint(x: 13, y: 3.3), controlPoint2: NSPoint(x: 10.8, y: 1.2))
        path.close()

        let monogram: [NSPoint] = [
            NSPoint(x: 5.1, y: 3), NSPoint(x: 6.3, y: 3), NSPoint(x: 8, y: 5.4),
            NSPoint(x: 9.7, y: 3), NSPoint(x: 10.9, y: 3), NSPoint(x: 10.9, y: 7.2),
            NSPoint(x: 9.7, y: 7.2), NSPoint(x: 9.7, y: 5.05), NSPoint(x: 8.5, y: 6.75),
            NSPoint(x: 7.5, y: 6.75), NSPoint(x: 6.3, y: 5.05), NSPoint(x: 6.3, y: 7.2),
            NSPoint(x: 5.1, y: 7.2),
        ]
        path.move(to: monogram[0])
        for point in monogram.dropFirst() {
            path.line(to: point)
        }
        path.close()

        path.appendRect(NSRect(x: 4.4, y: 8.85, width: 2.8, height: 1.35))
        path.appendRect(NSRect(x: 8.8, y: 8.85, width: 2.8, height: 1.35))

        return path
    }
}
