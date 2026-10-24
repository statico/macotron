# Demo clips

The homepage tour (`site/media/tour`), the social card strip (`site/og-menubar.png`) and the README GIF (`docs/media/highlights.gif`) are recorded in a macOS VM and cut with ffmpeg. This folder holds everything needed to shoot them again, along with the choices behind each clip.

| File | What it does |
| --- | --- |
| `setup.sh` | Stages `files/` and `plugins/` into the share, then does the headless half of the VM setup |
| `drive.py` | Drives the VM over VNC (pointer glides, keys, `record`, `wait_art`, `clean`) |
| `c.py x,y …` | Clicks points in the VM, then screenshots to `tmp/vm-small.png` |
| `clip_*.py` | One script per clip |
| `run_batch.py clip…` | Records clips in order, resetting state between them |
| `encode.sh` | Turns the recordings into every published asset |
| `video.sh` | Cuts the standalone demo video with captions |
| `captions.tsv`, `captions.swift` | The video's caption copy and its PNG renderer |
| `files/` | Documents, calendar scripts and the SomaFM page the VM uses |
| `plugins/deploy-status.js` | The demo-only deploy plugin |

The host tools are [Tart](https://tart.run), Python with `vncdotool` in `tmp/demo-venv`, and ffmpeg. They are needed only to make the clips. Macotron itself still uses built-in macOS only.

## The VM

- Tart VM `demo-gg`, cloned from `ghcr.io/cirruslabs/macos-golden-gate-base` (macOS 27). Use dark mode, a 1280x800 display (2560x1600 pixels) and keep the sound muted.
- Boot it with the share mounted, and leave it running:
  ```
  tart run demo-gg --no-graphics --no-clipboard --vnc-experimental --dir=share:$PWD/tmp/demo-share > tmp/demo-vm.log 2>&1
  ```
  `drive.py` reads the VNC port and password from that log. In the VM, the share is `/Volumes/My Shared Files/share`, and finished recordings are copied there.
- **No host clipboard.** Without `--no-clipboard`, Tart syncs the host Mac's clipboard into the VM through the guest agent's SPICE vdagent. Macotron's clipboard history then records host text, and it shows up in the clipboard clip. As a second guard, the VM's `/Library/LaunchAgents/org.cirruslabs.tart-guest-agent.plist` runs `tart-guest-agent --run-rpc` instead of `--run-agent`, so the vdagent never starts. `tart exec` needs only the RPC part. The VM has no iCloud account, so Universal Clipboard is not a path. Macotron keeps its history in memory only, so quitting it clears the history. `printf '' | pbcopy` in the VM clears the pasteboard.
- **Clock.** The tour clips show "Fri Oct 9" at about 11:30 PM GMT. To match it, turn off network time and set the date before a session: `sudo systemsetup -setusingnetworktime off; sudo date 100923302026`. Turn network time back on before you shut down.
- **Wallpaper.** Golden Gate's only wallpaper is a sunset aerial with no night version, so the desktop is a blue-hour grade of one frame of it. Copy `/System/Library/Wallpapers/.default/Golden Gate.mov` out of the VM as `tmp/demo-share/gg.mov`, then:
  ```
  ffmpeg -ss 2 -i tmp/demo-share/gg.mov -frames:v 1 -vf "crop=3456:2160:560:0,scale=2560:1600:flags=lanczos" tmp/gg-base.png
  ffmpeg -i tmp/gg-base.png -vf "eq=gamma=0.55:saturation=0.75:brightness=-0.06,colorbalance=rs=-0.15:bs=0.2:rm=-0.1:bm=0.12:rh=-0.05:bh=0.05,vignette=PI/4.5,format=rgb24" tmp/demo-share/gg-dark.png
  ```
  Then set `~/Pictures/gg-dark.png` as the desktop picture.
- **Setup.** Run `demo/setup.sh`. It installs Macotron from the DMG in the share and copies the catalog plugins plus the two demo plugins. The canned battery meter goes in as `canned-battery.js`. With the catalog name, Macotron 1.0 sees changed bytes and badges its menu bar icon with "1 plugin update". A `demo-` prefix does not work either, because Macotron renames `demo-*.js` back to the catalog name. It also writes `settings.json` with weather set to Cupertino and New York, London and Tokyo clocks. Finally it hides the Dock, Spotlight and widgets, and puts the documents into `~/Documents`.
  - `report.pdf` is `files/report.html` printed from Chrome with `--print-to-pdf`.
  - `docx.py` builds `report.docx`, because textutil drops images.
- **By hand over VNC:**
  - Approve the plugins under Review & Reload. Macotron 1.0 asks again after an upgrade, and each sheet says "This Mac cannot run Apple Intelligence". Click Run Anyway.
  - In Settings > General, set Updates to Never so the Sparkle prompt stays out of the clips.
  - Grant the permissions. Golden Gate calls the Accessibility pane "Device Control and Data Access".
  - The first `tart exec` AppleScript aimed at each app hangs on a "tart-guest-agent wants access to control …" prompt until you click Allow at (698,385).
- **Quiet the VM:**
  - `defaults -currentHost write com.apple.controlcenter NowPlaying -int 8` hides the system Now Playing item.
  - `defaults write com.apple.SoftwareUpdate AutomaticCheckEnabled -bool false`, plus the same in `/Library/Preferences` with sudo, cuts down the "Software Update Available" banners. A low-disk banner still shows up now and then. The trims in `encode.sh` cut around them; if one lands mid-clip, close it with the × at (924,52) and reshoot.
- **Music.** Tart passes the VM's audio to the host speakers. Mute the VM output before you start the music: `tart exec demo-gg osascript -e 'set volume output volume 0' -e 'set volume with output muted'`. Muted output does not stop Now Playing. Open `~/somafm.html` in Safari and press Play. It plays SomaFM Underground 80s, which gives Now Playing real titles. Cover art comes from the iTunes search, so `wait_art()` waits for a track that has art and started 25–90 s ago. That keeps the cover from changing mid-clip.
- **Menu bar.** Golden Gate hides overflow items behind a «, so Spotlight is hidden and the audio plugin is left out to make room. Cmd-drag the items into this order: Now Playing first (its width changes), then meetings, staging, prod, calendar, weather, battery, CPU.
- **Calendar.** `files/events.applescript` seeds the events. `files/sam.applescript` moves "1:1 with Sam" three hours out, so the meetings item shows a calm countdown in the other clips. Re-run it before a session.

## Choices that apply to every clip

- **Pinned deploy status.** `plugins/deploy-status.js` is canned at staging ✓ current and prod ↓ 1, so the menu bar reads the same in every clip.
- **No lead-in.** Each clip script starts its action right after `record()` and has no settle pause. `encode.sh` trims whatever lead remains.
- **Pace.** `PACE=0.8` (in `drive.py`) scales every sleep, glide and recording length. Change it there to retime the whole tour.
- **Clean desktop.** `clean()` closes Finder windows, hides every app except Finder and Macotron (Safari keeps playing) and brings Finder to the front. Only the windows clip shows app windows.
- **Pointer.** The pointer always glides with easing and never jumps, and it rests away from whatever the clip is about.

## Recording

```
cd demo
../tmp/demo-venv/bin/python -W ignore run_batch.py menubar launcher system nowplaying meetings community
```

`run_batch.py` waits for cover art and calls `clean()` before each clip. It also handles the state that two clips need:

- **community**: it turns Hot Reload on, deletes `chess-puzzles.js` and turns Hot Reload off, so Macotron notices the removal and its banner stays out of the menu. Adding the plugin brings up the trust sheet, which needs "Add Anyway".
- **meetings**: it runs `files/meet.applescript`, which puts "Design review" 50 s out. It then quits Calendar and waits 31 s, because the plugin polls every 30 s, before recording. Afterwards, close the overlay and delete the event.

The windows clip isn't in the batch because it needs windows open. Open `~/Documents/Trip itinerary.txt` in TextEdit with bounds `{100, 120, 900, 700}` and a Finder window on Documents at `{600, 60, 1260, 500}`. Check that (1000,350) lands on Finder and (300,400) on TextEdit, then run `clip_windows.py`. If the tiling hotkeys do nothing, restart Macotron.

Menu bar clicks sometimes miss on the first take. Check a contact sheet of every recording before encoding.

## Encoding

`demo/encode.sh` (set `FF=` if ffmpeg isn't on PATH) re-cuts everything from `tmp/demo-share/*.mov`. The tour clips are 1280x800 H.264 at 30 fps, CRF 26 (24 for the zoomed clips), with no audio and with faststart. Each clip gets a JPEG poster.

| Clip | Tab | Cut |
| --- | --- | --- |
| menubar | Your own menu bar | A still menu bar. The zoom (3.5x onto the left end of the items), the pan across and the zoom back out are all done in ffmpeg's zoompan, after an upscale to 5120 wide to stop jitter |
| launcher | Quick launcher | Cropped to the panel so it fills the frame; the 9-row "cal" list still fits |
| windows | Window management | Full frame |
| meetings | Meeting bar | Zooms 3x onto "Design review · Now", then zooms back out just as the overlay opens |
| nowplaying | Now Playing | A 1:1 crop of the top left of the items |
| system | At a glance | The right half of the menu bar: CPU, battery, weather, calendar. The 0.5 s trim skips a Software Update banner |
| community | Community plugins | Full frame, from the catalog to a chess puzzle |

The social card strip is a 1380x48 crop of the menu bar clip that stops just before the clock. After regenerating it, screenshot `site/og.html` at 1200x630 to `site/og.png`.

The README GIF is the launcher clip followed by the first 15 s of the glance clip. It is 720 px wide at 12 fps, with a 128-color palette built in two passes, and comes to about 2 MB.

After a reshoot the timings shift. Re-pick the trims and posters in `encode.sh` from a contact sheet.

## Demo video

`demo/video.sh` cuts `tmp/macotron-demo.mp4`, a standalone video of about 2 min 15 s. It is 1280x800 H.264 at 30 fps, CRF 23, with no audio and with faststart, and comes to about 5 MB. Run `encode.sh` first, because the video reads the tour clips in `site/media/tour`. It also reads two raw recordings: `deploy.mov` (a still 2.5x crop of the deploy-status items as their counts change) and `paste.mov`.

- **Order.** Title card, menu bar, launcher, clipboard and emoji, windows, deploy status, meetings, Now Playing, at a glance, community, closing card.
- **Captions.** This ffmpeg has no `drawtext` filter. `captions.swift` draws each row of `captions.tsv` (name, title, one line of text) as a lower third in SF Pro on a transparent 1280x800 PNG. It also draws the title and closing cards. `video.sh` overlays each PNG with a 0.35 s alpha fade, from 0.5 s into the clip until 0.8 s before its end. A sixth `seg` argument ends a caption early. The launcher uses it so the caption leaves before the "cal" list reaches it.
- **Segments.** Each segment is encoded with the same settings and tagged BT.709, so the final concat is a stream copy. Without the tags, the PNG cards come out as sRGB and players re-initialize at each card.
- **README.** The script also writes `docs/media/demo.avif`, an animated AVIF of the same cut (SVT-AV1, CRF 40, about 4 MB). The README shows it, with `highlights.gif` as the fallback for browsers without AVIF.
- **Check.** The script also writes `tmp/macotron-demo-sheet.jpg`, a sheet of 48 frames. Check that no caption covers the thing being shown.
- **`paste.mov`.** `clip_paste.py` records it with the 1.0 catalog's `clipboard-history.js` and `emoji.js` in the plugins folder. Quit and reopen Macotron first so the history holds only the seeds, then run `clean()`. The clip seeds the clipboard with Lisbon trip text and opens Clipboard History. It clicks "Taberna da Rua das Flores, 8 PM", which puts the entry back on the clipboard and closes the panel, and Cmd-V pastes it after "Dinner:". Then the emoji picker inserts 🍷. The take is about 13 s.

## Site

The tour lives in `site/index.html` and `site/tour.js`. When a tab is far away, the carousel cuts to its neighbor and glides only the last step, so the last slide arrives in about 250 ms.
