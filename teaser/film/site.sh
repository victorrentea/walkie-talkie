#!/bin/bash
# The demo site inside the guest: `site.sh push` copies teaser/demo-site and serves it on :8000,
# `site.sh state '{"header-dark":1,"button-orange":1}'` is the film's "agent" — the page restyles
# itself within ~150 ms (it polls state.json), `site.sh open` puts Safari on it, filling the screen.
source "$(dirname "$0")/lib.sh"
case "$1" in
  push)
    COPYFILE_DISABLE=1 tar -C "$TEASER_DIR" -cf - demo-site | tart exec -i $VM tar -C /Users/admin/film -xf -
    gsh 'cd ~/film/demo-site && (lsof -ti :8000 >/dev/null || nohup /usr/bin/python3 -m http.server 8000 --bind 127.0.0.1 >/dev/null 2>&1 </dev/null &) ; sleep 1; curl -s -o /dev/null -w "%{http_code}\n" localhost:8000/' ;;
  state) printf '%s' "$2" | tart exec -i $VM sh -c 'cat > /Users/admin/film/demo-site/state.json' ;;
  open)
    gsh 'open -a Safari "http://localhost:8000/"; sleep 2; osascript -e "tell application \"Safari\" to set bounds of front window to {0, 25, 1280, 720}"' ;;
esac
