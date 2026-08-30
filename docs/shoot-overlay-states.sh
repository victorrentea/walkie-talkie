#!/usr/bin/env bash
#
# Photograph every state of the overlay and rebuild docs/overlay-states.html.
#
# Run this after any change to the overlay — that is the rule, and it is written
# on the page itself. The states, their order and their prose live in
# Sources/WalkieTalkie/OverlayStates.swift; this only drives them.
#
# `RELAY_SHOOT` makes the app walk the catalogue and quit. Starting it also
# stands the installed copy down (SingleInstance), so it is put back at the end
# if it was running.
set -euo pipefail
cd "$(dirname "$0")/.."

was_running=0
pgrep -f "/Applications/Walkie Talkie.app" >/dev/null 2>&1 && was_running=1

swift build
rm -rf docs/states
RELAY_SHOOT="$PWD/docs/states" ./.build/debug/WalkieTalkie
python3 docs/build-overlay-states.py

if [ "$was_running" = 1 ]; then
  open "/Applications/Walkie Talkie.app"
  echo "→ installed app restarted"
fi
