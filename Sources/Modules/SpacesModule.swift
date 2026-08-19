// SpacesModule.swift — macotron.spaces: list, go, moveWindow, space:changed
import AppKit
import CQuickJS
import Foundation
import MacotronEngine

@MainActor
public final class SpacesModule: NativeModule {
    public let name = "spaces"
    public let moduleVersion = 1

    private weak var engine: Engine?
    private var observer: NSObjectProtocol?
    private var lastIDs: [UInt64] = []

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        self.engine = engine
        engine.configStore["__spacesModule"] = self
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JSBridge.getProperty(ctx, global, "macotron")
        let spaces = JS_NewObject(ctx)

        JS_SetPropertyStr(ctx, spaces, "list", JS_NewCFunction(ctx, { ctx, _, _, _ in
            guard let ctx else { return QJS_Undefined() }
            return JSBridge.newArray(ctx, Spaces.list().map(\.js))
        }, "list", 0))

        JS_SetPropertyStr(ctx, spaces, "current", JS_NewCFunction(ctx, { ctx, _, _, _ in
            guard let ctx else { return QJS_Undefined() }
            guard let space = Spaces.current() else { return QJS_Null() }
            return JSBridge.newObject(ctx, space.js)
        }, "current", 0))

        JS_SetPropertyStr(ctx, spaces, "go", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 1 else { return JSBridge.newBool(ctx!, false) }
            return JSBridge.newBool(ctx, Spaces.go(JSBridge.jsToSwift(ctx, argv[0])))
        }, "go", 1))

        JS_SetPropertyStr(ctx, spaces, "moveWindow", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 2 else { return JSBridge.newBool(ctx!, false) }
            let windowID = JSBridge.toInt32(ctx, argv[0])
            guard let space = Spaces.resolve(JSBridge.jsToSwift(ctx, argv[1])),
                  let cgID = WindowAX.cgWindowID(windowID) else {
                return JSBridge.newBool(ctx, false)
            }
            return JSBridge.newBool(ctx, Spaces.moveWindow(cgWindowID: cgID, space: space))
        }, "moveWindow", 2))

        JS_SetPropertyStr(ctx, macotron, "spaces", spaces)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)

        guard !engine.dryRun else { return }
        lastIDs = Spaces.list().filter(\.current).map(\.id)
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.emitIfChanged() }
        }
    }

    public func cleanup() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observer = nil
        engine = nil
    }

    private func emitIfChanged() {
        let current = Spaces.list().filter(\.current)
        let ids = current.map(\.id)
        guard ids != lastIDs else { return }
        lastIDs = ids
        guard let engine, let ctx = engine.context else { return }
        let payload: [String: Any]
        if let space = current.first {
            payload = space.js
        } else {
            payload = [:]
        }
        let data = JSBridge.newObject(ctx, payload)
        engine.eventBus.emit("space:changed", engine: engine, data: data)
        JS_FreeValue(ctx, data)
    }
}
