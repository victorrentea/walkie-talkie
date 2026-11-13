#!/usr/bin/env python3
"""Record his own takes of the wake phrase (2026-11-13).

    ~/.walkie-talkie/wake/venv/bin/python3 -I evals/wake-word/record_takes.py [-n 30] [--device "Elgato"]

A beep, 2.5 s of microphone, the next beep. Say "Hey Santa" once after each beep,
the way you would say it for real — vary it: near, far, quiet, fast, mid-thought.
Takes land in ~/.walkie-talkie/wake/santa/real/ as `Victor-…wav`; every fourth is
`VictorEval-…wav`, which the trainer holds out to measure recall on his voice.
While it runs it touches ~/.walkie-talkie/wake/hold, so the live wake word stays
quiet. A take with no voice in it is thrown away and asked again.
"""
import argparse
import os
import sys
import threading
import time
import wave

import numpy as np
import sounddevice as sd

RATE = 16000
HOME = os.path.expanduser("~/.walkie-talkie/wake")


def beep(freq=880, ms=120):
    t = np.arange(int(RATE * ms / 1000)) / RATE
    sd.play((0.2 * np.sin(2 * np.pi * freq * t)).astype(np.float32), RATE, blocking=True)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("-n", type=int, default=30)
    p.add_argument("--device", default="", help="a substring of the input's name; empty = system default")
    p.add_argument("--phrase", default="Hey Santa")
    p.add_argument("--out", default=os.path.join(HOME, "santa", "real"))
    a = p.parse_args()
    device = None
    if a.device:
        for i, d in enumerate(sd.query_devices()):
            if d["max_input_channels"] > 0 and a.device.lower() in d["name"].lower():
                device = i
                break
    os.makedirs(a.out, exist_ok=True)
    stop = threading.Event()

    def hold():
        while not stop.is_set():
            with open(os.path.join(HOME, "hold"), "w"):
                pass
            time.sleep(1)

    threading.Thread(target=hold, daemon=True).start()
    time.sleep(0.2)
    name = sd.query_devices(device if device is not None else sd.default.device[0])["name"]
    print(f'Microphone: {name}. Say "{a.phrase}" once after each beep. Ctrl-C stops.')
    stamp = time.strftime("%Y%m%d-%H%M%S")
    done = 0
    try:
        while done < a.n:
            beep()
            take = sd.rec(int(2.5 * RATE), samplerate=RATE, channels=1, dtype="int16", device=device, blocking=True)[:, 0]
            f = take[: len(take) // 320 * 320].reshape(-1, 320).astype(np.float64)
            e = np.sqrt((f ** 2).mean(1))
            if e.max() < 300 or (e > max(e.max() * 0.1, 60)).sum() < 10:
                print("   nothing heard — again")
                continue
            done += 1
            who = "VictorEval" if done % 4 == 0 else "Victor"
            path = os.path.join(a.out, f"{who}-{stamp}-{done:02d}.wav")
            with wave.open(path, "wb") as w:
                w.setnchannels(1)
                w.setsampwidth(2)
                w.setframerate(RATE)
                w.writeframes(take.tobytes())
            print(f"   {done}/{a.n}")
    except KeyboardInterrupt:
        pass
    finally:
        stop.set()
        try:
            os.remove(os.path.join(HOME, "hold"))
        except OSError:
            pass
    beep(1320, 200)
    print(f"{done} takes in {a.out} — retrain: ~/.walkie-talkie/wake/venv/bin/python3 -I evals/wake-word/train_whisper_wake.py")
    return 0


if __name__ == "__main__":
    sys.exit(main())
