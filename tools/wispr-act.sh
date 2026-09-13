#!/bin/bash
# The three things every script that dictates into Wispr has to get right, in
# one place: **the preflight, the system input, and the 🔒 locks.**
#
# Sourced, never run:
#
#   . "$(dirname "${BASH_SOURCE[0]}")/wispr-act.sh"
#   wispr_act_preflight "/test/state,/test/sink"     # exits 2 or 3 itself
#   wispr_act_switch_input                           # installs the restore trap
#   wispr_act_run "what I am doing" -- some-command…
#
# Why a library and not a copy in each script: the restore is a `trap` in the
# **caller's** shell, and it is the one thing here that must survive the process
# being killed. Leaving Victor's Mac recording from a Loopback device makes his
# next real dictation silence with nothing on screen to say why — so there is
# one implementation of it and both scripts get the same one.

# shellcheck shell=bash

WISPR_ACT_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WISPR_ACT_PY="${WISPR_LOOP_PYTHON:-/Library/Frameworks/Python.framework/Versions/3.12/bin/python3}"
WISPR_ACT_RESTORE=""
WISPR_ACT_DEVICE=""

wispr_act_say() { printf '%s\n' "$*"; }

# ── Preflight ───────────────────────────────────────────────────────────────
# Exits **2** for a Mac that is set up wrong and **3** for a relay build that is
# simply older than the harness. They are different answers: one is fixed, the
# other is waited out, and a caller that cannot tell them apart tells Victor to
# change a setting that is already right.
#
#   wispr_act_preflight <routes-csv> [extra preflight flags…]
wispr_act_preflight() {
  local routes="$1"; shift
  wispr_act_say "── preflight ──────────────────────────────────────────────"
  "$WISPR_ACT_PY" "$WISPR_ACT_REPO/helpers/wispr_preflight.py" --require-routes "$routes" "$@" && return 0
  if ! "$WISPR_ACT_PY" "$WISPR_ACT_REPO/helpers/wispr_preflight.py" --routes-only \
         --require-routes "$routes" --json 2>/dev/null | /usr/bin/grep -q '"ok": *true'; then
    wispr_act_say ""
    wispr_act_say "the relay's build has not got the loopback routes yet — rerun with --wait-routes 600"
    exit 3
  fi
  wispr_act_say ""
  wispr_act_say "✗ preflight failed — fix the ✗ rows above and run again"
  exit 2
}

# Poll until the routes appear, for the hour between "they are being written"
# and "they are there".  wispr_act_wait_routes <routes-csv> <seconds>
wispr_act_wait_routes() {
  local routes="$1" secs="$2" deadline=$((SECONDS + $2))
  wispr_act_say "⏳ waiting up to ${secs}s for $routes"
  until "$WISPR_ACT_PY" "$WISPR_ACT_REPO/helpers/wispr_preflight.py" --routes-only \
        --require-routes "$routes" --json 2>/dev/null | /usr/bin/grep -q '"ok": *true'; do
    [ $SECONDS -lt $deadline ] || { wispr_act_say "✗ the routes never arrived"; exit 3; }
    sleep 5
  done
  wispr_act_say "✓ the routes are there"
}

# ── The system default input ────────────────────────────────────────────────
_wispr_act_post_input() {
  "$WISPR_ACT_PY" - "$1" <<'EOF'
import json, sys, urllib.request
body = json.dumps({"name": sys.argv[1]}).encode()
for port in (8917, 8918, 8919):
    try:
        req = urllib.request.Request("http://127.0.0.1:%d/test/input" % port, data=body,
                                     headers={"content-type": "application/json"}, method="POST")
        print(urllib.request.urlopen(req, timeout=10).read().decode()); break
    except Exception:
        continue
EOF
}

# **Never leave a microphone open.** The chord is a toggle and every path between
# its two halves — Ctrl-C, a kill, a crash in the playback — leaves Wispr
# recording. Measured 2026-09-13: a 495-second row with an empty `app`, which is
# this rig's own chord left open, not anybody dictating. `POST /test/cancel` is
# the ✕ and is idempotent; a second *chord* would start one Wispr had missed.
# Gated on the state, and only reached when the Python did not clean up after
# itself: an ungated cancel in the trap fired **four** ⌃Escapes into Wispr on
# 2026-09-13 19:47, on top of the one the runner had already posted, and the
# extra ones land on whatever dictation exists next.
wispr_act_stand_down() {
  curl -s -m 3 "http://127.0.0.1:8917/test/state" 2>/dev/null \
    | /usr/bin/grep -qE '"(isRecording|listening)": *true' || return 0
  curl -s -m 5 -X POST "http://127.0.0.1:8917/test/cancel" \
       -H 'content-type: application/json' -d '{}' >/dev/null 2>&1 || true
}

