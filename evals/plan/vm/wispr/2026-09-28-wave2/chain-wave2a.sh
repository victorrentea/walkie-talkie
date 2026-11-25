#!/bin/bash
# lab wave 2 (2026-09-28 evening): W2b then W3 twice; the engine re-set before each phase
# (a cap SIGKILL skips the harness's own cleanup).
eng() { curl -s -H "X-Walkie-Token: $(cat ~/.walkie-talkie/test-token 2>/dev/null)" -m 60 -X POST 127.0.0.1:8917/engine -d '{"id":"wispr"}' >/dev/null; }
eng; bash ~/wt-lab/run-wphase.sh W2b 1800 "TW12,TW13,TW14,TW19,TW22"
sleep 10; eng; bash ~/wt-lab/run-wphase.sh W3r1 1200 "TW4,TW8a,TW15,TW20,TW3,TW11"
sleep 10; eng; bash ~/wt-lab/run-wphase.sh W3r2 1200 "TW4,TW8a,TW15,TW20,TW11"
eng; echo CHAINDONE >> ~/wt-lab/night/wispr/chain-wave2a.log
