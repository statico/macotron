# Host capabilities (2026-08-20)

Implement the APIs below. Stock macOS only. No Homebrew, npm, or third-party binaries.
Match existing module style: C callbacks, `JSBridge`, dry-run returns safe values, `cleanup()` frees taps/windows.
Tests: Swift Testing, extract logic into testable enums. Demo plugins start with `macotron.plugin({ title, description })`.
Do not edit `AppDelegate.swift` or `PluginChecker.swift` unless your file list says so.
Do not commit.

## Shared types live in `Sources/Macotron/Resources/macotron.d.ts`

Follow those signatures exactly.

---

## Window restore — `Sources/Modules/WindowRestore.swift` + `WindowModule.swift`

`macotron.window.restore(entries)` where each entry is `{ app, title?, frame, display? }`.
Match running windows by localized app name (then bundle id if present), then title (exact, else prefix).
Call existing `move` / `moveToFraction` path. Add `bundleID` on `getAll()` / `focused()` when cheap (`NSRunningApplication.bundleIdentifier`).
Return `{ restored, missing }` counts.

Tests: `Tests/MacotronTests/WindowRestoreTests.swift` for the matcher only (no live AX).
Demo: `Examples/plugins/demo-layouts.js` — commands Save Work / Restore Work via `localStorage`.

## Window switcher demo only

`Examples/plugins/demo-window-switcher.js` — Option-Tab via `event.tap`, panel list, `window.focus`.
No new host API. Optional `panel.open({ id })` if panel agent shipped it; else new UUID each show is fine.

---

## Hyper key — `KeyCombo.swift` + `KeyboardModule.swift` + `Sources/Modules/HyperKey.swift`

`KeyCombo.parse("hyper+h")` = cmd+shift+ctrl+opt+h.
`keyboard.setHyperKey("caps"|"fn"|null)` installs a session event tap that maps Caps Lock (or Fn) to those four modifiers while held, and swallows the caps lock lock.
`keyboard.hyperKey()` returns the current key or `null`.
Demo: `Examples/plugins/demo-hyper.js`.
Tests: KeyCombo parse/glyphs for `hyper`.

---

## Gestures — `EventModule.swift` + `Sources/Modules/GestureMonitor.swift`

`event.tap(["swipe"|"magnify"|"rotate"], cb)` also accepts those names.
Use `NSEvent.addGlobalMonitorForEvents` (and local) for `.swipe`, `.magnify`, `.rotate`.
Callback payload: `{ type, fingers, direction, delta, flags }`.
`direction` is `left|right|up|down` for swipe. `delta` is magnification or rotation.
Demo: `Examples/plugins/demo-gestures.js` — 3-finger swipe tiles the focused window.
Tests: payload builder / direction from delta.

---

## Clipboard history UI + plain paste

API already has history. Rewrite `Examples/plugins/demo-clipboard-history.js` to fill `launcher.set`.
`clipboard.setPastePlain(on)` / `isPastePlain()` — on Command-V, rewrite pasteboard to `public.utf8-plain-text` only, then let the paste through. Install a key-down tap. Dry-run is a no-op.
Demo: `Examples/plugins/demo-plain-paste.js`.
Tests: extract the UTI filter / plain-text rewrite helper.

---

## Menu bar sparkline / SVG

`menubar.status` accepts `sparkline: { values, width?, height?, color? }` and/or `svg: string`.
Render to a PNG in `NSTemporaryDirectory()` and pass the existing `imagePath`.
`Sources/Modules/SparklineImage.swift` — `png(values:width:height:color:)` and `png(svg:)`.
`NSImage(data:)` can load SVG on current macOS. Rasterize to PNG.
Demo: `Examples/plugins/demo-cpu-graph.js`.
Tests: sparkline produces non-empty PNG; empty values returns nil.

---

## Display appearance

On `macotron.display`:
- `nightShift()` / `setNightShift(on|{strength})`
- `trueTone()` / `setTrueTone(on)`
- `grayscale()` / `setGrayscale(on)`

