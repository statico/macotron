import AppKit
import ApplicationServices
import CQuickJS
import Foundation
import MacotronEngine

@MainActor
public final class AXModule: NativeModule {
    public let name = "ax"

    let handles = AXHandleTable<AXUIElement>()

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        engine.configStore["__axModule"] = self
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JSBridge.getProperty(ctx, global, "macotron")
        let ax = JS_NewObject(ctx)

        JSBridge.fn(ctx, ax, "focused", 0) { ctx, _, _, _ in
            guard let ctx else { return QJS_Undefined() }
            if AXModule.dryRun(ctx) { return QJS_Null() }
            guard let el = AXTree.focused() else { return QJS_Null() }
            return AXModule.wrap(ctx, el)
        }

        JSBridge.fn(ctx, ax, "selectedText", 0) { ctx, _, _, _ in
            guard let ctx else { return QJS_Undefined() }
            // NSWorkspace only answers on the main thread; the polling read that
            // needs the pid does not run there.
            let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
            return JSBridge.promise(ctx, dryRun: NSNull()) {
                .of(AXTree.selectedText(frontmostPID: pid))
            }
        }

        JSBridge.fn(ctx, ax, "children", 1) { ctx, _, argc, argv in
            guard let ctx else { return QJS_Undefined() }
            if AXModule.dryRun(ctx) { return JSBridge.newArray(ctx, []) }
            guard let argv, argc >= 1, let el = AXModule.element(ctx, argv[0]) else {
                return JSBridge.newArray(ctx, [])
            }
            return JSBridge.newArray(ctx, AXTree.children(el).map { AXModule.dict($0, ctx) })
        }

        JSBridge.fn(ctx, ax, "parent", 1) { ctx, _, argc, argv in
            guard let ctx else { return QJS_Undefined() }
            if AXModule.dryRun(ctx) { return QJS_Null() }
            guard let argv, argc >= 1, let el = AXModule.element(ctx, argv[0]),
                  let parent = AXTree.parent(el) else {
                return QJS_Null()
            }
            return AXModule.wrap(ctx, parent)
        }

        JSBridge.fn(ctx, ax, "press", 1) { ctx, _, argc, argv in
            guard let ctx else { return JSBridge.newBool(ctx!, false) }
            if AXModule.dryRun(ctx) { return JSBridge.newBool(ctx, false) }
            guard let argv, argc >= 1, let el = AXModule.element(ctx, argv[0]) else {
                return JSBridge.newBool(ctx, false)
            }
            return JSBridge.newBool(ctx, AXTree.press(el))
        }

        JSBridge.fn(ctx, ax, "setValue", 2) { ctx, _, argc, argv in
            guard let ctx else { return JSBridge.newBool(ctx!, false) }
            if AXModule.dryRun(ctx) { return JSBridge.newBool(ctx, false) }
            guard let argv, argc >= 2, let el = AXModule.element(ctx, argv[0]),
                  let value = JSBridge.toString(ctx, argv[1]) else {
                return JSBridge.newBool(ctx, false)
            }
            return JSBridge.newBool(ctx, AXTree.setValue(el, value))
        }

        JSBridge.fn(ctx, ax, "find", 1) { ctx, _, argc, argv in
            guard let ctx else { return QJS_Undefined() }
            if AXModule.dryRun(ctx) { return QJS_Null() }
            guard let argv, argc >= 1 else { return QJS_Null() }
            let opts = argv[0]
            let roleVal = JSBridge.getProperty(ctx, opts, "role")
            let titleVal = JSBridge.getProperty(ctx, opts, "title")
            let role = JSBridge.isUndefined(roleVal) || JSBridge.isNull(roleVal) ? nil : JSBridge.toString(ctx, roleVal)
            let title = JSBridge.isUndefined(titleVal) || JSBridge.isNull(titleVal) ? nil : JSBridge.toString(ctx, titleVal)
            JS_FreeValue(ctx, roleVal)
            JS_FreeValue(ctx, titleVal)
            guard let el = AXTree.find(role: role, title: title) else { return QJS_Null() }
            return AXModule.wrap(ctx, el)
        }

        JS_SetPropertyStr(ctx, macotron, "ax", ax)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)
    }

    public func cleanup() {
        handles.clear()
    }

    fileprivate static func wrap(_ ctx: OpaquePointer, _ el: AXUIElement) -> JSValue {
        JSBridge.newObject(ctx, dict(el, ctx))
    }

    fileprivate static func dict(_ el: AXUIElement, _ ctx: OpaquePointer) -> [String: Any] {
        guard let module = module(ctx) else { return [:] }
        let id = module.handles.alloc(el)
        return AXTree.node(id: id, el)
    }

    fileprivate static func element(_ ctx: OpaquePointer, _ val: JSValue) -> AXUIElement? {
        module(ctx)?.handles.lookup(JSBridge.toInt32(ctx, val))
    }

    fileprivate static func module(_ ctx: OpaquePointer) -> AXModule? {
        guard let opaque = JS_GetContextOpaque(ctx) else { return nil }
        let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()
        return engine.configStore["__axModule"] as? AXModule
    }

    fileprivate static func dryRun(_ ctx: OpaquePointer) -> Bool {
        guard let opaque = JS_GetContextOpaque(ctx) else { return false }
        return Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue().dryRun
    }
}
