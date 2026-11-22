#!/bin/zsh
# Bring the lab guest up for filming, from a stopped VM:  setup.sh [bundle]   (teardown.sh undoes it)
#   boots wt-lab headless with the framework's VNC framebuffer, deploys the app bundle (default: the
#   stage-only build in /tmp/teaser-staging — `WALKIE_STAGING=/tmp/teaser-staging ./build-app.sh --stage-only`),
#   960x540 HiDPI (round 6: the whole screen is shown un-zoomed, so the screen itself is small and the
#   framebuffer is exactly 1920x1080; FILM_MODE="1280 720" for the older rounds), Dock and desktop icons hidden, the drawn
#   pointer, the guest-side helpers and voices in ~/film, the demo site on :8000.
source "$(dirname "$0")/lib.sh"
# Never take a VM somebody else booted: the nightly Wispr labelling run (~/tart/wispr-batch, from 22:00 after 10 idle minutes)
# uses this same guest for hours. On 2026-11-22 this script did not look, changed its display setting and removed its
# control socket (vm_up_vnc) before noticing — the batch survived only because its guard falls back to SSH.
[ "$(vm_state)" = running ] && { echo "wt-lab is already running ($(pgrep -lf 'tart run wt-lab' | cut -c1-120)) — not mine to take; wait for it to stop"; exit 1; }
tart set $VM --display 1920x1080
vm_up_vnc
g mkdir -p /Users/admin/film/voice
for f in gkill.sh dispmode.swift mouse.py say.py fakecursor.py agent.py claude_p.py oneterm.sh termprofile.sh; do push "$FILM_DIR/$f" /Users/admin/film/$f; done
g defaults write ro.victorrentea.wispr-relay cropReadoutsHidden -bool true; g defaults write ro.victorrentea.wispr-relay edgeDust.marksBoost -float 2
g defaults write ro.victorrentea.wispr-relay hintBarHidden -bool true     # no corner hint bar in the footage (teardown removes the key)
gsh 'cd ~/film && FILM_MODE="'"${FILM_MODE:-960 540}"'" && swiftc -O dispmode.swift -o dispmode 2>/dev/null; ./dispmode ${FILM_MODE:-960 540} 1
     defaults write com.apple.finder CreateDesktop -bool false; bash ~/film/gkill.sh Finder
     defaults write com.apple.dock autohide -bool true; defaults write com.apple.dock autohide-delay -float 1000; bash ~/film/gkill.sh Dock
     bash ~/film/gkill.sh "Microsoft PowerPoint" "System Settings" TextEdit; true'
# the bound tab's agent runs under a process NAMED claude (Walkie looks for that name on the tty)
gsh 'mkdir -p ~/film/bin && printf "#include <stdlib.h>\nint main(void){return system(\"/usr/bin/python3 ~/film/agent.py\");}\n" > ~/film/bin/claude.c && cc -o ~/film/bin/claude ~/film/bin/claude.c
     defaults write com.apple.menuextra.clock IsAnalog -bool true; bash ~/film/gkill.sh ControlCenter; true'
# A classic OPAQUE Terminal (Victor: "De ce e transparent terminalul ăsta? … un terminal clasic"): the Pro profile with a
# solid black background, and a plain window title (no process name or arguments). teardown.sh puts the plist back.
gsh 'cp ~/Library/Preferences/com.apple.Terminal.plist ~/film/Terminal.plist.bak
osascript -e "tell application \"Terminal\" to set background color of settings set \"Pro\" to {0, 0, 0}" -e "tell application \"Terminal\" to set font size of settings set \"Pro\" to 13" -e "tell application \"Terminal\" to set font antialiasing of settings set \"Pro\" to true" -e "tell application \"Terminal\" to set default settings to settings set \"Pro\"" -e "tell application \"Terminal\" to quit"; sleep 2
bash ~/film/termprofile.sh; defaults write com.apple.Terminal NSQuitAlwaysKeepsWindows -bool false
defaults write NSGlobalDomain AppleShowScrollBars -string WhenScrolling     # no scroller strip in the terminal (teardown removes the key)
bash ~/film/gkill.sh cfprefsd; true'
gsh 'nohup /usr/bin/python3 ~/film/fakecursor.py >/tmp/fakecursor.log 2>&1 </dev/null & echo $! > /tmp/fakecursor.pid'
# Round 6: the site answers to a name (no "localhost" in the address bar), four pinned project folders for the folder
# dialog, the stamp a session's walkie-inbox mod leaves (a spawned session then gets the SHORT envelope), and a second
# browser APP for the image search (⌘Tab switches apps): Chrome, under ~/film so teardown removes it.
gsh 'grep -q brewly.test /etc/hosts || echo "127.0.0.1 brewly.test" | sudo tee -a /etc/hosts >/dev/null
mkdir -p ~/workspace/api ~/workspace/brewly ~/workspace/docs ~/workspace/mobile-app; echo 3 > ~/.walkie-talkie/agent-rules.claude
printf "{\"pinned\": [\"/Users/admin/workspace/api\", \"/Users/admin/workspace/brewly\", \"/Users/admin/workspace/docs\", \"/Users/admin/workspace/mobile-app\"]}" > ~/.walkie-talkie/pinned-projects.json
[ -d ~/film/chrome/"Google Chrome.app" ] || { mkdir -p ~/film/chrome && cd ~/film/chrome && curl -sL -o chrome.dmg https://dl.google.com/chrome/mac/universal/stable/GGRO/googlechrome.dmg && hdiutil attach -nobrowse -quiet chrome.dmg && cp -R "/Volumes/Google Chrome/Google Chrome.app" . && hdiutil detach -quiet "/Volumes/Google Chrome"; rm -f chrome.dmg; }'
"$FILM_DIR/voices.sh"
"$FILM_DIR/site.sh" push
gsh 'cd ~/film && qlmanage -t -s 600 -o . demo-site/beans.svg >/dev/null 2>&1; ls beans.svg.png'   # the picture s04 puts on the clipboard
deploy "${1:-/tmp/teaser-staging/Walkie Talkie.app}"
