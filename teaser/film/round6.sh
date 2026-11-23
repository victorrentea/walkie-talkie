#!/bin/zsh
# Round 6 takes — the whole screen is shown, no punch-ins: the guest runs at 960x540 HiDPI (the framebuffer is exactly
# 1920x1080, 1 pt = 2 px), normal fonts, normal browser zoom.   round6.sh open | s01 | s02 | s03 | s04 | s06 | s07e | s07a | s07b | s07c | s07d | cut [take…] | s04prep
#   open   Safari (ONE window, one tab: http://brewly.test — a hosts name, no "localhost") and Chrome in app mode (the image
#          search, no address bar) — two APPS, so a real ⌘Tab goes between them
#   s01…s04 one continuous page, in that order (only s01 resets it); s06 the Java diff; s07* the five destinations
# Screen points throughout (960x540, origin top-left); the page's content starts 77 pt down.
# Pointer moves are mouse.py's human paths. Every take leaves /tmp/teaser-raw/<take>.mp4 + .marks; `cut` exports it.
source "$(dirname "$0")/lib.sh"
SITE=http://brewly.test
TERM_BIG='100, 62, 860, 512'                                # the hook's terminal, and where every terminal shows
S() { g osascript "$@" >/dev/null; }
dark()  { S -e "tell application \"System Events\" to tell appearance preferences to set dark mode to $1"; }
url()   { S -e "tell application \"Safari\" to set URL of front document to \"$SITE/$1\""; }
front() { if [ "$1" = "Google Chrome" ]; then S -e 'tell application "/Users/admin/film/chrome/Google Chrome.app" to activate'; else S -e "tell application \"$1\" to activate"; fi; }
key_cmdtab() { mouse '[["flags","cmd"],["sleep",0.12],["key",48,"cmd"],["sleep",'${1:-0.9}'],["flags"]]'; }   # the switcher stays up while ⌘ is held
banner_off() { mouse '[["move",760,75,0.3],["sleep",0.8],["move",604,44,0.3],["sleep",0.4],["click"],["sleep",0.5],["move",600,300,0.3]]'; }   # the "Software Update" banner: hover, ✕ (ending NotificationCenter only brings it back)
calm() {   # nothing of the previous take on screen: a held panel / its corner dust (a spawn keeps it for half a minute) is let go and waited out
  api test/prompt '{"do":"release"}' >/dev/null 2>&1
  wait_state "not ((d.get('prompt') or {}).get('cornerTunnel') or {}).get('up') and not (d.get('prompt') or {}).get('held') and not d.get('chip')" 45 >/dev/null
}
rec_start() { calm; REC_NAME=$1; rm -f "$RAW/$1.marks" "$RAW/$1.gmarks" "$RAW/$1.rects" "$RAW/$1.peek"; python3 "$FILM_DIR/vncrec.py" "$RAW/$1.mp4" > "$RAW/$1.log" 2>&1 & REC_PID=$!; sleep 1.2; }
END()  { [ -f $RAW/$REC_NAME.gmarks ] && gmarks; kill -INT $REC_PID; wait $REC_PID; tail -1 $RAW/$REC_NAME.log; tr '\n' ' ' < $RAW/$REC_NAME.marks; echo; }
SEND() { wait_state "(d.get('prompt') or {}).get('held')" 25; sleep ${1:-1.4}; mark prompt_sent; api test/prompt '{"do":"send"}' >/dev/null; }
# One take = one choreography INSIDE the guest: `play` hands mouse.py every gesture, pointer path, control-port call and
# mark with its instant (["at", s] = s seconds after T0), `voice` starts one audio stream whose pieces begin at theirs.
# (A `tart exec` + python launch per step costs ~2 s; that is what made the words miss their gestures.)
OFF=$(python3 -c "import sys,time;print(float(sys.argv[1])-time.time())" "$(g /usr/bin/python3 -c 'import time;print(time.time())')")   # guest clock − host clock
GT0=0
t0() { GT0=$(python3 -c "import time;print(time.time()+$OFF+${1:-3.5})"); g rm -f /tmp/film-marks; }   # T0 = 3.5 s from now, guest clock
voice() {   # voice <name>@<s> …: each piece's WORDS begin s seconds after T0 (the files carry 0.3 s of lead-in); marks speech_<name>
  local a=() p; for p in "$@"; do a+=("/Users/admin/film/voice/${p%@*}.wav@$(python3 -c "print(${p#*@}-0.3)")"); echo "speech_${p%@*} $(python3 -c "print($GT0+${p#*@})")" >> $RAW/$REC_NAME.gmarks; done
  g /usr/bin/python3 /Users/admin/film/say.py --at $GT0 "${a[@]}" &
}
play() { g /usr/bin/python3 /Users/admin/film/mouse.py "$1" $GT0; g cat /tmp/film-marks >> $RAW/$REC_NAME.gmarks 2>/dev/null; g rm -f /tmp/film-marks; }   # blocks until the choreography ends
gmarks() {  # the guest's marks (guest epoch) → seconds of the recording, into the take's .marks
  python3 -c "
import re,sys
t0=float(re.search(r't0 ([0-9.]+)',open(sys.argv[1]).read()).group(1))
for l in open(sys.argv[2]): n,t=l.split(); print(n, round(float(t)-$OFF-t0,2))" $RAW/$REC_NAME.log $RAW/$REC_NAME.gmarks >> $RAW/$REC_NAME.marks; rm -f $RAW/$REC_NAME.gmarks
}
pill_rect() {   # pill_rect <mark name>: the 💸 pill's rectangle in the clip's pixels [x, y, w, h] (the app answers Cocoa points, origin bottom-left) + its alpha
  api test/turn-cost '{"state":true}' | python3 -c "
import json,sys
fl=json.load(sys.stdin)['floats']
if not fl: print('$1 gone'); sys.exit()
f=fl[-1]; x,y,w,h=f['frame']
print('$1', json.dumps({'rect_px':[round(x*2), round((540-y-h)*2), round(w*2), round(h*2)], 'alpha': round(f['alpha'],2)}))" | tee -a "$RAW/$REC_NAME.rects"
}
stage_terminal() {   # ONE opaque Terminal window running the stand-in session in ~/workspace/brewly, bound. Guest only.
  gkill -9 Terminal; g sudo bash /Users/admin/film/gkill.sh login; sleep 1.5
  gsh 'defaults write com.apple.Terminal ApplePersistenceIgnoreState -bool true; rm -rf ~/Library/Saved\ Application\ State/com.apple.Terminal.savedState
       printf "#!/bin/sh\nsleep 3.4\nclear\ncd ~/workspace/brewly && exec env '"${AGENT_ENV:-A=1}"' ~/film/bin/claude\n" > ~/film/brewly.command; chmod +x ~/film/brewly.command
       open -a Terminal ~/film/brewly.command'
  sleep 2.5
  S -e "tell application \"Terminal\" to set bounds of front window to {${TERM_BOUNDS:-$TERM_BIG}}" -e 'tell application "Terminal" to set custom title of selected tab of front window to "brewly"'
  local tty=$(g osascript -e 'tell application "Terminal" to get tty of selected tab of front window' | sed 's#/dev/##')
  api unbind '{}' >/dev/null 2>&1; api bind "{\"tty\":\"$tty\"}" >/dev/null; api target; echo
}
chrome() {   # start | show — the image search in Chrome's app mode (a window with a title bar and no address bar)
  case "$1" in
    start) gkill "Google Chrome"; sleep 1
           gsh 'nohup open -na ~/film/chrome/"Google Chrome.app" --args --no-first-run --no-default-browser-check --disable-search-engine-choice-screen --disable-notifications --hide-crash-restore-bubble --window-position=30,40 --window-size=900,480 --app=http://brewly.test/gimages/index.html?v=r6 >/dev/null 2>&1 </dev/null'; sleep 7 ;;
    show)  front "Google Chrome"; sleep 1 ;;
  esac
}
FINAL='{"header-dark":1,"button-orange":1,"moved":{"fromX":36,"fromY":412,"toX":36,"toY":137},"picture":1,"typo-fixed":1,"pictureSrc":"gimages/img/0.jpg","artBox":{"x":505,"y":165,"w":400,"h":260}}'
s07desk() {   # s07desk [agent env]: the one desktop of the s07 beats
  dark true; [ -f $RAW/final-state.json ] && FINAL=$(cat $RAW/final-state.json)      # the page exactly as the s04 take left it
  "$FILM_DIR/site.sh" state "$FINAL"; url "index.html?v=r6"
  AGENT_ENV="${1:-A=1}" stage_terminal >/dev/null; sleep 5
  BOUND_TTY=$(api target | python3 -c "import json,sys;print(json.load(sys.stdin).get('address',''))")
}
new_terminal_in_place() {   # the window Walkie spawned opens behind the browser: put it where the terminal always shows, first among Terminal's windows (STAGED, unseen)
  local tty i
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
    tty=$(api target | python3 -c "import json,sys;print(json.load(sys.stdin).get('address',''))")
    g osascript -e 'tell application "Terminal"' -e "set w to first window whose tty of selected tab is \"/dev/$tty\"" -e 'set miniaturized of w to false' -e "set bounds of w to {$TERM_BIG}" -e 'set index of w to 1' -e 'end tell' >/dev/null 2>&1 && [ "$tty" != "$BOUND_TTY" ] && return 0
    sleep 0.7
  done; echo "the spawned window was not found"
}
case "$1" in
cut) shift; python3 "$FILM_DIR/cut6.py" "$@" ;;      # export the takes to teaser/footage (+ sidecars); the replaced clips stay as *-r5
open)
  S -e 'tell application "Safari" to close every window' 2>/dev/null
  gsh "open -a Safari '$SITE/index.html?v=r6'"; sleep 3
  S -e 'tell application "Safari" to set bounds of front window to {0, 25, 960, 540}'
  chrome start; front Safari ;;
