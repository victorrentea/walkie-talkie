#!/bin/zsh
# Bring the lab guest up for filming, from a stopped VM:  setup.sh [bundle]   (teardown.sh undoes it)
#   boots wt-lab headless with the framework's VNC framebuffer, deploys the app bundle (default: the
#   stage-only build in /tmp/teaser-staging), 1280x720 HiDPI, Dock and desktop icons hidden, the drawn
#   pointer, the guest-side helpers and voices in ~/film, the demo site on :8000.
source "$(dirname "$0")/lib.sh"
tart set $VM --display 1920x1080
vm_up_vnc
g mkdir -p /Users/admin/film/voice
for f in dispmode.swift mouse.py say.py fakecursor.py agent.py claude_p.py oneterm.sh termprofile.sh; do push "$FILM_DIR/$f" /Users/admin/film/$f; done
g defaults write ro.victorrentea.wispr-relay cropReadoutsHidden -bool true; g defaults write ro.victorrentea.wispr-relay edgeDust.marksBoost -float 2
g defaults write ro.victorrentea.wispr-relay hintBarHidden -bool true     # no corner hint bar in the footage (teardown removes the key)
gsh 'cd ~/film && swiftc -O dispmode.swift -o dispmode 2>/dev/null; ./dispmode 1280 720 1
     defaults write com.apple.finder CreateDesktop -bool false; killall Finder
     defaults write com.apple.dock autohide -bool true; defaults write com.apple.dock autohide-delay -float 1000; killall Dock
     for a in "Microsoft PowerPoint" "System Settings" TextEdit; do pkill -x "$a"; done; true'
# the bound tab's agent runs under a process NAMED claude (Walkie looks for that name on the tty)
gsh 'mkdir -p ~/film/bin && printf "#include <stdlib.h>\nint main(void){return system(\"/usr/bin/python3 ~/film/agent.py\");}\n" > ~/film/bin/claude.c && cc -o ~/film/bin/claude ~/film/bin/claude.c
     defaults write com.apple.menuextra.clock IsAnalog -bool true; killall ControlCenter; true'
# A classic OPAQUE Terminal (Victor: "De ce e transparent terminalul ăsta? … un terminal clasic"): the Pro profile with a
# solid black background, and a plain window title (no process name or arguments). teardown.sh puts the plist back.
gsh 'cp ~/Library/Preferences/com.apple.Terminal.plist ~/film/Terminal.plist.bak
osascript -e "tell application \"Terminal\" to set background color of settings set \"Pro\" to {0, 0, 0}" -e "tell application \"Terminal\" to set font size of settings set \"Pro\" to 15" -e "tell application \"Terminal\" to set default settings to settings set \"Pro\"" -e "tell application \"Terminal\" to quit"; sleep 2
bash ~/film/termprofile.sh; defaults write com.apple.Terminal NSQuitAlwaysKeepsWindows -bool false
killall cfprefsd; true'
gsh 'nohup /usr/bin/python3 ~/film/fakecursor.py >/tmp/fakecursor.log 2>&1 </dev/null & echo $! > /tmp/fakecursor.pid'
"$FILM_DIR/voices.sh"
"$FILM_DIR/site.sh" push
gsh 'cd ~/film && qlmanage -t -s 600 -o . demo-site/beans.svg >/dev/null 2>&1; ls beans.svg.png'   # the picture s04 puts on the clipboard
deploy "${1:-/tmp/teaser-staging/Walkie Talkie.app}"
