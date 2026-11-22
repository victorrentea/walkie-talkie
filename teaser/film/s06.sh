#!/bin/zsh
# s06: a diff drawn in the browser (demo-site/code.html — Java; the lab has no IDE). During a REAL prompt the mouse
# selects the loop (Walkie attaches the highlight by itself), the voice says what is wrong; agent.py
# (stand-in) rewrites the loop when the prompt lands.
source "$(dirname "$0")/lib.sh"
"$FILM_DIR/site.sh" state '{}'
stage_terminal >/dev/null; sleep 5        # a fresh stand-in agent in the bound tab
g osascript -e 'tell application "Terminal" to set miniaturized of every window to true' -e 'tell application "Safari" to set URL of front document to "http://localhost:8000/code.html?v=5"' >/dev/null
g open -a Safari; mouse '[["move",760,520,0.4]]'; sleep 1.5
rec_start s06; sleep 1.5; mark dictation_starts
api test/gesture '{"name":"forward-right"}' >/dev/null
sleep 0.6
speak s06 1.6 & SPEAK=$!
mark selection_start
mouse '[["move",363,270,0.7],["sleep",0.2],["down","left"],["drag",470,350,0.7,"left"],["drag",489,441,0.7,"left"],["up","left"],["sleep",0.8],["move",820,560,0.7]]'
mark selection_end
wait $SPEAK
sleep 0.4
api test/gesture '{"name":"forward-click"}' >/dev/null
wait_state "(d.get('prompt') or {}).get('held')" 20
sleep 1.2; mark prompt_sent; api test/prompt '{"do":"send"}' >/dev/null
sleep 2.6; mark rewritten; sleep 6
kill -INT $REC_PID; wait $REC_PID; cat $RAW/s06.log
