# Built-in Plugin Names Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename built-in plugins, remove demo metadata, combine display effects, and migrate existing installations without data loss.

**Architecture:** `PluginCatalog` supplies the current built-in filenames and derives one-to-one legacy names. `PluginWorkspace` migrates files and filename-based settings before plugin loading. The catalog bundles one `screen-effects.js` file instead of three separate display-effect files.

**Tech Stack:** Swift 6, Foundation, Swift Testing, JavaScript, JSON

## Global Constraints

- Use only macOS APIs and Apple-shipped tools.
- Never overwrite an existing plugin during migration.
- Do not migrate the three old display-effect files.
- Preserve user source edits and filename-based settings for one-to-one moves.
- Use `make build` and the full Swift test suite before completion.

---

### Task 1: Checkpoint the design

**Files:**
- Create: `docs/superpowers/specs/2026-08-21-built-in-plugin-names-design.md`
- Create: `docs/superpowers/plans/2026-08-21-built-in-plugin-names.md`

**Interfaces:**
- Produces: Approved naming, consolidation, and migration rules.

- [ ] **Step 1: Review the design for ambiguous migration rules**

Make sure that the design defines destination conflicts and the three consolidation exceptions.

- [ ] **Step 2: Commit the design and plan**

```bash
git add docs/superpowers/specs/2026-08-21-built-in-plugin-names-design.md \
  docs/superpowers/plans/2026-08-21-built-in-plugin-names.md
git commit -m "Document built-in plugin naming and migration."
```

### Task 2: Add the filename migration

**Files:**
- Modify: `Sources/MacotronEngine/PluginCatalog.swift`
- Modify: `Sources/MacotronEngine/PluginWorkspace.swift`
- Modify: `Sources/MacotronEngine/PluginTrust.swift`
- Modify: `Tests/MacotronTests/PluginCatalogIntegrityTests.swift`

**Interfaces:**
- Produces: `PluginCatalog.legacyRenames()` as `[String: String]`.
- Produces: `PluginWorkspace.migratePluginNames(_:hashStore:)`.
- Consumes: `PluginHashStore`.

- [ ] **Step 1: Write migration tests**

Create temporary workspaces with old plugin files and settings.
Cover a successful move, an existing destination, settings keys, shortcut IDs,
favorite IDs, disabled names, and approved hashes.

```swift
let renames = ["demo-weather.js": "weather.js"]
workspace.migratePluginNames(renames, hashStore: hashes)
#expect(FileManager.default.fileExists(atPath: workspace.pluginsDir.appending(path: "weather.js").path))
```

- [ ] **Step 2: Run the focused tests**

```bash
swift test --build-path /tmp/macotron-build --filter PluginCatalog
```

Expected result: the new migration tests fail because the migration API does not exist.

- [ ] **Step 3: Implement the migration**

Move each source only when the destination does not exist.
Rewrite exact filenames and IDs that start with `<old filename>/`.
Copy the approved hash to the new filename and remove the old hash.

```swift
public func migratePluginNames(
    _ renames: [String: String],
    hashStore: PluginHashStore = PluginTrust.store
)
```

Call this function from `ensureReady()` after `settings.json` exists.

- [ ] **Step 4: Run the focused tests**

```bash
swift test --build-path /tmp/macotron-build --filter PluginCatalog
```

Expected result: all focused tests pass.

- [ ] **Step 5: Commit the migration**

```bash
git add Sources/MacotronEngine/PluginCatalog.swift \
  Sources/MacotronEngine/PluginWorkspace.swift \
  Sources/MacotronEngine/PluginTrust.swift \
  Tests/MacotronTests/PluginCatalogIntegrityTests.swift
git commit -m "Migrate installed built-in plugins to functional names."
```

### Task 3: Rename catalog plugins and combine Screen Effects

**Files:**
- Rename: `Examples/plugins/demo-*.js` to `Examples/plugins/*.js`
- Delete after merge: `Examples/plugins/night-vision.js`
- Delete after merge: `Examples/plugins/gamma-black.js`
- Delete after merge: `Examples/plugins/display-modes.js`
- Create: `Examples/plugins/screen-effects.js`
- Modify: `Resources/Catalog/catalog.json`
- Modify: `Sources/MacotronEngine/PluginCatalog.swift`

**Interfaces:**
- Removes: `CatalogPlugin.kind` and `CatalogPlugin.isStock`.
- Keeps: `CatalogPlugin.highlighted`.

- [ ] **Step 1: Rename all plugin files**

Use `git mv` for each `demo-*.js` file.
Do not rename the three consolidated files to their final standalone names.

- [ ] **Step 2: Create Screen Effects**

Combine the command implementations without changing command names.

```javascript
macotron.plugin({
  title: "Screen Effects",
  description: "Control color, gamma, and system display effects.",
});
```

- [ ] **Step 3: Simplify catalog metadata**

Remove every `kind` property from `catalog.json`.
Remove `kind` and `isStock` from `CatalogPlugin`.
Sort highlighted plugins first, then sort by title.

- [ ] **Step 4: Run catalog and gamma tests**

```bash
swift test --build-path /tmp/macotron-build --filter PluginCatalog
swift test --build-path /tmp/macotron-build --filter ScreenEffects
```

Expected result: all focused tests pass.

- [ ] **Step 5: Commit the renamed plugins**

```bash
git add Examples/plugins Resources/Catalog/catalog.json \
  Sources/MacotronEngine/PluginCatalog.swift Tests/MacotronTests
git commit -m "Rename built-in plugins and combine screen effects."
```

### Task 4: Update references and verify the bundle

**Files:**
- Modify: `Examples/plugins/README.md`
- Modify: `Tests/MacotronTests/*DemoTests.swift`
- Modify: `Tests/MacotronTests/EventLabelTests.swift`
- Modify: `Tests/MacotronTests/PluginEnableTests.swift`
- Modify: `site/site.js`
- Rename: `site/workdir/plugins/demo-weather.js` to `site/workdir/plugins/weather.js`
- Modify: relevant files under `docs/superpowers/`

**Interfaces:**
- Consumes: Final plugin filenames from Task 3.

- [ ] **Step 1: Replace old filename references**

Search for all remaining old names.

```bash
rg 'demo-[a-z0-9-]+\.js|DemoTests|Demos use' .
```

Update product references. Keep historical prose only when it describes an old release.

- [ ] **Step 2: Rename test suites**

Rename test files and suite names from `*DemoTests` to functional plugin names.
Update fixture paths to the new files.

- [ ] **Step 3: Run all checks**

```bash
make build
swift test --build-path /tmp/macotron-build
make bundle
```

Expected result: the build succeeds, all tests pass, and the app bundle contains no `demo-*.js` files.

- [ ] **Step 4: Commit references**

```bash
git add Examples Tests site docs
git commit -m "Update built-in plugin references."
```
