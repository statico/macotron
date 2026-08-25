# Releasing

Builds happen on this Mac, not in CI, so the Developer ID key never becomes a
repository secret.

```sh
make release VERSION=0.2.0
```

That does all of it: a clean, pushed tree checked against origin/main, release build, bundle stamped with the version, DMG,
notarization, a signed item added to the Sparkle feed in `site/appcast.xml` and
committed, git tag, GitHub release with notes from the commits since the last
tag, and a new `Casks/macotron.rb` pushed to statico/homebrew-tap.

The appcast is signed after notarization, not before: stapling rewrites the
DMG, and the EdDSA signature covers every byte of the file people download. The
commit lands before the tag so the tag contains the feed that describes it.
Vercel serves `site/` at the domain root, so pushing publishes
https://macotron.statico.io/appcast.xml, which is the `SUFeedURL` baked into
every shipped copy of the app. That branch push comes last, after the GitHub
release exists: a feed naming a DMG that is still uploading is a 404 for
everyone whose daily check lands in the gap.

If the run dies partway, after the appcast commit but before the push, reset
with `git tag -d v$VERSION; git reset --hard origin/main` and start over.
Nothing is public until the tag is pushed.

People then install with:

```sh
brew install statico/tap/macotron
```

## One-time setup

- A **Developer ID Application** certificate in the login keychain. Without it
  `make release` refuses to package, because an unsigned DMG downloads fine and
  then tells the user the app is damaged.
- A notary profile named `personal-notary`, so `xcrun notarytool` can submit
  without a prompt. The key authorizes the team, TA59XVWN77, so the same
  profile notarizes every app signed with that Developer ID. Make one in App
  Store Connect under Users and Access > Integrations > App Store Connect API,
  with the Developer role, then keep the `.p8` somewhere permanent, because
  the profile reads the file every time:

  ```sh
  xcrun notarytool store-credentials personal-notary \
    --key ~/private_keys/AuthKey_KEYID.p8 --key-id KEYID --issuer ISSUER-UUID
  ```

  Use another name with `NOTARY_PROFILE=...`. Without a profile `make release`
  refuses to package: a signed but unnotarized DMG downloads fine and then
  tells the user that Apple could not verify the app is free of malware. Pass
  `ALLOW_UNNOTARIZED=1` to build one anyway for local testing.
- An **EdDSA key pair** for signing updates. Sparkle installs nothing it cannot
  verify against the public key in `Resources/Info.plist`, so this is what makes
  self-updates possible at all. Generate it once with Sparkle's own tool, which
  SwiftPM unpacks during a build:

  ```sh
  make build
  /tmp/macotron-build/artifacts/sparkle/Sparkle/bin/generate_keys
  ```

  It writes the private key into the login keychain as a generic password with
  the service `https://sparkle-project.org` and the account `ed25519`, and
  prints the public key. The public key is already in `Info.plist`, so a fresh
  key pair would strand every installed copy. `sign_update`, which
  `make release` runs, sits in that same `bin` directory and reads the private
  key back out of the keychain. The first run may raise a keychain access
  prompt: click Always Allow, or every release stops to ask again.

  **Back up that keychain item.** Installed copies of Macotron trust that one
  key and nothing else. Lose it and no existing install can ever be updated
  again; everyone has to download a new build by hand.
- `gh auth login`, and push access to statico/homebrew-tap.

## Pieces

- `ALLOW_UNNOTARIZED=1 make release VERSION=x.y.z` builds the DMG and stops
  before tagging. Useful to test the packaging without shipping anything.
- `make tap VERSION=x.y.z` rewrites the cask on its own, if a release went out
  and the tap did not.
- `make bundle` still builds debug. `CONFIG=release` switches it.
- `scripts/update-appcast.sh VERSION DMG NOTES` prepends one item to
  `site/appcast.xml`, if a release went out and the feed did not. It needs
  `SPARKLE_DIR` set to find `sign_update`. It refuses to run twice for the same
  version: a rebuilt DMG is not byte-identical, so the old signature would be
  wrong. Delete that `<item>` by hand first.
- The cask sets `auto_updates true`, so `brew upgrade` leaves Macotron alone
  and lets Sparkle do the work. `brew upgrade --greedy` still reinstalls it.
  One exception is wired into `scripts/update-tap.sh`: the release named by
  `first_sparkle_release` ships without the stanza, because `brew upgrade`
  skips a cask that has it and everyone still on 0.2.7 needs one ordinary brew
  upgrade to reach a build that can update itself. **If the first Sparkle
  release is not 0.2.8, change that constant before shipping it.**
