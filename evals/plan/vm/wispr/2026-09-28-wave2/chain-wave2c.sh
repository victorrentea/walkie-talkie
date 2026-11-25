#!/bin/bash
# lab wave 2, part c: phase X again with the glob `TX*` (part b's `TX` matched no id: --only is
# exact-or-glob, not a prefix). Runs after part b (S) is done.
N=~/wt-lab/night/wispr
until grep -q CHAINDONE $N/chain-wave2b.log 2>/dev/null; do sleep 5; done
eng() { curl -s -H "X-Walkie-Token: $(cat ~/.walkie-talkie/test-token 2>/dev/null)" -m 60 -X POST 127.0.0.1:8917/engine -d '{"id":"wispr"}' >/dev/null; }
sleep 10; eng; bash ~/wt-lab/run-wphase.sh X2 4500 "TX*"
echo "pf rules after X2: $(sudo pfctl -a com.apple/wt-chaos -s rules 2>/dev/null | wc -l) in the anchor; main: $(sudo pfctl -s rules 2>/dev/null | wc -l)" >> $N/chain-wave2c.log
eng; cp /tmp/wt-plan/soak-*.json $N/soak-json/ 2>/dev/null
echo CHAINDONE >> $N/chain-wave2c.log
