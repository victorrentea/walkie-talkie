#!/bin/bash
# Drive one Wispr Flow dictation end to end, from a WAV, and report what the
# relay did with it.
#
#   tools/wispr-test.sh /tmp/test.wav            # bound or unbound, as it stands
#   tools/wispr-test.sh --device '🎙️TO Zoom' f.wav
#   tools/wispr-test.sh --no-switch f.wav        # leave the system input alone
#
# The channel, end to end:
#
#   WAV ──play──▶ virtual input device ──mic──▶ Wispr Flow ──⌘V──▶ (swallowed)
#                       ▲                                              │
#            system default input                     walkie-talkie ◀──┘
#            (Wispr mic = Auto-detect)                       │
#                                                   bound agent / caret
#
# Nothing here synthesises a keystroke of its own. The dictation is started and
# stopped through `POST /test/wispr-handsfree`, which makes the **app** post
# Wispr's own `fn ⌃ Space` — the app has the Accessibility grant, and posting the
# chord through the mechanism the forward button already uses is the one input
# this script is allowed to cause.
#
# The 🔒 hands-off locks go up for the run: Victor Addons watches for synthetic
# input and would raise them anyway, and a run he types into is a run whose
# result means nothing.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PY=/Library/Frameworks/Python.framework/Versions/3.12/bin/python3
LOG="$HOME/.walkie-talkie/relay.log"

DEVICE=""
WAV=""
SWITCH=1
SPEAKER=0
TIMEOUT=45
while [ $# -gt 0 ]; do
  case "$1" in
    --device) DEVICE="$2"; shift 2 ;;
    --no-switch) SWITCH=0; shift ;;
    # **Out loud, into whatever microphone Wispr is actually on.** The virtual
    # channel needs Wispr's microphone set to Auto-detect; until that is done the
    # only way to reach it is the room — play the clip on the speakers and let
    # the built-in microphone hear it. Crude, correct, and the one mode that
    # works with no setting changed. It is also the only mode that makes a noise.
    --speaker) SPEAKER=1; SWITCH=0; shift ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    -h|--help) sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) WAV="$1"; shift ;;
  esac
done
[ -n "$WAV" ] || { echo "usage: $0 [--device NAME] [--no-switch] <file.wav>" >&2; exit 2; }
[ -f "$WAV" ] || { echo "no such WAV: $WAV" >&2; exit 2; }

say() { printf '%s\n' "$*"; }
fail() { printf '✗ %s\n' "$*" >&2; exit 1; }

# ── Preflight: say exactly what is missing, never fail silently ─────────────
#
# The list itself lives in `helpers/wispr_preflight.py`, because
# `tools/wispr-loop.sh` needs the same six answers and a second copy of them is
# a copy that drifts — the `✗ Wispr microphone is pinned` row is the one thing
# standing between a real result and a WAV played into a device nobody records,
# and it has to say the same sentence from both scripts.
#
# `--no-idle-check`: this script is a single dictation Victor asked for by hand,
# so it is allowed to run beside whatever else is going on.
say "── preflight ──────────────────────────────────────────────"
PRE=(--no-idle-check)
[ -n "$DEVICE" ] && PRE+=(--device "$DEVICE")
[ "$SPEAKER" = 1 ] && PRE+=(--speaker)
"$PY" "$REPO/helpers/wispr_preflight.py" "${PRE[@]}" \
  || fail "preflight failed — fix the ✗ rows above and run again"

PORT=$("$PY" "$REPO/helpers/wispr_preflight.py" --print port) \
  || fail "the relay is not listening on 8917–8919 — is Walkie Talkie running?"

# **`"${2:-{}}"` sends a stray `}` and it cost a run** (2026-09-14). Bash closes
# the expansion at the *first* `}`, so the default is `{` and the second brace
# falls through as literal text: a call with a body posted `{"hand": true}}`,
# JSONSerialization refused it, the route read its flag as absent and took the
# default branch. The failure is silent at every step — curl is happy, the route
# answers 200, and only the echoed flag says the body never arrived. Spelled out
# in two statements rather than cleverly, because the clever form is the bug.
post() {
  local body="${2:-}"
  [ -n "$body" ] || body='{}'
  curl -s -m 10 -X POST "http://127.0.0.1:$PORT$1" -H 'content-type: application/json' -d "$body"
}

if [ "$SPEAKER" = 1 ]; then
  DEV_NAME="(speakers)"
else
  DEV_NAME=$("$PY" "$REPO/helpers/wispr_preflight.py" --print device ${DEVICE:+--device "$DEVICE"}) \
    || fail "no usable virtual output device"
