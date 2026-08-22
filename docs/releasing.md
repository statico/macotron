# Releasing

Builds happen on this Mac, not in CI, so the Developer ID key never becomes a
repository secret.

```sh
make publish VERSION=0.2.0
```

That does all of it: release build, bundle stamped with the version, DMG,
notarization, git tag, GitHub release with notes from the commits since the
last tag, and a new `Casks/macotron.rb` pushed to statico/homebrew-tap.

People then install with:

```sh
brew install statico/tap/macotron
```

## One-time setup

- A **Developer ID Application** certificate in the login keychain. Without it
  `make release` refuses to package, because an unsigned DMG downloads fine and
  then tells the user the app is damaged.
- A notary profile, so `xcrun notarytool` can submit without a prompt:

  ```sh
  xcrun notarytool store-credentials macotron-notary \
    --apple-id you@example.com --team-id TEAMID --password APP-SPECIFIC-PASSWORD
  ```

  Use another name with `NOTARY_PROFILE=...`. Without a profile the DMG is
  still signed, but Gatekeeper blocks it.
- `gh auth login`, and push access to statico/homebrew-tap.

## Pieces

- `make release VERSION=x.y.z` builds and notarizes the DMG only. Useful to
  test the packaging without tagging anything.
- `make tap VERSION=x.y.z` rewrites the cask on its own, if a release went out
  and the tap did not.
- `make bundle` still builds debug. `CONFIG=release` switches it.
