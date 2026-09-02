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

    @Test("unhandled promise rejection is recorded")
    func testUnhandledRejection() {
        let engine = Engine()
        engine.evaluate("(async () => { throw new Error('boom') })()")
        #expect(engine.lastUnhandledRejection?.contains("boom") == true)

        engine.lastUnhandledRejection = nil
        engine.evaluate("(async () => { throw new Error('caught') })().catch(() => {})")
        #expect(engine.lastUnhandledRejection == nil)
    }

    @Test("Evaluate error returns error string")
    func testEvaluateError() {
        let engine = Engine()
        let (result, error) = engine.evaluate("undefinedVar.property")
        #expect(result == nil)
        #expect(error != nil)
    }

    @Test("isolated plugins can both declare const opts")
    func testIsolatedPluginConst() {
        let engine = Engine()
        let (_, first) = engine.evaluate("const opts = 1")
        #expect(first == nil)
        let (_, clash) = engine.evaluate("const opts = 2")
        #expect(clash != nil)
        #expect(clash?.contains("opts") == true)

        let isolated = Engine()
        let (_, a) = isolated.evaluate(Engine.isolatedPlugin("const opts = 1"))
        let (_, b) = isolated.evaluate(Engine.isolatedPlugin("const opts = 2"))
        #expect(a == nil)
        #expect(b == nil)
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

    @Test("$$__on records unique events for the current plugin file")
    func recordsPluginEvents() {
        let engine = Engine()
        engine.currentEvaluatingFile = "weather.js"
        engine.evaluate("""
            $$__on("timer:tick", function() {});
            $$__on("timer:tick", function() {});
            $$__on("system:wake", function() {});
        """)
        #expect(engine.pluginEvents["weather.js"] == ["timer:tick", "system:wake"])
    }

    @Test("$$__on does not record events without a plugin file")
    func pluginEventsNeedAFile() {
        let engine = Engine()
        engine.evaluate("$$__on('timer:tick', function() {})")
        #expect(engine.pluginEvents.isEmpty)
    }

    @Test("reset clears recorded plugin events")
    func resetClearsPluginEvents() {
        let engine = Engine()
        engine.currentEvaluatingFile = "weather.js"
        engine.evaluate("$$__on('timer:tick', function() {})")
        engine.reset()
        #expect(engine.pluginEvents.isEmpty)
    }

    // MARK: - Type Return Tests

    @Test("evaluate stringifies each result type", arguments: [
        ("1 + 2", "3"),
        ("'hello' + ' ' + 'world'", "hello world"),
        ("42", "42"),
        ("3.14", "3.14"),
        ("true", "true"),
        ("false", "false"),
        ("JSON.stringify({a: 1, b: 'two'})", "{\"a\":1,\"b\":\"two\"}"),
        ("JSON.stringify([1, 2, 3])", "[1,2,3]"),
        // QuickJS JS_ToCString renders undefined and null as their names, and
        // a var declaration evaluates to undefined.
        ("undefined", "undefined"),
        ("null", "null"),
        ("var y = 10", "undefined"),
    ])
    func evaluatesTo(_ source: String, _ expected: String) {
        let engine = Engine()
        let (result, error) = engine.evaluate(source)
        #expect(error == nil)
        #expect(result == expected)
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

    @Test("a failed evaluate leaves the engine usable", arguments: [
        ("throw new Error('boom')", "1 + 1", "2"),
        ("nonExistent.foo", "var z = 99; z", "99"),
        ("function {{{", "'still works'", "still works"),
    ])
    func errorIsolation(_ bad: String, _ next: String, _ expected: String) {
        let engine = Engine()
        let (_, error1) = engine.evaluate(bad)
        #expect(error1 != nil)

        let (result, error2) = engine.evaluate(next)
        #expect(error2 == nil)
        #expect(result == expected)
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
        #expect(engine.commandRegistry["greet"]?.id == "greet")
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

    // MARK: - Script vs Module Detection

    @Test("Plain script returns its value, not a promise")
    func testScriptIsNotTreatedAsModule() {
        let engine = Engine()
        let (result, error) = engine.evaluate("'plain script'")
        #expect(error == nil)
        #expect(result == "plain script")
    }

    @Test("Top-level var in a script lands on the global object")
    func testScriptVarIsGlobal() {
        let engine = Engine()
        engine.evaluate("var scriptScoped = 5")
        let (result, error) = engine.evaluate("globalThis.scriptScoped")
        #expect(error == nil)
        #expect(result == "5")
    }

    @Test("Source using export still runs as a module")
    func testExportRunsAsModule() {
        let engine = Engine()
        let (_, error) = engine.evaluate("""
            export const answer = 42;
            globalThis.fromModule = answer;
        """)
        #expect(error == nil)

        let (result, _) = engine.evaluate("globalThis.fromModule")
        #expect(result == "42")
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
