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
