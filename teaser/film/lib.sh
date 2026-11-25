# Shared helpers for filming the teaser inside the Tart guest `wt-lab` (never on the host screen).
#   source teaser/film/lib.sh
export TART_HOME="${TART_HOME:-$HOME/tart}"
VM=wt-lab
FILM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
TEASER_DIR="$(dirname "$FILM_DIR")"
g()   { tart exec "$VM" "$@"; }                       # a command in the guest, as admin, in Aqua
gsh() { tart exec "$VM" bash -lc "$1"; }               # a shell line in the guest
api() {                                               # api <path> [json] → the app's control port
  # X-Walkie-Token (2026-11-25): the guest's own, read inside the guest at every call.
  if [ -n "${2:-}" ]; then g bash -c 'curl -fsS -m 60 -H "X-Walkie-Token: $(cat ~/.walkie-talkie/test-token 2>/dev/null)" -X POST "http://127.0.0.1:8917/$0" -d "$1"' "$1" "$2"
  else g bash -c 'curl -fsS -m 60 -H "X-Walkie-Token: $(cat ~/.walkie-talkie/test-token 2>/dev/null)" "http://127.0.0.1:8917/$0"' "$1"; fi
}
shot() { g screencapture -x /tmp/film-shot.png && g cat /tmp/film-shot.png > "${1:-/tmp/wt-guest.png}"; }
push() { tart exec -i "$VM" sh -c "cat > '$2'" < "$1"; }   # push <host file> <guest path>
pull() { g cat "$1" > "$2"; }                              # pull <guest path> <host file>
SSHO="-o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
vm_state() { tart list --format json | python3 -c "import json,sys;print([v['State'] for v in json.load(sys.stdin) if v['Name']=='$VM'][0])"; }
vm_down() {                                           # clean guest shutdown over SSH (tart stop is a pulled plug)
  [ "$(vm_state)" = running ] || return 0
  ssh ${=SSHO} "admin@$(tart ip $VM)" 'sudo -n shutdown -h now' >/dev/null 2>&1
  for _ in $(seq 1 200); do [ "$(vm_state)" = running ] || { echo "stopped"; return 0; }; sleep 1; done
  echo "still running after 200 s — tart stop"; tart stop $VM
}
vm_up_vnc() {                                         # headless, with Virtualization.framework's own VNC server (host-side framebuffer)
  rm -f "$TART_HOME/vms/$VM/control.sock"
  nohup tart run $VM --no-graphics --no-audio --no-clipboard --vnc-experimental > "$TART_HOME/$VM.log" 2>&1 &
  disown
  for _ in $(seq 1 300); do g true 2>/dev/null && break; sleep 1; done
  grep -o 'vnc://[^ ]*' "$TART_HOME/$VM.log" | tail -1
}
deploy() {                                            # deploy <bundle>: replace the guest's app with it and launch
  g bash /Users/admin/film/gkill.sh "Walkie Talkie"; sleep 1
  g sudo rm -rf "/Applications/Walkie Talkie.app"
  COPYFILE_DISABLE=1 tar -C "$(dirname "$1")" -cf - "Walkie Talkie.app" | tart exec -i $VM sudo tar -C /Applications -xf -
  g sudo chown -R admin:staff "/Applications/Walkie Talkie.app"
  # WT_PM_SCALE=1: the guest has only the software OpenGL renderer — the dust is 6 fps at 2x, 26 at 1x (docs/vm-lab.md)
  g open --env WT_PM_SCALE=1 "/Applications/Walkie Talkie.app"
  for _ in $(seq 1 90); do api test/state >/dev/null 2>&1 && { echo "app answering"; return 0; }; sleep 2; done
  echo "app never answered"; return 1
}
gssh() { ssh ${=SSHO} "admin@$(tart ip $VM)" "$@"; }  # the fallback when tart exec hangs (no Automation / mic grants over SSH)
RAW=/tmp/teaser-raw; mkdir -p $RAW
mouse() { g /usr/bin/python3 /Users/admin/film/mouse.py "$1"; }
speak() { g /usr/bin/python3 /Users/admin/film/say.py "/Users/admin/film/voice/$1.wav" "${2:-0}"; }
rec_start() { g pkill -x SoftwareUpdateNotificationManager; g killall NotificationCenter 2>/dev/null; REC_NAME=$1; rm -f "$RAW/$1.marks"; python3 "$FILM_DIR/vncrec.py" "$RAW/$1.mp4" > "$RAW/$1.log" 2>&1 & REC_PID=$!; sleep 1.2; }   # rec_start <name>
REC_NAME=""
mark() {                                              # mark <event>: seconds since frame 0 of the running recording → $RAW/<take>.marks
  python3 -c "import sys,time,re;t0=float(re.search(r't0 ([0-9.]+)',open(sys.argv[1]).read()).group(1));print(sys.argv[2],round(time.time()-t0,1))" "$RAW/$REC_NAME.log" "$1" >> "$RAW/$REC_NAME.marks"
}
marks_json() {                                        # marks_json <take> <trim start> '<note>' → the sidecar, times inside the exported clip
  python3 -c "import sys,json;d={'note':sys.argv[3]};[d.__setitem__(k,round(float(v)-float(sys.argv[2]),1)) for k,v in (l.split() for l in open(sys.argv[1]))];print(json.dumps(d))" "$RAW/$1.marks" "$2" "$3"
}
pill() { api test/turn-cost "{\"amount\":\"$1\",\"rest\":\" · Opus 5.5 in brewly\",\"capturable\":true}" >/dev/null; }   # the real 💸 pill, made-up amount
rec_stop()  { kill -INT $REC_PID; wait $REC_PID 2>/dev/null; cat "$RAW/$REC_NAME.log" 2>/dev/null; }
wait_state() {                                        # wait_state '<python expr on d>' [timeout s]
  local t=${2:-20} i
  for i in $(seq 1 $((t * 4))); do
    api test/state | python3 -c "import json,sys;d=json.load(sys.stdin);sys.exit(0 if ($1) else 1)" && return 0; sleep 0.25
  done; echo "timeout waiting for: $1"; return 1
}
tile() { ffmpeg -loglevel error -y -i "$1" -vf "fps=${3:-1/2},scale=960:-1,tile=${4:-2x5}" -frames:v 1 "$2"; }
reload_site() { g osascript -e 'tell application "Safari" to set URL of front document to "http://localhost:8000/"' >/dev/null; }
frame() { python3 "$FILM_DIR/vncrec.py" - --png "${1:-/tmp/teaser-raw/now.png}"; }   # one frame of the guest's screen, as the film sees it
gkill() { g bash /Users/admin/film/gkill.sh "$@"; }                                   # guest: end processes by exact name (film/gkill.sh)
tab() { g osascript -e "tell application \"Safari\" to tell front window to set current tab to tab $1" >/dev/null; }   # 1 = search, 2 = Brewly
agent_restart() {                                     # (re)start the stand-in agent in the bound Terminal tab
  g pkill -f film/agent.py; sleep 0.5               # in the guest only
  g osascript -e 'tell application "Terminal" to do script "clear; cd ~/film/demo-site && ~/film/bin/claude" in front window' >/dev/null
  g open -a Safari
}
fake_claude() {                                       # on | off — a stand-in `claude` on the guest's PATH, for the spawn take only
  if [ "$1" = on ]; then
    # (the Terminal profile — opaque Pro, plain title — is set once by setup.sh)
    push "$FILM_DIR/claude_p.py" /Users/admin/film/claude_p.py
    printf '#!/bin/sh\ncase " $* " in *" -p "*) exec /usr/bin/python3 /Users/admin/film/claude_p.py "$@";; esac\nexec /usr/bin/python3 /Users/admin/film/agent.py "$@"\n' | tart exec -i $VM sh -c 'cat > /opt/homebrew/bin/claude && chmod +x /opt/homebrew/bin/claude'
  else g rm -f /opt/homebrew/bin/claude; fi
}
stage_terminal() {                                    # ONE opaque Terminal window running the stand-in agent, bound. Guest only.
  # Terminal is restarted whole: a .command file opened at a cold launch is its only window (no default window,
  # no restored ones, no "terminate?" sheet from closing others).
  g pkill -f film/agent.py; g sudo pkill -x login; g pkill -9 -x Terminal; sleep 1.5
  gsh 'defaults write com.apple.Terminal ApplePersistenceIgnoreState -bool true; rm -rf ~/Library/Saved\ Application\ State/com.apple.Terminal.savedState
       printf "#!/bin/sh\nsleep 3.4\nclear\ncd '"${AGENT_CWD:-~/film/demo-site}"' && exec env '"${AGENT_ENV:-A=1}"' ~/film/bin/claude\n" > ~/film/brewly.command; chmod +x ~/film/brewly.command
       open -a Terminal ~/film/brewly.command'
  sleep 2.5
  g osascript -e "tell application \"Terminal\" to set bounds of front window to {${TERM_BOUNDS:-480, 320, 1056, 686}}" -e 'tell application "Terminal" to set custom title of selected tab of front window to "brewly"' >/dev/null
  local tty=$(g osascript -e 'tell application "Terminal" to get tty of selected tab of front window' | sed 's#/dev/##')
  api unbind '{}' >/dev/null 2>&1; api bind "{\"tty\":\"$tty\"}" >/dev/null; api target; echo
}
chrome() {                                            # show | hide | start — the guest's Chrome on the local image search, left of the screen
  case "$1" in
    start) g pkill -x "Google Chrome"; sleep 1
           gsh 'nohup open -na "Google Chrome" --args --no-first-run --no-default-browser-check --disable-search-engine-choice-screen --disable-notifications --hide-crash-restore-bubble --window-position=64,130 --window-size=576,332 "http://localhost:8000/gimages/index.html" >/dev/null 2>&1 </dev/null'; sleep 6 ;;
    show)  g open -a "Google Chrome"; sleep 1 ;;
    hide)  g osascript -e 'tell application "System Events" to set visible of process "Google Chrome" to false' >/dev/null 2>&1 ;;
  esac
}
deselect() { g osascript -e 'tell application "Safari" to do JavaScript "getSelection().removeAllRanges()" in tab 2 of front window' >/dev/null 2>&1; }
