import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Modules

@Suite("disks")
struct DisksTests {
    @Test("list has the root volume with plausible sizes")
    func root() throws {
        let root = try #require(Disks.list().first { $0["root"] as? Bool == true })
        let total = try #require(root["total"] as? Int)
        let free = try #require(root["free"] as? Int)
        let available = try #require(root["available"] as? Int)
        #expect(root["path"] as? String == "/")
        #expect(root["network"] as? Bool == false)
        #expect(total > 1 << 30)
        #expect(free > 0 && free <= total)
        #expect(available >= free && available <= total)
        #expect((root["device"] as? String)?.hasPrefix("disk") == true)
    }

    @Test("a mount with no resource values falls back to statfs")
    func network() {
        let mount = Mount(path: "/Volumes/Share", device: "//alex@nas/Share", fsType: "smbfs",
                          flags: UInt32(MNT_RDONLY), total: 1000, free: 400)
        let row = Disks.entry(mount, nil)
        #expect(row["name"] as? String == "Share")
        #expect(row["device"] as? String == "//alex@nas/Share")
        #expect(row["network"] as? Bool == true)
        #expect(row["readOnly"] as? Bool == true)
        #expect(row["available"] as? Int == 400)
        #expect(row["ejectable"] as? Bool == false)
        #expect(mount.visible)
    }

    @Test("system volumes Finder hides are not listed")
    func hidden() {
        let mount = Mount(path: "/System/Volumes/VM", device: "/dev/disk3s6", fsType: "apfs",
                          flags: UInt32(MNT_LOCAL | MNT_DONTBROWSE), total: 1, free: 1)
        #expect(!mount.visible)
        #expect(Disks.entry(mount, nil)["device"] as? String == "disk3s6")
    }
}

@Suite("image")
struct ImageTests {
    @Test("format names and extensions map to types")
    func types() {
        #expect(ImageConvert.type(format: "jpeg", dest: "x.png") == .jpeg)
        #expect(ImageConvert.type(format: "HEIC", dest: "") == .heic)
        #expect(ImageConvert.type(format: nil, dest: "~/a/b.tif") == .tiff)
        #expect(ImageConvert.type(format: nil, dest: "b") == nil)
        #expect(ImageConvert.type(format: "gif", dest: "b.png") == nil)
    }

    @Test("quality is clamped and a zero maxSize is ignored")
    func properties() {
        let props = ImageConvert.properties(quality: 1.5, maxSize: 0)
        #expect(props[kCGImageDestinationLossyCompressionQuality] as? Double == 1)
        #expect(props[kCGImageDestinationImageMaxPixelSize] == nil)
        #expect(ImageConvert.properties(quality: nil, maxSize: 200)[kCGImageDestinationImageMaxPixelSize] as? Int == 200)
    }

    @Test("a PNG converts to a JPEG that decodes, scaled to maxSize")
    func convert() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("macotron-image-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let png = dir.appendingPathComponent("a.png")
        let ctx = try #require(CGContext(
            data: nil, width: 64, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 32))
        let out = try #require(CGImageDestinationCreateWithURL(png as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(out, try #require(ctx.makeImage()), nil)
        #expect(CGImageDestinationFinalize(out))

        let jpeg = dir.appendingPathComponent("a.jpg")
        let result = ImageConvert.run(src: png.path, dest: jpeg.path, type: .jpeg,
                                      properties: ImageConvert.properties(quality: 0.8, maxSize: 16))
        #expect(result["ok"] as? Bool == true)
        let source = try #require(CGImageSourceCreateWithURL(jpeg as CFURL, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.jpeg.identifier)
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 16 && image.height == 8)

        let same = ImageConvert.run(src: png.path, dest: png.path, type: .png, properties: [:])
        #expect(same["ok"] as? Bool == false)
        let missing = ImageConvert.run(src: dir.appendingPathComponent("no.png").path, dest: jpeg.path, type: .jpeg, properties: [:])
        #expect(missing["ok"] as? Bool == false)
    }
}

@MainActor
@Suite("speech")
struct SpeechTests {
    @Test("a voice resolves by identifier or name, and nothing named is the default")
    func voice() throws {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        #expect(Speech.voice(nil, in: voices) == nil)
        #expect(Speech.voice("", in: voices) == nil)
        #expect(Speech.voice("No Such Voice", in: voices) == nil)
        let first = try #require(voices.first)
        #expect(Speech.voice(first.identifier, in: voices) == first)
        #expect(Speech.voice(first.name.uppercased(), in: voices)?.name == first.name)
    }
}
