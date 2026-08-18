# Plugin API compatibility and agent validation

Date: 2026-08-17

## Goal

The JavaScript API will change over time. Plugins need a clear way to declare what they need, the host needs a way to refuse incompatible plugins, and AI coding agents need a documented way to check that plugin JS is correct before commit.

## Decisions

- Soft + hard compatibility: keep old APIs (or shims) across minor bumps; use a hard `needs` floor so a future host can refuse cleanly.
- Single-file pragma (not `plugin.json` or a package layout).
- Agents validate with both typecheck (`macotron.d.ts`) and a QuickJS load check (`--check`).

## Version model

Two separate versions:

| Field | Meaning |
|-------|---------|
| `macotron.version.app` | App marketing / bundle version (already exists). |
| `macotron.version.api` | Semver of the plugin-facing JS API (new). |

Bump **API version** only when the plugin contract changes:

| Change | Bump |
|--------|------|
| New API or new optional args; old plugins still work | minor |
| Behavior change old plugins can survive with a shim | minor + document deprecation |
| Remove/break a call, or change meaning so a shim is wrong | major |

Per-module `moduleVersion` integers stay internal. Plugins and agents use **API version** only.

### Plugin pragma

At the top of a plugin `.js` file:

```js
// @macotron needs 1.2
// also accepted: 1.2.0
```

Rules:

- Optional. Missing `needs` means `needs 1.0.0` (current baseline).
- Normalize short forms (`1.2` → `1.2.0`) before compare.
- Semver compare: load only if `host.api >= plugin.needs`.
- If unmet: do **not** evaluate the file. Record an error such as `Needs Macotron API 1.2 (this host is 1.0)`. Surface it the same way as load errors (Settings → Plugins, and any existing error UI).
- Soft path: on a minor bump, keep old APIs or thin shims in `macotron-runtime.js`. On a major bump, drop shims and let `needs` refuse old plugins.
- Invalid pragma syntax: treat as a load error (do not eval).

Parse the pragma from the first ~20 lines of the source before eval.

## Agent validation

Two checks, both documented in app-owned `AGENTS.md`. Agents run them after editing a plugin and before committing.

### 1. Typecheck (API misuse)

- On every launch / workdir ensure, copy bundle `macotron.d.ts` to `.cache/macotron.d.ts` (gitignored).
- Seed `.cache/jsconfig.json` with `checkJs` enabled, types pointed at `./macotron.d.ts`, and `include` covering `../plugins/**/*.js`.
- Agents run from the workdir: `npx --yes typescript tsc -p .cache --noEmit` (exact line also in `AGENTS.md`).
- Catches wrong method names and bad arg shapes. The `needs` pragma is a comment; typecheck does not enforce it.

### 2. Load check (syntax + QuickJS)

- App binary flag: `macotron --check [path…]` (or `make check` wrapping it).
- Start engine + runtime + modules; evaluate each plugin **without** installing hotkeys, opening panels, or requesting permissions (stub those side effects).
- Enforce the `needs` pragma the same way as at normal load.
- Exit non-zero if any file fails so agents and CI can gate on it.

Prefer one CLI flag on the existing app binary over a second SwiftPM target (ponytail). Add a separate CLI later only if the flag path is messy.

### AGENTS.md content (additions)

1. Put `// @macotron needs <api>` at the top when using APIs from that version.
2. After edits: typecheck, then `macotron --check plugins/your-file.js`.
3. Commit only if both pass.
4. Do not edit `AGENTS.md` / `CLAUDE.md`.

## Workdir files

| File | Ownership |
|------|-----------|
| `AGENTS.md` / `CLAUDE.md` | App: document pragma, API version, validate steps |
| `.cache/macotron.d.ts` | App: copy from bundle each ensure (gitignored) |
| `.cache/jsconfig.json` | App: seed checkJs config (gitignored) |
| `plugins/*.js` | Agents / humans |

`.gitignore` already ignores `.cache/`.

## Host load path

1. Read plugin source.
2. Parse `// @macotron needs <semver>` from the first ~20 lines.
3. If `needs > apiVersion` → skip eval; push structured error.
4. Else evaluate as a script (current behavior).

## UX

- Failed `needs` or load: same plugin error treatment as today (`hasErrors` + message).
- No separate compatibility settings pane in v1.

## Rollout

1. Introduce `macotron.version.api = "1.0.0"` and pragma parser (missing → 1.0.0).
2. Copy `.d.ts` + jsconfig into `.cache/`; document validate in `AGENTS.md`.
3. Add `--check` dry-run.
4. Later API bumps: minor with shims; major only when willing to refuse old plugins.

## Out of scope (v1)

- Sidecar `plugin.json` / multi-file plugin packages
- Auto-updating plugins for new APIs
- Marketplace version matrix beyond the pragma
- Separate `macotron-cli` SwiftPM product (unless `--check` on the app proves awkward)

## Precedents

Similar ideas elsewhere: Node `engines`, VS Code `engines.vscode`, browser `manifest_version`, Homebrew `depends_on`. Macotron uses a file-top pragma because plugins are single `.js` files without a package manifest.
