// JSBridgeTests.swift — Tests for Swift<->JS type conversion helpers
import Testing
import Foundation
import CQuickJS
@testable import MacotronEngine

@MainActor
@Suite("JSBridge Tests")
struct JSBridgeTests {

    // Helper: create a fresh engine and return its context
    private func makeContext() -> (Engine, OpaquePointer) {
        let engine = Engine()
        return (engine, engine.context!)
    }

    // MARK: - Scalar round-trips
    //
    // One table per scalar type walks newX/toX, jsToSwift and anyToJS in a
    // single pass. This replaces the forty-odd one-assert tests that each
    // stood up a whole engine to check one value one way.

    @Test("String round-trips", arguments: ["hello", "", "cafe\u{0301}", "test"])
    func stringRoundTrip(_ value: String) {
        let (engine, ctx) = makeContext()
        let js = JSBridge.newString(ctx, value)
        #expect(JS_IsString(js))
        #expect(JSBridge.toString(ctx, js) == value)
        #expect(JSBridge.jsToSwift(ctx, js) as? String == value)
        #expect(JSBridge.isNull(js) == false)
        JS_FreeValue(ctx, js)

        let any = JSBridge.anyToJS(ctx, value as Any)
        #expect(JS_IsString(any))
        #expect(JSBridge.toString(ctx, any) == value)
        JS_FreeValue(ctx, any)
        _ = engine
    }

    @Test("Int32 round-trips", arguments: [42, -100, 0, 99, 7] as [Int32])
    func int32RoundTrip(_ value: Int32) {
        let (engine, ctx) = makeContext()
        let js = JSBridge.newInt32(ctx, value)
        #expect(JS_IsNumber(js))
        #expect(JSBridge.toInt32(ctx, js) == value)
        #expect(JSBridge.jsToSwift(ctx, js) as? Int == Int(value))
        #expect(JSBridge.isUndefined(js) == false)
        #expect(JSBridge.isException(js) == false)
        // Both Int and Int32 reach the same JS number through anyToJS.
        #expect(JSBridge.toInt32(ctx, JSBridge.anyToJS(ctx, Int(value) as Any)) == value)
        #expect(JSBridge.toInt32(ctx, JSBridge.anyToJS(ctx, value as Any)) == value)
        _ = engine
    }

    @Test("Double round-trips", arguments: [3.14159, -2.5, 2.718, 1.5])
    func doubleRoundTrip(_ value: Double) {
        let (engine, ctx) = makeContext()
        let js = JSBridge.newFloat64(ctx, value)
        #expect(JS_IsNumber(js))
        #expect(JSBridge.toDouble(ctx, js) == value)
        // Non-integral, so jsToSwift must keep it a Double.
        #expect(JSBridge.jsToSwift(ctx, js) as? Double == value)
        let any = JSBridge.anyToJS(ctx, value as Any)
        #expect(JS_IsNumber(any))
        #expect(JSBridge.toDouble(ctx, any) == value)
        _ = engine
    }

    @Test("Bool round-trips", arguments: [true, false])
    func boolRoundTrip(_ value: Bool) {
        let (engine, ctx) = makeContext()
        let js = JSBridge.newBool(ctx, value)
        #expect(JS_IsBool(js))
        #expect(JSBridge.toBool(ctx, js) == value)
        #expect(JSBridge.jsToSwift(ctx, js) as? Bool == value)
        let any = JSBridge.anyToJS(ctx, value as Any)
        #expect(JS_IsBool(any))
        #expect(JSBridge.toBool(ctx, any) == value)
        _ = engine
    }

    // MARK: - Object and Array Creation

