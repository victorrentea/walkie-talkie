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
# if it was running — **with the binding it had**, and never over a dictation
# in flight. See relay-restart.sh for Victor's rule and why standing the app
# down mid-sentence is worse than waiting.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=../relay-restart.sh
. ./relay-restart.sh

was_running=0
pgrep -f "/Applications/Walkie Talkie.app" >/dev/null 2>&1 && was_running=1
# Both read before anything stands the app down: the file is cleared at launch.
relay_wait_idle
bound_tty="$(relay_bound_tty)"

swift build
rm -rf docs/states
RELAY_SHOOT="$PWD/docs/states" ./.build/debug/WalkieTalkie
python3 docs/build-overlay-states.py

if [ "$was_running" = 1 ]; then
  open "/Applications/Walkie Talkie.app"
  echo "→ installed app restarted"
  relay_rebind "$bound_tty"
fi
