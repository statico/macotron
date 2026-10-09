#!/bin/bash
# Headless half of the demo VM setup (runbook steps 7, 17-25). Permissions,
# the display mode and SomaFM's Play button still need VNC clicks.
set -e
cd "$(dirname "$0")"
VM=${VM:-demo-gg}
x() { tart exec "$VM" bash -c "$1"; }
S="/Volumes/My Shared Files/share"

# Stage everything the VM copies into tmp/demo-share, which the VM mounts as
# "share". The VM has no battery, so its meter reads a canned one.
H=../tmp/demo-share
mkdir -p $H
cp files/* plugins/deploy-status.js $H/
sed 's/const bat = macotron.system.battery();/const bat = ({ level: 84, charging: false, timeRemaining: 347, source: "battery", health: 97, cycles: 212 });/' \
    ../Examples/plugins/battery.js > $H/battery.js
python3 docx.py $H/report.docx files/charts.png
[ -f $H/report.pdf ] || echo "Print files/report.html to $H/report.pdf (letter, no margins) before the next step." >&2

x "osascript -e 'set volume output volume 0' -e 'set volume with output muted'"
x "hdiutil attach -nobrowse -quiet '$S/Macotron-0.7.7.dmg' -mountpoint /tmp/m && cp -R /tmp/m/Macotron.app /Applications/ && hdiutil detach -quiet /tmp/m"
x "defaults write io.statico.macotron pluginsDirectory -string /Users/admin/Macotron
defaults write io.statico.macotron wizardCompleted -bool true
mkdir -p ~/Macotron/plugins
C=/Applications/Macotron.app/Contents/Resources/Catalog
for p in meetings now-playing windows window-grid cpu-graph weather mini-calendar file-search calculator web-search; do cp \$C/\$p.js ~/Macotron/plugins/; done
cp '$S/deploy-status.js' '$S/battery.js' ~/Macotron/plugins/
cat > ~/Macotron/settings.json <<'EOF'
{\"keyboardShortcuts\":{},\"launcher\":{\"hotkey\":\"opt+space\"},\"modules\":{},\"pluginSettings\":{\"weather.js\":{\"location\":\"Cupertino, CA\"},\"mini-calendar.js\":{\"clocks\":\"America/New_York = New York\\nEurope/London = London\\nAsia/Tokyo = Tokyo\"},\"file-search.js\":{\"ignorePatterns\":\"node_modules\\n*.tmp\\ngo/pkg\\nLibrary\\nactions-runner\\nMacotron\"}},\"disabledPlugins\":[],\"launcherFavorites\":[],\"commandShortcuts\":{},\"ui\":{\"textScale\":1,\"launcherBackground\":\"translucent\",\"hotReload\":true,\"appearance\":\"system\",\"showMenuBarIcon\":true}}
EOF
plutil -p ~/Macotron/settings.json"
x "defaults write com.apple.dock autohide -bool true
defaults -currentHost write com.apple.Spotlight MenuItemHidden -int 1
defaults write com.apple.WindowManager StandardHideWidgets -bool true
defaults write com.apple.WindowManager StageManagerHideWidgets -bool true
defaults write com.apple.WindowManager EnableStandardClickToShowDesktop -bool false
killall Dock WindowManager NotificationCenter Spotlight 2>/dev/null; true"
# report.pdf/.docx come from report.html (Chrome --print-to-pdf) and docx.py.
x "cd ~/Documents && cp '$S/report.pdf' 'Quarterly report.pdf' && cp '$S/report.docx' 'Quarterly report.docx'
cp '$S/roadmap.md' 'Roadmap 2027.md'; cp '$S/notes.md' 'Release notes 0.8.md'
cp '$S/trip.txt' 'Trip itinerary.txt'; cp '$S/somafm.html' ~/somafm.html; mkdir -p ~/Projects/macotron-site"
echo setup done
