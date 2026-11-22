#!/usr/bin/env python3
"""Assemble out/teaser-v1.mp4 from script.json, footage/, audio/ and music/.

    python3 teaser/build.py            # everything: voices, timeline, video, mix, mux
    python3 teaser/build.py --plan     # print the timeline only

How a cut is made
- Voices: tts.ensure() (cached per line).
- Timeline: a scene lasts max(target, its speech + gaps), then its end moves to the
  nearest beat of the music that still leaves room for the speech. Cuts are whole frames.
- Picture, per scene: footage/<id>.mp4 (or takes <id>-a.mp4, <id>-b.mp4 ... cut one per
  line), sped up / slowed down / trimmed to the scene; no clip -> a dark placeholder card.
  A scene whose id ends in "-end" is the generated end card. Optional per-scene keys in
  script.json: "trim": [in, out] seconds of the clip to use (per take: {"a": [in, out]}),
  "speed": a fixed speed instead of the fitted one.
- Subtitles: one full-frame PNG per line drawn with Pillow (Apple Color Emoji for the
  microphone), overlaid for exactly the time its audio plays.
- Sound: mixed in numpy -- voices at their timeline position, music ducked 12 dB under
  speech with ramps, fades at both ends.
Each scene renders to out/.work/<id>-<hash>.mp4 and is reused while nothing it depends on
changed, so a rebuild after one new clip re-encodes one scene.
"""
from __future__ import annotations
import hashlib
import json
import math
import os
import re
import subprocess
import sys
import textwrap
import wave
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = Path(__file__).resolve().parent
CUT_VERSION = 8                    # the file is out/teaser-v<N>.mp4
sys.path.insert(0, str(HERE))
import tts  # noqa: E402

# TEASER_FOOTAGE / TEASER_OUT: another footage folder and output file (a dry run with
# test clips, without touching the real cut).
FOOTAGE = Path(os.environ.get("TEASER_FOOTAGE", HERE / "footage"))
MUSIC_DIR, OUT = HERE / "music", HERE / "out"
FINAL = Path(os.environ.get("TEASER_OUT", OUT / f"teaser-v{CUT_VERSION}.mp4"))
CUTS = HERE / "cuts.json"
WORK = OUT / ".work" if FINAL.parent == OUT else FINAL.parent / ".work"
ICON = HERE.parent / "assets" / "walkie-bound.png"

W, H, FPS = 1920, 1080, 30
SR = 48000
RENDER_VERSION = 7                 # bump to throw away every cached scene

MUSIC = MUSIC_DIR / "brain-dance.mp3"
MUSIC_BPM = 124.0                  # stated by the composer; confirmed by beat_grid()
MUSIC_SKIP_BEATS = 4               # the track opens with a 2 s swell: start after it
MUSIC_GAIN_DB = -4.5               # music level between lines
DUCK_DB = -12.0                    # further drop under speech
VOICE_RMS_DB = -19.0               # every voice clip is levelled to this
MASTER_DB = 4.5                    # lift into the limiter: the cut lands near -15 LUFS

LEAD, GAP, TAIL = 0.30, 0.28, 0.35  # silence before the first line / between / after
BG = (11, 13, 18)
WHITE, YELLOW = (255, 255, 255), (255, 214, 10)
FONT = "/System/Library/Fonts/SFNS.ttf"
EMOJI_FONT = "/System/Library/Fonts/Apple Color Emoji.ttc"
MIC = "\U0001F399"


def run(cmd: list[str]) -> None:
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode:
        sys.exit(f"FAILED: {' '.join(cmd[:6])} ...\n{p.stderr[-3000:]}")


def probe_duration(path: Path) -> float:
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0",
                          "-show_entries", "format=duration", "-of", "csv=p=0", str(path)],
                         capture_output=True, text=True, check=True).stdout
    return float(out.strip().splitlines()[0])


def decode(path: Path, sr: int = SR, ch: int = 2) -> np.ndarray:
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-ac", str(ch),
                          "-ar", str(sr), "-f", "f32le", "-"], capture_output=True,
                         check=True).stdout
    return np.frombuffer(raw, np.float32).reshape(-1, ch).copy()


# ---------------------------------------------------------------- music beat grid

def beat_grid() -> tuple[float, float]:
    """(seconds per beat, time of a beat near 0) measured on the track itself."""
    cache = MUSIC_DIR / (MUSIC.stem + ".beat.json")
    if cache.is_file() and cache.stat().st_mtime > MUSIC.stat().st_mtime:
        d = json.loads(cache.read_text())
        return d["period"], d["phase"]
    sr, hop = 11025, 64
    x = decode(MUSIC, sr, 1)[: sr * 120, 0]
    n = len(x) // hop
    env = np.sqrt((x[: n * hop].reshape(n, hop) ** 2).mean(1))
    onset = np.maximum(0, np.diff(env))
    fps = sr / hop
    best = (0.0, MUSIC_BPM, 0.0)
    for bpm in np.arange(MUSIC_BPM - 1.5, MUSIC_BPM + 1.5, 0.02):
        period = 60 * fps / bpm
        for ph in np.linspace(0, period, 40, endpoint=False):
            idx = (ph + period * np.arange(int((len(onset) - ph) / period))).astype(int)
            score = onset[idx].sum()
            if score > best[0]:
                best = (score, bpm, ph / fps)
    period = 60 / best[1]
    cache.write_text(json.dumps({"bpm": round(best[1], 2), "period": period,
                                 "phase": best[2]}))
    return period, best[2]


