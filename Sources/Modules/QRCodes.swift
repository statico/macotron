import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import Vision

enum QRCodes {
    static let maxEncodedBytes = 8 * 1024 * 1024
    static let maxDecodedBytes = 8 * 1024 * 1024
    static let maxDimension = 8192
    static let maxTextCount = 4096
    static let maxPixelSize: CGFloat = 2048

    static func detect(data: Data) -> String? {
        guard data.count <= maxDecodedBytes, withinPixelCap(CGImageSourceCreateWithData(data as CFData, nil)) else { return nil }
        return detect(handler: VNImageRequestHandler(data: data))
    }

    static func detect(url: URL) -> String? {
        guard withinPixelCap(CGImageSourceCreateWithURL(url as CFURL, nil)) else { return nil }
        return detect(handler: VNImageRequestHandler(url: url))
    }

    static func detect(pixelBuffer: CVPixelBuffer) -> String? {
        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        guard w <= maxDimension, h <= maxDimension else { return nil }
        return detect(handler: VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up))
    }

    static func png(text: String, size: CGFloat = 256) -> Data? {
        guard text.count <= maxTextCount else { return nil }
        let size = min(max(size, 32), maxPixelSize)
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let out = filter.outputImage, out.extent.width > 0 else { return nil }
        let scale = max(size / out.extent.width, 1)
        let scaled = out.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }

    static func decodeBase64(_ value: String) -> Data? {
        let encoded = value.hasPrefix("data:")
            ? value.split(separator: ",", maxSplits: 1).last.map(String.init) ?? ""
            : value
        guard encoded.utf8.count <= maxEncodedBytes else { return nil }
        guard let data = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters),
              data.count <= maxDecodedBytes else { return nil }
        return data
    }

    private static func withinPixelCap(_ source: CGImageSource?) -> Bool {
        guard let source,
            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let w = props[kCGImagePropertyPixelWidth] as? Int,
            let h = props[kCGImagePropertyPixelHeight] as? Int
        else { return false }
        return w <= maxDimension && h <= maxDimension
    }

    private static func detect(handler: VNImageRequestHandler) -> String? {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        try? handler.perform([request])
        return request.results?.compactMap(\.payloadStringValue).first(where: { !$0.isEmpty })
    }
}
