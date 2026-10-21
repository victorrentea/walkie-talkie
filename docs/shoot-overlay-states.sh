#!/usr/bin/env bash
#
# Photograph every state of the overlay and rebuild docs/overlay-states.html.
#
# Run this after any change to the overlay — that is the rule, and it is written
# on the page itself. The states, their order and their prose live in
# Sources/WalkieTalkie/OverlayStates.swift; this only drives them.
#
# `RELAY_SHOOT` makes the app walk the catalogue and quit. It runs **beside** the
# installed copy and leaves it alone (2026-10-21): no event tap, no outbox line,
# no binding marker, no "From Walkie" switch (all guarded on `RelayWindow.shooting`).
# `SingleInstance` never stood the installed app down — the debug binary has no
# bundle id and another path — so the old "put it back" step (`open -g` on the
# running app) was a reopen event, i.e. a Dock-tile restart of an app nobody had
# stopped, ~1 s after every shoot; and the shooter's tap, at the head of the chain,
# took his gestures for the whole run (17:07, *"I was pressing the dictation and
# had to restart"*).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build
rm -rf docs/states
RELAY_SHOOT="$PWD/docs/states" ./.build/debug/WalkieTalkie
python3 docs/build-overlay-states.py
python3 docs/build-readme-shots.py