s01)  # a large terminal with the agent's session, still for 3.8 s; ⌘⌃B binds it under the pointer (the flight, the outline);
      # the hand goes to the page showing beside it and clicks: the browser covers the terminal, the chip names the session
  dark false; "$FILM_DIR/site.sh" state '{}'; url "index.html?v=r6"
  AGENT_ENV='AGENT_HISTORY=1' stage_terminal >/dev/null; sleep 5; api unbind '{}' >/dev/null 2>&1
  front Safari; sleep 0.6; front Terminal; mouse '[["move",560,330,0.3]]'; sleep 2
  rec_start s01; mark terminal_shown; sleep 3.8; mark bind_start
  mouse '[["key",11,"cmd","ctrl"],["sleep",3.4]]'; mark bind_done
  mouse '[["move",52,330,0.75],["sleep",0.25],["click"]]'; mark browser_front
  mouse '[["sleep",0.5],["move",600,300,0.9],["sleep",2.6]]'
  END ;;
s02)  # bound, the browser in front. "Make the header dark, and this button (the pointer comes to rest on the SECOND button,
      # 🔽 = the shutter) orange." → the header goes dark and only that button orange; then the 💸 pill (real UI, made-up amount)
  front Safari; mouse '[["move",600,300,0.3]]'; sleep 1; rm -f $RAW/s02.rects
  rec_start s02; t0; voice s02a@1.3 s02b@2.75 s02c@4.1
  play '[["at",0],["mark","dictation_starts"],["api","test/gesture",{"name":"forward-right"}],
         ["at",2.1],["mark","pointer_leaves"],["move",322,377,0.85],["mark","pointer_on_button"],
         ["at",3.35],["mark","shutter"],["api","test/gesture",{"name":"back-click"}],
         ["at",5.7],["mark","dictation_ends"],["api","test/gesture",{"name":"forward-click"}]]'
  SEND 1.6; mouse '[["move",640,250,0.8]]'; sleep 1.6; mark restyle
  sleep 1.0; mark cost_pill; pill '$0.12'; mouse '[["sleep",0.5],["move",726,221,0.5]]'; mark pointer_on_pill   # the pointer over it holds it at full opacity
  pill_rect pill; sleep 3.2; pill_rect pill_3s_later; mouse '[["move",700,300,0.6]]'; mark pointer_off_pill; sleep 2.5
  END; cat $RAW/s02.rects ;;
