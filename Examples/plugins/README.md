# Built-in plugins

Copy into your Macotron workdir `plugins/` to try. Most register launcher commands.

Built-in plugins use only `macotron.*` and Apple-shipped tools. They do not need Homebrew or other extra apps.

| File | APIs | Commands |
|---|---|---|
| clipboard-history.js | clipboard.history | Clipboard History |
| clipboard-image.js | clipboard.setImage/paste/remove | Clipboard Images |
| snippets.js | snippets.* + expansion | Insert OMW, List Snippets |
| calendar.js | calendar.upcoming | Upcoming Events |
| focus-idle.js | app:activated, frontmost | Frontmost App |
| idle.js | idle.*, system:idle/active | Idle Seconds |
| ocr.js | ocr.recognize, screen.capture | OCR Selection |
| qr.js | qr.scan / qr.show | Scan QR (Screen/Camera), Show QR |
| color-picker.js | screen.pickColor | Pick Color |
| system-metrics.js | system.cpu/gpu | System Metrics |
| battery.js | system.battery | Battery |
| meetings.js | calendar.upcoming | Next Meeting |
| windows.js | window.moveToFraction / snap / focus | Tile Left/Right/Full, Switch Window |
| window-grid.js | window.previewFraction / panel grid | Place Window |
| disk-usage.js | shell.run df/du + panel | Disk Usage |
| browser-profiles.js | url.open | Open GitHub in Safari |
| url-router.js | url.on / open | Open YouTube in Safari |
| power.js | power.* | Toggle Keep Awake |
| lock-screen.js | power.lock | Lock Screen |
| fan.js | system.fans / setFanFloor | Toggle Fan 100% |
| now-playing.js | media.nowPlaying, media:changed | Play/Pause, Next Track |
| audio.js | audio.devices / setOutput / setMuted | Cycle Output, Mute |
| spaces.js | spaces.list / go | Next Space |
| usb.js | usb.list, usb:changed | USB Devices |
| hid.js | hid.list | HID Devices |
| shortcuts.js | shortcuts.list / run | (launcher rows) |
| notes.js | notes.list, launcher.set | (launcher rows) |
| system-settings.js | launcher.set, url.open | (System Settings panes) |
| wifi.js | network.wifi / bluetooth / airDrop | Toggle Wi-Fi |
| brightness.js | display brightness/XDR | Toggle XDR |
| screen-effects.js | display.setGamma, system display | Toggle Night Vision, Extra Dark, Invert, Night Shift, True Tone, Grayscale |
| weather.js | http + menubar.status | Refresh Weather |
| icon-rainbow.js | menubar.setIconColor |  |
| pomodoro.js | timer + menubar.status | Start Pomodoro |
| datetime.js | clipboard.set | Insert ISO Date |
| lorem.js | command arguments | Generate Lorem Ipsum |
| screen-ai-summary.js | screen + ai | Summarize Screen |
| ai-chat.js | panel + ai.local/claude/gemini | AI Chat |
| devutils.js | clipboard | UUID, timestamp, Base64, JWT |
| calculator.js | panel | Calculator |
| regex.js | panel | Regex Workbench |
| present-mode.js | defaults + Finder | Toggle Present Mode |
| appearance.js | system.darkMode | Toggle Dark Mode |
| security-checklist.js | shell probes | Security Checklist |
| screenshot-rename.js | ocr + fs | Rename Last Screenshot |
| batch-rename.js | fs.rename | Prefix Downloads Today |
| heic-to-jpeg.js | sips + fs | Convert Downloads HEIC |
| file-search.js | spotlight + panel | Search Files |
