#!/bin/bash
# **Filmul efectului pe fundal negru** — rig-ul care a mers cel mai bine în studiul
# Mosaic, scos din directorul ăluia și făcut să meargă pe orice preset.
#
# Victor, 2026-09-22: *"ieri, cred că în studiul pentru Mozaic, un efect foarte
# benefic a fost să înregistrezi efectul pe un fundal negru. Pot să facă la fel și
# astăzi. Pe rând, evident."*
#
# De ce contează, și de ce nu înlocuiește capturile de cadru: `WT_PM_SHOOT` /
# `WT_MD_SHOOT` scot ce desenează motorul, adică exact ce se calibrează, dar șase
# cadre cheie nu spun nimic despre *mișcare* — inerția liniei interioare, pulsul pe
# bătaie, momentul în care efectul se aprinde. Un film de 30 fps peste negru le
# arată pe toate, iar negrul e ce presupune oricum formula de luminanță (rgb ×
# alpha, peste negru), deci ce se vede în film e ce măsoară `lum.py`.
#
#   tools/halo-record.sh <outdir> <stil> <tag>=<rută> ...
#   rute: web | native | native:<gainScale>
#
#   tools/halo-record.sh /tmp/sigil milkdrop213 web=web g1=native:1 g05=native:0.5
#
# „Pe rând, evident" e lacătul: tot ce e aici trece prin `tools/halo-lock.sh`, deci
# două campanii pot chema scriptul în același timp fără să-și strice filmele — a
# doua așteaptă și spune pe cine așteaptă.
set -u
cd "$(dirname "$0")/.."

# `hands-off`: rig-ul ăsta warpează cursorul și pune o fereastră neagră peste tot
# ecranul. Lacătele de pe ecran sunt singurul semn pe care Victor îl vede.
if [ -z "${HANDS_OFF_WRAPPED:-}" ]; then
  export HANDS_OFF_WRAPPED=1
  exec "$HOME/bin/hands-off" run "halo pe negru: $2" -- "$0" "$@"
fi

OUT=${1:?usage: halo-record.sh <outdir> <stil> <tag>=<rută> ...}; shift
S=${1:?lipsește stilul (ex. milkdrop213)}; shift
[ $# -gt 0 ] || { echo "nu ai cerut nicio rută (ex. web=web g1=native:1)"; exit 1; }

SECS=${SECS:-11}
WAV=${WAV:-$HOME/.walkie-talkie/voice-corpus/2026-09-21/14-46-41-11l108.wav}
NUM=${S#milkdrop}
mkdir -p "$OUT"

# Capcana din REPORT.md item 11: cu ecranul BLOCAT filmul iese negru pe ambele
# rute și arată exact ca un preset stricat. (`/usr/bin/python3` nu are PyObjC.)
LOCKED=$(python3 -c "import Quartz; d=Quartz.CGSessionCopyCurrentDictionary() or {}; print(1 if d.get('CGSSessionScreenIsLocked') else 0)" 2>/dev/null || echo "?")
case "$LOCKED" in
  1) echo "ecranul e BLOCAT — filmul ar ieși negru pe ambele rute; opresc"; exit 2 ;;
  0) ;;
  *) echo "nu pot citi starea de blocare (PyObjC lipsește) — continui, dar verifică" ;;
esac

# Un singur rig de capturi pe mașină — vezi tools/halo-lock.sh.
HALO_LOCK_WHO="halo-record $S" . tools/halo-lock.sh

# **Ora și commit-ul, scrise de scriptul însuși.** Victor le-a cerut explicit
# pentru fiecare rundă, iar o campanie care le notează de mână le notează greșit
# exact când contează: după un rebuild la mijloc.
note() { printf '%s  %-18s %s  binar %s\n' "$(date '+%F %H:%M:%S')" "$1" \
  "$(/usr/bin/git rev-parse --short HEAD)$(/usr/bin/git diff --quiet 2>/dev/null || echo '+dirty')" \
  "$(stat -f '%Sm' -t '%H:%M:%S' .build/debug/WalkieTalkie)" >> "$OUT/when.txt"; }

BLACKBIN="$HOME/.walkie-talkie/halo-black"
if [ ! -x "$BLACKBIN" ] || [ tools/halo-black.swift -nt "$BLACKBIN" ]; then
  swiftc -O tools/halo-black.swift -o "$BLACKBIN" || exit 1
fi

# Centrul ecranului încorporat, în coordonatele globale pe care le vrea
# `screencapture -R` (origine stânga-sus) — calculat, nu hardcodat ca în studiul
# Mosaic, ca să nu se strice dacă se schimbă rezoluția sau monitorul.
# `HALF` rămâne 540 ca în studiul Mosaic — filmele de ieri și cele de azi se
# compară cadru la cadru doar dacă au aceeași ramă; se strânge doar dacă ecranul
# e prea mic pentru ea.
read -r PX PY HALF <<<"$(HALF_WANT=${HALF:-540} python3 -c "
import os
from AppKit import NSScreen
f = NSScreen.screens()[0].frame()
half = min(int(os.environ['HALF_WANT']), int(min(f.size.width, f.size.height) / 2))
print(int(f.origin.x + f.size.width/2), int(f.origin.y + f.size.height/2), half)")"

ORIG=$(python3 -c "from Quartz import CGEventCreate, CGEventGetLocation; p=CGEventGetLocation(CGEventCreate(None)); print(int(p.x), int(p.y))")
warp() { python3 -c "from Quartz import CGWarpMouseCursorPosition; CGWarpMouseCursorPosition(($1,$2))"; }
NAME=$(/usr/bin/grep -A2 "case .$S:" Sources/WalkieTalkie/HaloStyle.swift | /usr/bin/grep -o 'return "[^"]*"' | head -1 | cut -d'"' -f2)
echo "$S — ${NAME:-?} · $SECS s pe rundă · centru $PX,$PY"

"$BLACKBIN" & BLACK=$!
trap 'kill $BLACK 2>/dev/null; warp $ORIG' EXIT INT TERM
sleep 0.8

for spec in "$@"; do
  TAG=${spec%%=*}; R=${spec#*=}
  case $R in
    web)      ENV="WT_HALO_ENGINE=web" ;;
    native)   ENV="WT_HALO_ENGINE=native" ;;
    native:*) ENV="WT_HALO_ENGINE=native WT_PM_STATS=1 WT_PM_GAIN_SCALE={\"$NUM\":${R#native:}}" ;;
    *) echo "rută necunoscută: $R (web | native | native:<gain>)"; exit 1 ;;
  esac
  note "$TAG=$R"
  warp $PX $PY; sleep 0.2
  env $ENV WT_HALO_STYLE=$S WT_HALO_VOICE=${VOICE:-direct} WT_HALO_DEMO=$SECS \
      WT_HALO_DEMO_AUDIO="clip:$WAV" WT_ALLOW_DIRECT=1 \
      ./.build/debug/WalkieTalkie > "$OUT/$TAG.log" 2>&1 &
  PID=$!
  python3 -c "import time; print(time.time())" > "$OUT/$TAG.t0"
  screencapture -x -V $((SECS-1)) -R$((PX-HALF)),$((PY-HALF)),$((2*HALF)),$((2*HALF)) "$OUT/$TAG.mov"
  wait $PID
  sleep 0.5
done

ls -la "$OUT"/*.mov
echo "--- when.txt ---"; cat "$OUT/when.txt"