Use `dlsym` private APIs (`CBBlueLightClient`, `CGDisplayForceToGray`). If a symbol is missing, return `{ on: false, available: false }` and `set*` returns `{ ok: false, error }`.
Never crash. Demo: `Examples/plugins/demo-display-modes.js`.
Tests: parse setNightShift argument (bool vs `{ strength }`).

---

## URL default handler + fallback

`url.setDefaultHandler(scheme)` / `isDefaultHandler(scheme)` via Launch Services (`LSSetDefaultHandlerForURLScheme` / `LSCopyDefaultHandlerForURLScheme`). Bundle id `io.statico.macotron`.
`url.onFallback(cb)` — if no `url.on(scheme, host)` matches, call fallback with `{ url, scheme, host, path, query, sourceBundle? }`.
If no fallback callback, show a small native picker (Safari / Chrome if present / system default) that calls `url.open`.
Add `http`, `https`, `mailto` to `Resources/Info.plist` `CFBundleURLTypes`.
When a URL arrives and no host rule matches, emit fallback. `url.on("https", "*", cb)` may also register as wildcard.
Demo: `Examples/plugins/demo-browser-picker.js`.
Tests: host match / wildcard / fallback routing (pure functions).

---

## Calendar URL + fullscreen meeting overlay + panel QR + fullscreen

`calendar.upcoming` adds `url` from `EKEvent.url` (absoluteString) or an `https` location.
`panel.open` new opts:
- `id?: string` — reuse that id (close old, reopen)
- `fullscreen?: boolean` — frame = the screen under the cursor (`visibleFrame` is wrong; user asked stretch to the edges → use `screen.frame`)
- `qr?: string` — append a QR `<img src="data:image/png;base64,…">` using existing `QRCodes.png`

Demo: `Examples/plugins/demo-meeting-overlay.js` — 60s before a timed event, fullscreen frameless glass panel with title, countdown, Join if url, and `qr` of the join url.
Keep `demo-meetings.js` as the menu bar plugin.

---

## Deep AX — `Sources/Modules/AXModule.swift` + `AXTree.swift`

`macotron.ax`:
- `focused()` → `{ id, role, title, value, frame }` or null
- `selectedText()` → string or null
- `children(id)` → array of the same shape
- `parent(id)` → same or null
- `press(id)` → bool
- `setValue(id, string)` → bool
- `find({ role?, title? })` → first match under focused app (or system-wide)

Stable `id` can be an incrementing handle table in the module (AXUIElement is not a JS value).
`cleanup()` drops the table.
No demo required. Tests: handle table + attribute mapping from mocks / string role names.

---

## Camera preview + mic record + share

`Sources/Modules/CameraModule.swift`:
- `camera.list()` `{ id, name }[]`
- `camera.preview({ id?, width?, height? })` — NSPanel with AVCaptureVideoPreviewLayer
- `camera.stopPreview()`
- `camera.snapshot()` → PNG base64 or null

`AudioModule`:
- `audio.record({ path })` — AVAudioRecorder, expand `~`
- `audio.stopRecord()` → `{ path, seconds }` or null
- `audio.isRecording()`

`Sources/Modules/ShareModule.swift`:
- `share.services()` names
- `share.open({ files?, text?, url? })` — `NSSharingServicePicker` or share panel from a tiny window
- `share.airDrop(paths)` — `NSSharingService(named: .sendViaAirDrop)`

Permissions: add `microphone` to `Permission` in `Permissions.swift` and parse `"microphone"`. Info.plist `NSMicrophoneUsageDescription`.
Demos: `demo-record.js`, `demo-share.js`.
Tests: path expand, service name list non-empty on macOS, record options parse.

---

## Wiring (controller does this if you do not)

`AppDelegate.registerModules` and `PluginChecker` must `addModule` for `AXModule`, `ShareModule`, `CameraModule`.
`docs/04-modules.md` module table.
