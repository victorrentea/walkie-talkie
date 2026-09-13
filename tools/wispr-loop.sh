#!/bin/bash
# Drive ONE real Wispr Flow dictation end to end, unattended, and assert what the
# relay did with it.
#
#   tools/wispr-loop.sh caret-short             # incident 1 — expected red today
#   tools/wispr-loop.sh caret-long --verbose
#   tools/wispr-loop.sh bound --wav /path/to.wav --transcript 'what it says'
#   tools/wispr-loop.sh --all --json
#   tools/wispr-loop.sh caret-short --dry-run   # print the steps, post nothing
#
# The difference from `wispr-test.sh`, which this is built beside: that one asks
# *did a transcript come back*. This one asks *did the words go where the gesture
# said, and did the ring come down when Wispr had finished* — the two questions
# the incidents of 2026-09-13 turned on, neither of which a transcript answers.
#
# The channel, end to end:
#
#   WAV ──play──▶ Loopback device ──mic──▶ Wispr Flow ──⌘V / AX insert──┐
#                      ▲                                               │
#        system default input                           Walkie Talkie ◀─┘
#      (POST /test/input, restored)                             │
#                                              sink window · bound tty · spawn
#
# Wispr must be on **Auto-detect**, because that is the setting that makes it
# follow the system default input, which is the only part of its microphone this
# script can move. Wispr's own `overrideAudioDeviceId` is a salted Chromium hash
# in a file Wispr rewrites, and **nothing here ever edits it** — the preflight
# prints the instruction and stops.
#
# Nothing here synthesises a keystroke either. Every gesture is `POST
# /test/gesture`, which makes the **app** post the real ⌃⌥⌘F-key chord; the app
# has the Accessibility grant, this script has none and needs none.
#
# There is no `--speaker`. Playing the clip out loud is `wispr-test.sh`'s way
# round a pinned microphone and it makes a noise in Victor's room; a harness that
# is meant to run unattended must not.
#
# Exit: 0 every assertion passed · 1 an assertion failed · 2 a precondition
# failed · 3 the relay's build has not got the routes yet.

set -uo pipefail

# The preflight, the system input and the 🔒 locks are shared with
# `wispr-transcribe.sh` — one implementation of the restore trap, not two.
# shellcheck source=tools/wispr-act.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/wispr-act.sh"

REPO="$WISPR_ACT_REPO"
PY="$WISPR_ACT_PY"
SCRATCH="${TMPDIR:-/tmp}/wispr-loop"

# The routes every scenario rests on. A build without them is not a failure to
# report as red — it is a build from before the harness, and the run should wait
# or say so rather than invent another way in.
ROUTES="/test/state,/test/sink,/test/gesture"

DEVICE=""
DRY_RUN=0
# The system default input is left alone unless the device is a pre-2026-09-13
# fallback Wispr is not pinned to.
FORCE_SWITCH=0
WAIT_ROUTES=0
PASSTHROUGH=()
# A string and not an array: /bin/bash on macOS is 3.2, where `${arr[*]}` on an
# empty array is an unbound-variable error under `set -u`.
SCENARIO_LABEL=""

say() { wispr_act_say "$@"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --device)      DEVICE="$2"; PASSTHROUGH+=(--device "$2"); shift 2 ;;
    --wav)         PASSTHROUGH+=(--wav "$2"); shift 2 ;;
    --transcript)  PASSTHROUGH+=(--transcript "$2"); shift 2 ;;
    --json|--verbose|--all|--list) PASSTHROUGH+=("$1"); shift ;;
    --repeat)      PASSTHROUGH+=(--repeat "$2"); shift 2 ;;
    --dismiss-delay) PASSTHROUGH+=(--dismiss-delay "$2"); shift 2 ;;
    --no-dismiss)  PASSTHROUGH+=(--no-dismiss); shift ;;
    --leave-unbound) PASSTHROUGH+=(--leave-unbound); shift ;;
    # **One token with `=`**, not two: the offsets may start with a minus (a
    # letter typed *during* the recording) and argparse reads a bare `-3,-1,…`
    # as a flag it has never heard of.
    # Both spellings. The value may start with a minus (a letter typed *during*
    # the recording), so it always reaches Python as one `=` token — argparse
    # reads a bare `-3,-1,…` as a flag it has never heard of.
    --probe-offsets)   PASSTHROUGH+=("--probe-offsets=$2"); shift 2 ;;
    --probe-offsets=*) PASSTHROUGH+=("$1"); shift ;;
    --dry-run)     DRY_RUN=1; PASSTHROUGH+=(--dry-run); shift ;;
    --switch-input) FORCE_SWITCH=1; shift ;;
    # For the hour between "the routes are being written" and "the routes are
    # there": poll instead of failing, so this can be started and left.
    --wait-routes) WAIT_ROUTES="${2:-600}"; shift 2 ;;
    --speaker)
      say "✗ there is no --speaker here. It plays Victor's own voice out loud on his"
      say "  machine, which an unattended harness must never do. Use tools/wispr-test.sh"
      say "  if the microphone cannot be put on Auto-detect."
      exit 2 ;;
    -h|--help)     sed -n '2,39p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)            say "unknown flag: $1"; exit 2 ;;
    *)             SCENARIO_LABEL="${SCENARIO_LABEL:+$SCENARIO_LABEL }$1"; PASSTHROUGH+=("$1"); shift ;;
  esac
done

mkdir -p "$SCRATCH"
PASSTHROUGH+=(--scratch "$SCRATCH")

# ── The scenarios, listed without touching anything ─────────────────────────
case " ${PASSTHROUGH[*]} " in
  *" --list "*) exec "$PY" "$REPO/helpers/wispr_loop.py" --list ;;
esac

# ── Preflight — every precondition named, none of them silent ───────────────
[ "$WAIT_ROUTES" != 0 ] && wispr_act_wait_routes "$ROUTES" "$WAIT_ROUTES"

PREFLIGHT_ARGS=()
[ -n "$DEVICE" ] && PREFLIGHT_ARGS+=(--device "$DEVICE")
# A dry run posts nothing, so nothing can be harmed by a setting being wrong: it
# still prints every row — the point of running it today is to see what is not
# ready yet — but it does not refuse to go on.
[ "$DRY_RUN" = 1 ] && PREFLIGHT_ARGS+=(--no-idle-check --advisory)
wispr_act_preflight "$ROUTES" "${PREFLIGHT_ARGS[@]+"${PREFLIGHT_ARGS[@]}"}"

if [ "$DRY_RUN" = 1 ]; then
  say ""
  say "── dry run — nothing below is posted ──────────────────────"
  exec "$PY" "$REPO/helpers/wispr_loop.py" "${PASSTHROUGH[@]}"
fi

if wispr_act_needs_switch "$DEVICE" "$FORCE_SWITCH"; then
  wispr_act_switch_input "$DEVICE"
else
  say "🎚️ Wispr is pinned to the device — the system default input is left alone"
  trap wispr_act_stand_down EXIT INT TERM
fi

say ""
wispr_act_run "wispr-loop ${SCENARIO_LABEL:-all}" -- \
  "$PY" "$REPO/helpers/wispr_loop.py" "${PASSTHROUGH[@]}"
STATUS=$?

wispr_act_restore_input
exit $STATUS
