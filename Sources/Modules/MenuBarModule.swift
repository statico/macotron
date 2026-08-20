// MenuBarModule.swift — JS bridge for macotron.menubar
// Delegates actual menu operations to MenuBarManager via protocol.
import CQuickJS
import Foundation
import MacotronEngine

/// Delegate protocol so the Modules target doesn't depend on MacotronUI.
/// MenuBarManager (in MacotronUI) conforms to this and is assigned at app startup.
@MainActor
public protocol MenuBarModuleDelegate: AnyObject {
    func menuBarAddItem(id: String, title: String, icon: String?, section: String?, onClick: (() -> Void)?, menu: [MenuBarEntry])
    func menuBarUpdateItem(id: String, title: String?, icon: String?)
    func menuBarRemoveItem(id: String)
    func menuBarSetIcon(sfSymbolName: String)
    func menuBarSetIconColor(color: String?)
    func menuBarSetTitle(text: String)
    func menuBarSetStatus(
        id: String,
        title: String,
        subtitle: String?,
        color: String?,
        subtitleColor: String?,
        bold: Bool,
        italic: Bool,
        secondary: Bool,
        minWidth: Double?,
        sfSymbol: String?,
        imagePath: String?,
        onClick: (() -> Void)?,
        menu: [MenuBarEntry]
    )
    func menuBarRemoveStatus(id: String)
    func menuBarRemoveAllStatus()
    func menuBarBeginStatusReload()
    func menuBarFinishStatusReload()
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

            if let mod = engine.configStore["__menuBarModule"] as? MenuBarModule {
                mod.dropCallbacks(for: id, ctx: ctx)
                let onClick: (() -> Void)? = mod.bindClick(ctx: ctx, from: onClickVal, key: id)
                let menu = mod.readMenu(ctx: ctx, from: opts, prefix: id)
                mod.delegate?.menuBarAddItem(
                    id: id, title: title, icon: icon, section: section, onClick: onClick, menu: menu
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
                mod.dropCallbacks(for: id, ctx: ctx)
                mod.delegate?.menuBarRemoveStatus(id: id)
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

        JS_SetPropertyStr(ctx, menubarObj, "setIconColor", JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv else { return QJS_Undefined() }
            let opaque = JS_GetContextOpaque(ctx)
            guard let opaque else { return QJS_Undefined() }
            let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()
            var color: String?
            if argc >= 1 {
                let raw = argv[0]
                if !JSBridge.isUndefined(raw), !JSBridge.isNull(raw) {
                    color = JSBridge.toString(ctx, raw)
                }
            }
            if let mod = engine.configStore["__menuBarModule"] as? MenuBarModule {
                mod.delegate?.menuBarSetIconColor(color: color)
            }
            return QJS_Undefined()
        }, "setIconColor", 1))

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

