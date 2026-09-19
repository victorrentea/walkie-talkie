#!/bin/bash
# One scene: put the page up, park the pointer on the highlighted word, open a
# dictation (so every decoration is on the screen), and take the pictures.
#
# The only thing here that synthesises input is the pointer move, and it is done
# under `hands-off` — which draws locks of its own, so the run waits for them to
# come down before any shutter fires. Everything after that is HTTP and a
# subprocess: nothing this script does touches the mouse or the keyboard.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
WT=$(cd "$HERE/../.." && pwd)
scene="$1"; out="$HERE/out/$scene"; mkdir -p "$out"
R=http://127.0.0.1:8917
cd "$HERE"

~/bin/hands-off run "încarc pagina scenei $scene în Chrome" -- \
  bash -c "open -a 'Google Chrome' $HERE/scene-$scene.html; sleep 3" >/dev/null

/usr/sbin/screencapture -x -D 1 "$out/00-locate.png"
read -r x0 y0 x1 y1 <<<"$(python3 - "$out/00-locate.png" <<'PY'
import sys; sys.path.insert(0, ".")
from findsel import find
box, n = find(sys.argv[1])
assert box, f"no selection highlight found ({n} px)"
print(*box)
PY
)"
echo "selection box (image px): $x0 $y0 $x1 $y1"
px=$(( (x0 + x1) / 4 )); py=$(( (y0 + y1) / 4 ))   # centre, image px -> points
~/bin/hands-off run "mut pointerul pe cuvântul selectat" -- \
  "$HERE/mouse.py" "$px" "$py" >/dev/null
sleep 5   # let the hands-off locks leave the screen before anything is shot
~/bin/hands-off state || true
# The control frame: the same screen, seconds earlier, with no dictation open
# and nothing of this app or of hands-off drawn on it.
/usr/sbin/screencapture -x -D 1 "$out/01-control.png"

curl -s -X POST "$R/test/dictation/start" -o "$out/10-start.json"
sleep 2
curl -s "$R/test/state" -o "$out/11-state-open.json"
/usr/sbin/screencapture -x -D 1 "$out/12-during.png"

# The recording, through the same `ScreenFilm` the 🔽 ↑ gesture drives — the one
# capture path in the app that is not `/usr/sbin/screencapture`.
( cd "$WT" && WT_SHOOT_FILM=4 ./.build/debug/WalkieTalkie ) > "$out/13-film.txt" 2>&1 || true
curl -s "$R/test/state" -o "$out/14-state-late.json"
curl -s -X POST "$R/test/cancel" -o "$out/15-cancel.json"
# The app's own picture: the newest `shot#00…` under the shots tree, which is
# the file `ScreenCapture.grab` just wrote — the same function the 🔽 shutter
# calls, so what holds for this frame holds for a hand-taken one.
shots=~/Library/Caches/ro.victorrentea.wispr-relay/shots
app_shot=$(find "$shots" -name 'shot#*.jpg' ! -name '*-small.jpg' -newer "$out/01-control.png" | head -1)
app_small=$(find "$shots" -name 'shot#*-small.jpg' -newer "$out/01-control.png" | head -1)
cp "$app_shot" "$out/20-app-shot.jpg"
cp "$app_small" "$out/21-app-shot-handover.jpg"
film_dir=$(sed -n 's/^frames: //p' "$out/13-film.txt")
cp "$film_dir/frame-0005.jpg" "$out/30-film-frame.jpg"
cp "$film_dir/sheet.png" "$out/31-film-sheet.png"
echo "app shot: $app_shot"
echo "pointer parked at ${px},${py} pt"
tail -3 "$out/13-film.txt"
