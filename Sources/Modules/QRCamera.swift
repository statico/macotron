import MacotronEngine
import AppKit
import AVFoundation
import Vision

@MainActor
final class QRCameraPicker: NSObject {
    static let shared = QRCameraPicker()

    private var continuation: CheckedContinuation<String?, Never>?
    private var session: AVCaptureSession?
    private var panel: NSPanel?
    private var keyMonitor: Any?

    func pick() async -> String? {
        if continuation != nil { return nil }
        guard await authorized() else { return nil }
        return await withCheckedContinuation { cont in
            continuation = cont
            start()
        }
    }

    private func authorized() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { cont in
                AVCaptureDevice.requestAccess(for: .video) { cont.resume(returning: $0) }
            }
        default:
            return false
        }
    }

    private func start() {
        let session = AVCaptureSession()
        session.sessionPreset = .medium
        guard let camera = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input) else {
            finish(nil)
            return
        }
        session.addInput(input)
        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "macotron.qr.camera"))
        guard session.canAddOutput(output) else {
            finish(nil)
            return
        }
        session.addOutput(output)
        self.session = session

        let preview = NSView(frame: NSRect(x: 0, y: 36, width: 480, height: 320))
        preview.wantsLayer = true
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = preview.bounds
        preview.layer = layer

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelScan))
        cancel.bezelStyle = .rounded
        cancel.frame = NSRect(x: 380, y: 6, width: 90, height: 24)

        let hint = NSTextField(labelWithString: "Point the camera at a QR code")
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        hint.frame = NSRect(x: 12, y: 8, width: 360, height: 20)

        let root = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 356))
        root.addSubview(preview)
        root.addSubview(hint)
        root.addSubview(cancel)

        let panel = NSPanel(
            contentRect: root.frame,
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Scan QR Code"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.contentView = root
        panel.delegate = self
        self.panel = panel
        AppActivation.activate("qr camera")
        panel.makeKeyAndOrderFront(nil)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.finish(nil)
                return nil
            }
            return event
        }
        session.startRunning()
    }

    @objc private func cancelScan() {
        finish(nil)
    }

    fileprivate func found(_ text: String) {
        finish(text)
    }

    private func finish(_ text: String?) {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        session?.stopRunning()
        session = nil
        panel?.delegate = nil
        panel?.close()
        panel = nil
        continuation?.resume(returning: text)
        continuation = nil
    }
}

extension QRCameraPicker: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixel = CMSampleBufferGetImageBuffer(sampleBuffer),
              let text = QRCodes.detect(pixelBuffer: pixel) else { return }
        DispatchQueue.main.async {
            self.found(text)
        }
    }
}

extension QRCameraPicker: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        finish(nil)
    }
}

@MainActor
enum QRWindow {
    private static var panel: NSPanel?

    static func show(_ image: NSImage) {
        let size = NSSize(width: 280, height: 280)
        let view = NSImageView(frame: NSRect(origin: .zero, size: size))
        view.image = image
        view.imageScaling = .scaleProportionallyUpOrDown
        if panel == nil {
            let next = NSPanel(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.titled, .closable, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            next.title = "QR Code"
            next.isFloatingPanel = true
            next.level = .floating
            next.isReleasedWhenClosed = false
            panel = next
        }
        panel?.contentView = view
        panel?.setContentSize(size)
        AppActivation.activate("qr camera")
        panel?.makeKeyAndOrderFront(nil)
    }
}
