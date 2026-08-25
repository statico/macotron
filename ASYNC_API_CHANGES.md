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
