#!/bin/bash
# wave 3, phase 1 (HEAD 1dbf9a2, before fix batch 2): TW regression, then the chaos cases not tied to A–D.
N=~/wt-lab/night/wispr3; mkdir -p $N
eng() { curl -s -H "X-Walkie-Token: $(cat ~/.walkie-talkie/test-token 2>/dev/null)" -m 60 -X POST 127.0.0.1:8917/engine -d '{"id":"wispr"}' >/dev/null; }
pfclean() { echo "pf rules after $1: $(sudo pfctl -a com.apple/wt-chaos -s rules 2>/dev/null | wc -l) in the anchor" >> $N/chain-p1.log; }
echo "chain start $(date -u +%T)" >> $N/chain-p1.log
eng; bash ~/wt-lab/run-w3phase.sh P1a 2400 "TW1,TW2,TW5,TW6a,TW6b,TW6c,TW6d,TW7,TW9,TW10,TW11,TW14,TW17,TW19,TW20"
sleep 10; eng; bash ~/wt-lab/run-w3phase.sh P1b 3600 "TX1,TX3,TX4,TX5,TX6a,TX6b,TX7,TX11*,TX12,TX12d"
pfclean P1b; eng
echo "CHAINDONE $(date -u +%T)" >> $N/chain-p1.log
