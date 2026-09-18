#!/usr/bin/env bash
# Send one WAV to ElevenLabs Scribe and print what came back.
#
# The point of it is the same as `tools/wispr-test.sh`'s: a recogniser you can
# only reach through a dictation is a recogniser you cannot debug. This one
# needs no microphone, no app running and no gesture — it answers *is the key
# right, is the model right, and what does Scribe actually do with Victor's
# Romanian*, which are three questions worth separating from *does the relay
# wire it up correctly*.
#
#   tools/eleven-test.sh <file.wav> [model_id]
#   tools/eleven-test.sh --corpus [n] [model_id]   # the n newest corpus samples
#
# With --corpus it prints Scribe's reading **beside the one already on disk**,
# which is whichever engine recorded that sample. That is the A/B, on his own
# voice, and it costs $0.40 an hour of audio.
#
# The key is read the same way the app reads it: ELEVENLABS_API_KEY from the
# environment, else ~/.walkie-talkie/elevenlabs.env.

set -uo pipefail

HOME_DIR="${WALKIE_HOME:-$HOME/.walkie-talkie}"
ENV_FILE="$HOME_DIR/elevenlabs.env"
CORPUS="$HOME_DIR/voice-corpus"

key="${ELEVENLABS_API_KEY:-}"
if [ -z "$key" ] && [ -f "$ENV_FILE" ]; then
    key=$(sed -n 's/^[[:space:]]*ELEVENLABS_API_KEY[[:space:]]*=[[:space:]]*//p' "$ENV_FILE" \
          | head -1 | tr -d '"' | tr -d "'" | tr -d '[:space:]')
fi
if [ -z "$key" ]; then
    echo "no API key." >&2
    echo "  put   ELEVENLABS_API_KEY=sk_…   in $ENV_FILE" >&2
    echo "  or    export ELEVENLABS_API_KEY=sk_…" >&2
    exit 2
fi

# One transcription. Prints the text on stdout and the metadata on stderr, so
# `$(transcribe …)` gives you the words alone.
transcribe() {
    local wav="$1" model="$2" started elapsed body code
    started=$(date +%s.%N)
    body=$(curl -sS --max-time 60 -w '\n%{http_code}' \
        -X POST 'https://api.elevenlabs.io/v1/speech-to-text' \
        -H "xi-api-key: $key" \
        -F "model_id=$model" \
        -F 'diarize=false' \
        -F 'tag_audio_events=false' \
        -F "file=@$wav;type=audio/wav") || { echo "curl failed" >&2; return 1; }
    elapsed=$(echo "$(date +%s.%N) - $started" | bc)
    code=$(echo "$body" | tail -1)
    body=$(echo "$body" | sed '$d')
    if [ "$code" != "200" ]; then
        echo "HTTP $code — $(echo "$body" | head -c 400)" >&2
        return 1
    fi
    printf '  %s in %.2fs\n' \
        "$(echo "$body" | python3 -c 'import json,sys; d=json.load(sys.stdin); print("%s %.0f%%" % (d.get("language_code","?"), 100*d.get("language_probability",0)))')" \
        "$elapsed" >&2
    echo "$body" | python3 -c 'import json,sys; print(json.load(sys.stdin)["text"].strip())'
}

model="${!#}"
case "$model" in scribe_*) ;; *) model="${WT_ELEVEN_MODEL:-scribe_v1}" ;; esac

if [ "${1:-}" = "--corpus" ]; then
    n="${2:-5}"; case "$n" in ''|*[!0-9]*) n=5 ;; esac
    echo "ElevenLabs $model — the $n newest corpus samples, against the transcript on disk"
    echo
    # The .txt beside each .wav is what the engine that recorded it heard.
    find "$CORPUS" -name '*.wav' -type f -print0 2>/dev/null \
        | xargs -0 ls -t 2>/dev/null | head -"$n" | while read -r wav; do
        txt="${wav%.wav}.txt"
        echo "── $(basename "$wav")"
        echo "   on disk: $(cat "$txt" 2>/dev/null || echo '(no transcript)')"
        got=$(transcribe "$wav" "$model") && echo "   scribe : $got"
        echo
    done
    exit 0
fi

wav="${1:-}"
if [ -z "$wav" ] || [ ! -f "$wav" ]; then
    echo "usage: $0 <file.wav> [model_id]" >&2
    echo "       $0 --corpus [n] [model_id]" >&2
    exit 1
fi
echo "ElevenLabs $model — $(basename "$wav")"
transcribe "$wav" "$model"
