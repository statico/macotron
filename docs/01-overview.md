# Macotron Overview

Macotron is a thin macOS host for JavaScript automation plugins. Macotron is a modern Hammerspoon, with extras like xbar.

External coding agents edit plugins. The app does not ship an in-app coding agent. You open the plugins directory in Cursor or Claude Code. The agent writes `.js` files. Macotron loads and runs them.

**Core principle:** Everything is "listen for event -> run code."

Plugins are JavaScript files that register hotkeys, hooks, and UI at load time. The files on disk are the source of truth.

**The layer cake:**

```
┌─────────────────────────────────┐
│  External agent                 │  Cursor / Claude Code edits plugins
├─────────────────────────────────┤
│  Plugins directory (git repo)   │  plugins/*.js + settings.json
├─────────────────────────────────┤
│  JS Engine (QuickJS)            │  macotron.keyboard.on("tile-left", "ctrl+opt+left", ...)
├─────────────────────────────────┤
│  Native Bridge (Swift)          │  AXUIElement, CGEventTap, ScreenCaptureKit, ...
├─────────────────────────────────┤
│  macOS                          │  windows move, events fire, notifications show
└─────────────────────────────────┘
```

## Product Shape

The host UI stays minimal:

- First-run wizard
- Settings
- Menu bar
- Launcher hotkey
- Plugin list

Plugin UI uses small WKWebView panels through `macotron.panel`.

## First-Run Wizard

On first launch, the wizard guides the user:

1. **Welcome** — Macotron hosts plugins that automate macOS.
2. **Pick directory** — Choose the plugins workdir. Optionally open it in Finder or Cursor.
3. **Ready** — The app seeds `README.md` once if missing. It writes `AGENTS.md` and `CLAUDE.md`.

The wizard does not demand Accessibility up front. Permissions arrive when a feature needs them.

## How Plugins Work

Each `.js` file under `plugins/` runs once at load. Side effects register hotkeys, timers, menu items, and panels. A file change triggers a full reload.

Plugins can call `macotron.ai` for Claude, OpenAI, Gemini, or on-device Foundation Models. That API is for plugin code. It is not an in-app agent session.

## Marketplace

Settings link to the GitHub topic search `topic:macotron-plugin`. v1 has no custom store backend.

https://github.com/topics/macotron-plugin

## Tech Stack

| Layer | Technology |
|---|---|
| Language | Swift 6.2 (strict concurrency, `defaultIsolation: MainActor`) |
| UI | SwiftUI + NSPanel |
| JS Runtime | QuickJS via [quickjs-ng](https://github.com/quickjs-ng/quickjs) (embedded C library, ~400KB) |
| Package Manager | Swift Package Manager |
| Min Target | macOS 15 Sequoia (macOS 26 Tahoe for Foundation Models) |
| Distribution | Direct download (optional Homebrew cask; the app does not need brew) |

### Why QuickJS over JavaScriptCore?

JSC ships with macOS and has a JIT compiler. For automation glue code those wins do not matter. QuickJS (quickjs-ng) wins on the points that do:

- **Explicit event loop control** — `JS_ExecutePendingJob()` drains the microtask queue in a clear order.
- **Script interruption** — `JS_SetInterruptHandler()` can stop runaway plugins.
- **ES modules** — native `import`/`export` with a custom module loader.
- **Bytecode caching** — compile `.js` to bytecode once, then load fast from `.cache/`.
- **Lower memory** — about 100-200KB per context vs about 1-5MB for JSC.
- **Faster startup** — about 300us vs about 2-10ms for JSC.
- **MIT license**, actively maintained.
- **About 400KB** added to the binary.

## Process Architecture

Single process, thin surfaces:

```
┌──────────────────────────────────────────────────────┐
│                    Macotron.app                       │
│                                                      │
│  Menu bar | Settings | Wizard | Launcher | Plugin list│
│                                                      │
│  ┌──────────────────────────────────────────────┐    │
│  │            MacotronEngine                    │    │
│  │  QuickJS | EventBus | Plugin loader           │    │
│  │  Native modules (window, keyboard, ai, panel,│    │
│  │  shell, fs, screen, ...)                     │    │
│  └──────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────┘
```

UserDefaults stores only the path to the workdir (`pluginsDirectory`). All other settings live in `settings.json` inside the workdir.
