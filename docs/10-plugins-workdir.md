# Plugins Workdir

The user picks one directory as the Macotron workdir. That directory holds settings, plugins, and agent instruction files. External coding agents edit plugins here. The Macotron app owns a small set of files inside it.

## Layout

```
<user-chosen>/
  .git/
  .gitignore          # ignores AGENTS.md, CLAUDE.md, .cache/
  settings.json       # launcher hotkey, UI prefs, plugin options
  README.md           # human (seeded once if missing)
  AGENTS.md           # app-owned — do not edit
  CLAUDE.md           # app-owned — do not edit
  plugins/
    *.js
  .cache/             # bytecode (gitignored)
```

Only the path to this directory can live in UserDefaults (`pluginsDirectory`). All other settings live in `settings.json`.

## settings.json

Example:

```json
{
  "launcher": { "hotkey": "opt+space" },
  "ui": {
    "showMenuBarIcon": true,
    "appearance": "system",
    "textScale": 1.0,
    "launcherBackground": "translucent",
    "hotReload": false
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

Launcher commands can declare `arguments` on `macotron.command`. Users assign per-command shortcuts in Settings → Plugins or in the launcher with ⌘K on a selected result (apps included). Those bindings live in `commandShortcuts`. Star a result with ⌘S; `launcherFavorites` is the empty-query list. Plugin hotkeys from `keyboard.on(id, default, callback)` are overridable in Settings (`keyboardShortcuts`). Do not register `keyboard.on` for launcher commands.

The app watches the workdir. `settings.json` updates apply without reloading plugins. With **Hot Reload** off (the default), a change to `plugins/*.js` keeps the last in-memory copy and asks you to Review & Reload. With Hot Reload on, plugins reload immediately and the menu bar shows an orange dot.

## Git

The workdir is a git repo for local versioning when Apple developer tools are present.

- The app runs `git init` only if `xcode-select -p` succeeds (real git, not the CLT stub).
- Git is optional. The app and plugins work without it.
- External agents create commits. The app does not create commits.
- Commit often on `main`.
- Do not commit secrets. Use `macotron.keychain` for API keys.

## App-Owned Agent Files

`AGENTS.md` and `CLAUDE.md` belong to the app. They must not be edited. The app overwrites them.

Each file starts with this banner:

```
<!-- DO NOT EDIT — Macotron overwrites this file. -->
```

Content covers:

- What the directory is
- Plugin rules
- API summary
- Git commit guidance (commit often on `main`, no secrets)

`.gitignore` must list `AGENTS.md`, `CLAUDE.md`, and `.cache/` so those files stay out of the repo.

## Human README

The app seeds `README.md` once if the file is missing. Humans and agents can edit that file after the seed. The app does not overwrite it later.

## Plugins

Plugins are `.js` files under `plugins/`. Each file registers hotkeys and hooks at load time. Community plugins can use the GitHub topic `macotron-plugin`:

https://github.com/topics/macotron-plugin

Plugins must run on a stock Mac. Use `macotron.*` and Apple-shipped CLI tools only. Do not depend on Homebrew, npm, or other third-party binaries.

## First-Run Flow

1. Pick the workdir in the wizard.
2. Optionally open the directory in Finder or your editor.
3. Make sure that the app wrote `AGENTS.md` and `CLAUDE.md`.
4. Ask an external agent to add files under `plugins/`.
5. Grant Accessibility or Screen Recording only when a plugin needs those features.
