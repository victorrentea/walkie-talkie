"""The candidate shapes of a delivered message, and the images each one hands over.

A variant is two decisions taken together, and they are only meaningful together:

  * **what the line says** — how the pictures are addressed and whether their
    order is stated or left to be inferred from a list of paths;
  * **what is on disk behind those paths** — the retina frame as captured, a
    downscaled copy, or a downscaled copy beside a native-resolution crop of
    what the pointer was on.

Splitting them into two axes and taking the cross product would be tidier and
would test combinations nobody would ship. These are the shapes worth arguing
about.

Every line is **one line**. The delivery ends with a Return, so a newline in
here is not formatting — it is an early submit that sends half the message.
"""

import os
import subprocess
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))

# Claude Code's Read tool downsamples to 2000px on the long edge before the
# image reaches the model, and an image costs about width*height/750 tokens.
# So a 3456×2234 retina frame arrives as 2000×1293 and costs ~3450 tokens
# whatever its file size — which is why "make the JPEG smaller" is not the
# lever and "make the picture smaller" is.
READ_MAX_EDGE = 2000
TOKENS_PER_PIXEL = 1 / 750.0


def estimate_tokens(path):
    with Image.open(path) as im:
        w, h = im.size
    scale = min(1.0, READ_MAX_EDGE / max(w, h))
    return int(w * scale * h * scale * TOKENS_PER_PIXEL)


