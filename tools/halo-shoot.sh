#!/bin/bash
# Captures of one halo style, with the style's id and name IN THE LOCK BANNER —
# Victor, 2026-09-21: *"cand mai redai animatii, pune in labelul de ecran blocat ce
# efect redai si id-ul, sa-ti spun care-mi place"*. Without it the amber on his
# screen is anonymous and a verdict cannot be attached to anything.
#   tools/halo-shoot.sh <outdir> <style> [voice-mode] [wav]
# Un singur rig de capturi pe mașină — vezi tools/halo-lock.sh.
HALO_LOCK_WHO="halo-shoot $2" . "$(dirname "$0")/halo-lock.sh"

OUT=$1; S=$2; M=${3:-direct}; WAV=$4
NAME=$(/usr/bin/grep -A2 "case .$S:" Sources/WalkieTalkie/HaloStyle.swift | /usr/bin/grep -o 'return "[^"]*"' | head -1 | cut -d'"' -f2)
mkdir -p "$OUT"
AUDIO=1; [ -n "$WAV" ] && AUDIO="clip:$WAV"
# Fără `exec`: el înlocuiește imaginea procesului și cu ea trap-ul care
# eliberează lacătul (`tools/halo-lock.sh`). Shell-ul ăsta costă nimic și curăță.
$HOME/bin/hands-off run "halo: $S — ${NAME:-?} · voce: $M" -- \
  env WT_HALO_ENGINE=native WT_HALO_STYLE=$S WT_PM_SHOOT=$OUT/$S-$M WT_PM_SCALE=1 \
      WT_HALO_VOICE=$M WT_HALO_DEMO=26 WT_HALO_DEMO_AUDIO="$AUDIO" WT_ALLOW_DIRECT=1 \
      ./.build/debug/WalkieTalkie
