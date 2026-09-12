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
WISPR_CONFIG="$HOME/Library/Application Support/Wispr Flow/config.json"

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

# ── The port the relay is listening on ──────────────────────────────────────
PORT=""
for p in 8917 8918 8919; do
  if curl -s -m 2 "http://127.0.0.1:$p/target" >/dev/null 2>&1; then PORT=$p; break; fi
done
[ -n "$PORT" ] || fail "the relay is not listening on 8917–8919 — is Walkie Talkie running?"

post() { curl -s -m 10 -X POST "http://127.0.0.1:$PORT$1" -H 'content-type: application/json' -d "${2:-{}}"; }

# ── Preflight: say exactly what is missing, never fail silently ─────────────
say "── preflight ──────────────────────────────────────────────"
MISSING=0

pgrep -f "Wispr Flow.app" >/dev/null || { say "✗ Wispr Flow is not running"; MISSING=1; }
say "✓ relay on port $PORT"

TARGET=$(curl -s -m 5 "http://127.0.0.1:$PORT/target")
if printf '%s' "$TARGET" | /usr/bin/grep -q '"bound":true'; then
  BOUND=$(printf '%s' "$TARGET" | sed -n 's/.*"address":"\([^"]*\)".*/\1/p')
  say "✓ bound to $BOUND — the transcript should reach that session"
else
  say "• unbound — the transcript should land at the caret"
fi

# Wispr's microphone. `overrideAudioDeviceId == "default"` is *Auto-detect*, the
# one setting that makes the system default input scriptable. Anything else is a
# named device and this script cannot point Wispr at the WAV.
if [ -f "$WISPR_CONFIG" ]; then
  MIC=$("$PY" - "$WISPR_CONFIG" <<'EOF' 2>/dev/null
import json, sys
u = json.load(open(sys.argv[1])).get("prefs", {}).get("user", {})
dev = u.get("overrideAudioDeviceId")
names = {d.get("deviceId"): d.get("name") for d in (u.get("rankedAudioDevices") or [])}
print(("default" if dev == "default" else "fixed") + "\t" + str(names.get(dev, dev)))
EOF
)
  case "$MIC" in
    default*)
      say "✓ Wispr microphone: Auto-detect — it follows the system default" ;;
    *)
      if [ "$SPEAKER" = 1 ]; then
        say "• Wispr microphone is pinned (${MIC#*	}) — playing out loud instead"
      else
        say "✗ Wispr microphone is pinned to a device (${MIC#*	})."
        say "  Victor: Wispr → Settings → Microphone → 'Auto-detect (MacBook Pro)'."
        say "  Without it Wispr will hear the built-in mic and not the WAV."
        MISSING=1
      fi ;;
  esac
else
  say "• Wispr config not found — cannot check which microphone it is on"
fi

"$PY" -c "import sounddevice, numpy" 2>/dev/null \
  || { say "✗ $PY has no sounddevice/numpy — pip install sounddevice numpy"; MISSING=1; }

# The virtual device the WAV is played into. Its *output* side is what we play
# to; its input side is what Wispr records.
DEV_NAME=$("$PY" - "$REPO" "$DEVICE" <<'EOF' 2>&1
import sys
sys.path.insert(0, sys.argv[1] + "/helpers")
try:
    import wispr_loopback as wl
    idx, name = wl.resolve_device(sys.argv[2] or None)
    print(name)
except SystemExit as e:
    print("MISSING\t%s" % str(e).replace("\n", " "))
except Exception as e:
    print("MISSING\t%s" % e)
EOF
)
if [ "$SPEAKER" = 1 ]; then
  DEV_NAME="(speakers)"
  say "✓ playing out loud — Wispr hears it through whatever microphone it is on"
else
  case "$DEV_NAME" in
    MISSING*) say "✗ no virtual output device: ${DEV_NAME#*	}"; MISSING=1 ;;
    *) say "✓ playing into: $DEV_NAME" ;;
  esac
fi

[ "$MISSING" = 0 ] || fail "preflight failed — fix the ✗ rows above and run again"

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
    if tail -c "+$((MARK + 1))" "$LOG" | /usr/bin/grep -qE '⚡ ring down|🗣️ wispr transcript'; then
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
tail -c "+$((MARK + 1))" "$LOG" | /usr/bin/grep -E \
  'wispr flow (opened|closed)|⚡|◯ caret halo|probe:|⌘V from|🗣️|📋|→ |delivered|No words' \
  || say "(nothing — the relay saw no dictation at all)"

say ""
TRANSCRIPT=$(tail -c "+$((MARK + 1))" "$LOG" | /usr/bin/grep -m1 '🗣️ wispr transcript' || true)
if [ -n "$TRANSCRIPT" ]; then
  say "✓ $TRANSCRIPT"
  exit 0
fi
say "✗ no transcript reached the relay."
say "  Check, in order: Wispr's microphone (Auto-detect), that the WAV is 16-bit PCM,"
say "  and the 'probe:' lines above — they say what Wispr posted, if anything."
exit 1
