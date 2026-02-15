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

    // MARK: - JS -> Swift Conversions

    @Test("toString converts JS string to Swift String")
    func testToString() {
        let (engine, ctx) = makeContext()
        let jsVal = JSBridge.newString(ctx, "hello")
        let result = JSBridge.toString(ctx, jsVal)
        #expect(result == "hello")
        JS_FreeValue(ctx, jsVal)
        _ = engine // keep engine alive
    }

    @Test("toString with empty string")
    func testToStringEmpty() {
        let (engine, ctx) = makeContext()
        let jsVal = JSBridge.newString(ctx, "")
        let result = JSBridge.toString(ctx, jsVal)
        #expect(result == "")
        JS_FreeValue(ctx, jsVal)
        _ = engine
    }

    @Test("toString with unicode characters")
    func testToStringUnicode() {
        let (engine, ctx) = makeContext()
        let jsVal = JSBridge.newString(ctx, "cafe\u{0301}")
        let result = JSBridge.toString(ctx, jsVal)
        #expect(result == "cafe\u{0301}")
        JS_FreeValue(ctx, jsVal)
        _ = engine
    }

    @Test("toInt32 converts JS number to Int32")
    func testToInt32() {
        let (engine, ctx) = makeContext()
        let jsVal = JS_NewInt32(ctx, 42)
        let result = JSBridge.toInt32(ctx, jsVal)
        #expect(result == 42)
        _ = engine
    }

    @Test("toInt32 with negative number")
    func testToInt32Negative() {
        let (engine, ctx) = makeContext()
        let jsVal = JS_NewInt32(ctx, -100)
        let result = JSBridge.toInt32(ctx, jsVal)
        #expect(result == -100)
        _ = engine
    }

    @Test("toInt32 with zero")
    func testToInt32Zero() {
        let (engine, ctx) = makeContext()
        let jsVal = JS_NewInt32(ctx, 0)
        let result = JSBridge.toInt32(ctx, jsVal)
        #expect(result == 0)
        _ = engine
    }

    @Test("toDouble converts JS float to Double")
    func testToDouble() {
        let (engine, ctx) = makeContext()
        let jsVal = JS_NewFloat64(ctx, 3.14159)
        let result = JSBridge.toDouble(ctx, jsVal)
        #expect(abs(result - 3.14159) < 0.00001)
        _ = engine
    }

    @Test("toDouble with negative value")
    func testToDoubleNegative() {
        let (engine, ctx) = makeContext()
        let jsVal = JS_NewFloat64(ctx, -2.5)
        let result = JSBridge.toDouble(ctx, jsVal)
        #expect(result == -2.5)
        _ = engine
    }

    @Test("toBool converts JS true to Swift true")
    func testToBoolTrue() {
        let (engine, ctx) = makeContext()
        let jsVal = QJS_NewBool(ctx, 1)
        let result = JSBridge.toBool(ctx, jsVal)
        #expect(result == true)
        _ = engine
    }

    @Test("toBool converts JS false to Swift false")
    func testToBoolFalse() {
        let (engine, ctx) = makeContext()
        let jsVal = QJS_NewBool(ctx, 0)
        let result = JSBridge.toBool(ctx, jsVal)
        #expect(result == false)
        _ = engine
    }

    // MARK: - Swift -> JS Conversions

    @Test("newString creates JS string")
    func testNewString() {
        let (engine, ctx) = makeContext()
        let jsVal = JSBridge.newString(ctx, "test")
        #expect(JS_IsString(jsVal))
        let roundTrip = JSBridge.toString(ctx, jsVal)
        #expect(roundTrip == "test")
        JS_FreeValue(ctx, jsVal)
        _ = engine
    }

    @Test("newInt32 creates JS integer")
    func testNewInt32() {
        let (engine, ctx) = makeContext()
        let jsVal = JSBridge.newInt32(ctx, 99)
        #expect(JS_IsNumber(jsVal))
        let roundTrip = JSBridge.toInt32(ctx, jsVal)
        #expect(roundTrip == 99)
        _ = engine
    }

    @Test("newFloat64 creates JS float")
    func testNewFloat64() {
        let (engine, ctx) = makeContext()
        let jsVal = JSBridge.newFloat64(ctx, 2.718)
        #expect(JS_IsNumber(jsVal))
        let roundTrip = JSBridge.toDouble(ctx, jsVal)
        #expect(abs(roundTrip - 2.718) < 0.001)
        _ = engine
    }

    @Test("newBool creates JS boolean true")
    func testNewBoolTrue() {
        let (engine, ctx) = makeContext()
        let jsVal = JSBridge.newBool(ctx, true)
        #expect(JS_IsBool(jsVal))
        let roundTrip = JSBridge.toBool(ctx, jsVal)
        #expect(roundTrip == true)
        _ = engine
    }

    @Test("newBool creates JS boolean false")
    func testNewBoolFalse() {
        let (engine, ctx) = makeContext()
        let jsVal = JSBridge.newBool(ctx, false)
        #expect(JS_IsBool(jsVal))
        let roundTrip = JSBridge.toBool(ctx, jsVal)
        #expect(roundTrip == false)
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

    @Test("anyToJS with String")
    func testAnyToJSString() {
        let (engine, ctx) = makeContext()
        let jsVal = JSBridge.anyToJS(ctx, "hello" as Any)
        #expect(JS_IsString(jsVal))
        #expect(JSBridge.toString(ctx, jsVal) == "hello")
        JS_FreeValue(ctx, jsVal)
        _ = engine
    }

    @Test("anyToJS with Int")
    func testAnyToJSInt() {
        let (engine, ctx) = makeContext()
        let jsVal = JSBridge.anyToJS(ctx, 42 as Any)
        #expect(JS_IsNumber(jsVal))
        #expect(JSBridge.toInt32(ctx, jsVal) == 42)
        _ = engine
    }

    @Test("anyToJS with Int32")
    func testAnyToJSInt32() {
        let (engine, ctx) = makeContext()
        let jsVal = JSBridge.anyToJS(ctx, Int32(7) as Any)
        #expect(JS_IsNumber(jsVal))
        #expect(JSBridge.toInt32(ctx, jsVal) == 7)
        _ = engine
    }

    @Test("anyToJS with Double")
    func testAnyToJSDouble() {
        let (engine, ctx) = makeContext()
        let jsVal = JSBridge.anyToJS(ctx, 1.5 as Any)
        #expect(JS_IsNumber(jsVal))
        #expect(abs(JSBridge.toDouble(ctx, jsVal) - 1.5) < 0.001)
        _ = engine
    }

    @Test("anyToJS with Bool true")
    func testAnyToJSBoolTrue() {
        let (engine, ctx) = makeContext()
        let jsVal = JSBridge.anyToJS(ctx, true as Any)
        #expect(JS_IsBool(jsVal))
        #expect(JSBridge.toBool(ctx, jsVal) == true)
        _ = engine
    }

    @Test("anyToJS with Bool false")
    func testAnyToJSBoolFalse() {
        let (engine, ctx) = makeContext()
        let jsVal = JSBridge.anyToJS(ctx, false as Any)
        #expect(JS_IsBool(jsVal))
        #expect(JSBridge.toBool(ctx, jsVal) == false)
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

    @Test("jsToSwift converts JS string")
    func testJsToSwiftString() {
        let (engine, ctx) = makeContext()
        let jsVal = JSBridge.newString(ctx, "test")
        let result = JSBridge.jsToSwift(ctx, jsVal)
        #expect(result as? String == "test")
        JS_FreeValue(ctx, jsVal)
        _ = engine
    }

    @Test("jsToSwift converts JS integer")
    func testJsToSwiftInt() {
        let (engine, ctx) = makeContext()
        let jsVal = JSBridge.newInt32(ctx, 7)
        let result = JSBridge.jsToSwift(ctx, jsVal)
        #expect(result as? Int == 7)
        _ = engine
    }

    @Test("jsToSwift converts JS float")
    func testJsToSwiftFloat() {
        let (engine, ctx) = makeContext()
        let jsVal = JSBridge.newFloat64(ctx, 1.5)
        let result = JSBridge.jsToSwift(ctx, jsVal)
        // 1.5 should remain as Double since Int(1) != 1.5
        #expect(result as? Double == 1.5)
        _ = engine
    }

    @Test("jsToSwift converts JS boolean")
    func testJsToSwiftBool() {
        let (engine, ctx) = makeContext()
        let jsVal = JSBridge.newBool(ctx, true)
        let result = JSBridge.jsToSwift(ctx, jsVal)
        #expect(result as? Bool == true)
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

    @Test("isUndefined returns true for undefined value")
    func testIsUndefined() {
        let val = QJS_Undefined()
        #expect(JSBridge.isUndefined(val) == true)
    }

    @Test("isUndefined returns false for non-undefined value")
    func testIsUndefinedFalse() {
        let (engine, ctx) = makeContext()
        let val = JSBridge.newInt32(ctx, 5)
        #expect(JSBridge.isUndefined(val) == false)
        _ = engine
    }

    @Test("isNull returns true for null value")
    func testIsNull() {
        let val = QJS_Null()
        #expect(JSBridge.isNull(val) == true)
    }

    @Test("isNull returns false for non-null value")
    func testIsNullFalse() {
        let (engine, ctx) = makeContext()
        let val = JSBridge.newString(ctx, "not null")
        #expect(JSBridge.isNull(val) == false)
        JS_FreeValue(ctx, val)
        _ = engine
    }

    @Test("isException returns true for exception value")
    func testIsException() {
        let (engine, ctx) = makeContext()
        // Trigger an exception by evaluating bad code
        let result = "undefinedVar.property".withCString { cStr in
            JS_Eval(ctx, cStr, "undefinedVar.property".utf8.count, "<test>", Int32(JS_EVAL_TYPE_GLOBAL))
        }
        #expect(JSBridge.isException(result) == true)
        // Clean up the exception from the context
        let exc = JS_GetException(ctx)
        JS_FreeValue(ctx, exc)
        _ = engine
    }

    @Test("isException returns false for normal value")
    func testIsExceptionFalse() {
        let (engine, ctx) = makeContext()
        let val = JSBridge.newInt32(ctx, 10)
        #expect(JSBridge.isException(val) == false)
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
}
