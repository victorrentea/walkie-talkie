#!/bin/bash
# The measurement sweep behind docs/projectm/REPORT.md: every preset, the web
# route (butterchurn in a WKWebView) against the native one (projectM), on the
# same 12 s demo voice (WT_HALO_DEMO + WT_HALO_DEMO_AUDIO), ring up on the real
# pointer. Per run: `top` 1 s samples of the app and, for the web route, the
# WebContent/GPU processes it spawned (the ones that were not there before it
# started); RSS from ps; region captures at 4, 5.5 and 7 s.
#   docs/projectm/sweep.sh <outdir> [styles...]
# Runs under hands-off (the whole sweep holds the locks): nothing here moves the
# pointer or activates a window; the demo panels are non-activating.
if [ -z "$HANDS_OFF_WRAPPED" ]; then export HANDS_OFF_WRAPPED=1; exec $HOME/bin/hands-off run "halo sweep: web vs native projectM" -- "$0" "$@"; fi
cd "$(dirname "$0")/../.."
OUT=$1; shift; mkdir -p "$OUT"
STYLES="$@"; [ -z "$STYLES" ] && STYLES="milkdrop7 milkdrop8 milkdrop20 milkdrop85 milkdrop87 milkdrop103"
REGION=${REGION:-0,0,1000,700}
run() {  # run <tag> <env...>
  local TAG=$1; shift
  local BEFORE=$(pgrep -f "com.apple.WebKit.(WebContent|GPU)" | sort)
  # The WebKit GPU process is shared by every WKWebView on the Mac (measured: one
  # burning 50 % of a core for another app the whole night), so its idle load is
  # sampled for 3 s before each run and subtracted by summarize.py.
  local GPUS=$(pgrep -f "com.apple.WebKit.GPU" | tr '\n' ' ')
  local GPIDS=""; for g in $GPUS; do GPIDS="$GPIDS -pid $g"; done
  local BASE=$( [ -n "$GPIDS" ] && top -l 4 -s 1 -stats pid,cpu $GPIDS 2>/dev/null | grep -E "^[0-9]+ " | awk 'NR>0{c[$1]+=$2; n[$1]++} END{for (p in c) printf "base %s %.1f\n", p, c[p]/n[p]}' )
  env "$@" WT_HALO_DEMO=12 WT_HALO_DEMO_AUDIO=1 WT_PM_STATS=1 WT_ALLOW_DIRECT=1 ./.build/debug/WalkieTalkie > "$OUT/$TAG.log" 2>&1 &
  local P=$!
  sleep 3.5
  local AFTER=$(pgrep -f "com.apple.WebKit.(WebContent|GPU)" | sort)
  # the WebContent it spawned, plus every WebKit GPU process (shared; the demo's is the one that moves)
  local NEW="$(comm -13 <(echo "$BEFORE") <(echo "$AFTER")) $(pgrep -f com.apple.WebKit.GPU)"
  local WS=$(pgrep -x WindowServer | head -1)
  local PIDS="-pid $P -pid $WS"; for w in $NEW; do PIDS="$PIDS -pid $w"; done
  # A web view spawns its OWN GPU process beside its WebContent (measured: a
  # census of a Tunnel demo — GPU 56–59 %, WebContent 26 %, app 5 %); the roles
  # are recorded so summarize.py can tell them apart.
  local ROLES=""; for p in $NEW; do ROLES="$ROLES $p:$(ps -o comm= -p $p 2>/dev/null | sed 's|.*com.apple.WebKit.||')"; done
  { echo "app=$P windowserver=$WS webkit=$(echo $NEW | tr '\n' ' ') gpu=$GPUS roles=$ROLES"; echo "$BASE"; } > "$OUT/$TAG.stats"
  # 4 one-second samples from t≈3.5 s (the first top sample is discarded by top itself)
  top -l 5 -s 1 -stats pid,cpu,rsize,command $PIDS 2>/dev/null | grep -E "^[0-9]+ " >> "$OUT/$TAG.stats" &
  local T=$!
  sleep 0.5; screencapture -x -R $REGION "$OUT/$TAG-4.0.png"
  sleep 1.5; screencapture -x -R $REGION "$OUT/$TAG-5.5.png"
  sleep 1.5; screencapture -x -R $REGION "$OUT/$TAG-7.0.png"
  wait $T
  ps -o pid=,rss=,command= -p $P $NEW 2>/dev/null | awk '{printf "rss %s %.0fMB %s\n",$1,$2/1024,$3}' | cut -c1-110 >> "$OUT/$TAG.stats"
  wait $P 2>/dev/null
  sleep 0.5
}
run film WT_HALO_STYLE=lightning
for S in $STYLES; do
  run "$S-web"     WT_HALO_ENGINE=web    WT_HALO_STYLE=$S
  run "$S-native1" WT_HALO_ENGINE=native WT_HALO_STYLE=$S WT_PM_SCALE=1
  run "$S-native2" WT_HALO_ENGINE=native WT_HALO_STYLE=$S WT_PM_SCALE=2
done
echo "done: $(ls $OUT/*.png | wc -l) captures in $OUT"
