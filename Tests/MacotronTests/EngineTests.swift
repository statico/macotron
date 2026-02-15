// EngineTests.swift — Basic tests for the QuickJS engine
import Testing
@testable import MacotronEngine

@MainActor
@Suite("Engine Tests")
struct EngineTests {
    @Test("Engine initializes successfully")
    func testInit() {
        let engine = Engine()
        #expect(engine.runtime != nil)
        #expect(engine.context != nil)
    }

    @Test("Evaluate simple expression")
    func testEvaluate() {
        let engine = Engine()
        let (result, error) = engine.evaluate("1 + 2")
        #expect(error == nil)
        #expect(result == "3")
    }

    @Test("Evaluate string expression")
    func testEvaluateString() {
        let engine = Engine()
        let (result, error) = engine.evaluate("'hello' + ' ' + 'world'")
        #expect(error == nil)
        #expect(result == "hello world")
    }

    @Test("Evaluate error returns error string")
    func testEvaluateError() {
        let engine = Engine()
        let (result, error) = engine.evaluate("undefinedVar.property")
        #expect(result == nil)
        #expect(error != nil)
    }

    @Test("Reset clears state")
    func testReset() {
        let engine = Engine()
        engine.evaluate("var x = 42")
        engine.reset()
        let (_, error) = engine.evaluate("x")
        // After reset, x should not exist
        #expect(error != nil)
    }

    @Test("EventBus registers and emits")
    func testEventBus() {
        let engine = Engine()
        // Register via JS
        engine.evaluate("""
            var received = false;
            $$__on("test:event", function() { received = true; });
        """)
        // Emit from Swift
        engine.eventBus.emit("test:event", engine: engine, data: nil)
        let (result, _) = engine.evaluate("received")
        #expect(result == "true")
    }
}
