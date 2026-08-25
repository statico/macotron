# Async API changes

## `macotron.launcher.query(id, fn)`

`fn(query)` may now return a `Promise` of rows as well as a row array. The
launcher does not wait on it: the keystroke is answered with whatever is ready,
and the rows are pushed into the launcher when the promise settles, exactly as
`macotron.launcher.set()` does. A promise that settles for a query the user has
already typed past is discarded. A rejected promise clears that provider's rows.

`macotron.d.ts` needs `query`'s callback return type widened to
`LauncherHit[] | Promise<LauncherHit[]>`.
