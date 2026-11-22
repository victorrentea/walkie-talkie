#!/usr/bin/env python3
"""How many DISTINCT pictures per second a region of a recording shows (the recorder repeats frames at 30 fps).
    fpsprobe.py clip.mp4 start seconds x y w h      (pixels of the 1920x1080 clip)"""
import subprocess, sys, numpy as np
f, ss, t, x, y, w, h = sys.argv[1], *map(float, sys.argv[2:4]), *map(int, sys.argv[4:8])
raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-ss", str(ss), "-t", str(t), "-i", f, "-vf", f"crop={w}:{h}:{x}:{y},format=gray",
                      "-f", "rawvideo", "-"], capture_output=True).stdout
a = np.frombuffer(raw, np.uint8).reshape(-1, h, w).astype(np.int16)
d = np.abs(np.diff(a, axis=0)).mean(axis=(1, 2))
changed = d > 0.15
per_s = [int(changed[i:i + 30].sum()) for i in range(0, len(changed), 30)]
print(f"{f}: distinct frames per second {per_s}  (mean diff {d.mean():.2f})")
