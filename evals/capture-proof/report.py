#!/usr/bin/env python3
"""Roll every scene up into one table: is anything Walkie drew in any frame?"""
import glob, json, os, sys
import numpy as np
from PIL import Image
from findsel import find
from analyse import counts, diff

rows, details = [], {}
for scene in sorted(glob.glob("out/*")):
    box, _ = find(f"{scene}/01-control.png")
    pointer = ((box[0] + box[2]) // 2, (box[1] + box[3]) // 2)
    film = json.load(open(f"{scene}/11-state-open.json"))
    frames = {
        "control (nothing open)": f"{scene}/01-control.png",
        "app's own shot": f"{scene}/20-app-shot.jpg",
        "handover copy (800px)": f"{scene}/21-app-shot-handover.jpg",
        "independent screencapture": f"{scene}/12-during.png",
        "film frame 5/20": f"{scene}/30-film-frame.jpg",
        "film contact sheet": f"{scene}/31-film-sheet.png",
    }
    for label, path in frames.items():
        if not os.path.exists(path):
            continue
        c = counts(path, pointer)
        rows.append((os.path.basename(scene), label, c["ring_pointer"], c["gold_pointer"],
                     c["red_pointer"], c["ring_frame"], c["gold_frame"], c["red_frame"]))
    details[scene] = {
        "pointer_px": list(pointer),
        "bound": bool(film.get("bound")),
        "ring_up": film.get("ringUp"),
        "listening": film.get("listening"),
        "chip": film.get("chip"),
        "diff_control_vs_during": diff(f"{scene}/01-control.png", f"{scene}/12-during.png"),
        "diff_control_vs_app_shot": diff(f"{scene}/01-control.png", f"{scene}/20-app-shot.jpg"),
    }

print(f"{'scene':6} {'frame':28} {'ring':>6} {'gold':>6} {'red':>5}   (in a 1200px box around the pointer)")
for r in rows:
    print(f"{r[0]:6} {r[1]:28} {r[2]:6} {r[3]:6} {r[4]:5}")
json.dump(details, open("out/summary.json", "w"), indent=1)
for scene, d in details.items():
    dd = d["diff_control_vs_during"]
    da = d["diff_control_vs_app_shot"]
    print(f"\n{scene}: bound={d['bound']} ringUp={d['ring_up']} chip={d['chip']}")
    print(f"  control vs independent capture : {dd['changed_percent']}% of pixels differ, "
          f"{dd['region_count']} regions {[r['box'] for r in dd['regions'][:3]]}")
    print(f"  control vs the app's own shot  : {da['changed_percent']}% of pixels differ, "
          f"{da['region_count']} regions {[r['box'] for r in da['regions'][:3]]}")
