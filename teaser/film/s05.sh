#!/bin/zsh
# s05: REAL film mode. The site's Plans menu is open and flickering (CSS); during a prompt 🔽 ↑ starts
# the screen film (● REC corners), the voice describes the bug, the prompt ends; agent.py stops the flicker.
source "$(dirname "$0")/lib.sh"
"$FILM_DIR/site.sh" state '{"menu-open":1,"flicker":1}'
g open -a Safari; mouse '[["move",700,430,0.4]]'; sleep 1.5
rec_start s05; sleep 1.5
mouse '[["move",930,300,0.7]]'
api test/gesture '{"name":"forward-right"}' >/dev/null
sleep 1.0
api test/gesture '{"name":"back-up"}' >/dev/null          # 🔽 ↑ : film the screen
speak s05 0.8
sleep 1.2
api test/gesture '{"name":"forward-click"}' >/dev/null
wait_state "(d.get('prompt') or {}).get('held')" 25
sleep 1.5; api test/prompt '{"do":"send"}' >/dev/null
sleep 8
kill -INT $REC_PID; wait $REC_PID; cat $RAW/s05.log
