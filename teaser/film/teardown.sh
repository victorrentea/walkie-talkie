#!/bin/zsh
# Put the guest back as the lab keeps it and stop the VM (clean shutdown over SSH).
source "$(dirname "$0")/lib.sh"
api test/quick '{"close":true}' >/dev/null 2>&1; api unbind '{}' >/dev/null 2>&1
fake_claude off; g osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to false' >/dev/null
g defaults delete ro.victorrentea.wispr-relay hintBarHidden; g defaults delete ro.victorrentea.wispr-relay cropReadoutsHidden; g defaults delete ro.victorrentea.wispr-relay edgeDust.marksBoost
g osascript -e 'tell application "System Events" to set picture of every desktop to "/System/Library/CoreServices/DefaultDesktop.heic"' >/dev/null
# guest processes are ended by exact name, PID by PID (film/gkill.sh) — no pkill / killall, here or anywhere
gsh 'K=/tmp/gkill.sh; cp ~/film/gkill.sh $K
     kill $(cat /tmp/fakecursor.pid) 2>/dev/null; /opt/homebrew/bin/tmux kill-session -t site 2>/dev/null; sudo /opt/homebrew/bin/tmux kill-session -t site80 2>/dev/null
     bash $K "Google Chrome"; bash $K -9 Terminal; sudo bash $K login; sleep 1; defaults delete NSGlobalDomain AppleShowScrollBars 2>/dev/null
     osascript -e "tell application \"Safari\" to quit" >/dev/null 2>&1; sleep 2
     [ -f ~/film/Terminal.plist.bak ] && cp ~/film/Terminal.plist.bak ~/Library/Preferences/com.apple.Terminal.plist && bash $K cfprefsd
     defaults delete com.apple.finder CreateDesktop; defaults delete com.apple.dock autohide; defaults delete com.apple.dock autohide-delay
     defaults delete com.apple.menuextra.clock IsAnalog 2>/dev/null; bash $K ControlCenter Finder Dock; ~/film/dispmode 1024 768 1; rm -rf ~/film ~/.walkie-talkie/pinned-projects.json ~/.walkie-talkie/agent-rules.claude ~/workspace/api ~/workspace/brewly ~/workspace/docs ~/workspace/mobile-app
     sudo sed -i.film /brewly.test/d /etc/hosts; true'
vm_down
tart set $VM --display 1024x768
tart list | grep $VM
