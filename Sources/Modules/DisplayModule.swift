// DisplayModule.swift — macotron.display: enumerate connected displays
import AppKit
import CQuickJS
import Foundation
import MacotronEngine

@MainActor
public final class DisplayModule: NativeModule {
    public let name = "display"
    public let moduleVersion = 1

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotronObj = JSBridge.getProperty(ctx, global, "macotron")

        let displayObj = JS_NewObject(ctx)

        // macotron.display.list() -> array of {id, width, height, main: bool}
        JS_SetPropertyStr(ctx, displayObj, "list",
                          JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx else { return QJS_Undefined() }
            let displays = DisplayModule.listDisplays()
            return JSBridge.newArray(ctx, displays.map { $0 as Any })
        }, "list", 0))

        JS_SetPropertyStr(ctx, macotronObj, "display", displayObj)
        JS_FreeValue(ctx, macotronObj)
        JS_FreeValue(ctx, global)
    }

    // MARK: - Display Enumeration

    private static func listDisplays() -> [[String: Any]] {
        var displays: [[String: Any]] = []
        let mainScreen = NSScreen.main

        for screen in NSScreen.screens {
            let frame = screen.frame
            let deviceDescription = screen.deviceDescription
            let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0

            let isMain = (mainScreen != nil && screen == mainScreen)

            displays.append([
                "id": Int(screenNumber),
                "width": Int(frame.width),
                "height": Int(frame.height),
                "main": isMain
            ])
        }

        return displays
    }
}