s03)  # "Move this" — a wheel box round the badge, ⇧ locks it, the ghost rides the pointer — "up here." — a click drops it above
      # the headline, and the badge lands exactly there. Then a real ⌘Tab (the switcher shows): the image search, in Chrome, comes forward.
  front "Google Chrome"; sleep 0.8; front Safari; mouse '[["move",640,280,0.3]]'; sleep 1
  rec_start s03; t0; voice s03a@2.05 s03b@4.75
  play '[["at",0],["mark","dictation_starts"],["api","test/gesture",{"name":"forward-right"}],
         ["at",1.0],["move",36,412,0.85],["at",2.0],["mark","wheel_box_start"],["down","middle"],["drag",273,452,0.8,"middle"],["mark","wheel_box_end"],
         ["sleep",0.3],["flags","shift"],["sleep",0.4],["up","middle"],["sleep",0.15],["flags"],["mark","box_locked"],
         ["at",3.95],["mark","carry_start"],["move",273,177,1.15],["mark","carry_end"],["at",5.9],["mark","drop"],["click","left"],
         ["at",7.3],["mark","dictation_ends"],["api","test/gesture",{"name":"forward-click"}]]'
  SEND 1.4; mouse '[["move",640,280,0.8]]'; sleep 1.6; mark page_lands
  sleep 1.0; mark cost_pill; pill '$0.08'; mouse '[["sleep",0.5],["move",726,251,0.5]]'; mark pointer_on_pill
  pill_rect pill; sleep 2.6; mouse '[["move",660,330,0.6]]'; mark pointer_off_pill; sleep 1.6
  mark cmd_tab; key_cmdtab 1.0; mark search_page_front; sleep 3
  END; cat $RAW/s03.rects ;;
