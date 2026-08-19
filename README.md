# ⚠️ VERY INCOMPLETE — STILL A WORK IN PROGRESS

<p align="center">
  <img src="Resources/banner.png" alt="Macotron" width="600">
</p>

Macotron is a modern Hammerspoon: a thin native macOS host for JavaScript automation plugins. External coding agents edit the plugins. The app does not ship an in-app AI coding agent.

You pick one plugins directory. Cursor, Claude Code, or another agent writes `.js` files there. Macotron loads those files in a QuickJS engine and bridges them to native macOS APIs.

## How It Works

1. Pick a plugins directory (workdir) in the first-run wizard.
2. Open that directory in Cursor or Claude Code.
3. Ask the agent to add or change plugins under `plugins/`.
4. Macotron hot-reloads when files change.

```
External agent (Cursor / Claude Code)
  |
  v
plugins/*.js  (git repo workdir)
  |
  v
Macotron.app  (QuickJS + native modules)
  |
  v
macOS (windows, hotkeys, notifications, ...)
```

## Architecture

```
+----------------------------------------------------------+
|                      Macotron.app                         |
|                                                          |
|  First-run wizard | Settings | Menu bar | Launcher       |
|                                                          |
|  +----------------------------------------------------+  |
|  |              MacotronEngine                         |  |
|  |  QuickJS  |  EventBus  |  Plugin loader / watcher   |  |
|  |                                                     |  |
|  |  Native modules: window, keyboard, screen, shell,    |  |
|  |  notify, camera, fs, clipboard, app, system, http,  |  |
|  |  menubar, display, timer, usb, url, spotlight,      |  |
|  |  keychain, localStorage, ai, panel                  |  |
|  +----------------------------------------------------+  |
+----------------------------------------------------------+
```

Plugins call `macotron.ai` for Claude, OpenAI, Gemini, or on-device Foundation Models. The host does not run an agent loop of its own.

## Plugins Directory

The workdir is a git repo that the app initializes. Layout:

```
<user-chosen>/
  settings.json
  README.md          # human (seeded once)
  AGENTS.md          # app-owned — do not edit
  CLAUDE.md          # app-owned — do not edit
  plugins/
    example-hello.js
  .cache/            # bytecode (gitignored)
```

See [docs/10-plugins-workdir.md](docs/10-plugins-workdir.md) for the full layout.

## Built-in macOS only

Installing Macotron.app on a new Mac is enough. The host and demo plugins use Apple frameworks and Apple-shipped CLI tools (`/usr/bin/open`, `/usr/bin/defaults`, `/bin/mv`, `/bin/ps`). They do not need Homebrew, npm, Chrome, or other extra installs. Optional: cloud AI API keys, and git if you want the plugins folder as a repo (the app skips `git init` when developer tools are missing).

## Marketplace

Browse community plugins on GitHub:

https://github.com/topics/macotron-plugin

v1 does not ship a custom store backend. Settings link to that topic search.

## Building

Requires **macOS 15 Sequoia** and **Swift 6.0+**. No Xcode GUI needed.

```bash
make build    # compile
make run      # compile + bundle + launch
make dev      # compile + bundle + run with debug server on :7777
make clean    # clean build artifacts
```

## Code Signing and Permissions

Macotron uses CGEvent taps and Accessibility APIs that need macOS permissions. Permissions attach to the app code signature.

### Ad-hoc signing (default)

By default, `make run` signs the app ad-hoc (`codesign --sign -`). Each rebuild gets a new cdhash. macOS can reset permissions after every rebuild.

### Stable signing with a self-signed certificate

Create a local code-signing certificate so permissions persist across rebuilds:

```bash
openssl req -x509 -newkey rsa:2048 -keyout /tmp/mc.key -out /tmp/mc.crt \
  -days 3650 -nodes -subj "/CN=Macotron-Dev" \
  -addext "extendedKeyUsage=codeSigning" && \
openssl pkcs12 -export -out /tmp/mc.p12 -inkey /tmp/mc.key -in /tmp/mc.crt \
  -passout pass:temp -legacy && \
security import /tmp/mc.p12 -k ~/Library/Keychains/login.keychain-db \
  -P temp -T /usr/bin/codesign && \
rm /tmp/mc.key /tmp/mc.crt /tmp/mc.p12
```

Then build with the certificate:

```bash
make run SIGN_IDENTITY=Macotron-Dev

# Or export it once:
export SIGN_IDENTITY=Macotron-Dev
make run
```

### Granting permissions

The app requests Accessibility, Input Monitoring, and Screen Recording only when a feature needs them. After the first build with a stable certificate:

1. Open **System Settings → Privacy & Security → Accessibility**.
2. Click **+** and add `~/Applications/Macotron.app`.
3. Enable the toggle.

If hotkeys stop after a rebuild, remove and re-add Macotron in the Accessibility list, or reset Accessibility entries:

```bash
tccutil reset Accessibility
```

### Verifying the signature

```bash
codesign -d -vvvv ~/Applications/Macotron.app
# Look for: Authority=Macotron-Dev (not "adhoc" or "unknown certificate")
```

## Development

### Reset to First-Run State

```bash
make cleanprefs   # wipes UserDefaults, triggers wizard on next launch
```

### Debug HTTP Server

Run with `make dev` to start the debug server on port 7777:

| Endpoint | Method | Description |
|---|---|---|
| `/screenshot` | GET | PNG of launcher panel |
| `/snapshot` | GET | Accessibility tree as JSON |
| `/eval` | POST | Evaluate JS in engine |
| `/reload` | POST | Trigger plugin reload |
| `/snippets` | GET | List loaded plugins |
| `/open` | POST | Toggle launcher panel |

## Tech Stack

| Component | Technology |
|---|---|
| Language | Swift 6.0 (strict concurrency) |
| UI | SwiftUI + NSPanel |
| JS Runtime | [quickjs-ng](https://github.com/quickjs-ng/quickjs) (embedded, ~400KB) |
| Plugin AI | `macotron.ai` (Claude, OpenAI, Gemini, Foundation Models) |
| Package Manager | Swift Package Manager |
| Distribution | Direct download (Homebrew cask is optional; the app does not need brew) |

## Documentation

See the `docs/` directory:

- [01 - Overview](docs/01-overview.md)
- [02 - Project Structure](docs/02-project-structure.md)
- [03 - Engine Design](docs/03-engine.md)
- [04 - Native Modules](docs/04-modules.md)
- [05 - AI Integration](docs/05-ai-integration.md)
- [06 - Security](docs/06-security.md)
- [07 - Build System](docs/07-build-system.md)
- [Examples](Examples/plugins/README.md)
- [09 - Phases](docs/09-phases.md)
- [10 - Plugins Workdir](docs/10-plugins-workdir.md)

Design source of truth: [docs/superpowers/specs/2026-08-17-host-shell-design.md](docs/superpowers/specs/2026-08-17-host-shell-design.md)
