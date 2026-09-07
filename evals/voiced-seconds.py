"""Replays MicRecorder's proposed voiced-seconds meter over the whole corpus.

The Swift side sees one converted buffer at a time (16kHz mono int16). This
reproduces that exactly, at a fixed 1024-frame hop (64ms), so the constants it
produces are the constants that go into the app.
"""
import json, wave, sys
import numpy as np

ROOT = "/Users/victorrentea/.walkie-talkie/voice-corpus/"
HOP = 1024            # frames per "buffer"
SR  = 16000.0

def voiced_seconds(path, over_floor_db=9.0, absolute_floor=180.0):
    try:
        with wave.open(path, "rb") as w:
            if w.getsampwidth() != 2 or w.getnchannels() != 1: return None
            n = w.getnframes()
            if n < HOP: return 0.0
            raw = w.readframes(n)
    except Exception:
        return None
    x = np.frombuffer(raw, dtype="<i2").astype(np.float32)
    nb = len(x) // HOP
    if nb == 0: return 0.0
    frames = x[:nb*HOP].reshape(nb, HOP)
    rms = np.sqrt((frames*frames).mean(axis=1)) + 1e-6

    # Adaptive noise floor, exactly as the Swift will run it: instant attack
    # downward, slow release upward. Seeded on the first buffer.
    floor = rms[0]
    ratio = 10.0 ** (over_floor_db / 20.0)
    voiced = 0
    for r in rms:
        if r < floor: floor = r
        else: floor += (r - floor) * 0.02
        if r > max(absolute_floor, floor * ratio): voiced += 1
    return voiced * HOP / SR

rows = []
for line in open(ROOT + "corpus.jsonl"):
    try: d = json.loads(line)
    except: continue
    dur = d.get("duration") or 0
    if dur <= 0 or dur > 300: continue
    v = voiced_seconds(ROOT + d["wav"])
    if v is None: continue
    txt = (d.get("asr") or d.get("text") or "").strip()
    rows.append({"dur": dur, "voiced": v, "lang": d.get("detectedLanguage"),
                 "empty": not txt, "words": len(txt.split())})

print(f"read {len(rows)} samples\n")

def table(key, buckets, label):
    print(f"=== by {label} ===")
    print(f"{'bucket':>10} {'n':>5} {'%empty':>7} {'%foreign':>9} {'med dur':>8} {'med voiced':>11}")
    for lo, hi in buckets:
        b = [r for r in rows if lo <= r[key] < hi]
        if not b: continue
        ne = [r for r in b if not r["empty"]]
        foreign = sum(1 for r in ne if r["lang"] not in ("ro", "en", None))
        print(f"{lo:>4}-{hi:<5} {len(b):>5} {100*sum(r['empty'] for r in b)/len(b):>6.0f}% "
              f"{100*foreign/max(1,len(ne)):>8.0f}% "
              f"{np.median([r['dur'] for r in b]):>8.1f} {np.median([r['voiced'] for r in b]):>11.1f}")
    print()

B = [(0,1),(1,2),(2,3),(3,4),(4,5),(5,6),(6,8),(8,12),(12,20),(20,300)]
table("dur", B, "wall-clock duration (what the ramp uses today)")
table("voiced", B, "VOICED seconds (what it should use)")

v = np.array([r["voiced"] for r in rows]); d = np.array([r["dur"] for r in rows])
frac = v / np.maximum(d, .01)
print(f"voiced/elapsed: median {np.median(frac):.2f}, p10 {np.percentile(frac,10):.2f}, "
      f"p25 {np.percentile(frac,25):.2f}, p75 {np.percentile(frac,75):.2f}")
print(f"words per voiced second: median {np.median([r['words']/max(r['voiced'],.01) for r in rows if r['words']>3]):.2f}")
