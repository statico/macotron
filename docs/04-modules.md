# Native Modules

Each module conforms to `NativeModule`, declares a `name`, and registers C functions on the `macotron` global object in the QuickJS context.

## Module List

| Module | JS Namespace | Purpose |
|---|---|---|
| WindowModule | `macotron.window` | AXUIElement window management |
| KeyboardModule | `macotron.keyboard` | CGEventTap global shortcuts |
| ScreenModule | `macotron.screen` | ScreenCaptureKit screenshots |
| ShellModule | `macotron.shell` | Process/command execution (with allowlist) |
| NotifyModule | `macotron.notify` | UserNotifications |
| CameraModule | `macotron.camera` | Camera state detection (polling) |
| URLSchemeModule | `macotron.url` | URL handler registration |
| USBModule | `macotron.usb` | IOKit device monitoring |
| FileSystemModule | `macotron.fs` | File read/write/watch (FSEvents) |
| ClipboardModule | `macotron.clipboard` | NSPasteboard |
| AIModule | `macotron.ai` | AI provider abstraction |
| SpotlightModule | `macotron.spotlight` | NSMetadataQuery file search |
| AppModule | `macotron.app` | NSWorkspace app launch/switch |
| SystemModule | `macotron.system` | CPU, memory, battery, temp |
| HTTPModule | `macotron.http` | URLSession |
| MenuBarModule | `macotron.menubar` | Custom menubar items |
| DisplayModule | `macotron.display` | Display config, spaces |
| TimerModule | `macotron.timer` | Intervals, cron-like scheduling |
| LocalStorageModule | `localStorage` | JSON-backed key-value (global) |
| KeychainModule | `macotron.keychain` | macOS Keychain secrets |

## Key JS APIs

**Window:** `macotron.window.getAll()`, `.focused()`, `.move(id, frame)`, `.moveToFraction(id, frame)`

**Keyboard:** `macotron.keyboard.on("cmd+shift+left", callback)`

**Shell:** `macotron.shell.run(cmd, args)` — first call to an unapproved command prompts Allow Once / Always Allow / Deny.

**MenuBar:** `macotron.menubar.add(id, config)`, `.update(id, config)`, `.remove(id)`, `.setIcon(name)`, `.setTitle(text)`

**localStorage:** Standard web API backed by `~/Library/Application Support/Macotron/data/localStorage.json`.

**Keychain:** `macotron.keychain.get(key)`, `.set(key, value)`, `.delete(key)`, `.has(key)`
