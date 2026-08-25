# Async API changes

Every API below moved off the main thread and now returns a promise. The
resolved shapes are unchanged — only the wrapper is new — so a plugin usually
needs one `await` added and nothing else. `--check` resolves each one with the
stub value it used to return synchronously.

Plugins are wrapped in a plain IIFE (`Engine.isolatedPlugin`), so **top-level
`await` is not available**. Use `.then()`, or an `async function` you call.

## Now promises

```
macotron.http.get(url, opts?)          -> Promise<{status, body, headers}>
macotron.http.post(url, body, opts?)   -> Promise<{status, body, headers}>
macotron.http.put(url, body, opts?)    -> Promise<{status, body, headers}>
macotron.http.delete(url, opts?)       -> Promise<{status, body, headers}>

macotron.bonjour.browse(type, opts?)   -> Promise<Array<{name, type, host, port, txt}>>
macotron.appletv.list()                -> Promise<Array<{id, name, host, port, type}>>
macotron.appletv.send(id, command)     -> Promise<{ok, error?}>

macotron.notes.list()                  -> Promise<Note[]>
macotron.notes.open(id)                -> Promise<void>
macotron.reminders.list(opts?)         -> Promise<Reminder[]>
macotron.calendar.upcoming(opts?)      -> Promise<Event[]>
macotron.contacts.list()               -> Promise<Contact[]>
macotron.contacts.search(query)        -> Promise<Contact[]>

macotron.network.wifiSSID()            -> Promise<string | null>
macotron.network.wifi()                -> Promise<WifiStatus>
macotron.network.setWifi(on)           -> Promise<WifiResult>
macotron.network.bluetooth()           -> Promise<BluetoothStatus>
macotron.network.setAirDrop(mode)      -> Promise<AirDropResult>
macotron.network.ping(host?)           -> Promise<PingResult>

macotron.system.processes(limit?)      -> Promise<Process[]>
macotron.system.setLowPowerMode(on)    -> Promise<LowPowerResult>
macotron.system.setDarkMode(on)        -> Promise<DarkModeResult>

macotron.shortcuts.list()              -> Promise<string[]>
macotron.shortcuts.run(name)           -> Promise<boolean>

macotron.screen.capture()              -> Promise<string>
macotron.ax.selectedText()             -> Promise<string | null>
```

Two behaviour changes beyond the wrapper:

- `screen.capture()` now **rejects** on failure. It used to log and resolve to
  `""`, which made a broken capture look like an empty screen.
- A failed `http.*` request still **resolves** with `status: 0` and the message
  in `body`. Plugins keep their single status check rather than needing both a
  status check and a `catch`.

## `macotron.launcher.query(id, fn)`

`fn(query)` may now return a promise of rows as well as a row array. The
launcher does not wait on it: the keystroke is answered with whatever is ready,
and late rows are pushed in when the promise settles, by the same path
`macotron.launcher.set()` uses. A promise that settles for a query the user has
already typed past is discarded; a rejected promise clears that provider's rows.

Returning a plain array still works exactly as before.

## Deliberately left synchronous

Converting these would have been churn for no gain — each is an in-process call,
not a subprocess, XPC round trip, or network request.

| API | Why |
| --- | --- |
| `macotron.system.fans()` | Two to six SMC reads over `IOConnectCallStructMethod`, each well under a millisecond. `setFanFloor` is the one that goes to the privileged helper, and it was already a promise. |
| `macotron.system.gpu()` | `MTLCreateSystemDefaultDevice` plus one IORegistry property copy. |
| `macotron.system.darkMode()` | Dlsym'd `SLSGetAppearanceThemeLegacy`, falling back to a `UserDefaults` read. |
| `macotron.system.battery()`, `cpu()`, `memory()`, `disk()`, `focus()` | IOKit / mach / `URLResourceValues` reads, all in process. |
| `macotron.system.network()`, `network.interfaces()`, `network.counters()` | `getifaddrs(3)`, one syscall. |
| `macotron.network.setBluetooth(on)` | A dlsym'd `IOBluetoothPreferenceSetControllerPowerState` call. |
| `macotron.network.airDrop()` | Reads `com.apple.sharingd`'s `DiscoverableMode` from `UserDefaults`. Only the setter has to `killall sharingd`. |
| `macotron.reminders.add()`, `reminders.complete()` | Local EventKit writes, not the multi-second reads this pass was about. |
