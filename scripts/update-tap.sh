#!/bin/sh
# Point the Homebrew cask at a published Macotron release. `make release` runs
# this last; rerun it by hand as `scripts/update-tap.sh 0.2.0 path/to.dmg` if a
# release was published without it.
#
# The tap is statico/homebrew-tap. `brew install statico/tap/macotron` shortens
# the name, but git needs the real one.
set -eu

version=${1:?usage: update-tap.sh VERSION DMG}
dmg=${2:?usage: update-tap.sh VERSION DMG}
sha=$(shasum -a 256 "$dmg" | cut -d' ' -f1)
tap=${TAP_DIR:-/tmp/macotron-build/tap}

# `brew upgrade` skips a cask that says auto_updates, and 0.2.7 and earlier have
# no Sparkle in them. So the first release that ships Sparkle has to go out
# without the stanza -- otherwise brew stops upgrading people who are still on a
# build that cannot update itself, and both channels close at once. Every
# release after it hands the job over to Sparkle.
first_sparkle_release=0.2.8
if [ "$version" = "$first_sparkle_release" ]; then
  auto_updates=""
else
  auto_updates="  # Macotron updates itself with Sparkle. Without this, brew would offer an
  # upgrade the app has already installed, then disagree about what is there.
  auto_updates true

"
fi

rm -rf "$tap"
# The clone keeps TAP_URL in .git/config, token and all, so do not leave it.
trap 'rm -rf "$tap"' EXIT
# CI has no SSH key, so it passes an HTTPS URL with a token in it.
git clone -q "${TAP_URL:-git@github.com:statico/homebrew-tap.git}" "$tap"
mkdir -p "$tap/Casks"

cat > "$tap/Casks/macotron.rb" <<EOF
cask "macotron" do
  version "$version"
  sha256 "$sha"

  url "https://github.com/statico/macotron/releases/download/v#{version}/Macotron-#{version}.dmg"
  name "Macotron"
  desc "Customization and automation with a launch bar, hotkeys, and menu bar items"
  homepage "https://macotron.statico.io/"

  livecheck do
    url :url
    strategy :github_latest
  end

${auto_updates}  depends_on macos: :sequoia

  app "Macotron.app"

  zap trash: [
    "~/Library/Application Support/Macotron",
    "~/Library/Caches/io.statico.macotron",
    "~/Library/Preferences/io.statico.macotron.plist",
    "~/Library/Saved Application State/io.statico.macotron.savedState",
  ]
end
EOF

cd "$tap"
# Staged, not working tree: the first release adds the file, which plain
# `git diff` reports as no change at all.
git add Casks/macotron.rb
if git diff --cached --quiet; then
  echo "The cask already describes $version."
  exit 0
fi
git commit -qm "macotron $version"
git push -q
echo "Tapped macotron $version."
