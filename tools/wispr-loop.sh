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

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PY="${WISPR_LOOP_PYTHON:-/Library/Frameworks/Python.framework/Versions/3.12/bin/python3}"
SCRATCH="${TMPDIR:-/tmp}/wispr-loop"

# The routes every scenario rests on. A build without them is not a failure to
# report as red — it is a build from before the harness, and the run should wait
# or say so rather than invent another way in.
ROUTES="/test/state,/test/sink,/test/gesture"

DEVICE=""
DRY_RUN=0
WAIT_ROUTES=0
PASSTHROUGH=()
# A string and not an array: /bin/bash on macOS is 3.2, where `${arr[*]}` on an
# empty array is an unbound-variable error under `set -u`.
SCENARIO_LABEL=""

say() { printf '%s\n' "$*"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --device)      DEVICE="$2"; PASSTHROUGH+=(--device "$2"); shift 2 ;;
    --wav)         PASSTHROUGH+=(--wav "$2"); shift 2 ;;
    --transcript)  PASSTHROUGH+=(--transcript "$2"); shift 2 ;;
    --json|--verbose|--all|--list) PASSTHROUGH+=("$1"); shift ;;
    --repeat)      PASSTHROUGH+=(--repeat "$2"); shift 2 ;;
    --dry-run)     DRY_RUN=1; PASSTHROUGH+=(--dry-run); shift ;;
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
say "── preflight ──────────────────────────────────────────────"

# The routes are checked first and separately, because "this build is older than
# the harness" is a different answer from "your Mac is not set up".
if [ "$WAIT_ROUTES" != 0 ]; then
  say "⏳ waiting up to ${WAIT_ROUTES}s for $ROUTES"
  deadline=$((SECONDS + WAIT_ROUTES))
  until "$PY" "$REPO/helpers/wispr_preflight.py" --routes-only --require-routes "$ROUTES" \
        --json 2>/dev/null | /usr/bin/grep -q '"ok": *true'; do
    [ $SECONDS -lt $deadline ] || { say "✗ the routes never arrived"; exit 3; }
    sleep 5
  done
  say "✓ the routes are there"
fi

PREFLIGHT_ARGS=(--require-routes "$ROUTES")
[ -n "$DEVICE" ] && PREFLIGHT_ARGS+=(--device "$DEVICE")
# A dry run posts nothing, so nothing can be harmed by a setting being wrong: it
# still prints every row — the point of running it today is to see what is not
# ready yet — but it does not refuse to go on.
[ "$DRY_RUN" = 1 ] && PREFLIGHT_ARGS+=(--no-idle-check --advisory)

"$PY" "$REPO/helpers/wispr_preflight.py" "${PREFLIGHT_ARGS[@]}"
PREFLIGHT=$?
if [ $PREFLIGHT != 0 ]; then
  # Tell the two apart: a build without the routes is waited out, a Mac that is
  # set up wrong is fixed.
  if ! "$PY" "$REPO/helpers/wispr_preflight.py" --routes-only --require-routes "$ROUTES" \
       --json 2>/dev/null | /usr/bin/grep -q '"ok": *true'; then
    say ""
    say "the relay's build has not got the loopback routes yet — rerun with --wait-routes 600"
    exit 3
  fi
  say ""
  say "✗ preflight failed — fix the ✗ rows above and run again"
  exit 2
fi

if [ "$DRY_RUN" = 1 ]; then
  say ""
  say "── dry run — nothing below is posted ──────────────────────"
  exec "$PY" "$REPO/helpers/wispr_loop.py" "${PASSTHROUGH[@]}"
fi

# ── The system default input, switched and ALWAYS put back ──────────────────
# The restore lives here rather than in the Python, because a trap in the shell
# is the one thing that survives the runner being killed. Leaving Victor's Mac
# recording from a Loopback device is the single worst thing this script could
# do — his next real dictation would be silence and nothing would say why.
RESTORE=""
restore() {
  [ -n "$RESTORE" ] || return 0
  local name="$RESTORE"; RESTORE=""
  "$PY" - "$name" <<'EOF' >/dev/null 2>&1
import json, sys, urllib.request
body = json.dumps({"name": sys.argv[1]}).encode()
for port in (8917, 8918, 8919):
    try:
        req = urllib.request.Request("http://127.0.0.1:%d/test/input" % port, data=body,
                                     headers={"content-type": "application/json"}, method="POST")
        urllib.request.urlopen(req, timeout=10).read()
        break
    except Exception:
        continue
EOF
  say "↩︎ system input restored to $name"
}
trap restore EXIT INT TERM

DEV_NAME=$("$PY" - "$REPO" "$DEVICE" <<'EOF'
import sys
sys.path.insert(0, sys.argv[1] + "/helpers")
import wispr_loopback as wl
print(wl.resolve_device(sys.argv[2] or None)[1])
EOF
) || { say "✗ no virtual output device"; exit 2; }

SWITCH=$("$PY" - "$DEV_NAME" <<'EOF'
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
)
case "$SWITCH" in
  *'"changed":true'*|*'"changed": true'*) : ;;
  *) say "✗ the relay could not make '$DEV_NAME' the system input: $SWITCH"; exit 2 ;;
esac
RESTORE=$(printf '%s' "$SWITCH" | sed -n 's/.*"was": *"\([^"]*\)".*/\1/p')
say "🎚️ system input → $DEV_NAME (was ${RESTORE:-unknown})"

# ── The run, with the 🔒 locks up ───────────────────────────────────────────
# Mandatory, not a nicety: the run posts real keystroke chords, opens and closes
# Terminal windows and steals focus. `hands-off run` releases on exit, on Ctrl-C
# and on a crash — a killed harness must never park the locks on Victor's screen.
say ""
"$HOME/bin/hands-off" run "wispr-loop ${SCENARIO_LABEL:-all}" -- \
  "$PY" "$REPO/helpers/wispr_loop.py" "${PASSTHROUGH[@]}"
STATUS=$?

restore
exit $STATUS
