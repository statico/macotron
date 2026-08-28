// EventBusTests.swift — Tests for EventBus event dispatching
import Testing
import CQuickJS
@testable import MacotronEngine

@MainActor
@Suite("EventBus Tests")
struct EventBusTests {

    // MARK: - on + emit
    // (bare on+emit lives in EngineTests.testEventBus)

    @Test("emit with data passes data to callback")
    func testEmitWithData() {
        let engine = Engine()
        engine.evaluate("""
            var receivedData = null;
            $$__on("test:data", function(d) { receivedData = d; });
        """)
        let ctx = engine.context!
        let dataVal = JSBridge.newString(ctx, "payload")
        engine.eventBus.emit("test:data", engine: engine, data: dataVal)
        JS_FreeValue(ctx, dataVal)

        let (result, _) = engine.evaluate("receivedData")
        #expect(result == "payload")
    }

    @Test("emit with object data passes object to callback")
    func testEmitWithObjectData() {
        let engine = Engine()
        engine.evaluate("""
            var receivedName = null;
            $$__on("test:objdata", function(d) { receivedName = d.name; });
        """)
        let ctx = engine.context!
        let dataVal = JSBridge.newObject(ctx, ["name": "Macotron"])
        engine.eventBus.emit("test:objdata", engine: engine, data: dataVal)
        JS_FreeValue(ctx, dataVal)

        let (result, _) = engine.evaluate("receivedName")
        #expect(result == "Macotron")
    }

    // MARK: - off

    @Test("off removes specific listener")
    func testOff() {
        let engine = Engine()
        // Register a listener via JS and store the callback reference
        engine.evaluate("""
            var offTestFired = false;
            var offCallback = function() { offTestFired = true; };
            $$__on("test:off", offCallback);
            $$__off("test:off", offCallback);
        """)
        engine.eventBus.emit("test:off", engine: engine, data: nil)
        let (result, _) = engine.evaluate("offTestFired")
        #expect(result == "false")
    }

    // MARK: - removeAllListeners

    @Test("removeAllListeners clears everything")
    func testRemoveAllListeners() {
        let engine = Engine()
        engine.evaluate("""
            var a = false;
            var b = false;
            $$__on("event:a", function() { a = true; });
            $$__on("event:b", function() { b = true; });
        """)

        engine.eventBus.removeAllListeners()
        engine.eventBus.emit("event:a", engine: engine, data: nil)
        engine.eventBus.emit("event:b", engine: engine, data: nil)
        let (a, _) = engine.evaluate("a")
        let (b, _) = engine.evaluate("b")
        #expect(a == "false")
        #expect(b == "false")
    }

    // MARK: - Multiple Listeners

    @Test("multiple listeners for same event all fire")
    func testMultipleListeners() {
        let engine = Engine()
        engine.evaluate("""
            var counter = 0;
            $$__on("test:multi", function() { counter += 1; });
            $$__on("test:multi", function() { counter += 10; });
            $$__on("test:multi", function() { counter += 100; });
        """)
        engine.eventBus.emit("test:multi", engine: engine, data: nil)
        let (result, _) = engine.evaluate("counter")
        #expect(result == "111")
    }

    @Test("listeners fire in registration order")
    func testListenerOrder() {
        let engine = Engine()
        engine.evaluate("""
            var order = [];
            $$__on("test:order", function() { order.push("first"); });
            $$__on("test:order", function() { order.push("second"); });
            $$__on("test:order", function() { order.push("third"); });
        """)
        engine.eventBus.emit("test:order", engine: engine, data: nil)
        let (result, _) = engine.evaluate("JSON.stringify(order)")
        #expect(result == "[\"first\",\"second\",\"third\"]")
    }

    // MARK: - Emit with No Listeners

    @Test("emit with no listeners does not crash")
    func testEmitNoListeners() {
        let engine = Engine()
        // This should not crash or produce any error
        engine.eventBus.emit("nonexistent:event", engine: engine, data: nil)
        // Verify engine is still functional
        let (result, error) = engine.evaluate("1 + 1")
        #expect(error == nil)
        #expect(result == "2")
    }

    // MARK: - Different Events Are Independent

    @Test("listeners for different events are independent")
    func testDifferentEventsIndependent() {
        let engine = Engine()
        engine.evaluate("""
            var aFired = false;
            var bFired = false;
            $$__on("event:a", function() { aFired = true; });
            $$__on("event:b", function() { bFired = true; });
        """)
        // Only emit event:a
        engine.eventBus.emit("event:a", engine: engine, data: nil)
        let (aResult, _) = engine.evaluate("aFired")
        let (bResult, _) = engine.evaluate("bFired")
        #expect(aResult == "true")
        #expect(bResult == "false")
    }

    // MARK: - Re-registration After removeAllListeners

    @Test("can register new listeners after removeAllListeners")
    func testReRegisterAfterClear() {
        let engine = Engine()
        engine.evaluate("""
            var val = 0;
            $$__on("test:rereg", function() { val = 1; });
        """)
        engine.eventBus.removeAllListeners()

        engine.evaluate("""
            $$__on("test:rereg", function() { val = 42; });
        """)
        engine.eventBus.emit("test:rereg", engine: engine, data: nil)
        let (result, _) = engine.evaluate("val")
        #expect(result == "42")
    }
}
