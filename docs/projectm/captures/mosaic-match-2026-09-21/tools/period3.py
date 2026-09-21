#!/usr/bin/env python3
"""Tile period per frame: the lattice's seams isolated by a high-pass (luminance minus its
Gaussian blur), restricted to the lit part of the centre crop; the radial profile of the 2-D
autocorrelation of that; the first peak beyond 12 px is the period T (q27 ~ 209/T).
usage: period3.py <recdir> <tag>... [--debug f]"""
import sys, os, glob, json, subprocess, numpy as np
from PIL import Image, ImageFilter
REC = sys.argv[1]; TAGS = [a for a in sys.argv[2:] if not a.startswith("--")]; FPS = 30; C = 768
def frames(tag):
    d = f"{REC}/centre-{tag}"; os.makedirs(d, exist_ok=True)
    if not glob.glob(f"{d}/*.png"):
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", f"{REC}/{tag}.mov", "-vf", f"fps={FPS},crop={C}:{C}:{(2160 - C) // 2}:{(2160 - C) // 2}", f"{d}/f%04d.png"], check=True)
    return sorted(glob.glob(f"{d}/*.png"))
yy, xx = np.mgrid[:C, :C]; rr = np.hypot(yy - C / 2, xx - C / 2).astype(int)
def period(f, debug=None):
    im = Image.open(f).convert("L"); a = np.array(im).astype(float)
    a[360:460, 360:460] = 0                      # the pointer, warped to the centre
    lit = a > 18
    if lit.mean() < 0.01: return 0, 0.0
    hp = a - np.array(im.filter(ImageFilter.GaussianBlur(8))).astype(float)
    hp = hp * lit
    F = np.fft.fft2(hp - hp.mean()); ac = np.real(np.fft.ifft2(np.abs(F) ** 2)); ac = np.fft.fftshift(ac) / ac.flat[0]
    rad = np.bincount(rr.ravel(), ac.ravel()) / np.maximum(1, np.bincount(rr.ravel()))
    r = rad[:C // 3]
    # first local max beyond 12 px that is above its surroundings
    T, h = 0, 0.0   # first local maximum beyond 22 px with prominence >= 0.012 over the dip before it
    for i in range(22, len(r) - 2):
        if r[i] > r[i - 1] and r[i] >= r[i + 1] and r[i] - r[22:i + 1].min() >= 0.012: T, h = i, float(r[i] - r[22:i + 1].min()); break
    if debug:
        d = np.clip(hp * 4 + 128, 0, 255).astype(np.uint8); Image.fromarray(d).save(debug)
    return T, h
if "--debug" in sys.argv:
    f = sys.argv[sys.argv.index("--debug") + 1]; print(f, period(f, debug=f + ".hp.png")); sys.exit()
for t in TAGS:
    rows = [period(f) for f in frames(t)]
    json.dump(rows, open(f"{REC}/{t}.period3.json", "w"))
    per = np.array([p for p, _ in rows])
    print(f"{t}: T per 0.5 s (device px): " + " ".join(f"{per[i]:.0f}" for i in range(0, len(per), 15)))
