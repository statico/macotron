# Core Engine Design

## Engine.swift — QuickJS Runtime

```swift
import CQuickJS

@MainActor
final class Engine {
    private(set) var runtime: OpaquePointer!   // JSRuntime*
    private(set) var context: OpaquePointer!   // JSContext*
    let eventBus = EventBus()
    private var modules: [NativeModule] = []
    private var timers: [UInt32: DispatchSourceTimer] = [:]
    private var nextTimerID: UInt32 = 1

    init() {
        runtime = JS_NewRuntime()
        context = JS_NewContext(runtime)

        JS_SetInterruptHandler(runtime, { rt, opaque -> Int32 in
            let engine = Unmanaged<Engine>.fromOpaque(opaque!).takeUnretainedValue()
            return engine.shouldInterrupt ? 1 : 0
        }, Unmanaged.passUnretained(self).toOpaque())

        JS_SetModuleLoaderFunc(runtime, nil, { ctx, moduleName, opaque -> OpaquePointer? in
            let name = String(cString: moduleName!)
            return Engine.loadModule(ctx: ctx!, name: name)
        }, nil)

        setupTimers()
        setupRuntime()
        registerModules()
    }

    func drainJobQueue() {
        while true {
            let ret = JS_ExecutePendingJob(runtime, nil)
            if ret <= 0 { break }
        }
    }

    func evaluate(_ js: String, filename: String = "<eval>") -> (String?, String?) {
        let result = js.withCString { cStr in
            JS_Eval(context, cStr, js.utf8.count, filename, Int32(JS_EVAL_TYPE_GLOBAL))
        }
        drainJobQueue()

        if JS_IsException(result) != 0 {
            let exception = JS_GetException(context)
            let errStr = String(cString: JS_ToCString(context, exception))
            JS_FreeValue(context, exception)
            return (nil, errStr)
        }

        let str = JS_ToCString(context, result)
        let output = str != nil ? String(cString: str!) : nil
        JS_FreeCString(context, str)
        JS_FreeValue(context, result)
        return (output, nil)
    }

    func reset() {
        cancelAllTimers()
        JS_FreeContext(context)
        context = JS_NewContext(runtime)
        setupTimers()
        setupRuntime()
        registerModules()
    }

    deinit {
        cancelAllTimers()
        JS_FreeContext(context)
        JS_FreeRuntime(runtime)
    }
}
```

## NativeModule Protocol

```swift
protocol NativeModule: AnyObject {
    var name: String { get }
    var version: Int { get }
    var defaultOptions: [String: Any] { get }
    func register(in engine: Engine, options: [String: Any])
}

extension NativeModule {
    var version: Int { 1 }
    var defaultOptions: [String: Any] { [:] }
}
```

Modules register C functions via `JS_SetPropertyStr` on the global `macotron` object. Module-specific options come from the `modules` block in `config.js` merged with `defaultOptions`.

```javascript
// config.js — module options
macotron.config({
    ai: {
        claude: { apiKey: macotron.keychain.get("claude-api-key") },
    },
    launcher: { hotkey: "cmd+space" },
    modules: {
        camera:   { pollInterval: 5000, device: "auto" },
        screen:   { retina: true, format: "png" },
        shell:    { timeout: 30000, maxOutput: "1MB" },
        keyboard: { swallowMatched: true },
        notify:   { sound: true, groupId: "macotron" },
    }
});
```

## EventBus — Unified Event Dispatch

```swift
@MainActor
final class EventBus {
    struct Listener {
        let callback: JSValue
        let ctx: OpaquePointer
    }

    private var listeners: [String: [Listener]] = [:]

    func on(_ event: String, callback: JSValue, ctx: OpaquePointer) {
        let protected = JS_DupValue(ctx, callback)
        listeners[event, default: []].append(Listener(callback: protected, ctx: ctx))
    }

    func emit(_ event: String, engine: Engine, data: JSValue = JS_UNDEFINED) {
        guard let callbacks = listeners[event] else { return }
        for listener in callbacks {
            JS_Call(engine.context, listener.callback, JS_UNDEFINED,
                    data == JS_UNDEFINED ? 0 : 1,
                    data == JS_UNDEFINED ? nil : [data])
        }
        engine.drainJobQueue()
    }

    func removeAllListeners() {
        for (_, list) in listeners {
            for listener in list {
                JS_FreeValue(listener.ctx, listener.callback)
            }
        }
        listeners.removeAll()
    }
}
```

## Execution Model

Snippets are loaded and executed in alphabetical order on app launch. Each file runs once, registering event listeners, commands, and menubar items as side effects.

```
App Launch
  │
  ├── Load config.js           (API keys, preferences)
  ├── Load 001-window-tiling.js   (registers keyboard listeners)
  ├── Load 002-url-handlers.js    (registers URL handler)
  ├── Load 003-cpu-monitor.js     (starts interval timer)
  ├── Load 004-camera-light.js    (starts camera polling)
  ├── Load 005-menubar-items.js   (adds items to menubar dropdown)
  ├── Load commands/*.js          (registers launcher commands)
  └── Ready.
```

**Reload** clears all listeners, commands, and menubar items, then re-executes everything from disk.
