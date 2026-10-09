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
| `files/` | Documents, calendar scripts and the SomaFM page the VM uses |
| `plugins/deploy-status.js` | The demo-only deploy plugin |

The host tools are [Tart](https://tart.run), Python with `vncdotool` in `tmp/demo-venv`, and ffmpeg. They are needed only to make the clips. Macotron itself still uses built-in macOS only.

## The VM

- Tart VM `demo-gg`, cloned from `ghcr.io/cirruslabs/macos-golden-gate-base` (macOS 27). Use dark mode, a 1280x800 display (2560x1600 pixels) and keep the sound muted.
- Boot it with the share mounted, and leave it running:
  ```
  tart run demo-gg --no-graphics --vnc-experimental --dir=share:$PWD/tmp/demo-share > tmp/demo-vm.log 2>&1
  ```
  `drive.py` reads the VNC port and password from that log. In the VM, the share is `/Volumes/My Shared Files/share`, and finished recordings are copied there.
- **Wallpaper.** Golden Gate's only wallpaper is a sunset aerial with no night version, so the desktop is a blue-hour grade of one frame of it. Copy `/System/Library/Wallpapers/.default/Golden Gate.mov` out of the VM as `tmp/demo-share/gg.mov`, then:
  ```
  ffmpeg -ss 2 -i tmp/demo-share/gg.mov -frames:v 1 -vf "crop=3456:2160:560:0,scale=2560:1600:flags=lanczos" tmp/gg-base.png
  ffmpeg -i tmp/gg-base.png -vf "eq=gamma=0.55:saturation=0.75:brightness=-0.06,colorbalance=rs=-0.15:bs=0.2:rm=-0.1:bm=0.12:rh=-0.05:bh=0.05,vignette=PI/4.5,format=rgb24" tmp/demo-share/gg-dark.png
  ```
  Then set `~/Pictures/gg-dark.png` as the desktop picture.
- **Setup.** Run `demo/setup.sh`. It installs Macotron from the DMG in the share and copies the catalog plugins plus the two demo plugins. It also writes `settings.json` with weather set to Cupertino and New York, London and Tokyo clocks. Finally it hides the Dock, Spotlight and widgets, and puts the documents into `~/Documents`.
  - `report.pdf` is `files/report.html` printed from Chrome with `--print-to-pdf`.
  - `docx.py` builds `report.docx`, because textutil drops images.
- **By hand over VNC:**
  - Grant the permissions. Golden Gate calls the Accessibility pane "Device Control and Data Access".
  - The first `tart exec` AppleScript aimed at each app hangs on a "tart-guest-agent wants access to control …" prompt until you click Allow at (698,385).
- **Quiet the VM:**
  - `defaults -currentHost write com.apple.controlcenter NowPlaying -int 8` hides the system Now Playing item.
  - `defaults write com.apple.SoftwareUpdate AutomaticCheckEnabled -bool false`, plus the same in `/Library/Preferences` with sudo, cuts down the "Software Update Available" banners. A low-disk banner still shows up now and then. The trims in `encode.sh` cut around them; if one lands mid-clip, close it with the × at (924,52) and reshoot.
- **Music.** Open `~/somafm.html` in Safari and press Play. It plays SomaFM Underground 80s, which gives Now Playing real titles. Cover art comes from the iTunes search, so `wait_art()` waits for a track that has art and started 25–90 s ago. That keeps the cover from changing mid-clip.
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

## Site

The tour lives in `site/index.html` and `site/tour.js`. When a tab is far away, the carousel cuts to its neighbor and glides only the last step, so the last slide arrives in about 250 ms.
