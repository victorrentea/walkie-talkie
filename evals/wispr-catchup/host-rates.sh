#!/bin/bash
# Wispr's speed tolerance on the host Mac (2026-09-30, Victor: "Nu poți folosi mașina fizică … cât
# vreme VM e ocupat?" → "Mac now, full"). Every clip at 1.0 ×2, 1.25, 1.5, 1.75, 2.0 played straight
# into From Walkie (Wispr's microphone) with Wispr's push-to-talk held — no relay in the path.
# Run under `hands-off run`: synthetic keys, and Walkie's test sink window in front catches the pastes.
# The relay's bridge is switched off for the run (a second writer on From Walkie wipes the clip, and
# his own-sentence feed would carry the room's microphone in), and put back on however this exits.
set -u
cd "$(dirname "$0")/../.."
PY=/Library/Frameworks/Python.framework/Versions/3.12/bin/python3
API=http://127.0.0.1:8917
OUT=evals/wispr-catchup/rates.jsonl
RATES="${RATES:-1.0 1.0 1.25 1.5 1.75 2.0}"
# X-Walkie-Token (2026-11-25): read at every call — a relaunched app writes a new one;
# sent only to the app's own port and never in argv (`helpers/walkie_auth.sh`, Fable review).
. helpers/walkie_auth.sh
post() { curl -s -m 5 -X POST "$API/$1" -H @<(wt_auth 8917) -d "$2" >/dev/null; }
restore() { post test/sink '{"restore":true}'; post test/sink '{"on":false}'; post test/bridge '{"on":true}'; echo "restored $(date +%T)"; }
trap restore EXIT INT TERM
post test/bridge '{"on":false}'
post test/sink '{"on":true}'
sleep 1
# CLIPS="a.wav b.wav" narrows the run (the fast-Romanian pass, Victor: "I tend to speak faster in RO").
if [ -n "${CLIPS:-}" ]; then LIST=$(for c in $CLIPS; do echo "evals/wispr-catchup/clips/$c"; done)
else LIST=$(ls evals/wispr-catchup/clips/*.wav); fi
for wav in $LIST; do
  clip=$(basename "$wav")
  for rate in $RATES; do
    at=$(date '+%F %T')
    line=$(WT_EVAL_WISPR_DEV="From Walkie" "$PY" evals/wispr-catchup/guest.py r "$wav" "$rate" 2>/dev/null | tail -1)
    [ -z "$line" ] && line='{"error":"no output"}'
    echo "$line" | "$PY" -c "import json,sys; r=json.loads(sys.stdin.read()); r.update(clip='$clip', kind='r', arg='$rate', at='$at', where='host'); print(json.dumps(r, ensure_ascii=False))" >> "$OUT"
    echo "$at r:$rate $clip $(tail -1 "$OUT" | cut -c1-120)"
  done
done
