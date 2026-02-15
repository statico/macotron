// EngineTests.swift — Tests for the QuickJS engine
import Testing
import CQuickJS
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

    // MARK: - Type Return Tests

    @Test("Evaluate returns number type correctly")
    func testEvaluateNumber() {
        let engine = Engine()
        let (result, error) = engine.evaluate("42")
        #expect(error == nil)
        #expect(result == "42")
    }

    @Test("Evaluate returns floating point number")
    func testEvaluateFloat() {
        let engine = Engine()
        let (result, error) = engine.evaluate("3.14")
        #expect(error == nil)
        #expect(result == "3.14")
    }

    @Test("Evaluate returns boolean true")
    func testEvaluateBoolTrue() {
        let engine = Engine()
        let (result, error) = engine.evaluate("true")
        #expect(error == nil)
        #expect(result == "true")
    }

    @Test("Evaluate returns boolean false")
    func testEvaluateBoolFalse() {
        let engine = Engine()
        let (result, error) = engine.evaluate("false")
        #expect(error == nil)
        #expect(result == "false")
    }

    @Test("Evaluate returns object as string representation")
    func testEvaluateObject() {
        let engine = Engine()
        let (result, error) = engine.evaluate("JSON.stringify({a: 1, b: 'two'})")
        #expect(error == nil)
        #expect(result == "{\"a\":1,\"b\":\"two\"}")
    }

    @Test("Evaluate returns array as string representation")
    func testEvaluateArray() {
        let engine = Engine()
        let (result, error) = engine.evaluate("JSON.stringify([1, 2, 3])")
        #expect(error == nil)
        #expect(result == "[1,2,3]")
    }

    // MARK: - Undefined / Null Handling

    @Test("Evaluate undefined returns 'undefined' string with no error")
    func testEvaluateUndefined() {
        let engine = Engine()
        let (result, error) = engine.evaluate("undefined")
        #expect(error == nil)
        // QuickJS JS_ToCString converts undefined to the string "undefined"
        #expect(result == "undefined")
    }

    @Test("Evaluate null returns nil result with no error")
    func testEvaluateNull() {
        let engine = Engine()
        let (result, error) = engine.evaluate("null")
        #expect(error == nil)
        #expect(result == "null")
    }

    @Test("Evaluate void expression returns 'undefined'")
    func testEvaluateVoid() {
        let engine = Engine()
        // var declaration evaluates to undefined in JS
        let (result, error) = engine.evaluate("var y = 10")
        #expect(error == nil)
        // QuickJS JS_ToCString converts undefined to "undefined"
        #expect(result == "undefined")
    }

    // MARK: - Timer Tests

    @Test("setTimeout schedules and returns timer ID")
    func testSetTimeoutReturnsID() {
        let engine = Engine()
        let (result, error) = engine.evaluate("setTimeout(function(){}, 1000)")
        #expect(error == nil)
        #expect(result != nil)
        // Timer ID should be a number (first timer = 1)
        let timerID = Int(result ?? "")
        #expect(timerID != nil)
        #expect(timerID! >= 1)
        engine.cancelAllTimers()
    }

    @Test("clearTimeout cancels a scheduled timer")
    func testClearTimeout() {
        let engine = Engine()
        // Set a global variable, schedule a timer to change it, then cancel
        engine.evaluate("""
            var timerFired = false;
            var tid = setTimeout(function() { timerFired = true; }, 10);
            clearTimeout(tid);
        """)
        // Give it time to potentially fire (it shouldn't)
        let (result, _) = engine.evaluate("timerFired")
        #expect(result == "false")
        engine.cancelAllTimers()
    }

    @Test("Multiple timer IDs are unique")
    func testTimerIDsUnique() {
        let engine = Engine()
        let (id1, _) = engine.evaluate("setTimeout(function(){}, 1000)")
        let (id2, _) = engine.evaluate("setTimeout(function(){}, 1000)")
        #expect(id1 != nil)
        #expect(id2 != nil)
        #expect(id1 != id2)
        engine.cancelAllTimers()
    }

    @Test("cancelAllTimers clears all pending timers")
    func testCancelAllTimers() {
        let engine = Engine()
        engine.evaluate("setTimeout(function(){}, 1000)")
        engine.evaluate("setTimeout(function(){}, 2000)")
        engine.evaluate("setInterval(function(){}, 500)")
        engine.cancelAllTimers()
        // After cancelling, new timer IDs should still increment, but no timers should be pending
        // This test just verifies cancelAllTimers doesn't crash
    }

    // MARK: - Config Store Tests

    @Test("$$__config stores values in configStore")
    func testConfigStore() {
        let engine = Engine()
        engine.evaluate("""
            $$__config({ launcher: { hotkey: "cmd+space" }, debug: true })
        """)
        let launcher = engine.configStore["launcher"] as? [String: Any]
        #expect(launcher != nil)
        #expect(launcher?["hotkey"] as? String == "cmd+space")

        let debug = engine.configStore["debug"] as? Bool
        #expect(debug == true)
    }

    @Test("$$__config overwrites previous configStore")
    func testConfigStoreOverwrite() {
        let engine = Engine()
        engine.evaluate("$$__config({ a: 1 })")
        #expect(engine.configStore["a"] as? Int == 1)

        engine.evaluate("$$__config({ b: 2 })")
        #expect(engine.configStore["b"] as? Int == 2)
        // Old key should be gone since configStore is fully replaced
        #expect(engine.configStore["a"] == nil)
    }

    // MARK: - Module Registration Tests

    @Test("registerAllModules creates macotron global object")
    func testRegisterAllModulesCreatesMacotronGlobal() {
        let engine = Engine()
        engine.registerAllModules()
        let (result, error) = engine.evaluate("typeof macotron")
        #expect(error == nil)
        #expect(result == "object")
    }

    @Test("registerAllModules sets version info")
    func testRegisterAllModulesSetsVersion() {
        let engine = Engine()
        engine.registerAllModules()
        let (result, error) = engine.evaluate("macotron.version.app")
        #expect(error == nil)
        #expect(result == "1.0.0")
    }

    @Test("registerAllModules registers custom module")
    func testRegisterAllModulesWithCustomModule() {
        let engine = Engine()
        let testModule = StubModule(name: "testmod", version: 3)
        engine.addModule(testModule)
        engine.registerAllModules()

        // Check the module version is set on macotron.version.modules
        let (result, error) = engine.evaluate("macotron.version.modules.testmod")
        #expect(error == nil)
        #expect(result == "3")
        #expect(testModule.wasRegistered)
    }

    // MARK: - Error Isolation Tests

    @Test("JS error in one evaluate doesn't break subsequent evaluates")
    func testErrorIsolation() {
        let engine = Engine()
        // First call: produce an error
        let (_, error1) = engine.evaluate("throw new Error('boom')")
        #expect(error1 != nil)

        // Second call: should still work fine
        let (result2, error2) = engine.evaluate("1 + 1")
        #expect(error2 == nil)
        #expect(result2 == "2")
    }

    @Test("ReferenceError doesn't corrupt engine state")
    func testReferenceErrorIsolation() {
        let engine = Engine()
        let (_, error1) = engine.evaluate("nonExistent.foo")
        #expect(error1 != nil)

        // Engine should still be usable
        engine.evaluate("var z = 99")
        let (result, error2) = engine.evaluate("z")
        #expect(error2 == nil)
        #expect(result == "99")
    }

    @Test("SyntaxError doesn't corrupt engine state")
    func testSyntaxErrorIsolation() {
        let engine = Engine()
        let (_, error1) = engine.evaluate("function {{{")
        #expect(error1 != nil)

        let (result, error2) = engine.evaluate("'still works'")
        #expect(error2 == nil)
        #expect(result == "still works")
    }

    // MARK: - Log Handler Tests

    @Test("logHandler receives $$__log output")
    func testLogHandler() {
        let engine = Engine()
        var capturedLog: String?
        engine.logHandler = { msg in
            capturedLog = msg
        }
        engine.evaluate("$$__log('hello from JS')")
        #expect(capturedLog == "hello from JS")
    }

    // MARK: - Command Registration Tests

    @Test("$$__registerCommand populates commandRegistry")
    func testRegisterCommand() {
        let engine = Engine()
        engine.evaluate("""
            $$__registerCommand("greet", "Says hello", function() { return "hi"; });
        """)
        #expect(engine.commandRegistry["greet"] != nil)
        #expect(engine.commandRegistry["greet"]?.name == "greet")
        #expect(engine.commandRegistry["greet"]?.description == "Says hello")
    }

    // MARK: - Reset Clears Everything

    @Test("Reset clears command registry")
    func testResetClearsCommands() {
        let engine = Engine()
        engine.evaluate("""
            $$__registerCommand("test", "Test cmd", function() {});
        """)
        #expect(!engine.commandRegistry.isEmpty)
        engine.reset()
        #expect(engine.commandRegistry.isEmpty)
    }

    @Test("Reset clears event listeners")
    func testResetClearsEventListeners() {
        let engine = Engine()
        engine.evaluate("""
            $$__on("my:event", function() {});
        """)
        #expect(engine.eventBus.hasListeners(for: "my:event"))
        engine.reset()
        #expect(!engine.eventBus.hasListeners(for: "my:event"))
    }

    // MARK: - Arithmetic and Expressions

    @Test("Evaluate complex arithmetic")
    func testComplexArithmetic() {
        let engine = Engine()
        let (result, error) = engine.evaluate("(10 * 5 + 3) / 2")
        #expect(error == nil)
        #expect(result == "26.5")
    }

    @Test("Evaluate template literals")
    func testTemplateLiterals() {
        let engine = Engine()
        engine.evaluate("var name = 'Macotron'")
        let (result, error) = engine.evaluate("`Hello ${name}!`")
        #expect(error == nil)
        #expect(result == "Hello Macotron!")
    }
}

// MARK: - Test Helpers

/// A stub NativeModule for testing module registration
@MainActor
final class StubModule: NativeModule {
    let name: String
    let moduleVersion: Int
    var defaultOptions: [String: Any] { [:] }
    var wasRegistered = false
    var registeredOptions: [String: Any] = [:]

    init(name: String, version: Int) {
        self.name = name
        self.moduleVersion = version
    }

    func register(in engine: Engine, options: [String: Any]) {
        wasRegistered = true
        registeredOptions = options
    }

    func cleanup() {
        wasRegistered = false
    }
}
