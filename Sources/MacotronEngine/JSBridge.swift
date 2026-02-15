// JSBridge.swift — Swift↔JS type conversion helpers for QuickJS
import CQuickJS
import Foundation

/// Helpers for converting between Swift types and QuickJS JSValues
@MainActor
public enum JSBridge {

    // MARK: - JS → Swift

    public static func toString(_ ctx: OpaquePointer, _ val: JSValue) -> String? {
        let cstr = JS_ToCString(ctx, val)
        guard let cstr else { return nil }
        let str = String(cString: cstr)
        JS_FreeCString(ctx, cstr)
        return str
    }

    public static func toInt32(_ ctx: OpaquePointer, _ val: JSValue) -> Int32 {
        var result: Int32 = 0
        JS_ToInt32(ctx, &result, val)
        return result
    }

    public static func toDouble(_ ctx: OpaquePointer, _ val: JSValue) -> Double {
        var result: Double = 0
        JS_ToFloat64(ctx, &result, val)
        return result
    }

    public static func toBool(_ ctx: OpaquePointer, _ val: JSValue) -> Bool {
        JS_ToBool(ctx, val) != 0
    }

    // MARK: - Swift → JS

    public static func newString(_ ctx: OpaquePointer, _ str: String) -> JSValue {
        str.withCString { cstr in
            JS_NewString(ctx, cstr)
        }
    }

    public static func newInt32(_ ctx: OpaquePointer, _ val: Int32) -> JSValue {
        JS_NewInt32(ctx, val)
    }

    public static func newFloat64(_ ctx: OpaquePointer, _ val: Double) -> JSValue {
        JS_NewFloat64(ctx, val)
    }

    public static func newBool(_ ctx: OpaquePointer, _ val: Bool) -> JSValue {
        QJS_NewBool(ctx, val ? 1 : 0)
    }

    /// Create a JS object from a dictionary of string keys
    public static func newObject(_ ctx: OpaquePointer, _ dict: [String: Any]) -> JSValue {
        let obj = JS_NewObject(ctx)
        for (key, value) in dict {
            let jsVal = anyToJS(ctx, value)
            JS_SetPropertyStr(ctx, obj, key, jsVal)
        }
        return obj
    }

    /// Create a JS array from a Swift array
    public static func newArray(_ ctx: OpaquePointer, _ arr: [Any]) -> JSValue {
        let jsArr = JS_NewArray(ctx)
        for (i, item) in arr.enumerated() {
            let jsVal = anyToJS(ctx, item)
            JS_SetPropertyUint32(ctx, jsArr, UInt32(i), jsVal)
        }
        return jsArr
    }

    /// Convert any Swift value to a JSValue (best effort)
    public static func anyToJS(_ ctx: OpaquePointer, _ value: Any) -> JSValue {
        switch value {
        case let s as String:
            return newString(ctx, s)
        case let i as Int:
            return newInt32(ctx, Int32(i))
        case let i as Int32:
            return newInt32(ctx, i)
        case let d as Double:
            return newFloat64(ctx, d)
        case let d as CGFloat:
            return newFloat64(ctx, Double(d))
        case let b as Bool:
            return newBool(ctx, b)
        case let dict as [String: Any]:
            return newObject(ctx, dict)
        case let arr as [Any]:
            return newArray(ctx, arr)
        default:
            return QJS_Undefined()
        }
    }

    /// Get a property from a JS object by string key
    public static func getProperty(_ ctx: OpaquePointer, _ obj: JSValue, _ key: String) -> JSValue {
        JS_GetPropertyStr(ctx, obj, key)
    }

    /// Set a property on a JS object by string key
    public static func setProperty(_ ctx: OpaquePointer, _ obj: JSValue, _ key: String, _ val: JSValue) {
        JS_SetPropertyStr(ctx, obj, key, val)
    }

    /// Check if a JSValue is undefined
    public static func isUndefined(_ val: JSValue) -> Bool {
        JS_IsUndefined(val)
    }

    /// Check if a JSValue is null
    public static func isNull(_ val: JSValue) -> Bool {
        JS_IsNull(val)
    }

    /// Check if a JSValue is an exception
    public static func isException(_ val: JSValue) -> Bool {
        JS_IsException(val)
    }

    /// Get exception string from context
    public static func getExceptionString(_ ctx: OpaquePointer) -> String {
        let exception = JS_GetException(ctx)
        let str = toString(ctx, exception) ?? "unknown error"
        JS_FreeValue(ctx, exception)
        return str
    }

    // MARK: - JS → Swift (deep conversion)

    /// Recursively convert a JSValue to a Swift Any (String, Int, Double, Bool, [Any], [String:Any], or NSNull)
    public static func jsToSwift(_ ctx: OpaquePointer, _ val: JSValue) -> Any {
        if JS_IsString(val) {
            return toString(ctx, val) ?? ""
        }
        if JS_IsBool(val) {
            return toBool(ctx, val)
        }
        if JS_IsNumber(val) {
            var i: Int32 = 0
            if JS_ToInt32(ctx, &i, val) == 0 {
                var d: Double = 0
                JS_ToFloat64(ctx, &d, val)
                if Double(i) == d { return Int(i) }
                return d
            }
            return toDouble(ctx, val)
        }
        if JS_IsArray(val) {
            let lenVal = JS_GetPropertyStr(ctx, val, "length")
            let len = toInt32(ctx, lenVal)
            JS_FreeValue(ctx, lenVal)
            var arr: [Any] = []
            for idx in 0..<len {
                let elem = JS_GetPropertyUint32(ctx, val, UInt32(idx))
                arr.append(jsToSwift(ctx, elem))
                JS_FreeValue(ctx, elem)
            }
            return arr
        }
        if JS_IsObject(val) {
            var dict: [String: Any] = [:]
            var ptab: UnsafeMutablePointer<JSPropertyEnum>?
            var plen: UInt32 = 0
            let flags = Int32(JS_GPN_STRING_MASK | JS_GPN_ENUM_ONLY)
            if JS_GetOwnPropertyNames(ctx, &ptab, &plen, val, flags) == 0, let ptab {
                for i in 0..<Int(plen) {
                    let prop = ptab[i]
                    let keyAtom = prop.atom
                    let keyCStr = JS_AtomToCString(ctx, keyAtom)
                    if let keyCStr {
                        let key = String(cString: keyCStr)
                        JS_FreeCString(ctx, keyCStr)
                        let propVal = JS_GetProperty(ctx, val, keyAtom)
                        dict[key] = jsToSwift(ctx, propVal)
                        JS_FreeValue(ctx, propVal)
                    }
                    JS_FreeAtom(ctx, keyAtom)
                }
                js_free(ctx, ptab)
            }
            return dict
        }
        if JS_IsNull(val) || JS_IsUndefined(val) {
            return NSNull()
        }
        return NSNull()
    }
}
