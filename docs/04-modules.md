# Native Modules

Each module conforms to `NativeModule`, declares a `name` and `version`, and registers C functions on the `macotron` global object in the QuickJS context.

## Module List

| Module | JS Namespace | Purpose | Version |
|---|---|---|---|
| WindowModule | `macotron.window` | AXUIElement window management | 1 |
| KeyboardModule | `macotron.keyboard` | CGEventTap global shortcuts | 1 |
| ScreenModule | `macotron.screen` | ScreenCaptureKit screenshots | 1 |
| ShellModule | `macotron.shell` | Process/command execution (with allowlist) | 1 |
| NotifyModule | `macotron.notify` | UserNotifications | 1 |
| CameraModule | `macotron.camera` | Camera state detection (polling) | 1 |
| URLSchemeModule | `macotron.url` | URL handler registration | 1 |
| USBModule | `macotron.usb` | IOKit device monitoring | 1 |
| FileSystemModule | `macotron.fs` | File read/write/watch (FSEvents) | 1 |
| ClipboardModule | `macotron.clipboard` | NSPasteboard | 1 |
| AIModule | `macotron.ai` | AI provider abstraction | 1 |
| SpotlightModule | `macotron.spotlight` | NSMetadataQuery file search | 1 |
| AppModule | `macotron.app` | NSWorkspace app launch/switch | 1 |
| SystemModule | `macotron.system` | CPU, memory, battery, temp | 1 |
| HTTPModule | `macotron.http` | URLSession | 1 |
| MenuBarModule | `macotron.menubar` | Custom menubar items | 1 |
| DisplayModule | `macotron.display` | Display config, spaces | 1 |
| TimerModule | `macotron.timer` | Intervals, cron-like scheduling | 1 |
| LocalStorageModule | `localStorage` | JSON-backed key-value (global) | 1 |
| KeychainModule | `macotron.keychain` | macOS Keychain secrets | 1 |

## Key JS APIs

### Window Management
```javascript
macotron.window.getAll()                    // → [{ id, title, app, frame }]
macotron.window.focused()                   // → { id, title, app, frame }
macotron.window.move(id, { x, y, w, h })    // absolute position
macotron.window.moveToFraction(id, { x, y, w, h })  // fraction of screen
```

### Keyboard Shortcuts
```javascript
macotron.keyboard.on("cmd+shift+left", callback)
```

### Shell (with allowlist)
Shell commands use a permission model: first call to an unapproved command prompts Allow Once / Always Allow / Deny. Approved commands stored in config.

### MenuBar (xbar-style)
```javascript
macotron.menubar.add(id, { title, icon?, shortcut?, onClick?, section?, refresh? })
macotron.menubar.update(id, { title?, icon? })
macotron.menubar.remove(id)
macotron.menubar.setIcon(sfSymbolName)
macotron.menubar.setTitle(text)
```

### localStorage (synchronous key-value)
Backed by `~/.macotron/data/localStorage.json`. Standard web API.

```javascript
localStorage.setItem("key", "value");
localStorage.getItem("key");
localStorage.removeItem("key");
localStorage.clear();
```

### Keychain
```javascript
macotron.keychain.get("key-name")           // → string | null
macotron.keychain.set("key-name", "sk-...")  // → void
macotron.keychain.delete("key-name")        // → void
macotron.keychain.has("key-name")           // → boolean
```
