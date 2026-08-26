# Releasing

There are two ways to ship a release. Both run the same Makefile targets.

```sh
make release VERSION=0.2.0
```

The other way is the **Release** workflow in the Actions tab. Give it a version
and run it. It builds on a `macos-26` runner and does one thing the Mac cannot:
it attaches a signed build provenance attestation and an SBOM to the DMG. Then
anyone can ask GitHub what made the file they downloaded.

```sh
gh attestation verify Macotron-0.2.9.dmg --repo statico/macotron
```

The cost of that is real. The Developer ID certificate and the Sparkle key are
GitHub secrets, so they no longer live only on this Mac. A person who can run
that workflow can sign an update. Keep the `release` environment gated with a
required reviewer, and keep the secret list short.

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
- `make dmg VERSION=x.y.z` builds, signs, and notarizes the DMG and stops.
  `make publish VERSION=x.y.z` takes it from there: appcast, tag, GitHub
  release, cask. `make release` runs both, and the workflow runs them with the
  attestation step in between.
- The window a downloader sees comes from `scripts/dmg-background.swift`, which
  draws the picture, and `scripts/dmg-layout.sh`, which asks Finder to place the
  app and the Applications alias on it. Finder is the only thing that can write
  that layout, so on a machine where it cannot be scripted the DMG still builds
  and opens as a plain list.
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

## Secrets for the Release workflow

The `release` environment holds these. Nothing outside that workflow reads them.

| Name | What it is |
|---|---|
| `APPLE_CERT_P12` | Developer ID Application identity, exported as `.p12`, base64 |
| `APPLE_CERT_PASSWORD` | The password on that `.p12` |
| `APPLE_API_KEY_P8` | App Store Connect API key for `notarytool`, base64 |
| `APPLE_API_KEY_ID` | The key ID from the `AuthKey_KEYID.p8` file name |
| `APPLE_API_ISSUER_ID` | The issuer UUID from App Store Connect |
| `SPARKLE_PRIVATE_KEY` | The EdDSA update key, as `generate_keys -x` writes it |
| `TAP_TOKEN` | Fine-grained token with Contents write on statico/homebrew-tap |

The built-in `GITHUB_TOKEN` covers the tag, the release, and the appcast commit.
It cannot write to the tap, which is a different repository. That is the only
reason for `TAP_TOKEN`.

The workflow imports the certificate into a temporary keychain, because
`codesign` finds an identity through the keychain search list. It passes the
App Store Connect key to `notarytool` with `NOTARY_KEY`, and the Sparkle key to
`sign_update` with `SPARKLE_KEY_FILE`. Both are files under `RUNNER_TEMP` that
the step erases when it is done.
