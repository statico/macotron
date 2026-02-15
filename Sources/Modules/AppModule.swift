// AppModule.swift — macotron.app: list/launch/switch running applications
import CQuickJS
import Foundation
import MacotronEngine
import AppKit
import os

private let logger = Logger(subsystem: "com.macotron", category: "app")

@MainActor
public final class AppModule: NativeModule {
    public let name = "app"

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JSBridge.getProperty(ctx, global, "macotron")

        let appObj = JS_NewObject(ctx)

        // macotron.app.list() -> [{name, bundleID, pid}]
        JS_SetPropertyStr(ctx, appObj, "list",
                          JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx else { return QJS_Undefined() }

            let runningApps = NSWorkspace.shared.runningApplications
            let jsArr = JS_NewArray(ctx)

            var index: UInt32 = 0
            for app in runningApps {
                // Only include apps with a bundle identifier (skip system daemons)
                guard let bundleID = app.bundleIdentifier else { continue }
                let name = app.localizedName ?? bundleID

                let entry = JSBridge.newObject(ctx, [
                    "name": name,
                    "bundleID": bundleID,
                    "pid": Int(app.processIdentifier)
                ])
                JS_SetPropertyUint32(ctx, jsArr, index, entry)
                index += 1
            }

            return jsArr
        }, "list", 0))

        // macotron.app.launch(bundleID) -> void
        JS_SetPropertyStr(ctx, appObj, "launch",
                          JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 1 else { return QJS_Undefined() }

            guard let bundleID = JSBridge.toString(ctx, argv[0]) else {
                logger.error("app.launch: bundleID argument required")
                return QJS_Undefined()
            }

            guard let url = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: bundleID
            ) else {
                logger.error("app.launch: no app found for \(bundleID)")
                return JSBridge.newBool(ctx, false)
            }

            let config = NSWorkspace.OpenConfiguration()
            config.activates = true

            // Fire and forget — launch is async but we don't block
            NSWorkspace.shared.openApplication(
                at: url,
                configuration: config,
                completionHandler: { app, error in
                    if let error {
                        logger.error("app.launch failed: \(error.localizedDescription)")
                    }
                }
            )

            return JSBridge.newBool(ctx, true)
        }, "launch", 1))

        // macotron.app.switch(bundleID) -> void (activate the app)
        // Note: "switch" is a reserved word in Swift; the JS property name is fine
        JS_SetPropertyStr(ctx, appObj, "switch",
                          JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 1 else { return QJS_Undefined() }

            guard let bundleID = JSBridge.toString(ctx, argv[0]) else {
                logger.error("app.switch: bundleID argument required")
                return QJS_Undefined()
            }

            let apps = NSRunningApplication.runningApplications(
                withBundleIdentifier: bundleID
            )

            guard let app = apps.first else {
                logger.warning("app.switch: no running app for \(bundleID)")
                return JSBridge.newBool(ctx, false)
            }

            let activated = app.activate()
            return JSBridge.newBool(ctx, activated)
        }, "switch", 1))

        // macotron.app.frontmost() -> {name, bundleID, pid} or null
        JS_SetPropertyStr(ctx, appObj, "frontmost",
                          JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx else { return QJS_Undefined() }

            guard let app = NSWorkspace.shared.frontmostApplication,
                  let bundleID = app.bundleIdentifier else {
                return QJS_Null()
            }

            return JSBridge.newObject(ctx, [
                "name": app.localizedName ?? bundleID,
                "bundleID": bundleID,
                "pid": Int(app.processIdentifier)
            ])
        }, "frontmost", 0))

        JS_SetPropertyStr(ctx, macotron, "app", appObj)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)
    }
}
