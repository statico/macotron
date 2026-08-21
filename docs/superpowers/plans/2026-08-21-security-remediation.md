# Security Remediation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close every actionable security finding from the two independent audits so approval, consent, and native lifetime match what the docs claim.

**Architecture:** Bind executed bytes to the Keychain ledger (source, cache, imports, scan). Keep Hot Reload out of the workdir. Enforce shell approval and dry-run checking. Isolate host trust state from plugins. Then harden runtime, privacy metadata, and the release path.

**Tech Stack:** Swift 6, QuickJS-ng, Keychain, TCC, Swift Testing, `make`

**Sources:** [GPT-5.6 Sol security review](92d084fd-34d5-4b30-a5c5-10b00dfdea81) (canvas + 5-phase ledger) and [Composer security review](2d020d0a-8106-409c-8e7b-5a122eb08de3) (re-evaluation + implementation plan). Deduplicated against HEAD after `a47a369`.

## Global Constraints

- Built-in host APIs and bundled plugins must work on a stock Mac with Macotron installed.
- No Homebrew, npm, or other third-party binaries.
- `make build` stays clean; add tests that fail if a bypass reopens.
- Do not split the shared JavaScript realm in this plan. Document that all plugins are one trust domain until a later project.
- Keep TCC inheritance for `shell.run` children. The shell prompt is the consent point.
- Interactive shell approval: Allow Once / Always Allow / Deny, persisted in `security.shell.allow`.
- Commit after each numbered item.

## Already done (do not redo)

| Finding | Evidence |
|---|---|
| Debug HTTP RCE | `d6637e9` deleted `DebugServer.swift` and Makefile targets |
| Camera in type unions | `macotron.d.ts` includes `"camera"` |
| Bluetooth TCC crash | `a47a369` added `NSBluetoothAlwaysUsageDescription` |

## Document, do not “fix”

These stay product decisions unless a later spec changes them:

- Shared QuickJS context for all plugins
- Event-tap swallow / keylogging power (reclassify as dangerous; keep the API)
- `url.open` scheme allowlists
- localStorage namespacing
- One-time `grandfatherIfEmpty` on first upgrade after the ledger service split

---

## Phase 0 — Bind approval to everything executed

Highest ROI. The ledger is theater until these four paths close.

### 0.1 Session-only Hot Reload

**Why (Composer):** `ui.hotReload` in workdir `settings.json` is writable by any approved plugin (`fs.write`) or local process. FSEvents re-applies it and skips the hash gate.

- [ ] Stop writing/reading `hotReload` from settings. Keep it on `moduleManager` / `settingsState` only. Default `false` at launch.
- [ ] Ignore any leftover `ui.hotReload` key. Menu toggle stays session-only; orange menu-bar dot stays.

**Files:** `Sources/Macotron/AppDelegate.swift`, `Sources/MacotronEngine/SnippetManager.swift`

**Test:** Write `ui.hotReload: true` into settings, fire disk change, drop unapproved JS → still `pendingReview`, not executed.

### 0.2 Bytecode cache keyed by source hash

**Why (both):** Trust checks `.js`, then loads `.cache/*.iife.bc` when mtime ≥ source mtime. Crafted bytecode for an approved name bypasses the scan and the hash.

- [ ] Cache path: `cacheDir/<filename>.<sha256(source)>.iife.bc` using `PluginHash.sha256`.
- [ ] Delete sibling caches for that filename on write. Reject any cache whose name does not match current source hash.

**Files:** `Sources/MacotronEngine/SnippetManager.swift`

**Test:** Plant a `.bc` next to approved source with a different hash → must not execute.

### 0.3 Hash-gate ES imports under the workdir

**Why (both):** `setupModuleLoader` compiles any resolved path. `plugins/lib/util.js` is not a plugin file and is never hashed.

- [ ] If the resolved path is under `moduleBaseDir`, require `PluginTrust.matches` on a workdir-relative key.
- [ ] On review/approve, walk static `import` paths in the reviewed source and approve those files too.
- [ ] Bundle `macotron-runtime.js` stays ungated.

**Files:** `Sources/MacotronEngine/Engine.swift`, `Sources/MacotronEngine/PluginTrust.swift`, review/install in `AppDelegate.swift`

**Test:** Approved plugin `import`s unapproved helper → load fails; after helper is approved → load succeeds.

### 0.4 Bind AI scan results to source bytes

**Why (Sol):** `PluginScanReport` has no source hash. `scanCatalogPlugin` matches filename only. A cancelled/restarted review can apply a stale verdict.

- [ ] Put `sourceHash` on the scan request and report.
- [ ] Cancel superseded scans. Approve only when `report.sourceHash == SHA-256(bytes about to write)`.