s04)  # starts on the image search (Chrome, in front). "Use this picture" — right-click a result, Copy Image (the menu shows, the
      # picture flies into the chip); a real ⌘Tab back to the site; "here," — a wheel box drawn in 0.45 s over an empty part of
      # the page; "and fix this text." — the misspelt word selected by a drag. The prompt panel is then opened by the hand
      # reaching the atom and stays, untouched, 7 s; sent; the picture appears in the drawn box and the typo is fixed; the pill.
  "$FILM_DIR/site.sh" merge '{"artBox":{"x":505,"y":165,"w":400,"h":260},"pictureSrc":"gimages/img/0.jpg"}'   # the fallback box = the one drawn below (the stand-in takes the prompt's own ✂️ box when it carries one)
  api test/auto-attach '{"screenshot":false}' >/dev/null   # no automatic context frame in THIS prompt: with it the panel is taller than the 540 pt screen and the sentence scrolls out of sight (put back below)
  front Safari; sleep 0.8; front "Google Chrome"; sleep 1; mouse '[["move",600,300,0.3]]'; sleep 1
  rec_start s04; mark search_page_shown; t0 4.5; voice s04a@1.7 s04bc@8.55
  play '[["at",0],["mark","dictation_starts"],["api","test/gesture",{"name":"forward-right"}],
         ["at",1.0],["move",131,222,0.85],["at",2.1],["click","right"],["mark","menu_open"],
         ["at",3.4],["move",182,277,0.5],["at",4.3],["click"],["mark","copy_clicked"],
         ["at",6.2],["mark","cmd_tab"],["flags","cmd"],["sleep",0.12],["key",48,"cmd"],["sleep",0.9],["flags"],["mark","back_on_site"],
         ["at",7.7],["move",505,165,0.75],["at",8.6],["mark","crop_start"],["down","middle"],["drag",905,425,0.45,"middle"],["mark","crop_end"],["sleep",0.3],["up","middle"],
         ["at",9.45],["move",201,298,0.8],["at",10.35],["mark","selection_start"],["down","left"],["drag",394,298,0.8,"left",0],["up","left"],["mark","selection_end"],
         ["at",12.5],["mark","dictation_ends"],["api","test/gesture",{"name":"forward-click"}],
         ["sleep",0.25],["move",150,196,0.9],
         ["waitstate","(d.get(\"prompt\") or {}).get(\"held\")",25],["mark","prompt_held"],["move",113,154,0.25],["mark","panel_open"],
         ["waitstate","not (d.get(\"prompt\") or {}).get(\"held\")",25],["mark","prompt_sent"],["sleep",0.3],["move",520,470,0.9]]'
  # (the panel's clock is the app's: 6 s from the moment the words are ready, pointer or not — it sends itself; nothing is clicked)
  sleep 1.8; mark page_updated
  sleep 1.0; mark cost_pill; pill '$0.19'; mouse '[["sleep",0.5],["move",606,441,0.5]]'; mark pointer_on_pill
  pill_rect pill; sleep 3; mouse '[["move",560,490,0.6]]'; mark pointer_off_pill; sleep 2
  END; cat $RAW/s04.rects; api test/auto-attach '{"screenshot":true}' >/dev/null
  g cat /Users/admin/film/demo-site/state.json > $RAW/final-state.json ;;                # the page as this take left it: what the s07 beats show
