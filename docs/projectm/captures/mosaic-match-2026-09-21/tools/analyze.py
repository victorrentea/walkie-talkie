#!/usr/bin/env python3
"""Per-frame measurements of the Mosaic recordings and pairwise comparisons.
usage: analyze.py <recdir> <outdir> <tag> [<tag> ...]      (the first tag is the reference)
Per recording: frames at 30 fps (ffmpeg), then per frame mean luminance, lit fraction, tile
period (autocorrelation of the column-mean luminance over the lit part; q27 ~ period/(209/scale)),
mean hue and saturation of the lit part. Recordings are aligned on their first lit frame.
Pairwise (each tag vs the reference and each vs the previous of the same route): per-frame mean
|difference| of luminance, correlation of the tile-period series, per-frame tile-period agreement."""
import sys, os, subprocess, glob, json
from PIL import Image, ImageDraw
import numpy as np
REC, OUT, TAGS = sys.argv[1], sys.argv[2], sys.argv[3:]
os.makedirs(OUT, exist_ok=True)
FPS = 30; SIDE = 540   # analysis size (device px / 4: the region is 1080 pt = 2160 px)
def frames(tag):
    fdir = f"{REC}/frames-{tag}"; os.makedirs(fdir, exist_ok=True)
    if not glob.glob(f"{fdir}/*.png"):
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", f"{REC}/{tag}.mov", "-vf", f"fps={FPS},scale={SIDE}:{SIDE}", f"{fdir}/f%04d.png"], check=True)
    return sorted(glob.glob(f"{fdir}/*.png"))
def period(y):
    lit = y > 20
    if lit.mean() < 0.01: return 0
    ys, xs = np.where(lit); y0, y1, x0, x1 = ys.min(), ys.max(), xs.min(), xs.max()
    if x1 - x0 < 40 or y1 - y0 < 10: return 0
    sig = y[y0:y1, x0:x1].mean(0); sig = sig - sig.mean()
    ac = np.correlate(sig, sig, "full")[len(sig) - 1:]; ac /= ac[0] if ac[0] else 1
    for i in range(3, len(ac) - 1):
        if ac[i] > ac[i - 1] and ac[i] >= ac[i + 1] and ac[i] > 0.1: return i
    return 0
