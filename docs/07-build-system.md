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

## Sparkle

Self-updates use [Sparkle](https://sparkle-project.org) 2.9.6, the one Swift
package dependency. It arrives as a prebuilt XCFramework, so SwiftPM only
unpacks it: `make bundle` copies `Sparkle.framework` into
`Macotron.app/Contents/Frameworks` and the executable gets an `@rpath` entry
pointing there.

Sparkle ships signed by the Sparkle project, and notarization wants our
Developer ID on every binary, so `make bundle` re-signs it. The nested helpers
(`XPCServices/*.xpc`, `Updater.app`, `Autoupdate`) are signed before the
framework that wraps them, because `codesign` seals nested code first.

`swift build` runs with `--disable-keychain`. With more than one github.com
entry in the login keychain, SwiftPM hangs forever trying to authenticate
instead of fetching Sparkle anonymously.

Update signing and the feed are in `docs/releasing.md`.

## Key Make Targets

- `make build` — `swift build`
- `make run` — Build, bundle into `.app`, open
- `make bundle` — Build + codesign + copy resources and Sparkle.framework into `.build/Macotron.app`
- `make clean` — `swift package clean` + remove `.app` bundle
- `make cleanprefs` — Reset UserDefaults (triggers first-run wizard)

## Workdir Path

UserDefaults stores only `pluginsDirectory`. Plugin files and `settings.json` live in that directory. They do not live under `~/Library/Application Support/Macotron/`.
