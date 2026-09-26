#!/usr/bin/env bash
#
# **The one way to restart the installed app.** `safe-restart.sh` is an alias.
#
#   ./relay-restart.sh [--build] [--dry-run] [--max-wait SECONDS] [--quiet SECONDS]
#
#   --build      run ./build-app.sh first — ungated, a build may happen while he
#                dictates; only the quit and relaunch wait
#   --dry-run    wait for the gate and say it would restart; touch nothing
#   --max-wait   give up after this long (default 1800 s = 30 min), exit 3
#   --quiet      seconds of quiet required after the last delivery (default 10)
#
# Exit: 0 restarted (or gate open on --dry-run), 1 build failed, 3 gave up waiting.
#
# Victor's rule, in three dated halves:
#
#   2026-09-09: *"Niciodată să nu mai dai restart la Walkie Talkie … în dictare.
#   Oprești și aștepți să se termine dictarea, să se livreze, abia apoi faci
#   restart."* *"Legat dar nu în dictare poți să-l restartezi totuși — ideal ar fi
#   să-l re-legi la același terminal automat."*
#
#   2026-09-23: *"Whenever you restart it, make sure it's not currently dictating
#   or transcribing. Make sure it's idle before you restart the app … After the
#   clean insert of the text [and submit], only then restart. Maybe, granted, even
#   10 more seconds in case I routed the prompt to the wrong place, and then only
#   then restart."*
#
# So, in order:
#
# 1. **Wait for the gate** — `tools/restart_gate.py wait`: `GET /test/state.busy`
#    false (the app's own `restartBlockers`: every engine's microphone, the
#    recogniser, a Wispr sentence behind the firewall, the prompt on screen, a
#    sentence held for a bind, the words being typed, a spawn until its window is bound), then ten quiet seconds after
#    the last delivery, the countdown starting over on anything new. Polled every
#    second; unit-tested by `evals/test_restart_gate.py`.
# 2. **Read the binding** from `~/.walkie-talkie/bound-tty` — before the SIGTERM
#    as a fallback, and again **once the process is gone** (2026-09-26, TD12): an
#    app being replaced leaves the binding it had *at quit* there, so a bind made
#    while the quit was deferred is the one put back. Cleared at launch. For tmux
#    the line is `ttysNNN %N` and the pane travels too (TD13).
# 3. **Quit gracefully: SIGTERM**, which since 2026-09-23 the app routes through
#    `applicationShouldTerminate` — and if a sentence started in the second
#    between the gate and the signal, the app refuses the quit and goes when the
#    words have landed (`quitPending`), and this waits for it. `.replacing` is
#    kept fresh meanwhile so no `session_end` reaches the watching agent. SIGKILL
#    only if the app neither exits nor says it is finishing a sentence within 15 s.
# 4. **Relaunch through LaunchServices**: `open -g "/Applications/Walkie Talkie.app"`.
#    Never the executable path (TCC files a path launch as a second app), and `-g`
#    so the relay he gets back is not in front of the terminal he is typing in.
# 5. **Re-bind** the same tty with `POST /bind {"tty", "pane"}` — no toggle, no
#    flight, and not a deliberate bind (it never takes a sentence's caret or spawn).
#
# Sourced by docs/shoot-overlay-states.sh for `relay_wait_idle`, `relay_bound_tty`
# and `relay_rebind`; run directly to restart.
set -euo pipefail

RELAY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELAY_HOME="${WALKIE_HOME:-$HOME/.walkie-talkie}"
RELAY_BOUND_FILE="$RELAY_HOME/bound-tty"
RELAY_APP="/Applications/Walkie Talkie.app"
RELAY_EXEC="$RELAY_APP/Contents/MacOS/Walkie Talkie"

relay_pid() { pgrep -f "$RELAY_EXEC" 2>/dev/null | head -1; }

# Block until the gate is open (see above). Exit status 3 when --max-wait ran out.
relay_wait_idle() {
  python3 "$RELAY_DIR/tools/restart_gate.py" wait --quiet "${RELAY_QUIET:-10}" \
    --max-wait "${RELAY_MAX_WAIT:-1800}"
}

# The tty it was pointed at, or nothing. Read *before* standing the app down —
# the file is cleared at launch and at quit. `ttysNNN listening` → `ttysNNN`.
relay_bound_tty() {
  [ -f "$RELAY_BOUND_FILE" ] || return 0
  awk '{print $1; exit}' "$RELAY_BOUND_FILE"
}

# The tmux pane beside it (`ttys006 %1` → `%1`), or nothing.
relay_bound_pane() {
  [ -f "$RELAY_BOUND_FILE" ] || return 0
  awk '$2 ~ /^%/ {print $2} {exit}' "$RELAY_BOUND_FILE"
}

