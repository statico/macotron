# Plugin catalog and on-disk integrity

Date: 2026-08-20

## Goal

Users install bundled built-in plugins from a catalog (first launch, before permissions, and later from Settings). Plugins on disk only execute after the user has approved those exact bytes, unless Hot Reload is on.

## Threat model

Another process can rewrite `plugins/*.js`. `settings.json` is not a trust store. Last-approved SHA-256 hashes live in the Keychain.

## Policy

- Failed LLM pass or missing Apple Intelligence: quarantine; explicit **Install/Run Anyway**.
- Hot Reload off + hash mismatch while running: keep the in-memory plugin; **Review & Reload**.
- Cold start + hash mismatch or no hash (after grandfathering): do not execute.
- Hot Reload on: reload immediately, no scan; orange menu-bar dot.
- Community plugins: later, not now.

## Catalog

`Resources/Catalog/catalog.json` plus bundled `Examples/plugins/*.js`. Entries: filename, highlighted, category. Parse title, description, permissions from source without eval.

Overwrite: warn if destination exists; stronger copy if SHA ≠ bundled catalog SHA.

Highlighted rows first, then the rest by title. Install is per plugin.

Wizard: Welcome → Folder → Choose Plugins → Permissions → Ready. Catalog is skippable. Wizard window is tall enough to scroll the list.

## Ledger

Keychain account `macotron.plugin.hash.<filename>` holds lowercase hex SHA-256. First upgrade with an empty ledger snapshots current files as approved.

`executeFile` loads only if Hot Reload is on, the SHA matches, or the user overrode after scan. Otherwise skip eval and record pending review.

## Scanner

Three independent `LanguageModelSession`s. Source is untrusted prompt data inside `<UNTRUSTED_PLUGIN_SOURCE>`. Never put source in instructions.

Chunk with `tokenCount(for:)` against `contextSize`, ~200 token overlap, headroom for instructions. Fall back to character windows when the model API is missing. Any failing chunk or pass fails the scan. Deterministic flags (`eval(`, large encoded blobs) fail into the same UI.

`@Generable` result: `{ approved, findings }`. Guardrail or parse errors fail that pass.

CI does not require Apple Intelligence.