**Files:** `Sources/MacotronEngine/PluginScan.swift`, `Sources/Macotron/AppDelegate.swift`

**Test:** Start scan on `foo.js`, change bytes, finish old scan → install/review rejected.

### 0.5 Host-only trust ledger

**Why (both):** Ledger accounts `macotron.plugin.hash.*` live in the same Keychain service as plugin secrets. Any plugin can forge, wipe, then `grandfatherIfEmpty`.

- [ ] `KeychainHashStore` uses service `io.statico.macotron.trust`.
- [ ] `macotron.keychain.*` cannot read/write/delete that service. Reject accounts prefixed `macotron.plugin.hash.` as defense in depth.
- [ ] Keep one-time grandfather for upgrades. After the split, an empty ledger with existing plugins is not a silent re-trust.

**Files:** `Sources/MacotronEngine/KeychainStore.swift`, `PluginTrust.swift`, `Sources/Modules/KeychainModule.swift`

**Test:** Plugin `keychain.delete("macotron.plugin.hash.foo.js")` does not change the ledger.

---

## Phase 1 — Repair native memory lifetime

Independent of product policy. Do before more async work.

### 1.1 Cancel async QuickJS work before `reset()`

**Why (Sol):** Shell, screen, QR, OCR, AI, and similar capture raw `JSContext` / promise values. Reload calls `JS_FreeContext` while those complete.

- [ ] Runtime generation counter on `Engine`.
- [ ] Async native ops capture generation. Before `JS_FreeContext`, cancel/drain in-flight work and reject stale completions.

**Files:** `Sources/MacotronEngine/Engine.swift`, `Sources/Modules/ShellModule.swift` and other async bridges

**Test:** Start `shell.run`, reload during flight → no crash; promise rejects.

### 1.2 Stop storing native pointers in writable JS

**Why (Sol):** `$$__fsModule` is a float64 global later passed to `Unmanaged.fromOpaque`.

- [ ] Engine-owned registry keyed by watcher id. JS cannot overwrite a native pointer.

**Files:** `Sources/Modules/FileSystemModule.swift`

**Test:** Mutate `$$__fsModule` then `fs.watch` → safe error, no SIGSEGV.

---

## Phase 2 — Make documented consent real

### 2.1 Shell approval and argv spawn

**Why (both):** Docs promise Allow Once / Always Allow / Deny. `ShellModule` never consults the allowlist and runs `/bin/zsh -c`.

- [ ] Before spawn: built-in safe set, then `security.shell.allow`. Strict mode denies unlisted commands.
- [ ] Else `NSAlert` with plugin filename + full command. Always Allow appends to `security.shell.allow`.
- [ ] Identify by canonical executable path. Invoke argv, not `zsh -c` concatenation.

**Files:** `Sources/Modules/ShellModule.swift`, `Sources/Macotron/AppDelegate.swift`, `docs/06-security.md`

**Test:** Unlisted `curl` prompts; Deny blocks; Always Allow persists; strict mode throws without a prompt.

### 2.2 `--check` has no side effects

**Why (both):** `PluginChecker` evaluates any path with no `PluginTrust` check. Shell, FS write, HTTP, Keychain, Window, Dialog, App launch, and more ignore `dryRun`. Workdir `AGENTS.md` still tells agents to `--check` after every edit.

- [ ] Keep evaluate-based checking (needed so `macotron.plugin()` / `command()` register).
- [ ] Stub every mutating bridge when `engine.dryRun` is true: shell, fs write/rename/watch, keychain set/delete, http, ai, url.open, shortcuts.run, HID send, notes.open, app launch/quit, window mutators, dialogs, clipboard.set, gamma, OCR/QR scan/show, camera/share.

**Files:** `Sources/Macotron/PluginChecker.swift`, each `Sources/Modules/*Module.swift` missing `dryRun`

**Test:** `--check` on a fixture that calls every dangerous API: zero Process/URLSession/NSAlert/window moves.

### 2.3 Per-plugin permission checks at the bridge

**Why (Sol):** `permissions` only drive Settings UI. After Macotron has TCC, any plugin can use Contacts, screen capture, AX, etc.

- [ ] Track the active plugin’s declared permissions.
- [ ] Sensitive bridges refuse if undeclared, even when the app has TCC.

**Files:** `Sources/MacotronEngine/Engine.swift`, sensitive modules (`Screen`, `AX`, `Contacts`, `Calendar`, `Camera`, `Clipboard.history`, …)

**Test:** Plugin without `screenRecording` cannot `screen.capture` while the app grant exists.

### 2.4 Keychain secrets scoped to the caller

**Why (both):** `keychain.get/set/delete` take arbitrary account names. Shared keys in `AGENTS.md` must still work.

