#!/bin/zsh
# One real-audio dictation from a desk, no speaker (test-plan §6.2, gap G1):
#   evals/plan/looprun.sh <workdir> <wav>   — run under `~/bin/hands-off run "…" --` (it posts F10)
# Sets the mic override to Loopback's "🎓 TO Wispr", opens a witness Terminal tab running `cat`
# and binds it, starts the dictation with F10, plays the WAV into the Loopback (48 kHz, 2 ch,
# 0.5 s of silence either side), waits ${WAIT:-6} s, stops with F10, prints the log lines that
# matter and the witness's tail, then unbinds, clears the override and closes the tab.
# Precondition: the 440 Hz pass-thru check on the Loopback device (see the plan).
set -u
B=http://127.0.0.1:8917; LOG=~/.walkie-talkie/relay.log; S=$1; CLIP=$2; DEV="🧪 WT Inject"
# X-Walkie-Token (2026-11-25): read at every call — a relaunched app writes a new one;
# sent only to the app's own port and never in argv (`helpers/walkie_auth.sh`, Fable review).
. "${0:A:h}/../../helpers/walkie_auth.sh"
post(){ curl -s -m 20 -X POST "$B$1" -H 'content-type: application/json' -H @<(wt_auth 8917) -d "${2:-{\}}"; }
MARK=$(wc -c < $LOG)
post /test/mic "{\"device\":\"WT Inject\"}" >/dev/null
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
curl -s -H @<(wt_auth 8917) $B/test/state | python3 -c "import sys,json; d=json.load(sys.stdin)['liveCaption']; print('band:', {k:d[k] for k in ['words','committed','corrections','correcting','eraseFront']})"
post /test/gesture '{"name":"forward-right"}' >/dev/null
for i in $(seq 1 240); do curl -s -H @<(wt_auth 8917) $B/test/state | /usr/bin/grep -q '"busy":false' && break; sleep 0.5; done; sleep 1
echo "---- log"; /usr/bin/tail -c +$((MARK+1)) $LOG | /usr/bin/grep -aE "live caption|live correction|elevenlabs:|delivery|returned no words|words landed|401|injected|↪️|standing in|fall|whisper helper|local whisper" | LC_ALL=C /usr/bin/cut -c1-230
echo "---- witness"; /usr/bin/tail -c 400 $S/witness.txt 2>/dev/null; echo
post /unbind >/dev/null; post /test/mic '{"device":null}' >/dev/null
# Close the witness without Terminal's "Terminate?" sheet (2026-09-27): kill what runs on its tty,
# wait up to 5 s for the tab to go idle, close it by tty; a tab still busy is left and said so.
WDEV=$TTY
for p in $(ps -t ${WDEV#/dev/} -o pid=,comm= | /usr/bin/awk '$2 !~ /login/ {print $1}'); do kill -9 $p 2>/dev/null; done
tabstate(){ osascript -e 'tell application "Terminal"' -e 'repeat with w in windows' -e 'try' -e 'repeat with t in tabs of w' \
  -e "if tty of t is \"$WDEV\" then return (busy of t) as text" -e 'end repeat' -e 'end try' -e 'end repeat' -e 'return "gone"' -e 'end tell'; }
for i in $(seq 1 25); do [[ $(tabstate) == true ]] || break; sleep 0.2; done
case $(tabstate) in
  true) echo "⚠️ witness $WDEV still busy 5 s after the kill — left open (a close would raise Terminate?)";;
  false) osascript -e 'tell application "Terminal"' -e 'repeat with w in windows' -e 'try' -e 'repeat with t in tabs of w' \
           -e "if tty of t is \"$WDEV\" then" -e 'close w saving no' -e 'return' -e 'end if' -e 'end repeat' -e 'end try' -e 'end repeat' -e 'end tell' >/dev/null;;
esac
defaults read ro.victorrentea.wispr-relay elevenCostBatchSeconds 2>/dev/null; defaults read ro.victorrentea.wispr-relay elevenCostLiveSeconds
