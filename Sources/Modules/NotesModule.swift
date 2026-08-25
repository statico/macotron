import CQuickJS
import Foundation
import MacotronEngine

@MainActor
public final class NotesModule: NativeModule {
    public let name = "notes"

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JSBridge.getProperty(ctx, global, "macotron")
        let notes = JS_NewObject(ctx)

        JS_SetPropertyStr(ctx, notes, "list", JS_NewCFunction(ctx, { ctx, _, _, _ in
            guard let ctx else { return QJS_Undefined() }
            return JSBridge.promise(ctx, dryRun: [Any]()) {
                .value(NotesList.visible(NotesStore.list()).map { note in
                    [
                        "id": note.id,
                        "title": note.title,
                        "folder": note.folder,
                    ] as [String: Any]
                })
            }
        }, "list", 0))

        JS_SetPropertyStr(ctx, notes, "open", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 1, let id = JSBridge.toString(ctx, argv[0]) else {
                return QJS_Undefined()
            }
            return JSBridge.promise(ctx) {
                NotesStore.open(id)
                return .value(NSNull())
            }
        }, "open", 1))

        JS_SetPropertyStr(ctx, macotron, "notes", notes)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)
    }
}
