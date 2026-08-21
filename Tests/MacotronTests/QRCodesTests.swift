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
