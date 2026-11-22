#!/bin/zsh
# s06: a diff drawn in the browser (demo-site/code.html — the lab has no IDE). During a REAL prompt the mouse
# selects the loop (Walkie attaches the highlight by itself), the voice says what is wrong; agent.py
# (stand-in) rewrites the loop when the prompt lands.
source "$(dirname "$0")/lib.sh"
"$FILM_DIR/site.sh" state '{}'
stage_terminal >/dev/null; sleep 5        # a fresh stand-in agent in the bound tab
g osascript -e 'tell application "Terminal" to set miniaturized of every window to true' -e 'tell application "Safari" to set URL of front document to "http://localhost:8000/code.html"' >/dev/null
g open -a Safari; mouse '[["move",760,520,0.4]]'; sleep 1.5
rec_start s06; sleep 1.5
api test/gesture '{"name":"forward-right"}' >/dev/null
sleep 0.6
speak s06 1.6 & SPEAK=$!
mouse '[["move",305,199,0.7],["sleep",0.2],["down","left"],["drag",330,290,0.6,"left"],["drag",442,367,0.6,"left"],["up","left"],["sleep",0.6],["move",720,330,0.7]]'
wait $SPEAK
sleep 0.4
api test/gesture '{"name":"forward-click"}' >/dev/null
wait_state "(d.get('prompt') or {}).get('held')" 20
sleep 1.2; api test/prompt '{"do":"send"}' >/dev/null
sleep 8
kill -INT $REC_PID; wait $REC_PID; cat $RAW/s06.log
