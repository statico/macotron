# Project Structure

This layout matches the host-shell redesign.

## Repo Layout

```
macotron/
├── Makefile                         # build, run, bundle
├── Package.swift                    # Swift Package Manager manifest
├── Indexer/                         # Rust file indexer (macotron-index), see 12-file-index.md
├── Vendor/
│   └── quickjs-ng/                  # QuickJS source
├── Resources/
│   ├── Info.plist
│   ├── Macotron.entitlements        # Entitlements (no sandbox)
│   ├── Macotron.icon/               # Icon Composer source, compiled by actool
│   └── banner.png
├── Sources/
│   ├── Macotron/                    # App entry point + AppDelegate
│   ├── MacotronUI/                  # Wizard, settings, menu bar, launcher
│   ├── MacotronEngine/              # QuickJS engine, EventBus, plugin loader
│   ├── Modules/                     # Native → JS bridge modules
│   └── AI/                          # Providers for macotron.ai (plugin API)
├── docs/
└── Tests/
```

The redesign removes in-app agent UI and agent loop types. Do not keep `AgentSession`, `ChatSession`, `SnippetAutoFix`, or agent progress panels as product surfaces.

## User Workdir

The user picks one directory. That directory is the plugins workdir and a git repo.

```
<user-chosen>/
├── .git/
├── .gitignore               # ignores AGENTS.md, CLAUDE.md, .cache/
├── settings.json            # launcher hotkey, UI prefs, plugin options
├── README.md                # human (seeded once if missing)
├── AGENTS.md                # app-owned — do not edit
├── CLAUDE.md                # app-owned — do not edit
├── plugins/
│   └── *.js
└── .cache/                  # bytecode (gitignored)
```

Only `pluginsDirectory` can live in UserDefaults. All other settings live in `settings.json`.

See [10-plugins-workdir.md](10-plugins-workdir.md).

