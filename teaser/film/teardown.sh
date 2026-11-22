#!/bin/zsh
# Put the guest back as the lab keeps it and stop the VM (clean shutdown over SSH).
source "$(dirname "$0")/lib.sh"
api test/quick '{"close":true}' >/dev/null 2>&1; api unbind >/dev/null 2>&1
fake_claude off
g osascript -e 'tell application "System Events" to set picture of every desktop to "/System/Library/CoreServices/DefaultDesktop.heic"' >/dev/null
gsh 'kill $(cat /tmp/fakecursor.pid) 2>/dev/null; /opt/homebrew/bin/tmux kill-session -t site 2>/dev/null; pkill -f "http.server 8000"; pkill -f film/agent.py; sudo pkill -x login; sleep 1
     osascript -e "tell application \"Terminal\" to set font size of settings set \"Pro\" to 10" -e "tell application \"Terminal\" to close every window" -e "tell application \"Safari\" to quit" >/dev/null 2>&1
     osascript -e "tell application \"Terminal\" to quit" >/dev/null 2>&1
     defaults delete com.apple.finder CreateDesktop; defaults delete com.apple.dock autohide; defaults delete com.apple.dock autohide-delay
     defaults delete com.apple.menuextra.clock IsAnalog 2>/dev/null; killall ControlCenter; ~/film/dispmode 1024 768 1; rm -rf ~/film; true'
vm_down
tart set $VM --display 1024x768
tart list | grep $VM