- [ ] Prefix JS accounts with `macotron.plugin.<currentEvaluatingFile>.` unless they start with `shared.`.
- [ ] Update `macotron.d.ts` and `PluginWorkspace.agentsTemplate`.

**Files:** `Sources/Modules/KeychainModule.swift`, `Sources/Macotron/Resources/macotron.d.ts`, `PluginWorkspace.swift`

**Test:** Plugin A cannot read Plugin B’s unprefixed secret; `shared.x` is visible to both.

---

## Phase 3 — Plugin trust boundaries (without splitting the realm)

### 3.1 Panel origin and message owner

**Why (both):** No navigation policy. `webkit.messageHandlers.macotron` survives remote navigation. Global `panel.onMessage` is a cross-plugin broadcast.

- [ ] Block top-level navigation away from `about:blank`. Open http(s) in the default browser.
- [ ] Record owning plugin at `panel.open` / `onMessage`. Dispatch only to that owner.
- [ ] Strip the handler before any permitted remote navigation.

**Files:** `Sources/Modules/PanelHost.swift`, `Sources/Modules/PanelModule.swift`

**Test:** Navigate to `https://evil.test` → messages ignored. Plugin A does not receive Plugin B’s panel messages.

### 3.2 Clipboard history opt-in and concealed types

**Why (both):** History polls every 500 ms for every load. All plugins can `history()`. Password-manager types are recorded.

- [ ] History off until a plugin that is allowed to use it starts (or a user setting).
- [ ] Skip `org.nspasteboard.ConcealedType`, `TransientType`, `AutoGeneratedType`.
- [ ] Cap count and age.

**Files:** `Sources/Modules/ClipboardModule.swift`

**Test:** Concealed pasteboard items never appear in history. No polling when no consumer is loaded.

### 3.3 Notes AppleScript escaping

**Why (Composer):** Note ids interpolated into AppleScript; newlines can break out of the string.

- [ ] Escape `\r`/`\n` in `NotesList.escape` (close quote, `& return &`, reopen).

**Files:** `Sources/Modules/NotesStore.swift` (or `Notes.swift`)

**Test:** Id containing a newline cannot inject AppleScript.

### 3.4 Custom URL events are untrusted

**Why (Sol):** `macotron://` GetURL events carry attacker-controlled path/query with no provenance.

- [ ] Document payloads as untrusted.
- [ ] Require confirmation for dangerous actions driven by URL events. Optional one-time tokens later.

**Files:** `Sources/Modules/URLSchemeModule.swift`, `docs/06-security.md`

---

## Phase 4 — Runtime limits and host robustness

### 4.1 Deadlines and memory on every JS entry

**Why (both):** 5s interrupt covers only initial `evaluate` / bytecode. Timers, events, panel, and promises have none. No `JS_SetMemoryLimit`.

- [ ] `Engine.withDeadline` around timer fire, `EventBus.emit`, panel/HID dispatch, job-queue drain.
- [ ] `JS_SetMemoryLimit` (~512 MB) and `JS_SetMaxStackSize` (~1 MB). Cap timers/listeners/watchers.
- [ ] Convert `http.*` to promises (same pattern as `shell.run`). `weather.js` already `await`s. Remove the main-thread semaphore.

**Files:** `Sources/MacotronEngine/Engine.swift`, `Sources/Modules/HTTPModule.swift`, QuickJS helpers, `macotron.d.ts`

**Test:** Infinite timer is interrupted. `http.get` does not block the main thread. Oversize allocation is rejected.

### 4.2 Cap QR inputs

**Why (Sol):** Base64 images decode fully before Vision. Generated QR size has a min, no max.

- [ ] Cap encoded bytes, decoded dimensions, text length, and generated pixel size.

**Files:** `Sources/Modules/QRModule.swift`, `Sources/Modules/QRCodes.swift`

**Test:** 100 MB base64 is rejected before Vision.

### 4.3 Enforce or delete `sandboxRoot`

**Why (Sol):** Option defaults to `$HOME` and is never applied. Misleading.

- [ ] Either enforce canonical, symlink-safe containment after shell is gated, or remove the option and document native-equivalent FS access.

**Files:** `Sources/Modules/FileSystemModule.swift`, docs

---

## Phase 5 — Privacy metadata, entitlements, release

### 5.1 Usage strings and Apple Events

**Why (Sol):** Screen capture exists without `NSScreenCaptureUsageDescription`. `osascript` paths lack `com.apple.security.automation.apple-events`. Automation is missing from permission UI.

- [ ] Add screen-capture purpose string. Add Apple Events entitlement where `osascript` is used.
- [ ] Surface Automation in Settings permissions.
- [ ] Defer notification authorization until first `notify` use; gate delivery on status.

**Files:** `Resources/Info.plist`, `Resources/Macotron.entitlements`, `Sources/Modules/NotifyModule.swift`, permission UI

