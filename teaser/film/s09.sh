#!/bin/zsh
# s09: Terminal in front. A REAL spoken prompt lands in the bound tab — its pictures are file paths in the
# text — then the 💸 turn-cost float by the pointer. The float is the app's real pill but shown through the
# demo route with made-up numbers (/test/turn-cost): the lab has no Claude Code session to price.
source "$(dirname "$0")/lib.sh"
"$FILM_DIR/site.sh" state '{}'
stage_terminal >/dev/null; sleep 6
g osascript -e 'tell application "Terminal" to activate'; mouse '[["move",820,560,0.4]]'; sleep 1.5
rec_start s09; sleep 1.5
mouse '[["move",700,470,0.7]]'
api test/gesture '{"name":"forward-right"}' >/dev/null
speak s02 0.4
api test/gesture '{"name":"forward-click"}' >/dev/null
wait_state "(d.get('prompt') or {}).get('held')" 20
sleep 1.0; api test/prompt '{"do":"send"}' >/dev/null
sleep 5.5
api test/turn-cost '{"amount":"$0.18","rest":" · Opus 5.5 in brewly","capturable":true}'; echo
sleep 8
kill -INT $REC_PID; wait $REC_PID; cat $RAW/s09.log
