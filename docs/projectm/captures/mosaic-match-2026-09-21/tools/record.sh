#!/bin/bash
# Screen recordings of the Mosaic demo ring on a BLACK backdrop, same clip every run.
#   record.sh <outdir> <tag>=<route> ...     routes: web | native | native-rs
# The pointer is warped to the centre of the built-in display and restored after.
set -u
if [ -z "${HANDS_OFF_WRAPPED:-}" ]; then export HANDS_OFF_WRAPPED=1; exec $HOME/bin/hands-off run "Mosaic recordings on black: web vs native projectM" -- "$0" "$@"; fi
cd /Users/victorrentea/workspace/walkie-talkie
S=$SCRATCH
OUT=$1; shift; mkdir -p "$OUT"
PX=864; PY=558; HALF=540; SECS=${SECS:-11}
ORIG=$(python3 -c "from Quartz import CGEventCreate, CGEventGetLocation; p=CGEventGetLocation(CGEventCreate(None)); print(int(p.x),int(p.y))")
warp() { python3 -c "from Quartz import CGWarpMouseCursorPosition; CGWarpMouseCursorPosition(($1,$2))"; }
$S/mm/black & BLACK=$!
sleep 0.8
for spec in "$@"; do
  TAG=${spec%%=*}; R=${spec#*=}; AUDIO="WT_HALO_DEMO_AUDIO=clip"
  case $R in
    web)       ENV="WT_HALO_ENGINE=web WT_HALO_PRESET_OPTS={\"speed\":1} WT_MD_LEVELS=1" ;;
    native)    ENV="WT_HALO_ENGINE=native WT_HALO_IGNORE_WEBONLY=1 PM_AUDIO_LOG=1" ;;
    native-rs) ENV="WT_HALO_ENGINE=native WT_HALO_IGNORE_WEBONLY=1 WT_PM_RESAMPLE=1 PM_AUDIO_LOG=1" ;;
    native-bc) ENV="WT_HALO_ENGINE=native WT_HALO_IGNORE_WEBONLY=1 WT_PM_RESAMPLE=1 PM_BC_AUDIO=1 PM_AUDIO_LOG=1" ;;
    web-tone)      ENV="WT_HALO_ENGINE=web WT_HALO_PRESET_OPTS={\"speed\":1} WT_MD_LEVELS=1"; AUDIO="WT_HALO_DEMO_AUDIO=clip:$S/mm/tone.wav" ;;
    native-tone)   ENV="WT_HALO_ENGINE=native WT_HALO_IGNORE_WEBONLY=1 PM_AUDIO_LOG=1"; AUDIO="WT_HALO_DEMO_AUDIO=clip:$S/mm/tone.wav" ;;
    web-silent)    ENV="WT_HALO_ENGINE=web WT_HALO_PRESET_OPTS={\"speed\":1} WT_MD_LEVELS=1"; AUDIO="" ;;
    native-silent) ENV="WT_HALO_ENGINE=native WT_HALO_IGNORE_WEBONLY=1 PM_AUDIO_LOG=1"; AUDIO="" ;;
  esac
  warp $PX $PY; sleep 0.2
  env $ENV WT_HALO_STYLE=milkdrop99 WT_HALO_DEMO=$SECS $AUDIO WT_ALLOW_DIRECT=1 ./.build/debug/WalkieTalkie > "$OUT/$TAG.log" 2>&1 &
  PID=$!
  python3 -c "import time; print(time.time())" > "$OUT/$TAG.t0"
  screencapture -x -V $((SECS-1)) -R$((PX-HALF)),$((PY-HALF)),$((2*HALF)),$((2*HALF)) "$OUT/$TAG.mov"
  wait $PID
  sleep 0.5
done
kill $BLACK
warp $ORIG
ls -la "$OUT"/*.mov
