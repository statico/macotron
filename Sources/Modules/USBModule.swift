// USBModule.swift — macotron.usb: list devices, usb:changed
import CQuickJS
import Foundation
import MacotronEngine

@MainActor
public final class USBModule: NativeModule {
    public let name = "usb"
    public let moduleVersion = 1

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        engine.configStore["__usbModule"] = self
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JSBridge.getProperty(ctx, global, "macotron")
        let usb = JS_NewObject(ctx)

        JS_SetPropertyStr(ctx, usb, "list", JS_NewCFunction(ctx, { ctx, _, _, _ in
            guard let ctx else { return QJS_Undefined() }
            return JSBridge.newArray(ctx, USBDevices.list().map { $0 as Any })
        }, "list", 0))

        JS_SetPropertyStr(ctx, macotron, "usb", usb)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)

        guard !engine.dryRun else { return }
        USBWatch.start(engine)
    }

    public func cleanup() {
        USBWatch.stop()
    }
}
