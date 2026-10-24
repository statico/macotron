#!/bin/bash
# Cut the standalone demo video: a title card, every tour clip plus the
# deploy-status and clipboard/emoji recordings, each with a lower-third caption, and a closing
# card. Captions come from demo/captions.tsv, rendered to PNG by
# demo/captions.swift (this ffmpeg has no drawtext), and are overlaid with a
# fade. Run demo/encode.sh first; this reads site/media/tour/*.mp4.
set -e
cd "$(dirname "$0")/.."
FF=${FF:-ffmpeg}
TOUR=site/media/tour
RAW=tmp/demo-share
W=tmp/video
OUT=tmp/macotron-demo.mp4
X264="-c:v libx264 -preset slow -crf 23 -pix_fmt yuv420p -r 30 -an"
# Tag every segment BT.709 alike, or the stream-copied concat changes color
# parameters mid-stream and players re-init at each card.
BT709="setparams=colorspace=bt709:color_primaries=bt709:color_trc=bt709:range=tv"
RGB2YUV="scale=out_color_matrix=bt709:out_range=tv"
FADE=0.35
mkdir -p $W
rm -f $W/*.mp4 $W/list.txt

swift demo/captions.swift demo/captions.tsv site/icon.png $W

# seg NAME SOURCE SEEK DURATION VF [CAPTION_END]: cut a 1280x800 segment,
# overlay NAME.png from 0.5 s to CAPTION_END (default 0.8 s before the
# end), and fade from and to black.
n=0
seg() {
    local d=$4 out=$W/$(printf %02d $n)-$1.mp4
    local t=(); [ "$3" != - ] && t=(-ss $3)
    local e=${6:-$(echo "$d - 0.8" | bc)}
    $FF -v error -y "${t[@]}" -i $2 -loop 1 -i $W/$1.png -t $d -filter_complex \
        "[0:v]$5,scale=1280:800:flags=lanczos,fps=30,format=yuv420p[v];[1:v]$RGB2YUV,format=yuva420p,fade=in:st=0.5:d=$FADE:alpha=1,fade=out:st=$e:d=$FADE:alpha=1[c];[v][c]overlay=shortest=1,fade=in:d=$FADE,fade=out:st=$(echo "$d - $FADE" | bc):d=$FADE,$BT709" \
        $X264 $out
    echo "file '$(basename $out)'" >> $W/list.txt
    n=$((n + 1))
}

# card NAME DURATION: a still card that fades from and to black.
card() {
    local out=$W/$(printf %02d $n)-$1.mp4
    $FF -v error -y -loop 1 -i $W/$1.png -t $2 \
        -vf "fps=30,$RGB2YUV,format=yuv420p,fade=in:d=0.5,fade=out:st=$(echo "$2 - 0.5" | bc):d=0.5,$BT709" $X264 $out
    echo "file '$(basename $out)'" >> $W/list.txt
    n=$((n + 1))
}

card title 3.5
seg menubar    $TOUR/menubar.mp4    - 12.4 null
# The caption leaves before the 9-row "cal" list reaches it.
seg launcher   $TOUR/launcher.mp4   - 9.9  null 6
# Clipboard history and the emoji picker (clip_paste.py), full frame. The
# take ends as the emoji lands, so hold the last frame.
seg paste      $RAW/paste.mov     0.3 12.4 "tpad=stop_mode=clone:stop_duration=2"
seg windows    $TOUR/windows.mp4    - 17.5 null
# Deploy status: a still 2.5x crop of the menu bar while the canned
# counts tick between "↓ n" and "✓ current".
seg deploy     $RAW/deploy.mov    0.3 12.8 "crop=1024:640:1018:0"
seg meetings   $TOUR/meetings.mp4   - 10   null
seg nowplaying $TOUR/nowplaying.mp4 - 7.2  null
seg system     $TOUR/system.mp4     - 16.5 null
seg community  $TOUR/community.mp4  - 27.4 null
card end 5

# Every segment shares one encoding, so the concat is a stream copy.
$FF -v error -y -f concat -i $W/list.txt -c copy -movflags +faststart $OUT

# Contact sheet: 48 evenly spaced frames, to check caption placement.
D=$(ffprobe -v error -show_entries format=duration -of csv=p=0 $OUT)
$FF -v error -y -i $OUT -vf "fps=48/$D,scale=426:-1,tile=6x8" -frames:v 1 tmp/macotron-demo-sheet.jpg
ls -la $OUT; echo "$D s"
