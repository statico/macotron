# Community Plugins

Anyone can publish a Macotron plugin. There is no index file, no review queue,
and no server. An author adds the `macotron-plugin` topic to a GitHub
repository, and the app finds it.

Settings → Plugins → Catalog → **Community** shows the list.

## Rules for an author

1. Name the repository `macotron-plugin-<name>`.
2. Put one plugin in the repository. One plugin, one repository.
3. Put the `.js` file in the root, named `<name>.js`. The app also accepts the
   full repository name, `plugin.js`, or `index.js`.
4. Add the topic `macotron-plugin` to the repository.
5. Write `title` and `description` in `macotron.plugin({...})`. The app shows
   those, not the GitHub description.

`macotron-plugin-weather` holds `weather.js` and installs as `weather.js`. The
app removes a `macotron-plugin-` prefix, and it still accepts the older
`macotron-` prefix and a `-plugin` suffix.

The repository description, the star count, and the last push date come from
the search result.

## Why there is no index

An index file is a list that somebody maintains. GitHub already keeps that
list, and the topic is free to add.

- **One search call.** Unauthenticated search allows 10 calls each minute for
  an IP address. Every user has their own IP address, so one person who
  browses never reaches the limit. The app caches the result for one hour.
- **One plugin for each repository.** The search result carries the name, the
  description, the star count, and the default branch. Listing the files in a
  repository is a second call against the core API, which allows only 60 calls
  each hour.
- **Downloads use the CDN.** `raw.githubusercontent.com` is not the API and
  spends no quota.

Stars sort the list. Stars are not a trust signal: they are bought in bulk.

## Security

A community plugin is unknown code from a stranger. Macotron gives it the same
treatment as a plugin that changed on disk.

1. The app downloads the source. It runs nothing yet.
2. The install sheet names the repository and the author, and states that the
   plugin runs with the same access Macotron has.
3. The Apple Intelligence scan and the static checks run over the bytes.
4. The user approves. Only then does the file reach the workdir, and only then
   does `PluginTrust` record its SHA-256 hash in the Keychain.

Nothing installs by itself and nothing updates by itself.

### Updates

The **Community** list marks an installed plugin **Update** when the published
bytes differ from the copy on disk. The check compares hashes over the CDN, and
it runs only for plugins that are installed. An update opens the same sheet as
a first install, so the user reads the new code before it runs.

### The block list

Delisting a repository stops discovery. It never stops code that is already
installed on a machine. `https://macotron.statico.io/blocked.json` does:

```json
{ "blocked": [{ "sha256": "…", "reason": "Sends the clipboard to a server." }] }
```

The app fetches the file at launch and caches it in Application Support, so a
Mac that starts up offline still refuses. A blocked hash is checked before the
trust ledger and before hot reload. Blocked bytes do not load, do not install,
and cannot be approved with **Run Anyway**.

Add an entry, publish the file, and every Mac stops running those bytes at the
next launch.

## What Macotron does not do

- **No signing and no pinned commit.** The hash check and the review sheet
  catch every change before it runs, which is what a pin buys.
- **No namespace control.** Two repositories can carry the same name. The app
  shows the owner, and an install over an existing file warns first.
- **No permission enforcement.** A plugin declares permissions, and the app
  cannot restrict it to them. The install sheet says so.

## Code

| File | What it does |
|---|---|
| `Sources/MacotronEngine/CommunityCatalog.swift` | Search, naming, download |
| `Sources/MacotronEngine/PluginBlocklist.swift` | The block list and its cache |
| `Sources/MacotronUI/CommunityBrowser.swift` | The Community tab |
| `site/blocked.json` | The published block list |
