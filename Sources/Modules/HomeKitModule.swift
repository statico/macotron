// HomeKitModule.swift — macotron.homekit: Home scenes as shortcuts
import CQuickJS
import Foundation
import MacotronEngine

// HomeKit.framework reaches Mac apps only through Mac Catalyst with an App
// Store or development profile; a Developer ID build gets no homes. So a
// "scene" is a shortcut the user keeps in one Shortcuts folder, and running it
// goes through /usr/bin/shortcuts like macotron.shortcuts.

@MainActor
public final class HomeKitModule: NativeModule {
    public let name = "homekit"
    public let moduleVersion = 2

    static let defaultFolder = "Home"

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JSBridge.getProperty(ctx, global, "macotron")
        let homekit = JS_NewObject(ctx)

        JSBridge.fn(ctx, homekit, "scenes", 1) { ctx, _, argc, argv in
            guard let ctx else { return QJS_Undefined() }
            let asked = argc >= 1 && JS_IsObject(argv![0]) ? JSBridge.string(ctx, argv![0], "folder") : nil
            let folder = asked ?? HomeKitModule.defaultFolder
            return JSBridge.promise(ctx, dryRun: [Any]()) {
                .value(ShortcutsCLI.list(folder: folder))
            }
        }

        JSBridge.fn(ctx, homekit, "run", 1) { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 1, let name = JSBridge.toString(ctx, argv[0]) else {
                return JSBridge.newBool(ctx!, false)
            }
            return JSBridge.promise(ctx, dryRun: true) {
                .value(ShortcutsCLI.runShortcut(name).ok)
            }
        }

        JS_SetPropertyStr(ctx, macotron, "homekit", homekit)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)
    }
}