# ---------------------------------------------------------------- timeline

def chunks(line: dict, force: int = 0) -> list[dict]:
    """A long line's subtitle, one sentence at a time: [{text, at, dur}] inside the clip.

    The boundary is the pause in the audio nearest to where the letters say it should be."""
    text, dur = line["text"], line["dur"]
    parts = re.split(r"(?<=[.?!])\s+", text) if len(text) > 55 else [text]
    if force:                                       # cuts.json asked for this many parts
        parts = re.split(r"(?<=[.?!,;:])\s+", text)
        if len(parts) != force:
            sys.exit(f"cannot split {text!r} into {force} parts at its punctuation")
    if len(parts) == 1:
        return [{"text": text, "at": 0.0, "dur": dur}]
    mono = decode(Path(line["file"]), 16000, 1)[:, 0]
    rms = np.sqrt((mono[: len(mono) // 160 * 160].reshape(-1, 160) ** 2).mean(1))
    quiet = rms < rms.max() * 0.06
    pauses, i = [], 0                               # centres of pauses >= 0.1 s
    while i < len(quiet):
        j = i
        while j < len(quiet) and quiet[j]:
            j += 1
        if j - i >= 10 and i > 0 and j < len(quiet):
            pauses.append((i + j) / 2 / 100)
        i = max(j, i + 1)
    cost = [len(p) + 6 for p in parts]
    cuts, acc = [0.0], 0
    for c in cost[:-1]:
        acc += c
        guess = dur * acc / sum(cost)
        near = min(pauses, key=lambda t: abs(t - guess), default=guess)
        cuts.append(near if abs(near - guess) < 0.8 and near > cuts[-1] + 0.3 else guess)
    cuts.append(dur)
    return [{"text": p, "at": round(a, 3), "dur": round(b - a, 3)}
            for p, a, b in zip(parts, cuts, cuts[1:])]


def plan() -> tuple[list[dict], float]:
    script = json.loads((HERE / "script.json").read_text())
    by_scene: dict[str, list[dict]] = {}
    for line in tts.ensure():
        by_scene.setdefault(line["scene"], []).append(line)
    period, phase = beat_grid()
    music_start = phase % period + MUSIC_SKIP_BEATS * period   # the cut starts on a beat
    scenes, t0 = [], 0                    # t0 in frames
    edit = json.loads(CUTS.read_text()) if CUTS.is_file() else {}
    for sc in script["scenes"]:
        lines = by_scene.get(sc["id"], [])
        tight = sc["id"] in edit.get("_tight", [])
        lead_in, tail = (0.12, 0.15) if tight else (LEAD, TAIL)
        sc = {**sc, "target": 0 if tight else edit.get("_target", {}).get(sc["id"], sc["target"])}
        speech = lead_in + sum(l["dur"] for l in lines) + GAP * max(0, len(lines) - 1) + tail
        start = t0 / FPS
        fixed = edit.get("_at", {}).get(sc["id"])
        placed = []
        if fixed:                                   # line (and part) start times given by hand
            for l, spec in zip(lines, fixed):
                if isinstance(spec, list):
                    subs = chunks(l, force=len(spec))
                    for c, t in zip(subs, spec):        # null = where the voice puts it
                        c["shift"] = 0.0 if t is None else round(t - (spec[0] + c["at"]), 3)
                    placed.append({**l, "at": spec[0], "subs": subs})
                else:
                    placed.append({**l, "at": spec, "subs": chunks(l)})
            speech = max(l["at"] + c["at"] + c.get("shift", 0) + c["dur"]
                         for l in placed for c in l["subs"]) + tail
        want = start + max(sc["target"], speech)
        beat = round(want / period) * period
        while beat < start + speech:
            beat += period
        end = round(beat * FPS)
        dur = (end - t0) / FPS
        if not fixed:
            # lines: spread over the scene, the spare time shared between the gaps
            spare = dur - speech
            lead = lead_in + min(spare * 0.25, 0.5)
            gap = GAP + (min(spare * 0.5, 1.2) / (len(lines) - 1) if len(lines) > 1 else 0)
            t = lead
            for l in lines:
                placed.append({**l, "at": round(t, 3), "subs": chunks(l)})
                t += l["dur"] + gap
        scenes.append({**sc, "frames": end - t0, "start": start, "dur": dur,
                       "lines": placed})
        t0 = end
    return scenes, music_start


# ---------------------------------------------------------------- drawing

def font(size: int, weight: str = "Bold") -> ImageFont.FreeTypeFont:
    f = ImageFont.truetype(FONT, size)
    try:
        f.set_variation_by_name(weight)
    except Exception:
        pass
    return f


def emoji(size: int) -> Image.Image:
    f = ImageFont.truetype(EMOJI_FONT, 160)       # the colour strike that exists
    im = Image.new("RGBA", (220, 220), (0, 0, 0, 0))
    ImageDraw.Draw(im).text((30, 30), MIC, font=f, embedded_color=True)
    im = im.crop(im.getbbox())
    if im.getbbox() is None or len(im.getcolors(100000) or []) < 20:
        sys.exit("the microphone emoji did not render in colour")
    k = size / im.height
    return im.resize((max(1, round(im.width * k)), size), Image.LANCZOS)


def wrap(text: str, f: ImageFont.FreeTypeFont, max_w: int) -> list[str]:
    words, lines, cur = text.split(), [], ""
    for w in words:
        trial = (cur + " " + w).strip()
        if f.getlength(trial) <= max_w or not cur:
            cur = trial
        else:
            lines.append(cur)
            cur = w
    lines.append(cur)
    if len(lines) == 2 and len(lines[1].split()) == 1 and len(lines[0].split()) > 3:
        head = lines[0].split()                   # no orphan word on the second row
        lines = [" ".join(head[:-1]), head[-1] + " " + lines[1]]
    return lines


def subtitle_png(text: str, who: str, path: Path, top: bool = False, tag: str | None = None) -> None:
    size = 62
    f = font(size, "Bold")
    colour = YELLOW if who == "u" else WHITE
    mic = emoji(round(size * 1.2)) if who == "u" else None
    mic_w = (mic.width + 22) if mic else 0
    rows = wrap(text, f, 1500 - mic_w)
    line_h = round(size * 1.28)
    widths = [f.getlength(r) for r in rows]
    block_w = max(widths) + mic_w
    block_h = line_h * len(rows)
    pad_x, pad_y = 44, 24
    box_w, box_h = block_w + 2 * pad_x, block_h + 2 * pad_y
    x0, y0 = (W - box_w) / 2, (64 if top else H - 78 - box_h)
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((x0, y0, x0 + box_w, y0 + box_h), 30,
                                             fill=(0, 0, 0, 190))
    im.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(6)))
    d = ImageDraw.Draw(im)
    for i, row in enumerate(rows):
        row_w = widths[i] + (mic_w if i == 0 else 0)
        x = (W - row_w) / 2
        y = y0 + pad_y + i * line_h
        if i == 0 and mic:
            im.alpha_composite(mic, (round(x), round(y + (line_h - mic.height) / 2)))
            x += mic_w
        d.text((x, y + line_h / 2), row, font=f, fill=colour, anchor="lm",
               stroke_width=3, stroke_fill=(0, 0, 0, 230))
    if tag:  # a small label riding the box's top-left corner (script line's "tag", e.g. WAKE WORD)
        tf = font(30, "Bold")
        tw = tf.getlength(tag)
        tx, ty = x0 + 26, y0 - 26
        d.rounded_rectangle((tx, ty, tx + tw + 36, ty + 46), 23, fill=(255, 214, 10, 255))
        d.text((tx + 18, ty + 23), tag, font=tf, fill=(20, 20, 20, 255), anchor="lm")
    im.save(path)


def backdrop() -> Image.Image:
    """Dark card background: a soft glow so it is visibly a card, not a dead frame."""
    yy, xx = np.mgrid[0:H, 0:W]
    r = np.hypot((xx - W / 2) / W, (yy - H * 0.42) / H)
    glow = np.clip(1 - r * 1.9, 0, 1) ** 2
    img = np.zeros((H, W, 3), np.float32)
    for c in range(3):
        img[..., c] = BG[c] + glow * (26, 30, 44)[c]
    return Image.fromarray(img.astype(np.uint8), "RGB")


def placeholder_png(scene: dict, path: Path) -> None:
    im = backdrop()
    d = ImageDraw.Draw(im)
    d.text((W / 2, 300), scene["id"], font=font(84, "Heavy"), fill=(235, 238, 245),
           anchor="mm")
    d.text((W / 2, 372), "footage pending", font=font(30, "Medium"), fill=(255, 170, 40),
           anchor="mm")
    f = font(36, "Regular")
    y = 450
    for row in wrap(scene.get("shows", ""), f, 1300):
        d.text((W / 2, y), row, font=f, fill=(150, 158, 175), anchor="mm")
        y += 50
    im.save(path)


def endcard_png(path: Path) -> None:
    im = backdrop().convert("RGBA")
    d = ImageDraw.Draw(im)
    y = 300
    if ICON.is_file():
        icon = Image.open(ICON).convert("RGBA").resize((300, 300), Image.LANCZOS)
        im.alpha_composite(icon, ((W - 300) // 2, 110))
        y = 500
    d.text((W / 2, y), "Walkie Talkie", font=font(124, "Heavy"), fill=WHITE, anchor="mm")
    # The tagline under the name; the facts and the link lower down (Victor, 2026-11-22).
    d.text((W / 2, y + 118), "Talk to your coding agent", font=font(62, "Bold"),
           fill=WHITE, anchor="mm")
    d.text((W / 2, H - 250), "Free  ·  open source  ·  built for macOS", font=font(48, "Medium"),
           fill=(255, 176, 32), anchor="mm")
    d.text((W / 2, H - 170), "github.com/victorrentea/walkie-talkie",
           font=font(44, "Regular"), fill=(190, 198, 214), anchor="mm")
    d.text((W / 2, H - 108), "use it, fork it, tweak it", font=font(38, "Medium"),
           fill=(140, 150, 170), anchor="mm")
    im.convert("RGB").save(path)


def checklist_png(items: list[str], ticked: int, path: Path) -> None:
    """The features card: `items` in one column, the first `ticked` of them ticked."""
    im = backdrop().convert("RGBA")
    d = ImageDraw.Draw(im)
    f, row = font(48, "Bold"), 80
    x = (W - max(f.getlength(t) for t in items) - 96) / 2
    y = max(40, (H - 260 - row * len(items)) / 2)   # clear of the subtitle below
    for i, text in enumerate(items):
        cy, on = y + i * row + row / 2, i < ticked
        d.rounded_rectangle((x, cy - 27, x + 54, cy + 27), 13,
                            fill=(52, 199, 89, 255) if on else None,
                            outline=None if on else (110, 118, 135, 255), width=4)
        if on:
            d.line([(x + 12, cy + 2), (x + 23, cy + 13), (x + 43, cy - 12)],
                   fill=WHITE, width=8, joint="curve")
        d.text((x + 88, cy), text, font=f, fill=WHITE if on else (120, 128, 145), anchor="lm")
    im.convert("RGB").save(path)


def note_png(note: dict, path: Path) -> None:
    """A caption with an arrow to a point of the frame: {text, point: [x, y], from: "left"|...}."""
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    f = font(46, "Bold")
    px, py = note["point"]
    tw = f.getlength(note["text"])
    dx, dy = {"left": (-1, 0), "right": (1, 0), "up": (0, -1), "down": (0, 1)}[note.get("from", "left")]
    gap = 170
    cx, cy = px + dx * (gap + (tw / 2 + 30 if dx else 0)), py + dy * (gap + (40 if dy else 0))
    cx = min(W - tw / 2 - 50, max(tw / 2 + 50, cx)); cy = min(H - 80, max(80, cy))
    box = (cx - tw / 2 - 30, cy - 42, cx + tw / 2 + 30, cy + 42)
    d.rounded_rectangle(box, 22, fill=(255, 214, 10, 255))
    d.text((cx, cy), note["text"], font=f, fill=(20, 20, 20, 255), anchor="mm")
    sx = box[2] if dx < 0 else box[0] if dx > 0 else cx
    sy = box[3] if dy < 0 else box[1] if dy > 0 else cy
    ex, ey = px + dx * 26, py + dy * 26
    d.line([(sx, sy), (ex, ey)], fill=(255, 214, 10, 255), width=8)
    L = math.hypot(ex - sx, ey - sy) or 1
    ux, uy = (ex - sx) / L, (ey - sy) / L
    d.polygon([(px + dx * 4, py + dy * 4), (ex - ux * 14 - uy * 20, ey - uy * 14 + ux * 20),
               (ex - ux * 14 + uy * 20, ey - uy * 14 - ux * 20)], fill=(255, 214, 10, 255))
    im.save(path)


def struck_png(st: dict, path: Path) -> None:
    """What was first heard, struck through in red above the corrected word: {text, over: [x, y, w, h]}.

    Optional: size (font px), lift (px between the word's top and the label's bottom, default
    clear of a text box's border)."""
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    x, y, w, h = st["over"]
    size = st.get("size", max(34, round(h * 1.2)))
    f = font(size, "Bold")
    tw = f.getlength(st["text"])
    half = size * 0.72
    cx, cy = x + w / 2, y - st.get("lift", 44) - half
    d.rounded_rectangle((cx - tw / 2 - 18, cy - half, cx + tw / 2 + 18, cy + half), 12,
                        fill=(20, 20, 24, 240), outline=(255, 69, 58, 255), width=2)
    d.text((cx, cy), st["text"], font=f, fill=(255, 150, 142, 255), anchor="mm")
    # a thin line, so the misheard word stays readable under it
    d.line([(cx - tw / 2 - 8, cy + 2), (cx + tw / 2 + 8, cy + 2)], fill=(255, 59, 48, 255),
           width=max(3, size // 14))
    d.polygon([(cx - 10, cy + half), (cx + 10, cy + half), (cx, cy + half + 12)],
              fill=(255, 69, 58, 255))                 # a small pointer down to the word
    im.save(path)


# ---------------------------------------------------------------- picture

def readout_masks(clip: str, a: float, b: float) -> list[dict]:
    """Where the crop box's readouts sit, frame by frame, in footage/<clip> between a and b.

    The wheel-drag box is drawn in yellow; its size badges ride above and left of it and
    the grey key hint below. Returns three moving regions [{w, h, keys: [[t, x, y], ...]}]
    (t in seconds from a, x/y the region's top-left on the 1920x1080 source)."""
    fps, w, h = 8, 960, 540
    raw = subprocess.run(["ffmpeg", "-v", "error", "-ss", f"{a:.3f}", "-t", f"{b - a:.3f}",
                          "-i", str(FOOTAGE / f"{clip}.mp4"), "-vf",
                          f"fps={fps},scale={w}:{h}", "-f", "rawvideo", "-pix_fmt", "rgb24",
                          "-"], capture_output=True, check=True).stdout
    frames = np.frombuffer(raw, np.uint8).reshape(-1, h, w, 3).astype(int)
    top, left, hint = [], [], []
    for i, f in enumerate(frames):
        r, g, bl = f[..., 0], f[..., 1], f[..., 2]
        yellow = (r > 200) & (g > 165) & (g < 235) & (bl < 110)
        rows = np.where(yellow.sum(1) >= 4)[0]
        cols = np.where(yellow.sum(0) >= 3)[0]
        if len(rows) < 2 or len(cols) < 2:
            continue
        # a drawn box has a solid top and bottom edge; a glow or a flash does not
        span = yellow[:, cols[0]: cols[-1] + 1]
        if span[rows[0]: rows[0] + 2].any(0).mean() < 0.7 or \
                span[rows[-1] - 1: rows[-1] + 1].any(0).mean() < 0.7:
            continue
        x0, x1, y0, y1 = cols[0] * 2, cols[-1] * 2, rows[0] * 2, rows[-1] * 2
        t, cx, cy = i / fps, (x0 + x1) / 2, (y0 + y1) / 2
        clampx = lambda v, bw: int(min(W - bw - 4, max(4, v)))
        clampy = lambda v, bh: int(min(H - bh - 4, max(4, v)))
        top.append([t, clampx(cx - 60, 120), clampy(y0 - 58, 52)])
        left.append([t, clampx(x0 - 112, 104), clampy(cy - 28, 56)])
        hint.append([t, clampx(cx - 285, 570), clampy(y1 + 8, 54)])
    if not top:
        return []
    return [{"w": 120, "h": 52, "keys": top}, {"w": 104, "h": 56, "keys": left},
            {"w": 570, "h": 54, "keys": hint}]


def piecewise(keys: list[list[float]], k: int) -> str:
    """ffmpeg expression: column k of keys, linear in t between them, held outside."""
    expr = str(keys[-1][k])
    for (t0, *v0), (t1, *v1) in reversed(list(zip(keys, keys[1:]))):
        a, b = v0[k - 1], v1[k - 1]
        seg = f"{a}+({b - a})*(t-{t0:.3f})/{t1 - t0:.3f}" if a != b else str(a)
        expr = f"if(lt(t,{t1:.3f}),{seg},{expr})"
    return f"if(lt(t,{keys[0][0]:.3f}),{keys[0][k]},{expr})"


def segments_for(scene: dict) -> list[dict]:
    """The scene's sub-cuts: cuts.json when it has them, else every clip found, whole.

    Each comes back with `dur` (seconds on screen, whole frames) and the speed that implies.
    Cuts tagged with the same `line` share the time from that line to the next tagged one
    and are stretched together to fill it; untagged cuts continue the group before them."""
    sid, lines, total = scene["id"], scene["lines"], scene["dur"]
    if scene.get("checklist"):                        # a generated card, whatever was filmed
        return []
    cuts = json.loads(CUTS.read_text()).get(sid) if CUTS.is_file() else None
    if cuts:
        segs = [{"clip": sid, **c} for c in cuts if (FOOTAGE / f"{c.get('clip', sid)}.mp4").is_file()]
    else:
        takes = sorted(FOOTAGE.glob(f"{sid}-[a-z].mp4")) or \
            [p for p in [FOOTAGE / f"{sid}.mp4"] if p.is_file()]
        segs = [{"clip": p.stem, "in": 0.0, "out": probe_duration(p),
                 **({"line": i} if len(takes) == len(lines) > 1 else {})}
                for i, p in enumerate(takes)]
    if not segs:
        return []
    def line_time(ref) -> float:
        i, j = ref if isinstance(ref, list) else (ref, 0)
        c = lines[i]["subs"][j]
        return max(0.0, lines[i]["at"] + c["at"] + c.get("shift", 0) - (0.25 if j == 0 else 0.1))

    groups: list[tuple[float, list[dict]]] = []      # (start time, cuts)
    for seg in segs:
        ref = seg.get("line")
        ok = ref is not None and (ref[0] if isinstance(ref, list) else ref) < len(lines)
        if "start" in seg:
            groups.append((seg["start"], [seg]))
        elif ok and groups:
            groups.append((line_time(ref), [seg]))
        elif not groups:
            groups.append((0.0, [seg]))
        else:
            groups[-1][1].append(seg)
    edges = [round(g[0] * FPS) for g in groups] + [scene["frames"]]
    for (_, members), f0, f1 in zip(groups, edges, edges[1:]):
        span = (f1 - f0) / FPS
        fixed = sum((m["out"] - m["in"]) / m["speed"] for m in members if "speed" in m)
        loose = sum(m["out"] - m["in"] for m in members if "speed" not in m)
        k = loose / max(0.1, span - fixed)            # speed of the stretched cuts
        if not cuts:
            k = min(3.0, max(0.75, k))                # an uncurated clip: trim or hold instead
        t, f = 0.0, f0
        for i, m in enumerate(members):
            m["speed"] = m.get("speed", k)
            t += (m["out"] - m["in"]) / m["speed"]
            end = f1 if i == len(members) - 1 else min(f1, f0 + round(t * FPS))
            m["at"], m["dur"] = f / FPS, (end - f) / FPS
            f = end
    return [m for m in segs if m["dur"] > 0]


def render_scene(scene: dict) -> tuple[Path, list[dict]]:
    WORK.mkdir(parents=True, exist_ok=True)
    sid = scene["id"]
    is_end = sid.endswith("-end")
    segs = [] if is_end else segments_for(scene)
    clips = sorted({s["clip"] for s in segs})
    stat = [(c, (FOOTAGE / f"{c}.mp4").stat().st_size, (FOOTAGE / f"{c}.mp4").stat().st_mtime_ns)
            for c in clips]
    icon = ICON.stat().st_mtime_ns if is_end and ICON.is_file() else 0
    key = hashlib.sha256(json.dumps([RENDER_VERSION, scene, segs, stat, icon],
                                    sort_keys=True).encode()).hexdigest()[:12]
    out = WORK / f"{sid}-{key}.mp4"
    if out.is_file():
        return out, segs
    for old in WORK.glob(f"{sid}-*"):
        old.unlink()

    dur = scene["dur"]
    inputs: list[str] = []
    chains: list[str] = []
    norm = (f"fps={FPS},scale={W}:{H}:force_original_aspect_ratio=decrease:flags=lanczos,"
            f"pad={W}:{H}:(ow-iw)/2:(oh-ih)/2:color=0x0b0d12,setsar=1,format=yuv420p")
    if segs:
        for i, sg in enumerate(segs):
            inputs += ["-ss", f"{sg['in']:.3f}", "-t", f"{sg['out'] - sg['in'] + 0.5:.3f}",
                       "-i", str(FOOTAGE / f"{sg['clip']}.mp4")]
            crop = "crop={2}:{3}:{0}:{1},".format(*sg["crop"]) if sg.get("crop") else ""
            src = f"[{i}:v]"
            if sg.get("mask") == "readout":         # hide the crop box's badges and key hint
                dl = []
                for m in readout_masks(sg["clip"], sg["in"], sg["out"]):
                    k = m["keys"]
                    dl.append(f"delogo=x='{piecewise(k, 1)}':y='{piecewise(k, 2)}':"
                              f"w={m['w']}:h={m['h']}:"
                              f"enable='between(t,{k[0][0] - 0.15:.3f},{k[-1][0] + 0.3:.3f})'")
                if dl:
                    chains.append(f"{src}{','.join(dl)}[m{i}]")
                    src = f"[m{i}]"
            if sg.get("blur"):                      # smear a region of the source (x, y, w, h)
                bx, by, bw, bh = sg["blur"]
                chains.append(f"{src}split[b{i}a][b{i}b];[b{i}b]crop={bw}:{bh}:{bx}:{by},"
                              f"boxblur=8:3[b{i}c];[b{i}a][b{i}c]overlay={bx}:{by}[b{i}]")
                src = f"[b{i}]"
            chains.append(
                f"{src}setpts=(PTS-STARTPTS)/{sg['speed']:.4f},{crop}{norm},"
                f"tpad=stop_mode=clone:stop_duration={sg['dur'] + 1:.3f},"
                f"trim=duration={sg['dur']:.4f},setpts=PTS-STARTPTS[t{i}]")
        n = len(segs)
        chains.append("".join(f"[t{i}]" for i in range(n)) + f"concat=n={n}:v=1:a=0[v0]")
    else:
        card = WORK / f"{sid}-card.png"
        items = scene.get("checklist")
        if is_end:
            endcard_png(card)
        elif items:
            checklist_png(items, len(items) - len(scene["lines"]), card)
        else:
            placeholder_png(scene, card)
        inputs += ["-loop", "1", "-framerate", str(FPS), "-t", f"{dur + 1:.3f}", "-i", str(card)]
        fade = ",fade=t=in:st=0:d=0.25" if is_end else ""
        chains.append(f"[0:v]{norm}{fade}[v0]")
        n = 1

    last = "v0"
    subs = [(line["who"], line["at"] + c["at"] + c.get("shift", 0), c["dur"], c["text"],
             line.get("tag"))
            for line in scene["lines"] for c in line["subs"]]
    if is_end:
        subs = []   # the end card says it in its own type; no subtitle over it
    for j, (who, at, sub_dur, text, tag) in enumerate(subs):
        a = max(0.0, at - 0.05)
        nxt = subs[j + 1][1] - 0.05 if j + 1 < len(subs) else dur
        b = min(dur, at + sub_dur + 0.25, nxt)
        # the subtitle goes to the top when a cut it shares more than 0.4 s with asks for that
        top = any(sg.get("sub") == "top" and
                  min(b, sg["at"] + sg["dur"]) - max(a, sg["at"]) > 0.4 for sg in segs)
        png = WORK / f"{sid}-sub{j}.png"
        subtitle_png(text, who, png, top, tag)
        inputs += ["-loop", "1", "-framerate", str(FPS), "-t", f"{dur + 1:.3f}", "-i", str(png)]
        chains.append(f"[{last}][{n + j}:v]overlay=0:0:enable='between(t,{a:.3f},{b:.3f})'"
                      f"[v{j + 1}]")
        last = f"v{j + 1}"
    # pictures over a span of the scene: the checklist's ticks, a cut's note / struck word
    extra: list[tuple[Path, float, float]] = []
    items = scene.get("checklist")
    if items and not segs:
        for j, line in enumerate(scene["lines"]):   # one more tick as each line is spoken
            png = WORK / f"{sid}-tick{j}.png"
            checklist_png(items, len(items) - len(scene["lines"]) + j + 1, png)
            extra.append((png, line["at"] + min(1.2, line["subs"][0]["dur"] * 0.4), dur))
    for i, sg in enumerate(segs):
        for kind, draw in (("note", note_png), ("struck", struck_png)):
            if sg.get(kind):
                png = WORK / f"{sid}-{kind}{i}.png"
                draw(sg[kind], png)
                a = sg["at"] + sg[kind].get("after", 0)
                extra.append((png, a, sg["at"] + sg["dur"]))
    base = n + len(subs)
    for j, (png, a, b) in enumerate(extra):
        inputs += ["-loop", "1", "-framerate", str(FPS), "-t", f"{dur + 1:.3f}", "-i", str(png)]
        chains.append(f"[{last}][{base + j}:v]overlay=0:0:enable='between(t,{a:.3f},{b:.3f})'"
                      f"[x{j}]")
        last = f"x{j}"
    if is_end:
        chains.append(f"[{last}]fade=t=out:st={dur - 0.5:.3f}:d=0.5[vf]")
        last = "vf"

    run(["ffmpeg", "-y", "-v", "error", *inputs, "-filter_complex", ";".join(chains),
         "-map", f"[{last}]", "-frames:v", str(scene["frames"]), "-r", str(FPS),
         "-c:v", "libx264", "-preset", "medium", "-crf", "18", "-pix_fmt", "yuv420p",
         "-video_track_timescale", "15360", "-an", str(out)])
    return out, segs


# ---------------------------------------------------------------- sound

def mix(scenes: list[dict], music_start: float, total: float, out: Path) -> None:
    n = int(round(total * SR))
    voice = np.zeros((n, 2), np.float32)
    duck = np.zeros(n, np.float32)                 # 1 where speech is
    spans = []
    for sc in scenes:
        for l in sc["lines"]:
            clip = decode(Path(l["file"]))
            mono = clip.mean(1)
            frame = mono[: len(mono) // 480 * 480].reshape(-1, 480)
            rms = np.sqrt((frame ** 2).mean(1))
            loud = rms[rms > rms.max() * 0.1]
            clip *= 10 ** (VOICE_RMS_DB / 20) / max(1e-4, float(np.sqrt((loud ** 2).mean())))
            moved = any(c.get("shift") for c in l["subs"])
            parts = l["subs"] if moved else [{"at": 0.0, "dur": l["dur"]}]
            for c in parts:                        # a line split by hand plays part by part
                piece = clip[int(c["at"] * SR): int((c["at"] + c["dur"]) * SR)].copy()
                if moved:
                    f = min(int(0.012 * SR), len(piece) // 2)
                    piece[:f] *= np.linspace(0, 1, f)[:, None]
                    piece[-f:] *= np.linspace(1, 0, f)[:, None]
                t = sc["start"] + l["at"] + c["at"] + c.get("shift", 0)
                at = int(round(t * SR))
                piece = piece[: n - at]
                voice[at: at + len(piece)] += piece
                spans.append((t, t + c["dur"]))
    merged: list[list[float]] = []
    for a, b in sorted(spans):                     # no pumping in the short gaps
        if merged and a - merged[-1][1] < 0.7:
            merged[-1][1] = b
        else:
            merged.append([a, b])
    for a, b in merged:
        duck[max(0, int((a - 0.12) * SR)): int((b + 0.10) * SR)] = 1
    ramp = int(0.22 * SR)
    kernel = np.hanning(ramp * 2 + 1).astype(np.float32)
    duck = np.convolve(duck, kernel / kernel.sum(), "same")
    env = 10 ** ((MUSIC_GAIN_DB + DUCK_DB * duck) / 20)

    music = decode(MUSIC)[int(music_start * SR):]
    if len(music) < n:
        music = np.tile(music, (math.ceil(n / len(music)), 1))
    music = music[:n] * env[:, None]
    fade_in, fade_out = int(0.12 * SR), int(1.6 * SR)
    music[:fade_in] *= np.linspace(0, 1, fade_in)[:, None] ** 2
    music[-fade_out:] *= np.linspace(1, 0, fade_out)[:, None] ** 2

    m = (voice + music) * 0.5                      # headroom; main() limits and lifts it
    pcm = (np.clip(m, -1, 1) * 32767).astype("<i2")
    with wave.open(str(out), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


# ---------------------------------------------------------------- main

def main() -> None:
    if not MUSIC.is_file():
        sys.exit(f"missing {MUSIC} -- see teaser/README.md for where it comes from")
    scenes, music_start = plan()
    total = sum(s["frames"] for s in scenes) / FPS
    period, _ = beat_grid()
    print(f"music {60 / period:.2f} BPM, starts at {music_start:.3f}s of the track")
    for s in scenes:
        print(f"{s['start']:6.2f}s  {s['id']:11} {s['dur']:5.2f}s "
              f"(target {s['target']}, {s['dur'] / period:.1f} beats)")
        for l in s["lines"]:
            print(f"           {l['who']} +{l['at']:.2f}s {l['dur']:.2f}s  "
                  + " | ".join(c["text"] for c in l["subs"]))
        segs = [] if s["id"].endswith("-end") else segments_for(s)
        for g in segs:
            print(f"           cut {s['start'] + g['at']:6.2f}-{s['start'] + g['at'] + g['dur']:6.2f}"
                  f"  {g['clip']} {g['in']:.1f}-{g['out']:.1f}s x{g['speed']:.2f}"
                  + (f"  crop {g['crop']}" if g.get("crop") else "")
                  + ("  sub top" if g.get("sub") == "top" else ""))
        if not segs:
            print("           " + ("end card" if s["id"].endswith("-end") else "PLACEHOLDER"))
    print(f"total {total:.2f}s")
    if "--plan" in sys.argv:
        return

    WORK.mkdir(parents=True, exist_ok=True)
    parts, real = [], 0
    for s in scenes:
        path, segs = render_scene(s)
        parts.append(path)
        real += bool(segs)
    (WORK / "cutlist.json").write_text(json.dumps(
        [{"scene": s["id"], "clip": g["clip"], "in": g["in"], "out": g["out"],
          "speed": round(g["speed"], 2), "from": round(s["start"] + g["at"], 2),
          "to": round(s["start"] + g["at"] + g["dur"], 2)}
         for s in scenes if not s["id"].endswith("-end") for g in segments_for(s)], indent=1))
    listing = WORK / "concat.txt"
    listing.write_text("".join(f"file '{p}'\n" for p in parts))
    wav = WORK / "mix.wav"
    mix(scenes, music_start, total, wav)
    run(["ffmpeg", "-y", "-v", "error", "-f", "concat", "-safe", "0", "-i", str(listing),
         "-i", str(wav), "-map", "0:v", "-map", "1:a", "-c:v", "copy",
         "-af", f"volume={6 + MASTER_DB}dB,alimiter=limit=0.78:attack=4:release=60:level=false",
         "-c:a", "aac", "-b:a", "192k", "-shortest", "-movflags", "+faststart", str(FINAL)])
    small = FINAL.with_name(FINAL.stem + "-720p.mp4")       # the copy that fits in a mail
    run(["ffmpeg", "-y", "-v", "error", "-i", str(FINAL), "-vf", "scale=1280:-2:flags=lanczos",
         "-c:v", "libx264", "-preset", "slow", "-crf", "27", "-pix_fmt", "yuv420p",
         "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart", str(small)])
    keep = {p.name for p in parts}
    for old in WORK.glob("s*-????????????.mp4"):
        if old.name not in keep:
            old.unlink()
    cards = sum(1 for s in scenes if not s["id"].endswith("-end")) - real
    print(f"{FINAL}  {total:.2f}s  footage: {real} scenes, placeholders: {cards}, "
          f"end card: 1")


if __name__ == "__main__":
    main()
