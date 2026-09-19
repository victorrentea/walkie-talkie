#!/usr/bin/env python3
"""Locate the browser's selection highlight in a screenshot, by its blue.

macOS/Chrome paints an active selection as the accent blue at ~30% over the
page. The search is a colour window rather than an exact value because the
glyphs inside the highlight darken their own pixels and JPEG moves the rest.

Chrome's own chrome is full of blue too (tab indicator, favicons, bookmark
glyphs), so the answer is the **largest connected blob**, not the bounding box
of every blue pixel — the highlight is one solid run of a few thousand pixels
and nothing in the toolbar comes close.
"""
import sys
import numpy as np
from PIL import Image
from scipy import ndimage


def find(path, min_pixels=800):
    im = np.asarray(Image.open(path).convert("RGB")).astype(int)
    r, g, b = im[..., 0], im[..., 1], im[..., 2]
    mask = (b > 200) & (b - r > 45) & (b - g > 20) & (r > 120) & (g > 160)
    # Close the gaps the glyphs cut through the highlight so a selected word is
    # one blob and not one blob per letter-gap.
    mask = ndimage.binary_closing(mask, structure=np.ones((5, 9)))
    labels, count = ndimage.label(mask)
    if not count:
        return None, 0
    sizes = ndimage.sum(mask, labels, range(1, count + 1))
    best = int(np.argmax(sizes)) + 1
    if sizes[best - 1] < min_pixels:
        return None, int(sizes.max())
    ys, xs = np.nonzero(labels == best)
    return (int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())), int(sizes[best - 1])


if __name__ == "__main__":
    for p in sys.argv[1:]:
        box, n = find(p)
        print(f"{p}: {box} ({n} px)")
