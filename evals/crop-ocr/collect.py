#!/usr/bin/env python3
"""Snapshot the area cut-outs still in the shots cache into out/crops (gitignored: private screens)
and join each to its outbox row. Writes out/crops.jsonl: one row per crop.

    python3 evals/crop-ocr/collect.py
"""
import json, os, re, shutil, subprocess, pathlib

HERE = pathlib.Path(__file__).parent
OUT = HERE / "out"
SHOTS = pathlib.Path.home() / "Library/Caches/ro.victorrentea.wispr-relay/shots"
OUTBOX = pathlib.Path.home() / ".walkie-talkie/outbox.jsonl"
CUT = re.compile(r"screenshot-(\d+)(?:-\d+)?\.jpg$")          # the cut-out: no -original / -800px suffix
TOKEN = re.compile(r"📸(\d+)✂️(\d+),(\d+)→(\d+),(\d+)")


def size(path):
    out = subprocess.run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", str(path)],
                         capture_output=True, text=True).stdout
    w = int(re.search(r"pixelWidth: (\d+)", out).group(1))
    h = int(re.search(r"pixelHeight: (\d+)", out).group(1))
    return w, h


def main():
    (OUT / "crops").mkdir(parents=True, exist_ok=True)
    by_folder = {}                                             # shots folder -> [outbox rows]
    for line in OUTBOX.read_text().splitlines():
        if "✂️" not in line:
            continue
        row = json.loads(line)
        for p in row.get("paths") or []:
            by_folder.setdefault(os.path.dirname(p), []).append(row)
    rows = []
    for path in sorted(SHOTS.glob("*/screenshot-*.jpg")):
        m = CUT.search(path.name)
        if not m:
            continue
        n = int(m.group(1))
        w, h = size(path)
        cid = f"{path.parent.name}_{path.stem}"
        dest = OUT / "crops" / f"{cid}.jpg"
        if not dest.exists():
            shutil.copy2(path, dest)
        row = {"id": cid, "src": str(path), "file": str(dest), "n": n, "w": w, "h": h,
               "mtime": path.stat().st_mtime}
        # the outbox row whose paths name this frame's -original sibling
        orig = path.with_name(path.stem + "-original.jpg")
        for r in by_folder.get(str(path.parent), []):
            if str(orig) in (r.get("paths") or []):
                row.update(ts=r["ts"], to=(r.get("delivery") or {}).get("to"), app=r.get("app"),
                           window=(r.get("sources") or {}).get(orig.name),
                           areas=len(TOKEN.findall(r.get("line") or r.get("text") or "")),
                           line_chars=len(r.get("line") or ""))
                break
        o = size(orig) if orig.exists() else None
        if o:
            row.update(ow=o[0], oh=o[1])
        rows.append(row)
    with open(OUT / "crops.jsonl", "w") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    print(len(rows), "crops,", sum("ts" in r for r in rows), "joined to an outbox row")


if __name__ == "__main__":
    main()
