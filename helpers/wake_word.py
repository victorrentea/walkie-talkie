#!/usr/bin/env python3
"""**"Hey Claude" — the wake word** (2026-11-12).

A listen-only helper the app spawns (`WakeWord.swift`): it holds its own input
stream on the microphone the app resolved, runs openWakeWord on 80 ms chunks,
and says what it heard as one JSON object per line on stdout. It never records
to disk and never decides what a wake *means* — the app does (a spawn, or a ⚡
question when the words open with "I have a question").

    {"event": "ready", "device": "...", "rate": 16000}
    {"event": "wake", "score": 0.93}
    {"event": "speech"}                      the first voiced hop after a wake
    {"event": "silence", "after": 1.2}       that much quiet after speech: the end
    {"event": "timeout"}                     nothing said within --no-speech-s
    {"event": "error", "error": "..."}

After a wake it watches for the end of the command on the same stream (an
adaptive RMS floor, the app's own meter shape: 9 dB over the floor is voice),
then goes back to listening for the wake word after `--cooldown-s`.

stdin takes one word per line: `pause` (the app is dictating — no wake fires,
the end-of-speech watch keeps running), `resume`, `quit`.

Why a child process and not the app's tap: the app's audio engine has a history
of lifecycle crashes (`.claude/rules/whisper-and-corpus.md`, *Do not*), and an
always-open second tap there would be one more thing for every take to share.
A child of the app is attributed to it by TCC, so the microphone grant is the
app's own. Its venv is separate (`~/.walkie-talkie/wake/venv`), so nothing here
can move the whisper helper's numpy.
"""
import argparse
import json
import math
import os
import queue
import sys
import threading
import time


def say(**event):
    sys.stdout.write(json.dumps(event) + "\n")
    sys.stdout.flush()


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--model", required=True)
    p.add_argument("--threshold", type=float, default=0.5)
    p.add_argument("--device", default="", help="a substring of the input's name; empty = system default")
    p.add_argument("--silence-s", type=float, default=1.2)
    p.add_argument("--no-speech-s", type=float, default=6.0)
    p.add_argument("--max-command-s", type=float, default=60.0)
    p.add_argument("--cooldown-s", type=float, default=1.5)
    p.add_argument("--wav", default="", help="read this 16 kHz file instead of a microphone (tests)")
    a = p.parse_args()

    import numpy as np
    from openwakeword.model import Model

    model = Model(wakeword_models=[a.model], inference_framework="onnx")
    key = list(model.models.keys())[0]
    chunks: "queue.Queue[np.ndarray]" = queue.Queue(maxsize=200)
    paused = threading.Event()
    stop = threading.Event()

    def stdin_loop():
        for line in sys.stdin:
            word = line.strip()
            if word == "pause":
                paused.set()
            elif word == "resume":
                paused.clear()
            elif word == "quit":
                break
        # EOF is the app gone (or `quit`); a file run ends with its file instead.
        if not a.wav:
            stop.set()

    threading.Thread(target=stdin_loop, daemon=True).start()

    stream = None
    if a.wav:
        import soundfile as sf
        audio, sr = sf.read(a.wav, dtype="int16")
        if audio.ndim > 1:
            audio = audio[:, 0]
        if sr != 16000:
            say(event="error", error=f"{a.wav} is {sr} Hz, not 16000")
            return 2
        audio = np.concatenate([np.zeros(16000, np.int16), audio, np.zeros(48000, np.int16)])

        def feed():
            for i in range(0, len(audio) - 1280, 1280):
                chunks.put(audio[i:i + 1280])
            chunks.put(None)

        threading.Thread(target=feed, daemon=True).start()
        say(event="ready", device=os.path.basename(a.wav), rate=16000)
    else:
        import sounddevice as sd
        device = None
        if a.device:
            needle = a.device.lower()
            for i, d in enumerate(sd.query_devices()):
                if d["max_input_channels"] > 0 and needle in d["name"].lower():
                    device = i
                    break

        def on_audio(indata, frames, t, status):
            try:
                chunks.put_nowait(indata[:, 0].copy())
            except queue.Full:
                pass

        try:
            stream = sd.InputStream(samplerate=16000, channels=1, dtype="int16", blocksize=1280,
                                    device=device, callback=on_audio)
            stream.start()
        except Exception as e:  # the device went away, or no grant
            say(event="error", error=f"microphone: {e}")
            return 3
        name = sd.query_devices(device if device is not None else sd.default.device[0])["name"]
        say(event="ready", device=name, rate=16000)

    # The end-of-command watch: the app's meter shape (`MicRecorder.meter`), per
    # 80 ms chunk — instant attack down, 2 % release up, 9 dB over it is voice,
    # never under 180.
    floor = None
    mode = "wake"             # "wake" | "command" | "cooldown"
    woke_at = 0.0
    voiced_at = None          # last voiced chunk in command mode
    heard = False
    cooldown_until = 0.0
    clock = 0.0               # seconds of audio seen — the wav and the mic alike

    while not stop.is_set() or not chunks.empty():
        try:
            chunk = chunks.get(timeout=0.2)
        except queue.Empty:
            continue
        if chunk is None:
            break
        clock += len(chunk) / 16000
        rms = math.sqrt(float(np.mean(chunk.astype(np.float32) ** 2))) if len(chunk) else 0.0
        if floor is None:
            floor = max(rms, 1.0)
        floor = rms if rms < floor else floor * 1.02
        voiced = rms > max(180.0, floor * 10 ** (9 / 20))

        if mode == "wake":
            score = float(model.predict(chunk)[key])
            if score >= a.threshold and not paused.is_set() and clock >= cooldown_until:
                say(event="wake", score=round(score, 3))
                mode, woke_at, voiced_at, heard = "command", clock, None, False
                model.reset()
        elif mode == "command":
            if voiced:
                if not heard:
                    say(event="speech")
                heard, voiced_at = True, clock
            if heard and voiced_at is not None and clock - voiced_at >= a.silence_s:
                say(event="silence", after=round(clock - voiced_at, 2))
                mode, cooldown_until = "wake", clock + a.cooldown_s
            elif not heard and clock - woke_at >= a.no_speech_s:
                say(event="timeout")
                mode, cooldown_until = "wake", clock + a.cooldown_s
            elif clock - woke_at >= a.max_command_s:
                say(event="silence", after=0, capped=True)
                mode, cooldown_until = "wake", clock + a.cooldown_s

    if stream is not None:
        stream.stop()
        stream.close()
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(0)
    except Exception as e:
        say(event="error", error=str(e))
        sys.exit(1)
