#!/bin/zsh
# Round 3: the Brewly scenes in story order on ONE continuous page — every change stays for the next scene.
#   story.sh s01 | s02 | s03 | s04 | s05 | s09      (run them in that order; only s01 resets the page)
# Real gestures and a real voice path as before; agent.py is the stand-in agent; after a task lands the app's
# real 💸 pill is raised through /test/turn-cost with a made-up amount ("done, and it cost this much").
# Screen points, 1280x720; the page's content starts 105 pt down. The pointer stays out of the bottom 15 %.
source "$(dirname "$0")/lib.sh"
SEND() { wait_state "(d.get('prompt') or {}).get('held')" 25; sleep ${1:-1.4}; mark prompt_sent; api test/prompt '{"do":"send"}' >/dev/null; }
END()  { kill -INT $REC_PID; wait $REC_PID; cat $RAW/$REC_NAME.log | tail -1; cat $RAW/$REC_NAME.marks | tr '\n' ' '; echo; }
case "$1" in
s01)  # the untouched page, a small opaque Terminal over it with the pointer resting ON it; ⌘⌃B binds it there (the
      # flight into the pointer, the outline); then the pointer goes quickly to the page beside it and clicks: browser in front
  "$FILM_DIR/site.sh" state '{}'
  chrome hide
  stage_terminal >/dev/null; sleep 5; api unbind '{}' >/dev/null 2>&1
  tab 2; deselect; g osascript -e 'tell application "Terminal" to activate' >/dev/null; mouse '[["move",922,360,0.3]]'; sleep 2
  rec_start s01; mark terminal_shown; sleep 2.4; mark bind_start
  mouse '[["key",11,"cmd","ctrl"],["sleep",3.2]]'; mark bind_done
  mouse '[["move",1075,353,0.3],["sleep",0.15],["click"]]'; mark browser_front
  sleep 2.5
  END ;;
s02)  # already bound, the browser in front: a prompt to the terminal behind it (right edge), the page restyles, the pill
  g open -a Safari; mouse '[["move",1075,353,0.3]]'; sleep 1
  rec_start s02; sleep 0.6
  mouse '[["move",470,330,0.7]]'; mark dictation_starts
  api test/gesture '{"name":"forward-right"}' >/dev/null
  speak s02 0.4; sleep 0.3; mark dictation_ends
  api test/gesture '{"name":"forward-click"}' >/dev/null
  SEND 1.6; mouse '[["move",600,470,0.7]]'; sleep 2.3; mark restyle
  sleep 1.0; mark cost_pill; pill '$0.12'; sleep 5
  END ;;
s03)  # wheel box round the badge, ⇧ locks it, the ghost rides the pointer, a left click drops it beside "Fresh coffee,"
  g open -a Safari; mouse '[["move",600,470,0.3]]'; sleep 1
  rec_start s03; sleep 1.0; mark dictation_starts
  api test/gesture '{"name":"forward-right"}' >/dev/null
  speak s03 0.9 & SPEAK=$!
  mouse '[["sleep",0.9],["move",56,465,0.7],["sleep",0.15]]'; mark wheel_box_start
  mouse '[["down","middle"],["drag",371,513,0.9,"middle"],["sleep",0.35],["flags","shift"],["sleep",0.45],["up","middle"],["sleep",0.15],["flags"]]'; mark box_locked
  mouse '[["move",560,380,0.7],["move",700,249.5,0.9],["sleep",0.9]]'; mark drop
  mouse '[["click","left"],["sleep",1.4]]'
  wait $SPEAK
  api test/gesture '{"name":"forward-click"}' >/dev/null
  SEND 1.2; mouse '[["move",760,440,0.7]]'; sleep 2.3; mark page_lands
  sleep 1.2; mark cost_pill; pill '$0.08'; sleep 5
  END ;;