        JS_SetPropertyStr(ctx, menubarObj, "status", JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 2 else { return QJS_Undefined() }
            let opaque = JS_GetContextOpaque(ctx)
            guard let opaque else { return QJS_Undefined() }
            let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()
            guard let id = JSBridge.toString(ctx, argv[0]) else { return QJS_Undefined() }
            let opts = argv[1]

            let titleVal = JSBridge.getProperty(ctx, opts, "title")
            let title = JSBridge.toString(ctx, titleVal) ?? id
            JS_FreeValue(ctx, titleVal)

            let subtitleVal = JSBridge.getProperty(ctx, opts, "subtitle")
            let subtitle: String? = JSBridge.isUndefined(subtitleVal) || JSBridge.isNull(subtitleVal)
                ? nil : JSBridge.toString(ctx, subtitleVal)
            JS_FreeValue(ctx, subtitleVal)

            let colorVal = JSBridge.getProperty(ctx, opts, "color")
            let color: String? = JSBridge.isUndefined(colorVal) || JSBridge.isNull(colorVal)
                ? nil : JSBridge.toString(ctx, colorVal)
            JS_FreeValue(ctx, colorVal)

            let subtitleColorVal = JSBridge.getProperty(ctx, opts, "subtitleColor")
            let subtitleColor: String? = JSBridge.isUndefined(subtitleColorVal) || JSBridge.isNull(subtitleColorVal)
                ? nil : JSBridge.toString(ctx, subtitleColorVal)
            JS_FreeValue(ctx, subtitleColorVal)

            let boldVal = JSBridge.getProperty(ctx, opts, "bold")
            let bold = JSBridge.isUndefined(boldVal) || JSBridge.isNull(boldVal) ? false : JSBridge.toBool(ctx, boldVal)
            JS_FreeValue(ctx, boldVal)

            let italicVal = JSBridge.getProperty(ctx, opts, "italic")
            let italic = JSBridge.isUndefined(italicVal) || JSBridge.isNull(italicVal) ? false : JSBridge.toBool(ctx, italicVal)
            JS_FreeValue(ctx, italicVal)

            let secondaryVal = JSBridge.getProperty(ctx, opts, "secondary")
            let secondary = JSBridge.isUndefined(secondaryVal) || JSBridge.isNull(secondaryVal)
                ? false : JSBridge.toBool(ctx, secondaryVal)
            JS_FreeValue(ctx, secondaryVal)

            let minWidthVal = JSBridge.getProperty(ctx, opts, "minWidth")
            let minWidth: Double? = JSBridge.isUndefined(minWidthVal) || JSBridge.isNull(minWidthVal)
                ? nil : JSBridge.toDouble(ctx, minWidthVal)
            JS_FreeValue(ctx, minWidthVal)

            let sfVal = JSBridge.getProperty(ctx, opts, "sfSymbol")
            var sfSymbol: String? = JSBridge.isUndefined(sfVal) || JSBridge.isNull(sfVal)
                ? nil : JSBridge.toString(ctx, sfVal)
            JS_FreeValue(ctx, sfVal)
            if sfSymbol == nil {
                let iconVal = JSBridge.getProperty(ctx, opts, "icon")
                sfSymbol = JSBridge.isUndefined(iconVal) || JSBridge.isNull(iconVal)
                    ? nil : JSBridge.toString(ctx, iconVal)
                JS_FreeValue(ctx, iconVal)
            }

            let imageVal = JSBridge.getProperty(ctx, opts, "image")
            let imagePath: String? = JSBridge.isUndefined(imageVal) || JSBridge.isNull(imageVal)
                ? nil : JSBridge.toString(ctx, imageVal)
            JS_FreeValue(ctx, imageVal)

            let onClickVal = JSBridge.getProperty(ctx, opts, "onClick")

            if let mod = engine.configStore["__menuBarModule"] as? MenuBarModule {
                mod.dropCallbacks(for: id, ctx: ctx)
                let onClick: (() -> Void)? = mod.bindClick(ctx: ctx, from: onClickVal, key: id)
                let menu = mod.readMenu(ctx: ctx, from: opts, prefix: id)
                mod.delegate?.menuBarSetStatus(
                    id: id,
                    title: title,
                    subtitle: subtitle,
                    color: color,
                    subtitleColor: subtitleColor,
                    bold: bold,
                    italic: italic,
                    secondary: secondary,
                    minWidth: minWidth,
                    sfSymbol: sfSymbol,
                    imagePath: imagePath,
                    onClick: onClick,
                    menu: menu
                )
            }
            JS_FreeValue(ctx, onClickVal)
            return QJS_Undefined()
        }, "status", 2))

        JS_SetPropertyStr(ctx, macotron, "menubar", menubarObj)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)

        // Stash self in configStore so C callbacks can find us
        engine.configStore["__menuBarModule"] = self
    }

    fileprivate func dropCallbacks(for id: String, ctx: OpaquePointer) {
        for key in callbacks.keys.filter({ $0 == id || $0.hasPrefix(id + "#") }) {
            if let cb = callbacks.removeValue(forKey: key) {
                JS_FreeValue(ctx, cb)
            }
        }
    }

    fileprivate func bindClick(ctx: OpaquePointer, from val: JSValue, key: String) -> (() -> Void)? {
        guard JS_IsFunction(ctx, val) else { return nil }
        callbacks[key] = JS_DupValue(ctx, val)
        let pluginFile = engine?.currentEvaluatingFile
        return { [weak self, weak engine] in
            guard let self, let engine, let ctx = engine.context else { return }
            guard let cb = self.callbacks[key] else { return }
            engine.withEvaluatingFile(pluginFile) {
                let fn = JS_DupValue(ctx, cb)
                _ = JS_Call(ctx, fn, QJS_Undefined(), 0, nil)
                JS_FreeValue(ctx, fn)
                engine.drainJobQueue()
            }
        }
    }

    fileprivate func readMenu(ctx: OpaquePointer, from opts: JSValue, prefix: String) -> [MenuBarEntry] {
        let menuVal = JSBridge.getProperty(ctx, opts, "menu")
        defer { JS_FreeValue(ctx, menuVal) }
        return parseMenu(ctx: ctx, menuVal, prefix: prefix)
    }

    private func parseMenu(ctx: OpaquePointer, _ val: JSValue, prefix: String) -> [MenuBarEntry] {
        guard JS_IsArray(val) else { return [] }
        let lenVal = JS_GetPropertyStr(ctx, val, "length")
        let len = JSBridge.toInt32(ctx, lenVal)
        JS_FreeValue(ctx, lenVal)
        var entries: [MenuBarEntry] = []
        for idx in 0..<len {
            let elem = JS_GetPropertyUint32(ctx, val, UInt32(idx))
            let key = "\(prefix)#\(idx)"
            if JS_IsString(elem) {
                entries.append(MenuBarEntry(title: JSBridge.toString(ctx, elem) ?? "-"))
            } else if JS_IsObject(elem) {
                let titleVal = JSBridge.getProperty(ctx, elem, "title")
                let title = JSBridge.toString(ctx, titleVal) ?? ""
                JS_FreeValue(ctx, titleVal)
                let iconVal = JSBridge.getProperty(ctx, elem, "icon")
                let icon: String? = JSBridge.isUndefined(iconVal) || JSBridge.isNull(iconVal)
                    ? nil : JSBridge.toString(ctx, iconVal)
                JS_FreeValue(ctx, iconVal)
                let onClickVal = JSBridge.getProperty(ctx, elem, "onClick")
                let onClick = bindClick(ctx: ctx, from: onClickVal, key: key)
                JS_FreeValue(ctx, onClickVal)
                let nestedVal = JSBridge.getProperty(ctx, elem, "menu")
                let children = parseMenu(ctx: ctx, nestedVal, prefix: key)
                JS_FreeValue(ctx, nestedVal)
                entries.append(MenuBarEntry(title: title, icon: icon, onClick: onClick, children: children))
            }
            JS_FreeValue(ctx, elem)
        }
        return entries
    }

    public func cleanup() {
        guard let ctx = engine?.context else { return }
        for (_, cb) in callbacks {
            JS_FreeValue(ctx, cb)
        }
        callbacks.removeAll()
        engine?.configStore.removeValue(forKey: "__menuBarModule")
        // Keep extra status items on screen; plugins re-apply in place after reload.
        delegate?.menuBarBeginStatusReload()
    }

    public func didReload() {
        delegate?.menuBarFinishStatusReload()
    }
}
