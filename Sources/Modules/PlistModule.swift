// PlistModule.swift — macotron.plist: read and parse property lists
import CQuickJS
import Foundation
import MacotronEngine

/// Property list values in the shapes `JSBridge.anyToJS` understands. A Date
/// becomes epoch ms and Data becomes base64, so a plist nested as Data (Screen
/// Sharing keeps its connections that way) can go straight back into
/// `plist.parse({ base64 })`.
public enum PlistValue {
    public static func toJS(_ value: Any) -> Any {
        switch value {
        case let date as Date: return date.timeIntervalSince1970 * 1000
        case let data as Data: return data.base64EncodedString()
        case let dict as [String: Any]: return dict.mapValues(toJS)
        case let array as [Any]: return array.map(toJS)
        default: return value
        }
    }

    /// Binary, XML, or OpenStep; nil when the bytes are none of them.
    public static func parse(_ data: Data) -> Any? {
        (try? PropertyListSerialization.propertyList(from: data, format: nil)).map(toJS)
    }

    public static func read(_ path: String) -> Any? {
        let url = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
        return (try? Data(contentsOf: url)).flatMap(parse)
    }
}

@MainActor
public final class PlistModule: NativeModule {
    public let name = "plist"

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JSBridge.getProperty(ctx, global, "macotron")
        let plist = JS_NewObject(ctx)

        JSBridge.fn(ctx, plist, "read", 1) { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 1,
                  let path = JSBridge.toString(ctx, argv[0]) else { return QJS_Null() }
            return PlistModule.js(ctx, PlistValue.read(path))
        }

        // parse(text) for XML or OpenStep; parse({ base64 }) for any format, binary included.
        JSBridge.fn(ctx, plist, "parse", 1) { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 1 else { return QJS_Null() }
            let data = JS_IsString(argv[0])
                ? JSBridge.toString(ctx, argv[0]).map { Data($0.utf8) }
                : JSBridge.string(ctx, argv[0], "base64").flatMap {
                    Data(base64Encoded: $0, options: .ignoreUnknownCharacters)
                }
            return PlistModule.js(ctx, data.flatMap(PlistValue.parse))
        }

        JS_SetPropertyStr(ctx, macotron, "plist", plist)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)
    }

    static func js(_ ctx: OpaquePointer, _ value: Any?) -> JSValue {
        value.map { JSBridge.anyToJS(ctx, $0) } ?? QJS_Null()
    }
}
