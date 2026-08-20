# Native Modules

Each module conforms to `NativeModule`, declares a `name`, and registers C functions on the `macotron` global object in the QuickJS context.

## Module List

| Module | JS Namespace | Purpose |
|---|---|---|
| WindowModule | `macotron.window` | AXUIElement window management |
| EventModule | `macotron.event` / `macotron.mouse` | HID click/key/scroll post, event taps, cursor |
| KeyboardModule | `macotron.keyboard` | CGEventTap global shortcuts |
| ScreenModule | `macotron.screen` | ScreenCaptureKit screenshots + color picker |
| ShellModule | `macotron.shell` | Process/command execution (with allowlist) |
| NotifyModule | `macotron.notify` | UserNotifications + one-line HUD toasts |
| URLSchemeModule | `macotron.url` | URL handler registration |
| FileSystemModule | `macotron.fs` | File read/write/rename/watch (FSEvents) |
| ClipboardModule | `macotron.clipboard` | NSPasteboard |
| AIModule | `macotron.ai` | AI provider abstraction for plugins |
| PanelModule | `macotron.panel` | Small WKWebView panels |
| SpotlightModule | `macotron.spotlight` | NSMetadataQuery file search |
| AppModule | `macotron.app` | NSWorkspace app launch/switch/hide/quit/menu |
| AudioModule | `macotron.audio` | Default input/output, volume, mute |
| SpacesModule | `macotron.spaces` | Mission Control spaces |
| USBModule | `macotron.usb` | USB devices + attach/detach |
| ShortcutsModule | `macotron.shortcuts` | List and run Shortcuts.app |
| SystemModule | `macotron.system` | CPU usage, GPU usage, locale, memory, battery, temp |
| HTTPModule | `macotron.http` | URLSession |
| MenuBarModule | `macotron.menubar` | Custom menubar items |
| DisplayModule | `macotron.display` | Displays, brightness, gamma, XDR |
| LocalStorageModule | `localStorage` | JSON-backed key-value (global) |
| KeychainModule | `macotron.keychain` | macOS Keychain secrets |
| MediaModule | `macotron.media` | Now Playing metadata, artwork, play/pause |
| LauncherModule | `macotron.launcher` | Extra rows in the quick launcher |
| NotesModule | `macotron.notes` | List and open Apple Notes |
| PowerModule | `macotron.power` | Prevent sleep, lock, sleep |

## Key JS APIs

