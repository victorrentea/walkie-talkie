#!/usr/bin/env bash
# Stream one WAV to Speechmatics' real-time WebSocket and print what comes back,
# as it comes back.
#
# Same purpose as `tools/eleven-test.sh`: a recogniser you can only reach through
# a dictation is a recogniser you cannot debug. This one needs no microphone, no
# app running and no gesture — it answers *is the key right, does the pinned
# language fit his Romanian, and how long is the tail after the audio stops*,
# which is the number the whole engine was chosen for.
#
#   tools/speechmatics-test.sh <file.wav> [language]
#   tools/speechmatics-test.sh --corpus [n] [language]   # the n newest samples
#
# The audio is fed **at the speed it was spoken**, because that is the only way
# the latency numbers mean anything — a WAV blasted down the socket in one go
# measures the server's throughput, not his wait. `--fast` skips the pacing when
# you only want the text.
#
# With --corpus it prints Speechmatics' reading beside the transcript already on
# disk, whichever engine recorded it. That is the A/B, on his own voice.
#
# The key is read the way the app reads it: SPEECHMATICS_API_KEY from the
# environment, else ~/.walkie-talkie/speechmatics.env.

set -uo pipefail

HOME_DIR="${WALKIE_HOME:-$HOME/.walkie-talkie}"
ENV_FILE="$HOME_DIR/speechmatics.env"
CORPUS="$HOME_DIR/voice-corpus"

key="${SPEECHMATICS_API_KEY:-}"
if [ -z "$key" ] && [ -f "$ENV_FILE" ]; then
    key=$(sed -n 's/^[[:space:]]*SPEECHMATICS_API_KEY[[:space:]]*=[[:space:]]*//p' "$ENV_FILE" \
          | head -1 | tr -d '"' | tr -d "'" | tr -d '[:space:]')
fi
if [ -z "$key" ]; then
    echo "no API key." >&2
    echo "  sign up at https://portal.speechmatics.com (\$100 of credit, no card)," >&2
    echo "  then put   SPEECHMATICS_API_KEY=…   in $ENV_FILE" >&2
    exit 2
fi
export SPEECHMATICS_API_KEY="$key"

python3 - "$@" <<'PY'
import asyncio, json, os, sys, time, wave

try:
    import websockets
except ImportError:
    sys.exit("pip3 install websockets — this tool needs it (the app does not).")

KEY = os.environ["SPEECHMATICS_API_KEY"]
MODEL = os.environ.get("WT_SM_MODEL")
URL = os.environ.get("WT_SM_URL") or (
    "wss://preview.rt.speechmatics.com/v2/agent" if MODEL else "wss://eu.rt.speechmatics.com/v2")
POINT = os.environ.get("WT_SM_OPERATING_POINT", "enhanced")
DELAY = float(os.environ.get("WT_SM_MAX_DELAY", "1.0"))
CHUNK = 3200                      # 0.1 s of 16 kHz mono int16, the app's buffer size
HOME = os.path.expanduser(os.environ.get("WALKIE_HOME", "~/.walkie-talkie"))


def custom_dictionary():
    """The same file the app sends, parsed the same way — `term` or
    `term: sounds like, …`.

    It reads **his** copy first and the checked-in starter second, because an
    A/B run against the app has to send what the app sends: a test that measured
    a different dictionary from the one in force would be measuring nothing.
    """
    here = os.path.dirname(os.path.abspath(__file__)) if "__file__" in dir() else "tools"
    # `vocab.txt` since the list became shared with `GeminiSource`; the old name
    # is still honoured, because his copy may carry his own edits under it.
    for path in (os.path.join(HOME, "vocab.txt"),
                 os.path.join(HOME, "speechmatics-vocab.txt"),
                 os.path.join(here, "vocab.txt"), "tools/vocab.txt"):
        if os.path.exists(path):
            break
    else:
        return [], None
    entries = []
    for line in open(path, encoding="utf-8"):
        row = line.strip()
        if not row or row.startswith("#"):
            continue
        content, _, sounds = row.partition(":")
        content = content.strip()
        if not content:
            continue
        like = [s.strip() for s in sounds.split(",") if s.strip()]
        entries.append({"content": content, "sounds_like": like} if like
                       else {"content": content})
    return entries[:1000], path


