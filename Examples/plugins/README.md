# Demo plugins

Copy into your Macotron workdir `plugins/` to try. Most register launcher commands.

Demos use only `macotron.*` and Apple-shipped tools. They do not need Homebrew or other extra apps.

| File | APIs | Commands |
|---|---|---|
| demo-clipboard-history.js | clipboard.history | Clipboard History |
| demo-clipboard-image.js | clipboard.setImage/paste/remove | Clipboard Images |
| demo-snippets.js | snippets.* + expansion | Insert OMW, List Snippets |
| demo-calendar.js | calendar.upcoming | Upcoming Events |
| demo-focus-idle.js | app:activated, frontmost | Frontmost App |
| demo-idle.js | idle.*, system:idle/active | Idle Seconds |
| demo-ocr.js | ocr.recognize, screen.capture | OCR Selection |
| demo-color-picker.js | screen.pickColor | Pick Color |
| demo-system-metrics.js | system.cpu/gpu | System Metrics |
| demo-battery.js | system.battery | Battery |
| demo-meetings.js | calendar.upcoming | Next Meeting |
| demo-windows.js | window.moveToFraction / snap / focus | Tile Left/Right/Full, Switch Window |
| demo-disk-usage.js | shell.run df/du + panel | Disk Usage |
| demo-browser-profiles.js | url.open | Open GitHub in Safari |
| demo-url-router.js | url.on / open | Open YouTube in Safari |
| demo-power.js | power.* | Toggle Keep Awake |
| demo-fan.js | system.fans / setFanFloor | Toggle Fan 100% |
| demo-now-playing.js | media.nowPlaying, media:changed | Play/Pause, Next Track |
| demo-audio.js | audio.devices / setOutput / setMuted | Cycle Output, Mute |
| demo-spaces.js | spaces.list / go | Next Space |
| demo-usb.js | usb.list, usb:changed | USB Devices |
| demo-shortcuts.js | shortcuts.list / run | (launcher rows) |
| demo-notes.js | notes.list, launcher.set | (launcher rows) |
| demo-wifi.js | network.wifi / bluetooth / airDrop | Toggle Wi-Fi |
| demo-brightness.js | display brightness/XDR | Toggle XDR |
| demo-night-vision.js | display.setGamma | Toggle Night Vision |
| demo-gamma-black.js | display.setGamma white/black | Toggle Extra Dark, Toggle Invert Display |
| demo-weather.js | http + menubar.status | Refresh Weather |
| demo-icon-rainbow.js | menubar.setIconColor |  |
| demo-pomodoro.js | timer + menubar.status | Start Pomodoro |
| demo-datetime.js | clipboard.set | Insert ISO Date |
| demo-lorem.js | command arguments | Generate Lorem Ipsum |
| demo-screen-ai-summary.js | screen + ai | Summarize Screen |
| demo-ai-chat.js | panel + ai.local/claude/gemini | AI Chat |
| demo-devutils.js | clipboard | UUID, timestamp, Base64, JWT |
| demo-calculator.js | panel | Calculator |
| demo-regex.js | panel | Regex Workbench |
| demo-present-mode.js | defaults + Finder | Toggle Present Mode |
| demo-appearance.js | system.darkMode | Toggle Dark Mode |
| demo-security-checklist.js | shell probes | Security Checklist |
| demo-screenshot-rename.js | ocr + fs | Rename Last Screenshot |
| demo-batch-rename.js | fs.rename | Prefix Downloads Today |
| demo-heic-to-jpeg.js | sips + fs | Convert Downloads HEIC |
| demo-file-search.js | spotlight + panel | Search Files |
