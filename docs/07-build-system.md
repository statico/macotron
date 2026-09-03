# Build System and Development

No Xcode GUI. Everything runs from the CLI.

## Targets

The targets, their dependencies, and the build settings are declared in
`Package.swift`. `Makefile` drives everything on top of them.

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

The file indexer (`docs/12-file-index.md`) is a Rust crate in `Indexer/`.
`make build` runs `cargo build --release --manifest-path Indexer/Cargo.toml`
before `swift build`, and fails with a pointer to https://rustup.rs when
`cargo` is missing. `make bundle` copies `Indexer/target/release/macotron-index`
into `Macotron.app/Contents/MacOS` and signs it like `MacotronHelper`, before
the outer bundle is sealed. `make clean` runs `cargo clean` too.

Rust is a build-time dependency only. The GitHub `macos-26` runner image
ships rustup and a stable toolchain, so `.github/workflows/release.yml`
needs no extra step.


- `make build` — `cargo build` (indexer) + `swift build`
- `make run` — Build, bundle into `.app`, open
- `make bundle` — Build + codesign + copy resources and Sparkle.framework into `~/Applications/Macotron.app`
- `make clean` — `swift package clean` + `cargo clean` + remove `.app` bundle
- `make cleanprefs` — Reset UserDefaults (triggers first-run wizard)

## Workdir Path

UserDefaults stores only `pluginsDirectory`. Plugin files and `settings.json` live in that directory. They do not live under `~/Library/Application Support/Macotron/`.
