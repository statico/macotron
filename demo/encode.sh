#!/bin/bash
# Turn the raw recordings in tmp/demo-share (2560x1600, 60 fps) into the
# homepage tour, the social card strip and the README GIF. Each clip's trim,
# crop and poster time were picked by eye from a contact sheet:
#   ffmpeg -i tmp/demo-share/NAME.mov -vf "fps=2,scale=320:-1,tile=4x5" -frames:v 1 sheet.png
# Re-pick them after a reshoot; the timings shift a little every take.
set -e
cd "$(dirname "$0")/.."
FF=${FF:-ffmpeg}
IN=tmp/demo-share
OUT=site/media/tour
X264="-c:v libx264 -preset slow -an -movflags +faststart"

# clip NAME TRIM DURATION CROP POSTER: crop the source, scale to 1280x800.
clip() {
    local t=(); [ "$3" != - ] && t=(-t "$3")
    local c=; [ "$4" != - ] && c="crop=$4,"
    $FF -v error -y -ss "$2" -i $IN/$1.mov "${t[@]}" \
        -vf "${c}scale=1280:800:flags=lanczos,fps=30,format=yuv420p" $X264 -crf 26 $OUT/$1.mp4
    poster $1 $5
}
poster() { $FF -v error -y -ss $2 -i $OUT/$1.mp4 -frames:v 1 -q:v 3 $OUT/$1.jpg; }

# Smoothstep from 0 to 1 as $1 goes from 0 to 1, for zoompan expressions.
E() { echo "(clip(($1),0,1)*clip(($1),0,1)*(3-2*clip(($1),0,1)))"; }

# zoom NAME TRIM DURATION ZOOM CENTER_X POSTER: zoompan along the top edge.
# Upscaling to 5120 first keeps zoompan's integer crop from jittering.
zoom() {
    $FF -v error -y -ss "$2" -i $IN/$1.mov -t "$3" \
        -vf "fps=30,scale=5120:3200:flags=lanczos,zoompan=z='$4':x='clip(2*($5)-iw/zoom/2,0,iw-iw/zoom)':y=0:d=1:s=1280x800:fps=30,format=yuv420p" \
        $X264 -crf 24 $OUT/$1.mp4
    poster $1 $6
}

# Menu bar: zoom 3.5x onto the left end of the items, pan right across
# them, zoom back out. The recording is a still menu bar.
A=$(E "(it-0.2)/1.3"); B=$(E "(it-1.5)/8"); C=$(E "(it-9.8)/1.6")
zoom menubar 0 12.4 "1+2.5*$A-2.5*$C" "1350+810*$B" 5

# Launcher: crop to the panel so it fills the frame; the 9-row "cal" list fits.
clip launcher 0.6 - 1720:1075:420:230 1.5

# At a glance: the right half of the menu bar and its menus. The trim skips
# a Software Update banner.
clip system 0.5 16.5 1600:1000:960:0 12.5

# Now playing: 1:1 crop of the top left of the menu bar items.
clip nowplaying 0.6 7.2 1280:800:800:0 2.4

# Meetings: zoom 3x onto "Design review · Now" (x 1310 px), then back out
# just as the overlay opens 4.25 s in.
A=$(E "(it-0.1)/0.9"); C=$(E "(it-3.6)/0.7")
zoom meetings 31 10 "1+2*$A-2*$C" 1310 7

clip windows 0.3 - - 8.8
clip community 0.8 - - 26.5

# Social card: a strip of the menu bar from the left of the items to just
# before the clock. Then screenshot site/og.html at 1200x630 to site/og.png.
$FF -v error -y -ss 0.5 -i $IN/menubar.mov -frames:v 1 -vf "crop=1380:48:900:0" site/og-menubar.png

# README: launcher then the first 15 s of the glance clip, 720 px at 12 fps.
$FF -v error -y -i $OUT/launcher.mp4 -t 15 -i $OUT/system.mp4 -filter_complex \
    "[0:v][1:v]concat=n=2:v=1,fps=12,scale=720:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" \
    docs/media/highlights.gif
ls -la $OUT site/og-menubar.png docs/media/highlights.gif
