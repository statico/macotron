# Build System and Development

No Xcode GUI. Everything runs from the CLI.

## Targets

The targets, their dependencies, and the build settings are declared in
`Package.swift`. `Makefile` drives everything on top of them.

`make run` bundles the app and launches it. `make run/hot-reload` does the
same and turns Hot Reload on, through the `MACOTRON_HOT_RELOAD` variable.

`make run/hot-reload` is for development only. The target refuses to run when
`CONFIG` is not `debug`, and the app reads the variable inside `#if DEBUG`, so
a release binary contains no code that can act on it. See `docs/06-security.md`.

## Sparkle

Self-updates use [Sparkle](https://sparkle-project.org), the one Swift
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

## Rust

The file indexer is a Rust crate in `Indexer/`; how it is built and bundled
is in [12-file-index.md](12-file-index.md).


- `make build` — `cargo build` (indexer) + `swift build`
- `make run` — Build, bundle into `.app`, open
- `make bundle` — Build + codesign + copy resources and Sparkle.framework into `~/Applications/Macotron.app`
- `make clean` — `swift package clean` + `cargo clean` + remove `.app` bundle
- `make cleanprefs` — Reset UserDefaults (triggers first-run wizard)

## Workdir Path

UserDefaults stores only `pluginsDirectory`. Plugin files and `settings.json` live in that directory. They do not live under `~/Library/Application Support/Macotron/`.
