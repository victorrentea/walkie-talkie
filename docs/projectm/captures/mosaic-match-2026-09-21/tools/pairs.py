#!/usr/bin/env python3
"""Every pair of recordings: mean per-frame |lum diff| (aligned on first lit frame) and the
correlation of the mean-luminance series; then the mean per group of pairs."""
import sys, json, itertools, numpy as np, glob
from PIL import Image
REC = sys.argv[1]; TAGS = sys.argv[2:]; SIDE = 540
def first_lit(rows): return next((i for i, r in enumerate(rows) if r["lit"] > 0.01), 0)
M = {t: json.load(open(f"{REC}/{t}.measure.json")) for t in TAGS}
F = {t: sorted(glob.glob(f"{REC}/frames-{t}/*.png")) for t in TAGS}
G = {t: None for t in TAGS}
def gray(t, i):
    return np.array(Image.open(F[t][i]).convert("L")).astype(float)[int(SIDE * .06):int(SIDE * .94), int(SIDE * .06):int(SIDE * .94)]
def group(t): return "web" if t.startswith("web") else "bc" if t.startswith("bc") else "rs" if t.startswith("rs") else "native"
res = {}
for a, b in itertools.combinations(TAGS, 2):
    sa, sb = first_lit(M[a]), first_lit(M[b]); n = min(len(M[a]) - sa, len(M[b]) - sb, 240)
    la = np.array([M[a][sa + i]["lum"] for i in range(n)]); lb = np.array([M[b][sb + i]["lum"] for i in range(n)])
    d = np.mean([np.abs(gray(a, sa + i) - gray(b, sb + i)).mean() for i in range(0, n, 3)])
    res[(a, b)] = (d, np.corrcoef(la, lb)[0, 1])
    print(f"{a:8s} vs {b:8s}: per-frame |diff| {d:5.2f}, lum corr {res[(a, b)][1]:.2f}")
print("\n| pair group | pairs | mean per-frame |diff| | mean lum corr |\n|---|---|---|---|")
groups = {}
for (a, b), v in res.items(): groups.setdefault(tuple(sorted((group(a), group(b)))), []).append(v)
for g, vs in sorted(groups.items()):
    print(f"| {g[0]}–{g[1]} | {len(vs)} | {np.mean([v[0] for v in vs]):.2f} | {np.mean([v[1] for v in vs]):.2f} |")