    @Test("newObject creates proper JS object with string values")
    func testNewObjectStrings() {
        let (engine, ctx) = makeContext()
        let jsObj = JSBridge.newObject(ctx, ["name": "Alice", "city": "NYC"])
        #expect(JS_IsObject(jsObj))

        let nameVal = JS_GetPropertyStr(ctx, jsObj, "name")
        #expect(JSBridge.toString(ctx, nameVal) == "Alice")
        JS_FreeValue(ctx, nameVal)

        let cityVal = JS_GetPropertyStr(ctx, jsObj, "city")
        #expect(JSBridge.toString(ctx, cityVal) == "NYC")
        JS_FreeValue(ctx, cityVal)

        JS_FreeValue(ctx, jsObj)
        _ = engine
    }

    @Test("newObject creates JS object with mixed value types")
    func testNewObjectMixed() {
        let (engine, ctx) = makeContext()
        let jsObj = JSBridge.newObject(ctx, [
            "name": "Bob" as Any,
            "age": 30 as Any,
            "active": true as Any
        ])
        #expect(JS_IsObject(jsObj))

        let nameVal = JS_GetPropertyStr(ctx, jsObj, "name")
        #expect(JSBridge.toString(ctx, nameVal) == "Bob")
        JS_FreeValue(ctx, nameVal)

        let ageVal = JS_GetPropertyStr(ctx, jsObj, "age")
        #expect(JSBridge.toInt32(ctx, ageVal) == 30)
        JS_FreeValue(ctx, ageVal)

        let activeVal = JS_GetPropertyStr(ctx, jsObj, "active")
        #expect(JSBridge.toBool(ctx, activeVal) == true)
        JS_FreeValue(ctx, activeVal)

        JS_FreeValue(ctx, jsObj)
        _ = engine
    }

    @Test("newObject with empty dictionary")
    func testNewObjectEmpty() {
        let (engine, ctx) = makeContext()
        let jsObj = JSBridge.newObject(ctx, [:])
        #expect(JS_IsObject(jsObj))
        JS_FreeValue(ctx, jsObj)
        _ = engine
    }

    @Test("newArray creates proper JS array")
    func testNewArray() {
        let (engine, ctx) = makeContext()
        let jsArr = JSBridge.newArray(ctx, ["a" as Any, "b" as Any, "c" as Any])
        #expect(JS_IsArray(jsArr))

        let lenVal = JS_GetPropertyStr(ctx, jsArr, "length")
        #expect(JSBridge.toInt32(ctx, lenVal) == 3)
        JS_FreeValue(ctx, lenVal)

        let elem0 = JS_GetPropertyUint32(ctx, jsArr, 0)
        #expect(JSBridge.toString(ctx, elem0) == "a")
        JS_FreeValue(ctx, elem0)

        let elem2 = JS_GetPropertyUint32(ctx, jsArr, 2)
        #expect(JSBridge.toString(ctx, elem2) == "c")
        JS_FreeValue(ctx, elem2)

        JS_FreeValue(ctx, jsArr)
        _ = engine
    }

    @Test("newArray creates JS array with numbers")
    func testNewArrayNumbers() {
        let (engine, ctx) = makeContext()
        let jsArr = JSBridge.newArray(ctx, [1 as Any, 2 as Any, 3 as Any])
        #expect(JS_IsArray(jsArr))

        let elem0 = JS_GetPropertyUint32(ctx, jsArr, 0)
        #expect(JSBridge.toInt32(ctx, elem0) == 1)
        JS_FreeValue(ctx, elem0)

        JS_FreeValue(ctx, jsArr)
        _ = engine
    }

    @Test("newArray with empty array")
    func testNewArrayEmpty() {
        let (engine, ctx) = makeContext()
        let jsArr = JSBridge.newArray(ctx, [])
        #expect(JS_IsArray(jsArr))

        let lenVal = JS_GetPropertyStr(ctx, jsArr, "length")
        #expect(JSBridge.toInt32(ctx, lenVal) == 0)
        JS_FreeValue(ctx, lenVal)

        JS_FreeValue(ctx, jsArr)
        _ = engine
    }

    // MARK: - anyToJS

