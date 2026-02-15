// MenuBarModule.swift — JS bridge for macotron.menubar
// Delegates actual menu operations to MenuBarManager via protocol.
import CQuickJS
import Foundation
import MacotronEngine

/// Delegate protocol so the Modules target doesn't depend on MacotronUI.
/// MenuBarManager (in MacotronUI) conforms to this and is assigned at app startup.
@MainActor
public protocol MenuBarModuleDelegate: AnyObject {
    func menuBarAddItem(id: String, title: String, icon: String?, section: String?, onClick: (() -> Void)?)
    func menuBarUpdateItem(id: String, title: String?, icon: String?)
    func menuBarRemoveItem(id: String)
    func menuBarSetIcon(sfSymbolName: String)
    func menuBarSetTitle(text: String)
}

@MainActor
public final class MenuBarModule: NativeModule {
    public let name = "menubar"

    public weak var delegate: MenuBarModuleDelegate?

    /// Stored JS onClick callbacks keyed by menu item ID.
    /// Values are DupValue'd so QuickJS won't GC them.
    private var callbacks: [String: JSValue] = [:]

    /// Keep a reference to the engine context for invoking callbacks and cleanup.
    private weak var engine: Engine?

    public init() {}

    // MARK: - NativeModule

    public func register(in engine: Engine, options: [String: Any]) {
        self.engine = engine
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JSBridge.getProperty(ctx, global, "macotron")

        let menubarObj = JS_NewObject(ctx)

        // --- add(id, opts) ---
        JS_SetPropertyStr(ctx, menubarObj, "add", JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 2 else { return QJS_Undefined() }
            let opaque = JS_GetContextOpaque(ctx)
            guard let opaque else { return QJS_Undefined() }
            let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()

            guard let id = JSBridge.toString(ctx, argv[0]) else { return QJS_Undefined() }
            let opts = argv[1]

            let titleVal = JSBridge.getProperty(ctx, opts, "title")
            let title = JSBridge.toString(ctx, titleVal) ?? id
            JS_FreeValue(ctx, titleVal)

            let iconVal = JSBridge.getProperty(ctx, opts, "icon")
            let icon: String? = JSBridge.isUndefined(iconVal) || JSBridge.isNull(iconVal)
                ? nil : JSBridge.toString(ctx, iconVal)
            JS_FreeValue(ctx, iconVal)

            let sectionVal = JSBridge.getProperty(ctx, opts, "section")
            let section: String? = JSBridge.isUndefined(sectionVal) || JSBridge.isNull(sectionVal)
                ? nil : JSBridge.toString(ctx, sectionVal)
            JS_FreeValue(ctx, sectionVal)

            let onClickVal = JSBridge.getProperty(ctx, opts, "onClick")
            let hasOnClick = !(JSBridge.isUndefined(onClickVal) || JSBridge.isNull(onClickVal))

            // Find the MenuBarModule instance via engine's modules
            // We stash ourselves in the engine's configStore under a private key.
            if let mod = engine.configStore["__menuBarModule"] as? MenuBarModule {
                // Free any previously stored callback for this id
                if let prev = mod.callbacks[id] {
                    JS_FreeValue(ctx, prev)
                }
                if hasOnClick {
                    mod.callbacks[id] = JS_DupValue(ctx, onClickVal)
                } else {
                    mod.callbacks.removeValue(forKey: id)
                }

                let onClick: (() -> Void)? = hasOnClick ? { [weak mod, weak engine] in
                    guard let mod, let engine, let ctx = engine.context else { return }
                    if let cb = mod.callbacks[id] {
                        _ = JS_Call(ctx, cb, QJS_Undefined(), 0, nil)
                        engine.drainJobQueue()
                    }
                } : nil

                mod.delegate?.menuBarAddItem(
                    id: id, title: title, icon: icon, section: section, onClick: onClick
                )
            }

            JS_FreeValue(ctx, onClickVal)
            return QJS_Undefined()
        }, "add", 2))

        // --- update(id, opts) ---
        JS_SetPropertyStr(ctx, menubarObj, "update", JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 2 else { return QJS_Undefined() }
            let opaque = JS_GetContextOpaque(ctx)
            guard let opaque else { return QJS_Undefined() }
            let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()

            guard let id = JSBridge.toString(ctx, argv[0]) else { return QJS_Undefined() }
            let opts = argv[1]

            let titleVal = JSBridge.getProperty(ctx, opts, "title")
            let title: String? = JSBridge.isUndefined(titleVal) || JSBridge.isNull(titleVal)
                ? nil : JSBridge.toString(ctx, titleVal)
            JS_FreeValue(ctx, titleVal)

            let iconVal = JSBridge.getProperty(ctx, opts, "icon")
            let icon: String? = JSBridge.isUndefined(iconVal) || JSBridge.isNull(iconVal)
                ? nil : JSBridge.toString(ctx, iconVal)
            JS_FreeValue(ctx, iconVal)

            if let mod = engine.configStore["__menuBarModule"] as? MenuBarModule {
                mod.delegate?.menuBarUpdateItem(id: id, title: title, icon: icon)
            }

            return QJS_Undefined()
        }, "update", 2))

        // --- remove(id) ---
        JS_SetPropertyStr(ctx, menubarObj, "remove", JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 1 else { return QJS_Undefined() }
            let opaque = JS_GetContextOpaque(ctx)
            guard let opaque else { return QJS_Undefined() }
            let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()

            guard let id = JSBridge.toString(ctx, argv[0]) else { return QJS_Undefined() }

            if let mod = engine.configStore["__menuBarModule"] as? MenuBarModule {
                // Free stored callback if any
                if let cb = mod.callbacks.removeValue(forKey: id) {
                    JS_FreeValue(ctx, cb)
                }
                mod.delegate?.menuBarRemoveItem(id: id)
            }

            return QJS_Undefined()
        }, "remove", 1))

        // --- setIcon(sfSymbolName) ---
        JS_SetPropertyStr(ctx, menubarObj, "setIcon", JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 1 else { return QJS_Undefined() }
            let opaque = JS_GetContextOpaque(ctx)
            guard let opaque else { return QJS_Undefined() }
            let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()

            guard let symbolName = JSBridge.toString(ctx, argv[0]) else { return QJS_Undefined() }

            if let mod = engine.configStore["__menuBarModule"] as? MenuBarModule {
                mod.delegate?.menuBarSetIcon(sfSymbolName: symbolName)
            }

            return QJS_Undefined()
        }, "setIcon", 1))

        // --- setTitle(text) ---
        JS_SetPropertyStr(ctx, menubarObj, "setTitle", JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 1 else { return QJS_Undefined() }
            let opaque = JS_GetContextOpaque(ctx)
            guard let opaque else { return QJS_Undefined() }
            let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()

            guard let text = JSBridge.toString(ctx, argv[0]) else { return QJS_Undefined() }

            if let mod = engine.configStore["__menuBarModule"] as? MenuBarModule {
                mod.delegate?.menuBarSetTitle(text: text)
            }

            return QJS_Undefined()
        }, "setTitle", 1))

        JS_SetPropertyStr(ctx, macotron, "menubar", menubarObj)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)

        // Stash self in configStore so C callbacks can find us
        engine.configStore["__menuBarModule"] = self
    }

    public func cleanup() {
        guard let ctx = engine?.context else { return }
        for (_, cb) in callbacks {
            JS_FreeValue(ctx, cb)
        }
        callbacks.removeAll()
        engine?.configStore.removeValue(forKey: "__menuBarModule")
    }
}
