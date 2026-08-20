<!-- DO NOT EDIT — Macotron overwrites this file. -->

# Macotron plugins directory

This directory is the Macotron workdir. External coding agents edit plugins here.
Macotron loads the plugins and runs them. The app does not write plugin code.

## Layout

- `plugins/*.js` — plugin scripts. Macotron loads every `.js` file in alphabetical order.
- `settings.json` — launcher hotkey, UI prefs, module options. Do not put secrets here.
- `.cache/` — bytecode cache and typecheck config. Gitignored. Do not edit.
- `AGENTS.md` / `CLAUDE.md` — owned by Macotron. Overwritten on every launch.

## API version

Current plugin API version is `1.1.0` (`macotron.version.api`).
Bump only when the plugin-facing JS contract changes.

## Built-in macOS only

Plugins must run on a stock Mac with only Macotron installed. Use `macotron.*`
APIs and Apple-shipped tools (`/usr/bin/open`, `/usr/bin/defaults`, `/bin/mv`).
Do not call Homebrew, npm, pip, ffmpeg, Chrome-only binaries, or other
third-party installs. Optional cloud AI keys are fine; they are not required
for the host or demo plugins to load.

## API compatibility pragma

Optional. Put at the top of a plugin when you need a minimum API version:

```js
// @macotron needs 1.2
// also accepted: 1.2.0
```

- Missing `needs` means `needs 1.0.0`.
- Short forms normalize (`1.2` → `1.2.0`) before compare.
- Host loads only if `host.api >= plugin.needs`.

## Validate after edits

Load-check from this workdir:

`~/Applications/Macotron.app/Contents/MacOS/Macotron --check plugins/your-file.js`

Do not edit `AGENTS.md` / `CLAUDE.md`.

## Plugins

Put one `.js` file per plugin under `plugins/`. Each file runs in its own
function scope, so `const opts` in two plugins does not collide.

Register hotkeys at load time:

```js
macotron.keyboard.on("Hello", "cmd+shift+h", () => {
  macotron.notify.toast("Hello", "From a Macotron plugin");
});
```

The id is the Settings label. Ids are unique per plugin. Users override the combo in Settings → Plugins.

`macotron.notify.toast(title, body?, { position, duration, sfSymbol, color })` is a
one-line HUD on the screen under the cursor (3s default). `color` is `info`,
`success` (green check), `error` (red x), or `warning` (orange triangle).
`macotron.notify.show` is a system banner.
`macotron.screen.pickColor()` opens the system magnifier and returns
`{ hex, r, g, b, x, y }` or `null`.

Control Center-style toggles live on the host: `macotron.audio.volume` /
`setVolume` / `setMuted`, `network.wifi` / `setWifi`, `network.bluetooth` /
`setBluetooth`, `network.airDrop` / `setAirDrop("off"|"contacts"|"everyone")`,
`system.darkMode` / `setDarkMode`, `system.focus()` (`{ focused }`, read-only).

## Launcher commands

```js
macotron.command("Generate Lorem Ipsum", "Placeholder text", (args) => {
  macotron.clipboard.set(String(args.count) + " " + args.unit);
}, {
  id: "lorem-ipsum",
  arguments: [
    { name: "count", type: "number", placeholder: "Count", default: 3 },
    { name: "unit", type: "dropdown", placeholder: "Unit", default: "paragraphs",
      choices: [
        { title: "Words", value: "words" },
        { title: "Lines", value: "lines" },
        { title: "Paragraphs", value: "paragraphs" },
      ],
    },
  ],
});
```

The three-argument form still works. `id` is optional; the default is `{filename}/{name}`.
Set `id` if the user will assign a shortcut. Users set shortcuts in Settings → Plugins
or in the launcher with ⌘K on the selected result (apps too). Do not call `keyboard.on`
for launcher commands. `keyboard.on(id, default, callback)` is for global hotkeys;
those combos are also overridable in Settings → Plugins.

## Panel API (stub)

```js
const id = macotron.panel.open({ title: "Chat", width: 420, height: 520, html: "<p>Hi</p>", glass: true });
macotron.panel.close(id);
macotron.panel.postMessage(id, { hello: true });
macotron.panel.onMessage(id, (data) => { /* ... */ });
```

