# Built-in plugins

Copy into your Macotron workdir `plugins/` to try. Most register launcher commands.

Built-in plugins use only `macotron.*` and Apple-shipped tools. They do not need Homebrew or other extra apps.

| File | APIs | Commands |
|---|---|---|
| ai-chat.js | panel + ai.local/claude/gemini | AI Chat |
| appearance.js | system.darkMode | Toggle Dark Mode |
| apple-tv.js | appletv.list / send, panel | Apple TV Remote |
| audio.js | audio.devices / setOutput / setMuted | Cycle Output, Mute |
| batch-rename.js | fs.rename | Prefix Downloads Today |
| battery.js | system.battery | Battery |
| bluetooth.js | network.bluetooth | (menu bar batteries) |
| brightness.js | display brightness/XDR | Toggle XDR |
| browser-picker.js | url.setDefaultHandler / on / onFallback | (URL routing, browser picker) |
| browser-profiles.js | url.open | Open GitHub in Safari |
| calculator.js | panel | Calculator |
| calendar.js | calendar.upcoming | Upcoming Events |
| clipboard-history.js | clipboard.history, launcher.set, panel | Clipboard History |
| clipboard-image.js | clipboard.setImage/paste/remove | Clipboard Images |
| color-picker.js | screen.pickColor | Pick Color |
| contacts.js | contacts.list, launcher.set | (launcher rows) |
| cpu-graph.js | system.cpu, menubar.status sparkline | (CPU menu bar graph) |
| datetime.js | clipboard.set | Insert ISO Date |
| devutils.js | clipboard | UUID, timestamp, Base64, JWT |
| disk-usage.js | shell.run df/du + panel | Disk Usage |
| eject.js | fs.list + diskutil eject | Empty Trash |
| fan.js | system.fans / setFanFloor | Toggle Fan 100% |
| file-search.js | spotlight.search kind + panel | Search Files |
| focus-idle.js | app:activated, frontmost | Frontmost App |
| gestures.js | event.tap swipe, window.moveToFraction | (3-finger swipe tiles) |
| heic-to-jpeg.js | sips + fs | Convert Downloads HEIC |
| hid.js | hid.list | HID Devices |
| headphone-pause.js | audio:changed, media.playPause | (pause when headphones unplug) |
| homekit.js | homekit.homes / accessories / set | (HomeKit menu bar) |
| hyper.js | keyboard.setHyperKey, keyboard.on | (Caps Lock as Hyper) |
| icon-rainbow.js | menubar.setIconColor |  |
| idle.js | idle.*, system:idle/active | Idle Seconds |
| layouts.js | window.restore, localStorage | Save Work, Restore Work |
| lock-screen.js | power.lock | Lock Screen |
| lorem.js | command arguments | Generate Lorem Ipsum |
| markdown.js | clipboard + panel | Markdown from Clipboard |
| meeting-overlay.js | calendar.upcoming, panel fullscreen | (pre-meeting overlay) |
| meetings.js | calendar.upcoming | Next Meeting |
| mic-mute.js | audio.input / setMuted | (mic mute) |
| network-path.js | network.counters / ping | (menu bar throughput + ping) |
| notes.js | notes.list, launcher.set | (launcher rows) |
| now-playing.js | media.nowPlaying, media:changed | Play/Pause, Next Track |
| ocr.js | ocr.recognize, screen.capture | OCR Selection |
| plain-paste.js | clipboard.setPastePlain | (plain-text Command-V) |
| pomodoro.js | timer + menubar.status | Start Pomodoro |
| power.js | power.* | Toggle Keep Awake |
| present-mode.js | defaults + Finder | Toggle Present Mode |
| profiles.js | wifi:changed, system.setDarkMode | (home/work appearance) |
| qr.js | qr.scan / qr.show | Scan QR (Screen/Camera), Show QR |
| record.js | audio.record, camera.preview/snapshot | Start/Stop Recording, Camera Preview/Snapshot |
| reminders.js | reminders.list / add / complete | (Reminders menu bar) |
| regex.js | panel | Regex Workbench |
| screen-ai-summary.js | screen + ai | Summarize Screen |
| screen-effects.js | display.setGamma, display nightShift/trueTone/grayscale | Toggle Night Vision, Toggle Extra Dark, Toggle Invert Display, Toggle Night Shift, Night Shift 60%, Toggle True Tone, Toggle Grayscale |
| screenshot-rename.js | ocr + fs | Rename Last Screenshot |
| security-checklist.js | shell probes | Security Checklist |
| share.js | share.open, share.airDrop | Share Text, Share File, AirDrop File |
| shortcuts.js | shortcuts.list / run | (launcher rows) |
| snippets.js | snippets.* + expansion, launcher.set | Insert OMW |
| spaces.js | spaces.list / go | Next Space |
| system-metrics.js | system.cpu/gpu | System Metrics |
| system-settings.js | launcher.set, url.open | (System Settings panes) |
| time-machine.js | tmutil status | (Time Machine) |
| translate.js | ax.selectedText + ai.local + panel | Translate Selection |
| url-router.js | url.on / open | Open YouTube in Safari |
| usb.js | usb.list, usb:changed, /usr/bin/say | USB Devices |
| weather.js | http + menubar.status | Refresh Weather |
| web-search.js | url.open, /usr/bin/open dict:// | Search Google, Search Wikipedia, Search Maps, Search YouTube, Search GitHub, Define |
| wifi.js | network.wifi / bluetooth / airDrop | Toggle Wi-Fi |
| world-clock.js | menubar.status | (world clocks) |
| window-grid.js | window.previewFraction / panel grid | Place Window |
| window-switcher.js | event.tap, window.focus, panel | (Option-Tab switcher) |
| windows.js | window.moveToFraction / snap / focus | Tile Left/Right/Full, Switch Window |
