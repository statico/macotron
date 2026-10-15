# Radio & Podcasts — design

A cliamp-style player inside Macotron: internet radio and podcasts, driven from
the launcher and a menu bar item. Built-in macOS only — no ffmpeg, no yt-dlp.

## Scope

In: a native `macotron.player` module (AVPlayer), radio-browser.info search,
podcast search and playback with resume, a menu bar item.

Out: local files, lyrics, streaming services (Spotify, Plex, …), visualizers,
EQ, playlists/queues.

## 1. `macotron.player` (host)

New files: `Sources/Modules/Player.swift` (AVPlayer wrapper, singleton) and
`Sources/Modules/PlayerModule.swift` (JS surface). Registered in
`StandardModules.swift`.

API:

| Call | Tier | Notes |
|---|---|---|
| `play(url, { title?, artist?, artwork?, position? })` | moderate | `http`, `https`, `file` only; anything else returns `false`. Replaces whatever is playing. `position` is seconds to start at. |
| `pause()`, `resume()`, `toggle()`, `stop()` | moderate | |
| `seek(seconds)` | moderate | Absolute. No-op on live streams. |
| `setVolume(0…1)` | moderate | Player volume, not system volume. |
| `state()` | safe | `{ status, url, title, artist, streamTitle, position, duration, volume, error? }`. `status` is `"stopped" \| "loading" \| "playing" \| "paused" \| "error"`. `duration` is `null` for live streams. |

Event `player:changed` fires with `state()` when `status`, `streamTitle`,
the item, or `error` change — not on position ticks. Plugins that show a
position read `state()` themselves.

- **ICY metadata:** `AVPlayerItemMetadataOutput` delivers the stream's
  `StreamTitle` (usually `Artist - Song`) as `streamTitle`.
- **System integration:** the player sets `MPNowPlayingInfoCenter` and
  handles `MPRemoteCommandCenter` play / pause / toggle, plus skip ±30 s when
  there is a duration. Media keys, Control Center, and the existing Now
  Playing plugin then see Macotron like any other player.
- **Lifetime:** the player is a singleton that survives plugin reloads, so
  hot-reloading any plugin does not cut the music. A reloaded plugin re-syncs
  from `state()`. Quitting Macotron stops it.
- **Errors:** a failed load or a dropped stream sets `status: "error"` with
  AVFoundation's message in `error`. No automatic retry.
- **Dry run:** every call is a no-op, `state()` is stopped, `play` returns
  `true`.

## 2. `Examples/plugins/radio.js` (built-in plugin)

One plugin, "Radio & Podcasts".

### Launcher

`macotron.launcher.query`, active only behind a keyword so it does not
flood every search:

- `radio <text>` — radio-browser.info
  `GET /json/stations/search?name=<text>&hidebroken=true&order=votes&reverse=true&limit=20`
  against `all.api.radio-browser.info`. Row: station name, subtitle
  `country · codec bitrate kbps · tags`. Return plays it. After play the
  plugin POSTs `/json/url/<uuid>` (radio-browser asks clients to count clicks).
- `podcast <text>` — iTunes Search API
  `https://itunes.apple.com/search?media=podcast&term=<text>&limit=15`.
  Row: show name, subtitle author. Return subscribes and plays the newest
  episode (resuming if started before).
- `radio` / `podcast` with no text — favorite stations / subscribed shows.

Queries are debounced by the launcher's late-rows behaviour; no extra cache.

### Podcasts

- The feed is fetched with `macotron.http.get` and parsed with a small regex
  over `<item>` → `title`, `enclosure url`, `pubDate`, `itunes:duration`.
  QuickJS has no DOMParser; podcast RSS is regular enough for this.
- Subscriptions and resume positions live in `localStorage` (`radio.subs`,
  `radio.pos.<enclosure url>`). Position is saved every 15 s while playing
  and on pause/stop; an episode within 30 s of its end counts as finished and
  restarts from 0.

### Menu bar item

`macotron.menubar.status`, `sfSymbol: "radio"`.

- Title: `streamTitle`, else the station / episode title, clipped to ~30
  chars. Icon only when stopped.
- Menu: what is playing (station, song) · Play/Pause · Stop · Back 30 s /
  Forward 30 s (podcasts only) · Volume ▸ 25/50/75/100 % · Add/Remove
  Favorite · Favorites ▸ · Recent ▸ (last 5 stations) · Podcasts ▸ (each show ▸
  its 10 newest episodes, plus Unsubscribe) · Copy Song (when there is a
  `streamTitle`).
- Repaints on `player:changed`.

Favorites and recents are `localStorage` too (`radio.favs`, `radio.recent`),
storing `{ name, url, uuid }`.

## Docs

`docs/04-modules.md` (Player section), `docs/06-security.md` (tiers),
`Sources/Macotron/Resources/macotron.d.ts`, and a `site/docs/src` API page
matching the existing ones.

## Testing

- `DryRunStubTests`: player calls do not play and `state()` is stopped.
- Swift unit test for the ICY `StreamTitle` extraction and URL-scheme
  rejection (pure functions pulled out of `Player`).
- `PluginHarness` tests for `radio.js` with mocked `http`, `player`,
  `menubar`, `launcher`: station rows from a radio-browser response, podcast
  RSS parsing, resume position saved and used.
- Manual: play a real station (SomaFM via radio-browser) and a podcast,
  check media keys, Control Center, and the song title in the menu bar.

## Risks

- Some stations only stream formats AVPlayer cannot decode (Ogg Vorbis, some
  Opus). They fail with `status: "error"`; search rows filter to
  `codec` MP3 / AAC / AAC+ to avoid offering them.
- radio-browser mirrors come and go; `all.api.radio-browser.info` resolves to
  a live one.
