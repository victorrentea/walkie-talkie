#!/bin/bash
# run-d.sh CAP_SECONDS PER_CASE_CAP ID... — phase D: one case per process, each after 30 s of busy==false.
cap=$1; per=$2; shift 2
N=$HOME/wt-lab/night; mkdir -p "$N"; L="$N/run-D.log"
t0=$(date +%s); i=0
# X-Walkie-Token (2026-11-25): read at every call — a relaunched app writes a new one.
wt_auth() { printf 'X-Walkie-Token: %s' "$(cat "${WALKIE_HOME:-$HOME/.walkie-talkie}/test-token" 2>/dev/null)"; }
busy() { curl -fsS -m 5 -H "$(wt_auth)" http://127.0.0.1:8917/test/state 2>/dev/null | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["busy"])' 2>/dev/null; }
echo "start D cap=${cap}s per=${per}s $(date)" >> "$L"
for id in "$@"; do
  i=$((i+1)); nn=$(printf %02d $i)
  left=$(( cap - ($(date +%s) - t0) ))
  [ $left -le 60 ] && { echo "D cap reached before $id $(date)" >> "$L"; break; }
  # 30 s of busy == false (≤ 5 min)
  q=0; for _ in $(seq 1 150); do [ "$(busy)" = "False" ] && q=$((q+2)) || q=0; [ $q -ge 30 ] && break; sleep 2; done
  c=$per; [ $c -gt $left ] && c=$left
  echo "== D$nn $id cap=${c}s idle=${q}s $(date)" >> "$L"
  bash "$HOME/wt-lab/run-phase.sh" "D$nn-$id" "$c" "$id"
  tail -3 "$N/run-D$nn-$id.log" | head -2 >> "$L"
done
echo "PHASEDONE D $(date)" >> "$L"
