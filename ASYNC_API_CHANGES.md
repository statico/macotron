# Async API changes

JS APIs that now return a Promise. `macotron.d.ts` still describes the old
signatures — update it there.

| API | Was | Now | Notes |
| --- | --- | --- | --- |
| `macotron.screen.capture()` | `string` (base64 PNG), synchronous | `Promise<string>` | `capture({ selection: true })` was already a Promise. A failed capture used to log and resolve to `""`; it now rejects with `screen.capture failed: …`. |
| `macotron.ax.selectedText()` | `string \| null`, synchronous | `Promise<string \| null>` | Blocked the main thread for up to 300 ms polling a Chromium accessibility tree; the poll now runs off-main. |

Plugins updated: `Examples/plugins/translate.js` (awaits `ax.selectedText()`).
`ocr.js` and `screen-ai-summary.js` already awaited `screen.capture`.
`docs/04-modules.md` also documents `screen.capture()` as returning a PNG
directly.
