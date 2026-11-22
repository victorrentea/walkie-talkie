#!/bin/zsh
# s08: REAL ⚡ quick question UI (🔼 ← at rest: left edge question marks, the reply pop-up and its 🔎 / 🧐
# phases) over a fictional package page. The three answers come from claude_p.py — a scripted stand-in for
# `claude -p`, installed as the guest's `claude` by `fake_claude on`. Filmed first as the ad-hoc take "t8".
source "$(dirname "$0")/lib.sh"
fake_claude on
g osascript -e 'tell application "Terminal" to set miniaturized of every window to true' -e 'tell application "Safari" to set URL of front document to "http://localhost:8000/lib.html"' >/dev/null
g open -a Safari; sleep 2
rec_start s08
mouse '[["move",980,250,0.6]]'
api test/gesture '{"name":"forward-left"}' >/dev/null     # 🔼 ← at rest: a quick question
speak s08 0.3
api test/gesture '{"name":"forward-click"}' >/dev/null
sleep 16
kill -INT $REC_PID; wait $REC_PID; cat $RAW/s08.log
api test/quick '{"close":true}' >/dev/null
