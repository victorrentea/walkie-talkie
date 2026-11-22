#!/bin/zsh
# s01 + s02: the calm site, then a REAL spoken prompt to the bound terminal (right-edge dust, halo, chip,
# the prompt panel) — synthetic voice into the guest's BlackHole mic, transcribed by the local Whisper,
# delivered by Walkie into the Terminal tab hidden behind Safari, where agent.py (the stand-in agent)
# applies the scripted restyle ~1 s after the prompt lands.
source "$(dirname "$0")/lib.sh"
"$FILM_DIR/site.sh" state '{}'
stage_terminal >/dev/null; sleep 6
g osascript -e 'tell application "Terminal" to set miniaturized of every window to true' -e 'tell application "Safari" to set URL of front document to "http://localhost:8000/"' >/dev/null
g open -a Safari; mouse '[["move",930,470,0.4]]'; sleep 1.5
rec_start s02
sleep 7                                               # s01: nothing happens
mouse '[["move",820,330,0.9]]'
api test/gesture '{"name":"forward-right"}' >/dev/null # 🔼 → : prompt at the bound terminal
speak s02 0.4
sleep 0.3
api test/gesture '{"name":"forward-click"}' >/dev/null # 🔼 ends it
wait_state "(d.get('prompt') or {}).get('held')" 20
sleep 1.6; api test/prompt '{"do":"send"}' >/dev/null  # ⏎ on the held prompt instead of waiting out its countdown
wait_state "(d.get('lastDelivery') or {}).get('to','').startswith('terminal')" 15
sleep 6
kill -INT $REC_PID; wait $REC_PID; cat $RAW/s02.log
