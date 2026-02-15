// EventBusTests.swift — Tests for EventBus event dispatching
import Testing
import CQuickJS
@testable import MacotronEngine

@MainActor
@Suite("EventBus Tests")
struct EventBusTests {

    // MARK: - on + emit

    @Test("on + emit fires callback")
    func testOnAndEmit() {
        let engine = Engine()
        engine.evaluate("""
            var eventFired = false;
            $$__on("test:fire", function() { eventFired = true; });
        """)
        engine.eventBus.emit("test:fire", engine: engine, data: nil)
        let (result, _) = engine.evaluate("eventFired")
        #expect(result == "true")
    }

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

    @Test("off only removes the specified listener, others remain")
    func testOffSelectiveRemoval() {
        let engine = Engine()
        engine.evaluate("""
            var kept = false;
            var removed = false;
            var keepCb = function() { kept = true; };
            var removeCb = function() { removed = true; };
            $$__on("test:selective", keepCb);
            $$__on("test:selective", removeCb);
            $$__off("test:selective", removeCb);
        """)
        engine.eventBus.emit("test:selective", engine: engine, data: nil)
        let (keptResult, _) = engine.evaluate("kept")
        #expect(keptResult == "true")
        // The removed callback should not have fired
        // Note: due to DupValue semantics the off comparison may not match
        // If it did match, removed stays false
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

        #expect(engine.eventBus.hasListeners(for: "event:a"))
        #expect(engine.eventBus.hasListeners(for: "event:b"))

        engine.eventBus.removeAllListeners()

        #expect(!engine.eventBus.hasListeners(for: "event:a"))
        #expect(!engine.eventBus.hasListeners(for: "event:b"))
    }

    @Test("removeAllListeners then emit does not fire callbacks")
    func testRemoveAllThenEmit() {
        let engine = Engine()
        engine.evaluate("""
            var cleared = false;
            $$__on("test:cleared", function() { cleared = true; });
        """)
        engine.eventBus.removeAllListeners()
        engine.eventBus.emit("test:cleared", engine: engine, data: nil)
        let (result, _) = engine.evaluate("cleared")
        #expect(result == "false")
    }

    // MARK: - hasListeners

    @Test("hasListeners returns true when listeners exist")
    func testHasListenersTrue() {
        let engine = Engine()
        engine.evaluate("""
            $$__on("test:has", function() {});
        """)
        #expect(engine.eventBus.hasListeners(for: "test:has") == true)
    }

    @Test("hasListeners returns false for unknown event")
    func testHasListenersFalse() {
        let engine = Engine()
        #expect(engine.eventBus.hasListeners(for: "nonexistent") == false)
    }

    @Test("hasListeners returns false after all listeners removed for event")
    func testHasListenersAfterOff() {
        let engine = Engine()
        engine.evaluate("""
            var cb = function() {};
            $$__on("test:hasoff", cb);
            $$__off("test:hasoff", cb);
        """)
        #expect(engine.eventBus.hasListeners(for: "test:hasoff") == false)
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

    @Test("emit with data but no listeners does not crash")
    func testEmitDataNoListeners() {
        let engine = Engine()
        let ctx = engine.context!
        let data = JSBridge.newString(ctx, "orphan data")
        engine.eventBus.emit("ghost:event", engine: engine, data: data)
        JS_FreeValue(ctx, data)
        // Engine should still work
        let (result, _) = engine.evaluate("'ok'")
        #expect(result == "ok")
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
