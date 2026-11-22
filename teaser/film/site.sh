#!/bin/bash
# The demo site inside the guest: `site.sh push` copies teaser/demo-site and serves it on :8000,
# `site.sh state '{"header-dark":1,"button-orange":1}'` is the film's "agent" — the page restyles
# itself within ~150 ms (it polls state.json), `site.sh open` puts Safari on it, filling the screen.
source "$(dirname "$0")/lib.sh"
case "$1" in
  push)
    COPYFILE_DISABLE=1 tar -C "$TEASER_DIR" -cf - demo-site | tart exec -i $VM tar -C /Users/admin/film -xf -
    gsh 'cd ~/film/demo-site && (lsof -ti :8000 >/dev/null || /opt/homebrew/bin/tmux new-session -d -s site "/usr/bin/python3 -m http.server 8000 --bind 127.0.0.1"); 
         (lsof -ti :80 >/dev/null || sudo /opt/homebrew/bin/tmux new-session -d -s site80 "cd /Users/admin/film/demo-site && /usr/bin/python3 -m http.server 80 --bind 127.0.0.1")   # round 6: http://brewly.test/
         sleep 1; curl -s -o /dev/null -w "%{http_code}\n" localhost:8000/; curl -s -o /dev/null -w "%{http_code}\n" http://brewly.test/' ;;
  merge)   # merge keys into the page's state without resetting what earlier scenes changed
    g /usr/bin/python3 -c 'import json,sys,os; p=os.path.expanduser("~/film/demo-site/state.json"); s=json.load(open(p)); s.update(json.loads(sys.argv[1])); json.dump(s, open(p+".tmp","w")); os.replace(p+".tmp", p)' "$2" ;;
  state) printf '%s' "$2" | tart exec -i $VM sh -c 'cat > /Users/admin/film/demo-site/state.json' ;;
  open)
    # one window, two tabs, always (so the page never shifts between scenes): 1 = the image search, 2 = Brewly (in front)
    gsh 'osascript -e "tell application \"Safari\" to close every window" 2>/dev/null; open -a Safari "http://localhost:8000/search.html"; sleep 2
         osascript -e "tell application \"Safari\"" -e "set bounds of front window to {0, 25, 1280, 720}" -e "tell front window to set current tab to (make new tab with properties {URL:\"http://localhost:8000/index.html?v=r3\"})" -e "end tell"' ;;
esac
