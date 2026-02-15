# Phase Plan

## Phase 1 — Engine + Menubar
- Swift package structure with vendored quickjs-ng
- QuickJS engine: runtime, context, timers, job queue draining
- EventBus (native events → JS callbacks)
- NativeModule protocol with `version`, `defaultOptions`, `options`
- Module versioning exposed to JS
- Menubar agent with NSStatusItem + dynamic NSMenu
- Ordered snippet loading from `~/.macotron/snippets/`
- Snippet error isolation
- Full reload on file change (FSEvents watcher)
- Config backup before every change
- localStorage (JSON-backed key-value)
- Keychain module (Security.framework)
- `console.log` → log file
- Basic modules: shell, notify, fs, timer, menubar
- Shell command allowlist
- Debug HTTP server

## Phase 2 — Launcher + Search + Key Modules
- NSPanel floating window with SwiftUI
- Global hotkey to toggle
- Search field with fuzzy matching
- Natural language detection
- Spotlight file search
- Command registration from `commands/`
- Window module (AXUIElement)
- Keyboard module (CGEventTap)
- Clipboard module
- Permission onboarding flow

## Phase 3 — AI Integration
- AI provider abstraction + Claude/OpenAI/Gemini/Local providers
- Tool-call-based file management
- Capability tier system
- Snippet capability review
- Chat mode in launcher
- Prompt injection mitigation
- AI system prompt with type definitions
- Snippet auto-fix with security constraints

## Phase 4 — More Modules
- Screen module (ScreenCaptureKit)
- App, System, HTTP modules
- Camera module (polling)
- USB module (IOKit)
- URL module (URL scheme handler)
- Display module

## Phase 5 — Polish & Community
- ES module support
- Bytecode caching
- Snippet sharing format
- Documentation site
- Homebrew cask formula
- Notarized DMG
