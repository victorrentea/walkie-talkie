#!/bin/bash
# wave 3, phase 2 (HEAD 575bbb2 = fix batch 2): the re-run list, then the soak, then the phase-1 leftovers on the fixed build.
N=~/wt-lab/night/wispr3; mkdir -p $N
eng() { curl -s -H "X-Walkie-Token: $(cat ~/.walkie-talkie/test-token 2>/dev/null)" -m 60 -X POST 127.0.0.1:8917/engine -d '{"id":"wispr"}' >/dev/null; }
pfclean() { echo "pf rules after $1: $(sudo pfctl -a com.apple/wt-chaos -s rules 2>/dev/null | wc -l) in the anchor" >> $N/chain-p2.log; }
warm() { for i in $(seq 1 30); do curl -s -H "X-Walkie-Token: $(cat ~/.walkie-talkie/test-token 2>/dev/null)" -m 10 -X POST 127.0.0.1:8917/test/whisper -d '{}' | grep -q '"ready":true' && return; sleep 10; done; }
drain() { for i in $(seq 1 40); do curl -s -H "X-Walkie-Token: $(cat ~/.walkie-talkie/test-token 2>/dev/null)" -m 10 127.0.0.1:8917/test/state | grep -q '"busy":false' && return; sleep 10; done; echo "drain gave up $(date -u +%T)" >> $N/chain-p2.log; }
echo "chain start $(date -u +%T)" >> $N/chain-p2.log
warm; eng; bash ~/wt-lab/run-w3phase.sh P2a 2700 "TW4,TW8a,TW8b,TW11,TW15,TW20,TW32,TW33,TW34,TN4"
drain; warm; eng; bash ~/wt-lab/run-w3phase.sh P2b 2700 "TX2,TX7,TX8a,TX8b,TX9,TX10,TX13"
pfclean P2b; drain; warm; eng
echo "P2c ready $(date -u +%T)" >> $N/chain-p2.log
while [ -f ~/wt-lab/HOLD-SOAK ]; do sleep 15; done
bash ~/wt-lab/run-w3phase.sh P2c 5400 "TS1,TS2,TS3"
mkdir -p $N/soak-json; cp /tmp/wt-plan/soak-*.json $N/soak-json/ 2>/dev/null
drain; warm; eng; bash ~/wt-lab/run-w3phase.sh P2d 3600 "TW1,TW14,TW17,TW19,TX1,TX3,TX4,TX5,TX6a,TX6b,TX11*,TX12,TX12d"
pfclean P2d; eng
echo "CHAINDONE $(date -u +%T)" >> $N/chain-p2.log
