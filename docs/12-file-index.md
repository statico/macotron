# File Index

Macotron finds files the way Raycast 2 does: its own index, not Spotlight.
Spotlight's `mdfind` costs 0.3–1.2 s for any common three-letter prefix on a
busy disk, because it materialises every hit (20k for `con`) before the
launcher can rank them. An in-memory name index answers in milliseconds.

## Pieces

- `Indexer/` — a Rust crate that builds `macotron-index`, a separate process
  that walks the configured roots, keeps the entries in memory, watches them
  with FSEvents, and answers searches over stdin/stdout.
- `Sources/Modules/FileIndex.swift` — the host-side client. Spawns the
  process from the app bundle, restarts it if it dies, and serialises requests.
- `Sources/Modules/FilesModule.swift` — `macotron.files.*`, the JS surface.
- `Examples/plugins/file-search.js` — the built-in plugin: launcher rows,
  settings, recent files, actions.
- `macotron.spotlight.search` stays as-is for content search and as a fallback
  when the indexer is missing.

## Building

`make build` runs `cargo build --release --manifest-path Indexer/Cargo.toml`
before `swift build`; `make bundle` copies the binary into
`Macotron.app/Contents/MacOS/macotron-index` and signs it. A Rust toolchain is a
build-time dependency only: the shipped app has no runtime dependency beyond
the binary it carries. The GitHub macOS runners ship rustup, so CI needs no
extra step.

When the binary is not in the bundle (`swift run`, tests, SearchProbe) the host
looks at `$MACOTRON_INDEXER`, then `Indexer/target/release/macotron-index`
relative to the working directory.

## Protocol

Newline-delimited JSON. One request per line on stdin, one response per line on
stdout, matched by `id`. The process never writes anything unsolicited to
stdout; diagnostics go to stderr. Every response carries `id` and `ok`; a
failure is `{"id":n,"ok":false,"error":"..."}`.

### configure

```json
{"id":1,"op":"configure","roots":["/Users/ian","/Applications"],
 "ignore":["node_modules","*.tmp","Library/Caches"],
 "hidden":false,"ignoreFiles":true}
```
→ `{"id":1,"ok":true}`

Replaces the configuration. Starts a background index build if the roots or
rules changed (or none exists yet); a call with identical settings is a no-op.
Searches during a build answer from the previous index (empty on first run)
and report `"indexing":true`; `status.roots` likewise reflects the live index
until the build lands.

- `roots`: absolute paths. `~` is expanded by the host, not the indexer.
- `ignore`: gitignore-style globs, matched against the path relative to the
  root that contains it and against the bare name. `node_modules` skips every
  folder of that name; `Library/Caches` skips that one relative path.
- `hidden`: index names starting with `.`. Default false.
- `ignoreFiles`: honour `.gitignore`, `.ignore` and `.macotronignore` found
  during the walk. Default true.

Always skipped regardless of settings: the contents of bundles (`.app`,
`.framework`, `.bundle`, `.xcodeproj`, `.xcassets`, `.photoslibrary`,
`.musiclibrary`, `.tvlibrary`, `.playground`, `.lproj`, `.nib`). The bundle
itself is indexed as one entry. Symlinks are indexed as entries but never
followed.

### search

```json
{"id":2,"op":"search","query":"con","limit":50,
 "folder":"/Users/ian/dev","kind":"pdf","dirsOnly":false}
```
→
```json
{"id":2,"ok":true,"indexing":false,
 "results":[{"path":"/Users/ian/Downloads/contract.pdf","name":"contract.pdf",
             "isDir":false,"score":900,"modified":1725000000}]}
```

`folder`, `kind` and `dirsOnly` are optional. `folder` limits results to that
subtree. `kind` is an extension without the dot, case-insensitive. `limit`
defaults to 50, max 500. An empty query returns `[]`.

Matching, best first, all case-insensitive:

1. exact name
2. name prefix
3. word prefix inside the name (`budget` in `Q3 Budget.pdf`; words split on
   space, `-`, `_`, `.`, and camelCase boundaries)