s04)  # a Chrome window with an image search (left): click a picture, right-click → Copy Image, the picture flies into
      # the chip; then to the site: the wheel box EXACTLY round the placeholder; then the typo selected; panel; page; pill.
      # (Google answers the guest with a reCAPTCHA wall: the page is demo-site/gimages — real result thumbnails, laid out as captured, under a rebuilt header.)
  g open -a Safari; tab 2; deselect; sleep 0.5; chrome show; mouse '[["move",900,560,0.3]]'; sleep 1.5
  rec_start s04; mark search_page_shown; sleep 1.2
  api test/gesture '{"name":"forward-right"}' >/dev/null; mark dictation_starts
  speak s04a 1.4 & SPEAK=$!
  mouse '[["sleep",0.6],["move",170,376,0.8],["sleep",0.2],["click"],["sleep",0.5],["click","right"]]'; mark menu_open
  mouse '[["sleep",1.4],["move",223,430,0.5],["sleep",0.3],["click"]]'; mark copy_clicked
  mouse '[["sleep",2.4]]'; wait $SPEAK; mark copy_flight_end
  mouse '[["move",680,560,0.7],["click"],["sleep",0.9]]'; mark back_on_site
  speak s04b 0.8 & SPEAK=$!
  mouse '[["move",722,225,0.7],["sleep",0.15]]'; mark crop_start
  mouse '[["down","middle"],["drag",1216,475,1.3,"middle"],["sleep",0.35],["up","middle"]]'; mark crop_end
  mouse '[["sleep",2.3]]'; wait $SPEAK; mark crop_flight_end
  mouse '[["move",371,335,0.9],["sleep",0.3]]'; mark selection_start
  speak s04c 0.2 & SPEAK=$!
  mouse '[["down","left"],["drag",452,335,1.3,"left"],["up","left"]]'; mark selection_end
  mouse '[["sleep",2.6]]'; wait $SPEAK; mark selection_flight_end
  api test/gesture '{"name":"forward-click"}' >/dev/null
  wait_state "(d.get('prompt') or {}).get('held')" 25
  mouse '[["move",120,150,0.9],["sleep",0.4],["move",150,120,0.3]]'; mark panel_open
  sleep 4.5; mark prompt_sent; api test/prompt '{"do":"send"}' >/dev/null
  mouse '[["move",600,470,0.7]]'; sleep 2.3; mark page_updated
  sleep 1.2; mark cost_pill; pill '$0.19'; sleep 5
  END; chrome hide ;;
s05)  # film mode over the blinking menu
  "$FILM_DIR/site.sh" merge '{"menu-open":1,"flicker":1}'
  g open -a Safari; mouse '[["move",600,470,0.3]]'; sleep 1.5
  rec_start s05; sleep 1.5
  mouse '[["move",520,330,0.7]]'; mark dictation_starts
  api test/gesture '{"name":"forward-right"}' >/dev/null
  sleep 1.0; mark rec_starts
  api test/gesture '{"name":"back-up"}' >/dev/null
  speak s05 0.8; sleep 1.2; mark rec_ends
  api test/gesture '{"name":"forward-click"}' >/dev/null
  SEND 1.5; sleep 3.0; mark flicker_stops; sleep 4
  END
  "$FILM_DIR/site.sh" merge '{"menu-open":0}' ;;
s09)  # the terminal in front: a prompt lands (short envelope, paths not pixels), then the cost pill beside it
  g osascript -e 'tell application "Terminal" to activate' >/dev/null; mouse '[["move",520,300,0.4]]'; sleep 1.5
  rec_start s09; sleep 1.5
  mouse '[["move",600,440,0.7]]'; mark dictation_starts
  api test/gesture '{"name":"forward-right"}' >/dev/null
  speak s09 0.4
  api test/gesture '{"name":"forward-click"}' >/dev/null
  SEND 1.0; sleep 1.5; mark prompt_lands; sleep 3.5; mark cost_pill; pill '$0.06'; sleep 7
  END ;;
esac
