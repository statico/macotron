# Demo plugins

Copy into your Macotron workdir `plugins/` to try. Most register launcher commands.

| File | APIs | Commands |
|---|---|---|
| demo-clipboard-history.js | clipboard.history | Clipboard History |
| demo-clipboard-image.js | clipboard.setImage/paste/remove | Clipboard Images |
| demo-snippets.js | snippets.* + expansion | Insert OMW, List snippets |
| demo-calendar.js | calendar.upcoming | upcoming-events |
| demo-focus-idle.js | app:activated, frontmost | Frontmost App |
| demo-idle.js | idle.*, system:idle/active | Idle seconds |
| demo-ocr.js | ocr.recognize | OCR Screen |
| demo-system-metrics.js | system.disk/network/gpu | System Metrics |
| demo-window-tiling.js | window.moveToFraction | Tile Left/Right/Full |
| demo-window-snap.js | window.setSnapEnabled | Toggle Window Snap |
| demo-browser-profiles.js | url.open profile | Open GitHub (Chrome Profile 1) |
| demo-url-router.js | url.on / open | Open YouTube in Safari |
| demo-power.js | power.* | Toggle Keep Awake |
| demo-wifi.js | network.wifiSSID, wifi:changed | Wi-Fi SSID |
| demo-brightness.js | display brightness/XDR | Toggle XDR |
| demo-keep-awake.js | shell caffeinate | Toggle Keep Awake |
| demo-weather.js | http + menubar | Refresh Weather |
| demo-pomodoro.js | timer + menubar | Start Pomodoro |
| demo-datetime.js | clipboard.set | Insert ISO Date |
| demo-lorem.js | command arguments | Generate Lorem Ipsum |
| demo-screen-ai-summary.js | screen + ai | Summarize Screen |
| demo-ai-chat.js | panel + ai | AI Chat |
| demo-window-hopper.js | window.getAll + panel | Switch Window |
| demo-devutils.js | clipboard | UUID, timestamp, Base64, JWT |
| demo-calculator.js | panel | Calculator |
| demo-homebrew.js | shell brew | Brew List, Brew Copy Outdated |
| demo-regex.js | panel | Regex Workbench |
| demo-present-mode.js | defaults + Finder | Toggle Present Mode |
| demo-security-checklist.js | shell probes | Security Checklist |
| demo-screenshot-rename.js | ocr + fs | Rename Last Screenshot |
| demo-batch-rename.js | fs + shell | Prefix Downloads Today |
| demo-file-search.js | spotlight + panel | Search Files |
