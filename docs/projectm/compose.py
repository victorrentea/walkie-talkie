#!/usr/bin/env python3
"""Side-by-side of the engine-only captures (docs/projectm/shoot.sh):
python3 docs/projectm/compose.py <shootdir> <capturesdir> — one PNG per preset,
web | native 1x | native 2x, each on a mid-grey ground and 600 px wide, plus the
per-image statistics the report quotes (lit fraction, mean brightness of the lit part)."""
import sys, os
from PIL import Image, ImageDraw
import numpy as np
SRC, DST = sys.argv[1], sys.argv[2]
os.makedirs(DST, exist_ok=True)
NAMES = {"milkdrop7": "tunnel", "milkdrop8": "cauldron", "milkdrop20": "tendrils", "milkdrop85": "snowflake", "milkdrop87": "sparks", "milkdrop103": "water-dream"}
print("| preset | route | px | lit % (alpha > 25), 3 s / 5 s / 7 s | mean alpha of the lit part, 3 / 5 / 7 s |")
print("|---|---|---|---|---|")
TIMES = ["3s", "5s", "7s"]
for s, name in NAMES.items():
    rows = []
    for r in ["web", "native1", "native2"]:
        tiles, lits, alphas, px = [], [], [], 0
        for t in TIMES:
            p = f"{SRC}/{s}-{r}-{t}.png"
            if not os.path.exists(p): continue
            im = Image.open(p).convert("RGBA"); px = im.width
            a = np.array(im).astype(float)
            lit = a[..., 3] > 25
            lits.append(f"{100 * lit.mean():.0f}"); alphas.append(f"{a[..., 3][lit].mean() if lit.any() else 0:.0f}")
            rgb = a[..., :3] + (1 - a[..., 3:4] / 255) * 96      # premultiplied, over grey 96
            tile = Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8)).resize((400, 400), Image.LANCZOS)
            d = ImageDraw.Draw(tile); d.rectangle((0, 0, 190, 16), fill=(0, 0, 0)); d.text((3, 2), f"{name} · {r} · {px}px · {t}", fill=(255, 255, 255))
            tiles.append(tile)
        if tiles:
            print(f"| {name} | {r} | {px} | {' / '.join(lits)} | {' / '.join(alphas)} |")
            rows.append(tiles)
    if rows:
        out = Image.new("RGB", (400 * len(TIMES), 400 * len(rows)), (96, 96, 96))
        for j, tiles in enumerate(rows):
            for i, t in enumerate(tiles): out.paste(t, (400 * i, 400 * j))
        out.save(f"{DST}/{name}.png", optimize=True)
