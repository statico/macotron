# Build System & Development

No Xcode GUI. Everything from the CLI.

## Targets

| Target | Type | Purpose |
|---|---|---|
| CQuickJS | C library | quickjs-ng amalgam build |
| MacotronEngine | Library | QuickJS Engine, EventBus, SnippetManager, CapabilityReview |
| MacotronUI | Library | LauncherPanel, SettingsWindow, WizardWindow, AgentProgressPanel |
| Modules | Library | Native modules (window, keyboard, shell, etc.) |
| AI | Library | ClaudeProvider, AgentSession, SnippetAutoFix, tool definitions |
| Macotron | Executable | AppDelegate, module registration, wiring |
| MacotronTests | Tests | Engine and UI tests |

See `Package.swift` and `Makefile` in the repo for full build configuration.

## Key Make Targets

- `make build` — `swift build`
- `make run` — Build, bundle into `.app`, open
- `make dev` — Build, bundle, run with `--debug-server`
- `make bundle` — Build + codesign + copy resources into `.build/Macotron.app`
- `make clean` — `swift package clean` + remove `.app` bundle
- `make cleanprefs` — Reset UserDefaults (triggers first-run wizard)

## Debug HTTP Server

Embedded HTTP server (debug builds only) on port 7777:

| Endpoint | Method | Description |
|---|---|---|
| `/screenshot` | GET | PNG of launcher panel |
| `/snapshot` | GET | Accessibility tree as JSON |
| `/eval` | POST | Evaluate JS in engine |
| `/menubar` | GET | Current menubar items |
| `/reload` | POST | Trigger snippet reload |
| `/snippets` | GET | List loaded snippets |
| `/open` | POST | Toggle launcher panel |
