#!/usr/bin/env python3
"""State-independent rendering statistics per recording, over the lit pixels of the centre crop
(768 px, pointer masked): lit share, mean luminance of the lit part, its 99th percentile, mean
saturation, mean hue, and the tile texture: the std of the high-pass (lum minus 8 px blur) over
the lit part, relative to the lit part's std. usage: aggregates.py <recdir> <tag>..."""
import sys, glob, numpy as np
from PIL import Image, ImageFilter
REC, TAGS = sys.argv[1], sys.argv[2:]
print("| run | lit % | lit mean lum | lit p99 lum | lit sat | lit hue | high-pass std / lit std | frames |")
print("|---|---|---|---|---|---|---|---|")
for t in TAGS:
    fs = sorted(glob.glob(f"{REC}/centre-{t}/*.png"))[30::3]
    lit_s, lum_s, p99_s, sat_s, hue_s, hp_s, n = [], [], [], [], [], [], 0
    for f in fs:
        im = Image.open(f).convert("RGB"); a = np.array(im).astype(float); a[360:460, 360:460] = 0
        y = 0.2126 * a[..., 0] + 0.7152 * a[..., 1] + 0.0722 * a[..., 2]; lit = y > 18
        if lit.mean() < 0.02: continue
        hsv = np.array(im.convert("HSV")).astype(float)
        hp = y - np.array(Image.fromarray(y.astype(np.uint8)).filter(ImageFilter.GaussianBlur(8))).astype(float)
        lit_s.append(lit.mean()); lum_s.append(y[lit].mean()); p99_s.append(np.percentile(y[lit], 99)); sat_s.append(hsv[..., 1][lit].mean()); hue_s.append(hsv[..., 0][lit].mean())
        hp_s.append(hp[lit].std() / (y[lit].std() or 1)); n += 1
    print(f"| {t} | {np.mean(lit_s) * 100:.1f} | {np.mean(lum_s):.1f} | {np.mean(p99_s):.0f} | {np.mean(sat_s):.0f} | {np.mean(hue_s):.0f} | {np.mean(hp_s):.2f} | {n} |")
