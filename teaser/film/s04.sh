#!/bin/zsh
# s04: one REAL prompt that collects, while the (synthetic) voice talks: a picture put on the clipboard
# (by script — no Google Images in the lab), a wheel-drag crop of the empty picture slot, and a mouse-selected
# title. Then the pointer goes to the prompt atom (top-left) and the real prompt panel opens with all of them
# inline in the sentence. agent.py (stand-in) then puts the picture in and fixes the typo.
source "$(dirname "$0")/lib.sh"
"$FILM_DIR/site.sh" state '{}'
stage_terminal >/dev/null; sleep 5        # a fresh stand-in agent in the bound tab
g osascript -e 'tell application "Terminal" to set miniaturized of every window to true' -e 'tell application "Safari" to set URL of front document to "http://localhost:8000/"' >/dev/null
g open -a Safari; mouse '[["move",600,470,0.4]]'; sleep 1.5
rec_start s04; sleep 1.2
api test/gesture '{"name":"forward-right"}' >/dev/null
sleep 0.8
speak s04 & SPEAK=$!
mouse '[["move",900,330,0.6],["sleep",1.3],["pbimage","/Users/admin/film/beans.svg.png"],["sleep",0.3],["move",712,186,0.6],["sleep",0.1],["down","middle"],["drag",1226,452,1.3,"middle"],["sleep",0.2],["up","middle"],["sleep",0.3],["move",452,575,1.0],["sleep",2.2],["down","left"],["drag",575,575,0.6,"left"],["up","left"],["sleep",1.5],["move",640,500,0.5]]'
wait $SPEAK
api test/gesture '{"name":"forward-click"}' >/dev/null
wait_state "(d.get('prompt') or {}).get('held')" 20
mouse '[["move",120,150,0.9],["sleep",0.4],["move",150,120,0.3]]'      # the hand reaches the atom: the dialog opens, the countdown pauses
sleep 4.5
api test/state | python3 -c "import json,sys;d=json.load(sys.stdin);p=d.get('prompt');print(p.get('text'), p.get('opacity'), p.get('paused'))"
api test/prompt '{"do":"send"}' >/dev/null
mouse '[["move",640,480,0.6]]'
sleep 7
kill -INT $REC_PID; wait $REC_PID; cat $RAW/s04.log
