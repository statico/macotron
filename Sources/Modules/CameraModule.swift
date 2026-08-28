import AppKit
@preconcurrency import AVFoundation
import CQuickJS
import CoreImage
import Foundation
import MacotronEngine

private final class CameraFrames: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: CVPixelBuffer?

    func set(_ next: CVPixelBuffer?) {
        lock.lock()
        buffer = next
        lock.unlock()
    }

    func get() -> CVPixelBuffer? {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }
}

@MainActor
private final class CameraPreview: NSObject, NSWindowDelegate {
    var session: AVCaptureSession?
    var panel: NSPanel?
    let frames = CameraFrames()

    func start(device: AVCaptureDevice, width: CGFloat, height: CGFloat) -> Bool {
        stop()
        let session = AVCaptureSession()
        session.sessionPreset = .high
        guard let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
            return false
        }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "macotron.camera.preview"))
        guard session.canAddOutput(output) else { return false }
        session.addOutput(output)

        let preview = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        preview.wantsLayer = true
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = preview.bounds
        preview.layer = layer

        let panel = NSPanel(
            contentRect: preview.frame,
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = device.localizedName
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.contentView = preview
        panel.delegate = self
        self.session = session
        self.panel = panel
        AppActivation.activate("camera panel")
        panel.makeKeyAndOrderFront(nil)
        session.startRunning()
        return true
    }

    func stop() {
        session?.stopRunning()
        session = nil
        frames.set(nil)
        panel?.delegate = nil
        panel?.close()
        panel = nil
    }

    func snapshot() -> String? {
        guard session?.isRunning == true, let pixel = frames.get() else { return nil }
        let image = CIImage(cvPixelBuffer: pixel)
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(image, from: image.extent) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        return rep.representation(using: .png, properties: [:])?.base64EncodedString()
    }

    func windowWillClose(_ notification: Notification) {
        session?.stopRunning()
        session = nil
        frames.set(nil)
        panel?.delegate = nil
        panel = nil
    }
}

extension CameraPreview: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        frames.set(CMSampleBufferGetImageBuffer(sampleBuffer))
    }
}

@MainActor
public final class CameraModule: NativeModule {
    public let name = "camera"
    public let moduleVersion = 1

    private let preview = CameraPreview()

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        engine.configStore["__cameraModule"] = self
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JSBridge.getProperty(ctx, global, "macotron")
        let camera = JS_NewObject(ctx)

        JS_SetPropertyStr(ctx, camera, "list", JS_NewCFunction(ctx, { ctx, _, _, _ in
            guard let ctx else { return QJS_Undefined() }
            if Engine.isDryRun(ctx) { return JSBridge.newArray(ctx, []) }
            return JSBridge.newArray(ctx, CameraModule.devices().map {
                ["id": $0.uniqueID, "name": $0.localizedName] as [String: Any]
            })
        }, "list", 0))

        JS_SetPropertyStr(ctx, camera, "preview", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx else { return JSBridge.newBool(ctx!, false) }
            if Engine.isDryRun(ctx) { return JSBridge.newBool(ctx, false) }
            return JSBridge.newBool(ctx, CameraModule.module(ctx)?.startPreview(ctx, argc: argc, argv: argv) ?? false)
        }, "preview", 1))

        JS_SetPropertyStr(ctx, camera, "stopPreview", JS_NewCFunction(ctx, { ctx, _, _, _ in
            CameraModule.module(ctx)?.preview.stop()
            return QJS_Undefined()
        }, "stopPreview", 0))

        JS_SetPropertyStr(ctx, camera, "snapshot", JS_NewCFunction(ctx, { ctx, _, _, _ in
            guard let ctx else { return QJS_Undefined() }
            if Engine.isDryRun(ctx) { return QJS_Null() }
            guard let png = CameraModule.module(ctx)?.preview.snapshot() else { return QJS_Null() }
            return JSBridge.newString(ctx, png)
        }, "snapshot", 0))

        JS_SetPropertyStr(ctx, macotron, "camera", camera)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)
    }

    public func cleanup() {
        preview.stop()
    }

    private func startPreview(_ ctx: OpaquePointer, argc: Int32, argv: UnsafePointer<JSValue>?) -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { _ in }
            return false
        default:
            return false
        }

        var id: String?
        var width: CGFloat = 640
        var height: CGFloat = 480
        if let argv, argc >= 1, JS_IsObject(argv[0]) {
            let opts = argv[0]
            id = JSBridge.string(ctx, opts, "id")
            if let w = JSBridge.int(ctx, opts, "width") { width = CGFloat(max(w, 160)) }
            if let h = JSBridge.int(ctx, opts, "height") { height = CGFloat(max(h, 120)) }
        }

        let devices = Self.devices()
        let device = id.flatMap { want in devices.first { $0.uniqueID == want } }
            ?? devices.first
            ?? AVCaptureDevice.default(for: .video)
        guard let device else { return false }
        return preview.start(device: device, width: width, height: height)
    }

    fileprivate static func devices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .continuityCamera, .deskViewCamera, .external],
            mediaType: .video,
            position: .unspecified
        ).devices
    }

    fileprivate static func module(_ ctx: OpaquePointer?) -> CameraModule? {
        Engine.module(ctx, "__cameraModule")
    }
}