fi

# ── The system default input, switched and always put back ──────────────────
RESTORE=""
restore() {
  [ -n "$RESTORE" ] || return 0
  post /test/input "{\"name\": $(printf '%s' "$RESTORE" | "$PY" -c 'import json,sys; print(json.dumps(sys.stdin.read()))')}" >/dev/null
  say "↩︎ system input restored to $RESTORE"
  RESTORE=""
}
trap restore EXIT INT TERM

if [ "$SWITCH" = 1 ]; then
  if command -v SwitchAudioSource >/dev/null 2>&1; then
    RESTORE=$(SwitchAudioSource -c -t input)
    SwitchAudioSource -t input -s "$DEV_NAME" >/dev/null || fail "SwitchAudioSource refused $DEV_NAME"
  else
    OUT=$(post /test/input "{\"name\": $(printf '%s' "$DEV_NAME" | "$PY" -c 'import json,sys; print(json.dumps(sys.stdin.read()))')}")
    printf '%s' "$OUT" | /usr/bin/grep -q '"changed":true' \
      || fail "the relay could not make '$DEV_NAME' the system input: $OUT"
    RESTORE=$(printf '%s' "$OUT" | sed -n 's/.*"was":"\([^"]*\)".*/\1/p')
  fi
  say "🎚️ system input → $DEV_NAME (was $RESTORE)"
fi

# ── Only this run's log lines ───────────────────────────────────────────────
MARK=$(wc -c < "$LOG" 2>/dev/null || echo 0)

# ── The run, with the locks up ──────────────────────────────────────────────
run() {
  say ""
  say "── dictating ──────────────────────────────────────────────"
  post /test/wispr-handsfree >/dev/null
  say "▶ chord posted — playing $(basename "$WAV")"
  if [ "$SPEAKER" = 1 ]; then
    # The lead and tail silence the virtual path gets for free: Wispr drops the
    # first fraction of a second while its recorder spins up, and its endpointing
    # wants an ending rather than a key release mid-word.
    sleep 0.6; afplay "$WAV"; sleep 0.5
  else
    "$PY" - "$REPO" "$WAV" "$DEV_NAME" <<'EOF'
import sys
sys.path.insert(0, sys.argv[1] + "/helpers")
import wispr_loopback as wl
idx, name = wl.resolve_device(sys.argv[3])
audio, rate, _ = wl.read_wav(sys.argv[2])
wl.play(audio, rate, idx)
EOF
  fi
  # The chord is a toggle and hands-free does not end itself.
  post /test/wispr-handsfree >/dev/null
  say "■ chord posted again — waiting for the words"

  # Wait for the relay to say what it did, not for Wispr's database.
  local deadline=$((SECONDS + TIMEOUT))
  while [ $SECONDS -lt $deadline ]; do
    # The ring goes down at the stop, a second or two *before* the words —
    # waiting for it reported "no transcript" on deliveries that then landed
    # (2026-09-22). Wait for the words themselves, or for the relay saying
    # there were none.
    if tail -c "+$((MARK + 1))" "$LOG" | /usr/bin/grep -aqE '🗣️ wispr transcript|No words|⚠️ wispr: copy_last_text carried nothing'; then
      sleep 1
      break
    fi
    sleep 0.5
  done
}

if [ -x "$HOME/bin/hands-off" ]; then
  export -f say post run 2>/dev/null || true
  "$HOME/bin/hands-off" start "wispr end-to-end test" 120 >/dev/null 2>&1
  run
  "$HOME/bin/hands-off" end >/dev/null 2>&1
else
  run
fi

restore

# ── What happened ───────────────────────────────────────────────────────────
say ""
say "── relay.log ──────────────────────────────────────────────"
tail -c "+$((MARK + 1))" "$LOG" | /usr/bin/grep -aE \
  'wispr flow (opened|closed)|⚡|◯ caret halo|probe:|⌘V from|🗣️|📋|→ |delivered|No words' \
  || say "(nothing — the relay saw no dictation at all)"

say ""
TRANSCRIPT=$(tail -c "+$((MARK + 1))" "$LOG" | /usr/bin/grep -am1 '🗣️ wispr transcript' || true)
if [ -n "$TRANSCRIPT" ]; then
  say "✓ $TRANSCRIPT"
  exit 0
fi
say "✗ no transcript reached the relay."
say "  Check, in order: Wispr's microphone (Auto-detect), that the WAV is 16-bit PCM,"
say "  and the 'probe:' lines above — they say what Wispr posted, if anything."
exit 1
