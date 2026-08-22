#!/bin/sh
# Point the Homebrew cask at a published Macotron release. `make publish` runs
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

rm -rf "$tap"
git clone -q git@github.com:statico/homebrew-tap.git "$tap"
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

  depends_on macos: :sequoia

  app "Macotron.app"

  zap trash: [
    "~/Library/Application Support/Macotron",
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
