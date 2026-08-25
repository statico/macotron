// ShortcutsModule.swift — macotron.shortcuts: list and run Shortcuts.app
import CQuickJS
import Foundation
import MacotronEngine

@MainActor
public final class ShortcutsModule: NativeModule {
    public let name = "shortcuts"
    public let moduleVersion = 1

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JSBridge.getProperty(ctx, global, "macotron")
        let shortcuts = JS_NewObject(ctx)

        // Both shell out to /usr/bin/shortcuts: listing waits on Shortcuts.app's
        // database, and running waits on the whole shortcut to finish.
        JS_SetPropertyStr(ctx, shortcuts, "list", JS_NewCFunction(ctx, { ctx, _, _, _ in
            guard let ctx else { return QJS_Undefined() }
            return JSBridge.promise(ctx, dryRun: [Any]()) {
                .value(ShortcutsCLI.list())
            }
        }, "list", 0))

        JS_SetPropertyStr(ctx, shortcuts, "run", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 1, let name = JSBridge.toString(ctx, argv[0]) else {
                return JSBridge.newBool(ctx!, false)
            }
            return JSBridge.promise(ctx, dryRun: true) {
                .value(ShortcutsCLI.runShortcut(name).ok)
            }
        }, "run", 1))

        JS_SetPropertyStr(ctx, macotron, "shortcuts", shortcuts)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)
    }
}