def _stem(offset, cursor):
    """The name the relay gives a shot today: when in the sentence, and where the
    pointer was in the pixels of that frame."""
    s = max(0, int(round(offset)))
    name = "shot-%02d:%02d" % (s // 60, s % 60)
    if cursor:
        name += "(mouse-at-%dx%dpx)" % cursor
    return name + ".jpg"


def _downscale(src, dst, width):
    with Image.open(src) as im:
        w, h = im.size
        if w > width:
            im = im.resize((width, int(h * width / w)), Image.LANCZOS)
        im.convert("RGB").save(dst, "JPEG", quality=82, optimize=True)
    return dst


def _crop(src, dst, cursor, size=(1100, 700)):
    """A native-resolution window onto what the pointer was on.

    The whole frame downscaled answers "what was on screen"; this answers "what
    did he mean by *this*", and it answers it in the pixels the text was
    actually rendered at, which a 1000px-wide copy of a retina desktop no longer
    has."""
    with Image.open(src) as im:
        W, H = im.size
        x, y = cursor
        cw, ch = size
        left = max(0, min(W - cw, x - cw // 2))
        top = max(0, min(H - ch, y - ch // 2))
        im.crop((left, top, left + cw, top + ch)).convert("RGB").save(
            dst, "JPEG", quality=88, optimize=True)
    return dst


# --------------------------------------------------------------------------
# The shapes
# --------------------------------------------------------------------------

def v_current(fx, workdir):
    """What `AppDelegate.terminalLine` writes today.

    Absolute paths, retina frames, and the order of the pictures stated
    nowhere — it is carried only by the order of the paths inside `[look at:]`,
    which is an ordering an agent has to guess is meaningful."""
    files = _materialise(fx, workdir, "current", width=None, crop=False)
    ctx, shots = files[0], files[1:]
    line = fx["text"]
    if shots:
        line += " [look at: %s]" % " ".join(shots)
    line += " [context: %s]" % ctx
    return line, files


def v_compact(fx, workdir):
    """Same pictures, addressed once.

    The directory is said one time instead of once per shot, and the ordering
    is stated rather than implied. Nothing about what the model has to *look*
    at changes — this isolates how much of the cost is the addressing."""
    files = _materialise(fx, workdir, "compact", width=None, crop=False)
    return _compact_line(fx, files, drop_context=False), files


def v_small(fx, workdir):
    """The compact line over frames downscaled to 1000px wide.

    A retina desktop read through a 2000px pipe costs ~3450 tokens; the same
    desktop at 1000px costs ~860. The question is whether the fourfold saving
    takes any of the answer with it."""
    files = _materialise(fx, workdir, "small", width=1000, crop=False)
    return _compact_line(fx, files, drop_context=False), files


def v_small_crop(fx, workdir):
    """Downscaled frame **plus** a native-resolution crop around the pointer.

    Costs more than `small` and less than `current`, and is the only variant
    that gives the model the pointed-at text at the resolution it was rendered
    at. If the cursor tag is worth carrying at all, this is where it shows."""
    files = _materialise(fx, workdir, "smallcrop", width=1000, crop=True)
    return _compact_line(fx, files, drop_context=False, crops=True), files


def v_small_nocontext(fx, workdir):
    """`small`, minus the automatic frame.

    168 of the 180 dictations in the outbox carry one, and in the transcripts
    the agent opened it three times out of four — including for "Test, test,
    test, test." This variant asks what is actually lost by not offering it."""
    files = _materialise(fx, workdir, "nocontext", width=1000, crop=False)
    return _compact_line(fx, files, drop_context=True), files[1:]


def _by_width(width):
    """`small`, one notch narrower — the ladder that hunts for the floor.

    1000px was measured against retina and came out free; nothing measured what
    is *below* it, and the bill is quadratic in the long edge: 800px is 551
    tokens against 861, 700px is 422, 600px is 310. `text-vs-pixels.md` walked
    Vision OCR down the same frames and found it clean at 700 and gibberish at
    600 (`»in browser/sql LIMIT OFFSET` becomes `San broawry Cane uorare`) — but
    OCR is a pessimistic stand-in for what a model can read, and 700 duly came
    back 6/6. So the ladder continues past where OCR gave up.

    One factory rather than a function per rung: the rungs differ in a number
    and nothing else, and four copies of this docstring would be four places to
    update when the floor is found."""
    def variant(fx, workdir):
        files = _materialise(fx, workdir, "small%d" % width, width=width, crop=False)
        return _compact_line(fx, files, drop_context=False, width=width), files
    variant.__name__ = "v_small_%d" % width
    return variant


def v_small_ptrtext(fx, workdir):
    """`small`, plus the line the pointer was sitting on, as text.

    Vision OCR at the recorded cursor, quoted in the line — ~20 tokens a shot
    against the 861 the picture costs. It is the cheap half of what `small-crop`
    tried to buy, without `small-crop`'s defect: a crop is a *second picture*
    per shot, and two pictures per shot is what scrambled the sequence there.

    Only fixtures with cursors have anything to say here. `unsubscribe` predates
    the pointer tag, so on it this variant is `small` with extra steps."""
    files = _materialise(fx, workdir, "smallptr", width=1000, crop=False)
    line = _compact_line(fx, files, drop_context=False, width=1000)
    quotes = []
    sources = [fx["context"]] + fx["shots"]
    for i, src in enumerate(sources[1:], start=1):
        cursor = fx["cursors"][i]
        if not cursor:
            continue
        text = pointer_line(src, cursor)
        if text:
            quotes.append('%s = "%s"' % (os.path.basename(files[i]), text))
    if quotes:
        line += " [what the mouse was resting on in each, read off the screen: %s]" % "; ".join(quotes)
    return line, files


VARIANTS = {
    "current": v_current,
    "compact": v_compact,
    "small": v_small,
    "small-crop": v_small_crop,
    "small-nocontext": v_small_nocontext,
    "small-800": _by_width(800),
    "small-700": _by_width(700),
    "small-600": _by_width(600),
    "small-500": _by_width(500),
    "small-ptrtext": v_small_ptrtext,
}


# --------------------------------------------------------------------------

_OCRLINE = os.path.join(HERE, "work", "ocrline")


def pointer_line(image, cursor):
    """The text under the pointer, via `probes/ocrline.swift`.

    Built on demand into `work/` rather than checked in as a binary. The probe
    prints its three nearest candidates with distances; only the first is the
    answer, and the rest are there for a human deciding whether to trust it."""
    if not os.path.exists(_OCRLINE):
        os.makedirs(os.path.dirname(_OCRLINE), exist_ok=True)
        subprocess.run(["swiftc", "-O", os.path.join(HERE, "probes", "ocrline.swift"),
                        "-o", _OCRLINE], check=True, capture_output=True)
    out = subprocess.run([_OCRLINE, image, str(cursor[0]), str(cursor[1])],
                         capture_output=True, text=True, timeout=60).stdout
    first = out.splitlines()[0] if out.strip() else ""
    # `0.0000  the text` — drop the distance the probe leads with.
    return first.split("  ", 1)[1].strip().replace('"', "'") if "  " in first else ""


# --------------------------------------------------------------------------

def _materialise(fx, workdir, tag, width, crop):
    """Put this variant's images on disk under their relay names and return the
    paths, context frame first."""
    out = os.path.join(workdir, tag)
    os.makedirs(out, exist_ok=True)
    sources = [fx["context"]] + fx["shots"]
    paths = []
    for i, src in enumerate(sources):
        name = _stem(fx["offsets"][i], fx["cursors"][i])
        dst = os.path.join(out, name)
        if width:
            _downscale(src, dst, width)
        else:
            with Image.open(src) as im:
                im.convert("RGB").save(dst, "JPEG", quality=92)
        paths.append(dst)
        if crop and fx["cursors"][i]:
            cdst = dst.replace(".jpg", "-zoom.jpg")
            _crop(src, cdst, fx["cursors"][i])
    return paths


def _compact_line(fx, files, drop_context, crops=False, width=1000):
    """A clause per thing, mirroring `AppDelegate.shotsClause`.

    The folder is said once and the frames are listed by bare name, oldest
    first. The names already carry the reading — `shot-00:18(mouse-at-1034x1466px).jpg`
    is when in the sentence and where the pointer was — so this loses nothing
    and drops ~90 characters per picture. What the paths cannot say is that the
    list is chronological and that the first one is the frame nobody asked for,
    so the line says both.

    **The context frame gets a bracket of its own** rather than riding on the
    end of the shots sentence. The shipped line names the window each frame came
    from, window titles are arbitrary text, and one that ends in a full stop
    turned the separator between the last shot and the context frame into part
    of a title. Brackets are the one delimiter a title cannot forge.

    The fixtures here predate the window titles and carry none, so this renders
    the shape without them; the wording otherwise tracks what ships.
    """
    d = os.path.dirname(files[0])
    ctx, shots = files[0], files[1:]
    line = fx["text"]
    names = [os.path.basename(p) for p in shots]
    note = "Each is %dpx wide; drop the -small for the full-resolution original." % width
    if not shots:
        return line + " [the screen when I started talking, open only if the words need it: %s/%s]" % (
            d, os.path.basename(ctx))
    line += " [the shots I took, in %s/, oldest first: %s. %s]" % (d, " ".join(names), note)
    if not drop_context:
        line += " [and %s is the screen when I started talking, open it only if the words need it]" % (
            os.path.basename(ctx))
    if crops:
        line += " [each *-zoom.jpg beside a shot is that shot cropped to what the mouse was on, at full resolution]"
    return line
