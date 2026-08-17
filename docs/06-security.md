# Permissions and Security

## Lazy Permissions

The first-run wizard does not demand Accessibility up front. The app prompts only when a feature needs the permission.

| Permission | When the app prompts |
|---|---|
| **Accessibility** | When the keyboard module registers a global hotkey, or when the launcher hotkey cannot install |
| **Input Monitoring** | Same path as Accessibility for global event taps |
| **Screen Recording** | When screen or window capture APIs run for the first time |
| **Automation** | Per-app prompts as needed |

**Not sandboxed.** Distribution uses a direct `.dmg` download (notarized) plus `brew install --cask macotron`.

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

`window.getAll`, `window.focused`, `clipboard.text`, `system.cpuTemp`, `system.memory`, `system.battery`, `camera.isActive`, `app.list`, `spotlight.search`, `display.list`, `keychain.get`, `keychain.has`

### Moderate (reversible side effects)

`window.move`, `window.moveToFraction`, `notify.show`, `menubar.*`, `keyboard.on`, `clipboard.set`, `app.launch`, `app.switch`, `panel.open`, `panel.close`

### Dangerous (system / network / filesystem)

`shell.run`, `fs.write`, `fs.delete`, `http.post`, `http.put`, `http.delete`, `url.open`, `url.registerHandler`, `keychain.set`, `keychain.delete`, `screen.capture`

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
