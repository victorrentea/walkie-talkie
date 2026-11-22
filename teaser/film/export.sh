#!/bin/zsh
# export.sh <raw name> <clip id> <start s> <end s> ['json marks']  →  teaser/footage/<clip id>.mp4 (1920x1080, 30 fps, no audio)
# Optional marks (seconds inside the clip) go beside it as <clip id>.json for the editor.
source "$(dirname "$0")/lib.sh"
mkdir -p "$TEASER_DIR/footage"
nice -n 5 ffmpeg -loglevel error -y -ss "$3" -to "$4" -i "$RAW/$1.mp4" -an -r 30 -c:v libx264 -preset medium -crf 17 \
  -pix_fmt yuv420p -movflags +faststart "$TEASER_DIR/footage/$2.mp4"
[ -n "${5:-}" ] && print -r -- "$5" > "$TEASER_DIR/footage/$2.json"
ffprobe -v error -show_entries format=duration -of csv=p=0 "$TEASER_DIR/footage/$2.mp4"