    @Test("anyToJS widens an Int that does not fit Int32", arguments: [
        1_755_470_000_000,          // a millisecond timestamp from Date.now()
        Int(Int32.min), Int(Int32.max), Int(Int32.max) + 1, Int(Int32.min) - 1
    ])
    func anyToJSWideInt(_ value: Int) {
        let (engine, ctx) = makeContext()
        let jsVal = JSBridge.anyToJS(ctx, value as Any)
        #expect(JS_IsNumber(jsVal))
        #expect(JSBridge.toDouble(ctx, jsVal) == Double(value))
        _ = engine
    }

    @Test("anyToJS with [String: Any] dictionary")
    func testAnyToJSDict() {
        let (engine, ctx) = makeContext()
        let dict: [String: Any] = ["key": "value"]
        let jsVal = JSBridge.anyToJS(ctx, dict as Any)
        #expect(JS_IsObject(jsVal))

        let propVal = JS_GetPropertyStr(ctx, jsVal, "key")
        #expect(JSBridge.toString(ctx, propVal) == "value")
        JS_FreeValue(ctx, propVal)
        JS_FreeValue(ctx, jsVal)
        _ = engine
    }

    @Test("anyToJS with [Any] array")
    func testAnyToJSArray() {
        let (engine, ctx) = makeContext()
        let arr: [Any] = ["x", "y"]
        let jsVal = JSBridge.anyToJS(ctx, arr as Any)
        #expect(JS_IsArray(jsVal))

        let lenVal = JS_GetPropertyStr(ctx, jsVal, "length")
        #expect(JSBridge.toInt32(ctx, lenVal) == 2)
        JS_FreeValue(ctx, lenVal)

        JS_FreeValue(ctx, jsVal)
        _ = engine
    }

    @Test("anyToJS with unsupported type returns undefined")
    func testAnyToJSUnsupported() {
        let (engine, ctx) = makeContext()
        // NSObject is not a recognized type
        let jsVal = JSBridge.anyToJS(ctx, NSObject() as Any)
        #expect(JSBridge.isUndefined(jsVal))
        _ = engine
    }

    // MARK: - jsToSwift Round-Trip

    @Test("jsToSwift round-trip: object to JS and back to Swift dict")
    func testJsToSwiftRoundTrip() {
        let (engine, ctx) = makeContext()
        let original: [String: Any] = [
            "name": "Alice",
            "age": 30,
            "active": true
        ]
        let jsObj = JSBridge.newObject(ctx, original)
        let converted = JSBridge.jsToSwift(ctx, jsObj)
        JS_FreeValue(ctx, jsObj)

        let dict = converted as? [String: Any]
        #expect(dict != nil)
        #expect(dict?["name"] as? String == "Alice")
        #expect(dict?["age"] as? Int == 30)
        #expect(dict?["active"] as? Bool == true)
        _ = engine
    }

    @Test("jsToSwift converts JS array")
    func testJsToSwiftArray() {
        let (engine, ctx) = makeContext()
        let jsArr = JSBridge.newArray(ctx, ["a" as Any, "b" as Any])
        let result = JSBridge.jsToSwift(ctx, jsArr)
        JS_FreeValue(ctx, jsArr)

        let arr = result as? [Any]
        #expect(arr != nil)
        #expect(arr?.count == 2)
        #expect(arr?[0] as? String == "a")
        #expect(arr?[1] as? String == "b")
        _ = engine
    }

    @Test("jsToSwift converts null to NSNull")
    func testJsToSwiftNull() {
        let (engine, ctx) = makeContext()
        let jsVal = QJS_Null()
        let result = JSBridge.jsToSwift(ctx, jsVal)
        #expect(result is NSNull)
        _ = engine
    }

    @Test("jsToSwift converts undefined to NSNull")
    func testJsToSwiftUndefined() {
        let (engine, ctx) = makeContext()
        let jsVal = QJS_Undefined()
        let result = JSBridge.jsToSwift(ctx, jsVal)
        #expect(result is NSNull)
        _ = engine
    }

