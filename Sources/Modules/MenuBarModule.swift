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
    func updateItem(id: String, title: String?, icon: String?)
    func removeItem(id: String)
    func setIcon(_ sfSymbolName: String)
    func setIconColor(_ color: String?)
    func setTitle(_ text: String)
    func setStatus(
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
        menu: [MenuBarEntry],
        required: Bool
    )
    func removeStatus(id: String)
    func removeAllStatus()
    func beginStatusReload()
    func finishStatusReload()
}

@MainActor
public final class MenuBarModule: NativeModule {
    public let name = "menubar"

    public weak var delegate: MenuBarModuleDelegate?

    /// status id -> plugin filename, so Settings can show a missing item on the
    /// page of the plugin that asked for it.
    public var statusOwners: [String: String] = [:]

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

            guard let id = JSBridge.toString(ctx, argv[0]) else { return QJS_Undefined() }
            let opts = argv[1]

            let title = JSBridge.string(ctx, opts, "title") ?? id
            let icon = JSBridge.string(ctx, opts, "icon")
            let section = JSBridge.string(ctx, opts, "section")

            let onClickVal = JSBridge.getProperty(ctx, opts, "onClick")

            if let mod: MenuBarModule = Engine.module(ctx, "__menuBarModule") {
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

            guard let id = JSBridge.toString(ctx, argv[0]) else { return QJS_Undefined() }
            let opts = argv[1]

            let title = JSBridge.string(ctx, opts, "title")
            let icon = JSBridge.string(ctx, opts, "icon")

            if let mod: MenuBarModule = Engine.module(ctx, "__menuBarModule") {
                mod.delegate?.updateItem(id: id, title: title, icon: icon)
            }

            return QJS_Undefined()
        }, "update", 2))

        // --- remove(id) ---
        JS_SetPropertyStr(ctx, menubarObj, "remove", JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 1 else { return QJS_Undefined() }

            guard let id = JSBridge.toString(ctx, argv[0]) else { return QJS_Undefined() }

            if let mod: MenuBarModule = Engine.module(ctx, "__menuBarModule") {
                mod.statusOwners[id] = nil
                mod.dropCallbacks(for: id, ctx: ctx)
                mod.delegate?.removeStatus(id: id)
                mod.delegate?.removeItem(id: id)
            }

            return QJS_Undefined()
        }, "remove", 1))

        // --- setIcon(sfSymbolName) ---
        JS_SetPropertyStr(ctx, menubarObj, "setIcon", JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 1 else { return QJS_Undefined() }

            guard let symbolName = JSBridge.toString(ctx, argv[0]) else { return QJS_Undefined() }

            if let mod: MenuBarModule = Engine.module(ctx, "__menuBarModule") {
                mod.delegate?.setIcon(symbolName)
            }

            return QJS_Undefined()
        }, "setIcon", 1))

        JS_SetPropertyStr(ctx, menubarObj, "setIconColor", JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv else { return QJS_Undefined() }
            var color: String?
            if argc >= 1 {
                let raw = argv[0]
                if !JSBridge.isUndefined(raw), !JSBridge.isNull(raw) {
                    color = JSBridge.toString(ctx, raw)
                }
            }
            if let mod: MenuBarModule = Engine.module(ctx, "__menuBarModule") {
                mod.delegate?.setIconColor(color)
            }
            return QJS_Undefined()
        }, "setIconColor", 1))

        // --- setTitle(text) ---
        JS_SetPropertyStr(ctx, menubarObj, "setTitle", JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 1 else { return QJS_Undefined() }

            guard let text = JSBridge.toString(ctx, argv[0]) else { return QJS_Undefined() }

            if let mod: MenuBarModule = Engine.module(ctx, "__menuBarModule") {
                mod.delegate?.setTitle(text)
            }

            return QJS_Undefined()
        }, "setTitle", 1))

        JS_SetPropertyStr(ctx, menubarObj, "status", JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 2 else { return QJS_Undefined() }
            guard let id = JSBridge.toString(ctx, argv[0]) else { return QJS_Undefined() }
            let opts = argv[1]

            let title = JSBridge.string(ctx, opts, "title") ?? id
            let subtitle = JSBridge.string(ctx, opts, "subtitle")
            let color = JSBridge.string(ctx, opts, "color")
            let subtitleColor = JSBridge.string(ctx, opts, "subtitleColor")
            let bold = JSBridge.bool(ctx, opts, "bold") ?? false
            let italic = JSBridge.bool(ctx, opts, "italic") ?? false
            let secondary = JSBridge.bool(ctx, opts, "secondary") ?? false
            let minWidth = JSBridge.double(ctx, opts, "minWidth")
            // Absent means required: a plugin only opts out on purpose.
            let required = JSBridge.bool(ctx, opts, "required") ?? true
            let sfSymbol = JSBridge.string(ctx, opts, "sfSymbol") ?? JSBridge.string(ctx, opts, "icon")
            var imagePath = JSBridge.string(ctx, opts, "image")

            if let png = SparklineImage.png(fromJS: ctx, opts: opts) {
                let safe = id.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
                // AppKit's own convention: a name ending in Template means a mask.
                let suffix = png.template ? "Template" : ""
                let path = (NSTemporaryDirectory() as NSString)
                    .appendingPathComponent("macotron-status-\(safe)\(suffix).png")
                // Rewriting an identical image bumps its timestamp, which is
                // how the status item tells a real repaint from a no-op tick.
                let url = URL(fileURLWithPath: path)
                if (try? Data(contentsOf: url)) == png.data {
                    imagePath = path
                } else if (try? png.data.write(to: url)) != nil {
                    imagePath = path
                }
            }

            let onClickVal = JSBridge.getProperty(ctx, opts, "onClick")

            if let mod: MenuBarModule = Engine.module(ctx, "__menuBarModule") {
                if let file = Engine.of(ctx)?.currentEvaluatingFile { mod.statusOwners[id] = file }
                mod.dropCallbacks(for: id, ctx: ctx)
                let onClick: (() -> Void)? = mod.bindClick(ctx: ctx, from: onClickVal, key: id)
                let menu = mod.readMenu(ctx: ctx, from: opts, prefix: id)
                mod.delegate?.setStatus(
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
                    menu: menu,
                    required: required
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
                if let result = engine.callJS(fn, label: "menubar click \(key)") {
                    JS_FreeValue(ctx, result)
                }
                JS_FreeValue(ctx, fn)
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
                let title = JSBridge.string(ctx, elem, "title") ?? ""
                let icon = JSBridge.string(ctx, elem, "icon")
                let onClickVal = JSBridge.getProperty(ctx, elem, "onClick")
                let onClick = bindClick(ctx: ctx, from: onClickVal, key: key)
                JS_FreeValue(ctx, onClickVal)
                let nestedVal = JSBridge.getProperty(ctx, elem, "menu")
                var children = parseMenu(ctx: ctx, nestedVal, prefix: key)
                JS_FreeValue(ctx, nestedVal)
                let buttonsVal = JSBridge.getProperty(ctx, elem, "buttons")
                var inline = false
                if JS_IsArray(buttonsVal) {
                    children = parseMenu(ctx: ctx, buttonsVal, prefix: "\(key)!")
                    inline = true
                }
                JS_FreeValue(ctx, buttonsVal)
                let html = JSBridge.string(ctx, elem, "html")
                entries.append(MenuBarEntry(
                    title: title,
                    icon: icon,
                    onClick: onClick,
                    children: children,
                    html: html,
                    inline: inline,
                    width: JSBridge.double(ctx, elem, "width") ?? 260,
                    height: JSBridge.double(ctx, elem, "height") ?? 160
                ))
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
        delegate?.beginStatusReload()
    }

    public func didReload() {
        delegate?.finishStatusReload()
    }
}
