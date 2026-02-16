# Phase Plan

## Phase 1 — Engine + Menubar ✅
- [x] Swift package with vendored quickjs-ng
- [x] QuickJS engine: runtime, context, timers, job queue draining
- [x] EventBus (native events → JS callbacks)
- [x] NativeModule protocol with `version`, `defaultOptions`, `options`
- [x] SnippetManager with ordered loading from `~/Library/Application Support/Macotron/snippets/`
- [x] Snippet error isolation, full reload on FSEvents change
- [x] Menubar agent with NSStatusItem + dynamic NSMenu
- [x] Config backup/rollback
- [x] localStorage, Keychain module
- [x] Debug HTTP server
- [x] Basic modules: shell, notify, fs, timer, menubar

## Phase 2 — Launcher + Key Modules ✅
- [x] NSPanel floating window with SwiftUI
- [x] Global hotkey to toggle
- [x] Search field with fuzzy matching
- [x] Window module (AXUIElement)
- [x] Keyboard module (CGEventTap)
- [x] Clipboard module
- [x] All 18 native modules (screen, app, system, HTTP, camera, USB, URL, display, etc.)
- [x] Permission checks

## Phase 3 — AI Integration ✅
- [x] AI provider abstraction (Claude, OpenAI, Gemini, Local)
- [x] Tool-call-based file management
- [x] Capability review system
- [x] Chat mode in launcher (replaced by agent mode in Phase 4)
- [x] Auto-fix mechanism
- [x] Prompt injection mitigation
- [x] AI system prompt with type definitions

## Phase 4 — Agent Mode & Wizard
- [ ] First-run setup wizard (Welcome → Permissions → AI Provider → Open Prompt)
  - Dev shortcut: `~/Library/Application Support/Macotron-dev.json` for pre-set API key
- [ ] Replace chat interface with coding agent interface
- [ ] Agent progress UI (floating panel with shiny progress text)
  - Status flow: "Writing script..." → "Testing script..." → "Done!" with green check
- [ ] Example prompts in main panel ("set up keybindings to move windows", "use safari to open youtube links")
- [ ] Agent loop: plan → write → reload → validate → auto-repair → done
- [ ] Context engineering (stable prefix, file-system memory, failure traces, plan recitation)

## Phase 5 — Script Summary & Polish
- [ ] Script summary tab in Settings (always up-to-date)
- [ ] Better error reporting and recovery
- [ ] Improved auto-repair with context from Manus/harness research

## Phase 6 — Distribution & Community
- [ ] ES module support
- [ ] Bytecode caching
- [ ] Snippet sharing format
- [ ] Documentation site
- [ ] Homebrew cask formula
- [ ] Notarized DMG