VOCAB, VOCAB_PATH = custom_dictionary()

args = [a for a in sys.argv[1:] if a != "--fast"]
PACED = "--fast" not in sys.argv[1:]


def read_wav(path):
    with wave.open(path, "rb") as w:
        if (w.getnchannels(), w.getsampwidth(), w.getframerate()) != (1, 2, 16000):
            sys.exit(f"{path}: need 16 kHz mono 16-bit, got "
                     f"{w.getframerate()} Hz × {w.getnchannels()}ch × {w.getsampwidth()*8}bit\n"
                     f"  afconvert -f WAVE -d LEI16@16000 -c 1 '{path}' /tmp/x.wav")
        return w.readframes(w.getnframes())


async def transcribe(path, language, quiet=False):
    """Returns (text, first_partial_s, tail_s) — or (None, …) on failure.

    Wrapped, because the interesting failures here arrive as a *close frame*
    rather than as a refused handshake: a wrong key connects fine and is thrown
    out when StartRecognition arrives, which as an unhandled exception is a
    twenty-line traceback ending in `close_exc` and saying nothing about keys.
    """
    try:
        return await session(path, language, quiet)
    except websockets.exceptions.WebSocketException as e:
        code = getattr(getattr(e, "rcvd", None), "code", None)
        reason = getattr(getattr(e, "rcvd", None), "reason", "") or str(e)
        print(f"\r   ! the session was closed"
              + (f" ({code})" if code else "") + f": {reason}", file=sys.stderr)
        if code == 4001 or "auth" in reason.lower() or "token" in reason.lower():
            print("     the key in the environment or in speechmatics.env is not "
                  "being accepted.", file=sys.stderr)
        return None, None, None
    except OSError as e:
        print(f"\r   ! could not reach {URL}: {e}", file=sys.stderr)
        return None, None, None


