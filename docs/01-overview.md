# Macotron Overview

Macotron is a modern Hammerspoon: a thin native macOS host for JavaScript automation plugins.

External coding agents edit plugins. The app does not ship an in-app coding agent. You open the plugins directory in Claude Code, Codex, Cursor, or pi.dev. The agent writes `.js` files. Macotron loads and runs them.

**Core principle:** Everything is "listen for event -> run code."

Plugins are JavaScript files that register hotkeys, hooks, and UI at load time. The files on disk are the source of truth.

**The layer cake:**

```
┌─────────────────────────────────┐
│  External agent                 │  Claude Code, Codex, Cursor, pi.dev
├─────────────────────────────────┤
│  Plugins directory (git repo)   │  plugins/*.js + settings.json
├─────────────────────────────────┤
│  JS Engine (QuickJS)            │  macotron.keyboard.on("Tile Left", "ctrl+opt+left", ...)
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
2. **Pick directory** — Choose the plugins workdir. Optionally open it in Finder or your editor.
3. **Choose plugins** — Install built-in plugins. You can skip this.
4. **Permissions** — Grant what the installed plugins declared.
5. **Ready** — The app seeds `README.md` once if missing. It writes `AGENTS.md` and `CLAUDE.md`.

The wizard does not demand Accessibility up front. Permissions arrive when a feature needs them.

The first-run catalog lists built-in plugins after the folder step and before permissions. Featured plugins are highlighted. You can skip the catalog and install later from Settings → Plugins.

## How Plugins Work

Each `.js` file under `plugins/` runs once at load if its SHA-256 matches the last approved hash in the Keychain, or if Hot Reload is on. Side effects register hotkeys, timers, menu items, and panels.

With Hot Reload off, a disk change does not replace a running plugin. The menu bar shows an orange dot and **Review & Reload**. Cold start does not execute a file whose hash does not match.

Plugins can call `macotron.ai` for Claude, OpenAI, Gemini, or on-device Foundation Models. That API is for plugin code. It is not an in-app agent session.

## Marketplace

The in-app catalog installs built-in plugins. Settings also links to the GitHub topic search `topic:macotron-plugin`. Community listings are later.

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
