#!/bin/bash
# Wave 5 on fix batch 4 (F1, E-FP, a quit is not his stop, process age, the exit watch; rig fixes).
# The list and why: evals/plan/vm/wispr/wave5-rerun.txt. Copy into the guest as ~/wt-lab/chain-wave5.sh
# beside run-w5phase.sh and bhcheck.py (2026-09-29-wave4/), then launch it THROUGH `tart exec`, detached:
#   tart exec wt-lab sh -c "nohup bash ~/wt-lab/chain-wave5.sh >/dev/null 2>&1 </dev/null & echo launched"
# Never over SSH: the harness would read BlackHole as zeros (no microphone grant for sshd's chain).
N=~/wt-lab/night/wispr5; mkdir -p $N; C=$N/chain-w5.log
eng() { curl -s -H "X-Walkie-Token: $(cat ~/.walkie-talkie/test-token 2>/dev/null)" -m 60 -X POST 127.0.0.1:8917/engine -d '{"id":"wispr"}' >/dev/null; }
pfclean() { echo "pf rules after $1: $(sudo pfctl -a com.apple/wt-chaos -s rules 2>/dev/null | wc -l) in the anchor" >> $C; }
# The local helper up before every phase. `{}` only READS its state — it never loads it (wave 4's
# first warm() posted `{}` and waited on a helper nobody started) — so anything not ready and not
# already loading gets `{"restart": true}`; a warm helper is left alone.
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
phase() { [ -f $N/STOP ] && { echo "STOP file: skipping $1 $(date -u +%T)" >> $C; return; }; drain; wisprup "$1"; ghost "$1"; warm; eng; bh "$1"; echo "$1 start $(date -u +%T)" >> $C; bash ~/wt-lab/run-w5phase.sh "$@"; }
echo "chain start $(date -u +%T) $(cat ~/wt-lab/MIRROR_HEAD)" >> $C
# W5a: batch 4's own cases (desk ones run here too), then F1 + E-FP back to back (TW4 → TW8a), g, the quit.
phase W5a 2700 "TW41,TW42,TW43,TA6,TW4,TW8a,TW11,TW20"
# W5b: TW4 a second time (F1 must hold twice), the ghost cases, the cold start from outside (item 4).
phase W5b 2700 "TW4,TX3,TX6b,TX9,TX13"
pfclean W5b
# W5c: the auto fallback against real Wispr — the quit mid-sentence (item 3 + 5), not running.
phase W5c 1800 "TQ2,TQ4"
# W5t (driver, 2026-09-29): TS1, the 30-sentence relay soak (criterion d/a volume).
phase W5t 1800 "TS1"
mkdir -p $N/soak-json; cp /tmp/wt-plan/soak-*.json $N/soak-json/ 2>/dev/null
export WT_SOAK_GAP=2
phase W5e 2400 "TS3"
unset WT_SOAK_GAP
cp /tmp/wt-plan/soak-*.json $N/soak-json/ 2>/dev/null
# W5d: the rig fixes (optional) — moved last by the driver; skipped when the stop file exists.
[ -f ~/wt-lab/night/wispr5/STOP ] || phase W5d 1800 "TM1,TM2,TW39,TX8b,TX10"
pfclean end; eng
echo "CHAINDONE $(date -u +%T)" >> $C
