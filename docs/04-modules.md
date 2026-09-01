# Native Modules

Each module conforms to `NativeModule`, declares a `name`, and registers C functions on the `macotron` global object in the QuickJS context.

## Module List

The list of modules and their JS namespaces lives in `Sources/Modules/` and in
`Sources/Macotron/Resources/macotron.d.ts`, which is the typed contract plugins
are checked against.

## Key JS APIs

**Window:** `macotron.window.getAll()`, `.focused()`, `.focus(id)` (raise, unminimize, activate the app), `.minimize(id, on?)`, `.close(id)`, `.setFullscreen(id, on)`, `.move(id, frame)`, `.moveToFraction(id, {x,y,w,h,display?})` (fractions of the window's current display, or `display` from `macotron.display.list()`), `.previewFraction({x,y,w,h,display?})` (translucent destination overlay; pass `null` to hide), `.snap({ enabled, threshold, corner, gap, zones, modifiers })` — drag the focused window to a screen edge or corner (clicks do not snap). A preview box fades in over the destination. Zones are `{x,y,w,h}` fractions of the visible frame (same as `moveToFraction`). Omit a slot to disable it. Default zones are halves. `modifiers` is a map of held keys (`shift`, `cmd+shift`) to an alternate zone map. `.setSnapEnabled` / `.isSnapEnabled` toggle without changing the map. `window:created` and `window:focused` fire with `{ id, title, app }`.

**System:** `macotron.system.cpu()` is `{ usage }` 0–100 since the last call. `gpu()` is `{ name, usage }` or `null`. `locale()` is `{ language, region, measurement: "metric"|"us", hour12 }` (`hour12` is the system clock setting -- QuickJS has no Intl). `battery()` is `{ level, charging, charged, timeRemaining, timeToFull, source, lowPowerMode }` plus optional `health` (max capacity % of design), `cycles`, and `watts` (adapter). `timeRemaining` / `timeToFull` are minutes, or `-1` if unknown. `source` is `"ac"` or `"battery"`. `setLowPowerMode(true|false)` runs `pmset` (admin password) and resolves with `{ ok, lowPowerMode, error? }`. `darkMode()` reads the system appearance; `setDarkMode(on)` resolves once it is set. `appearance()` is `"light"`, `"dark"`, or `"auto"` (auto reads as auto even while a theme shows); `setAppearance(mode)` resolves with `{ ok, appearance, error? }` and clears auto when given an explicit theme. `processes(limit?)` resolves with `{ name, pid, cpu }[]`. `focus()` is `{ focused }` for the current Focus mode (read-only). `fans()` is current RPM plus `available` (this Mac has fans), `controllable` (a floor can be set right now), and an optional `floor` (50 or 100). Reads need no privileges; writes do, so `controllable` is false until the user installs the background helper from the plugin's Settings page (`macotron.settings.open()`). It is listed there only for plugins declaring the `helper` permission. `setFanFloor(100 | 50 | null)` is a promise of the same snapshot -- the privileged call is a round trip to the helper daemon -- and holds a minimum; `null` is system default. The host never commands below firmware min, and releases the fans to macOS when `ProcessInfo.thermalState` reaches `.serious` -- a floor held in manual mode is also a ceiling, so it has to yield before it can starve a struggling Mac of air.

**Media:** `macotron.media.nowPlaying()` is `{ playing, title, artist, album, app, bundle, artwork? }`. `artwork` is a JPEG path when iTunes Search finds a cover. `playPause()` / `next()` / `previous()` talk to the system Now Playing target (Spotify, Music, SomaFM, Safari, …). `media:changed` fires when the snapshot changes.

**Launcher:** `macotron.launcher.set(id, items)` replaces that plugin's extra rows in the quick launcher. Each item is `{ id, title, subtitle?, app?, path?, sfSymbol?, kind?, onClick }`. `macotron.launcher.query(id, fn)` answers the typed text instead; `fn` may return rows or a promise of rows, and the launcher shows late rows when the promise settles rather than holding up the keystroke. `app` is a bundle ID (Notes uses `com.apple.Notes`), and `path` a file path the launcher turns into that file's Finder icon and a ⌘Return "Reveal in Finder". `query` takes an optional third argument `{ run }`, a resolver called with a row's `id` so a shortcut bound to one of these rows still runs after the row has scrolled out of the results or the app has restarted. An empty query shows only starred items (⌘S). Typing filters plugin rows with apps and commands.

**Notes:** `macotron.notes.list()` resolves with `{ id, title, folder }[]`. `open(id)` shows the note in the Notes app and resolves when it has. macOS prompts to allow controlling Notes on first use. Recently Deleted notes are omitted.

**Contacts:** `macotron.contacts.list()` and `.search(query)` resolve with `{ id, name, first, last, organization, emails, phones }[]`. macOS prompts for Contacts access on first use.

**App:** `macotron.app.launch(bundleID)` and `.switch(bundleID)` both open via Launch Services (`activates: true`), so a running app comes forward. `.list()`, `.frontmost()`, `.hide(bundleID?)`, `.quit(bundleID?)`, `.menu(["File", "New"], bundleID?)`. Events: `app:activated`, `app:launched`, `app:terminated`.

**Audio:** `devices()`, `input()`, `output()`, `setInput` / `setOutput` (id or name), `volume` / `setVolume` (0…1), `isMuted` / `setMuted`. No-id mute is the default output. Pass the input device id to mute that input. `audio:changed` is `{ flags: ["input"|"output"|"devices"] }`. System output volume is this same `volume` / `setVolume` / `setMuted` with no device id.

**Network:** `wifi()` resolves with `{ available, on, ssid? }`. `setWifi(on)` uses `networksetup` and resolves with the new state. `wifiSSID()` resolves with the SSID or `null`. `bluetooth()` resolves with `{ on, devices: [{ name, address, connected, battery? }] }`. `battery` is 0–100 when known. `setBluetooth(on)` toggles the radio and returns directly — it is one in-process call, not a subprocess. `airDrop()` reads sharingd Discoverable Mode directly; `setAirDrop("off"|"contacts"|"everyone")` has to restart sharingd, so it resolves. `interfaces()` is IPv4 `{ name, ip }[]`. `counters()` is `{ name, ip?, bytesIn, bytesOut }[]` (no loopback). `ping(host?)` resolves with `{ ms, host, error? }` via `/sbin/ping` (default `1.1.1.1`). `wifi:changed` is `{ on, ssid }`.

**HTTP:** `http.get(url, opts?)`, `.post(url, body, opts?)`, `.put`, `.delete`. All resolve with `{ status, body, headers }`; a request that fails resolves with `status: 0` and the reason in `body` instead of rejecting. `opts.timeout` is milliseconds and defaults to 30000 -- URLSession enforces it, so the request is really cancelled, which racing the promise against `setTimeout` in a plugin would not do. `opts.headers` carries Content-Type, Authorization, Accept, User-Agent, X-API-Key, and X-Request-ID; others are dropped.

**Bonjour:** `bonjour.browse(type, { timeout })` resolves with `{ name, type, host, port, txt }[]`. `type` is `_airplay._tcp` or `_companion-link._tcp` (with or without `local.`). `timeout` is seconds, default 1.5. Dry-run resolves with `[]`.

**UDP:** `udp.send(host, port, data)` sends utf8 or a byte array. `listen(port)` emits `udp:message` as `{ host, port, data }` (`data` is utf8 or base64). `unlisten(port)`. Dry-run send is `{ ok: true }`.

**Apple TV:** `appletv.list()` browses companion-link and AirPlay and resolves with the devices. `id` is `host:port`. `send(id, command)` is `up|down|left|right|select|menu|home|play|pause|playpause` and resolves with `{ ok, error? }`. Missing device is `{ ok: false, error: "No Apple TV" }`. Found but unpaired is `{ ok: false, error: "not paired" }`. The tvOS Simulator does not advertise these services and cannot be controlled. Dry-run send resolves with `{ ok: true }`.

**Spaces:** `list()` is `{ id, index, desktop, display, current, type }[]`. `current()`, `go(2)` (Mission Control desktop number) or `go({ id })` / `go({ index, display })`. `moveWindow(windowId, spec)` tries SkyLight and returns false when SIP blocks it. `space:changed` fires on a desktop switch.

**USB:** `usb.list()` is `{ name, vendor, vendorID, productID }[]`. `usb:changed` is the same plus `action: "add"|"remove"`.

**HID:** `hid.list(filter?)` is HID devices (`name`, `vendor`, `vendorID`, `productID`, `usagePage`, `usage`, `serial`, `path`, max report sizes). `hid.open(filter)` returns the same plus `id`, or `null`. Filter is `{ vendorID, productID, usagePage, usage, serial, path, vidpid }` or a hidapitester vid/pid string (`"27b8/1ed"`). First byte of send data is the report id (`0` if unused). `sendOutput` / `sendFeature` take a byte array or `"1,99,0,255"` and optional `{ length }` (zero-pads). `readFeature(id, reportId, { length })` and `readInput(id, { reportId, length })` return bytes or `null`. `listen(id)` emits `hid:input` as `{ id, reportId, data }`. `close(id)` / `unlisten(id)` / `reportDescriptor(id)`.

**Shortcuts:** `shortcuts.list()` and `shortcuts.run(name)` call `/usr/bin/shortcuts` and both resolve.

**Power:** `preventSleep` / `allowSleep` / `isPreventing`, plus `lock()`, `sleep()`, `displaySleep()`, `screensaver()`, `logOut()`, `restart()`, and `shutdown()`. Events: `system:sleep`, `system:wake`, `system:lock`, `system:unlock`.

**Dialog:** `alert(message)`, `confirm(message)`, and `prompt(message, default?)` are blocking NSAlert sheets, same as the browser. They also live on `macotron`. Cancel on `confirm` is `false`; cancel on `prompt` is `null`.

**Keyboard:** `macotron.keyboard.on("Tile Left", "ctrl+opt+left", callback)` — the id is the Settings label and is unique per plugin; override the combo in Settings → Plugins. `keyboard.flags()` is `{ cmd, shift, ctrl, opt, caps, fn }`.

**Event:** `macotron.event.post({ type: "click"|"key"|"unicode"|"scroll", ... })` posts HID. `event.tap(["flagsChanged","scroll"], cb)` listens; return `false` to swallow. Coords are Cocoa (same as `window.frame`). `macotron.mouse.location()`, `.warp(x, y)`, `.buttons()`.

**Display:** `list()` is `{ id, width, height, main, frame, visibleFrame, scale, rotation, builtin, mirrored, serial, mm }`. `display:changed` fires with `{ id, flags }` (`add`, `remove`, `move`, `main`, `mode`, `enable`, `disable`, `mirror`, `unmirror`, `shape`). `getBrightness` / `setBrightness`, `setXDREnabled`. `setGamma({ red, green, blue }, black?, id?)` writes the display LUT (omit `id` for every screen). Red-only night vision is `setGamma({ red: 1, green: 0, blue: 0 })`. Extra-dark (below hardware min) is a lowered white point with black at 0. Invert is swapped white and black. `restoreGamma()` puts ColorSync back. Plugin unload also restores ColorSync.

**Shell:** `macotron.shell.run(cmd, args)` — first call to an unapproved command prompts Allow Once / Always Allow / Deny.

**Files:** `read`, `readBytes` (base64), `write`, `exists`, `list`, `watch`, `rename(from, to)`. Paths expand `~`. `rename` fails if `to` already exists.

**Clipboard:** `text()`, `set(text)`, `setImage(base64)`, `clear()`, `types()`, `data(uti)` (base64 or `null`). `clipboard:changed` is `{ changeCount, types }`. History: `history()`, `paste(id)`, `remove(id)`, `clearHistory()`. Recording is off until a consumer opts in — a `clipboard:changed` listener, a `history()` call, or `modules.clipboard.history: true`. Items marked `org.nspasteboard.ConcealedType`, `TransientType`, or `AutoGeneratedType` (password managers) are never recorded. History keeps at most 50 items for at most 24 hours.

**Calendar:** `upcoming({ hours })` resolves with `{ id, title, start, end, allDay, location, calendar, url }[]`. Times are epoch ms. `url` is the join link -- the first URL in the event's URL field, location, or notes, preferring a known meeting host (Meet, Zoom, Teams, Webex) -- or `""`.

**Reminders:** `list({ days, completed })` resolves with `{ id, title, due, completed, list }[]`. `due` is epoch ms or `null`. Incomplete only unless `completed: true`. `add({ title, due?, list? })` and `complete(id, on?)` are local writes, so they return `{ ok, id?, error? }` directly. macOS prompts for Reminders access on first use.

**HomeKit:** `available()` is true when `HMHomeManager` is present (including with no homes). On native macOS the public HomeKit framework is unavailable, so `homes()` is `[]` and `set` returns `{ ok: false, error }`. `accessories(homeId?)` is `{ id, name, room, type, on?, value?, reachable }[]`. Lights and switches include `on`; sensors may include `value`.

**Dock:** `badges()` is `{ app, bundleID?, badge }[]` for Dock tiles that show a badge. Needs Accessibility. Empty when untrusted.

**MenuBar:** `macotron.menubar.add(id, config)` (rows in the Macotron menu; `menu` is a nested dropdown), `.status(id, config)` (extra item next to the Macotron icon: `title`, `subtitle`, `color`, `subtitleColor`, `bold`, `italic`, `secondary`, `minWidth` in points, `sfSymbol`, `image` file path, `onClick`, `menu`), `.update`, `.remove`, `.setIcon`, `.setIconColor(color)` (named or `#RRGGBB`; `null` restores the system tint), `.setTitle`. Two-line extras use the same size and color for both lines unless `secondary` is set (smaller, dimmer subtitle).

**Notify:** `macotron.notify.show(title, body, { sound, subtitle, id, url })` is a system banner. Clicking a banner with a `url` opens it; the URL rides in the notification itself, so the click works even after Macotron restarts. `macotron.notify.toast(title, body?, { position: "top"|"bottom", duration, sfSymbol, color })` is a one-line HUD centered at the bottom (or top) of the screen under the cursor, inset 48pt from the edges. Default duration is 3000ms. `color` is `info` (label color, no icon), `success` (green check), `error` / `failure` (red x), `warning` (orange triangle), a name (`green`), or `#RRGGBB`. Pass `sfSymbol` to override the default icon.

**Checks:** `macotron.checks([{ title, ok, message }])` replaces this plugin's Checks list in Settings → Plugins. A row with `ok: false` shows an orange warning on the plugin (red stays a JS load error). Pass `[]` to clear. Call again when the status changes.

**Settings:** `macotron.settings.open()` opens Settings → Plugins on the calling plugin.

**Schedule:** `macotron.every(30_000, fn)` repeats every 30s. `macotron.every("1h", fn)` fires each local hour at :00; `"15m"` is :00, :15, :30, :45. `macotron.at("1pm", fn)` runs daily at 13:00; pass `{ weekdays: [1,2,3,4,5] }` (JS `getDay()`, 0=Sun) before the callback for weekdays only. Both return `stop()`. Reload cancels all jobs.

**Screen:** `macotron.screen.capture()` resolves with a full-display PNG (base64), and rejects if the capture fails. `capture({ selection: true })` lets the user drag a rectangle. `pickColor()` opens the system magnifier eyedropper and returns `{ hex, r, g, b, x, y }` or `null` if cancelled.

**QR:** `qr.detect({ image }` / `{ path })` is the first QR payload, or `null`. `qr.scan({ camera: true })` opens a camera preview until a code is found or cancelled. `qr.scan({ screenshot: true })` (default) uses a screen selection; `selection: false` is the full display. `qr.image(text)` is a PNG (base64). `qr.show(text)` floats that image in a window.

**Panel:**

```js
const id = macotron.panel.open({ title: "Chat", width: 420, height: 520, html: "<p>Hi</p>", glass: true });
macotron.panel.close(id);
macotron.panel.focus(id); // brings an open panel forward; false if it is gone
macotron.panel.postMessage(id, data);
macotron.panel.onMessage(id, (data) => { /* ... */ });
```

`html` is inserted into a host document (system font, padding, light/dark). `rawHtml` is a full document, the old `html` behavior. `url` loads an http(s) page first-party, so its site storage (localStorage) persists across opens — prefer it over an iframe for embedding a website. `glass: true` or `"regular"` is Liquid Glass; `"clear"` is the clearer Liquid Glass; `"translucent"` is a HUD blur (not glass). `frameless: true` hides the title bar (Escape closes; `escapeCloses: false` makes the panel wait for a click on your own button). `closeOnBlur: true` closes when the panel loses key focus. Host `html` pages get a transparent background so the chrome shows through. In the page, `close()` closes the panel. `panel:closed` fires with `{ id }` when a panel goes away.

Host CSS defines system colors as variables: `--macotron-accent`, `--macotron-accent-text`, `--macotron-label`, `--macotron-secondary-label`, `--macotron-fill`, `--macotron-control`, `--macotron-control-text`, `--macotron-control-border`, `--macotron-field`, `--macotron-field-text`, `--macotron-selected`, `--macotron-selected-text`, `--macotron-link`. They follow the system appearance. `button.primary` uses the accent color.

`panel.open` also accepts `id` (reuse), `fullscreen` (stretch to the screen edges), and `qr` (append a QR PNG).

**Window restore:** `macotron.window.restore([{ app, title, frame }])` matches by app and title, then moves. IDs change after a restart.

**Hyper key:** `keyboard.setHyperKey("caps")` makes Caps Lock mean Command+Shift+Control+Option. Combos use `hyper+h`.

**Plain paste:** `clipboard.setPastePlain(true)` makes Command-V paste text only.

**Menu bar graphs:** `menubar.status` accepts `sparkline: { values }` or `svg`.

**Display modes:** `display.nightShift`, `trueTone`, and `grayscale` plus the matching `set*` calls.

**URL routing:** `url.on("https", "example.com", callback)` matches the host and its subdomains. Pass a `RegExp` to match hosts by pattern. `url.onFallback` handles misses.

**AX:** `ax.focused`, `selectedText` (a promise — reading it can poll a Chromium tree for up to 300ms), `children`, `parent`, `press`, `setValue`, `find`.

**Camera / record / share:** `camera.preview`, `audio.record`, `share.airDrop`.

**localStorage:** Standard web API backed by JSON under the workdir data store.

**Keychain:** `macotron.keychain.get(key)`, `.set(key, value)`, `.delete(key)`, `.has(key)`

**AI:** See [05-ai-integration.md](05-ai-integration.md).