s06)  # the Java diff (drawn in the browser; the lab has no IDE). "I don't like this loop." — the loop is selected by a 0.3 s drag
      # WHILE the line is spoken — "Use Streams." → the stand-in rewrites it: stream().filter().mapToDouble().sum()
  "$FILM_DIR/site.sh" merge '{"loop-fixed":0}'; url "code.html?v=r6"; front Safari; mouse '[["move",640,330,0.3]]'; sleep 2
  rec_start s06; t0; voice s06a@1.5 s06b@3.6
  play '[["at",0],["mark","dictation_starts"],["api","test/gesture",{"name":"forward-right"}],
         ["at",1.1],["move",320,255,0.7],["at",2.15],["mark","selection_start"],["down","left"],["drag",334,351,0.3,"left"],["up","left"],["mark","selection_end"],
         ["at",3.3],["move",640,400,0.9],
         ["at",5.5],["mark","dictation_ends"],["api","test/gesture",{"name":"forward-click"}]]'
  SEND 1.4; sleep 2.4; mark rewritten; sleep 5
  END ;;
s04prep)  # the page back to how s03 left it (s04's result undone), to retake s04 alone
  "$FILM_DIR/site.sh" state "$(python3 -c "import json;d=json.load(open('$RAW/final-state.json'));[d.pop(k,None) for k in ('picture','typo-fixed','artBox','pictureSrc')];print(json.dumps(d))")"
  dark false; url "index.html?v=r6"; sleep 1.5 ;;