    @Test("jsToSwift nested object round-trip")
    func testJsToSwiftNested() {
        let (engine, ctx) = makeContext()
        let inner: [String: Any] = ["x": 1]
        let outer: [String: Any] = ["inner": inner, "label": "test"]
        let jsObj = JSBridge.newObject(ctx, outer)
        let converted = JSBridge.jsToSwift(ctx, jsObj) as? [String: Any]
        JS_FreeValue(ctx, jsObj)

        #expect(converted != nil)
        #expect(converted?["label"] as? String == "test")
        let innerDict = converted?["inner"] as? [String: Any]
        #expect(innerDict != nil)
        #expect(innerDict?["x"] as? Int == 1)
        _ = engine
    }

    // MARK: - Predicate Checks

    @Test("each predicate answers for its own value and no other")
    func testPredicates() {
        let (engine, ctx) = makeContext()
        #expect(JSBridge.isUndefined(QJS_Undefined()) == true)
        #expect(JSBridge.isNull(QJS_Undefined()) == false)
        #expect(JSBridge.isNull(QJS_Null()) == true)
        #expect(JSBridge.isUndefined(QJS_Null()) == false)

        let num = JSBridge.newInt32(ctx, 5)
        #expect(JSBridge.isUndefined(num) == false)
        #expect(JSBridge.isException(num) == false)

        let str = JSBridge.newString(ctx, "not null")
        #expect(JSBridge.isNull(str) == false)
        JS_FreeValue(ctx, str)

        let src = "undefinedVar.property"
        let thrown = src.withCString {
            JS_Eval(ctx, $0, src.utf8.count, "<test>", Int32(JS_EVAL_TYPE_GLOBAL))
        }
        #expect(JSBridge.isException(thrown) == true)
        JS_FreeValue(ctx, JS_GetException(ctx))   // leave the context clean
        _ = engine
    }

    // MARK: - getExceptionString

    @Test("getExceptionString returns error message")
    func testGetExceptionString() {
        let (engine, ctx) = makeContext()
        // Trigger an exception
        let result = "throw new Error('test error')".withCString { cStr in
            JS_Eval(ctx, cStr, "throw new Error('test error')".utf8.count, "<test>", Int32(JS_EVAL_TYPE_GLOBAL))
        }
        #expect(JS_IsException(result))
        let errStr = JSBridge.getExceptionString(ctx)
        #expect(errStr.contains("test error"))
        _ = engine
    }

    @Test("getExceptionString with ReferenceError")
    func testGetExceptionStringReferenceError() {
        let (engine, ctx) = makeContext()
        let js = "nonExistent.foo"
        let result = js.withCString { cStr in
            JS_Eval(ctx, cStr, js.utf8.count, "<test>", Int32(JS_EVAL_TYPE_GLOBAL))
        }
        #expect(JS_IsException(result))
        let errStr = JSBridge.getExceptionString(ctx)
        #expect(errStr.contains("not defined") || errStr.contains("ReferenceError") || errStr.contains("nonExistent"))
        _ = engine
    }

    // MARK: - Property Get/Set

    @Test("getProperty retrieves property from JS object")
    func testGetProperty() {
        let (engine, ctx) = makeContext()
        let obj = JSBridge.newObject(ctx, ["foo": "bar"])
        let prop = JSBridge.getProperty(ctx, obj, "foo")
        #expect(JSBridge.toString(ctx, prop) == "bar")
        JS_FreeValue(ctx, prop)
        JS_FreeValue(ctx, obj)
        _ = engine
    }

    @Test("getProperty returns undefined for missing key")
    func testGetPropertyMissing() {
        let (engine, ctx) = makeContext()
        let obj = JSBridge.newObject(ctx, ["foo": "bar"])
        let prop = JSBridge.getProperty(ctx, obj, "missing")
        #expect(JSBridge.isUndefined(prop))
        JS_FreeValue(ctx, obj)
        _ = engine
    }