`html` is inserted into a host document (system font, padding, light/dark).
`rawHtml` is a full document. `glass: true` (or `"regular"`) uses Liquid Glass
with a transparent page background; `glass: "clear"` is the clearer variant.
`frameless: true` hides the title bar; Escape closes.
Host CSS exposes `--macotron-accent` (and related `--macotron-*` system colors);
`button.primary` uses the accent color. In the page, `close()` closes the panel.
The page may also call `webkit.messageHandlers.macotron.postMessage(data)`.

## Plugin metadata and settings

Every plugin must declare a title and description so they appear in
Settings → Plugins. Put macOS permissions on the same call:

```js
const opts = macotron.plugin({
  title: "Chat",
  description: "Talk to a model",
  help: "Set an API key below for cloud models.",
  permissions: ["accessibility"],
});
```

Valid permission names: `accessibility`, `inputMonitoring`, `screenRecording`,
`fanControl`. Window control needs `accessibility`. Screen capture needs
`screenRecording`. Holding a fan-speed floor needs `fanControl`, which the
user installs as the background helper from this plugin's Settings page.

Add `options` on the same call to expose configurable settings. The user
edits values in Settings → Plugins; the plugin reads the resolved values
from the `macotron.plugin()` return value. Do not hand-edit
`pluginSettings` to configure plugins — use the Settings UI.

```js
const opts = macotron.plugin({
  title: "Chat",
  description: "Talk to a model",
  options: {
    model: {
      type: "dropdown",
      label: "Model",
      default: "sonnet",
      choices: [
        { value: "sonnet", label: "Claude Sonnet" },
        { value: "opus", label: "Claude Opus" },
      ],
    },
    apiKey: { type: "password", label: "Anthropic API key", required: true },
    openHotkey: { type: "keybinding", label: "Open chat", default: "cmd+shift+c" },
    notesFile: { type: "file", label: "Notes file" },
    workspace: { type: "directory", label: "Workspace folder" },
  },
});
// opts.apiKey === resolved secret string (or "")
```

Option types: `string`, `boolean`, `number`, `keybinding`, `dropdown`
(requires `choices: [{ value, label }]`), `password`, `file`, `directory`.
Every option takes `label`, optional `default`, and optional `required`
(Settings shows a "Needs setup" hint while a required option is unset).

`password` options: the secret lives in the macOS Keychain. `settings.json`
stores only a Keychain ref like `macotron.plugin.chat.js.apiKey`. Refs may
be committed; real secrets must never appear in JSON or plugin source.
`macotron.plugin()` returns the resolved secret string, never the ref.
`file` / `directory` store absolute path strings.

Report host problems with `macotron.checks([{ title, ok, message }])`.
Replace the list each call; `[]` clears it. A failed check (`ok: false`)
shows an orange warning on the plugin in Settings → Plugins.
`macotron.settings.open()` opens that plugin's page.

```js
macotron.checks([
  { title: "Speed control", ok: false, message: "This Mac blocked fan-speed writes." },
]);
```

## settings.json schema

```json
{
  "launcher": { "hotkey": "cmd+space" },
  "ui": {
    "showDockIcon": true,
    "showMenuBarIcon": true,
    "appearance": "system",
    "textScale": 1.0,
    "launcherBackground": "translucent"
  },
  "modules": {},
  "pluginSettings": {},
  "disabledPlugins": [],
  "commandShortcuts": {},
  "keyboardShortcuts": {},
  "launcherFavorites": [],
  "security": { "shell": { "allow": [], "strict": false } }
}
```
Disabled plugins stay on disk but are not loaded; manage them in Settings → Plugins.

## Git

Commit often on `main`. Never commit secrets (API keys, tokens, passwords).
Declare `password` options and let the user set them in Settings, or store
secrets with `macotron.keychain`. Macotron runs `git init` only when Apple
developer tools are already installed. Git is optional.

## AI from plugins

Plugins may call `macotron.ai.claude()`, `macotron.ai.anthropic()`,
`macotron.ai.gemini()`, `macotron.ai.openai()`, or `macotron.ai.local()`.
Prefer a `password` option for API keys (the user sets it in Settings);
`macotron.keychain.get("anthropic-api-key")` also works for shared keys.
`ai.chat` / `ai.stream` accept a string or `[{role, content}]`. Use `stream` with
`onChunk` for token updates. Save chat history yourself via `localStorage`.
