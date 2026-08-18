# Plugin settings in the Macotron UI

Date: 2026-08-18

## Goal

Plugins declare configurable options (hotkeys, strings, API keys, paths, etc.). Macotron Settings → Plugins renders a form. Values persist in `settings.json` except secrets, which live in Keychain with a stable ref stored in JSON.

## Decisions

- Extend the existing `macotron.module({ options })` API ( declarative prefs).
- Secret type is `password`: Keychain holds the value; `settings.json` stores a Keychain account **ref**.
- `file` / `directory` store absolute path strings (not security-scoped bookmarks).
- Stay on API version `1.0.0` (not released yet). No `needs` bump for these types.

## Declaration

```js
const opts = macotron.module({
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
    apiKey: {
      type: "password",
      label: "Anthropic API key",
      required: true,
    },
    openHotkey: {
      type: "keybinding",
      label: "Open chat",
      default: "cmd+shift+c",
    },
    notesFile: {
      type: "file",
      label: "Notes file",
      default: "",
    },
    workspace: {
      type: "directory",
      label: "Workspace folder",
      default: "",
    },
  },
});
// opts.apiKey === resolved secret string (or "")
```

## Option types (v1)

| Type | Storage | UI |
|------|---------|-----|
| `string` | value in `pluginSettings` | text field |
| `boolean` | value | checkbox |
| `number` | value | number field |
| `keybinding` | value | hotkey recorder |
| `dropdown` | value | popup; requires `choices: [{ value, label }]` |
| `password` | Keychain **ref** in JSON; secret in Keychain | secure field + Clear; show Set / Not set |
| `file` | absolute path string | path + Choose… (`NSOpenPanel` files) |
| `directory` | absolute path string | path + Choose… (`NSOpenPanel` directories) |

Optional fields on every option:

- `label` (required for UI)
- `default` (optional; password defaults to unset)
- `required` (optional bool) — Settings shows a needs-setup hint when unset

Invalid dropdown (missing `choices`): empty control + log / treat as metadata warning.

## Password / Keychain

- Account id: `macotron.plugin.<filename>.<optionKey>`  
  Example: `macotron.plugin.chat.js.apiKey`
- On Set: write Keychain password for that account; store the account string in `pluginSettings[file][key]`.
- On Clear: delete Keychain item; remove or clear the JSON ref.
- `macotron.module()` returns the **resolved secret string** to JS, never the ref. Unset → `""`.
- Refs in JSON may be committed. Real secrets must never appear in JSON or plugin source.

Example `settings.json` fragment:

```json
"pluginSettings": {
  "chat.js": {
    "model": "sonnet",
    "apiKey": "macotron.plugin.chat.js.apiKey",
    "openHotkey": "cmd+shift+c",
    "notesFile": "/Users/alex/notes.md",
    "workspace": "/Users/alex/dev/project"
  }
}
```

## Settings UI

- Settings → Plugins: each plugin row shows title, description, errors.
- Options section: expand by default when any `required` option is unset; otherwise collapsed with an “N settings” hint.
- Saving an option updates storage and reloads plugins (existing `saveModuleOption` path).
- `required` + unset: badge / “Needs setup” only. Do not block launcher commands in v1.

## Resolution

| Type | Plugin sees |
|------|-------------|
| Non-password | `pluginSettings` value, else `default` |
| `password` | Keychain value for the JSON ref, else `""` |

## Docs

- Update `macotron.d.ts` and app-owned `AGENTS.md` with all types and the password-ref rule.
- Tell agents: configure via Settings UI; read via `macotron.module()`.

## Migration

- Existing `string` / `boolean` / `number` / `keybinding` options keep working unchanged.
- API version remains `1.0.0`.

## Out of scope (v1)

- Custom WKWebView settings pages per plugin
- Security-scoped bookmarks for paths
- Blocking commands until required options are set
- Renaming `macotron.module` (docs may say “plugin settings”; API name stays)

## Precedents

 extension `preferences` (declarative types + host form + password type). VS Code `contributes.configuration`. Alfred workflow config fields.
