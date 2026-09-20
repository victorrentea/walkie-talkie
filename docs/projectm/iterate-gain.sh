#!/bin/bash
# Iterates ProjectMHalo.gainScale until the native route's mean luminance
# matches the web twin's: shoot (web + native 1×, 3…8 s), lum.py → ratios,
# scale ← scale × ratio^0.8, again. Prints each round's table and the final
# JSON to paste into ProjectMHalo.gainScale.
#   docs/projectm/iterate-gain.sh <outdir> [rounds] [start-json]
if [ -z "$HANDS_OFF_WRAPPED" ]; then export HANDS_OFF_WRAPPED=1; exec $HOME/bin/hands-off run "halo gain iteration: web vs native" -- "$0" "$@"; fi
cd "$(dirname "$0")/../.."
OUT=$1; ROUNDS=${2:-3}; SCALE=${3:-'{"7": 0.72, "8": 0.49, "20": 0.95, "85": 0.47, "87": 0.42, "103": 2.0}'}
mkdir -p "$OUT"
for R in $(seq 1 $ROUNDS); do
  echo "== round $R, scale $SCALE"
  rm -rf "$OUT/r$R"; WT_PM_GAIN_SCALE="$SCALE" ROUTES="web native1" docs/projectm/shoot.sh "$OUT/r$R" > /dev/null
  python3 docs/projectm/lum.py "$OUT/r$R" "$OUT/r$R/ratios.json"
  SCALE=$(python3 - "$SCALE" "$OUT/r$R/ratios.json" <<'PY'
import json, sys
scale = json.loads(sys.argv[1]); ratios = json.load(open(sys.argv[2]))
for k, r in ratios.items():
    scale[k] = round(min(8.0, max(0.1, scale.get(k, 1.0) * r ** 0.8)), 3)
print(json.dumps(scale))
PY
)
  echo "$SCALE" > "$OUT/scale-after-r$R.json"
done
echo "final scale: $SCALE"
