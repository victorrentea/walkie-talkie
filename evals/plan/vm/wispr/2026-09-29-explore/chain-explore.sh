#!/bin/bash
# chain-explore.sh NAME CAP IDS — one phase of the exploratory run with wave 5's preparation (drain, Wispr up,
# ghost check, local model warm, Engine = wispr, 440 Hz check), then run-exphase.sh. Through `tart exec`, detached:
#   tart exec wt-lab sh -c "nohup bash ~/wt-lab/chain-explore.sh E0 2400 'TQ1,…' >/dev/null 2>&1 </dev/null & echo launched"
N=~/wt-lab/night/explore; mkdir -p $N; C=$N/chain-explore.log
eng() { curl -s -H "X-Walkie-Token: $(cat ~/.walkie-talkie/test-token 2>/dev/null)" -m 60 -X POST 127.0.0.1:8917/engine -d '{"id":"wispr"}' >/dev/null; }
pfclean() { echo "pf rules after $1: $(sudo pfctl -a com.apple/wt-chaos -s rules 2>/dev/null | wc -l) in the anchor" >> $C; }
warm() {
  local r
  for i in $(seq 1 40); do
    r=$(curl -s -H "X-Walkie-Token: $(cat ~/.walkie-talkie/test-token 2>/dev/null)" -m 10 -X POST 127.0.0.1:8917/test/whisper -d '{}')
    echo "$r" | grep -q '"ready":true' && return
    echo "$r" | grep -q '"loading":true' || { echo "warm: restarting the helper $(date -u +%T)" >> $C; curl -s -H "X-Walkie-Token: $(cat ~/.walkie-talkie/test-token 2>/dev/null)" -m 10 -X POST 127.0.0.1:8917/test/whisper -d '{"restart":true}' >/dev/null; }
    sleep 5
  done
  echo "warm gave up $(date -u +%T)" >> $C
}
bh() { local r; r=$(/usr/bin/python3 ~/wt-lab/bhcheck.py "$1" 2>&1 | tail -1); echo "440 Hz before $1: $r" >> $C; }
st() { curl -s -H "X-Walkie-Token: $(cat ~/.walkie-talkie/test-token 2>/dev/null)" -m 10 127.0.0.1:8917/test/state; }
ghost() {
  local s; s=$(st)
  if echo "$s" | /usr/bin/python3 -c 'import json,sys; s=json.load(sys.stdin); w=s.get("wisprLive") or {}; sys.exit(0 if w.get("micOpen") and not s.get("listening") and not w.get("captureOpen") else 1)'; then
    echo "GHOST mic open before $1 at $(date -u +%T) — relaunching Wispr" >> $C
    curl -s -H "X-Walkie-Token: $(cat ~/.walkie-talkie/test-token 2>/dev/null)" -m 60 -X POST 127.0.0.1:8917/test/wispr-proc -d '{"relaunch":true}' >> $C; echo >> $C; sleep 25
  fi; }
wisprup() { pgrep -f "^/Applications/Wispr Flow.app/Contents/MacOS/Wispr Flow" >/dev/null || { echo "Wispr not running before $1 at $(date -u +%T) — opening it" >> $C; open "/Applications/Wispr Flow.app"; sleep 30; }; }
drain() { for i in $(seq 1 40); do st | grep -q '"busy":false' && return; ghost drain; sleep 10; done; echo "drain gave up $(date -u +%T)" >> $C; }
[ -f $N/STOP ] && { echo "STOP file: skipping $1 $(date -u +%T)" >> $C; exit 0; }
drain; wisprup "$1"; ghost "$1"; warm; eng; bh "$1"
echo "$1 start $(date -u +%T) $(cat ~/wt-lab/MIRROR_HEAD)" >> $C
[ -n "$WT_SOAK_GAP" ] && export WT_SOAK_GAP
bash ~/wt-lab/run-exphase.sh "$@"
pfclean "$1"; eng
echo "$1 CHAINDONE $(date -u +%T)" >> $C
