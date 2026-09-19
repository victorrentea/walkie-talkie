#!/usr/bin/env python3
"""Cut the wheel-drag crop out of the app's own frame, the way the app does.

`ScreenCapture.grabArea` captures the whole display and cuts the rectangle at
its real pixel scale, then `writeHandoverCopy` shrinks whatever travels to the
agent to 800 px on the long edge at JPEG 0.82. Both steps are reproduced here,
including the cap, so the crop the eval judges is the file an agent would
actually have been handed.

The box is deliberately **not** centred on the word: a hand dragging a wheel
frames the phrase it is looking at, and lands where it lands. Left 240, right
420, top 150, bottom 180 image pixels around the highlight.
"""
import sys
from PIL import Image
from findsel import find

MARGIN = (240, 150, 420, 180)   # left, top, right, bottom
HANDOVER = 800


def handover(im, path, quality=82):
    im = im.copy()
    im.thumbnail((HANDOVER, HANDOVER), Image.LANCZOS)
    im.convert("RGB").save(path, "JPEG", quality=quality)
    return im.size


def main(scene):
    src = f"out/{scene}/20-app-shot.jpg"
    box, _ = find(f"out/{scene}/01-control.png")
    im = Image.open(src)
    l, t, r, b = MARGIN
    rect = (max(0, box[0] - l), max(0, box[1] - t),
            min(im.width, box[2] + r), min(im.height, box[3] + b))
    crop = im.crop(rect)
    crop.save(f"out/{scene}/40-crop-full.jpg", "JPEG", quality=95)
    size = handover(crop, f"out/{scene}/41-crop.jpg")
    print(f"scene {scene}: highlight {box} -> crop {rect} "
          f"({rect[2]-rect[0]}x{rect[3]-rect[1]}px) -> handed over at {size[0]}x{size[1]}")


if __name__ == "__main__":
    for s in sys.argv[1:]:
        main(s)
