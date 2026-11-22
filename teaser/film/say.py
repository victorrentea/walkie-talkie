#!/usr/bin/python3
"""Guest: play WAVs (48 kHz stereo) into BlackHole 2ch — the lab's microphone. No speaker anywhere.
    say.py <wav> [delay seconds]
    say.py --at <epoch> <wav>@<s> [<wav>@<s> …]    one stream: each file's audio starts s seconds after the epoch
       (the imports take ~2 s, so a take that must put a word on a gesture launches this early and names the instant)"""
import sys, time
import numpy as np
import sounddevice as sd
from scipy.io import wavfile
idx = [i for i, d in enumerate(sd.query_devices()) if "BlackHole 2ch" in d["name"] and d["max_output_channels"] >= 2][0]
if sys.argv[1] == "--at":
    parts = [(wavfile.read(a.split("@")[0]), float(a.split("@")[1])) for a in sys.argv[3:]]
    rate = parts[0][0][0]; first = min(s for _, s in parts)
    mix = np.zeros((int((max(s + len(d) / rate for (_, d), s in parts) - first) * rate) + 1, 2), np.float32)
    for (_, d), s in parts:
        i = int((s - first) * rate); mix[i:i + len(d)] += d.astype(np.float32) / 32768
    time.sleep(max(0, float(sys.argv[2]) + first - time.time()))
    sd.play(mix, rate, device=idx, blocking=True)
else:
    rate, data = wavfile.read(sys.argv[1])
    if len(sys.argv) > 2: time.sleep(float(sys.argv[2]))
    sd.play(data, rate, device=idx, blocking=True)
