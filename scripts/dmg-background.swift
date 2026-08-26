// Draws the picture behind the icons in the mounted DMG: the app on the left,
// an arrow, the Applications alias on the right. Run by `make dmg`, which turns
// the two sizes into one multi-resolution TIFF for Finder.
//
// usage: swift scripts/dmg-background.swift <1x.png> <2x.png>
import AppKit

let W = 640.0, H = 400.0
let iconY = 228.0          // from the top, where Finder is told to put the icons
let leftX = 168.0, rightX = 472.0

func rgb(_ hex: UInt32, _ alpha: Double = 1) -> NSColor {
    NSColor(srgbRed: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255, alpha: alpha)
}

// Nord, the same palette as the site and the banner.
let base = rgb(0x3B4252), deep = rgb(0x2E3440)
let accent = rgb(0x88C0D0), ink = rgb(0xECEFF4), muted = rgb(0x9AA6BA)

func label(_ text: String, _ size: Double, _ weight: NSFont.Weight,
           _ color: NSColor, kern: Double, top: Double) {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    NSAttributedString(string: text, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color, .kern: kern, .paragraphStyle: style,
    ]).draw(in: NSRect(x: 0, y: H - top - size * 1.4, width: W, height: size * 1.4))
}

// A frosted plate under each icon. Finder paints item names in the viewer's
// text color, so neither a black nor a white name is readable against a flat
// dark picture: a mid tone behind both cells works in either appearance.
func plate(x: Double, y: Double) {
    let box = NSRect(x: x - 102, y: H - y - 86, width: 204, height: 196)
    let path = NSBezierPath(roundedRect: box, xRadius: 24, yRadius: 24)
    NSColor(white: 1, alpha: 0.24).setFill()
    path.fill()
    NSColor(white: 1, alpha: 0.16).setStroke()
    path.lineWidth = 1
    path.stroke()
}

func arrow() {
    let y = H - iconY, x0 = 282.0, x1 = 358.0, head = 30.0
    let path = NSBezierPath()
    path.move(to: NSPoint(x: x0, y: y + 9))
    path.line(to: NSPoint(x: x1 - head, y: y + 9))
    path.line(to: NSPoint(x: x1 - head, y: y + 23))
    path.line(to: NSPoint(x: x1, y: y))
    path.line(to: NSPoint(x: x1 - head, y: y - 23))
    path.line(to: NSPoint(x: x1 - head, y: y - 9))
    path.line(to: NSPoint(x: x0, y: y - 9))
    path.close()
    let shadow = NSShadow()
    shadow.shadowColor = accent.withAlphaComponent(0.9)
    shadow.shadowBlurRadius = 22
    shadow.shadowOffset = .zero
    shadow.set()
    accent.setFill()
    path.fill()
}

func render(scale: Int, to path: String) {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(W) * scale, pixelsHigh: Int(H) * scale,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: W, height: H)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGradient(colors: [base, deep])!.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -90)
    plate(x: leftX, y: iconY)
    plate(x: rightX, y: iconY)
    label("MACOTRON", 27, .heavy, ink, kern: 5, top: 52)
    label("AI-powered macOS automation", 12, .medium, muted, kern: 1.5, top: 92)
    arrow()
    label("Drag the app onto Applications, then launch it", 12, .regular,
          muted, kern: 0, top: H - 62)
    NSGraphicsContext.current?.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: path))
}

let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write(Data("usage: dmg-background.swift <1x.png> <2x.png>\n".utf8))
    exit(1)
}
render(scale: 1, to: args[1])
render(scale: 2, to: args[2])
