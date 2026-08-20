import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import Vision

enum QRCodes {
    static func detect(data: Data) -> String? {
        detect(handler: VNImageRequestHandler(data: data))
    }

    static func detect(url: URL) -> String? {
        detect(handler: VNImageRequestHandler(url: url))
    }

    static func detect(pixelBuffer: CVPixelBuffer) -> String? {
        detect(handler: VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up))
    }

    static func png(text: String, size: CGFloat = 256) -> Data? {
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
        return Data(base64Encoded: encoded, options: .ignoreUnknownCharacters)
    }

    private static func detect(handler: VNImageRequestHandler) -> String? {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        try? handler.perform([request])
        return request.results?.compactMap(\.payloadStringValue).first(where: { !$0.isEmpty })
    }
}