4. substring of the name
5. subsequence of the name (`ctrct` → `contract`)
6. subsequence of the path relative to its root (`docdad` → `Documents/Dad`)

Tiers 5 and 6 apply only to tokens of three or more characters; a shorter
token must hit tiers 1–4 on the name or the entry does not match. A query with
spaces is a set of tokens that must all match; the score is the sum. In a
multi-token query at least one token must match the name at tier 4 or better,
so a query where every token only matches fuzzily is no match. Ties break on
shallower path, then shorter name, then path order.
Dotted components (`.git`) and anything under `Library` sort below equals.

### status

`{"id":3,"op":"status"}` →
```json
{"id":3,"ok":true,"entries":986092,"indexing":false,"watching":true,
 "roots":["/Users/ian","/Applications"],"lastIndexed":1725000000,
 "memoryBytes":120000000}
```

### reindex

`{"id":4,"op":"reindex"}` → `{"id":4,"ok":true}`. Drops the index and walks
again.

### shutdown

`{"id":5,"op":"shutdown"}` → `{"id":5,"ok":true}`, then the process exits 0.
Closing stdin also exits.

## Budgets

Measured on a home with 986k indexable entries (after skipping caches):

- build: under 3 s, on a background thread, never blocking search requests
- search: under 30 ms for a three-letter query at 1M entries
- memory: under 150 MB resident at 1M entries; store names once with a parent
  reference rather than a full path per entry
- FSEvents changes reflected within 2 s

## JS API

```ts
macotron.files.configure(opts: {
    roots?: string[]; ignore?: string[]; hidden?: boolean; ignoreFiles?: boolean;
}): Promise<void>;
macotron.files.search(query: string, opts?: {
    folder?: string; kind?: string; dirsOnly?: boolean; limit?: number;
}): Promise<Array<{ path: string; name: string; isDir: boolean; score: number; modified: number }>>;
macotron.files.status(): Promise<{
    entries: number; indexing: boolean; watching: boolean; roots: string[];
    lastIndexed: number; memoryBytes: number; available: boolean;
}>;
macotron.files.reindex(): Promise<void>;
```

`available` is false when the indexer binary cannot be found or started; the
plugin then falls back to `macotron.spotlight.search`.

## Plugin settings

Mirrors Raycast's File Search settings, using Macotron plugin options:

| option | type | default |
|---|---|---|
| `searchScopes` | text, one folder per line | `~` and `/Applications` |
| `ignorePatterns` | text, one glob per line | `node_modules, *.tmp, go/pkg, Library/Caches, Library/Containers, Library/Group Containers, Library/pnpm, Library/Developer/Xcode/DerivedData, Library/Keychains, Library/Cookies, Library/Mail, Library/Messages, Library/Safari, Library/Application Support, Library/Preferences, Library/Saved Application State, Library/HTTPStorages, Library/WebKit, Library/Logs, Library/Biome, Library/Metadata, Library/Accounts, Library/IdentityServices, Library/Suggestions` |
| `includeHidden` | boolean | false |
| `useIgnoreFiles` | boolean | true |
| `contentSearch` | boolean | false; adds Spotlight `kMDItemTextContent` hits below name hits |
| `includeInRootSearch` | boolean | true; when off, files only answer a query starting with the keyword `f ` |
| `maxResults` | number | 8 |

The `Library/*` entries beyond caches mirror what Spotlight hides: keychains,
cookies, mail, messages, app support and state. iCloud Drive
(`Library/Mobile Documents`, `Library/CloudStorage`) stays searchable.

Actions on a row: Return opens, ⌘Return reveals in Finder, ⌥Return shows a
Quick Look preview, ⌘C copies the path. The launcher is the Search Files view:
`f` alone lists recent opens, `f ` before a query searches files only.
Commands: "Reindex Files", "Reset File Ranking". The plugin's Checks row
reports the index state and entry count; it is `ok` whenever the indexer is
available, and carries the error when `configure` rejects a glob. When
`files.search` rejects, the plugin answers from Spotlight until a later
`status()` reports the indexer available again.
