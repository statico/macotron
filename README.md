<p align="center">
  <img src="site/icon.png" alt="Macotron" width="128" height="128">
</p>

<h1 align="center">Macotron</h1>
<p align="center"><b>It does everything.</b><br>Customization and automation with a quick launch bar, global hotkeys, menu bar items, and APIs for everything you can think of. Open-source and free.</p>

<p align="center">
  <a href="#install">Install</a> ·
  <a href="#quickstart">Quickstart</a> ·
  <a href="#what-it-does">What it Does</a> ·
  <a href="#the-api">API</a> ·
  <a href="#plugins">Plugins</a> ·
  <a href="#security">Security</a> ·
  <a href="https://macotron.statico.io">Home Page</a>
</p>

> [!NOTE]
> **Macotron is in beta.** It hits 1.0 when I decide it's stable, and not before. Until then, expect things to move around.

---

## Install

Pick one:

- [Download for macOS](https://github.com/statico/macotron/releases/latest)
- `brew install statico/tap/macotron`

Either way, Macotron updates itself after that. It checks daily and asks before installing anything; **Check for Updates...** in the menu checks right now, and Settings > General turns the automatic check off.

Macotron runs on macOS 15 Sequoia and later. A few things need macOS 26 Tahoe: the Apple Intelligence chat and plugin scanner (Foundation Models), and the Liquid Glass chrome.

## Quickstart

1. Download, install, and open Macotron
1. Pick a directory to store your settings and plugins
1. Add any example plugins that look interesting
1. Approve any permissions requests
1. Hit ⌥-Space (the default) and explore the quick search items
1. Explore the new menu bar items
1. Explore the Macotron settings
1. Open the plugins directory with your favorite AI coding agent and have fun!

## What it Does

The 74 built-in plugins do things like:

- Extend quick search with files, contacts, or Apple Notes
- Toggle extra-dark or red night vision mode
- Put CPU, GPU, and memory meters in the menu bar
- Show upcoming meetings and alert you when they start
- Organize windows by halves, thirds, or by snapping edges & corners
- Hold Option and press Tab to flip through windows
- Clipboard history, text snippets, and text replacement
- Open certain URLs in certain browsers
- Control your fan speed
- Convert HEIC images to JPEGs in `~/Downloads`
- Toggle mic mute or cycle through audio output devices
- Show the now-playing music information with album art
- Start a chat window with Apple Intelligence, Claude, or Gemini
- Select a region on the screen and OCR it
- Scan a QR code off the screen, or show one
- Show Time Machine backup progress
- Browse Apple TVs on your network

...but that's not all. Check [the home page](https://macotron.statico.io) for a longer list of examples.

## The API

Everything hangs off a `macotron` global. Plugins are plain JavaScript on QuickJS, so there is no `npm`, no bundler, and no build step. The plugin-facing API is versioned: `macotron.version` is `{ app, api, modules }`, and `api` is currently `1.5.0`.

| Namespace | What it covers |
|---|---|
| `window` | List, focus, move, tile, fullscreen, drag-to-edge snap, `flash()`, restore layouts |
| `display` | Frames and scale, brightness, XDR, gamma LUT, CRT overlay, Night Shift, True Tone, grayscale |
| `spaces` | Mission Control desktops; move a window when SIP allows |
| `keyboard` | Global hotkeys overridable in Settings, modifier flags, hyper key |
| `event` / `mouse` | Post clicks, keys, unicode, scroll; tap HID and swallow events; cursor warp |
| `app` | Launch, switch, hide, quit, drive menus; activated/launched/terminated events |
| `launcher` | Inject rows into the quick launcher, or answer the typed query |
| `menubar` | Menu rows and status items: SF Symbols, images, two-line text, sparklines, SVG |
| `notify` | System banners and HUD toasts |
| `panel` | WKWebView windows for custom UI; Liquid Glass, frameless, `postMessage` |
| `alert` / `confirm` / `prompt` | Blocking sheets, on `macotron` and as bare globals |
| `system` | CPU, GPU, memory pressure, processes, battery, fans, Low Power Mode, `timeIn()` for any IANA zone (there is no `Intl`), dark mode, Focus |
| `power` | Prevent sleep, lock, sleep, screensaver, log out, restart, shut down |
| `idle` | Seconds idle, thresholds, `system:idle` / `system:active` |
| `network` | Wi-Fi, Bluetooth and device batteries, AirDrop, interfaces, counters, ping |
| `http` | `get`, `post`, `put`, `delete` |
| `bonjour` / `udp` | Browse mDNS services; send and listen on IPv4 |
| `appletv` | Discover Apple TVs; `send()` awaits Companion pairing, so keys report "not paired" |
| `usb` / `hid` | Enumerate devices; open a HID device, read and write reports |
| `fs` | `read`, `readBytes`, `write`, `exists`, `list`, `watch`, `rename` |
| `files` | Millisecond name search over an in-memory file index you point at folders |
| `spotlight` | Filename search via `mdfind`, filtered by folder and kind |
| `shell` | Run a command through `/bin/zsh` |
| `clipboard` | Text, images, UTIs, history, plain paste |
| `snippets` | Abbreviations and as-you-type expansion |
| `screen` / `ocr` / `qr` | Capture a display or region, `pickColor()` eyedropper, recognize text, scan and generate QR codes |
| `camera` / `share` | List cameras, preview, snapshot; share sheet and AirDrop |
| `audio` / `media` | Devices, volume, mute, record; Now Playing and transport controls |
| `calendar` / `reminders` | Upcoming events; list, add, and complete reminders |
| `notes` / `contacts` | List and open Apple Notes; search contacts |
| `homekit` / `dock` | HomeKit is a stub on native macOS (no public framework); Dock tile badges |
| `shortcuts` / `url` | Run Shortcuts.app; route schemes and hosts, `setDefaultHandler`, `onFallback` |
| `ax` | Focused element, selected text, tree walk, press, `setValue` |
| `ai` | Apple Intelligence on-device, Claude, Gemini, OpenAI; chat and streaming |
| `keychain` | `get`, `set`, `delete`, `has` for secrets that never touch `settings.json` |

Plus, directly on `macotron`: `plugin()` for metadata, permissions, and typed Settings options; `command()` for launcher commands with text, number, and dropdown arguments; `on()` / `off()` for host events; `every()` and `at()` for interval and wall-clock jobs; `checks()` for status rows in Settings; `settings.open()`; `config()` for the host module config; and `log()` and `sleep()`. `localStorage` and `console` are globals.

Read [the full API reference](https://github.com/statico/macotron/blob/main/Sources/Macotron/Resources/macotron.d.ts) for exact signatures, or [browse the built-in plugins](https://github.com/statico/macotron/blob/main/Examples/plugins/README.md). Or just, y'know, let your agent do that for you or whatever.

## Plugins

Each bit of Macotron functionality is contained in a **plugin**: a JavaScript file that defines metadata, permissions required, settings that the user can override, and all of the hooks and logic needed for it to run. One file is the usual shape, but a plugin can `import` sibling files as ES modules, and those imports are hash-approved too.

**The intention is to let AI coding agents make plugins for you.** The plugins directory will contain an `AGENTS.md` with all of the information your agent needs.

**Plugins must be reloaded once changed,** at least by default. When developing plugins, you can choose **Enable Hot Reloading** in the Macotron menu to automatically reload them without confirmation.

### Example Plugin

```javascript
macotron.plugin({
  title: "Move Windows",
  description: "Tile windows using hotkeys",
  permissions: ["accessibility"],
});

macotron.keyboard.on("Tile Left", "ctrl+opt+left", () => {
  const win = macotron.window.focused();
  macotron.window.moveToFraction(win.id, {
    x: 0, y: 0, w: 0.5, h: 1,
  });
});

// ...
```

If you have Hot Reloading turned on, changing the plugin source will take effect instantly.

### Sharing Plugins

**Settings → Plugins → Catalog → Community** lists every GitHub repo tagged [`macotron-plugin`](https://github.com/topics/macotron-plugin). To get yours in there:

1. Name the repo `macotron-plugin-<name>`. One plugin per repo, with the script in the root — `<name>.js` is the tidiest choice, and `plugin.js` or `index.js` also work.
2. Add the `macotron-plugin` topic.

That's the whole process. There's no index to update, no PR to file, and no review queue to wait on. [macotron-plugin-cleanshot](https://github.com/statico/macotron-plugin-cleanshot) is a working example.

Nothing installs or updates itself. Macotron downloads the source, scans it, shows you who wrote it, and waits for you to say yes.

## Security

Hotkeys and window control need Accessibility and Input Monitoring. Screen capture needs Screen Recording. Fan control needs a system helper app installed. It's a little scary, but Macotron tries to only ask for additional permissions when an enabled plugin needs them.

By default, plugins are not reloaded if the source changes. Every plugin file is tracked in a hash ledger, and a file whose bytes changed has to be approved again before it runs. That is what stops another program from quietly editing a plugin to run its own code. You can turn on Hot Reloading in the menu bar to skip that while developing.

Plugin source that came from outside the signed app bundle gets scanned before you approve it. On macOS 26 the scan makes three on-device Apple Intelligence passes, and static checks flag `eval()`, keychain-plus-HTTP, `curl`/`wget` shells, and prompt-injection comments either way. `make scan` sweeps the built-in plugins. A published blocklist of SHA-256 hashes is checked before the ledger and cached on disk, so an offline Mac still refuses known-bad code.

**`macotron.shell.run` is not gated.** It runs what it is given through `/bin/zsh`, with no allowlist and no per-command prompt. The decision to enable a plugin *is* the decision to let it run shell commands — treat it as equivalent to running them yourself. See [docs/06-security.md](docs/06-security.md).

Plugins can define secrets that are stored in the Keychain instead of on disk.

Updates are signed. Macotron only installs one that verifies against the key inside the copy you already have, so a hijacked download can't replace it.

## Contributing

Due to the hopelessness of reviewing code contributions in the AI era, pull requests have been disabled. Instead, file an issue to report a bug or request a feature.

The intent behind built-in plugins isn't to offer every plugin imaginable, but rather a set just big enough to show off Macotron's capabilities and provide great default behavior.

### Building

You'll need macOS 15 Sequoia or later, Swift 6.0 or later, and a Rust toolchain — the file indexer is a small Rust binary that ships inside the app bundle. No Xcode GUI is required.

```bash
make          # list every target
make build    # compile the Rust indexer and the Swift binaries
make bundle   # build, then assemble ~/Applications/Macotron.app
make run      # bundle and launch (kills the running instance first)
make check    # typecheck-load plugins (ARGS='plugins/foo.js' optional)
make trace    # stream the app log to the terminal and tmp/log
make scan     # sweep the built-in plugins, and a malware corpus, with the scanner
make clean    # remove build artifacts *and* ~/Applications/Macotron.app
```

`make build` alone does not produce an app — `make bundle` is what creates, signs, and populates the bundle. Note that `make clean` deletes your installed copy along with the build directory.

For more information, refer to the plans and documentation in `docs/`.

## License

Macotron is MIT licensed. See [LICENSE](LICENSE).

### Third-party code

| Component | Location | License |
|---|---|---|
| [QuickJS-ng](https://github.com/quickjs-ng/quickjs), the JavaScript engine | `Vendor/quickjs-ng/` | MIT |
| [Sparkle](https://sparkle-project.org), the self-update framework | Swift package, embedded in the app bundle | MIT |
| The file indexer's Rust crates | `Indexer/Cargo.toml` | MIT / Apache-2.0 |

QuickJS-ng is the only vendored dependency. It ships here as an amalgamated `quickjs-amalgam.c` plus headers, with the upstream copyright notices intact in the source: Fabrice Bellard, Charlie Gordon, Ben Noordhuis, Saúl Ibarra Corretgé, and Marcin Kolny. The vendored version is whatever `QJS_VERSION_*` in `Vendor/quickjs-ng/include/quickjs.h` says. `quickjs-swift-helpers.c` is Macotron's own shim, not upstream code.

Sparkle is the only Swift package dependency. The `macotron-index` binary is built from `Indexer/` and pulls a handful of crates from crates.io (`serde`, `serde_json`, `ignore`, `notify`, `libc`, `memchr`, `unicode-normalization`). Everything else is first-party Swift or an Apple-shipped framework. Nothing at runtime needs Homebrew or npm: plugins use `macotron.*` and Apple-shipped tools only.

### AI Disclaimer

Macotron was developed with various AI coding agents and models, partially as a research project for me to test various models. I haven't looked at much of the code in detail, but I've had many models perform many reviews, and the codebase feels decent enough. I've put significant effort into making the API concise, the UX decent, and performance reasonable.
