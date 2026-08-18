# Command arguments and per-command shortcuts

Date: 2026-08-18

## Goal

Plugins can declare arguments on launcher commands (lorem ipsum: count + unit). Users can assign a global shortcut to any command in Settings, the same way Raycast does.

## Out of scope

- Nested command lists / command views (select a command, then browse a plugin-provided list)
- Password command arguments
- Leftover-query parsing (`lorem 3 paragraphs` as free text)
- A launcher action that sets a shortcut (Settings only)
- API version bump (stay `1.0.0`; not released)

## Command API

Keep the three-argument form. Add an optional fourth `opts` object.

```js
macotron.command("Generate Lorem Ipsum", "Placeholder text", (args) => {
  macotron.clipboard.set(generate(args.count, args.unit));
}, {
  id: "lorem-ipsum",
  arguments: [
    { name: "count", type: "number", placeholder: "Count", default: 3 },
    {
      name: "unit",
      type: "dropdown",
      placeholder: "Unit",
      default: "paragraphs",
      choices: [
        { title: "Words", value: "words" },
        { title: "Lines", value: "lines" },
        { title: "Paragraphs", value: "paragraphs" },
      ],
    },
  ],
});
```

Three-argument plugins keep working. The handler still runs if it ignores `args`. Extra JS arguments are ignored.

### Stable id

Registry key is `id`, not the display name.

| Case | id |
|---|---|
| `opts.id` is a non-empty string | that string |
| Plugin file is evaluating | `{filename}/{name}` (example: `demo-datetime.js/Insert ISO Date`) |
| Eval / tests (`currentEvaluatingFile` is nil) | `name` |

Duplicate ids: last registration wins. Log a warning.

Set `id` when a shortcut must survive a rename of the display name.

### Argument schema

| Field | Rule |
|---|---|
| `name` | Required. Skip the entry if missing or empty. |
| `type` | `text`, `number`, or `dropdown`. Unknown types become `text`. |
| `placeholder` | Optional. Fallback: `name`. |
| `required` | Optional bool. Default `false`. |
| `default` | Optional. Number defaults coerce to number at resolve time. |
| `choices` | Required for `dropdown`. Each choice: `value` plus `title` or `label`. |

A dropdown with no choices is dropped (log a warning).

## Run path

`Engine.invokeCommand(id, args)` builds a JS object and calls the handler with one argument. Empty args is `{}`.

### Launcher

Search still matches `name`. `SearchResult.id` is the command `id`.

- No arguments: run immediately, close the launcher (today).
- Has arguments: stay open, show the command name as a chip, and a form under the search field (one row per argument: text/number field or dropdown picker). Prefill defaults. Return submits. Escape returns to search.

Do not tokenize the search field. A form is enough for count + unit.

If a required argument is empty, or a number does not parse, or a dropdown value is not in `choices`, do not run.

### Shortcuts

If every required argument has a value (typed or default), run with those values and do not open the launcher. Otherwise open the launcher in argument mode for that command.

## Per-command shortcuts

Host-owned. Stored in `settings.json`:

```json
"commandShortcuts": {
  "lorem-ipsum": "cmd+shift+l"
}
```

Settings → Plugins → plugin detail lists that plugin's commands. Each row has the existing `HotkeyRecorderView`. Delete/Backspace clears.

One combo maps to one command. Assigning a combo that another command already uses moves it. A combo equal to the launcher shortcut is rejected.

Install bindings on the existing `KeyboardModule` event tap (that tap already supports many combos). `GlobalHotkey` stays launcher-only. Check host bindings before plugin `keyboard.on` combos so the user shortcut wins.

After every plugin reload, reinstall host bindings for command ids that still exist. Stale ids stay in JSON until the user clears them; they do nothing.

`keyboard.on` stays for actions that are not launcher commands (window tiling and similar).

## Files

| Unit | Role |
|---|---|
| `CommandArguments.swift` | Spec parse + value resolve (pure, testable) |
| `CommandShortcuts.swift` | id → combo map, reassign, persist |
| `Engine` | `RegisteredCommand`, `invokeCommand` |
| `LauncherView` | Argument form + pending-args session |
| `KeyboardModule` | Host bindings on the existing tap |
| `SettingsView` | Per-command recorder on plugin detail |
| `AppDelegate` | Wire search, run, shortcuts, reload |
