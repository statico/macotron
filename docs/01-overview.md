# Macotron Overview

Macotron is a unified, AI-powered macOS automation platform that replaces Raycast, Hammerspoon, Rectangle, Velja, OverSight, xbar, and similar tools with a single scriptable app. Users interact through natural language — the AI writes JavaScript, the JavaScript talks to macOS. You never have to see the code if you don't want to.

**Core principle:** Everything is "listen for event → run code." Under the hood, Macotron is a collection of JavaScript files executed in order, easily reloadable, with rich native macOS API bindings. The AI is the primary configuration interface — not a text editor.

**The layer cake:**
```
┌─────────────────────────────┐
│  User (natural language)    │  "tile my windows with keyboard shortcuts"
├─────────────────────────────┤
│  AI (generates JS)          │  writes window-tiling.js → ~/.macotron/snippets/
├─────────────────────────────┤
│  JS Engine (executes)       │  macotron.keyboard.on("ctrl+opt+left", ...)
├─────────────────────────────┤
│  Native Bridge (Swift)      │  AXUIElement, CGEventTap, ScreenCaptureKit, ...
├─────────────────────────────┤
│  macOS                      │  windows move, events fire, notifications show
└─────────────────────────────┘
```

The JS files are the "compiled output" — real, readable, editable if you want, but most users never touch them. Power users can write snippets directly. Either way, the source of truth is the files on disk.

## Tech Stack

| Layer | Technology |
|---|---|
| Language | Swift 6.2 (strict concurrency, `defaultIsolation: MainActor`) |
| UI | SwiftUI + NSPanel (floating launcher) |
| JS Runtime | QuickJS via [quickjs-ng](https://github.com/quickjs-ng/quickjs) (embedded C library, ~400KB) |
| Package Manager | Swift Package Manager |
| Min Target | macOS 15 Sequoia (macOS 26 Tahoe for Foundation Models) |
| Distribution | Direct download + Homebrew (not App Store — needs Accessibility & Input Monitoring) |

### Why QuickJS over JavaScriptCore?

JSC ships with macOS (zero binary cost) and has a JIT compiler, but for automation glue code neither matters. QuickJS (quickjs-ng) wins on every dimension that does matter:

- **Explicit event loop control** — `JS_ExecutePendingJob()` drains the microtask queue deterministically.
- **Script interruption** — `JS_SetInterruptHandler()` lets us kill runaway snippets.
- **ES modules** — native `import`/`export` with a custom module loader.
- **Bytecode caching** — compile `.js` → bytecode once, load instantly on subsequent runs.
- **Lower memory** — ~100-200KB per context vs ~1-5MB for JSC.
- **Faster startup** — ~300μs vs ~2-10ms for JSC.
- **MIT license**, actively maintained.
- **~400KB** added to binary.

## Process Architecture

Single process, three surfaces:

```
┌──────────────────────────────────────────────────────┐
│                    Macotron.app                       │
│                                                      │
│  ┌──────────────────┐  ┌──────────────────────────┐  │
│  │ Menu Bar         │  │ Floating Launcher Panel  │  │
│  │ Dropdown (xbar)  │  │ (NSPanel + SwiftUI)      │  │
│  │ (always on)      │  │ (toggle via hotkey)      │  │
│  └──────────────────┘  └──────────────────────────┘  │
│                                                      │
│  ┌──────────────────────────────────────────────┐    │
│  │            MacotronEngine                    │    │
│  │  ┌─────────┐ ┌────────┐ ┌──────────────┐    │    │
│  │  │ JSCore  │ │ Event  │ │ Snippet      │    │    │
│  │  │ VM      │ │ Bus    │ │ Manager      │    │    │
│  │  └─────────┘ └────────┘ └──────────────┘    │    │
│  │  ┌──────────────────────────────────────┐    │    │
│  │  │        Native Modules                │    │    │
│  │  │  window | keyboard | screen |        │    │    │
│  │  │  shell  | notify   | camera |        │    │    │
│  │  │  url    | usb      | fs     |        │    │    │
│  │  │  ai     | clipboard| system |        │    │    │
│  │  │  app    | spotlight| http   |        │    │    │
│  │  │  menubar| display  | timer  |        │    │    │
│  │  └──────────────────────────────────────┘    │    │
│  └──────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────┘
```

The app uses `NSApp.setActivationPolicy(.accessory)` so it lives in the menubar without a Dock icon.
