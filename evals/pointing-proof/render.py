#!/usr/bin/env python3
"""Build, for each scene, the three files an agent could be handed for the
**same** wheel drag — with nothing highlighted on the page.

The question this harness asks is the one the selection eval could not: when
Victor selects no text and only drags the wheel around a sentence, is the
region he framed recoverable from what actually travels?

What actually travels, since 2026-09-14 (`ScreenCapture.grabArea`), is **not a
crop**: it is the whole display, shrunk to 800 px on the long edge, with the
rectangle carried as four numbers in the file's name, *in the full-resolution
frame's pixels*. So the three conditions are:

  small — only `…(area-…px)-small.jpg`, 800 px wide. The coordinates in the
          name are in 3456-px space and the file is 800 px wide: the reader has
          to scale them by 800/3456 itself, and nothing says so out loud.
  full  — the same, with the full-resolution original beside it on disk, which
          the clause invites it to open ("drop the -small").
  crop  — the region cut out and shrunk to 800 px: what the app did *before*
          2026-09-14, kept here as the baseline the previous eval measured.

The page is rendered by headless Chrome at 1728×1117 CSS px with a device scale
factor of 2, which is exactly the geometry of the display the capture eval ran
on (3456×2234). No frame of Victor's screen is involved, so everything here can
live in a public repo.
"""
import json, pathlib, re, subprocess, sys
from PIL import Image

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
CSS_W, CSS_H, DSF = 1728, 1117, 2
HANDOVER = 800
HERE = pathlib.Path(__file__).parent
OUT = HERE / "out"

# One target sentence per paragraph. Each is the **second** sentence of its
# paragraph on purpose: a box drawn round it has a sentence above and a sentence
# below inside the same block of text, so naming "the paragraph" is not an
# answer and the reader has to have located the box.
SCENES = {
    "1": ("p1", "A subprocess per frame costs two hundred milliseconds on this machine, "
                "which is already over the budget a five frame per second recording has, "
                "so the recorder reaches for the in-process call instead and keeps the "
                "subprocess for stills."),
    "2": ("p2", "The variance between runs was smaller than the variance between displays, "
                "which is the reason the table reports the display it was measured on "
                "rather than averaging the two together."),
    "3": ("p3", "A <code>retina</code> factor applied twice is the classic failure here: "
                "the box lands at half the intended place and nobody notices until a crop "
                "comes back empty."),
    "4": ("p4", "A sheet answers what moved and when in one look; the frames answer what "
                "the screen actually said."),
}

# **A hand's margins, not a designer's.** A wheel drag frames what the eye is
# reading and lands where it lands; a box mathematically centred on the sentence
# would be an easier question than the real gesture asks. Per scene, in CSS px:
# left, top, right, bottom.
MARGINS = {"1": (34, 11, 62, 19), "2": (18, 22, 41, 9),
           "3": (47, 7, 25, 27), "4": (12, 16, 88, 13)}


def scene_html(name):
    """The page with the target sentence wrapped, plus a script that reports its
    box through the title — `--dump-dom` is the only channel headless Chrome
    gives back, and the title survives it."""
    para, sentence = SCENES[name]
    base = (HERE / "page.html").read_text()
    # The sentence is written here with the line breaks of the source stripped;
    # the file has it wrapped, so match on whitespace-insensitive text.
    pattern = re.compile(r"\s+".join(re.escape(w) for w in sentence.split()))
    assert pattern.search(base), f"scene {name}: sentence not found in page.html"
    marked = pattern.sub(lambda m: f'<span id="target">{m.group(0)}</span>', base, count=1)
    marked += """
<script>
  const r = document.getElementById('target').getClientRects();
  let x1 = 1e9, y1 = 1e9, x2 = -1e9, y2 = -1e9;
  for (const b of r) { x1 = Math.min(x1, b.left); y1 = Math.min(y1, b.top);
                       x2 = Math.max(x2, b.right); y2 = Math.max(y2, b.bottom); }
  document.title = 'RECT ' + JSON.stringify([x1, y1, x2, y2]);
</script>
"""
    # The mark must not be visible: `<span>` with no style paints nothing, and
    # the assert below is what keeps a future stylesheet from changing that.
    assert "span {" not in base and "span{" not in base
    path = HERE / f"scene-{name}.html"
    path.write_text(marked)
    return path, para


def chrome(*args):
    return subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                           f"--force-device-scale-factor={DSF}",
                           f"--window-size={CSS_W},{CSS_H}", *args],
                          capture_output=True, text=True)


def rect_of(path):
    dom = chrome("--dump-dom", f"file://{path}").stdout
    m = re.search(r"<title>RECT (\[[^\]]+\])</title>", dom)
    assert m, "the page did not report a rect (did the script run?)"
    return json.loads(m.group(1))


def handover(im, dst, quality=82):
    """`ScreenCapture.writeHandoverCopy`: ≤800 px on the long edge, JPEG 0.82."""
    small = im.copy()
    small.thumbnail((HANDOVER, HANDOVER), Image.LANCZOS)
    small.convert("RGB").save(dst, "JPEG", quality=quality)
    return small.size


def build(name):
    d = OUT / name
    d.mkdir(parents=True, exist_ok=True)
    html, para = scene_html(name)
    css = rect_of(html)
    l, t, r, b = MARGINS[name]
    box = [max(0, css[0] - l), max(0, css[1] - t),
           min(CSS_W, css[2] + r), min(CSS_H, css[3] + b)]
    px = [int(round(v * DSF)) for v in box]

    shot = d / "screen.png"
    chrome(f"--screenshot={shot}", f"file://{html}")
    im = Image.open(shot)
    assert im.size == (CSS_W * DSF, CSS_H * DSF), f"unexpected render size {im.size}"

    # The names the app writes. The rectangle is in the pixels of the
    # full-resolution frame — `ScreenCapture.tagArea` measures it off the JPEG.
    stem = f"shot-1-00:04(area-{px[0]}x{px[1]}-to-{px[2]}x{px[3]}px)"
    full = d / f"{stem}.jpg"
    im.convert("RGB").save(full, "JPEG", quality=90)
    small_size = handover(im, d / f"{stem}-small.jpg")
    # The pre-2026-09-14 behaviour, as the baseline condition.
    crop_stem = f"shot-1-00:04(crop-{px[2]-px[0]}x{px[3]-px[1]}px)"
    crop = im.crop(tuple(px))
    crop.convert("RGB").save(d / f"{crop_stem}.jpg", "JPEG", quality=90)
    crop_size = handover(crop, d / f"{crop_stem}-small.jpg")

    (d / "truth.json").write_text(json.dumps({
        "scene": name, "paragraph": para, "sentence": " ".join(
            re.sub(r"<[^>]+>", "", SCENES[name][1]).split()),
        "rect_css": box, "rect_px": px, "stem": stem, "crop_stem": crop_stem,
        "screen_px": list(im.size), "small_px": list(small_size),
        "crop_px": [px[2] - px[0], px[3] - px[1]], "crop_small_px": list(crop_size),
    }, indent=1))
    print(f"scene {name}: target {px} on {im.size[0]}x{im.size[1]} -> "
          f"small {small_size[0]}x{small_size[1]}, crop "
          f"{px[2]-px[0]}x{px[3]-px[1]} -> {crop_size[0]}x{crop_size[1]}")


if __name__ == "__main__":
    for s in (sys.argv[1:] or sorted(SCENES)):
        build(s)
