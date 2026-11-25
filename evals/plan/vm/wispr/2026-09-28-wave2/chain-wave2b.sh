#!/bin/bash
# lab wave 2 (2026-09-28 evening), part b: after chain-wave2a — phase X (chaos, cap 75 min),
# then S: a 0.2-scale smoke of TS2/TS4/TS5 and the full TS1/TS3/TS6 (the soak author's ask).
N=~/wt-lab/night/wispr
until grep -q CHAINDONE $N/chain-wave2a.log 2>/dev/null; do sleep 5; done
eng() { curl -s -H "X-Walkie-Token: $(cat ~/.walkie-talkie/test-token 2>/dev/null)" -m 60 -X POST 127.0.0.1:8917/engine -d '{"id":"wispr"}' >/dev/null; }
pfclean() { echo "pf rules after $1: $(sudo pfctl -a com.apple/wt-chaos -s rules 2>/dev/null | wc -l) in the anchor" >> $N/chain-wave2b.log; }
sleep 10
P=$N/probe-relaunch.log; C=~/.walkie-talkie/voice-corpus/2026-09-18/21-05-35-11l735.wav
for k in control relaunch control relaunch; do echo "== $k $(date -u +%T)" >> $P; /usr/bin/python3 ~/wt-lab/relaunch_probe.py $k $C >> $P 2>&1; sleep 20; done
sleep 10; eng; bash ~/wt-lab/run-wphase.sh X 4500 "TX"
pfclean X; sleep 10; eng
WT_SOAK_SCALE=0.2 bash ~/wt-lab/run-wphase.sh Ssmoke 1200 "TS2,TS4,TS5"
sleep 10; eng; bash ~/wt-lab/run-wphase.sh S 3000 "TS1,TS3,TS6"
eng; mkdir -p $N/soak-json; cp /tmp/wt-plan/soak-*.json $N/soak-json/ 2>/dev/null
echo CHAINDONE >> $N/chain-wave2b.log
