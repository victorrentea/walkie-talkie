#!/usr/bin/env python3
"""Long-lived local transcriber for Walkie Talkie.

**It is a daemon and not a script because of one measurement**: importing
`mlx_whisper` costs 7.4s and the first transcription pays another 2.8s to load
the weights, while a second one takes 1.3s. Shelling out per dictation would put
ten seconds between Victor finishing a sentence and the agent seeing it — so the
process starts once, warms up once, and then answers in about a tenth of the
audio's length.

Protocol, one JSON object per line each way:

    →  {"wav": "/path/to/file.wav"}
    ←  {"ok": true, "text": "…", "language": "ro", "avg_logprob": -0.21,
        "compression_ratio": 1.4, "no_speech_prob": 0.0}
    ←  {"ok": false, "error": "…"}

and once, unprompted, at start-up:

    ←  {"ready": true, "model": "…"}   (or {"ready": false, "error": "…"})

stdout carries **only** protocol lines. mlx and huggingface both write progress
bars and warnings to stdout, so every model call is wrapped in a redirect —
without it the first tqdm bar corrupts the stream and the relay sees garbage.

`condition_on_previous_text=False` is deliberate and is the one decode setting
that was measured rather than guessed. Left at its default (True), 3 of 20
sample dictations fell into repetition loops — "nu știu, nu știu, nu știu…" for
forty words — and because every looped word is an insertion, those three alone
moved pooled WER from 37% to 50%. The flag is right *here* and would be wrong in
victor-macos-addons, which streams short chunks and genuinely needs the previous
one for continuity.
"""
import contextlib
import json
import os
import sys

MODEL = os.environ.get("RELAY_WHISPER_MODEL", "mlx-community/whisper-large-v3-turbo")


def emit(obj):
    sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
    sys.stdout.flush()


@contextlib.contextmanager
def quiet():
    """Keep mlx/tqdm chatter off the protocol stream."""
    with open(os.devnull, "w") as dev:
        with contextlib.redirect_stdout(dev), contextlib.redirect_stderr(dev):
            yield


try:
    with quiet():
        import mlx_whisper
        import numpy as np
except Exception as e:  # noqa: BLE001 — any import failure is the same answer
    emit({"ready": False, "error": f"cannot import mlx_whisper: {e}"})
    sys.exit(1)


def transcribe(path):
    with quiet():
        return mlx_whisper.transcribe(
            path,
            path_or_hf_repo=MODEL,
            language=None,
            verbose=False,
            condition_on_previous_text=False,
        )


# Warm up on a second of silence so the weights are resident before Victor's
# first sentence, rather than his first sentence paying for them. Same reason
# victor-macos-addons warms up before its GUI starts.
try:
    warm = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".warmup.wav")
    if not os.path.exists(warm):
        import wave
        with wave.open(warm, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(16000)
            w.writeframes(b"\x00" * 32000)
    transcribe(warm)
    emit({"ready": True, "model": MODEL})
except Exception as e:  # noqa: BLE001
    emit({"ready": False, "error": f"warm-up failed: {e}"})
    sys.exit(1)


for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        req = json.loads(line)
        wav = req["wav"]
        if not os.path.exists(wav):
            emit({"ok": False, "error": f"no such file: {wav}"})
            continue
        res = transcribe(wav)
        segs = res.get("segments") or []
        # The worst segment, not the average: a dictation is unusable if any part
        # of it was hallucinated, and averaging hides one bad segment inside
        # twenty good ones. `avg_logprob` is the signal that actually separates —
        # measured over the corpus, a gate at -0.6 caught 7 of 11 semantically
        # broken transcripts while falsely rejecting 0 of 40 good ones, whereas
        # `no_speech_prob` caught none of them.
        emit({
            "ok": True,
            "text": (res.get("text") or "").strip(),
            "language": res.get("language"),
            "avg_logprob": min((s.get("avg_logprob", 0.0) for s in segs), default=0.0),
            "compression_ratio": max((s.get("compression_ratio", 0.0) for s in segs), default=0.0),
            "no_speech_prob": max((s.get("no_speech_prob", 0.0) for s in segs), default=0.0),
        })
    except Exception as e:  # noqa: BLE001 — one bad request must not kill the daemon
        emit({"ok": False, "error": str(e)})
