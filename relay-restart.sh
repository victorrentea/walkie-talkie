#!/usr/bin/env bash
#
# **Restart the installed app without losing what it was pointed at.**
#
# Victor's rule, 2026-09-09, in two halves:
#
#   *"Niciodată să nu mai dai restart la Walkie Talkie … în dictare. Oprești și
#   aștepți să se termine dictarea, să se livreze, abia apoi faci restart."*
#   *"Legat dar nu în dictare poți să-l restartezi totuși — ideal ar fi să-l
#   re-legi la același terminal automat."*
#
# So: a dictation in flight is a **stop**, and a binding is a thing to put back.
# A restart mid-sentence throws away audio he has already spoken, and it is
# invisible from inside the very session that ordered the restart — which is the
# session this app types into.
#
# Both facts are read from `~/.walkie-talkie/bound-tty`, which the app publishes
# for the status line: absent when nothing is bound, `ttysNNN` when it is, and
# `ttysNNN listening` while the microphone is open. It is one `cat` rather than
# an HTTP round trip, and it is written from the two switches that own those
# facts, so it cannot disagree with the chip.
#
# Sourced by docs/shoot-overlay-states.sh; run directly to restart by hand.
set -euo pipefail

RELAY_BOUND_FILE="${WALKIE_HOME:-$HOME/.walkie-talkie}/bound-tty"

# Block while a dictation is running. Not a timeout to be got past: a sentence
# ends when Victor ends it, and the decode plus the held panel is a handful of
# seconds after that.
relay_wait_idle() {
  local waited=0
  while grep -q listening "$RELAY_BOUND_FILE" 2>/dev/null; do
    [ "$waited" = 0 ] && echo "⏳ a dictation is running — waiting for it to be delivered…"
    sleep 1
    waited=$((waited + 1))
  done
  # The line goes non-`listening` when the microphone closes, which is a few
  # seconds before the transcript has been delivered. Let the decode and the
  # held panel finish rather than pulling the app out from under them.
  [ "$waited" = 0 ] || sleep 6
}

# The tty it was pointed at, or nothing. Read *before* standing the app down —
# the file is cleared at launch and at quit.
relay_bound_tty() {
  [ -f "$RELAY_BOUND_FILE" ] || return 0
  cut -d' ' -f1 "$RELAY_BOUND_FILE"
}

# Put the binding back on the app that has just come up. The frontmost window is
# whatever the build was watched in, which is exactly not the session that was
# bound, so this addresses it by tty. The relay takes a few seconds to open its
# port; a bind that never lands is reported and nothing else — the app is
# running either way.
relay_rebind() {
  local tty="${1:-}" port
  [ -n "$tty" ] || return 0
  for _ in $(seq 1 20); do
    for port in 8917 8918 8919; do
      if curl -fsS -m 1 -X POST "127.0.0.1:$port/bind" -d "{\"tty\":\"$tty\"}" >/dev/null 2>&1; then
        echo "→ re-bound to $tty"
        return 0
      fi
    done
    sleep 0.5
  done
  echo "⚠️ could not re-bind to $tty — bind it by hand (◀️ + 🔼)"
}

relay_restart() {
  relay_wait_idle
  local tty; tty="$(relay_bound_tty)"
  pkill -f "/Applications/Walkie Talkie.app" 2>/dev/null || true
  sleep 0.5
  open "/Applications/Walkie Talkie.app"
  relay_rebind "$tty"
}

# Sourced for the functions, run for the restart.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then relay_restart; fi
