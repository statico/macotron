// KeyboardModule.swift — macotron.keyboard: global keyboard shortcut registration
import CQuickJS
import MacotronEngine
import Foundation
import CoreGraphics
import os

private let logger = Logger(subsystem: "io.statico.macotron", category: "keyboard")

@MainActor
public final class KeyboardModule: NativeModule {
    public let name = "keyboard"

    public var onHostCommand: ((String) -> Void)?

    private weak var engine: Engine?
    private var hostHotKeyIDs: [UInt32] = []
    private var pluginHotKeyIDs: [UInt32] = []

    public init() {}

    public func setHostBindings(_ bindings: [(commandId: String, combo: String)]) {
        CarbonHotKeys.shared.unregister(hostHotKeyIDs)
        hostHotKeyIDs.removeAll()
        guard engine?.dryRun != true else { return }
        for item in bindings {
            guard let combo = KeyCombo.parse(item.combo) else {
                NSLog("[Macotron] Skipping invalid command shortcut '%@' for %@", item.combo, item.commandId)
                continue
            }
            let commandId = item.commandId
            if let id = CarbonHotKeys.shared.register(
                keyCode: UInt32(combo.keyCode),
                carbonModifiers: combo.carbonModifiers,
                handler: { [weak self] in
                    DispatchQueue.main.async { self?.onHostCommand?(commandId) }
                }
            ) {
                hostHotKeyIDs.append(id)
            }
        }
    }

    public func setPluginBindings(_ bindings: [(eventName: String, combo: String)]) {
        CarbonHotKeys.shared.unregister(pluginHotKeyIDs)
        pluginHotKeyIDs.removeAll()
        guard engine?.dryRun != true else { return }
        for item in bindings {
            guard let combo = KeyCombo.parse(item.combo) else {
                NSLog("[Macotron] Skipping invalid plugin shortcut '%@'", item.combo)
                continue
            }
            let eventName = item.eventName
            if let id = CarbonHotKeys.shared.register(
                keyCode: UInt32(combo.keyCode),
                carbonModifiers: combo.carbonModifiers,
                handler: { [weak self] in
                    DispatchQueue.main.async {
                        guard let self, let engine = self.engine else { return }
                        engine.eventBus.emit(eventName, engine: engine)
                    }
                }
            ) {
                pluginHotKeyIDs.append(id)
            }
        }
    }

    public func register(in engine: Engine, options: [String: Any]) {
        self.engine = engine
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JSBridge.getProperty(ctx, global, "macotron")

        let keyboardObj = JS_NewObject(ctx)

        // ---------- on(id, defaultCombo, callback) ----------
        JS_SetPropertyStr(ctx, keyboardObj, "on", JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 3 else {
                return QJS_ThrowTypeError(ctx, "keyboard.on(id, default, callback)")
            }
            guard let key = JSBridge.toString(ctx, argv[0]), !key.isEmpty else {
                return QJS_ThrowTypeError(ctx, "keyboard.on requires an id")
            }
            guard let defaultCombo = JSBridge.toString(ctx, argv[1]), !defaultCombo.isEmpty else {
                return QJS_ThrowTypeError(ctx, "keyboard.on requires a default shortcut")
            }

            let opaque = JS_GetContextOpaque(ctx)
            guard let opaque else { return QJS_Undefined() }
            let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()
            let pluginFile = engine.currentEvaluatingFile ?? ""
            let fullId = pluginFile.isEmpty ? key : "\(pluginFile)/\(key)"
            let table = CommandShortcuts.load(from: engine.configStore["keyboardShortcuts"])
            let comboStr = table.resolved(fullId, default: defaultCombo)

            engine.hotkeyRegistry[fullId] = RegisteredHotkey(
                id: fullId,
                pluginFile: pluginFile,
                key: key,
                defaultCombo: defaultCombo
            )
            engine.eventBus.on("keyboard:\(fullId)", callback: argv[2], ctx: ctx)

            if !comboStr.isEmpty, KeyCombo.parse(comboStr) == nil {
                logger.warning("Failed to parse keyboard combo: \(comboStr)")
            }

            return QJS_Undefined()
        }, "on", 3))

        JS_SetPropertyStr(ctx, keyboardObj, "flags", JS_NewCFunction(ctx, { ctx, _, _, _ in
            guard let ctx else { return QJS_Undefined() }
            let flags = CGEventSource.flagsState(.hidSystemState)
            return JSBridge.newObject(ctx, [
                "cmd": flags.contains(.maskCommand),
                "shift": flags.contains(.maskShift),
                "ctrl": flags.contains(.maskControl),
                "opt": flags.contains(.maskAlternate),
                "caps": flags.contains(.maskAlphaShift),
                "fn": flags.contains(.maskSecondaryFn),
            ])
        }, "flags", 0))

        JS_SetPropertyStr(ctx, macotron, "keyboard", keyboardObj)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)
    }

    public func cleanup() {
        CarbonHotKeys.shared.unregister(pluginHotKeyIDs)
        pluginHotKeyIDs.removeAll()
    }
}
