#!/usr/bin/env python3
"""**"Hey Claude" — the wake word** (2026-11-12).

A listen-only helper the app spawns (`WakeWord.swift`): it holds its own input
stream on the microphone the app resolved, runs openWakeWord on 80 ms chunks,
and says what it heard as one JSON object per line on stdout. It keeps only the
few seconds around a wake (below) and never decides what a wake *means* — the app does (a spawn, or a ⚡
question when the words open with "I have a question").

    {"event": "ready", "device": "...", "rate": 16000}
    {"event": "wake", "score": 0.93, "word": "hey claude"}
    {"event": "speech"}                      the first voiced hop after a wake
    {"event": "silence", "after": 1.2, "voiced": 2.3, "head": "/…/head.wav"}
                                             that much quiet after speech: the end;
                                             `head` = the first --head-s seconds from the
                                             wake on, gapless (the app's own take opens
                                             later and loses the first words)
    {"event": "timeout"}                     nothing said within --no-speech-s, or under
                                             --min-voiced-s of voice in all
    {"event": "error", "error": "..."}

After a wake it watches for the end of the command on the same stream (an
adaptive RMS floor, the app's own meter shape: 9 dB over the floor is voice),
then goes back to listening for the wake word after `--cooldown-s`.

**Every wake leaves its audio** (2026-11-13, after 38 false "hey santa" in one
workshop day): `--triggers`/<stamp>-<word>-<score>.wav = the 3 s before the wake
plus 1 s after, with a `.json` beside it (`window_end` = the sample the scored
2 s window ended on). `evals/wake-word/train_whisper_wake.py` has the local
Whisper label each one — said it, or fooled the detector — and retrains on
them. The newest `--triggers-keep` are kept.

**`--hold`** (a file touched in the last 5 s) = no wake fires: the take
recorder (`evals/wake-word/record_takes.py`) says the phrase thirty times.

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
import collections
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


class WhisperWake:
    """A wake word on Whisper's encoder (`evals/wake-word/train_whisper_wake.py`):
    the last 2 s, every 0.4 s, mean+max of tiny's encoder → a logistic regression.
    A phrase stays in view for several strides; the cooldown after a wake keeps
    it to one."""

    def __init__(self, path):
        import numpy as np
        from faster_whisper import WhisperModel
        z = np.load(path)
        self.np = np
        self.mean, self.scale, self.coef = z["mean"], z["scale"], z["coef"]
        self.intercept = float(z["intercept"])
        self.win = int(float(z["window_seconds"]) * 16000)
        self.keep = int(z["keep_frames"])
        self.m = WhisperModel(str(z["whisper_model"]), device="cpu", compute_type="int8", cpu_threads=2)
        self.fx = self.m.feature_extractor
        self.reset()

    def reset(self):
        self.buf = self.np.zeros(0, self.np.int16)
        self.since = 0

    def feed(self, chunk):
        np = self.np
        self.buf = np.concatenate([self.buf, chunk])[-self.win:]
        self.since += len(chunk)
        if self.since < 6400 or len(self.buf) < self.win:
            return None
        self.since = 0
        mel = self.fx(self.buf.astype(np.float32) / 32768.0)[..., : self.fx.nb_max_frames]
        out = np.array(self.m.encode(mel))[0][: self.keep]
        v = np.concatenate([out.mean(0), out.max(0)])
        z = float(((v - self.mean) / self.scale) @ self.coef + self.intercept)
        return 1 / (1 + math.exp(-z))


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--model", default="", help="an openWakeWord .onnx (\"hey claude\")")
    p.add_argument("--threshold", type=float, default=0.5)
    p.add_argument("--whisper-wake", default="", help="a Whisper-encoder wake word .npz (\"hey santa\")")
    p.add_argument("--whisper-threshold", type=float, default=0.6)
    p.add_argument("--device", default="", help="a substring of the input's name; empty = system default")
    p.add_argument("--silence-s", type=float, default=1.2)
    p.add_argument("--no-speech-s", type=float, default=6.0)
    p.add_argument("--max-command-s", type=float, default=60.0)
    p.add_argument("--cooldown-s", type=float, default=1.5)
    p.add_argument("--min-voiced-s", type=float, default=0.6)
    p.add_argument("--ignore-s", type=float, default=0.25, help="the wake word's own tail, not speech")
    p.add_argument("--head-s", type=float, default=4.0)
    p.add_argument("--head", default=os.path.expanduser("~/.walkie-talkie/wake/head.wav"))
    p.add_argument("--triggers", default=os.path.expanduser("~/.walkie-talkie/wake/santa/triggers"),
                   help="keep each wake's audio here; empty = keep nothing")
    p.add_argument("--triggers-keep", type=int, default=2000)
    p.add_argument("--hold", default=os.path.expanduser("~/.walkie-talkie/wake/hold"))
    p.add_argument("--wav", default="", help="read this 16 kHz file instead of a microphone (tests)")
    a = p.parse_args()

    import numpy as np
    from openwakeword.model import Model

    model = Model(wakeword_models=[a.model], inference_framework="onnx") if a.model else None
    key = list(model.models.keys())[0] if model else None
    whisper = WhisperWake(a.whisper_wake) if a.whisper_wake else None
    if not model and not whisper:
        say(event="error", error="no wake word model given")
        return 2
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
    voiced_s = 0.0
    head: list = []
    cooldown_until = 0.0

    def write_head():
        import wave
        try:
            os.makedirs(os.path.dirname(a.head), exist_ok=True)
            tmp = a.head + ".tmp"
            with wave.open(tmp, "wb") as w:
                w.setnchannels(1)
                w.setsampwidth(2)
                w.setframerate(16000)
                w.writeframes(np.concatenate(head).tobytes() if head else b"")
            os.replace(tmp, a.head)
            return a.head
        except Exception as e:
            say(event="error", error=f"head: {e}")
            return None

    ring: "collections.deque" = collections.deque(maxlen=38)   # 3.04 s of 80 ms chunks
    trigger = None            # the wake whose second after it is still arriving

    def held():
        try:
            return time.time() - os.stat(a.hold).st_mtime < 5
        except OSError:
            return False

    def write_trigger(t):
        import wave
        try:
            os.makedirs(a.triggers, exist_ok=True)
            base = os.path.join(a.triggers, t["id"])
            with wave.open(base + ".wav", "wb") as w:
                w.setnchannels(1)
                w.setsampwidth(2)
                w.setframerate(16000)
                w.writeframes(np.concatenate(t["pre"] + t["post"]).tobytes())
            with open(base + ".json", "w") as f:
                json.dump(dict(word=t["word"], score=t["score"], window_end=sum(len(c) for c in t["pre"])), f)
            old = sorted(n for n in os.listdir(a.triggers) if n.endswith(".wav"))[:-a.triggers_keep]
            for n in old:
                for ext in (".wav", ".json", ".txt"):
                    try:
                        os.remove(os.path.join(a.triggers, n[:-4] + ext))
                    except OSError:
                        pass
        except Exception as e:
            say(event="error", error=f"trigger: {e}")

    def end(after, capped=False):
        nonlocal mode, cooldown_until
        mode, cooldown_until = "wake", clock + a.cooldown_s
        if voiced_s < a.min_voiced_s:
            say(event="timeout", voiced=round(voiced_s, 2))
            return
        ev = dict(event="silence", after=round(after, 2), voiced=round(voiced_s, 2), head=write_head())
        if capped:
            ev["capped"] = True
        say(**ev)
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
        ring.append(chunk)
        if trigger is not None:
            trigger["post"].append(chunk)
            if len(trigger["post"]) >= 13:   # ~1 s after the wake
                write_trigger(trigger)
                trigger = None

        if mode == "wake":
            hit = None
            if model:
                score = float(model.predict(chunk)[key])
                if score >= a.threshold:
                    hit = ("hey claude", score)
            if whisper:
                score = whisper.feed(chunk)
                if score is not None and score >= a.whisper_threshold and hit is None:
                    hit = ("hey santa", score)
            if hit and not paused.is_set() and clock >= cooldown_until and not held():
                # The wake's name: its audio's file here, its outcome's line in the
                # app's `outcomes.jsonl` (silent / cancelled / session / question).
                wake_id = "%s-%s-%.2f" % (time.strftime("%Y%m%d-%H%M%S"), hit[0].split()[-1], hit[1])
                say(event="wake", score=round(hit[1], 3), word=hit[0], id=wake_id)
                if a.triggers:
                    # The chunk that fired is the ring's last: the scored window ends here.
                    trigger = dict(id=wake_id, word=hit[0], score=round(hit[1], 3), pre=list(ring), post=[])
                mode, woke_at, voiced_at, heard, voiced_s, head = "command", clock, None, False, 0.0, []
                if model:
                    model.reset()
                if whisper:
                    whisper.reset()
        elif mode == "command":
            if clock - woke_at <= a.head_s:
                head.append(chunk)
            if voiced and clock - woke_at > a.ignore_s:
                voiced_s += len(chunk) / 16000
                if not heard:
                    say(event="speech")
                heard, voiced_at = True, clock
            if heard and voiced_at is not None and clock - voiced_at >= a.silence_s:
                end(clock - voiced_at)
            elif not heard and clock - woke_at >= a.no_speech_s:
                end(0)
            elif clock - woke_at >= a.max_command_s:
                end(0, capped=True)

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
