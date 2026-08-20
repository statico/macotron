# Phase Plan

## Historical Phases (pre host-shell)

These phases describe the earlier in-app agent product. They are complete for the old architecture. They are not the roadmap for host-shell v1.

### Phase 1 — Engine + Menubar (historical) ✅

- [x] Swift package with vendored quickjs-ng
- [x] QuickJS engine: runtime, context, timers, job queue draining
- [x] EventBus (native events → JS callbacks)
- [x] NativeModule protocol
- [x] Ordered script loading and FSEvents reload
- [x] Menubar with NSStatusItem + dynamic NSMenu
- [x] localStorage, Keychain module
- [x] Basic modules: shell, notify, fs, timer, menubar

### Phase 2 — Launcher + Key Modules (historical) ✅

- [x] NSPanel floating window with SwiftUI
- [x] Global hotkey to toggle
- [x] Window, keyboard, clipboard modules
- [x] Broad native module set
- [x] Permission helpers

### Phase 3 — AI Providers (historical) ✅

- [x] AI provider abstraction (Claude, OpenAI, Gemini, Local)
- [x] `macotron.ai` module surface for scripts

### Phase 4–6 — In-app Agent (historical / superseded)

Earlier plans covered an in-app coding agent, chat UI, auto-fix, and Application Support snippets. Host-shell redesign removes that product path. External agents edit plugins instead.

---

## Host-Shell v1 Phases

Source of truth: [2026-08-17-host-shell-design.md](superpowers/specs/2026-08-17-host-shell-design.md).

### HS-1 — Workdir and Settings

- [ ] First-run wizard picks plugins directory
- [ ] Optional open in Finder / Cursor
- [ ] `git init` of the workdir
- [ ] Seed human `README.md` once if missing
- [ ] Write app-owned `AGENTS.md` and `CLAUDE.md` (do not edit banner)
- [ ] `.gitignore` for `AGENTS.md`, `CLAUDE.md`, `.cache/`
- [ ] `settings.json` with hot reload
- [ ] UserDefaults stores only `pluginsDirectory`

### HS-2 — Plugin Loader

- [ ] Load `plugins/*.js` in alphabetical order
- [ ] Hot reload on any workdir file change
- [ ] Bytecode cache under `.cache/`
- [ ] Plugin list in host UI

### HS-3 — Thin Host UI

- [ ] Settings window for workdir path, UI prefs, marketplace link
- [ ] Menu bar
- [ ] Launcher hotkey from `settings.json`
- [ ] Remove in-app AgentSession, ChatSession, tool-call agent UI, module auto-fix

### HS-4 — Panel Module and Lazy Permissions

- [ ] `macotron.panel` WKWebView API
- [ ] Prompt Accessibility / Input Monitoring only when hotkeys need them
- [ ] Prompt Screen Recording on first capture use

### HS-5 — Marketplace Link and Polish

- [ ] Settings link to `https://github.com/topics/macotron-plugin`
- [ ] Keep `macotron.ai` for plugins (including `macotron.ai.local()` when available)
- [ ] Docs match this architecture
- [ ] Homebrew cask and notarized DMG (later)
