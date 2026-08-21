# Macotron host shell redesign

Date: 2026-08-17

## Goal

Macotron is a thin macOS host. External coding agents edit plugins. The app does not ship an in-app coding agent.

## Product shape

- Minimal UI: first-run wizard, settings, menu bar, launcher hotkey, plugin list.
- User picks one plugins directory (workdir for Claude Code, Codex, Cursor, or pi.dev).
- That directory is a git repo for local versioning.
- App writes and owns `AGENTS.md` and `CLAUDE.md` (do not edit; overwritten).
- App seeds a human `README.md` once if missing.
- Settings live in `settings.json` in the workdir. Hot reload on any file change.
- Permissions are requested only when a feature needs them.
- Plugins are `.js` files under `plugins/`. Each file registers hotkeys and hooks at load time.
- Plugin UI: small WKWebView panels via `macotron.panel`.
- Keep QuickJS + native modules. Keep `macotron.ai` for plugins (Claude / OpenAI / Foundation Models).
- Remove in-app AgentSession, ChatSession, tool-call agent UI, and module auto-fix.
- Marketplace: settings link to GitHub topic search `topic:macotron-plugin`. No custom store backend in v1.

## Workdir layout

```
<user-chosen>/
  .git/
  .gitignore          # ignores AGENTS.md, CLAUDE.md, .cache/
  settings.json       # launcher hotkey, UI prefs, etc.
  README.md           # human; seeded once
  AGENTS.md           # app-owned
  CLAUDE.md           # app-owned (same content or short pointer)
  plugins/
    example-hello.js
  .cache/             # bytecode; gitignored
```

## settings.json (example)

```json
{
  "launcher": { "hotkey": "cmd+space" },
  "ui": { "showDockIcon": true, "showMenuBarIcon": true },
  "modules": {},
  "security": { "shell": { "allow": [], "strict": false } }
}
```

Only the path to the workdir may live in UserDefaults (`pluginsDirectory`).

## Agent docs

Banner at top:

```
<!-- DO NOT EDIT — Macotron overwrites this file. -->
```

Content: what the directory is, plugin rules, API summary, git commit guidance (commit often on `main`, no secrets).

## Lazy permissions

- Wizard: pick directory, optional open in Finder or your editor. Do not demand Accessibility up front.
- Input Monitoring / Accessibility: prompt when keyboard module registers a global hotkey or when the launcher hotkey cannot install.
- Screen Recording: prompt when screen/window capture APIs are first used.

## Panel API (minimal)

```js
const id = macotron.panel.open({ title: "Chat", width: 420, height: 520, html: "..." });
macotron.panel.close(id);
macotron.panel.postMessage(id, data);
macotron.panel.onMessage(id, (data) => { ... });
```

## Out of scope (ponytail)

- Built-in GitHub marketplace browser beyond a search link
- Custom React-to-AppKit UI kit
- App-driven git commits (agents commit; app only `git init`)
- Full Foundation Models polish beyond exposing `macotron.ai.local()` when available
