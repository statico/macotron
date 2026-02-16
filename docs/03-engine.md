# Core Engine Design

## Engine.swift — QuickJS Runtime

`Engine` wraps a QuickJS runtime and context. It provides:

- `evaluate(_ js:, filename:)` — Execute JS, returns `(output?, error?)`
- `evaluateBytecode(_:, filename:)` — Run cached bytecode
- `compileToBytecode(_:, filename:)` — Compile JS source to bytecode `Data`
- `drainJobQueue()` — Process pending async jobs (promises, etc.)
- `reset()` — Tear down context, cancel timers, re-create fresh
- `addModule(_:)` / `registerAllModules()` — Register native modules
- `configStore` — Dictionary populated by `macotron.config()` in config.js
- `commandRegistry` — Dictionary of registered JS commands
- `logHandler` — Closure for `console.log` output

Module loader resolves ES module imports relative to `moduleBaseDir` (the user's config directory).

## NativeModule Protocol

```swift
protocol NativeModule: AnyObject {
    var name: String { get }
    func register(in engine: Engine, options: [String: Any])
}
```

Modules register C functions via `JS_SetPropertyStr` on the global `macotron` object. Module-specific options come from the `modules` block in `config.js`.

## EventBus — Unified Event Dispatch

`EventBus` manages JS callback registration and dispatch:

- `on(_ event:, callback:, ctx:)` — Register a listener
- `emit(_ event:, engine:, data:)` — Fire an event, calling all listeners
- `removeAllListeners()` — Tear down (called on reset)

All callbacks are ref-counted via `JS_DupValue` / `JS_FreeValue`.

## Execution Model

Snippets are loaded and executed in alphabetical order on app launch. Each file runs once, registering event listeners, commands, and menubar items as side effects.

```
App Launch
  |
  +-- Load config.js              (API keys, preferences)
  +-- Load 001-window-tiling.js   (registers keyboard listeners)
  +-- Load 002-url-handlers.js    (registers URL handler)
  +-- Load 003-cpu-monitor.js     (starts interval timer)
  +-- Load 004-camera-light.js    (starts camera polling)
  +-- Load 005-menubar-items.js   (adds items to menubar dropdown)
  +-- Load commands/*.js          (registers launcher commands)
  +-- Ready.
```

**Reload** clears all listeners, commands, and menubar items, then re-executes everything from disk.