# Put the binding back on the app that has just come up, addressed by tty.
#
# **Ten seconds per attempt, not one** (2026-09-09). A bind is one to two
# `osascript` round trips and the route answers only when it has finished, so
# `-m 1` timed out on a bind that had *succeeded* — and the loop bound again and
# again: seven re-binds over 70 seconds after one restart, one stealing a binding
# Victor had made by hand, another redirecting a caret dictation. The retry is for
# a port that is not open yet, which fails in milliseconds.
relay_rebind() {
  local tty="${1:-}" pane="${2:-}" port
  [ -n "$tty" ] || return 0
  for _ in $(seq 1 20); do
    for port in 8917 8918 8919; do
      if curl -fsS -m 10 -X POST "127.0.0.1:$port/bind" \
           -d "{\"tty\":\"$tty\",\"pane\":\"$pane\"}" >/dev/null 2>&1; then
        echo "→ re-bound to $tty${pane:+ $pane}"
        return 0
      fi
    done
    sleep 0.5
  done
  echo "⚠️ could not re-bind to $tty — bind it by hand (◀️ + 🔼)"
}

# Is the app refusing a quit while it finishes a sentence? (new builds only)
relay_quit_pending() {
  local port
  for port in 8917 8918 8919; do
    curl -s -m 2 "http://127.0.0.1:$port/test/state" 2>/dev/null | python3 -c '
import json, sys
try: sys.exit(0 if json.load(sys.stdin).get("quitPending") else 1)
except Exception: sys.exit(1)' && return 0
  done
  return 1
}

# SIGTERM, then wait for the process to go — for as long as it says it is
# finishing a sentence, up to the max wait; SIGKILL only for an app that neither
# exits nor answers that it is deferring.
relay_quit() {
  local pid="$1" start now said=0 undeferred_since
  start=$(date +%s); undeferred_since=$start
  touch "$RELAY_HOME/.replacing"
  kill -TERM "$pid" 2>/dev/null || return 0
  while kill -0 "$pid" 2>/dev/null; do
    now=$(date +%s)
    touch "$RELAY_HOME/.replacing"
    if relay_quit_pending; then
      undeferred_since=$now
      [ "$said" = 1 ] || { echo "⏳ a sentence started meanwhile — the app quits once it has landed"; said=1; }
      if [ $((now - start)) -ge "${RELAY_MAX_WAIT:-1800}" ]; then
        echo "⛔️ still finishing a sentence after ${RELAY_MAX_WAIT:-1800} s — left running"; return 3
      fi
    elif [ $((now - undeferred_since)) -ge 15 ]; then
      echo "⚠️ pid $pid ignored the quit for 15 s — force-killing it"
      pkill -KILL -f "$RELAY_EXEC" 2>/dev/null || true
      sleep 0.5
      break
    fi
    sleep 0.5
  done
}

relay_launch() {
  open -g "$RELAY_APP"
  local waited=0
  while [ "$waited" -lt 60 ]; do
    if python3 "$RELAY_DIR/tools/restart_gate.py" once 2>/dev/null | grep -q '"answered": true'; then
      echo "→ relaunched (pid $(relay_pid))"
      return 0
    fi
    sleep 0.5; waited=$((waited + 1))
  done
  echo "⚠️ relaunched, but it has not answered on 8917–8919 after 30 s"
}

relay_restart() {
  local build=0 dry=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --build) build=1 ;;
      --dry-run) dry=1 ;;
      --max-wait) RELAY_MAX_WAIT="$2"; shift ;;
      --quiet) RELAY_QUIET="$2"; shift ;;
      -h|--help) sed -n '2,13p' "$RELAY_DIR/relay-restart.sh"; return 0 ;;
      *) echo "unknown argument: $1" >&2; return 2 ;;
    esac
    shift
  done

  if [ "$build" = 1 ]; then
    echo "🔨 building (ungated — the running app is not touched)…"
    (cd "$RELAY_DIR" && ./build-app.sh) || { echo "⛔️ build failed — nothing restarted"; return 1; }
  fi

  local pid; pid="$(relay_pid)"
  if [ -z "$pid" ]; then
    if [ "$dry" = 1 ]; then echo "🧪 dry run: the app is not running — would launch it"; return 0; fi
    echo "the app is not running — launching it"
    relay_launch
    return 0
  fi

  echo "🔍 waiting until Walkie Talkie (pid $pid) is idle and quiet for ${RELAY_QUIET:-10} s…"
  relay_wait_idle || return $?

  local tty pane; tty="$(relay_bound_tty)"; pane="$(relay_bound_pane)"
  if [ "$dry" = 1 ]; then
    echo "🧪 dry run: the gate is open — would quit pid $pid, relaunch, and re-bind ${tty:-nothing}"
    return 0
  fi
  if [ -n "$tty" ]; then echo "↻ restarting — the binding to $tty travels with it"
  else echo "↻ restarting — nothing bound to put back"; fi
  relay_quit "$pid" || return $?
  # The binding at quit time, when the app left one (TD12) — a bind made while
  # the quit waited for a sentence wins over the one read before the SIGTERM.
  local at_quit at_pane; at_quit="$(relay_bound_tty)"; at_pane="$(relay_bound_pane)"
  if [ -n "$at_quit" ]; then
    if [ "$at_quit $at_pane" != "$tty $pane" ]; then
      echo "↻ the binding changed while the quit waited — putting back $at_quit${at_pane:+ $at_pane} instead"
    fi
    tty="$at_quit"; pane="$at_pane"
  fi
  relay_launch
  relay_rebind "$tty" "$pane"
}

# Sourced for the functions, run for the restart.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then relay_restart "$@"; fi