**Test:** Plist contains `NSScreenCaptureUsageDescription`. Notify does not prompt at module register.

### 5.2 Hardened runtime and entitlements

**Why (both):** JIT, unsigned executable memory, and `disable-library-validation` are on. Makefile enables hardened runtime only for Developer ID.

- [ ] Drop the three exceptions unless a tested release build proves QuickJS needs them (interpreter path should not).
- [ ] Always pass `--options runtime` when signing, including self-signed.
- [ ] Verify plugins, panels, and the fan helper after the change.

**Files:** `Resources/Macotron.entitlements`, `Makefile`

### 5.3 Build staging, provenance, notarization

**Why (both):** `BUILD_DIR=/tmp/macotron-build`. `make release` is a TODO. QuickJS has a version string but no commit/checksum. C flags use `-w`.

- [ ] Stage under `$(HOME)/Library/Caches/macotron-build` or a private clean root.
- [ ] Record QuickJS upstream commit + checksum; narrow `-w`.
- [ ] `make release`: clean stage, sign nested helper + app, notarize, staple, checksum, expected-file manifest. CI later.

**Files:** `Makefile`, `Package.swift`, `docs/06-security.md`, `docs/09-phases.md`

### 5.4 Tests must not use the login Keychain

**Why (Composer):** Plugin settings tests write real `io.statico.macotron` items.

- [ ] `KeychainStore.serviceName` overridable. Tests use `io.statico.macotron.tests`.

**Files:** `Sources/MacotronEngine/KeychainStore.swift`, `Tests/MacotronTests/PluginSettingsTests.swift`

---

## Phase 6 — Docs, scanner copy, and verification

### 6.1 Honest scanner and security doc

- [ ] Banner: “No issues found by on-device automated checks.” Not “Scanned for safety by AI. Looks good.”
- [ ] Extra static flags: `Function(`, dense `String.fromCharCode`. Document chunk-boundary limits.
- [ ] `docs/06-security.md`: add missing APIs (`ax.*`, contacts, calendar, clipboard.history, camera, share, schedule); reclassify `keychain.get`, `event.tap`/`post`, AirDrop everyone, `ax.setValue`/`press` as dangerous; document shared realm, TCC inheritance, session Hot Reload, trust Keychain service, `--check` dry-run, advisory scan.
- [ ] Update `macotron.d.ts` for http promises and keychain scoping.

**Files:** `CatalogBrowser.swift`, `PluginScan.swift`, `docs/06-security.md`, `macotron.d.ts`

### 6.2 Final verification

- [ ] Tests listed above plus `make build` and a full `swift test`.
- [ ] Manual: fresh workdir → catalog add → edit on disk → Review & Reload → Hot Reload toggle → quit/relaunch (Hot Reload off) → `--check` on a hostile fixture with no side effects.

---

## Ship order

```text
0.1 hotReload → 0.2 cache → 0.3 imports → 0.4 scan hash → 0.5 ledger
     ↓
1.1 async UAF → 1.2 fs pointer
     ↓
2.2 --check dryRun  (can ship with 2.1)
2.1 shell approval → 2.3 permissions → 2.4 keychain namespaces
     ↓
3.x panels / clipboard / notes / URL docs
     ↓
4.x deadlines, HTTP async, QR caps, sandboxRoot
     ↓
5.x plist, entitlements, staging, notarization, test Keychain
     ↓
6.x docs + smoke
```

Phase 0 before 2/3: consent is worthless if bytecode or imports skip the ledger. Phase 1 before 4: limits on a UAF-prone runtime hide crashes.

## Mapping (audit id → this plan)

| ID | Plan |
|---|---|
| hotReload settings bypass | 0.1 |
| bytecode-cache | 0.2 |
| unscanned-imports | 0.3 |
| stale-scan | 0.4 |
| keychain-isolation (ledger) | 0.5 |
| async-uaf | 1.1 |
| fs-pointer | 1.2 |
| shell-policy | 2.1 |
| checker-side-effects | 2.2 |
| permission-model | 2.3 |
| keychain-isolation (secrets) | 2.4 |
| panel-origin / global onMessage | 3.1 |
| clipboard-history | 3.2 |
| Notes AppleScript injection | 3.3 |
| url-events | 3.4 |
| runtime-limits / http sync | 4.1 |
| qr-limits | 4.2 |
| filesystem-root | 4.3 |
| privacy-metadata / notify-consent | 5.1 |
| runtime-entitlements | 5.2 |
| release-pipeline / build-provenance | 5.3 |
| test Keychain pollution | 5.4 |
| scanner copy / docs drift | 6.1 |
| shared-context | document only |
| debug-rce / camera-types / Bluetooth plist | already done |
