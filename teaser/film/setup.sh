#!/bin/zsh
# Bring the lab guest up for filming, from a stopped VM:  setup.sh [bundle]   (teardown.sh undoes it)
#   boots wt-lab headless with the framework's VNC framebuffer, deploys the app bundle (default: the
#   stage-only build in /tmp/teaser-staging), 1280x720 HiDPI, Dock and desktop icons hidden, the drawn
#   pointer, the guest-side helpers and voices in ~/film, the demo site on :8000.
source "$(dirname "$0")/lib.sh"
tart set $VM --display 1920x1080
vm_up_vnc
g mkdir -p /Users/admin/film/voice
for f in dispmode.swift mouse.py say.py fakecursor.py agent.py claude_p.py; do push "$FILM_DIR/$f" /Users/admin/film/$f; done
gsh 'cd ~/film && swiftc -O dispmode.swift -o dispmode 2>/dev/null; ./dispmode 1280 720 1
     defaults write com.apple.finder CreateDesktop -bool false; killall Finder
     defaults write com.apple.dock autohide -bool true; defaults write com.apple.dock autohide-delay -float 1000; killall Dock
     for a in "Microsoft PowerPoint" "System Settings" TextEdit; do pkill -x "$a"; done; true'
# the bound tab's agent runs under a process NAMED claude (Walkie looks for that name on the tty)
gsh 'mkdir -p ~/film/bin && printf "#include <stdlib.h>\nint main(void){return system(\"/usr/bin/python3 ~/film/agent.py\");}\n" > ~/film/bin/claude.c && cc -o ~/film/bin/claude ~/film/bin/claude.c
     defaults write com.apple.menuextra.clock IsAnalog -bool true; killall ControlCenter; true'
gsh 'nohup /usr/bin/python3 ~/film/fakecursor.py >/tmp/fakecursor.log 2>&1 </dev/null & echo $! > /tmp/fakecursor.pid'
"$FILM_DIR/voices.sh"
"$FILM_DIR/site.sh" push
gsh 'cd ~/film && qlmanage -t -s 600 -o . demo-site/beans.svg >/dev/null 2>&1; ls beans.svg.png'   # the picture s04 puts on the clipboard
deploy "${1:-/tmp/teaser-staging/Walkie Talkie.app}"
