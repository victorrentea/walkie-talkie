#!/bin/bash
# wave 4 on 051baed (fix batch 3 + auto fallback p98 + A's peak-0 watch): TM, the batch-3 re-runs, chaos, auto fallback (TA + TQ on real Wispr), soak.
N=~/wt-lab/night/wispr4; mkdir -p $N; C=$N/chain-w4.log
eng() { curl -s -H "X-Walkie-Token: $(cat ~/.walkie-talkie/test-token 2>/dev/null)" -m 60 -X POST 127.0.0.1:8917/engine -d '{"id":"wispr"}' >/dev/null; }
pfclean() { echo "pf rules after $1: $(sudo pfctl -a com.apple/wt-chaos -s rules 2>/dev/null | wc -l) in the anchor" >> $C; }
warm() { local r; for i in $(seq 1 40); do r=$(curl -s -H "X-Walkie-Token: $(cat ~/.walkie-talkie/test-token 2>/dev/null)" -m 10 -X POST 127.0.0.1:8917/test/whisper -d '{}'); echo "$r" | grep -q '"ready":true' && return; echo "$r" | grep -q '"loading":true' || { echo "warm: restarting the helper $(date -u +%T)" >> $C; curl -s -H "X-Walkie-Token: $(cat ~/.walkie-talkie/test-token 2>/dev/null)" -m 10 -X POST 127.0.0.1:8917/test/whisper -d '{"restart":true}' >/dev/null; }; sleep 10; done; echo "warm gave up $(date -u +%T)" >> $C; }
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
phase() { drain; wisprup "$1"; ghost "$1"; warm; eng; bh "$1"; echo "$1 start $(date -u +%T)" >> $C; bash ~/wt-lab/run-w4phase.sh "$@"; }
echo "chain start $(date -u +%T) $(cat ~/wt-lab/MIRROR_HEAD)" >> $C
phase W4a 3000 "TM1,TM2,TW35,TW36,TW37,TW38,TW39,TW40,TW33,TW1,TW4,TW34,TW8a,TW8b,TW12,TW20,TN4"
phase W4b 2700 "TX2,TX3,TX6b,TX8a,TX8b,TX10,TX13"
pfclean W4b
phase W4c 2700 "TA1,TA2,TA3,TA4,TA5,TQ1,TQ2,TQ3,TQ4"
phase W4d 3600 "TS1,TS2"
mkdir -p $N/soak-json; cp /tmp/wt-plan/soak-*.json $N/soak-json/ 2>/dev/null
export WT_SOAK_GAP=2
phase W4e 2400 "TS3"
unset WT_SOAK_GAP
cp /tmp/wt-plan/soak-*.json $N/soak-json/ 2>/dev/null
pfclean end; eng
echo "CHAINDONE $(date -u +%T)" >> $C
