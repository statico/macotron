// CameraModule.swift — macotron.camera: poll camera device status
import CQuickJS
import Foundation
import MacotronEngine

@MainActor
public final class CameraModule: NativeModule {
    public let name = "camera"
    public let moduleVersion = 1

    public var defaultOptions: [String: Any] {
        ["pollInterval": 5000]  // milliseconds
    }

    private weak var engine: Engine?
    private var pollingTask: DispatchSourceTimer?
    private var lastActive = false
    private var pollInterval: Int = 5000

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        self.engine = engine

        if let interval = options["pollInterval"] as? Int {
            pollInterval = interval
        }

        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotronObj = JSBridge.getProperty(ctx, global, "macotron")

        let cameraObj = JS_NewObject(ctx)

        // macotron.camera.isActive() → bool
        JS_SetPropertyStr(ctx, cameraObj, "isActive",
                          JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx else { return QJS_Undefined() }
            let active = CameraModule.checkCameraActive()
            return JSBridge.newBool(ctx, active)
        }, "isActive", 0))

        JS_SetPropertyStr(ctx, macotronObj, "camera", cameraObj)
        JS_FreeValue(ctx, macotronObj)
        JS_FreeValue(ctx, global)

        startPolling()
    }

    public func cleanup() {
        stopPolling()
        engine = nil
    }

    // MARK: - Camera Check

    /// Check if the camera device is currently in use by running lsof on /dev/video0
    private static func checkCameraActive() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["/dev/video0"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            // lsof returns 0 if the file is open by some process
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    // MARK: - Polling

    private func startPolling() {
        stopPolling()

        let timer = DispatchSource.makeTimerSource(queue: .main)
        let interval = DispatchTimeInterval.milliseconds(pollInterval)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            self?.pollCamera()
        }
        pollingTask = timer
        timer.resume()
    }

    private func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func pollCamera() {
        guard let engine else { return }

        let active = CameraModule.checkCameraActive()

        if active != lastActive {
            lastActive = active
            let event = active ? "camera:active" : "camera:inactive"
            engine.eventBus.emit(event, engine: engine)
        }
    }
}