s05)  # film mode over the blinking Plans menu, on the page as s04 left it. 🔼 → opens the prompt, 🔽 ↑ starts the film of the whole
      # display (REC corners; the app draws no dust and no edge while it runs), "See how this flickers? Fix it.", 🔼 ends both;
      # the stand-in stops the blinking when the prompt lands. The dust already in the air when the film starts lives out its
      # ~4 s (the app adds none): the words are spoken after it is gone, so the whole spoken part is clean
  dark false; [ -f $RAW/final-state.json ] && FINAL=$(cat $RAW/final-state.json)
  "$FILM_DIR/site.sh" state "$(python3 -c "import json,sys;d=json.loads(sys.argv[1]);d.update({'menu-open':1,'flicker':1});print(json.dumps(d))" "$FINAL")"; url "index.html?v=r6"
  stage_terminal >/dev/null; sleep 5; front Terminal; sleep 0.6; front Safari; mouse '[["move",430,330,0.3]]'; sleep 1.5
  rec_start s05; t0; voice s05b@4.7
  play '[["at",0],["mark","flicker_visible_from"],["mark","dictation_starts"],["api","test/gesture",{"name":"forward-right"}],
         ["at",0.3],["mark","film_starts"],["api","test/gesture",{"name":"back-up"}],
         ["at",0.6],["move",740,347,0.8],["at",5.2],["move",800,352,0.6],["at",6.4],["move",762,342,0.6],
         ["at",8.4],["mark","film_stops"],["mark","dictation_ends"],["api","test/gesture",{"name":"forward-click"}]]'
  SEND 1.4; sleep 9
  END; "$FILM_DIR/site.sh" merge '{"menu-open":0,"flicker":0}' ;;
s08)  # the ⚡ quick question (🔼 ← at rest) over the real github.com/Netflix/Hystrix, dark appearance: question marks down the left
      # edge, the reply pop-up and its 🔎 web check and 🧐 review. The three answers are SCRIPTED (claude_p.py stands in for
      # `claude -p`; they state only what was verified on that page on 2026-11-22)
  fake_claude on; dark true; api test/quick '{"close":true}' >/dev/null 2>&1
  S -e 'tell application "Terminal" to set miniaturized of every window to true' 2>/dev/null
  S -e 'tell application "Safari" to set URL of front document to "https://github.com/Netflix/Hystrix#hystrix-status"'; front Safari; sleep 12
  mouse '[["move",600,300,0.3]]'; sleep 1
  rec_start s08; t0; voice s08@1.0
  play '[["at",0],["move",560,280,0.7],["mark","question_starts"],["api","test/gesture",{"name":"forward-left"}],
         ["at",5.6],["mark","question_ends"],["api","test/gesture",{"name":"forward-click"}]]'
  for i in $(seq 1 44); do   # the pop-up's frame and words, twice a second, for the editor's marks
    api test/quick '{"peek":true}' | python3 -c "
import json,sys,time
d=json.load(sys.stdin); print(json.dumps({'t':time.time(),'frame':d.get('frame'),'shown':d.get('shown')}, ensure_ascii=False))" >> $RAW/s08.peek 2>/dev/null; sleep 0.4
  done
  END; api test/quick '{"close":true}' >/dev/null; dark false ;;
# ---- s07: five destinations on ONE desktop: dark appearance, the Brewly page as s04 left it filling the screen, the bound
#      session's terminal (TERM_BIG) behind it. Each beat stages that desktop afresh.
s07e) # a prompt to the bound session hidden behind the browser (right edge dust); the moment it is sent, a real ⌘Tab brings the
      # terminal forward: the prompt is there, the stand-in "works" (spinner, a tool row) for as long as it is filmed
  s07desk 'AGENT_DELAY=600'; front Terminal; sleep 0.6; front Safari; mouse '[["move",560,300,0.3]]'; sleep 1.5
  rec_start s07e; t0; voice s07e6@1.9
  play '[["at",0],["mark","dictation_starts"],["api","test/gesture",{"name":"forward-right"}],["at",0.5],["move",470,290,0.8],
         ["at",5.0],["mark","dictation_ends"],["api","test/gesture",{"name":"forward-click"}],
         ["waitstate","(d.get(\"prompt\") or {}).get(\"held\")",25],["sleep",1.0],["mark","prompt_sent"],["api","test/prompt",{"do":"send"}],
         ["sleep",0.5],["mark","cmd_tab"],["flags","cmd"],["sleep",0.12],["key",48,"cmd"],["sleep",0.8],["flags"],["mark","terminal_front"],["sleep",6]]'
  END ;;
