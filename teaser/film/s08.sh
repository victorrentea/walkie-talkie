#!/bin/zsh
# s08: REAL ⚡ quick question UI (🔼 ← at rest: left edge question marks, the reply pop-up and its 🔎 / 🧐
# phases) over a fictional package page. The three answers come from claude_p.py — a scripted stand-in for
# `claude -p`, installed as the guest's `claude` by `fake_claude on`. Filmed first as the ad-hoc take "t8".
source "$(dirname "$0")/lib.sh"
fake_claude on
# the REAL page github.com/Netflix/Hystrix in the guest's Safari, dark appearance, scrolled to "Hystrix Status"
g osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to true' >/dev/null
g osascript -e 'tell application "Terminal" to set miniaturized of every window to true' -e 'tell application "Safari" to set miniaturized of every window to false' -e 'tell application "Safari" to set URL of front document to "https://github.com/Netflix/Hystrix"' >/dev/null
g open -a Safari; sleep 12
g osascript -e 'tell application "Safari" to do JavaScript "var h=[...document.querySelectorAll(\"h2,h1,h3\")].find(e=>/Hystrix Status/i.test(e.textContent)); if(h){scrollTo(0, scrollY+h.getBoundingClientRect().top-230);}" in front document' >/dev/null
sleep 1.5
rec_start s08; sleep 1
mouse '[["move",820,330,0.6]]'; mark question_starts
api test/gesture '{"name":"forward-left"}' >/dev/null     # 🔼 ← at rest: a quick question
speak s08 0.3; sleep 2.2
api test/gesture '{"name":"forward-click"}' >/dev/null
sleep 2.5; mark first_answer; sleep 8; mark web_checked_by; sleep 7; mark reviewed_by; sleep 4.5
kill -INT $REC_PID; wait $REC_PID; cat $RAW/s08.log | tail -1
api test/quick '{"close":true}' >/dev/null
g osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to false' >/dev/null
