# Project Structure

## Repo Layout

```
macotron/
├── Makefile                         # build, run, bundle, dev, screenshot
├── Package.swift                    # Swift Package Manager manifest
├── Vendor/
│   └── quickjs-ng/                  # QuickJS source (~6 C files)
│       ├── include/
│       │   ├── quickjs.h
│       │   └── quickjs-libc.h
│       ├── quickjs.c
│       ├── libunicode.c
│       ├── libregexp.c
│       ├── cutils.c
│       └── quickjs-libc.c
├── Resources/
│   ├── Info.plist                   # App bundle metadata
│   ├── Macotron.entitlements        # Entitlements (no sandbox)
│   ├── macotron-runtime.js          # JS runtime loaded before snippets
│   └── macotron.d.ts                # JS type definitions for AI/autocomplete
├── Sources/
│   ├── Macotron/                    # App entry point + AppDelegate
│   ├── MacotronUI/                  # SwiftUI + NSPanel + MenuBar
│   ├── MacotronEngine/              # QuickJS engine, EventBus, SnippetManager
│   │   ├── Engine.swift             # QuickJS lifecycle, timers, job queue
│   │   ├── EventBus.swift
│   │   ├── SnippetManager.swift     # Load, watch, backup, auto-fix, reload
│   │   ├── ConfigBackup.swift       # Compress & backup config before changes
│   │   ├── LocalStorageModule.swift # localStorage emulation (JSON file)
│   │   ├── KeychainModule.swift     # macOS Keychain bridge
│   │   └── NLClassifier.swift       # Natural language vs search detection
│   ├── Modules/                     # Native → JS bridge modules
│   ├── AI/                          # AI providers + tool-call file management
│   └── Debug/
│       └── DebugServer.swift        # HTTP server (debug builds only)
├── docs/                            # Architecture documentation
└── Tests/
```

## Source Targets

```
Sources/
├── Macotron/                    # App entry point
│   ├── MacotronApp.swift        # @main, app lifecycle
│   ├── AppDelegate.swift        # NSApplicationDelegate, permissions
│   └── Permissions.swift        # Accessibility, Input Monitoring checks
│
├── MacotronUI/                  # All UI code
│   ├── LauncherPanel.swift      # NSPanel subclass (floating window)
│   ├── LauncherView.swift       # SwiftUI root view (search + chat)
│   ├── SearchField.swift        # Text input + fuzzy matching
│   ├── ResultsList.swift        # File/action/snippet results
│   ├── ChatView.swift           # AI conversation + [Enable]/[Show code] UI
│   ├── MenuBarManager.swift     # NSStatusItem + dynamic NSMenu
│   ├── PreviewPane.swift        # Right-side preview
│   └── CodePreview.swift        # Collapsible code block (for [Show code])
│
├── MacotronEngine/              # Core engine
│   ├── Engine.swift             # JSContext lifecycle, module registration
│   ├── EventBus.swift           # Native→JS event dispatch
│   ├── SnippetManager.swift     # Load, watch, execute snippets
│   ├── ConfigBackup.swift       # Backup/rollback config dir
│   ├── NativeModule.swift       # Protocol all modules conform to
│   └── JSBridge.swift           # Swift↔JS type conversion helpers
│
├── Modules/                     # Native API modules (each exposes to JS)
│   ├── WindowModule.swift       # AXUIElement window management
│   ├── KeyboardModule.swift     # CGEventTap global shortcuts
│   ├── ScreenModule.swift       # ScreenCaptureKit screenshots
│   ├── ShellModule.swift        # Process/command execution
│   ├── NotifyModule.swift       # UserNotifications
│   ├── CameraModule.swift       # Camera state detection
│   ├── URLSchemeModule.swift    # URL handler registration
│   ├── USBModule.swift          # IOKit device monitoring
│   ├── FileSystemModule.swift   # File read/write/watch (FSEvents)
│   ├── ClipboardModule.swift    # NSPasteboard
│   ├── AIModule.swift           # AI provider abstraction
│   ├── SpotlightModule.swift    # NSMetadataQuery file search
│   ├── AppModule.swift          # NSWorkspace app launch/switch
│   ├── SystemModule.swift       # CPU, memory, battery, temp
│   ├── HTTPModule.swift         # URLSession
│   ├── MenuBarModule.swift      # Custom menubar items
│   ├── DisplayModule.swift      # Display config, spaces
│   └── TimerModule.swift        # Intervals, cron-like scheduling
│
└── AI/                          # AI provider implementations
    ├── AIProvider.swift          # Protocol
    ├── AIToolCall.swift          # Tool-call-based file management
    ├── ClaudeProvider.swift      # Anthropic API
    ├── OpenAIProvider.swift      # OpenAI API
    ├── GeminiProvider.swift      # Google Gemini API
    └── LocalProvider.swift       # Apple Foundation Models (on-device)
```

## User Config Structure

```
~/.macotron/
├── config.js                # Main config (API keys, preferences, module options, launcher hotkey)
├── snippets/                # Automations — executed alphabetically on load
│   ├── 001-window-tiling.js
│   ├── 002-url-handlers.js
│   ├── 003-cpu-monitor.js
│   ├── 004-camera-light.js
│   └── 005-menubar-items.js
├── commands/                # Named commands (appear in launcher + menubar)
│   ├── summarize-screen.js
│   └── clipboard-history.js
├── plugins/                 # Third-party snippet packs (git repos or downloads)
│   └── community-pack/
├── data/                    # Persistent state for snippets
│   └── localStorage.json
├── backups/                 # Compressed config backups (auto-created before changes)
│   ├── 2026-02-13T10-30-00.tar.gz
│   └── 2026-02-13T11-15-22.tar.gz
└── logs/
    └── macotron.log
```

**All files are plain JavaScript.** When the AI generates code from a user request, it writes a `.js` file via tool calls. The source of truth is the files on disk.

### Config Backup & Rollback

Before every AI-initiated change (creating, modifying, or deleting snippets), the entire `~/.macotron/` config directory is compressed and backed up to `~/.macotron/backups/`. This enables full rollback to any previous state. Old backups are pruned after 30 days or 100 entries (whichever comes first).

### Module Versioning

Each native module declares a version number. The JS runtime exposes this via `macotron.version.modules` so snippets can check compatibility:

```javascript
macotron.version.app;     // "1.0.0"
macotron.version.modules; // { window: 1, keyboard: 1, shell: 1, ... }
```

When a module's API changes, its version bumps. Snippets can guard against version mismatches.