async def session(path, language, quiet):
    audio = read_wav(path)
    seconds = len(audio) / 32000
    finals, first_partial, started = [], None, None

    config = {"language": language, "operating_point": POINT, "max_delay": DELAY,
              "enable_partials": True, "diarization": "none"}
    if MODEL:
        config["model"] = MODEL
    if VOCAB:
        config["additional_vocab"] = VOCAB
    start_msg = {
        "message": "StartRecognition",
        "audio_format": {"type": "raw", "encoding": "pcm_s16le", "sample_rate": 16000},
        "transcription_config": config,
    }

    headers = {"Authorization": f"Bearer {KEY}"}
    try:
        connect = websockets.connect(URL, additional_headers=headers, max_size=None)
    except TypeError:                       # websockets < 14 spelled it differently
        connect = websockets.connect(URL, extra_headers=headers, max_size=None)

    async with connect as ws:
        await ws.send(json.dumps(start_msg))
        reply = json.loads(await ws.recv())
        if reply.get("message") != "RecognitionStarted":
            print(f"   ! {reply}", file=sys.stderr)
            return None, None, None
        started = time.monotonic()

        done = asyncio.Event()
        ended = {}

        async def reader():
            nonlocal first_partial
            async for raw in ws:
                m = json.loads(raw)
                kind = m.get("message")
                if kind == "AddPartialTranscript":
                    if first_partial is None and m.get("transcript", "").strip():
                        first_partial = time.monotonic() - started
                    if not quiet and m.get("transcript"):
                        sys.stderr.write("\r   … " + m["transcript"][-100:].ljust(100))
                        sys.stderr.flush()
                elif kind == "AddTranscript":
                    if m.get("transcript"):
                        finals.append(m["transcript"])
                elif kind == "EndOfTranscript":
                    ended["at"] = time.monotonic()
                    done.set()
                    return
                elif kind == "Error":
                    print(f"\r   ! {m.get('type')}: {m.get('reason')}", file=sys.stderr)
                    done.set()
                    return
                elif kind == "Warning":
                    print(f"\r   ~ {m.get('reason')}", file=sys.stderr)

        pump = asyncio.create_task(reader())

        seq = 0
        wall = time.monotonic()
        for i in range(0, len(audio), CHUNK):
            await ws.send(audio[i:i + CHUNK])
            seq += 1
            if PACED:
                # Where the next chunk *should* go out, measured from the start
                # rather than slept per chunk, so the send does not drift late.
                due = wall + (i + CHUNK) / 32000
                nap = due - time.monotonic()
                if nap > 0:
                    await asyncio.sleep(nap)
        released = time.monotonic()
        await ws.send(json.dumps({"message": "EndOfStream", "last_seq_no": seq}))

        try:
            await asyncio.wait_for(done.wait(), timeout=30)
        except asyncio.TimeoutError:
            print("\r   ! no EndOfTranscript in 30s", file=sys.stderr)
        pump.cancel()

    if not quiet:
        sys.stderr.write("\r" + " " * 106 + "\r")
    tail = ended["at"] - released if "at" in ended else None
    text = "".join(finals).strip()
    if not quiet:
        bits = [f"{seconds:.1f}s of audio"]
        if first_partial is not None:
            bits.append(f"first words {first_partial:.2f}s in")
        if tail is not None:
            bits.append(f"tail {tail:.2f}s after the release")
        print("   " + ", ".join(bits), file=sys.stderr)
    return text, first_partial, tail


def banner():
    """What this run is actually configured as — printed rather than assumed,
    because the dictionary and the pinned language are the two things that make
    two runs of the same WAV disagree."""
    bits = [MODEL or POINT, language_pick(), f"max_delay {DELAY}s"]
    if VOCAB:
        bits.append(f"{len(VOCAB)} dictionary entries")
    return ", ".join(bits)


def language_pick():
    if args and args[-1] in ("ro", "en", "de", "fr", "es", "it", "nl", "pt"):
        return args[-1]
    return os.environ.get("WT_SM_LANG", "ro")


async def main():
    language = language_pick()

    if args and args[0] == "--corpus":
        n = int(args[1]) if len(args) > 1 and args[1].isdigit() else 5
        corpus = os.path.expanduser(
            os.environ.get("WALKIE_HOME", "~/.walkie-talkie") + "/voice-corpus")
        # The corpus is a folder per day, so this walks — a flat listdir here
        # finds nothing at all and says "the 0 newest samples", which reads like
        # an empty corpus rather than like a bug.
        found = [os.path.join(root, f)
                 for root, _, files in os.walk(corpus) for f in files if f.endswith(".wav")]
        wavs = sorted(found, key=os.path.getmtime, reverse=True)[:n]
        print(f"Speechmatics {banner()} — "
              f"the {len(wavs)} newest corpus samples, against the transcript on disk\n")
        for wav in wavs:
            print(f"── {os.path.basename(wav)}")
            txt = wav[:-4] + ".txt"
            on_disk = open(txt).read().strip() if os.path.exists(txt) else "(no transcript)"
            print(f"   on disk: {on_disk}")
            text, _, _ = await transcribe(wav, language)
            if text is not None:
                print(f"   sm     : {text}")
            print()
        return

    if not args or not os.path.isfile(args[0]):
        sys.exit("usage: speechmatics-test.sh <file.wav> [language]\n"
                 "       speechmatics-test.sh --corpus [n] [language]")
    print(f"Speechmatics {banner()} — {os.path.basename(args[0])}")
    text, _, _ = await transcribe(args[0], language)
    if text is not None:
        print(text)


asyncio.run(main())
PY
