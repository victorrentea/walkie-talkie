#!/bin/zsh
# Round 5 (teaser v6) takes:  round5.sh prep | s07e | s07a | s07b | s07c
#   prep  page = after s02 (dark header, orange button), a bound stand-in agent behind the browser; then story.sh s03 s04 s05
#   s07e  "send your prompt to the session in the back": browser in front, the bound terminal peeking bottom-right
#   s07a  swipe up over the dark diff page: the REAL folder dialog (four pinned folders + Workspace), brewly picked
#   s07b  wake word (injected) · s07c  caret prompt — both over the accumulated Brewly page, dark appearance
source "$(dirname "$0")/lib.sh"
END()  { kill -INT $REC_PID; wait $REC_PID; cat $RAW/$REC_NAME.log | tail -1; cat $RAW/$REC_NAME.marks | tr '\n' ' '; echo; }
dark() { g osascript -e "tell application \"System Events\" to tell appearance preferences to set dark mode to $1" >/dev/null; }
brewly() { g osascript -e 'tell application "Safari" to set URL of tab 2 of front window to "http://localhost:8000/index.html?v=r5"' >/dev/null; tab 2; sleep 2; }
forward_new_terminal() {
  local tty=$(api target | python3 -c "import json,sys;print(json.load(sys.stdin).get('address',''))")
  g osascript -e 'tell application "Terminal"' -e "set w to first window whose tty of selected tab is \"/dev/$tty\"" -e 'set miniaturized of w to false' -e 'set bounds of w to {505, 190, 1255, 700}' -e 'set index of w to 1' -e 'activate' -e 'end tell' >/dev/null
}
case "$1" in
prep)
  dark false; "$FILM_DIR/site.sh" state '{"header-dark":1,"button-orange":1,"pictureSrc":"gimages/img/0.jpg"}'; brewly
  TERM_BOUNDS='697, 371, 1235, 695' stage_terminal; sleep 5; g open -a Safari ;;
s07e)
  dark false; brewly
  AGENT_ENV='AGENT_QUIET=1' TERM_BOUNDS='760, 420, 1262, 706' stage_terminal >/dev/null; sleep 5
  g open -a Safari; mouse '[["move",560,600,0.3]]'; sleep 1.5
  rec_start s07e; sleep 1.2
  mouse '[["move",430,470,0.7]]'; mark dictation_starts
  api test/gesture '{"name":"forward-right"}' >/dev/null
  speak s07e 2.0; sleep 0.6; mark dictation_ends
  api test/gesture '{"name":"forward-click"}' >/dev/null
  wait_state "(d.get('prompt') or {}).get('held')" 25; sleep 1.0; mark prompt_sent; api test/prompt '{"do":"send"}' >/dev/null
  sleep 1.2; g osascript -e 'tell application "Terminal" to activate' >/dev/null; mark terminal_forward
  sleep 4.5
  END ;;
s07a)
  dark true; fake_claude on
  g osascript -e 'tell application "Terminal" to set miniaturized of every window to true' -e 'tell application "Safari" to set URL of tab 2 of front window to "http://localhost:8000/code.html?v=5"' >/dev/null
  "$FILM_DIR/site.sh" merge '{"loop-fixed":1}'; g open -a Safari; mouse '[["move",760,640,0.3]]'; sleep 2
  rec_start s07a; sleep 1.2
  mouse '[["move",800,430,0.7]]'; mark swipe_up
  api test/gesture '{"name":"forward-up"}' >/dev/null
  speak s07a 0.3 & SPEAK=$!
  sleep 3.2; mark dialog_held
  mouse "[[\"move\",${PICK:-880,510},0.6],[\"sleep\",0.5],[\"click\"]]"; mark brewly_picked
  wait $SPEAK; mark speech_ends
  api test/gesture '{"name":"forward-click"}' >/dev/null
  wait_state "(d.get('lastDelivery') or {}).get('to','').startswith('spawn')" 40; sleep 1.2; forward_new_terminal; mark new_terminal
  sleep 5
  END; "$FILM_DIR/site.sh" merge '{"loop-fixed":0}' ;;
s07b)
  dark true; fake_claude on; brewly
  g osascript -e 'tell application "Terminal" to set miniaturized of every window to true' >/dev/null; g open -a Safari; mouse '[["move",700,560,0.3]]'; sleep 2
  rec_start s07b; sleep 1.2
  mouse '[["move",540,440,0.7]]'; mark wake
  api test/wake '{"event":"wake"}' >/dev/null
  speak s07a 1.6; mark speech_ends
  api test/wake '{"event":"silence","head":"start a new session and review my last commit"}' >/dev/null
  wait_state "(d.get('lastDelivery') or {}).get('to','').startswith('spawn')" 40; sleep 1.2; forward_new_terminal; mark new_terminal
  sleep 5
  END ;;
s07c)
  dark true; brewly
  TERM_BOUNDS='300, 150, 980, 450' stage_terminal >/dev/null; sleep 5; g bash /Users/admin/film/oneterm.sh >/dev/null 2>&1
  g osascript -e 'tell application "Terminal" to activate' >/dev/null; mouse '[["move",900,520,0.4]]'; sleep 1.5
  rec_start s07c; sleep 1.5
  mouse '[["move",640,300,0.8]]'; mark dictation_starts
  api test/gesture '{"name":"forward-click"}' >/dev/null
  speak s07c 0.3; sleep 1.0; mark speech_ends
  api test/gesture '{"name":"forward-click"}' >/dev/null
  wait_state "(d.get('lastDelivery') or {}).get('to')=='caret' and not d.get('listening') and d.get('phase')=='done'" 20; mark prompt_lands
  sleep 6
  END; dark false ;;
esac