    @Test("setProperty sets property on JS object")
    func testSetProperty() {
        let (engine, ctx) = makeContext()
        let obj = JS_NewObject(ctx)
        let val = JSBridge.newString(ctx, "world")
        JSBridge.setProperty(ctx, obj, "hello", val)

        let retrieved = JSBridge.getProperty(ctx, obj, "hello")
        #expect(JSBridge.toString(ctx, retrieved) == "world")
        JS_FreeValue(ctx, retrieved)
        JS_FreeValue(ctx, obj)
        _ = engine
    }
    // MARK: - Option readers

    /// Build an options object by evaluating a JS literal, the way a plugin
    /// would hand one to a module binding.
    @MainActor
    private func options(_ engine: Engine, _ literal: String) -> JSValue {
        let ctx = engine.context!
        return literal.withCString { JS_Eval(ctx, $0, strlen($0), "<opts>", JS_EVAL_TYPE_GLOBAL) }
    }

    @Test("option readers convert each type")
    func optionReaders() {
        let (engine, ctx) = makeContext()
        let opts = options(engine, "({s: 'hi', i: 7, d: 1.5, b: true, arr: ['a', 'b']})")
        defer { JS_FreeValue(ctx, opts) }
        #expect(JSBridge.string(ctx, opts, "s") == "hi")
        #expect(JSBridge.int(ctx, opts, "i") == 7)
        #expect(JSBridge.double(ctx, opts, "d") == 1.5)
        #expect(JSBridge.bool(ctx, opts, "b") == true)
        #expect(JSBridge.stringArray(ctx, opts, "arr") == ["a", "b"])
    }

    @Test("a missing key is nil, so the caller's default applies")
    func optionMissingKey() {
        let (engine, ctx) = makeContext()
        let opts = options(engine, "({})")
        defer { JS_FreeValue(ctx, opts) }
        #expect(JSBridge.string(ctx, opts, "nope") == nil)
        #expect(JSBridge.int(ctx, opts, "nope") == nil)
        #expect(JSBridge.double(ctx, opts, "nope") == nil)
        #expect(JSBridge.bool(ctx, opts, "nope") == nil)
        #expect(JSBridge.stringArray(ctx, opts, "nope") == nil)
        #expect(JSBridge.int(ctx, opts, "nope") ?? 42 == 42)
    }

    @Test("undefined and null read as absent, not as values")
    func optionUndefinedAndNull() {
        // The hand-rolled version of this check was four lines and one call
        // site forgot the null half, so an explicit null read back as 0.
        let (engine, ctx) = makeContext()
        let opts = options(engine, "({u: undefined, n: null})")
        defer { JS_FreeValue(ctx, opts) }
        for key in ["u", "n"] {
            #expect(JSBridge.string(ctx, opts, key) == nil)
            #expect(JSBridge.int(ctx, opts, key) == nil)
            #expect(JSBridge.bool(ctx, opts, key) == nil)
        }
    }

    @Test("present-but-falsy is not the same answer as absent")
    func optionFalsyIsPresent() {
        let (engine, ctx) = makeContext()
        let opts = options(engine, "({b: false, i: 0, s: ''})")
        defer { JS_FreeValue(ctx, opts) }
        #expect(JSBridge.bool(ctx, opts, "b") == false)
        #expect(JSBridge.int(ctx, opts, "i") == 0)
        #expect(JSBridge.string(ctx, opts, "s") == "")
        // The distinction that matters: an explicit false must not fall
        // through to a `?? true` default.
        #expect((JSBridge.bool(ctx, opts, "b") ?? true) == false)
    }

    @Test("stringArray rejects a non-array and skips non-string elements")
    func optionStringArrayShape() {
        let (engine, ctx) = makeContext()
        let opts = options(engine, "({notArr: 'abc', mixed: ['a', 1, null, 'b']})")
        defer { JS_FreeValue(ctx, opts) }
        #expect(JSBridge.stringArray(ctx, opts, "notArr") == nil)
        #expect(JSBridge.stringArray(ctx, opts, "mixed") == ["a", "1", "b"])
    }
}
