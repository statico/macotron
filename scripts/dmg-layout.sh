#!/bin/sh
# Arranges the window of a read-write DMG: background picture, window size, and
# where the two icons sit. Only Finder writes the .DS_Store that stores this, so
# a machine where Finder cannot be scripted just ships the default list view.
#
# usage: scripts/dmg-layout.sh <rw.dmg> <volume name> <app name>
set -eu

dmg=$1
volume=$2
app=$3

mount=$(hdiutil attach -readwrite -noverify -noautoopen "$dmg" |
	sed -n 's/.*\(\/Volumes\/.*\)$/\1/p' | tail -1)
[ -n "$mount" ] || { echo "Could not mount $dmg"; exit 1; }

detach() {
	# Finder keeps the volume busy for a moment after it stops arranging it.
	for _ in 1 2 3 4 5; do
		hdiutil detach "$mount" -quiet 2>/dev/null && return 0
		sleep 1
	done
	hdiutil detach "$mount" -force -quiet
}
trap detach EXIT

if osascript - "$volume" "$app" <<'APPLESCRIPT'
on run argv
	set volumeName to item 1 of argv
	set appName to item 2 of argv
	tell application "Finder"
		tell disk volumeName
			open
			set current view of container window to icon view
			set toolbar visible of container window to false
			set statusbar visible of container window to false
			-- The picture is 640x400; the extra 28 points are the title bar.
			set the bounds of container window to {200, 140, 840, 568}
			set viewOptions to the icon view options of container window
			set arrangement of viewOptions to not arranged
			set icon size of viewOptions to 128
			set text size of viewOptions to 13
			set background picture of viewOptions to file ".background:background.tiff"
			set position of item appName of container window to {168, 228}
			set position of item "Applications" of container window to {472, 228}
			update without registering applications
			close
		end tell
	end tell
end run
APPLESCRIPT
then
	# Makes the mounted volume show the app icon instead of the plain disk.
	SetFile -a C "$mount" 2>/dev/null || true
else
	echo "  Finder would not arrange the DMG; shipping the default layout."
fi

# Finder writes .DS_Store lazily, so give it a moment before unmounting.
sleep 2
sync
