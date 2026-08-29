<!-- DO NOT EDIT — Macotron overwrites this file. -->

# Macotron plugins directory

This directory is the Macotron workdir. External coding agents edit plugins here.
Macotron loads the plugins and runs them. The app does not write plugin code.

## Layout

- `plugins/*.js` — plugin scripts. Macotron loads every `.js` file in alphabetical order.
- `settings.json` — launcher hotkey, UI prefs, plugin options. Do not put secrets here.
- `.cache/` — bytecode cache and typecheck config. Gitignored. Do not edit.
- `AGENTS.md` / `CLAUDE.md` — owned by Macotron. Overwritten on every launch.

## Example plugins

Browse the built-in examples at
https://github.com/statico/macotron/tree/main/Examples/plugins
or inside the installed app at
`/Applications/Macotron.app/Contents/Resources/Catalog/`
(or `~/Applications/Macotron.app/…` after `make bundle`).

## API version

Current plugin API version is `1.1.0` (`macotron.version.api`).
Bump only when the plugin-facing JS contract changes.

## Built-in macOS only

Plugins must run on a stock Mac with only Macotron installed. Use `macotron.*`
APIs and Apple-shipped tools (`/usr/bin/open`, `/usr/bin/defaults`, `/bin/mv`).
Do not call Homebrew, npm, pip, ffmpeg, Chrome-only binaries, or other
third-party installs. Optional cloud AI keys are fine; they are not required
for the host or built-in plugins to load.

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

## Logging

Log as you write. A plugin runs with no console attached, so the log is
the only record of what it did. Log the load, the start and result of each
command or hotkey, and every caught error — with the values that decided
the outcome, not just "failed".

```js
console.log("weather: loaded, city =", opts.city);
try {
  const res = await macotron.http.get(url);
  console.log("weather: got", res.status, "for", url);
} catch (e) {
  console.error("weather: request failed for", url, e);
}
```

Log every periodic refresh too. One that fails partway leaves stale UI
that still looks live — the menu bar shows a number, and nothing says it
is an hour old.

`console.log` / `info` / `debug` write at info level, `console.warn` at
notice, `console.error` at error. `macotron.log(...)` is the same as
`console.log`. Every line is tagged with the plugin filename, so prefix
messages with what they are about rather than the file. Do not log secrets:
API keys, tokens, clipboard contents, or the text of what the user typed.

## Debugging

Read the log. Macotron logs under subsystem `io.statico.macotron`, and
plugin output under category `plugin`.

Follow it live while you reproduce the problem:

```sh
log stream --level info --style compact   --predicate 'subsystem == "io.statico.macotron" AND category == "plugin"'
```

Look at what already happened (drop the category to see the host too):

```sh
log show --info --last 10m --style compact   --predicate 'subsystem == "io.statico.macotron"'
```

`--level info` and `--info` are required, or the plain `console.log` lines
are dropped and only warnings and errors show.

If a plugin logs nothing at all it never ran. The usual causes:

- It is new or the file changed, so it is parked until you approve it in
  Settings → Plugins. Macotron posts a notification when a new plugin lands.
- It is switched off in Settings → Plugins.
- It failed to load. Run `--check` (above) to see the error.

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
`macotron.hid.list/open/sendFeature/sendOutput/readFeature/readInput/listen`
talks to HID devices (report id is the first send byte). Both an
`hid:input` event and `readInput` give `{ id, reportId, data }`.
- `await readInput(id, { timeout: 500 })` for request/response: reports
  queue from the moment `open` returns, so a fast reply is not lost.
  Resolves `null` on timeout.
- `listen(id)` plus the `hid:input` event for a device that reports on its
  own (a button, a dial). While listening, reports arrive as events
  instead of queueing.
- `readFeature` / `readInputReport` are control GetReports; most devices
  never answer the input one.
`macotron.qr.detect({ image|path })`, `qr.scan({ camera|screenshot })`,
`qr.image(text)`, and `qr.show(text)` read and display QR codes.

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

The three-argument form still works. `id` is optional (default `{filename}/{name}`);
set it if the user will assign a shortcut, in Settings → Plugins or in the launcher
with ⌘K on the selected result (apps too). Do not call `keyboard.on` for launcher
commands — that is for global hotkeys, overridable in the same place.

