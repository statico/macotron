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
| URLSchemeModule | `macotron.url` | URL handler registration |
| FileSystemModule | `macotron.fs` | File read/write/watch (FSEvents) |
| ClipboardModule | `macotron.clipboard` | NSPasteboard |
| AIModule | `macotron.ai` | AI provider abstraction for plugins |
| PanelModule | `macotron.panel` | Small WKWebView panels |
| SpotlightModule | `macotron.spotlight` | NSMetadataQuery file search |
| AppModule | `macotron.app` | NSWorkspace app launch/switch |
| SystemModule | `macotron.system` | CPU, memory, battery, temp |
| HTTPModule | `macotron.http` | URLSession |
| MenuBarModule | `macotron.menubar` | Custom menubar items |
| DisplayModule | `macotron.display` | Display settings, spaces |
| LocalStorageModule | `localStorage` | JSON-backed key-value (global) |
| KeychainModule | `macotron.keychain` | macOS Keychain secrets |

## Key JS APIs

**Window:** `macotron.window.getAll()`, `.focused()`, `.move(id, frame)`, `.moveToFraction(id, frame)`

**Keyboard:** `macotron.keyboard.on("tile-left", "ctrl+opt+left", callback)` — ids are unique per plugin; override the combo in Settings → Plugins.

**Shell:** `macotron.shell.run(cmd, args)` — first call to an unapproved command prompts Allow Once / Always Allow / Deny.

**MenuBar:** `macotron.menubar.add(id, config)` (rows in the Macotron menu; `menu` is a nested dropdown), `.status(id, config)` (extra item next to the Macotron icon: `title`, `subtitle`, `color`, `bold`, `italic`, `sfSymbol`, `image` file path, `onClick`, `menu`), `.update`, `.remove`, `.setIcon`, `.setTitle`

**Panel:**

```js
const id = macotron.panel.open({ title: "Chat", width: 420, height: 520, html: "<p>Hi</p>" });
macotron.panel.close(id);
macotron.panel.postMessage(id, data);
macotron.panel.onMessage(id, (data) => { /* ... */ });
```

`html` is inserted into a host document (system font, padding, light/dark). `rawHtml` is a full document, the old `html` behavior. In the page, `close()` closes the panel.

**localStorage:** Standard web API backed by JSON under the workdir data store.

**Keychain:** `macotron.keychain.get(key)`, `.set(key, value)`, `.delete(key)`, `.has(key)`

**AI:** See [05-ai-integration.md](05-ai-integration.md).