def measure(tag):
    cache = f"{REC}/{tag}.measure.json"
    if os.path.exists(cache): return json.load(open(cache))
    rows = []
    for f in frames(tag):
        im = Image.open(f).convert("RGB"); im = im.crop((int(SIDE * 0.06), int(SIDE * 0.06), int(SIDE * 0.94), int(SIDE * 0.94))); a = np.array(im).astype(float)
        a[SIDE // 2 - 40:SIDE // 2 - 5, SIDE // 2 - 40:SIDE // 2 - 5] = 0   # the pointer (centre of the uncropped frame, drawn down-right of the tip)
        y = 0.2126 * a[..., 0] + 0.7152 * a[..., 1] + 0.0722 * a[..., 2]
        hsv = np.array(im.convert("HSV")).astype(float); lit = y > 20
        rows.append(dict(lum=float(y.mean()), lit=float(lit.mean()), period=int(period(y)),
                         hue=float(hsv[..., 0][lit].mean()) if lit.any() else 0, sat=float(hsv[..., 1][lit].mean()) if lit.any() else 0))
    json.dump(rows, open(cache, "w")); return rows
M = {t: measure(t) for t in TAGS}
def first_lit(rows): return next((i for i, r in enumerate(rows) if r["lit"] > 0.01), 0)
def series(rows, key, start, n): return np.array([rows[i][key] if i < len(rows) else np.nan for i in range(start, start + n)])
print(f"| tag | frames | first lit | mean lum | lit % | tile period median (px@{SIDE}) | period changes |")
print("|---|---|---|---|---|---|---|")
N = min(len(M[t]) - first_lit(M[t]) for t in TAGS)
for t in TAGS:
    r = M[t]; s = first_lit(r); per = series(r, "period", s, N); per = per[per > 0]
    changes = int((np.abs(np.diff(per)) > 1).sum()) if per.size > 1 else 0
    print(f"| {t} | {len(r)} | f{s} | {series(r, 'lum', s, N).mean():.1f} | {series(r, 'lit', s, N).mean() * 100:.0f} | {np.median(per) if per.size else 0:.0f} | {changes} |")
print("\n| pair | frames | mean per-frame abs lum diff | lum corr | period corr | period agrees (±1 px) % | hue diff | sat diff |")
print("|---|---|---|---|---|---|---|---|")
def pair(a, b):
    ra, rb = M[a], M[b]; sa, sb = first_lit(ra), first_lit(rb); n = min(len(ra) - sa, len(rb) - sb)
    la, lb = series(ra, "lum", sa, n), series(rb, "lum", sb, n); pa, pb = series(ra, "period", sa, n), series(rb, "period", sb, n)
    ok = (pa > 0) & (pb > 0)
    # per-frame image difference
    fa, fb = frames(a)[sa:sa + n], frames(b)[sb:sb + n]; d = []
    for x, y in zip(fa, fb):
        m = slice(int(SIDE * 0.06), int(SIDE * 0.94))
        d.append(np.abs(np.array(Image.open(x).convert("L")).astype(float)[m, m] - np.array(Image.open(y).convert("L")).astype(float)[m, m]).mean())
    print(f"| {a} vs {b} | {n} | {np.mean(d):.2f} | {np.corrcoef(la, lb)[0, 1]:.2f} | {np.corrcoef(pa[ok], pb[ok])[0, 1] if ok.sum() > 2 else 0:.2f} | "
          f"{(np.abs(pa[ok] - pb[ok]) <= 1).mean() * 100 if ok.any() else 0:.0f} | {np.abs(series(ra, 'hue', sa, n) - series(rb, 'hue', sb, n)).mean():.1f} | {np.abs(series(ra, 'sat', sa, n) - series(rb, 'sat', sb, n)).mean():.1f} |")
    return n
for t in TAGS[1:]: pair(TAGS[0], t)
for i in range(2, len(TAGS)): pair(TAGS[i - 1], TAGS[i])
# timeline: luminance and period per tag, aligned
H = 90; tl = Image.new("RGB", (N * 3, H * len(TAGS)), (18, 18, 18)); dr = ImageDraw.Draw(tl)
for k, t in enumerate(TAGS):
    r = M[t]; s = first_lit(r); lum = series(r, "lum", s, N); per = series(r, "period", s, N)
    for i in range(N):
        y0 = H * (k + 1) - 1
        dr.line((i * 3, y0, i * 3, y0 - int(min(H - 12, lum[i] * 1.2))), fill=(90, 160, 255))
        if per[i] > 0: dr.line((i * 3 + 1, y0, i * 3 + 1, y0 - int(min(H - 12, per[i] * 1.5))), fill=(255, 140, 60))
    dr.text((3, H * k + 1), f"{t}: blue mean luminance x1.2, orange tile period x1.5 ({N} frames @30 fps from first lit frame)", fill=(255, 255, 255))
tl.save(f"{OUT}/timeline.png", optimize=True)
# contact sheet: every 30th frame (1 s), one row per tag
cols = N // FPS; cs = Image.new("RGB", (160 * cols, 160 * len(TAGS) + 14), (0, 0, 0)); dr = ImageDraw.Draw(cs)
for k, t in enumerate(TAGS):
    fs = frames(t); s = first_lit(M[t])
    for c in range(cols):
        i = s + c * FPS
        if i < len(fs): cs.paste(Image.open(fs[i]).convert("RGB").resize((160, 160), Image.LANCZOS), (160 * c, 14 + 160 * k))
    dr.text((2, 14 + 160 * k), t, fill=(255, 255, 255))
for c in range(cols): dr.text((160 * c + 2, 1), f"+{c} s", fill=(255, 255, 255))
cs.save(f"{OUT}/sheet.png", optimize=True)
print(f"\nwrote {OUT}/timeline.png and {OUT}/sheet.png")
