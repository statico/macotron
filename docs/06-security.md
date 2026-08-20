# Permissions and Security

## Required Permissions

The first-run wizard does not demand permissions up front. The required set is the baseline plus whatever the loaded plugins declare.

| Permission | Source | Why |
|---|---|---|
| **Input Monitoring** | Baseline | Snippet expansion, window snap, and event taps |
| **Accessibility** | Baseline | Move and focus windows |
| **Screen Recording** | Declared by a plugin | Capture the screen |

A plugin declares what it needs in `macotron.plugin()`:

```js
macotron.plugin({
  title: "OCR",
  description: "Select a screen area and copy the text.",
  permissions: ["accessibility", "screenRecording"],
});
```

## Permission Alerts

When a required permission is missing, Macotron shows two alerts:

- A red dot on the menu bar icon, and a red row in the menu that names each missing permission.
- A permissions tab in Settings. Each row has a **Grant** button. The tab is orange when anything still needs approval.

The app re-checks on launch, after every plugin reload, when it becomes active, and every 3 seconds while anything is missing.

The first check calls the system request API for each missing permission. That call registers Macotron in the matching System Settings list. The app does not open System Settings by itself. The user opens it from a button.

**Not sandboxed.** Distribution is a direct `.dmg` download (notarized). A Homebrew cask is optional and is not required to run Macotron.

## Secrets

Store secrets in the macOS Keychain through `macotron.keychain`. Do not put API keys in plugin source, `settings.json`, or git history.

## Gitignore for App-Owned Docs

The workdir `.gitignore` must ignore app-owned agent files and cache:

```
AGENTS.md
CLAUDE.md
.cache/
```

Those agent files must not be edited. The app overwrites them on launch and on workdir refresh.

```
<!-- DO NOT EDIT — Macotron overwrites this file. -->
```

## Capability Tiers

Every native API is classified:

```swift
enum CapabilityTier {
    case safe       // read-only, no side effects
    case moderate   // visible effects but reversible
    case dangerous  // can affect system, network, or filesystem
}
```

### Safe (read-only)

`window.getAll`, `window.focused`, `clipboard.text`, `system.cpuTemp`, `system.memory`, `system.battery`, `system.darkMode`, `system.focus`, `app.list`, `spotlight.search`, `display.list`, `keychain.get`, `keychain.has`, `media.nowPlaying`, `notes.list`, `keyboard.flags`, `mouse.location`, `mouse.buttons`, `audio.devices`, `audio.input`, `audio.output`, `audio.volume`, `audio.isMuted`, `network.wifi`, `network.wifiSSID`, `network.bluetooth`, `network.airDrop`, `network.interfaces`, `spaces.list`, `spaces.current`, `usb.list`, `shortcuts.list`

### Moderate (reversible side effects)

`window.move`, `window.moveToFraction`, `window.focus`, `window.minimize`, `window.close`, `window.setFullscreen`, `window.snap`, `window.setSnapEnabled`, `notify.show`, `notify.toast`, `menubar.*`, `keyboard.on`, `clipboard.set`, `app.launch`, `app.switch`, `app.hide`, `app.quit`, `app.menu`, `audio.setInput`, `audio.setOutput`, `audio.setVolume`, `audio.setMuted`, `network.setWifi`, `network.setBluetooth`, `network.setAirDrop`, `spaces.go`, `spaces.moveWindow`, `shortcuts.run`, `panel.open`, `panel.close`, `screen.pickColor`, `media.playPause`, `media.next`, `media.previous`, `launcher.set`, `notes.open`, `display.setGamma`, `display.restoreGamma`, `event.post`, `event.tap`, `mouse.warp`, `system.setLowPowerMode`, `system.setDarkMode`

### Dangerous (system / network / filesystem)

`shell.run`, `fs.write`, `fs.rename`, `http.post`, `http.put`, `http.delete`, `url.open`, `url.registerHandler`, `keychain.set`, `keychain.delete`, `screen.capture`, `power.lock`, `power.sleep`

## Shell Command Approval

First call to shell run with an unapproved command prompts:

- **Allow Once** — run this time only
- **Always Allow** — add to the allowlist in `settings.json`
- **Deny** — block

Shell allowlist settings live under `security.shell` in `settings.json`.

## Version Control

The workdir is a git repo. External agents commit changes. The app runs `git init` only. The app does not create commits.

Commit often on `main`. Do not commit secrets.

## Mitigations Summary

| Attack Surface | Mitigation |
|---|---|
| Plugin runs dangerous APIs | Capability tiers plus user prompts for shell |
| Shell commands | Shell allowlist plus per-command approval |
| Secrets in repo | Keychain storage. Gitignore guidance in agent docs |
| App-owned agent files edited by users | Banner plus overwrite. Files stay gitignored |
| Third-party plugins | Same access as local plugins. Review before install |
| Screen or clipboard sent to models | Structured delimiters plus ignore-instructions framing |
