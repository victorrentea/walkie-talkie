#!/bin/bash
# Engine-only captures for the side-by-side in REPORT.md: for every preset, the
# web route's keyed frame (halo.snapshot(), WT_MD_SHOOT) and the native route's
# (WT_PM_SHOOT, at 1× and 2×), each at 3, 5 and 7 s into the same demo voice. Nothing of the
# screen is in them; docs/projectm/compose.py puts them side by side.
#   docs/projectm/shoot.sh <outdir> [styles...]
if [ -z "$HANDS_OFF_WRAPPED" ]; then export HANDS_OFF_WRAPPED=1; exec $HOME/bin/hands-off run "halo captures: web vs native projectM" -- "$0" "$@"; fi
cd "$(dirname "$0")/../.."
OUT=$1; shift; mkdir -p "$OUT"
STYLES="$@"; [ -z "$STYLES" ] && STYLES="milkdrop7 milkdrop8 milkdrop20 milkdrop85 milkdrop87 milkdrop103"
for S in $STYLES; do
  WT_HALO_ENGINE=web    WT_HALO_STYLE=$S WT_MD_SHOOT=$OUT/$S-web     WT_HALO_DEMO=9 WT_HALO_DEMO_AUDIO=1 WT_ALLOW_DIRECT=1 ./.build/debug/WalkieTalkie > $OUT/$S-web.log 2>&1
  WT_HALO_ENGINE=native WT_HALO_STYLE=$S WT_PM_SHOOT=$OUT/$S-native1 WT_PM_SCALE=1 WT_HALO_DEMO=9 WT_HALO_DEMO_AUDIO=1 WT_ALLOW_DIRECT=1 ./.build/debug/WalkieTalkie > $OUT/$S-native1.log 2>&1
  WT_HALO_ENGINE=native WT_HALO_STYLE=$S WT_PM_SHOOT=$OUT/$S-native2 WT_PM_SCALE=2 WT_HALO_DEMO=9 WT_HALO_DEMO_AUDIO=1 WT_ALLOW_DIRECT=1 ./.build/debug/WalkieTalkie > $OUT/$S-native2.log 2>&1
done
ls $OUT/*.png
