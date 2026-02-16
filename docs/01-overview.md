# Macotron Overview

Macotron is an AI-powered coding agent for macOS automation. It replaces Raycast, Hammerspoon, Rectangle, Velja, OverSight, xbar, and similar tools with a single scriptable app. Users describe what they want in natural language — the agent plans, writes JavaScript scripts, reloads the engine, tests them, and auto-repairs if anything breaks. Think Claude Code or Manus, not ChatGPT.

**Core principle:** Everything is "listen for event -> run code." Under the hood, Macotron is a collection of JavaScript files executed in order, easily reloadable, with rich native macOS API bindings. The agent is the primary configuration interface — not a text editor, not a chat window.

**The layer cake:**
```
┌─────────────────────────────┐
│  User (prompt)              │  "set up keybindings to move windows"
├─────────────────────────────┤
│  Agent (plans + writes JS)  │  plans steps, writes window-tiling.js, reloads, tests, repairs
├─────────────────────────────┤
│  JS Engine (executes)       │  macotron.keyboard.on("ctrl+opt+left", ...)
├─────────────────────────────┤
│  Native Bridge (Swift)      │  AXUIElement, CGEventTap, ScreenCaptureKit, ...
├─────────────────────────────┤
│  macOS                      │  windows move, events fire, notifications show
└─────────────────────────────┘
```

The JS files are the "compiled output" — real, readable, editable if you want, but most users never touch them. Power users can write snippets directly. Either way, the source of truth is the files on disk.

## First-Run Wizard

On first launch, a four-step wizard guides the user:

1. **Welcome** — Macotron is a tool that uses AI to set up automations. Shows example use cases: create window shortcuts, automate camera lights, open links in specific browsers, build a menu bar dashboard.
2. **Permissions** — Suggests enabling Accessibility, Input Monitoring, and Screen Recording. User can skip, but functionality will be limited.
3. **AI Provider** — Select a provider and enter an API key. Dev shortcut: if `~/.macotron-dev.json` exists with a pre-set key, this step is auto-filled.
4. **Open prompt panel** — Drops the user into the main interface.

## Main Prompt Panel

The prompt panel is not a search bar — it's a command entry point. It shows example prompts to get started:

- "set up keybindings to let me move windows"
- "use safari to open all youtube links"
- "show CPU and memory in the menu bar"
- "flash my USB light when my camera turns on"

When the user enters a command, the agent takes over.

## Agent Workflow

The agent operates like a coding agent, not a chatbot:

1. **Plan** — Decide what scripts to create or modify.
2. **Write** — Generate JavaScript snippets to `~/.macotron/snippets/`.
3. **Reload** — Hot-reload the engine to pick up changes.
4. **Test** — Validate that scripts loaded without errors and behave correctly.
5. **Repair** — If anything fails, read the error trace, fix the script, and retry (with rate limiting).
6. **Report** — Show progress in a floating panel: "Writing script..." -> "Testing script..." -> "Done!"

### Context Engineering

Inspired by the Manus approach:

- **Stable prompt prefix** — Keep the system prompt and tool definitions static for KV-cache efficiency. Dynamic context goes at the end.
- **File system as memory** — The agent writes plans and state to disk (`~/.macotron/agent/`), not just to the context window.
- **Failure traces** — Preserve error logs so the agent learns from past mistakes within a session.
- **Rate-limited auto-repair** — Retry broken scripts automatically, but cap retries to avoid loops.

## Summary Tab

Settings > Summary keeps a live overview of all active scripts: what they do, what events they listen to, and their current status. This is always kept up to date as scripts are added or modified.

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
- **Bytecode caching** — compile `.js` -> bytecode once, load instantly on subsequent runs.
- **Lower memory** — ~100-200KB per context vs ~1-5MB for JSC.
- **Faster startup** — ~300us vs ~2-10ms for JSC.
- **MIT license**, actively maintained.
- **~400KB** added to binary.

## Process Architecture

Single process, three surfaces:

```
┌──────────────────────────────────────────────────────┐
│                    Macotron.app                       │
│                                                      │
│  ┌──────────────────┐  ┌──────────────────────────┐  │
│  │ Menu Bar         │  │ Floating Prompt Panel    │  │
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
│                                                      │
│  ┌──────────────────────────────────────────────┐    │
│  │            Agent Loop                        │    │
│  │  ┌─────────┐ ┌────────┐ ┌──────────────┐    │    │
│  │  │ Planner │ │ Writer │ │ Test/Repair  │    │    │
│  │  └─────────┘ └────────┘ └──────────────┘    │    │
│  │  ┌──────────────────────────────────────┐    │    │
│  │  │  Context: plans, state, error logs   │    │    │
│  │  │  (~/.macotron/agent/)                │    │    │
│  │  └──────────────────────────────────────┘    │    │
│  └──────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────┘
```

The app uses `NSApp.setActivationPolicy(.accessory)` so it lives in the menubar without a Dock icon.