## Panel API (stub)

```js
const id = macotron.panel.open({ title: "Chat", width: 420, height: 520, html: "<p>Hi</p>", glass: true });
macotron.panel.close(id);
macotron.panel.postMessage(id, { hello: true });
macotron.panel.onMessage(id, (data) => { /* ... */ });
```

`html` is inserted into a host document (system font, padding, light/dark).
`rawHtml` is a full document. `glass: true` (or `"regular"`) uses Liquid Glass
with a transparent page background; `glass: "clear"` is the clearer variant;
`glass: "translucent"` is a HUD blur. `closeOnBlur: true` closes on unfocus.
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
`camera`, `helper`. Window control needs `accessibility`. Screen capture needs
`screenRecording`. QR camera scan needs `camera`. Privileged work such as holding
a fan-speed floor needs `helper`, which the user installs as the background helper
from this plugin's Settings page.

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
    locale: { type: "string", label: "Locale", placeholder: macotron.system.locale().language },
  },
});
// opts.apiKey === resolved secret string (or "")
```

Option types: `string`, `text`, `boolean`, `number`, `keybinding`, `dropdown`
(requires `choices: [{ value, label }]`), `password`, `file`, `directory`.

Every option takes `label`, and optional `default`, `required` (Settings
shows a "Needs setup" hint until it is set), and `help`, a sentence under
the field. Keep `label` to a few words; put the explanation in `help`.

Text, number, password, file, and directory options accept `placeholder`,
the grey hint shown while the field is empty. It is read at load, so it
can show live state such as the current locale — use it instead of
writing the fallback into the label.

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

## Remembering state

Plugin variables do not survive: editing any plugin reloads all of them,
and quitting clears the lot. Every choice the user made -- a mode, a
deadline, a list they built up -- belongs in `localStorage`: write it when
it changes, read it back at load. Do not copy in what is already saved
elsewhere: options declared in `macotron.plugin()`, or state the system
can be asked for (volume, battery, current network).

```js
const KEY = "pomodoro.session"; // one store for all plugins: prefix keys

let until = JSON.parse(localStorage.getItem(KEY) || "null");

function start(ms) {
  until = Date.now() + ms;
  localStorage.setItem(KEY, JSON.stringify(until));
}
```

Host state a plugin was holding is dropped on reload too -- a sleep
assertion, a fan-speed floor -- so claim it back at load from what was
saved, and quietly: the notification was read the first time.

## Async and error handling

A `macotron.every` or `macotron.at` callback, and the initial call at the
bottom of the file, run unattended -- nobody sees the return value. If the
body throws, that tick stops there and the menu bar or panel keeps what
was last painted, usually the first run's placeholder, which then sits
there looking like a real reading. Wrap the body and paint a terminal
state on every path, failure included.

`macotron.http` does not reject on a dead network: it resolves with
`status: 0` and the reason in `body`. Check the status *and* catch, or the
failure you are guarding against is the one that slips through.

```js
async function refresh() {
  console.log("weather: refreshing", url);
  try {
    const res = await macotron.http.get(url, { timeout: 10000 });
    if (res.status !== 200) throw new Error("HTTP " + res.status + ": " + res.body);
    paint(JSON.parse(res.body));
    console.log("weather: refreshed");
  } catch (e) {
    console.error("weather: refresh failed", e);
    macotron.menubar.status("weather", {
      title: "--",
      color: "red",
      menu: [
        { title: "Refresh failed: " + (e.message || e) },
        "-",
        { title: "Refresh", onClick: refresh },
      ],
    });
  }
}
```

Run independent awaits together with `Promise.all`. A loop of `await`
runs them one at a time, so at a 10s timeout twenty items can outlast the
interval that started them. For a fan-out big enough to annoy a server,
cap how many are in flight:

```js
async function mapLimit(items, limit, fn) {
  const out = new Array(items.length);
  let i = 0;
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, async () => {
    while (i < items.length) out[i] = await fn(items[i], i++);
  }));
  return out;
}
```

Results come back in the order of `items`, not the order they finished.

## settings.json schema

```json
{
  "launcher": { "hotkey": "opt+space" },
  "ui": {
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
  "launcherFavorites": []
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
