#!/bin/zsh
# s03: REAL wheel-drag crop round the green badge, ⇧ locks it (red dashed source, 50 % ghost on the pointer,
# the arrow), a left click drops it; the prompt carries both boxes and agent.py (stand-in agent) moves the
# badge to exactly the dropped box. Voice: synthetic, into the guest mic, transcribed by the local Whisper.
source "$(dirname "$0")/lib.sh"
"$FILM_DIR/site.sh" state '{}'
stage_terminal >/dev/null; sleep 5        # a fresh stand-in agent in the bound tab
g open -a Safari; mouse '[["move",560,520,0.4]]'; sleep 1.5
rec_start s03
sleep 1.5
api test/gesture '{"name":"forward-right"}' >/dev/null
speak s03 0.9 & SPEAK=$!
mouse '[["sleep",0.9],["move",56,431,0.7],["sleep",0.15],["down","middle"],["drag",366,479,0.9,"middle"],["sleep",0.35],["flags","shift"],["sleep",0.45],["up","middle"],["sleep",0.15],["flags"],["move",540,300,0.6],["move",706,212,0.8],["sleep",0.7],["click","left"],["sleep",1.3]]'
wait $SPEAK
api test/gesture '{"name":"forward-click"}' >/dev/null
wait_state "(d.get('prompt') or {}).get('held')" 20
sleep 1.2; api test/prompt '{"do":"send"}' >/dev/null
wait_state "(d.get('lastDelivery') or {}).get('to','').startswith('terminal')" 15
sleep 6
kill -INT $REC_PID; wait $REC_PID; cat $RAW/s03.log
