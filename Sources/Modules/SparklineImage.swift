import AppKit
import CQuickJS
import Foundation
import MacotronEngine

enum SparklineImage {
    static func png(values: [Double], width: Int, height: Int, color: String?) -> Data? {
        guard !values.isEmpty, width > 0, height > 0 else { return nil }
        let size = NSSize(width: width, height: height)
        guard let rep = bitmap(size) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        drawPolyline(values, size: size, color: parseColor(color) ?? .labelColor)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    @MainActor
    static func png(fromJS ctx: OpaquePointer, opts: JSValue) -> Data? {
        let sparkVal = JSBridge.getProperty(ctx, opts, "sparkline")
        defer { JS_FreeValue(ctx, sparkVal) }
        if JS_IsObject(sparkVal), !JSBridge.isUndefined(sparkVal), !JSBridge.isNull(sparkVal) {
            let valuesVal = JSBridge.getProperty(ctx, sparkVal, "values")
            var values: [Double] = []
            if JS_IsArray(valuesVal) {
                let lenVal = JS_GetPropertyStr(ctx, valuesVal, "length")
                let len = JSBridge.toInt32(ctx, lenVal)
                JS_FreeValue(ctx, lenVal)
                for i in 0..<len {
                    let elem = JS_GetPropertyUint32(ctx, valuesVal, UInt32(i))
                    values.append(JSBridge.toDouble(ctx, elem))
                    JS_FreeValue(ctx, elem)
                }
            }
            JS_FreeValue(ctx, valuesVal)
            let wVal = JSBridge.getProperty(ctx, sparkVal, "width")
            let width = JSBridge.isUndefined(wVal) || JSBridge.isNull(wVal) ? 36 : Int(JSBridge.toInt32(ctx, wVal))
            JS_FreeValue(ctx, wVal)
            let hVal = JSBridge.getProperty(ctx, sparkVal, "height")
            let height = JSBridge.isUndefined(hVal) || JSBridge.isNull(hVal) ? 18 : Int(JSBridge.toInt32(ctx, hVal))
            JS_FreeValue(ctx, hVal)
            let cVal = JSBridge.getProperty(ctx, sparkVal, "color")
            let color: String? = JSBridge.isUndefined(cVal) || JSBridge.isNull(cVal) ? nil : JSBridge.toString(ctx, cVal)
            JS_FreeValue(ctx, cVal)
            if let png = png(values: values, width: width, height: height, color: color) {
                return png
            }
        }

        let svgVal = JSBridge.getProperty(ctx, opts, "svg")
        defer { JS_FreeValue(ctx, svgVal) }
        if let svg = JSBridge.toString(ctx, svgVal), let png = png(svg: svg) {
            return png
        }
        return nil
    }

    static func png(svg: String) -> Data? {
        guard !svg.isEmpty, let image = NSImage(data: Data(svg.utf8)), image.size.width > 0 else {
            return nil
        }
        let size = image.size
        guard let rep = bitmap(size) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    private static func bitmap(_ size: NSSize) -> NSBitmapImageRep? {
        let scale: CGFloat = 2
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(ceil(size.width * scale)),
            pixelsHigh: Int(ceil(size.height * scale)),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        rep.size = size
        return rep
    }

    private static func drawPolyline(_ values: [Double], size: NSSize, color: NSColor) {
        let minV = values.min() ?? 0
        let maxV = values.max() ?? 0
        let range = max(maxV - minV, 1e-9)
        let pad: CGFloat = 1
        let plot = NSSize(width: max(size.width - pad * 2, 1), height: max(size.height - pad * 2, 1))
        let path = NSBezierPath()
        path.lineWidth = 1
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        for (i, value) in values.enumerated() {
            let x = pad + (values.count == 1 ? plot.width / 2 : plot.width * CGFloat(i) / CGFloat(values.count - 1))
            let y = pad + plot.height * CGFloat((value - minV) / range)
            if i == 0 { path.move(to: NSPoint(x: x, y: y)) }
            else { path.line(to: NSPoint(x: x, y: y)) }
        }
        color.setStroke()
        path.stroke()
    }

    private static func parseColor(_ raw: String?) -> NSColor? {
        guard let raw else { return nil }
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix("#") else { return nil }
        var hex = String(s.dropFirst())
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
