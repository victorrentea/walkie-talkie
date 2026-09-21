#!/usr/bin/env python3
"""Luminance of the engine-only captures: mean luminance of the premultiplied
output (= what is composited over black) and its 99th percentile, per
preset/route, averaged over the 3/5/7 s frames; web/native ratios."""
import sys, os
from PIL import Image
import numpy as np
SRC = sys.argv[1]
NAMES = {"milkdrop1": "bipolar", "milkdrop7": "tunnel", "milkdrop8": "cauldron", "milkdrop20": "tendrils", "milkdrop85": "snowflake", "milkdrop87": "sparks", "milkdrop103": "water-dream"}
def lum(p):
    a = np.array(Image.open(p).convert("RGBA")).astype(float)
    # The PNGs carry STRAIGHT alpha (ImageIO and canvas.toDataURL both
    # un-premultiply on write), so the light that reaches the screen over
    # black is rgb × alpha.
    y = (0.2126 * a[..., 0] + 0.7152 * a[..., 1] + 0.0722 * a[..., 2]) * a[..., 3] / 255
    return y.mean(), np.percentile(y, 99)
import json
RATIOS = {}
print("| preset | route | mean lum, 3…8 s | p99 lum, 3…8 s | mean of means | web/native |")
print("|---|---|---|---|---|---|")
for s, name in NAMES.items():
    ref = None
    for r in ["web", "native1", "native2"]:
        ms, ps = [], []
        for t in range(3, 9):
            p = f"{SRC}/{s}-{r}-{t}s.png"
            if os.path.exists(p): m, q = lum(p); ms.append(m); ps.append(q)
        if not ms: continue
        mm = sum(ms) / len(ms)
        if r == "web": ref = mm
        ratio = f"{ref / mm:.2f}" if ref and r != "web" else "—"
        if ref and r == "native1": RATIOS[s.replace("milkdrop", "")] = ref / mm
        print(f"| {name} | {r} | {' / '.join(f'{v:.1f}' for v in ms)} | {' / '.join(f'{v:.0f}' for v in ps)} | {mm:.1f} | {ratio} |")

if len(sys.argv) > 2: json.dump(RATIOS, open(sys.argv[2], "w"))
