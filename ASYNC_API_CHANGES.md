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
