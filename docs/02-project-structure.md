# Project Structure

This layout matches the host-shell redesign.

## Repo Layout

```
macotron/
├── Makefile                         # build, run, bundle
├── Package.swift                    # Swift Package Manager manifest
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

## Source Targets (Intended)

```
Sources/
├── Macotron/                    # App entry point
│   ├── MacotronApp.swift
│   ├── AppDelegate.swift
│   ├── Permissions.swift        # Lazy Accessibility / Input Monitoring / Screen Recording
│   └── Resources/
│       ├── macotron-runtime.js
│       └── macotron.d.ts
│
├── MacotronUI/                  # Host UI only
│   ├── WizardView.swift         # Pick workdir, optional open in Finder or your editor
│   ├── WizardWindow.swift
│   ├── SettingsView.swift
│   ├── SettingsWindow.swift
│   ├── MenuBarManager.swift
│   ├── LauncherPanel.swift
│   ├── LauncherView.swift       # Plugin list / launcher
│   └── GlobalHotkey.swift
│
├── MacotronEngine/              # Core engine
│   ├── Engine.swift             # QuickJS lifecycle, timers, job queue
│   ├── EventBus.swift
│   ├── SnippetManager.swift     # Load / watch / reload plugins/ (name can stay)
│   ├── NativeModule.swift
│   └── JSBridge.swift
│
├── Modules/                     # Native API modules
│   ├── WindowModule.swift
│   ├── KeyboardModule.swift
│   ├── EventModule.swift
│   ├── ScreenModule.swift
│   ├── ShellModule.swift
│   ├── NotifyModule.swift
│   ├── URLSchemeModule.swift
│   ├── FileSystemModule.swift
│   ├── ClipboardModule.swift
│   ├── AIModule.swift           # Exposes macotron.ai to plugins
│   ├── PanelModule.swift        # WKWebView panels (macotron.panel)
│   ├── SpotlightModule.swift
│   ├── AppModule.swift
│   ├── SystemModule.swift
│   ├── HTTPModule.swift
│   ├── MenuBarModule.swift
│   ├── DisplayModule.swift
│   ├── LocalStorageModule.swift
│   └── KeychainModule.swift
│
└── AI/                          # Cloud and on-device providers for plugins
    ├── AIProvider.swift
    ├── ClaudeProvider.swift
    ├── OpenAIProvider.swift
    └── LocalProvider.swift      # Apple Foundation Models
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

## Module Versioning

Each native module declares a version number. The JS runtime exposes this via `macotron.version.modules` so plugins can guard compatibility:

```javascript
macotron.version.app;     // "1.0.0"
macotron.version.modules; // { window: 1, keyboard: 1, shell: 1, ... }
```

When a module API changes, its version bumps.
