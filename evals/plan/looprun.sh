#!/bin/zsh
# One real-audio dictation from a desk, no speaker (test-plan §6.2, gap G1):
#   evals/plan/looprun.sh <workdir> <wav>   — run under `~/bin/hands-off run "…" --` (it posts F10)
# Sets the mic override to Loopback's "🎓 TO Wispr", opens a witness Terminal tab running `cat`
# and binds it, starts the dictation with F10, plays the WAV into the Loopback (48 kHz, 2 ch,
# 0.5 s of silence either side), waits ${WAIT:-6} s, stops with F10, prints the log lines that
# matter and the witness's tail, then unbinds, clears the override and closes the tab.
# Precondition: the 440 Hz pass-thru check on the Loopback device (see the plan).
set -u
B=http://127.0.0.1:8917; LOG=~/.walkie-talkie/relay.log; S=$1; CLIP=$2; DEV="🎓 TO Wispr"
post(){ curl -s -m 20 -X POST "$B$1" -H 'content-type: application/json' -d "${2:-{\}}"; }
MARK=$(wc -c < $LOG)
post /test/mic "{\"device\":\"TO Wispr\"}" >/dev/null
TTY=$(osascript -e 'tell application "Terminal" to set t to do script "printf \"\\\\e]0;wt-witness\\\\a\"; stty -echo; exec cat >> '"$S"'/witness.txt"' -e 'tell application "Terminal" to get tty of t')
post /bind "{\"tty\":\"${TTY#/dev/}\"}" >/dev/null
post /test/gesture '{"name":"forward-right"}' >/dev/null
for i in $(seq 1 30); do /usr/bin/tail -c +$((MARK+1)) $LOG | /usr/bin/grep -aq "mic: recording through" && break; sleep 0.2; done
/usr/bin/tail -c +$((MARK+1)) $LOG | /usr/bin/grep -a "mic: recording through"
sleep 0.5
python3 - "$CLIP" "$DEV" <<'PY'
import sys, wave, numpy as np, sounddevice as sd
from scipy.signal import resample_poly
clip, name = sys.argv[1], sys.argv[2]
idx=[i for i,d in enumerate(sd.query_devices()) if name.lower() in d['name'].lower()][0]
w=wave.open(clip); a=np.frombuffer(w.readframes(w.getnframes()),np.int16).astype(np.float32)/32768; sr=w.getframerate()
a=resample_poly(a,48000,sr); a=a/max(1e-6,np.abs(a).max())*0.5
a=np.concatenate([np.zeros(24000,np.float32),a,np.zeros(24000,np.float32)])
sd.play(np.repeat(a[:,None],2,1),48000,device=idx,blocking=True)
print("played", len(a)/48000, "s")
PY
echo "waiting"; sleep ${WAIT:-6}
curl -s $B/test/state | python3 -c "import sys,json; d=json.load(sys.stdin)['liveCaption']; print('band:', {k:d[k] for k in ['words','committed','corrections','correcting','eraseFront']})"
post /test/gesture '{"name":"forward-right"}' >/dev/null
for i in $(seq 1 240); do curl -s $B/test/state | /usr/bin/grep -q '"busy":false' && break; sleep 0.5; done; sleep 1
echo "---- log"; /usr/bin/tail -c +$((MARK+1)) $LOG | /usr/bin/grep -aE "live caption|live correction|elevenlabs:|delivery|returned no words|words landed|401|injected|↪️|standing in|fall|whisper helper|local whisper" | LC_ALL=C /usr/bin/cut -c1-230
echo "---- witness"; /usr/bin/tail -c 400 $S/witness.txt 2>/dev/null; echo
post /unbind >/dev/null; post /test/mic '{"device":null}' >/dev/null
osascript -e 'tell application "Terminal" to close (every window whose name contains "wt-witness")' 2>/dev/null
defaults read ro.victorrentea.wispr-relay elevenCostBatchSeconds 2>/dev/null; defaults read ro.victorrentea.wispr-relay elevenCostLiveSeconds
