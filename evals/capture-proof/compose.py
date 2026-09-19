#!/usr/bin/env python3
"""The two pictures Victor asked for, laid out so they read on a phone."""
from PIL import Image, ImageDraw, ImageFont

F = "/System/Library/Fonts/Supplemental/Arial.ttf"
FB = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
font = lambda s, bold=False: ImageFont.truetype(FB if bold else F, s)
INK, DIM, HOT = (24, 24, 26), (110, 110, 118), (224, 58, 58)


def text(d, xy, s, size=22, bold=False, fill=INK):
    d.text(xy, s, font=font(size, bold), fill=fill)


def proof_artifacts(scene="1", pointer=(2398, 1377), out="PROOF-1-no-artifacts.png"):
    shot = Image.open(f"out/{scene}/20-app-shot.jpg").convert("RGB")
    W = 1100
    body = shot.resize((1040, round(1040 * shot.height / shot.width)), Image.LANCZOS)
    k = 1040 / shot.width
    halo_span = 700                      # px on screen the ring and its filaments cover
    cut = shot.crop((pointer[0] - halo_span // 2, pointer[1] - halo_span // 2,
                     pointer[0] + halo_span // 2, pointer[1] + halo_span // 2)).resize((500, 500))
    ring = Image.open("halo-arrow.png").convert("RGB")
    w, h = ring.size
    ring = ring.crop((w // 2, h // 2, w, h)).resize((500, 500))

    H = 150 + body.height + 60 + 500 + 190
    im = Image.new("RGB", (W, H), "white")
    d = ImageDraw.Draw(im)
    text(d, (30, 28), "Walkie Talkie — nothing it draws is in what it shoots", 34, True)
    text(d, (30, 74), "The app's own picture, taken by ScreenCapture.grab while the caret halo, the", 21, fill=DIM)
    text(d, (30, 100), "lightning ring and the chip were all up on the screen.  19 Sep 2026, 10:58.", 21, fill=DIM)
    im.paste(body, (30, 140))
    px, py = 30 + pointer[0] * k, 140 + pointer[1] * k
    rad = halo_span * k / 2
    for i in range(0, 360, 12):                      # a dashed circle, drawn by hand
        d.arc([px - rad, py - rad, px + rad, py + rad], i, i + 7, fill=HOT, width=3)
    text(d, (px + rad + 10, py - 14), "← the halo was here", 20, True, HOT)

    y = 140 + body.height + 45
    im.paste(ring, (30, y + 34))
    im.paste(cut, (570, y + 34))
    text(d, (30, y), "ON THE SCREEN — the halo as the app draws it", 20, True)
    text(d, (570, y), "IN THE FILE — the same 700×700 px, from the shot", 20, True)
    d.rectangle([30, y + 34, 529, y + 533], outline=(210, 210, 214))
    d.rectangle([570, y + 34, 1069, y + 533], outline=(210, 210, 214))

    y += 560
    for line, bold in [
        ("0 ring pixels, 0 chevron pixels, 0 cursor-mark pixels in a 1200 px box around the pointer —", True),
        ("in the app's shot, in an independent screencapture, and in the 5 fps film frames.", True),
        ("The shot differs from a control frame taken seconds earlier, with nothing open, in 0.0% of", False),
        ("its pixels: 0 changed regions. Same result bound and unbound, over four runs.", False),
    ]:
        text(d, (30, y), line, 21, bold, INK if bold else DIM)
        y += 30
    im.save(out)
    print(out, im.size)


def proof_selection(scene="2", out="PROOF-2-selected-word.png"):
    page = Image.open(f"out/{scene}/21-app-shot-handover.jpg").convert("RGB")
    crop = Image.open(f"out/{scene}/41-crop.jpg").convert("RGB")
    W = 900
    page = page.resize((840, round(840 * page.height / page.width)), Image.LANCZOS)
    crop = crop.resize((840, round(840 * crop.height / crop.width)), Image.LANCZOS)
    H = 150 + page.height + 70 + crop.height + 190
    im = Image.new("RGB", (W, H), "white")
    d = ImageDraw.Draw(im)
    text(d, (30, 28), "One word selected — and what an agent makes of it", 32, True)
    text(d, (30, 72), "Both files are what the relay really hands over: 800 px on the long edge, JPEG 0.82.", 20, fill=DIM)
    y = 118
    text(d, (30, y), "THE WHOLE SCREEN", 19, True); y += 28
    im.paste(page, (30, y)); d.rectangle([30, y, 30 + page.width, y + page.height], outline=(210, 210, 214))
    y += page.height + 40
    text(d, (30, y), "THE WHEEL-DRAG REGION", 19, True); y += 28
    im.paste(crop, (30, y)); d.rectangle([30, y, 30 + crop.width, y + crop.height], outline=(210, 210, 214))
    y += crop.height + 40
    for line, bold in [
        ("24 agent runs, 4 words, 3 conditions: the right word 24/24.", True),
        ("Which occurrence: the crop alone 6/6, the whole page 4/6, both together 3/6.", True),
        ("Three of the four words appear twice in their own paragraph, and the highlight was", False),
        ("on the second. Handed the page, an agent quotes the sentence — which holds both.", False),
        ("Handed the crop, it quotes the line it was given, and that pins the occurrence.", False),
    ]:
        text(d, (30, y), line, 20, bold, INK if bold else DIM)
        y += 28
    im.save(out)
    print(out, im.size)


if __name__ == "__main__":
    proof_artifacts()
    proof_selection()
