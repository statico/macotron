# Native Modules

Each module conforms to `NativeModule`, declares a `name`, and registers C functions on the `macotron` global object in the QuickJS context.

## Module List

| Module | JS Namespace | Purpose |
|---|---|---|
| WindowModule | `macotron.window` | AXUIElement window management |
| KeyboardModule | `macotron.keyboard` | CGEventTap global shortcuts |
| ScreenModule | `macotron.screen` | ScreenCaptureKit screenshots + color picker |
| ShellModule | `macotron.shell` | Process/command execution (with allowlist) |
| NotifyModule | `macotron.notify` | UserNotifications + one-line HUD toasts |
| URLSchemeModule | `macotron.url` | URL handler registration |
| FileSystemModule | `macotron.fs` | File read/write/watch (FSEvents) |
| ClipboardModule | `macotron.clipboard` | NSPasteboard |
| AIModule | `macotron.ai` | AI provider abstraction for plugins |
| PanelModule | `macotron.panel` | Small WKWebView panels |
| SpotlightModule | `macotron.spotlight` | NSMetadataQuery file search |
| AppModule | `macotron.app` | NSWorkspace app launch/switch |
| SystemModule | `macotron.system` | CPU usage, GPU usage, locale, memory, battery, temp |
| HTTPModule | `macotron.http` | URLSession |
| MenuBarModule | `macotron.menubar` | Custom menubar items |
| DisplayModule | `macotron.display` | Display settings, spaces |
| LocalStorageModule | `localStorage` | JSON-backed key-value (global) |
| KeychainModule | `macotron.keychain` | macOS Keychain secrets |

## Key JS APIs

**Window:** `macotron.window.getAll()`, `.focused()`, `.move(id, frame)`, `.moveToFraction(id, {x,y,w,h,display?})` (fractions of the window's current display, or `display` from `macotron.display.list()`), `.snap({ enabled, threshold, corner, gap, zones })` — drag the focused window to a screen edge or corner (clicks do not snap). Zones are `{x,y,w,h}` fractions of the visible frame (same as `moveToFraction`). Omit a slot to disable it. `.setSnapEnabled` / `.isSnapEnabled` toggle without changing the map.

**System:** `macotron.system.cpu()` is `{ usage }` 0–100 since the last call. `gpu()` is `{ name, usage }` or `null`. `locale()` is `{ language, region, measurement: "metric"|"us" }`.

**Keyboard:** `macotron.keyboard.on("tile-left", "ctrl+opt+left", callback)` — ids are unique per plugin; override the combo in Settings → Plugins.

**Shell:** `macotron.shell.run(cmd, args)` — first call to an unapproved command prompts Allow Once / Always Allow / Deny.

**MenuBar:** `macotron.menubar.add(id, config)` (rows in the Macotron menu; `menu` is a nested dropdown), `.status(id, config)` (extra item next to the Macotron icon: `title`, `subtitle`, `color`, `bold`, `italic`, `sfSymbol`, `image` file path, `onClick`, `menu`), `.update`, `.remove`, `.setIcon`, `.setTitle`

**Notify:** `macotron.notify.show(title, body, { sound, subtitle, id })` is a system banner. `macotron.notify.toast(title, body?, { position: "top"|"bottom", duration, sfSymbol, color })` is a one-line HUD centered at the bottom (or top) of the screen under the cursor, inset 24pt from the edges. Default duration is 3000ms. `color` is `success` / `failure` / `warning`, a name (`green`), or `#RRGGBB`. `success` uses a green check if `sfSymbol` is omitted.

**Screen:** `macotron.screen.capture()` is a full-display PNG (base64). `capture({ selection: true })` lets the user drag a rectangle. `pickColor()` opens the system magnifier eyedropper and returns `{ hex, r, g, b, x, y }` or `null` if cancelled.

**Panel:**

```js
const id = macotron.panel.open({ title: "Chat", width: 420, height: 520, html: "<p>Hi</p>", glass: true });
macotron.panel.close(id);
macotron.panel.postMessage(id, data);
macotron.panel.onMessage(id, (data) => { /* ... */ });
```

`html` is inserted into a host document (system font, padding, light/dark). `rawHtml` is a full document, the old `html` behavior. `glass: true` or `"regular"` is translucent Liquid Glass; `"clear"` is the clearer style. Host `html` pages get a transparent background so the glass shows through. In the page, `close()` closes the panel.

**localStorage:** Standard web API backed by JSON under the workdir data store.

**Keychain:** `macotron.keychain.get(key)`, `.set(key, value)`, `.delete(key)`, `.has(key)`

**AI:** See [05-ai-integration.md](05-ai-integration.md).
