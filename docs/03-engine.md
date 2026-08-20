# Core Engine Design

## Engine.swift — QuickJS Runtime

`Engine` wraps a QuickJS runtime and context. It provides:

- `evaluate(_ js:, filename:)` — Execute JS, returns `(output?, error?)`
- `evaluateBytecode(_:, filename:)` — Run cached bytecode
- `compileToBytecode(_:, filename:)` — Compile JS source to bytecode `Data`
- `drainJobQueue()` — Process pending async jobs (promises and more)
- `reset()` — Tear down context, cancel timers, re-create fresh
- `addModule(_:)` / `registerAllModules()` — Register native modules
- `commandRegistry` — Dictionary of registered JS commands
- `pluginChecks` — Latest `macotron.checks()` rows, keyed by plugin filename
- `logHandler` — Closure for `console.log` output

Module loader resolves ES module imports relative to `moduleBaseDir` (the user plugins workdir).

Module options come from the `modules` block in `settings.json`.

## NativeModule Protocol

```swift
protocol NativeModule: AnyObject {
    var name: String { get }
    func register(in engine: Engine, options: [String: Any])
}
```

Modules register C functions via `JS_SetPropertyStr` on the global `macotron` object.

## EventBus — Unified Event Dispatch

`EventBus` manages JS callback registration and dispatch:

- `on(_ event:, callback:, ctx:)` — Register a listener
- `emit(_ event:, engine:, data:)` — Fire an event, calling all listeners
- `removeAllListeners()` — Tear down (called on reset)

All callbacks are ref-counted via `JS_DupValue` / `JS_FreeValue`.

## Execution Model

Plugins load from `plugins/` in alphabetical order on app launch. Each file runs once. Side effects register event listeners, hotkeys, commands, menubar items, and panels.

```
App Launch
  |
  +-- Read settings.json          (hotkey, UI prefs, plugin options)
  +-- Load plugins/001-....js     (registers listeners)
  +-- Load plugins/002-....js
  +-- Ready.
```

Any file change in the workdir triggers a hot reload. **Reload** clears all listeners, commands, menubar items, and panels. Then the engine re-executes every plugin from disk.

Bytecode caches under `.cache/` inside the workdir. That directory is gitignored.

## Scheduling

`macotron.every(ms | "1h", fn)` and `macotron.at("1pm", fn)` register wall-clock jobs in native `ScheduleModule`. Both return a stop function. Jobs run only while Macotron is launched; reload cancels all schedules. `macotron.sleep(ms)` remains a one-shot JS promise helper in `macotron-runtime.js`.
