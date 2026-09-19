#!/usr/bin/env python3
"""Is anything Walkie Talkie draws inside the pictures Walkie Talkie takes?

Three independent readings, because each can fail differently:

1. **Signature counts.** The caret halo is a violet/pink lightning ring
   (`g < min(r,b)`, saturated), the drop arrows are a pale gold chevron stack
   (`r > g > b`), the cursor mark is `systemRed`. Counted inside a box around
   the pointer big enough to hold the ring twice over (its radius is 105 pt =
   210 px), and over the whole frame.
2. **Difference against a control** taken seconds earlier with no dictation
   open and nothing drawn. Anything the app added would be a new bright region;
   the only region expected to move is the menu-bar clock.
3. **The positive control**: the same two masks run over the app's own rendering
   of the halo (`WT_SHOOT_HALO`), so a count of zero is read against a count
   that is not zero rather than against nothing.
"""
import json
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

RING = lambda r, g, b: (g < np.minimum(r, b) - 15) & (np.maximum(r, b) > 90)
GOLD = lambda r, g, b: (r > g + 12) & (g > b + 25) & (r > 150)
RED  = lambda r, g, b: (r > 170) & (g < 95) & (b < 95)


def load(path):
    a = np.asarray(Image.open(path).convert("RGB")).astype(int)
    return a, a[..., 0], a[..., 1], a[..., 2]


def counts(path, pointer=None, half=600):
    a, r, g, b = load(path)
    out = {"file": path, "size": [a.shape[1], a.shape[0]]}
    for name, mask in (("ring", RING), ("gold", GOLD), ("red", RED)):
        m = mask(r, g, b)
        out[name + "_frame"] = int(m.sum())
        if pointer:
            x, y = pointer
            sx, sy = a.shape[1] / 3456, a.shape[0] / 2234   # frames may be scaled
            x, y = int(x * sx), int(y * sy)
            box = m[max(0, y - half):y + half, max(0, x - half):x + half]
            out[name + "_pointer"] = int(box.sum())
    return out


def diff(control, during, top=6):
    a, *_ = load(control)
    b, *_ = load(during)
    if a.shape != b.shape:
        return {"error": "different sizes"}
    d = np.abs(a - b).max(axis=2)
    changed = d > 40
    labels, n = ndimage.label(ndimage.binary_closing(changed, np.ones((9, 9))))
    regions = []
    for i in range(1, n + 1):
        ys, xs = np.nonzero(labels == i)
        if len(xs) < 150:
            continue
        regions.append({"box": [int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())],
                        "pixels": int(len(xs))})
    regions.sort(key=lambda r: -r["pixels"])
    return {"changed_pixels": int(changed.sum()),
            "changed_percent": round(100 * changed.sum() / changed.size, 4),
            "regions": regions[:top], "region_count": len(regions)}


if __name__ == "__main__":
    pointer = (2398, 1376)
    report = {"pointer_px": list(pointer)}
    report["positive_control"] = counts("halo-arrow.png")
    report["frames"] = [counts(p, pointer) for p in sys.argv[2:]]
    report["diff_control_vs_during"] = diff(sys.argv[1], sys.argv[2])
    print(json.dumps(report, indent=1))
