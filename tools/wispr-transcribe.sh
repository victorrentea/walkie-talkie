#!/bin/bash
# **Feed Wispr Flow an arbitrary WAV and print what it transcribed.** One file,
# one answer, no scenario and no assertions — the primitive everything else in
# this folder is built on.
#
#   tools/wispr-transcribe.sh clip.wav
#   tools/wispr-transcribe.sh clip.wav --json
#   tools/wispr-transcribe.sh clip.wav --device '🎙️TO Zoom' --verbose
#   tools/wispr-transcribe.sh clip.wav --repeat 5      # the reliability table
#   tools/wispr-transcribe.sh clip.wav --no-sink       # nothing of ours in front
#   tools/wispr-transcribe.sh clip.wav --dry-run
#
# The transcript goes to **stdout** and everything else — the preflight, the
# timings, the diagnosis — to stderr, so `$(tools/wispr-transcribe.sh f.wav)` is
# the sentence and nothing else.
#
#   WAV ──play──▶ Loopback device ──mic──▶ Wispr Flow ──inserts──▶ the relay's
#                       ▲                                          sink window
#            system default input                                      │
#         (switched here, restored on every path)          ◀───────────┘
#                                                       stdout
#
# **The chord is Wispr's own, not a relay gesture.** `POST /test/wispr-handsfree`
# makes the app post `fn ⌃ Space`, so the relay sees a dictation *Victor* began:
# it draws the ring and watches, and routes the words nowhere. A relay gesture
# would start a dictation with a destination and deliver the sentence to a
# terminal — which is the right thing for a scenario and the wrong thing for a
# transcription.
#
# Nothing here synthesises a keystroke. The app holds the Accessibility grant;
# this script holds none and needs none — which is the difference from
# `helpers/wispr_loopback.py`'s older `dictate()`, and the reason the
# teacher-labelling batch should move onto this (see `docs/loopback.md`).
#
# `--no-sink` opens nothing of ours at all. The text still comes from Wispr's
# History row, and the run additionally reports the pasteboard's `changeCount`
# before and after plus the relay's `probe:` lines — the two independent
# witnesses to **where Wispr's output went when nothing of ours was in front**:
# onto the pasteboard and through a ⌘V, or by a route that touches neither. The
# pasteboard is snapshotted with every flavour and put back if anything wrote to
# it. **The relay is bound to Victor's terminal**, so a ⌘V the tap swallows in
# this mode is routed *there* — use it deliberately, never by default.
#
# Exit: 0 a transcript · 1 nothing arrived · 2 a precondition failed · 3 Wispr
# itself said there would be nothing (`dismissed` / `empty` / `no_audio`).

set -uo pipefail

# shellcheck source=tools/wispr-act.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/wispr-act.sh"

ROUTES="/test/state,/test/sink,/test/wispr-handsfree"

WAV=""
DEVICE=""
DRY_RUN=0
# The system default input is left alone unless the device is a pre-2026-09-13
# fallback Wispr is not pinned to.
FORCE_SWITCH=0
WAIT_ROUTES=0
ARGS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --device)      DEVICE="$2"; ARGS+=(--device "$2"); shift 2 ;;
    --json|--verbose|--no-sink) ARGS+=("$1"); shift ;;
    --repeat)      ARGS+=(--repeat "$2"); shift 2 ;;
    --transcript)  ARGS+=(--transcript "$2"); shift 2 ;;
    --dry-run)     DRY_RUN=1; ARGS+=(--dry-run); shift ;;
    --switch-input) FORCE_SWITCH=1; shift ;;
    --wait-routes) WAIT_ROUTES="${2:-600}"; shift 2 ;;
    -h|--help)     sed -n '2,45p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)            wispr_act_say "unknown flag: $1"; exit 2 ;;
    *)             WAV="$1"; shift ;;
  esac
done

[ -n "$WAV" ] || { wispr_act_say "usage: $0 [--json] [--device NAME] <file.wav>"; exit 2; }
[ -f "$WAV" ] || { wispr_act_say "no such WAV: $WAV"; exit 2; }

[ "$WAIT_ROUTES" != 0 ] && wispr_act_wait_routes "$ROUTES" "$WAIT_ROUTES"

PRE=()
[ -n "$DEVICE" ] && PRE+=(--device "$DEVICE")
# A dry run posts nothing, so nothing can be harmed by a setting being wrong —
# it still prints every row, because seeing what is not ready is the point.
[ "$DRY_RUN" = 1 ] && PRE+=(--no-idle-check --advisory)
wispr_act_preflight "$ROUTES" "${PRE[@]+"${PRE[@]}"}" >&2

if [ "$DRY_RUN" = 1 ]; then
  exec "$WISPR_ACT_PY" "$WISPR_ACT_REPO/helpers/wispr_loop.py" --transcribe "$WAV" "${ARGS[@]+"${ARGS[@]}"}"
fi

if wispr_act_needs_switch "$DEVICE" "$FORCE_SWITCH"; then
  wispr_act_switch_input "$DEVICE" >&2
else
  wispr_act_say "🎚️ Wispr is pinned to the device — the system default input is left alone" >&2
  trap wispr_act_stand_down EXIT INT TERM
fi
wispr_act_run "wispr-transcribe $(basename "$WAV")" -- \
  "$WISPR_ACT_PY" "$WISPR_ACT_REPO/helpers/wispr_loop.py" --transcribe "$WAV" "${ARGS[@]+"${ARGS[@]}"}"
STATUS=$?
wispr_act_restore_input >&2
exit $STATUS
