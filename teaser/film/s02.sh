#!/bin/zsh
# s01 + s02: the calm site, then a REAL spoken prompt to the bound terminal (right-edge dust, halo, chip,
# the prompt panel) — synthetic voice into the guest's BlackHole mic, transcribed by the local Whisper,
# delivered by Walkie into the Terminal tab hidden behind Safari, where agent.py (the stand-in agent)
# applies the scripted restyle ~1 s after the prompt lands.
source "$(dirname "$0")/lib.sh"
"$FILM_DIR/site.sh" state '{}'
stage_terminal >/dev/null; sleep 6
g osascript -e 'tell application "Safari" to set URL of front document to "http://localhost:8000/"' >/dev/null
g open -a Safari; mouse '[["move",930,470,0.4]]'; sleep 1.5
g osascript -e 'tell application "Terminal" to set miniaturized of every window to false' -e 'tell application "Terminal" to activate' >/dev/null
mouse '[["move",560,600,0.3]]'; sleep 1.5
rec_start s02
# s01: the agent's terminal is in front; a click on the page puts the browser over it, then the pointer wanders
sleep 1.8
mouse '[["move",1190,300,0.9],["click"],["sleep",0.5],["move",900,380,1.0],["move",330,420,1.3],["move",620,560,1.2],["sleep",0.8]]'
# s02: pointer left of centre (away from the right edge); 🔼 → : a prompt at the bound terminal
mouse '[["move",470,330,0.8]]'
api test/gesture '{"name":"forward-right"}' >/dev/null
speak s02 0.4
sleep 0.3
api test/gesture '{"name":"forward-click"}' >/dev/null
wait_state "(d.get('prompt') or {}).get('held')" 20
sleep 1.6; api test/prompt '{"do":"send"}' >/dev/null
wait_state "(d.get('lastDelivery') or {}).get('to','').startswith('terminal')" 15
sleep 6
kill -INT $REC_PID; wait $REC_PID; cat $RAW/s02.log
