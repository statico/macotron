// AppModule.swift — macotron.app: list/launch/switch running applications
import CQuickJS
import Foundation
import MacotronEngine
import AppKit
import os

private let logger = Logger(subsystem: "io.statico.macotron", category: "app")

@MainActor
public final class AppModule: NativeModule {
    public let name = "app"
    public let moduleVersion = 2

    private weak var engine: Engine?
    private var activationObserver: NSObjectProtocol?
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var lastOther: [String: Any]?
    private static let ownBundleID = Bundle.main.bundleIdentifier ?? "io.statico.macotron"

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        self.engine = engine
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
            return JSBridge.newBool(ctx, AppLaunch.open(bundleID: bundleID))
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
            return JSBridge.newBool(ctx, AppLaunch.open(bundleID: bundleID))
        }, "switch", 1))

        // macotron.app.frontmost() -> {name, bundleID, pid} or null
        JS_SetPropertyStr(ctx, appObj, "frontmost",
                          JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let opaque = JS_GetContextOpaque(ctx) else { return QJS_Null() }
            let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()
            guard let module = engine.configStore["__appModule"] as? AppModule,
                  let info = module.frontmostInfo() else {
                return QJS_Null()
            }
            return JSBridge.newObject(ctx, info)
        }, "frontmost", 0))

        JS_SetPropertyStr(ctx, appObj, "hide", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx else { return JSBridge.newBool(ctx!, false) }
            let id = argc > 0 ? JSBridge.toString(ctx, argv![0]) : nil
            return JSBridge.newBool(ctx, AppControl.hide(id))
        }, "hide", 1))

        JS_SetPropertyStr(ctx, appObj, "quit", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx else { return JSBridge.newBool(ctx!, false) }
            let id = argc > 0 ? JSBridge.toString(ctx, argv![0]) : nil
            return JSBridge.newBool(ctx, AppControl.quit(id))
        }, "quit", 1))

        JS_SetPropertyStr(ctx, appObj, "menu", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 1 else { return JSBridge.newBool(ctx!, false) }
            guard let path = (JSBridge.jsToSwift(ctx, argv[0]) as? [Any])?.compactMap({ $0 as? String }),
                  !path.isEmpty else {
                return JSBridge.newBool(ctx, false)
            }
            let bundleID = argc > 1 ? JSBridge.toString(ctx, argv[1]) : nil
            guard let app = AppControl.running(bundleID) else { return JSBridge.newBool(ctx, false) }
            return JSBridge.newBool(ctx, AppMenu.select(pid: app.processIdentifier, path: path))
        }, "menu", 2))

        JS_SetPropertyStr(ctx, macotron, "app", appObj)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)

        engine.configStore["__appModule"] = self
        guard !engine.dryRun else { return }
        let center = NSWorkspace.shared.notificationCenter
        activationObserver = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication,
                  let bundleID = app.bundleIdentifier else {
                return
            }
            let name = app.localizedName ?? bundleID
            let pid = Int(app.processIdentifier)
            Task { @MainActor [weak self] in
                self?.emitActivation(bundleID: bundleID, name: name, pid: pid)
            }
        }
        observe(center, NSWorkspace.didLaunchApplicationNotification, "app:launched")
        observe(center, NSWorkspace.didTerminateApplicationNotification, "app:terminated")
    }

    public func cleanup() {
        let center = NSWorkspace.shared.notificationCenter
        if let activationObserver {
            center.removeObserver(activationObserver)
        }
        for token in lifecycleObservers {
            center.removeObserver(token)
        }
        lifecycleObservers = []
        activationObserver = nil
        engine = nil
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ event: String) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let info = AppControl.info(app) else { return }
            Task { @MainActor [weak self] in
                self?.emitApp(event, info)
            }
        }
        lifecycleObservers.append(token)
    }

    private func emitApp(_ event: String, _ info: [String: Any]) {
        guard let bundleID = info["bundleID"] as? String, bundleID != Self.ownBundleID else { return }
        guard let engine, let ctx = engine.context else { return }
        let data = JSBridge.newObject(ctx, info)
        engine.eventBus.emit(event, engine: engine, data: data)
        JS_FreeValue(ctx, data)
    }

    func frontmostInfo() -> [String: Any]? {
        if let app = NSWorkspace.shared.frontmostApplication,
           let bundleID = app.bundleIdentifier,
           bundleID != Self.ownBundleID {
            return [
                "name": app.localizedName ?? bundleID,
                "bundleID": bundleID,
                "pid": Int(app.processIdentifier)
            ]
        }
        return lastOther
    }

    private func emitActivation(bundleID: String, name: String, pid: Int) {
        guard bundleID != Self.ownBundleID else { return }
        lastOther = ["name": name, "bundleID": bundleID, "pid": pid]

        guard let engine, let ctx = engine.context else {
            return
        }

        let data = JSBridge.newObject(ctx, lastOther ?? [:])
        engine.eventBus.emit("app:activated", engine: engine, data: data)
        JS_FreeValue(ctx, data)
    }
}

/// Directories and extra bundles the launcher scans. Finder lives in CoreServices,
/// Keychain Access in CoreServices/Applications — neither is under /Applications.
public enum AppCatalog {
    public static func searchDirectories(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
            URL(fileURLWithPath: "/Applications/Utilities"),
            home.appending(path: "Applications"),
            URL(fileURLWithPath: "/System/Library/CoreServices/Applications"),
        ]
    }

    public static let extraApps = [
        URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"),
    ]

    /// `/Applications/Safari.app` is a hidden symlink into the Cryptexes volume, so
    /// skipping hidden entries would drop Safari from the launcher.
    public static func appBundles(in directory: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        return contents.filter { $0.pathExtension == "app" }
    }

    /// Xcode ships Simulator, Instruments, and friends inside its own bundle, where
    /// a top-level directory scan never reaches them. Only Xcode is descended into,
    /// so this costs two directory reads rather than two per installed app.
    public static func nestedBundles(in appBundle: URL) -> [URL] {
        guard appBundle.lastPathComponent.hasPrefix("Xcode") else { return [] }
        return ["Contents/Developer/Applications", "Contents/Applications"]
            .flatMap { appBundles(in: appBundle.appending(path: $0)) }
    }

    /// Every bundle the launcher offers, nested and out-of-tree ones included.
    public static func allBundles(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        let top = searchDirectories(home: home).flatMap(appBundles(in:))
        return top + top.flatMap(nestedBundles(in:)) + extraApps
    }
}

/// Launch or activate via Launch Services. `NSRunningApplication.activate()` from a
/// background/menubar host does not steal focus.
public enum AppLaunch {
    public static func shouldHide(bundleID: String, frontmost: String?) -> Bool {
        guard let frontmost, !bundleID.isEmpty else { return false }
        return frontmost == bundleID
    }

    @discardableResult
    public static func open(bundleID: String, hideIfFrontmost: Bool = false) -> Bool {
        if hideIfFrontmost,
           let front = NSWorkspace.shared.frontmostApplication,
           shouldHide(bundleID: bundleID, frontmost: front.bundleIdentifier) {
            return front.hide()
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            logger.error("app.open: no app found for \(bundleID)")
            return false
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            if let error {
                logger.error("app.open \(bundleID): \(error.localizedDescription)")
            }
        }
        return true
    }
}
