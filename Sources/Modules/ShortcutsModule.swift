// ShortcutsModule.swift — macotron.shortcuts: list and run Shortcuts.app
import CQuickJS
import Foundation
import MacotronEngine

@MainActor
public final class ShortcutsModule: NativeModule {
    public let name = "shortcuts"

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JSBridge.getProperty(ctx, global, "macotron")
        let shortcuts = JS_NewObject(ctx)

        // Both shell out to /usr/bin/shortcuts: listing waits on Shortcuts.app's
        // database, and running waits on the whole shortcut to finish.
        JSBridge.fn(ctx, shortcuts, "list", 0) { ctx, _, _, _ in
            guard let ctx else { return QJS_Undefined() }
            return JSBridge.promise(ctx, dryRun: [Any]()) {
                .value(ShortcutsCLI.list())
            }
        }

        JSBridge.fn(ctx, shortcuts, "run", 1) { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 1, let name = JSBridge.toString(ctx, argv[0]) else {
                return JSBridge.newBool(ctx!, false)
            }
            return JSBridge.promise(ctx, dryRun: true) {
                .value(ShortcutsCLI.runShortcut(name).ok)
            }
        }

        JS_SetPropertyStr(ctx, macotron, "shortcuts", shortcuts)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)
    }
}
