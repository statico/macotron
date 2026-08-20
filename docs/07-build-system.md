# Build System and Development

No Xcode GUI. Everything runs from the CLI.

## Targets

| Target | Type | Purpose |
|---|---|---|
| CQuickJS | C library | quickjs-ng amalgam build |
| MacotronEngine | Library | QuickJS Engine, EventBus, plugin loader |
| MacotronUI | Library | Wizard, Settings, MenuBar, Launcher |
| Modules | Library | Native modules (window, keyboard, shell, panel, ai, ...) |
| AI | Library | Providers for `macotron.ai` (Claude, OpenAI, Gemini, Local) |
| Macotron | Executable | AppDelegate, module registration, wiring |
| MacotronTests | Tests | Engine and UI tests |

See `Package.swift` and `Makefile` in the repo for full build settings.

## Key Make Targets

- `make build` — `swift build`
- `make run` — Build, bundle into `.app`, open
- `make bundle` — Build + codesign + copy resources into `.build/Macotron.app`
- `make clean` — `swift package clean` + remove `.app` bundle
- `make cleanprefs` — Reset UserDefaults (triggers first-run wizard)

## Workdir Path

UserDefaults stores only `pluginsDirectory`. Plugin files and `settings.json` live in that directory. They do not live under `~/Library/Application Support/Macotron/`.