s07a) # 🔼 ↑ = a session that does not exist yet: the folder dialog (four pinned folders; under brewly the bound session, working: ⏳),
      # brewly clicked; top edge dust; the new Terminal window with the stand-in "claude", the prompt in the SHORT envelope
  s07desk 'AGENT_STATUS=busy'; fake_claude on; front Safari; mouse '[["move",560,330,0.3]]'; sleep 2.5
  rec_start s07a; t0; voice s07a@1.0
  play '[["at",0],["move",430,200,0.7],["mark","swipe_up"],["api","test/gesture",{"name":"forward-up"}],["mark","dialog_up"],
         ["at",3.6],["move",'${PICK:-505,281}',0.7],["mark","pointer_on_folder"],["at",5.0],["click"],["mark","folder_picked"],
         ["at",7.6],["mark","dictation_ends"],["api","test/gesture",{"name":"forward-click"}]]'
  wait_state "(d.get('lastDelivery') or {}).get('to','').startswith('spawn')" 40; mark spawned; sleep 1.0; new_terminal_in_place
  mark cmd_tab; key_cmdtab 0.8; mark new_terminal_front; sleep 6
  END ;;
s07b) # the wake word. The wake itself is INJECTED (/test/wake: the lab has no wake-word helper); the row, the top edge, the
      # spoken sentence and the spawned session are the app's own
  s07desk; fake_claude on; front Safari; mouse '[["move",560,330,0.3]]'; sleep 2.5
  rec_start s07b; t0; voice s07a@1.6
  play '[["at",0],["move",470,300,0.7],["at",0.9],["mark","wake"],["api","test/wake",{"event":"wake"}],
         ["at",7.6],["mark","speech_ends"],["api","test/wake",{"event":"silence","head":"start a new session and review my last commit"}]]'
  wait_state "(d.get('lastDelivery') or {}).get('to','').startswith('spawn')" 40; mark spawned; sleep 1.0; new_terminal_in_place
  mark cmd_tab; key_cmdtab 0.8; mark new_terminal_front; sleep 6
  END ;;
s07c) # a prompt at the caret: the terminal in front, the red pin on its caret, bottom edge pins; the words land in the input box, unsent
  s07desk; front Safari; sleep 0.6; front Terminal; mouse '[["move",700,400,0.3]]'; sleep 2
  rec_start s07c; t0; voice s07c@1.2
  play '[["at",0],["move",520,330,0.7],["mark","dictation_starts"],["api","test/gesture",{"name":"forward-click"}],
         ["at",8.0],["mark","dictation_ends"],["api","test/gesture",{"name":"forward-click"}]]'
  wait_state "(d.get('lastDelivery') or {}).get('to')=='caret' and not d.get('listening') and d.get('phase')=='done'" 20; mark prompt_lands
  sleep 6
  END ;;
s07d) # plain dictation into a chat box: the Mosaic dress, the red pin on the caret; Transcribing → ✍️ Redacting → the clean text,
      # "Resilience4j" spelt right (the redactor's far end is claude_p.py, a scripted stand-in for `claude -p`; vocabulary.txt seeded)
  s07desk; fake_claude on
  gsh 'printf "Resilience4j\nresilience for jay → Resilience4j\n" > ~/.walkie-talkie/vocabulary.txt; rm -f ~/film/redactor.log'
  url "chat.html?v=r6"; front Safari; sleep 2; mouse '[["move",560,455,0.4],["click"],["sleep",0.3],["move",640,330,0.4]]'; sleep 1.5
  rec_start s07d; t0; voice s07d@1.0
  play '[["at",0],["move",640,255,0.6],["mark","dictation_starts"],["api","test/gesture",{"name":"back-click"}],
         ["at",8.4],["mark","dictation_ends"],["api","test/gesture",{"name":"back-click"}]]'
  sleep 2; wait_state "d.get('phase')=='done' and not any('Redact' in c or 'Transcrib' in c for c in d.get('chip') or [])" 25; mark text_landed
  sleep 6
  END; g cat /Users/admin/film/redactor.log | tee $RAW/s07d.heard; dark false ;;
esac
