import AppKit
import Foundation
import Testing
@testable import MacotronEngine
@testable import Modules

@Suite("QRCodes")
struct QRCodesTests {
    @Test("generated QR detects the same payload")
    func roundTrip() throws {
        let payload = "https://macotron.example/qr-test"
        let png = try #require(QRCodes.png(text: payload, size: 160))
        #expect(QRCodes.detect(data: png) == payload)
    }

    @Test("empty image has no QR")
    func empty() {
        let empty = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        #expect(QRCodes.detect(data: empty) == nil)
    }

    @Test("oversize base64 is rejected before Vision")
    func rejectsHugeBase64() {
        let huge = String(repeating: "A", count: QRCodes.maxEncodedBytes + 1)
        #expect(QRCodes.decodeBase64(huge) == nil)
    }

    @Test("oversize payload is not encoded")
    func rejectsHugeText() {
        let text = String(repeating: "x", count: QRCodes.maxTextCount + 1)
        #expect(QRCodes.png(text: text) == nil)
    }

    @Test("generated size is clamped")
    func pixelCap() throws {
        let png = try #require(QRCodes.png(text: "hi", size: 1_000_000))
        let rep = try #require(NSBitmapImageRep(data: png))
        #expect(rep.pixelsWide <= Int(QRCodes.maxPixelSize))
        #expect(rep.pixelsHigh <= Int(QRCodes.maxPixelSize))
    }

    @Test("images wider than the dimension cap are not scanned")
    func dimensionCap() throws {
        let payload = "https://macotron.example/wide"
        let qr = try #require(QRCodes.png(text: payload, size: 96))
        let small = try embed(qr, width: 512, height: 128)
        #expect(QRCodes.detect(data: small) == payload)
        let wide = try embed(qr, width: QRCodes.maxDimension + 8, height: 128)
        #expect(QRCodes.detect(data: wide) == nil)
    }

    private func embed(_ qr: Data, width: Int, height: Int) throws -> Data {
        let image = try #require(NSImage(data: qr))
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        image.draw(in: NSRect(x: 16, y: 16, width: 96, height: 96))
        NSGraphicsContext.restoreGraphicsState()
        return try #require(rep.representation(using: .png, properties: [:]))
    }
}

@Suite("Camera permission")
@MainActor
struct CameraPermissionTests {
    @Test func aliases() {
        #expect(Permissions.parse("camera") == .camera)
        #expect(Permissions.parse("webcam") == .camera)
        #expect(Permissions.parse("qr") == .camera)
    }

    @Test func settingsLabel() {
        #expect(Permission.camera.title == "Camera")
        #expect(Permission.camera.isAutoRequestable)
    }
}
