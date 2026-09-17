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
# The binding is read from `~/.walkie-talkie/bound-tty`, which the app publishes
# for the status line: absent when nothing is bound, `ttysNNN` when it is. It is
# one `cat` rather than an HTTP round trip, and it is written from the one switch
# that owns it, so it cannot disagree with the chip. Whether a sentence is in
# flight is a different question and is asked of the relay itself.
#
# Sourced by docs/shoot-overlay-states.sh; run directly to restart by hand.
set -euo pipefail

RELAY_BOUND_FILE="${WALKIE_HOME:-$HOME/.walkie-talkie}/bound-tty"

# Does the **source** have a sentence in flight? Asked of the running relay, not
# of the file. Answers false (idle) only on a clear no; an unreachable relay is
# not an idle one, so a port that does not answer keeps the caller waiting.
#
# **`done` is as idle as `idle` is** — `DictationPhase` sits at `done(<status>)`
# from the moment a sentence lands until the next chord, so a predicate that
# wants `phase == "idle"` is false for ever after the first dictation of the
# session. Only `warming`, `listening` and `transcribing` are a sentence.
relay_source_is_idle() {
  local port state
  for port in 8917 8918 8919; do
    state=$(curl -s -m 2 "http://127.0.0.1:$port/test/state" 2>/dev/null) || continue
    [ -n "$state" ] || continue
    printf '%s' "$state" | /usr/bin/python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(1)
idle = (not d.get("isRecording") and not d.get("settling")
        and not d.get("speculative") and d.get("phase") in ("idle", "done"))
sys.exit(0 if idle else 1)'
    return $?
  done
  return 1
}

# **Is a sentence in flight right now?** Asked of the relay, which is the only
# thing that knows. A **positive** answer only — an unreachable relay is not a
# busy one here, because a restart of an app that is not answering has no
# sentence to protect and the caller would otherwise wait for ever. `done` is a
# finished sentence and is not one of the phases that count — see above.
relay_is_dictating() {
  local port state
  for port in 8917 8918 8919; do
    state=$(curl -s -m 2 "http://127.0.0.1:$port/test/state" 2>/dev/null) || continue
    [ -n "$state" ] || continue
    printf '%s' "$state" | /usr/bin/python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(1)
busy = (d.get("listening") or d.get("isRecording") or d.get("settling")
        or d.get("speculative")
        or d.get("phase") in ("warming", "listening", "transcribing"))
sys.exit(0 if busy else 1)'
    return $?
  done
  return 1
}

# Block while a dictation is running. Not a timeout to be got past: a sentence
# ends when Victor ends it, and the decode plus the held panel is a handful of
# seconds after that.
#
# **A stuck flag is not a sentence, and telling them apart is a reading rather
# than a timeout** (2026-09-14). The relay says `listening` for as long as it
# believes a dictation is open — and it can believe that with no microphone
# behind it at all: `/test/dictation/start` opens exactly such a dictation, and so
# does a recogniser that dies between the chord and the words. This script then
# waited for a sentence nobody was speaking, for ever, which is how it was found.
# So the flag is the fast check and the **source** is the arbiter: one that is not
# recording, not settling and `idle` has no sentence in flight, whatever the flag
# says.
relay_wait_idle() {
  local waited=0
  while relay_is_dictating; do
    if [ "$waited" -ge 5 ] && relay_source_is_idle; then
      echo "⚠️  the relay still says listening but its recogniser is idle —"
      echo "    a dictation flag left standing, not a sentence. Going ahead."
      return 0
    fi
    [ "$waited" = 0 ] && echo "⏳ a dictation is running — waiting for it to be delivered…"
    sleep 1
    waited=$((waited + 1))
  done
  # The relay goes idle when the microphone closes, which is a few seconds
  # before the transcript has been delivered. Let the decode and the held panel
  # finish rather than pulling the app out from under them.
  [ "$waited" = 0 ] || sleep 6
}

# The tty it was pointed at, or nothing. Read *before* standing the app down —
# the file is cleared at launch and at quit.
relay_bound_tty() {
  [ -f "$RELAY_BOUND_FILE" ] || return 0
  cat "$RELAY_BOUND_FILE"
}

# Put the binding back on the app that has just come up. The frontmost window is
# whatever the build was watched in, which is exactly not the session that was
# bound, so this addresses it by tty. The relay takes a few seconds to open its
# port; a bind that never lands is reported and nothing else — the app is
# running either way.
#
# **Ten seconds per attempt, not one** (2026-09-09). A bind is one to two
# `osascript` round trips and the route answers only when it has finished, so
# `-m 1` timed out on a bind that had *succeeded* — and the loop, seeing a
# failure, bound again, and again: seven re-binds over 70 seconds after one
# restart, measured. That is not merely noisy. Each one is a deliberate bind, so
# one of them stole a binding Victor had made by hand in the meantime and another
# redirected a caret dictation he had just started (`showBound` takes a paste
# back when a bind lands mid-sentence). The retry is for a port that is not open
# yet, which fails in milliseconds; it must never fire against a bind still
# running.
relay_rebind() {
  local tty="${1:-}" port
  [ -n "$tty" ] || return 0
  for _ in $(seq 1 20); do
    for port in 8917 8918 8919; do
      if curl -fsS -m 10 -X POST "127.0.0.1:$port/bind" -d "{\"tty\":\"$tty\"}" >/dev/null 2>&1; then
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
