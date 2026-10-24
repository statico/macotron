// Render the demo video's caption PNGs at 1280x800 with SF Pro.
//   swift demo/captions.swift demo/captions.tsv site/icon.png OUTDIR
// Each TSV row (name, title, text) becomes OUTDIR/name.png: a transparent
// frame with a lower-third in the bottom left. Also writes title.png and
// end.png, the opaque opening and closing cards.
import AppKit

let args = CommandLine.arguments
let (tsv, iconPath, out) = (args[1], args[2], args[3])
let W = 1280.0, H = 800.0

func png(_ name: String, _ draw: () -> Void) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw()
    NSGraphicsContext.current = nil
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
}

func text(_ s: String, _ size: Double, _ weight: NSFont.Weight, _ alpha: Double = 1) -> NSAttributedString {
    NSAttributedString(string: s, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: NSColor(white: 1, alpha: alpha),
        .kern: size >= 40 ? -0.02 * size : 0,
    ])
}

// Lower third: a dark rounded panel 40 px in from the bottom left.
func lowerThird(_ title: String, _ body: String) {
    let t = text(title, 28, .semibold), b = text(body, 20, .regular, 0.82)
    let pad = 20.0, gap = 4.0
    let w = max(t.size().width, b.size().width) + 2 * pad
    let h = t.size().height + gap + b.size().height + 2 * pad - 4
    let r = NSRect(x: 40, y: 40, width: w, height: h)
    precondition(r.maxX <= W - 40, "caption too wide: \(title)")
    let path = NSBezierPath(roundedRect: r, xRadius: 16, yRadius: 16)
    NSColor(calibratedRed: 0.08, green: 0.08, blue: 0.1, alpha: 0.78).setFill()
    path.fill()
    NSColor(white: 1, alpha: 0.14).setStroke()
    path.lineWidth = 1
    path.stroke()
    b.draw(at: NSPoint(x: r.minX + pad, y: r.minY + pad - 2))
    t.draw(at: NSPoint(x: r.minX + pad, y: r.minY + pad - 2 + b.size().height + gap))
}

func card(_ draw: () -> Void) {
    NSGradient(starting: NSColor(calibratedRed: 0.09, green: 0.1, blue: 0.16, alpha: 1),
               ending: NSColor(calibratedRed: 0.02, green: 0.02, blue: 0.04, alpha: 1))!
        .draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -90)
    draw()
}

func centered(_ s: NSAttributedString, _ y: Double) {
    s.draw(at: NSPoint(x: (W - s.size().width) / 2, y: y))
}

for line in try! String(contentsOfFile: tsv, encoding: .utf8).split(separator: "\n") {
    let f = line.split(separator: "\t").map(String.init)
    png(f[0]) { lowerThird(f[1], f[2]) }
}

let icon = NSImage(contentsOfFile: iconPath)!
png("title") {
    card {
        icon.draw(in: NSRect(x: (W - 200) / 2, y: 380, width: 200, height: 200))
        centered(text("Macotron", 72, .bold), 270)
        centered(text("It does everything.", 30, .regular, 0.75), 225)
    }
}
png("end") {
    card {
        icon.draw(in: NSRect(x: (W - 120) / 2, y: 470, width: 120, height: 120))
        centered(text("Macotron", 56, .bold), 375)
        centered(text("macotron.statico.io", 30, .medium), 295)
        centered(text("github.com/statico/macotron", 24, .regular, 0.7), 250)
    }
}
