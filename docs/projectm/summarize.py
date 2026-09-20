#!/usr/bin/env python3
"""Turn a sweep folder (docs/projectm/sweep.sh) into the REPORT's table and the
side-by-side captures: python3 docs/projectm/summarize.py <sweepdir> <capturesdir>"""
import re, sys, os, glob
from collections import defaultdict
SW, CAP = sys.argv[1], sys.argv[2]
os.makedirs(CAP, exist_ok=True)
NAMES = {"milkdrop7": "Tunnel", "milkdrop8": "Cauldron", "milkdrop20": "Tendrils", "milkdrop85": "Snowflake",
         "milkdrop87": "Sparks", "milkdrop103": "Water Dream", "film": "film (lightning)"}

def stats(tag):
    p = f"{SW}/{tag}.stats"
    if not os.path.exists(p): return None
    lines = open(p).read().splitlines()
    head = {}
    for part in re.findall(r"(\w+)=([^=]*?)(?=\s\w+=|$)", lines[0]): head[part[0]] = part[1].strip()
    app, ws = head.get("app"), head.get("windowserver")
    gpus = set(head.get("gpu", "").split())
    base = {}
    cpu = defaultdict(list); rss = {}; name = {}
    for l in lines[1:]:
        m = re.match(r"^base (\d+) ([\d.]+)$", l)
        if m: base[m.group(1)] = float(m.group(2)); continue
        m = re.match(r"^(\d+)\s+([\d.]+)\s+(\S+)\s+(.*)$", l)
        if m:
            pid, c, r, cmd = m.groups()
            cpu[pid].append(float(c)); name[pid] = cmd.strip()
            rss[pid] = r
        m = re.match(r"^rss (\d+) (\d+)MB (.*)$", l)
        if m: rss[m.group(1)] = m.group(2) + "M"
    def mb(r):
        if r is None: return None
        r = str(r)
        if r.endswith("M"): return float(r[:-1].replace("+", "").replace("-", ""))
        if r.endswith("G"): return float(r[:-1].replace("+", "").replace("-", "")) * 1024
        if r.endswith("K"): return float(r[:-1].replace("+", "").replace("-", "")) / 1024
        return float(r)
    def avg(pid): v = cpu.get(pid, []); v = v[1:] if len(v) > 1 else v; return sum(v) / len(v) if v else None
    out = {"app_cpu": avg(app), "app_rss": mb(rss.get(app)), "ws_cpu": avg(ws), "web_cpu": 0.0, "gpu_cpu": 0.0, "web_rss": 0.0, "gpu_rss": 0.0, "webkit": 0}
    for pid in cpu:
        if pid in (app, ws): continue
        out["webkit"] += 1
        key = "gpu" if pid in gpus else "web"
        # the shared GPU process: what it did during the run, less what it was doing before
        out[key + "_cpu"] += max(0.0, (avg(pid) or 0) - base.get(pid, 0.0))
        out[key + "_rss"] += mb(rss.get(pid)) or 0
    log = open(f"{SW}/{tag}.log").read() if os.path.exists(f"{SW}/{tag}.log") else ""
    m = re.findall(r"engine ([\d.]+) ms \+ key ([\d.]+) ms", log)
    out["frame_ms"] = (sum(float(a) + float(b) for a, b in m) / len(m)) if m else None
    out["failed"] = "falling back to the film" in log
    return out

def f(v, d=1): return "—" if v is None else f"{v:.{d}f}"
rows = []
rows.append("| preset | route | app CPU % | WebContent CPU % | WebKit GPU CPU % | WindowServer CPU % | app RSS MB | WebContent RSS MB | GPU proc RSS MB | native frame ms (CPU) |")
rows.append("|---|---|---|---|---|---|---|---|---|---|")
for tag in ["film"] + [f"{s}-{r}" for s in ["milkdrop7", "milkdrop8", "milkdrop20", "milkdrop85", "milkdrop87", "milkdrop103"] for r in ["web", "native1", "native2"]]:
    st = stats(tag)
    if not st: continue
    style, _, route = tag.partition("-")
    route = {"web": "web (butterchurn, 2×)", "native1": "native 1×", "native2": "native 2×", "": "—"}[route]
    fail = " **(fell back to the film)**" if st["failed"] else ""
    rows.append(f"| {NAMES.get(style, style)} | {route}{fail} | {f(st['app_cpu'])} | {f(st['web_cpu'])} | {f(st['gpu_cpu'])} | {f(st['ws_cpu'])} | {f(st['app_rss'],0)} | {f(st['web_rss'],0)} | {f(st['gpu_rss'],0)} | {f(st['frame_ms'],2)} |")
print("\n".join(rows))

# side-by-side captures: crop 1000×1000 px round the pointer from each region capture, web | native1 | native2
try:
    from PIL import Image, ImageDraw
    import json
    MX, MY = [int(v) for v in os.environ.get("MOUSE_PX", "988,450").split(",")]
    for s in ["milkdrop7", "milkdrop8", "milkdrop20", "milkdrop85", "milkdrop87", "milkdrop103"]:
        for t in ["4.0", "5.5", "7.0"]:
            tiles = []
            for r in ["web", "native1", "native2"]:
                p = f"{SW}/{s}-{r}-{t}.png"
                if not os.path.exists(p): continue
                im = Image.open(p).convert("RGB")
                box = (max(0, MX - 500), max(0, MY - 500), max(0, MX - 500) + 1000, max(0, MY - 500) + 1000)
                tile = im.crop(box).resize((500, 500))
                d = ImageDraw.Draw(tile); d.rectangle((0, 0, 140, 22), fill=(0, 0, 0)); d.text((4, 4), f"{r} t={t}s", fill=(255, 255, 255))
                tiles.append(tile)
            if tiles:
                out = Image.new("RGB", (500 * len(tiles), 500))
                for i, tl in enumerate(tiles): out.paste(tl, (500 * i, 0))
                out.save(f"{CAP}/{NAMES[s].replace(' ', '-').lower()}-{t}s.png")
except ImportError:
    print("no PIL — captures not composed", file=sys.stderr)
