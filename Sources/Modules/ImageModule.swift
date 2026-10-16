// ImageModule.swift — macotron.image: convert between image formats
import CQuickJS
import Foundation
import ImageIO
import MacotronEngine
import UniformTypeIdentifiers

enum ImageConvert {
    static let formats: [String: UTType] = [
        "jpeg": .jpeg, "jpg": .jpeg, "png": .png, "heic": .heic, "tiff": .tiff, "tif": .tiff,
    ]

    /// The named format, or the destination's extension when none is named.
    static func type(format: String?, dest: String) -> UTType? {
        let key = format ?? (dest as NSString).pathExtension
        return formats[key.lowercased()]
    }

    /// `quality` is clamped to 0…1 and only matters to lossy formats;
    /// `maxSize` caps the longer side in pixels, keeping the aspect ratio.
    static func properties(quality: Double?, maxSize: Int?) -> [CFString: Any] {
        var props: [CFString: Any] = [:]
        if let quality { props[kCGImageDestinationLossyCompressionQuality] = min(max(quality, 0), 1) }
        if let maxSize, maxSize > 0 { props[kCGImageDestinationImageMaxPixelSize] = maxSize }
        return props
    }

    /// Copying from the source rather than decoding to a CGImage first keeps
    /// the EXIF, GPS and orientation tags, which is what sips did.
    static func run(src: String, dest: String, type: UTType, properties: [CFString: Any]) -> [String: Any] {
        let from = URL(fileURLWithPath: src).standardizedFileURL
        let to = URL(fileURLWithPath: dest).standardizedFileURL
        // ImageIO reads the source lazily, so writing over it would truncate
        // the file it is still reading.
        guard from.resolvingSymlinksInPath() != to.resolvingSymlinksInPath() else {
            return fail("source and destination are the same file")
        }
        guard let source = CGImageSourceCreateWithURL(from as CFURL, nil),
              CGImageSourceGetCount(source) > 0 else {
            return fail("cannot read \(src)")
        }
        guard let destination = CGImageDestinationCreateWithURL(
            to as CFURL, type.identifier as CFString, 1, nil) else {
            return fail("cannot write \(type.preferredFilenameExtension ?? type.identifier) to \(dest)")
        }
        CGImageDestinationAddImageFromSource(destination, source, 0, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return fail("could not write \(dest)") }
        return ["ok": true]
    }

    private static func fail(_ message: String) -> [String: Any] {
        ["ok": false, "error": message]
    }
}

@MainActor
public final class ImageModule: NativeModule {
    public let name = "image"

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JSBridge.getProperty(ctx, global, "macotron")
        let image = JS_NewObject(ctx)

        JSBridge.fn(ctx, image, "convert", 3) { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 2,
                  let src = JSBridge.toString(ctx, argv[0]), !src.isEmpty,
                  let dest = JSBridge.toString(ctx, argv[1]), !dest.isEmpty else {
                return QJS_ThrowTypeError(ctx, "image.convert requires a source and a destination path")
            }
            let hasOpts = argc >= 3 && JS_IsObject(argv[2])
            let opts = argv[2]
            let format = hasOpts ? JSBridge.string(ctx, opts, "format") : nil
            guard let type = ImageConvert.type(format: format, dest: dest) else {
                return QJS_ThrowTypeError(ctx, "image.convert format must be jpeg, png, heic or tiff")
            }
            let from = (src as NSString).expandingTildeInPath
            let to = (dest as NSString).expandingTildeInPath
            nonisolated(unsafe) let properties = ImageConvert.properties(
                quality: hasOpts ? JSBridge.double(ctx, opts, "quality") : nil,
                maxSize: hasOpts ? JSBridge.int(ctx, opts, "maxSize") : nil)
            return JSBridge.promise(ctx, dryRun: ["ok": true]) {
                .value(ImageConvert.run(src: from, dest: to, type: type, properties: properties))
            }
        }

        JS_SetPropertyStr(ctx, macotron, "image", image)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)
    }
}
