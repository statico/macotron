# Async API changes

JS APIs whose signature changed when the PIM modules stopped blocking the main
thread. Every one of these now returns a promise; `--check` resolves it with the
stub value it used to return.

```
macotron.notes.list()            -> Promise<Note[]>     (was: sync Note[])
macotron.notes.open(id)          -> Promise<void>       (was: sync void)
macotron.reminders.list(opts?)   -> Promise<Reminder[]> (was: sync Reminder[])
macotron.calendar.upcoming(opts?)-> Promise<Event[]>    (was: sync Event[])
macotron.contacts.list()         -> Promise<Contact[]>  (was: sync Contact[])
macotron.contacts.search(query)  -> Promise<Contact[]>  (was: sync Contact[])
```

Unchanged and still synchronous: `macotron.reminders.add()` and
`macotron.reminders.complete()`. Both are local EventKit writes, not the
multi-second reads this pass was about.

Also out of scope but now stale: `docs/04-modules.md` still describes
`macotron.notes.list()`, `macotron.contacts.list()` and `.search()` as returning
arrays, and `site/workdir/plugins/` holds pre-async copies of the example
plugins.
||||||| ee21888
# Async API changes

JS APIs that now return a Promise. `macotron.d.ts` still describes the old
signatures — update it there.

| API | Was | Now | Notes |
| --- | --- | --- | --- |
| `macotron.screen.capture()` | `string` (base64 PNG), synchronous | `Promise<string>` | `capture({ selection: true })` was already a Promise. A failed capture used to log and resolve to `""`; it now rejects with `screen.capture failed: …`. |
| `macotron.ax.selectedText()` | `string \| null`, synchronous | `Promise<string \| null>` | Blocked the main thread for up to 300 ms polling a Chromium accessibility tree; the poll now runs off-main. |

Plugins updated: `Examples/plugins/translate.js` (awaits `ax.selectedText()`).
`ocr.js` and `screen-ai-summary.js` already awaited `screen.capture`.
`docs/04-modules.md` also documents `screen.capture()` as returning a PNG
directly.

# Async API changes

JS APIs whose signature changed when their native bridge stopped blocking the
main thread.

```
macotron.http.get(url, opts?) -> Promise<{status, body, headers}>              (was: sync {status, body, headers})
macotron.http.post(url, body, opts?) -> Promise<{status, body, headers}>       (was: sync {status, body, headers})
macotron.http.put(url, body, opts?) -> Promise<{status, body, headers}>        (was: sync {status, body, headers})
macotron.http.delete(url, opts?) -> Promise<{status, body, headers}>           (was: sync {status, body, headers})
macotron.bonjour.browse(type, opts?) -> Promise<Array<{name, type, host, port, txt}>>  (was: sync array)
macotron.appletv.list() -> Promise<Array<{id, name, host, port, type}>>        (was: sync array)
macotron.appletv.send(id, command) -> Promise<{ok, error?}>                    (was: sync {ok, error?})
```

None of the resolved shapes changed. A failed HTTP request still resolves with
`status: 0` and the message in `body` rather than rejecting, so plugins keep
their single status check.

# Async API changes

JS APIs whose signature changed when their blocking work moved off the main
thread. For `macotron.d.ts`.

```
macotron.network.wifiSSID()          -> Promise<string | null>       (was: sync string | null)
macotron.network.wifi()              -> Promise<WifiStatus>          (was: sync WifiStatus)
macotron.network.setWifi(on)         -> Promise<WifiResult>          (was: sync WifiResult)
macotron.network.bluetooth()         -> Promise<BluetoothStatus>     (was: sync BluetoothStatus)
macotron.network.setAirDrop(mode)    -> Promise<AirDropResult>       (was: sync AirDropResult)
macotron.network.ping(host?)         -> Promise<PingResult>          (was: sync PingResult)
macotron.system.processes(limit?)    -> Promise<Process[]>           (was: sync Process[])
macotron.system.setLowPowerMode(on)  -> Promise<LowPowerResult>      (was: sync LowPowerResult)
macotron.system.setDarkMode(on)      -> Promise<DarkModeResult>      (was: sync DarkModeResult)
macotron.shortcuts.list()            -> Promise<string[]>            (was: sync string[])
macotron.shortcuts.run(name)         -> Promise<boolean>             (was: sync boolean)
```

Resolved values are unchanged; only the wrapper is new.

## Deliberately left synchronous

| API | Why |
| --- | --- |
| `macotron.network.setBluetooth(on)` | A dlsym'd `IOBluetoothPreferenceSetControllerPowerState` call. No subprocess, no XPC. |
| `macotron.network.airDrop()` | Reads `com.apple.sharingd`'s `DiscoverableMode` from `UserDefaults`. Only the setter has to `killall sharingd`. |
| `macotron.network.interfaces()`, `counters()`, `macotron.system.network()` | `getifaddrs(3)`, an in-process syscall. |
| `macotron.system.darkMode()` | Dlsym'd `SLSGetAppearanceThemeLegacy`, falling back to a `UserDefaults` read. |
| `macotron.system.gpu()` | `MTLCreateSystemDefaultDevice` plus one IORegistry property copy. Microseconds. |
| `macotron.system.fans()` | Two to six SMC reads over `IOConnectCallStructMethod`, each well under a millisecond. `setFanFloor` is the one that goes to the privileged helper, and it is already a promise. |
| `macotron.system.battery()`, `cpu()`, `memory()`, `disk()`, `focus()` | IOKit / mach / `URLResourceValues` reads, all in process. |
