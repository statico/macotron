// DialogModule.swift — browser-style alert, confirm, and prompt
import AppKit
import CQuickJS
import Foundation
import MacotronEngine

@MainActor
enum Dialog {
    static func alert(
        _ message: String,
        dryRun: Bool,
        run: (NSAlert) -> NSApplication.ModalResponse = { $0.runModal() }
    ) {
        guard !dryRun else { return }
        _ = run(sheet(message, buttons: ["OK"]))
    }

    static func confirm(
        _ message: String,
        dryRun: Bool,
        run: (NSAlert) -> NSApplication.ModalResponse = { $0.runModal() }
    ) -> Bool {
        guard !dryRun else { return false }
        return run(sheet(message, buttons: ["OK", "Cancel"])) == .alertFirstButtonReturn
    }

    static func prompt(
        _ message: String,
        defaultValue: String,
        dryRun: Bool,
        run: (NSAlert) -> NSApplication.ModalResponse = { $0.runModal() }
    ) -> String? {
        guard !dryRun else { return nil }
        let alert = sheet(message, buttons: ["OK", "Cancel"])
        let field = NSTextField(string: defaultValue)
        field.frame.size = NSSize(width: 260, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard run(alert) == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }

    private static func sheet(_ message: String, buttons: [String]) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = message
        for title in buttons {
            alert.addButton(withTitle: title)
        }
        return alert
    }
}

@MainActor
public final class DialogModule: NativeModule {
    public let name = "dialog"
    public let moduleVersion = 1

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JSBridge.getProperty(ctx, global, "macotron")

        let alertFn = JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx else { return QJS_Undefined() }
            Dialog.alert(dialogMessage(ctx, argc, argv), dryRun: dialogDryRun(ctx))
            return QJS_Undefined()
        }, "alert", 1)
        JS_SetPropertyStr(ctx, global, "alert", JS_DupValue(ctx, alertFn))
        JS_SetPropertyStr(ctx, macotron, "alert", alertFn)

        let confirmFn = JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx else { return JSBridge.newBool(ctx!, false) }
            return JSBridge.newBool(ctx, Dialog.confirm(dialogMessage(ctx, argc, argv), dryRun: dialogDryRun(ctx)))
        }, "confirm", 1)
        JS_SetPropertyStr(ctx, global, "confirm", JS_DupValue(ctx, confirmFn))
        JS_SetPropertyStr(ctx, macotron, "confirm", confirmFn)

        let promptFn = JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx else { return QJS_Null() }
            let defaultValue = argc >= 2 ? (JSBridge.toString(ctx, argv![1]) ?? "") : ""
            if let text = Dialog.prompt(
                dialogMessage(ctx, argc, argv),
                defaultValue: defaultValue,
                dryRun: dialogDryRun(ctx)
            ) {
                return JSBridge.newString(ctx, text)
            }
            return QJS_Null()
        }, "prompt", 2)
        JS_SetPropertyStr(ctx, global, "prompt", JS_DupValue(ctx, promptFn))
        JS_SetPropertyStr(ctx, macotron, "prompt", promptFn)

        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)
    }
}

@MainActor
private func dialogMessage(_ ctx: OpaquePointer, _ argc: Int32, _ argv: UnsafePointer<JSValue>?) -> String {
    guard let argv, argc >= 1 else { return "" }
    return JSBridge.toString(ctx, argv[0]) ?? ""
}

@MainActor
private func dialogDryRun(_ ctx: OpaquePointer) -> Bool {
    guard let opaque = JS_GetContextOpaque(ctx) else { return false }
    return Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue().dryRun
}
