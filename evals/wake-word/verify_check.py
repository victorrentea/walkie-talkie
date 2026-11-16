#!/usr/bin/env python3
"""Would a small Whisper *decode* of the last 3 s confirm a wake? (2026-11-16)

The detectors fire on talk (37 of the 41 wakes kept in `santa/triggers/` are false,
0.60–1.00 — no threshold separates them). This asks whether transcribing the audio
the detector fired on, and requiring the phrase's word in the text, separates them —
and with which model size, at what cost.

    POST=0.4 ONLY=prompt ~/.walkie-talkie/wake/venv/bin/python3 -I evals/wake-word/verify_check.py base

`POST` = seconds awaited after the hit, `ONLY` = `no prompt,prompt,hotwords`, `SHOW` = how many
misses to print, `ALL=<set>` prints every text of a set, `TEACH` = teaching windows (300).

Sets: the live triggers (the 3 s before the wake; truth = the mlx large-turbo label
beside each, `train_whisper_wake.py --triggers`), his 30 takes of *Hey Santa*
(`santa/real/`), and `say` positives of each phrase.
"""
import glob
import json
import os
import random
import re
import statistics
import sys
import time
import wave

import numpy as np
from faster_whisper import WhisperModel

HOME = os.path.expanduser("~/.walkie-talkie/wake")
POST = float(os.environ.get("POST", "0"))      # seconds of audio after the hit the decode waits for
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "helpers"))
from wake_word import CONFIRM, HINT  # noqa: E402  the helper's own patterns


SAID = re.compile(r"santa|gep+et+o|claude", re.I)


def load(path, end=None):
    with wave.open(path) as w:
        a = np.frombuffer(w.readframes(w.getnframes()), np.int16)
    if end is not None:
        end = min(len(a), end + int(POST * 16000))
        a = a[max(0, end - 48640):end]
    return a.astype(np.float32) / 32768.0


def sets():
    out = []  # (set, word, said?, audio)
    for f in sorted(glob.glob(HOME + "/santa/triggers/*.wav")):
        meta = json.load(open(f[:-4] + ".json"))
        txt = open(f[:-4] + ".txt").read() if os.path.exists(f[:-4] + ".txt") else ""
        word = meta["word"]
        said = bool(SAID.search(txt))     # the large model's label: the word is in it
        out.append(("trigger-said" if said else "trigger-false", word, said, load(f, meta.get("window_end"))))
    for f in sorted(glob.glob(HOME + "/santa/real/*.wav")):
        out.append(("his-takes", "hey santa", True, load(f)))
    random.seed(0)
    for data, word in (("santa", "hey santa"), ("gepetto", "hey gepetto")):
        for f in random.sample(sorted(glob.glob(f"{HOME}/{data}/pos/*.wav")), 60):
            out.append((f"say-{data}", word, True, load(f)))
    # Him teaching (the held-out days): 3 s windows with a voice in them — does the hint
    # make the decode *invent* a wake word? Any of the three counts.
    files = sorted(glob.glob(os.path.expanduser("~/.walkie-talkie/voice-corpus/mic/2026-09-1[467]/*.wav")))
    n = 0
    for f in random.sample(files, len(files)):
        a = load(f)
        if len(a) < 48000 * 2:
            continue
        i = random.randrange(0, len(a) - 48000)
        w = a[i:i + 48000]
        if np.sqrt((w ** 2).mean()) * 32768 < 300:
            continue
        out.append(("teaching", None, False, w))
        n += 1
        if n >= int(os.environ.get("TEACH", "300")):
            break
    return out


def main():
    data = sets()
    prompts = {"no prompt": dict(), "prompt": dict(initial_prompt=HINT), "hotwords": dict(hotwords="Santa Gepetto Claude")}
    only = os.environ.get("ONLY")
    if only:
        prompts = {k: v for k, v in prompts.items() if k in only.split(",")}
    for size in sys.argv[1:] or ["tiny", "base", "small"]:
        m = WhisperModel(size, device="cpu", compute_type="int8", cpu_threads=4)
        for pname, prompt in prompts.items():
            res, times, misses, leaks = {}, [], [], []
            for name, word, said, audio in data:
                t = time.time()
                segs, _ = m.transcribe(audio, language="en", beam_size=1, temperature=0.0,
                                       condition_on_previous_text=False, without_timestamps=True, **prompt)
                text = " ".join(s.text for s in segs).strip()
                times.append(time.time() - t)
                ok = bool(CONFIRM[word].search(text)) if word else any(r.search(text) for r in CONFIRM.values())
                if os.environ.get("ALL") and name in os.environ["ALL"]:
                    print("     ", name, "|", text[:90])
                a = res.setdefault(name, [0, 0])
                a[0] += ok
                a[1] += 1
                if said and not ok and name in ("his-takes", "trigger-said", "say-gepetto"):
                    misses.append(text)
                if not said and ok:
                    leaks.append(text)
            print(f"{size:6s} {pname:9s} " + "  ".join(f"{k} {v[0]}/{v[1]}" for k, v in sorted(res.items()))
                  + f"  | decode median {statistics.median(times):.2f}s max {max(times):.2f}s")
            for t in misses[:int(os.environ.get("SHOW", "8"))]:
                print("      missed:", t[:80])
            for t in leaks[:8]:
                print("      leaked:", t[:80])


if __name__ == "__main__":
    main()