# **And check that it took.** The device the run displaced can be gone by the
# time the run ends — measured 2026-09-13: it was a Bluetooth headset, `Vic
# Bose`, which disconnected mid-run; the restore was posted, went nowhere, and
# left Victor's Mac recording from a Loopback device with nothing on screen to
# say so. That is the single worst thing this script can leave behind, so it
# verifies and falls back to the built-in microphone.
WISPR_ACT_FALLBACK_INPUT="MacBook Pro Microphone"

wispr_act_restore_input() {
  wispr_act_stand_down
  [ -n "$WISPR_ACT_RESTORE" ] || return 0
  local name="$WISPR_ACT_RESTORE" now; WISPR_ACT_RESTORE=""
  _wispr_act_post_input "$name" >/dev/null 2>&1
  now=$(_wispr_act_post_input "" 2>/dev/null | sed -n 's/.*"input": *"\([^"]*\)".*/\1/p')
  if [ -n "$now" ] && [ "$now" != "$name" ]; then
    wispr_act_say "↩︎ '$name' is gone (now '$now') — falling back to $WISPR_ACT_FALLBACK_INPUT"
    _wispr_act_post_input "$WISPR_ACT_FALLBACK_INPUT" >/dev/null 2>&1
    now=$(_wispr_act_post_input "" 2>/dev/null | sed -n 's/.*"input": *"\([^"]*\)".*/\1/p')
  fi
  wispr_act_say "↩︎ system input is ${now:-$name}"
}

# **Is the system default input any of our business?**
#
# Since 2026-09-13 it normally is not. `🎓 TO Wispr` is a Loopback device whose
# sources are the physical MacBook Pro Microphone *and* Pass-Thru, and **Wispr's
# microphone is pinned to it**: Victor's own dictation goes mic → device → Wispr
# unchanged, and the rig plays WAVs into the same device. Nothing has to be
# steered, so nothing is — the switch existed only to point *Auto-detect* at a
# device, and Auto-detect turned out to mean the built-in microphone anyway.
#
# The old devices are kept as a fallback and need `--switch-input`, because Wispr
# is not pinned to them.
#   wispr_act_needs_switch <device-substring> <forced 0|1>
wispr_act_needs_switch() {
  [ "${2:-0}" = 1 ] && return 0
  "$WISPR_ACT_PY" - "$WISPR_ACT_REPO" "${1:-}" <<'EOF'
import sys
sys.path.insert(0, sys.argv[1] + "/helpers")
import wispr_loopback as wl
sys.exit(0 if not wl.is_pinned_device(wl.resolve_device(sys.argv[2] or None)[1]) else 1)
EOF
}

# Point the system's default input at the Loopback device and arrange for it to
# be put back on EXIT, INT and TERM — every path, including a kill.
#   wispr_act_switch_input [device-substring]
wispr_act_switch_input() {
  trap wispr_act_restore_input EXIT INT TERM
  WISPR_ACT_DEVICE=$("$WISPR_ACT_PY" "$WISPR_ACT_REPO/helpers/wispr_preflight.py" \
                     --print device ${1:+--device "$1"}) \
    || { wispr_act_say "✗ no virtual output device"; exit 2; }
  local answer
  answer=$(_wispr_act_post_input "$WISPR_ACT_DEVICE")
  case "$answer" in
    *'"changed":true'*|*'"changed": true'*) : ;;
    *) wispr_act_say "✗ the relay could not make '$WISPR_ACT_DEVICE' the system input: $answer"; exit 2 ;;
  esac
  WISPR_ACT_RESTORE=$(printf '%s' "$answer" | sed -n 's/.*"was": *"\([^"]*\)".*/\1/p')
  wispr_act_say "🎚️ system input → $WISPR_ACT_DEVICE (was ${WISPR_ACT_RESTORE:-unknown})"
}

# ── The locks ───────────────────────────────────────────────────────────────
# Mandatory, not a nicety. The act posts real keystroke chords, opens and closes
# windows and steals focus; **locks on screen are the only way Victor learns the
# machine is busy**, because he is not reading this terminal. `hands-off run`
# releases on exit, on Ctrl-C and on a crash.
#   wispr_act_run "what I am doing" -- command…
wispr_act_run() {
  local what="$1"; shift
  [ "${1:-}" = "--" ] && shift
  "$HOME/bin/hands-off" run "$what" -- "$@"
}
