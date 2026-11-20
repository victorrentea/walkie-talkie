#!/usr/bin/env python3
"""Compose the README's pictures out of docs/states/*.png.

The state shots are white text on a transparent background — the overlay is drawn
over whatever is on screen — so on GitHub's light theme they would be invisible.
Each one is set here on the same dark "editor" backdrop the states page uses.

Run by shoot-overlay-states.sh after every reshoot, so the README never shows an
overlay the code no longer draws.
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

DOCS = Path(__file__).resolve().parent
STATES = DOCS / "states"
OUT = DOCS / "readme"

BG = (36, 36, 42, 255)       # #24242a, the states page's .shot
LINE = (255, 255, 255, 14)   # its faint code lines
PAD = 40                     # @2x pixels
RADIUS = 20
ARROW = (150, 150, 160, 255)


def backdrop(w: int, h: int) -> Image.Image:
    card = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(card)
    d.rounded_rectangle((0, 0, w - 1, h - 1), RADIUS, fill=BG)
    lines = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ld = ImageDraw.Draw(lines)
    for i, frac in enumerate([0.34, 0.21, 0.46, 0.28, 0.38, 0.17, 0.42] * 20):
        y = 44 + i * 44
        if y > h - 30:
            break
        ld.rounded_rectangle((48, y, 48 + int((w - 96) * frac), y + 14), 7, fill=LINE)
    return Image.alpha_composite(card, lines)


def framed(name: str) -> Image.Image:
    shot = Image.open(STATES / f"{name}.png").convert("RGBA")
    card = backdrop(shot.width + 2 * PAD, shot.height + 2 * PAD)
    card.alpha_composite(shot, (PAD, PAD))
    return card


def font(size: int) -> ImageFont.FreeTypeFont:
    for path in ("/System/Library/Fonts/SFNS.ttf", "/System/Library/Fonts/Helvetica.ttc"):
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            pass
    return ImageFont.load_default()


def strip(names: list[str], out: str) -> None:
    """Frames side by side, joined by arrows: the order a dictation goes through them."""
    frames = [framed(n) for n in names]
    gap = 90
    w = sum(f.width for f in frames) + gap * (len(frames) - 1)
    h = max(f.height for f in frames)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    f = font(56)
    x = 0
    for i, frame in enumerate(frames):
        img.alpha_composite(frame, (x, (h - frame.height) // 2))
        x += frame.width
        if i < len(frames) - 1:
            d.text((x + gap / 2, h / 2), "→", font=f, fill=ARROW, anchor="mm")
            x += gap
    img.save(OUT / f"{out}.png", optimize=True)


def single(name: str) -> None:
    framed(name).save(OUT / f"{name}.png", optimize=True)


if __name__ == "__main__":
    OUT.mkdir(exist_ok=True)
    strip(["listening-everything", "prompt-shots", "flash-sent"], "hero")
    for n in ["listening", "listening-selection",
              "prompt-shots", "spawn-folder", "bind-to-send"]:
        single(n)
    print(f"→ {OUT.relative_to(DOCS.parent)}/")
