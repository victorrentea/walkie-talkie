#!/bin/zsh
# s07 takes. All real gestures (the side button's chords) and a real voice path (synthetic voice → BlackHole → local Whisper).
#   s07.sh c   prompt at the caret: Terminal in front (stand-in agent at its ❯), red pin on the caret, bottom edge pins
#   s07.sh b   "Hey Claude": the wake event is INJECTED (/test/wake — no wake-word helper in the lab), the rest is real
#   s07.sh d   plain dictation into a chat box: Transcribing → ✍️ Redacting → pasted clean; the redactor's far end is
#              claude_p.py, a scripted stand-in for `claude -p` (it drops the fillers)
#   s07.sh a   new session: 🔼 ↑, top edge dust, Walkie spawns a Terminal window; `claude` there is the stand-in (lib: fake_claude)
source "$(dirname "$0")/lib.sh"
case "$1" in
c)
  "$FILM_DIR/site.sh" state '{}'; TERM_BOUNDS='150, 215, 1130, 716' stage_terminal; sleep 5; g osascript -e 'tell application "Terminal" to activate'; mouse '[["move",930,330,0.4]]'; sleep 1.5
  rec_start s07c; sleep 2
  mouse '[["move",700,300,0.8]]'
  api test/gesture '{"name":"forward-click"}' >/dev/null     # 🔼 : prompt at the caret
  speak s07c 0.3
  api test/gesture '{"name":"forward-click"}' >/dev/null
  wait_state "(d.get('lastDelivery') or {}).get('to')=='caret' and not d.get('listening') and d.get('phase')=='done'" 20
  sleep 7
  kill -INT $REC_PID; wait $REC_PID; cat $RAW/s07c.log ;;
a)
  fake_claude on
  g osascript -e 'tell application "Terminal" to set miniaturized of every window to true' -e 'tell application "Safari" to set miniaturized of every window to true' >/dev/null
  g osascript -e 'tell application "System Events" to set picture of every desktop to "/System/Library/Desktop Pictures/Solid Colors/Black.png"' >/dev/null
  g osascript -e 'tell application "Finder" to activate'; mouse '[["move",820,560,0.4]]'; sleep 2
  rec_start s07a; sleep 2
  mouse '[["move",560,470,0.7]]'
  api test/gesture '{"name":"forward-up"}' >/dev/null        # 🔼 ↑ : a session that does not exist yet
  speak s07a 0.3
  api test/gesture '{"name":"forward-click"}' >/dev/null
  sleep 14
  kill -INT $REC_PID; wait $REC_PID; cat $RAW/s07a.log
  fake_claude off ;;
b)
  fake_claude on; "$FILM_DIR/site.sh" state '{}'
  g osascript -e 'tell application "Safari" to set URL of front document to "http://localhost:8000/"' >/dev/null; g osascript -e 'tell application "Safari" to set miniaturized of every window to false' >/dev/null; g open -a Safari; sleep 1.5
  rec_start s07b
  mouse '[["move",600,470,0.5]]'
  api test/wake '{"event":"wake"}' >/dev/null
  speak s07a 0.3
  api test/wake '{"event":"silence","head":"start a new session and review my last commit"}' >/dev/null
  sleep 12
  kill -INT $REC_PID; wait $REC_PID; cat $RAW/s07b.log ;;
d)
  fake_claude on
  g osascript -e 'tell application "Safari" to set miniaturized of every window to false' -e 'tell application "Safari" to set URL of front document to "http://localhost:8000/chat.html"' >/dev/null; g open -a Safari; sleep 1.5
  mouse '[["move",600,640,0.4],["click"]]'                 # the caret into the message box
  rec_start s07d
  mouse '[["move",760,560,0.5]]'
  api test/gesture '{"name":"back-click"}' >/dev/null      # 🔽 : plain dictation
  speak s07d 0.3
  api test/gesture '{"name":"back-click"}' >/dev/null
  sleep 11
  kill -INT $REC_PID; wait $REC_PID; cat $RAW/s07d.log ;;
esac
