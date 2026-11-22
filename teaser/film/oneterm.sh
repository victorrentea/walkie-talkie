#!/bin/bash
# GUEST: keep only the front Terminal window — end the other windows' shells first, so no "terminate?" sheet comes up.
for t in $(osascript -e 'tell application "Terminal" to get tty of selected tab of (every window whose index > 1)' | tr -d ','); do
  sudo pkill -t "${t#/dev/}"
done
sleep 0.7
osascript -e 'tell application "Terminal" to close (every window whose index > 1)'
osascript -e 'tell application "Terminal" to count windows'
