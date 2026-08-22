# Macotron does everything.

<p align="center">
  <img src="site/icon.png" alt="Macotron" width="128" height="128">
</p>

Tile windows, bind hotkeys, drive the menu bar, read sensors, capture the screen, talk to models. From small JavaScript files that reload when you save them.

Free and open source. Built with Swift and QuickJS.

- [Download for macOS](https://github.com/statico/macotron/releases/latest), or `brew install statico/tap/macotron`
- [Homepage](https://macotron.statico.io/)
- [Source](https://github.com/statico/macotron)

## What it is

Macotron is a native macOS host for JavaScript plugins. First launch asks for a directory. Scripts go in `plugins/`. Macotron writes an `AGENTS.md` next to them so a coding agent already knows the API. [Claude Code](https://claude.com/claude-code), [Codex](https://openai.com/codex/), [Cursor](https://cursor.com), [pi.dev](https://pi.dev), or you.

The catalog ships 73 built-in plugins. Everything hangs off `macotron.*`. Apple-shipped tools only. No Homebrew, npm, or extra binaries.

## Example

```javascript
// ~/Macotron/plugins/tile.js
macotron.keyboard.on("Tile Left", "ctrl+opt+left", () => {
  const win = macotron.window.focused();
  macotron.window.moveToFraction(win.id, {
    x: 0, y: 0, w: 0.5, h: 1,
  });
});
```

Save the file. The hotkey is live.

## Capabilities

The [homepage](https://macotron.statico.io/#can) lists the host: launcher, windows, menu bar, screen, clipboard, display, system, power, network, input, apps, audio, home, devices, files, shell, AI, and accessibility.

Types: [macotron.d.ts](Sources/Macotron/Resources/macotron.d.ts). Modules: [docs/04-modules.md](docs/04-modules.md).

## Plugins

Featured: Calculator, Clipboard History, File Search, Lock Screen, Meetings, Notes, Snippets, Weather, Window Grid, Windows.

All 73 live in [Examples/plugins](Examples/plugins/). Community plugins: [github.com/topics/macotron-plugin](https://github.com/topics/macotron-plugin).

## Building

macOS 15 Sequoia and Swift 6.2 or later. No Xcode GUI.

```bash
make build    # compile
make run      # compile, bundle, launch
make clean    # build artifacts
```

The app lands at `~/Applications/Macotron.app`.

## Permissions and signing

Hotkeys and window control need Accessibility and Input Monitoring. Screen capture needs Screen Recording. The app asks when a feature needs them.

Permissions stick to the code signature. `make run` signs ad-hoc by default, so each rebuild can reset the toggles. For a stable signature, create a local **Macotron-Dev** code-signing certificate in Keychain Access (Certificate Assistant, then Code Signing). Then:

```bash
make run   # picks Macotron-Dev if it exists
```

After the first stable-signed build, add `~/Applications/Macotron.app` under **System Settings, Privacy & Security, Accessibility** (and Input Monitoring / Screen Recording as needed).

If hotkeys die after a rebuild, remove and re-add Macotron in that list, or `tccutil reset Accessibility`.

```bash
codesign -d -vvvv ~/Applications/Macotron.app
```

Look for `Authority=Macotron-Dev`, not adhoc.

```bash
make cleanprefs   # wipe prefs, wizard on next launch
```

## Docs

- [Overview](docs/01-overview.md)
- [Project structure](docs/02-project-structure.md)
- [Engine](docs/03-engine.md)
- [Native modules](docs/04-modules.md)
- [AI](docs/05-ai-integration.md)
- [Security](docs/06-security.md)
- [Build](docs/07-build-system.md)
- [Built-in plugins](Examples/plugins/README.md)
- [Phases](docs/09-phases.md)
- [Plugins workdir](docs/10-plugins-workdir.md)

## License

Macotron is MIT licensed. See [LICENSE](LICENSE).

### Third-party code

| Component | Location | License |
|---|---|---|
| [QuickJS-ng](https://github.com/quickjs-ng/quickjs), the JavaScript engine | `Vendor/quickjs-ng/` | MIT |

QuickJS-ng is the only vendored dependency. It ships here as an amalgamated `quickjs-amalgam.c` plus headers, with the upstream copyright notices intact in the source: Fabrice Bellard, Charlie Gordon, Ben Noordhuis, Saúl Ibarra Corretgé, and Marcin Kolny. The vendored version is whatever `QJS_VERSION_*` in `Vendor/quickjs-ng/include/quickjs.h` says. `quickjs-swift-helpers.c` is Macotron's own shim, not upstream code.

Everything else is first-party Swift or an Apple-shipped framework. There are no Swift package dependencies, no npm, and no Homebrew.
