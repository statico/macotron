#!/bin/sh
# Add a release to the Sparkle feed in site/appcast.xml, which Vercel serves at
# https://macotron.statico.io/appcast.xml. `make release` runs this after
# stapling, because stapling rewrites the DMG and every byte of it is signed.
#
# The EdDSA private key lives in the login keychain of this Mac (see
# docs/releasing.md). sign_update reads it from there.
set -eu

version=${1:?usage: update-appcast.sh VERSION DMG NOTES}
dmg=${2:?usage: update-appcast.sh VERSION DMG NOTES}
notes=${3:?usage: update-appcast.sh VERSION DMG NOTES}
appcast=site/appcast.xml
sign_update=${SPARKLE_DIR:?SPARKLE_DIR is not set}/bin/sign_update

test -x "$sign_update" || { echo "No sign_update at $sign_update. Run make build."; exit 1; }
grep -q '<!-- newest first -->' "$appcast" || \
  { echo "No insertion marker in $appcast; sed would drop the item silently."; exit 1; }
# Stop rather than skip: a rebuilt DMG is not byte-identical, so an existing
# item for this version describes a file nobody can download any more.
if grep -qF "<sparkle:version>$version</sparkle:version>" "$appcast"; then
  echo "$appcast already offers $version. Delete that <item> first if the DMG changed."
  exit 1
fi

# Prints the enclosure attributes ready to paste: edSignature and length.
attrs=$("$sign_update" "$dmg")

# Sparkle renders <description> as HTML, so the commit lines need escaping and
# the leading "- " turned into list markup.
body="<ul>$(sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' \
  -e 's|^- \(.*\)|<li>\1</li>|' "$notes" | tr -d '\n')</ul>"

item=$(mktemp)
trap 'rm -f "$item"' EXIT
cat > "$item" <<EOF
        <item>
            <title>$version</title>
            <sparkle:version>$version</sparkle:version>
            <sparkle:shortVersionString>$version</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
            <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
            <description><![CDATA[$body]]></description>
            <enclosure url="https://github.com/statico/macotron/releases/download/v$version/Macotron-$version.dmg" type="application/octet-stream" $attrs />
        </item>
EOF

sed -e "/<!-- newest first -->/r $item" "$appcast" > "$appcast.new"
mv "$appcast.new" "$appcast"
echo "Appcast now offers $version."
