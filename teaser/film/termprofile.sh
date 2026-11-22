#!/bin/bash
# GUEST: give the Terminal's "Pro" profile a plain window title (no process name, arguments, size). Terminal must be quit.
P=~/Library/Preferences/com.apple.Terminal.plist
while pgrep -x Terminal >/dev/null; do sleep 0.5; done
for k in ShowActiveProcessArgumentsInTitle ShowActiveProcessInTitle ShowWindowSettingsNameInTitle ShowDimensionsInTitle ShowRepresentedURLInTitle ShowRepresentedURLPathInTitle ShowTTYNameInTitle ShowShellCommandInTitle ShowCommandKeyInTitle; do
  /usr/libexec/PlistBuddy -c "Delete :Window\ Settings:Pro:$k" $P 2>/dev/null; /usr/libexec/PlistBuddy -c "Add :Window\ Settings:Pro:$k bool false" $P
done
/usr/libexec/PlistBuddy -c "Delete :Window\ Settings:Pro:WindowTitle" $P 2>/dev/null; /usr/libexec/PlistBuddy -c "Add :Window\ Settings:Pro:WindowTitle string brewly" $P
killall cfprefsd; sleep 1
defaults read com.apple.Terminal "Window Settings" | grep -c "InTitle = 0"
