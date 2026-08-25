# Async API changes

JS APIs whose signature changed when the PIM modules stopped blocking the main
thread. Every one of these now returns a promise; `--check` resolves it with the
stub value it used to return.

```
macotron.notes.list()            -> Promise<Note[]>     (was: sync Note[])
macotron.notes.open(id)          -> Promise<void>       (was: sync void)
macotron.reminders.list(opts?)   -> Promise<Reminder[]> (was: sync Reminder[])
macotron.calendar.upcoming(opts?)-> Promise<Event[]>    (was: sync Event[])
macotron.contacts.list()         -> Promise<Contact[]>  (was: sync Contact[])
macotron.contacts.search(query)  -> Promise<Contact[]>  (was: sync Contact[])
```

Unchanged and still synchronous: `macotron.reminders.add()` and
`macotron.reminders.complete()`. Both are local EventKit writes, not the
multi-second reads this pass was about.

Also out of scope but now stale: `docs/04-modules.md` still describes
`macotron.notes.list()`, `macotron.contacts.list()` and `.search()` as returning
arrays, and `site/workdir/plugins/` holds pre-async copies of the example
plugins.
||||||| ee21888
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

# Async API changes

JS APIs whose signature changed when their native bridge stopped blocking the
main thread.

```
macotron.http.get(url, opts?) -> Promise<{status, body, headers}>              (was: sync {status, body, headers})
macotron.http.post(url, body, opts?) -> Promise<{status, body, headers}>       (was: sync {status, body, headers})
macotron.http.put(url, body, opts?) -> Promise<{status, body, headers}>        (was: sync {status, body, headers})
macotron.http.delete(url, opts?) -> Promise<{status, body, headers}>           (was: sync {status, body, headers})
macotron.bonjour.browse(type, opts?) -> Promise<Array<{name, type, host, port, txt}>>  (was: sync array)
macotron.appletv.list() -> Promise<Array<{id, name, host, port, type}>>        (was: sync array)
macotron.appletv.send(id, command) -> Promise<{ok, error?}>                    (was: sync {ok, error?})
```

None of the resolved shapes changed. A failed HTTP request still resolves with
`status: 0` and the message in `body` rather than rejecting, so plugins keep
their single status check.
