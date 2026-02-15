// FileSystemModule.swift — macotron.fs: file system operations from JS
import CQuickJS
import Foundation
import MacotronEngine
import os

private let logger = Logger(subsystem: "com.macotron", category: "fs")

@MainActor
public final class FileSystemModule: NativeModule {
    public let name = "fs"
    public let moduleVersion = 1

    public var defaultOptions: [String: Any] {
        // Default sandbox root: user's home directory
        ["sandboxRoot": NSHomeDirectory()]
    }

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JS_GetPropertyStr(ctx, global, "macotron")

        let fsObj = JS_NewObject(ctx)

        // -----------------------------------------------------------------
        // macotron.fs.read(path) -> string
        // -----------------------------------------------------------------
        JS_SetPropertyStr(ctx, fsObj, "read", JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 1 else {
                return QJS_ThrowTypeError(ctx, "fs.read requires a path argument")
            }
            guard let path = JSBridge.toString(ctx, argv[0]) else {
                return QJS_ThrowTypeError(ctx, "fs.read: path must be a string")
            }

            let expandedPath = NSString(string: path).expandingTildeInPath
            do {
                let content = try String(contentsOfFile: expandedPath, encoding: .utf8)
                logger.info("fs.read: \(expandedPath)")
                return JSBridge.newString(ctx, content)
            } catch {
                return QJS_ThrowInternalError(ctx, "fs.read failed: \(error.localizedDescription)")
            }
        }, "read", 1))

        // -----------------------------------------------------------------
        // macotron.fs.write(path, content) -> void
        // -----------------------------------------------------------------
        JS_SetPropertyStr(ctx, fsObj, "write", JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 2 else {
                return QJS_ThrowTypeError(ctx, "fs.write requires path and content arguments")
            }
            guard let path = JSBridge.toString(ctx, argv[0]) else {
                return QJS_ThrowTypeError(ctx, "fs.write: path must be a string")
            }
            guard let content = JSBridge.toString(ctx, argv[1]) else {
                return QJS_ThrowTypeError(ctx, "fs.write: content must be a string")
            }

            let expandedPath = NSString(string: path).expandingTildeInPath
            do {
                // Create intermediate directories if needed
                let dir = (expandedPath as NSString).deletingLastPathComponent
                try FileManager.default.createDirectory(
                    atPath: dir,
                    withIntermediateDirectories: true
                )
                try content.write(toFile: expandedPath, atomically: true, encoding: .utf8)
                logger.info("fs.write: \(expandedPath) (\(content.count) chars)")
                return QJS_Undefined()
            } catch {
                return QJS_ThrowInternalError(ctx, "fs.write failed: \(error.localizedDescription)")
            }
        }, "write", 2))

        // -----------------------------------------------------------------
        // macotron.fs.exists(path) -> bool
        // -----------------------------------------------------------------
        JS_SetPropertyStr(ctx, fsObj, "exists", JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 1 else {
                return QJS_ThrowTypeError(ctx, "fs.exists requires a path argument")
            }
            guard let path = JSBridge.toString(ctx, argv[0]) else {
                return QJS_ThrowTypeError(ctx, "fs.exists: path must be a string")
            }

            let expandedPath = NSString(string: path).expandingTildeInPath
            let exists = FileManager.default.fileExists(atPath: expandedPath)
            return JSBridge.newBool(ctx, exists)
        }, "exists", 1))

        // -----------------------------------------------------------------
        // macotron.fs.list(path) -> string[]
        // -----------------------------------------------------------------
        JS_SetPropertyStr(ctx, fsObj, "list", JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 1 else {
                return QJS_ThrowTypeError(ctx, "fs.list requires a path argument")
            }
            guard let path = JSBridge.toString(ctx, argv[0]) else {
                return QJS_ThrowTypeError(ctx, "fs.list: path must be a string")
            }

            let expandedPath = NSString(string: path).expandingTildeInPath
            do {
                let entries = try FileManager.default.contentsOfDirectory(atPath: expandedPath)
                let jsArr = JS_NewArray(ctx)
                for (i, entry) in entries.enumerated() {
                    JS_SetPropertyUint32(ctx, jsArr, UInt32(i),
                                         JSBridge.newString(ctx, entry))
                }
                logger.info("fs.list: \(expandedPath) (\(entries.count) entries)")
                return jsArr
            } catch {
                return QJS_ThrowInternalError(ctx, "fs.list failed: \(error.localizedDescription)")
            }
        }, "list", 1))

        JS_SetPropertyStr(ctx, macotron, "fs", fsObj)

        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)
    }

    public func cleanup() {
        // No persistent state to clean up
    }
}
