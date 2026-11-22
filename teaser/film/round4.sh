#!/bin/zsh
# Round 4 retakes:  round4.sh s01 | s09 | s07b | s07a | s07c     (in that order)
#   s01  the untouched page, the small opaque Terminal anchored bottom-right, ⌘⌃B on it, then the click on the page
#   s09  last Brewly scene: the Terminal over the picture, the pointer over an empty dark area, so neither the chip nor
#        the 💸 pill covers the terminal's text; the stand-in runs QUIET (no tty echo: the envelope's bracket rows are not shown)
#   s07b/a/c  over the end-of-story dark site, the guest in dark appearance (dark toolbar: the top edge's dust reads).
#        The Terminal that Walkie spawns opens BEHIND the browser; the script brings it forward and places it (staged).
source "$(dirname "$0")/lib.sh"
END()  { kill -INT $REC_PID; wait $REC_PID; cat $RAW/$REC_NAME.log | tail -1; cat $RAW/$REC_NAME.marks | tr '\n' ' '; echo; }
ENDSTATE='{"header-dark":1,"button-orange":1,"moved":{"fromX":56.0,"fromY":465.0,"toX":385.0,"toY":201.0},"picture":1,"typo-fixed":1,"pictureSrc":"gimages/img/0.jpg"}'
dark() { g osascript -e "tell application \"System Events\" to tell appearance preferences to set dark mode to $1" >/dev/null; }
site_end() { "$FILM_DIR/site.sh" state "$1"; tab 2; g osascript -e 'tell application "Safari" to set URL of tab 2 of front window to "http://localhost:8000/index.html?v=r4"' >/dev/null; sleep 2; }
forward_new_terminal() {   # the spawned window: forward, lower-right
  local tty=$(api target | python3 -c "import json,sys;print(json.load(sys.stdin).get('address',''))")
  g osascript -e 'tell application "Terminal"' -e "set w to first window whose tty of selected tab is \"/dev/$tty\"" -e 'set miniaturized of w to false' -e 'set bounds of w to {505, 190, 1255, 700}' -e 'set index of w to 1' -e 'activate' -e 'end tell' >/dev/null
}
case "$1" in
s01)
  dark false; "$FILM_DIR/site.sh" state '{}'; g osascript -e 'tell application "Safari" to set URL of tab 2 of front window to "http://localhost:8000/index.html?v=r4"' >/dev/null
  TERM_BOUNDS='697, 371, 1235, 695' stage_terminal >/dev/null; sleep 5; api unbind '{}' >/dev/null 2>&1
  tab 2; deselect; g osascript -e 'tell application "Terminal" to activate' >/dev/null; mouse '[["move",960,530,0.3]]'; sleep 2
  rec_start s01; mark terminal_shown; sleep 2.6; mark bind_start
  mouse '[["key",11,"cmd","ctrl"],["sleep",4.2]]'; mark bind_done
  mouse '[["move",430,300,0.35],["sleep",0.15],["click"]]'; mark browser_front
  sleep 3
  END ;;
s09)
  dark false; site_end "$ENDSTATE"
  AGENT_ENV='AGENT_QUIET=1' TERM_BOUNDS='722, 190, 1250, 500' stage_terminal >/dev/null; sleep 5
  g osascript -e 'tell application "Terminal" to activate' >/dev/null; mouse '[["move",470,460,0.4]]'; sleep 1.5
  rec_start s09; sleep 1.5; mark dictation_starts
  api test/gesture '{"name":"forward-right"}' >/dev/null
  speak s09 0.4
  api test/gesture '{"name":"forward-click"}' >/dev/null
  wait_state "(d.get('prompt') or {}).get('held')" 25; sleep 1.0; mark prompt_sent; api test/prompt '{"do":"send"}' >/dev/null
  sleep 1.5; mark prompt_lands; sleep 4.5; mark cost_pill; pill '$0.06'; sleep 7
  END ;;
s07b)
  dark true; fake_claude on; site_end '{"header-dark":1,"button-orange":1,"moved":{"fromX":56.0,"fromY":465.0,"toX":385.0,"toY":201.0},"picture":1,"typo-fixed":1,"card-fixed":1,"pictureSrc":"gimages/img/0.jpg"}'
  g osascript -e 'tell application "Terminal" to set miniaturized of every window to true' >/dev/null; g open -a Safari; mouse '[["move",700,560,0.3]]'; sleep 2
  rec_start s07b; sleep 1.2
  mouse '[["move",540,440,0.7]]'; mark wake
  api test/wake '{"event":"wake"}' >/dev/null
  speak s07a 1.6; mark speech_ends
  api test/wake '{"event":"silence","head":"start a new session and review my last commit"}' >/dev/null
  wait_state "(d.get('lastDelivery') or {}).get('to','').startswith('spawn')" 40; sleep 1.2; forward_new_terminal; mark new_terminal
  sleep 5
  END ;;
s07a)
  dark true; fake_claude on
  g osascript -e 'tell application "Terminal" to set miniaturized of every window to true' >/dev/null
  g open -a Safari; mouse '[["move",700,560,0.3]]'; sleep 2
  rec_start s07a; sleep 1.2
  mouse '[["move",600,420,0.7]]'; mark flick_up
  api test/gesture '{"name":"forward-up"}' >/dev/null
  speak s07a 0.3; mark speech_ends
  api test/gesture '{"name":"forward-click"}' >/dev/null
  wait_state "(d.get('lastDelivery') or {}).get('to','').startswith('spawn')" 40; sleep 1.2; forward_new_terminal; mark new_terminal
  sleep 5
  END ;;
s07c)
  dark true
  TERM_BOUNDS='300, 150, 980, 450' stage_terminal >/dev/null; sleep 5; g bash /Users/admin/film/oneterm.sh >/dev/null 2>&1
  g osascript -e 'tell application "Terminal" to activate' >/dev/null; mouse '[["move",900,560,0.4]]'; sleep 1.5
  rec_start s07c; sleep 1.5
  mouse '[["move",640,300,0.8]]'; mark dictation_starts
  api test/gesture '{"name":"forward-click"}' >/dev/null
  speak s07c 0.3; mark speech_ends
  api test/gesture '{"name":"forward-click"}' >/dev/null
  wait_state "(d.get('lastDelivery') or {}).get('to')=='caret' and not d.get('listening') and d.get('phase')=='done'" 20; mark prompt_lands
  sleep 6
  END; dark false ;;
esac
