#!/bin/bash
# **Feed Wispr Flow an arbitrary WAV and print what it transcribed.** One file,
# one answer, no scenario and no assertions — the primitive everything else in
# this folder is built on.
#
#   tools/wispr-transcribe.sh clip.wav
#   tools/wispr-transcribe.sh clip.wav --json
#   tools/wispr-transcribe.sh clip.wav --device '🎙️TO Zoom' --verbose
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
# Exit: 0 a transcript · 1 nothing arrived · 2 a precondition failed · 3 Wispr
# itself said there would be nothing (`dismissed` / `empty` / `no_audio`).

set -uo pipefail

# shellcheck source=tools/wispr-act.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/wispr-act.sh"

ROUTES="/test/state,/test/sink,/test/wispr-handsfree"

WAV=""
DEVICE=""
DRY_RUN=0
WAIT_ROUTES=0
ARGS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --device)      DEVICE="$2"; ARGS+=(--device "$2"); shift 2 ;;
    --json|--verbose) ARGS+=("$1"); shift ;;
    --dry-run)     DRY_RUN=1; ARGS+=(--dry-run); shift ;;
    --wait-routes) WAIT_ROUTES="${2:-600}"; shift 2 ;;
    -h|--help)     sed -n '2,35p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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

wispr_act_switch_input "$DEVICE" >&2
wispr_act_run "wispr-transcribe $(basename "$WAV")" -- \
  "$WISPR_ACT_PY" "$WISPR_ACT_REPO/helpers/wispr_loop.py" --transcribe "$WAV" "${ARGS[@]+"${ARGS[@]}"}"
STATUS=$?
wispr_act_restore_input >&2
exit $STATUS