**Window:** `macotron.window.getAll()`, `.focused()`, `.focus(id)` (raise, unminimize, activate the app), `.minimize(id, on?)`, `.close(id)`, `.setFullscreen(id, on)`, `.move(id, frame)`, `.moveToFraction(id, {x,y,w,h,display?})` (fractions of the window's current display, or `display` from `macotron.display.list()`), `.snap({ enabled, threshold, corner, gap, zones })` — drag the focused window to a screen edge or corner (clicks do not snap). Zones are `{x,y,w,h}` fractions of the visible frame (same as `moveToFraction`). Omit a slot to disable it. `.setSnapEnabled` / `.isSnapEnabled` toggle without changing the map. `window:created` and `window:focused` fire with `{ id, title, app }`.

**System:** `macotron.system.cpu()` is `{ usage }` 0–100 since the last call. `gpu()` is `{ name, usage }` or `null`. `locale()` is `{ language, region, measurement: "metric"|"us" }`. `fans()` is current RPM plus `available` (this Mac has fans), `controllable` (a floor can be set right now), and an optional `floor` (50 or 100). Reads need no privileges; writes do, so `controllable` is false until the user installs the fan helper from the plugin's Settings page (`macotron.settings.open()`). It is listed there only for plugins declaring the `fanControl` permission. `setFanFloor(100 | 50 | null)` holds a minimum; `null` is system default. The host never commands below firmware min, and yields to macOS when it already wants a higher speed.

**Media:** `macotron.media.nowPlaying()` is `{ playing, title, artist, album, app, bundle, artwork? }`. `artwork` is a JPEG path when iTunes Search finds a cover. `playPause()` / `next()` / `previous()` talk to the system Now Playing target (Spotify, Music, SomaFM, Safari, …). `media:changed` fires when the snapshot changes.

**Launcher:** `macotron.launcher.set(id, items)` replaces that plugin's extra rows in the quick launcher. Each item is `{ id, title, subtitle?, app?, sfSymbol?, kind?, onClick }`. `app` is a bundle ID (Notes uses `com.apple.Notes`). An empty query shows only starred items (⌘S). Typing filters plugin rows with apps and commands.

**Notes:** `macotron.notes.list()` is `{ id, title, folder }[]`. `open(id)` shows the note in the Notes app. macOS prompts to allow controlling Notes on first use.

**App:** `macotron.app.launch(bundleID)` and `.switch(bundleID)` both open via Launch Services (`activates: true`), so a running app comes forward. `.list()`, `.frontmost()`, `.hide(bundleID?)`, `.quit(bundleID?)`, `.menu(["File", "New"], bundleID?)`. Events: `app:activated`, `app:launched`, `app:terminated`.

**Audio:** `devices()`, `input()`, `output()`, `setInput` / `setOutput` (id or name), `volume` / `setVolume` (0…1), `isMuted` / `setMuted`. `audio:changed` is `{ flags: ["input"|"output"|"devices"] }`.

**Spaces:** `list()` is `{ id, index, desktop, display, current, type }[]`. `current()`, `go(2)` (Mission Control desktop number) or `go({ id })` / `go({ index, display })`. `moveWindow(windowId, spec)` tries SkyLight and returns false when SIP blocks it. `space:changed` fires on a desktop switch.

**USB:** `usb.list()` is `{ name, vendor, vendorID, productID }[]`. `usb:changed` is the same plus `action: "add"|"remove"`.

**Shortcuts:** `shortcuts.list()` and `shortcuts.run(name)` call `/usr/bin/shortcuts`.

**Power:** `preventSleep` / `allowSleep` / `isPreventing`, plus `lock()` and `sleep()`. Events: `system:sleep`, `system:wake`, `system:lock`, `system:unlock`.

**Keyboard:** `macotron.keyboard.on("tile-left", "ctrl+opt+left", callback)` — ids are unique per plugin; override the combo in Settings → Plugins. `keyboard.flags()` is `{ cmd, shift, ctrl, opt, caps, fn }`.

**Event:** `macotron.event.post({ type: "click"|"key"|"unicode"|"scroll", ... })` posts HID. `event.tap(["flagsChanged","scroll"], cb)` listens; return `false` to swallow. Coords are Cocoa (same as `window.frame`). `macotron.mouse.location()`, `.warp(x, y)`, `.buttons()`.

**Display:** `list()` is `{ id, width, height, main, frame, visibleFrame, scale, rotation, builtin, mirrored, serial, mm }`. `display:changed` fires with `{ id, flags }` (`add`, `remove`, `move`, `main`, `mode`, `enable`, `disable`, `mirror`, `unmirror`, `shape`). `getBrightness` / `setBrightness`, `setXDREnabled`. `setGamma({ red, green, blue }, black?, id?)` writes the display LUT (omit `id` for every screen). Red-only night vision is `setGamma({ red: 1, green: 0, blue: 0 })`. `restoreGamma()` puts ColorSync back. Plugin unload also restores ColorSync.

**Shell:** `macotron.shell.run(cmd, args)` — first call to an unapproved command prompts Allow Once / Always Allow / Deny.

**Files:** `read`, `write`, `exists`, `list`, `watch`, `rename(from, to)`. Paths expand `~`. `rename` fails if `to` already exists.

**MenuBar:** `macotron.menubar.add(id, config)` (rows in the Macotron menu; `menu` is a nested dropdown), `.status(id, config)` (extra item next to the Macotron icon: `title`, `subtitle`, `color`, `subtitleColor`, `bold`, `italic`, `secondary`, `minWidth` in points, `sfSymbol`, `image` file path, `onClick`, `menu`), `.update`, `.remove`, `.setIcon`, `.setTitle`. Two-line extras use the same size and color for both lines unless `secondary` is set (smaller, dimmer subtitle).

**Notify:** `macotron.notify.show(title, body, { sound, subtitle, id })` is a system banner. `macotron.notify.toast(title, body?, { position: "top"|"bottom", duration, sfSymbol, color })` is a one-line HUD centered at the bottom (or top) of the screen under the cursor, inset 48pt from the edges. Default duration is 3000ms. `color` is `info` (label color, no icon), `success` (green check), `error` / `failure` (red x), `warning` (orange triangle), a name (`green`), or `#RRGGBB`. Pass `sfSymbol` to override the default icon.

**Checks:** `macotron.checks([{ title, ok, message }])` replaces this plugin's Checks list in Settings → Plugins. A row with `ok: false` shows an orange warning on the plugin (red stays a JS load error). Pass `[]` to clear. Call again when the status changes.

**Settings:** `macotron.settings.open()` opens Settings → Plugins on the calling plugin.

**Screen:** `macotron.screen.capture()` is a full-display PNG (base64). `capture({ selection: true })` lets the user drag a rectangle. `pickColor()` opens the system magnifier eyedropper and returns `{ hex, r, g, b, x, y }` or `null` if cancelled.

**Panel:**

```js
const id = macotron.panel.open({ title: "Chat", width: 420, height: 520, html: "<p>Hi</p>", glass: true });
macotron.panel.close(id);
macotron.panel.postMessage(id, data);
macotron.panel.onMessage(id, (data) => { /* ... */ });
```

`html` is inserted into a host document (system font, padding, light/dark). `rawHtml` is a full document, the old `html` behavior. `glass: true` or `"regular"` is translucent Liquid Glass; `"clear"` is the clearer style. Host `html` pages get a transparent background so the glass shows through. In the page, `close()` closes the panel.

Host CSS defines system colors as variables: `--macotron-accent`, `--macotron-accent-text`, `--macotron-label`, `--macotron-secondary-label`, `--macotron-fill`, `--macotron-control`, `--macotron-control-text`, `--macotron-control-border`, `--macotron-field`, `--macotron-field-text`, `--macotron-selected`, `--macotron-selected-text`, `--macotron-link`. They follow the system appearance. `button.primary` uses the accent color.

**localStorage:** Standard web API backed by JSON under the workdir data store.

**Keychain:** `macotron.keychain.get(key)`, `.set(key, value)`, `.delete(key)`, `.has(key)`

**AI:** See [05-ai-integration.md](05-ai-integration.md).
