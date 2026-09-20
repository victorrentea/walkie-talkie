#!/usr/bin/env python3
"""Lay out one dictation's artifacts on disk, in the names the new template uses.

The eval next door asks a model what the envelope's symbols mean. Half of
those questions are answerable only by opening a file — *which file would you
read to see the region I framed* is not a reading-comprehension question if the
folder is empty — so the scene is built for real: two whole-screen frames, an
area frame with its unscaled cut-out, and a screen recording with a filmstrip
and two of its frames.

Everything is rendered from `page.html` by headless Chrome at 1728×1117 CSS px
with a device scale factor of 2 — 3456×2234, the geometry of the display the
capture evals ran on. Nothing of Victor's screen is here, so it can be built
and thrown away on any machine.
"""
import pathlib, subprocess, sys
from PIL import Image, ImageDraw

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
CSS_W, CSS_H, DSF = 1728, 1117, 2
W, H = CSS_W * DSF, CSS_H * DSF
HANDOVER = 800
HERE = pathlib.Path(__file__).parent
OUT = HERE / "shots" / "2026-09-19-17-32-15"

# The rectangle the wheel drag framed, in the pixels of the full-resolution
# frame — the numbers the inline `✂️` token and the footer both carry.
AREA = (900, 345, 2594, 574)
# Where the pointer was for each whole-screen shot, same pixels.
MOUSE = {0: (1000, 800), 1: (2400, 1180), 2: (640, 430)}


def render(dst):
    subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                    f"--force-device-scale-factor={DSF}",
                    f"--window-size={CSS_W},{CSS_H}",
                    f"--screenshot={dst}", f"file://{HERE / 'page.html'}"],
                   capture_output=True)
    return Image.open(dst).convert("RGB")


def small(im, dst):
    thumb = im.copy()
    thumb.thumbnail((HANDOVER, HANDOVER), Image.LANCZOS)
    thumb.save(dst, "JPEG", quality=82)
    return thumb.size


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    base = render(OUT / "_render.png")
    assert base.size == (W, H), base.size

    # 📸0, 📸1 and 📸2 — whole screens, each scrolled differently so they are not
    # the same picture, which is what makes *which one is the automatic one* and
    # *which file is 📸2* real questions rather than guesses.
    #
    # **Three of them since 2026-09-20, and that is the point of the scene.**
    # Victor, looking at two identical legend rows: *"Chiar e nevoie de astea? Nu
    # inferă agentul singur că în loc de 1 trebuie să pună 2?"* With two plain
    # frames the repetition is barely visible and the inference is trivial; with
    # three it is the shape he is actually paying for.
    for n in (0, 1, 2):
        frame = base.copy()
        if n:
            frame = frame.transform(frame.size, Image.AFFINE, (1, 0, 0, 0, 1, 260 * n))
        frame.save(OUT / f"screenshot-{n}-original.jpg", "JPEG", quality=88)
        small(frame, OUT / f"screenshot-{n}-800px.jpg")

    # 📸3 — the whole screen again, plus the framed region cut out of it unscaled.
    area = base.copy()
    area.save(OUT / "screenshot-3-original.jpg", "JPEG", quality=88)
    small(area, OUT / "screenshot-3-800px.jpg")
    area.crop(AREA).save(OUT / "screenshot-3.jpg", "JPEG", quality=92)

    # 🎦1 — a five-second recording: a filmstrip contact sheet and two frames of
    # it, named by the second they were taken at.
    frames = []
    for i in range(10):
        f = base.copy().transform(base.size, Image.AFFINE, (1, 0, 0, 0, 1, i * 40))
        frames.append(f)
    for t, f in (("0.1", frames[0]), ("2.5", frames[5])):
        f.save(OUT / f"screencast-1-frame-{t}s-original.jpg", "JPEG", quality=88)
        small(f, OUT / f"screencast-1-frame-{t}s-800px.jpg")
    cols, rows, cell = 5, 2, (320, 207)
    sheet = Image.new("RGB", (cols * cell[0], rows * cell[1]), "#111")
    draw = ImageDraw.Draw(sheet)
    for i, f in enumerate(frames):
        thumb = f.resize(cell, Image.LANCZOS)
        x, y = (i % cols) * cell[0], (i // cols) * cell[1]
        sheet.paste(thumb, (x, y))
        draw.text((x + 6, y + 6), f"{i * 0.5:.1f}s", fill="#ffd479")
    sheet.save(OUT / "screencast-1-filmstrip.jpg", "JPEG", quality=88)

    (OUT / "_render.png").unlink()
    print(f"{OUT}:")
    for f in sorted(OUT.iterdir()):
        print(f"  {f.name:42} {Image.open(f).size}")


if __name__ == "__main__":
    main()
