#!/usr/bin/env python3
"""The crops on disk are whatever he worked on in the last day (a website, mostly), so code and
terminal text are thin. This cuts extra bands out of his own recent full frames whose front window
was a terminal or an IDE — real pixels, a box nobody dragged — and appends them to out/crops.jsonl
with "synthetic": true. Band sizes are drawn from the real crops' own sizes (≥ 300×60).

    python3 evals/crop-ocr/synth_mono.py [--n 14]
"""
import argparse, json, pathlib, random, re, subprocess

OUT = pathlib.Path(__file__).parent / "out"
OUTBOX = pathlib.Path.home() / ".walkie-talkie/outbox.jsonl"
APPS = ("Terminal", "Code", "IntelliJ IDEA", "iTerm2", "Xcode", "Cursor")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=14)
    a = ap.parse_args()
    random.seed(11)
    crops = [json.loads(l) for l in open(OUT / "crops.jsonl")]
    if any(c.get("synthetic") for c in crops):
        return print("already there")
    sizes = [(c["w"], c["h"]) for c in crops if c["w"] >= 300 and c["h"] >= 60]
    frames = {}
    for line in OUTBOX.read_text().splitlines()[-600:]:
        row = json.loads(line)
        for p in row.get("paths") or []:
            win = (row.get("sources") or {}).get(pathlib.Path(p).name) or ""
            if win.split(" — ")[0] in APPS and pathlib.Path(p).exists():
                frames[p] = win
    picks = random.sample(sorted(frames), min(a.n, len(frames)))
    with open(OUT / "crops.jsonl", "a") as f:
        for k, p in enumerate(picks):
            out = subprocess.run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", p], capture_output=True, text=True).stdout
            W = int(re.search(r"pixelWidth: (\d+)", out).group(1)); H = int(re.search(r"pixelHeight: (\d+)", out).group(1))
            w, h = random.choice(sizes)
            w, h = min(w, W // 2), min(h, H // 3)
            x = random.randint(W // 8, W - w - W // 8); y = random.randint(H // 6, H - h - H // 6)
            cid = f"mono_{k:02d}"
            dest = OUT / "crops" / f"{cid}.jpg"
            subprocess.run(["sips", "-c", str(h), str(w), "--cropOffset", str(y), str(x), p, "--out", str(dest)],
                           capture_output=True, check=True)
            f.write(json.dumps({"id": cid, "src": p, "file": str(dest), "n": 0, "w": w, "h": h, "synthetic": True,
                                "app": frames[p].split(" — ")[0], "window": frames[p]}, ensure_ascii=False) + "\n")
    print(len(picks), "bands cut")


if __name__ == "__main__":
    main()
