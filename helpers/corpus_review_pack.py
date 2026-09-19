#!/usr/bin/env python3
"""Turn teacher-labelled corpus samples into something a human can check in one sitting.

`teacher_label.py` produces labels; nothing produced *evidence*. A column in
SQLite is unreviewable — the only way to know whether Wispr heard the clip right
is to hear the clip and read the words at the same time, and doing that 80 times
through a database client is how a review does not happen.

So this writes a **review pack**:

    out/
      wav/01-….wav …     the clips themselves
      transcripts.txt    teacher beside student, numbered to match
      review.jsonl       the machine-readable pairs
      review.mp4         the clips played back to back, each with its
                         transcript on screen for exactly as long as it sounds

    python3 helpers/corpus_review_pack.py --out ~/Desktop/pack
    python3 helpers/corpus_review_pack.py --out … --limit 40 --no-video

The video is the deliverable Victor asked for and it is the one that answers the
question: the text is on screen while the audio plays, so a transcript that
drifted from its clip is visible rather than inferable. It is built with the
concat demuxer at one image per clip — no re-encoding per frame, no subtitle
track to go out of sync, and the image's duration *is* the clip's duration, so
the two cannot come apart.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sqlite3
import subprocess
import sys
import textwrap
import wave
from pathlib import Path

CORPUS = Path(os.environ.get(
    "VOICE_CORPUS_DIR", os.path.expanduser("~/.walkie-talkie/voice-corpus")))
CORPUS_DB = CORPUS / "corpus.db"

W, H = 1280, 720
FONT_DIR = Path("/System/Library/Fonts/Supplemental")


def rows(db, limit):
    q = ("SELECT id, wav, seconds, source, language, asr_text, final_text,"
         "       teacher_text, teacher_at, teacher_mic"
         "  FROM samples"
         " WHERE teacher_text IS NOT NULL AND teacher_text != ''"
         " ORDER BY teacher_at ASC")
    if limit:
        q += f" LIMIT {int(limit)}"
    return [dict(r) for r in db.execute(q)]


def wav_seconds(path):
    """Measured off the header — `seconds` in the DB is what the source claimed."""
    with wave.open(str(path)) as w:
        return w.getnframes() / float(w.getframerate())


def card(idx, total, rec, secs, out_png):
    """One still: the teacher's reading big, the student's underneath it."""
    from PIL import Image, ImageDraw, ImageFont

    def font(name, size):
        try:
            return ImageFont.truetype(str(FONT_DIR / name), size)
        except OSError:
            return ImageFont.load_default()

    img = Image.new("RGB", (W, H), (18, 18, 22))
    d = ImageDraw.Draw(img)
    f_small = font("Arial.ttf", 22)
    f_big = font("Arial Bold.ttf", 40)
    f_mid = font("Arial.ttf", 26)

    d.text((48, 40), f"{idx}/{total}   {secs:.1f}s   {rec.get('language') or '?'}"
                     f"   [{rec.get('source')}]",
           font=f_small, fill=(120, 125, 140))
    d.text((48, 96), "WISPR FLOW heard:", font=f_small, fill=(240, 176, 64))

    y = 140
    # Wrapping by character count rather than by measured width: the card is a
    # fixed size and the font is fixed, so the two agree, and a text longer than
    # the card is truncated rather than allowed to run off the bottom.
    for line in textwrap.wrap(rec["teacher_text"].strip(), width=46)[:8]:
        d.text((48, y), line, font=f_big, fill=(238, 240, 245))
        y += 54

    y = max(y + 40, 470)
    d.text((48, y), "local whisper had:", font=f_small, fill=(95, 130, 190))
    y += 34
    student = (rec.get("asr_text") or rec.get("final_text") or "").strip()
    for line in textwrap.wrap(student, width=62)[:5]:
        d.text((48, y), line, font=f_mid, fill=(140, 150, 170))
        y += 34

    img.save(out_png)


def build_video(pack, items, out_mp4):
    """Concat the audio, concat the stills, mux. One ffmpeg pass each."""
    listing = pack / "_concat.txt"
    audio_list = pack / "_audio.txt"
    with open(listing, "w") as fh, open(audio_list, "w") as af:
        for png, wav, secs in items:
            # The concat demuxer needs the last image repeated, or it is shown
            # for a single frame rather than for its stated duration.
            fh.write(f"file '{png}'\nduration {secs:.3f}\n")
            af.write(f"file '{wav}'\n")
        fh.write(f"file '{items[-1][0]}'\n")

    silent = pack / "_video.mp4"
    audio = pack / "_audio.wav"
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "concat",
                    # No `-vsync`/`-fps_mode`: it was removed in ffmpeg 9 and is
                    # unnecessary anyway — the concat demuxer's own `duration`
                    # lines set how long each still is shown, and `-r` only
                    # fixes the output frame rate.
                    "-safe", "0", "-i", str(listing),
                    "-pix_fmt", "yuv420p", "-r", "25", str(silent)], check=True)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "concat",
                    "-safe", "0", "-i", str(audio_list), "-ar", "16000",
                    "-ac", "1", str(audio)], check=True)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(silent),
                    "-i", str(audio), "-c:v", "copy", "-c:a", "aac",
                    "-shortest", str(out_mp4)], check=True)
    for tmp in (listing, audio_list, silent, audio):
        tmp.unlink(missing_ok=True)


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--out", required=True)
    ap.add_argument("--limit", type=int)
    ap.add_argument("--no-video", action="store_true")
    args = ap.parse_args(argv)

    db = sqlite3.connect(f"file:{CORPUS_DB}?mode=ro", uri=True)
    db.row_factory = sqlite3.Row
    recs = rows(db, args.limit)
    if not recs:
        raise SystemExit("no teacher-labelled samples yet — run teacher_label.py first")

    pack = Path(os.path.expanduser(args.out))
    (pack / "wav").mkdir(parents=True, exist_ok=True)
    frames = pack / "_frames"
    frames.mkdir(exist_ok=True)

    items, lines, total_sec = [], [], 0.0
    for i, rec in enumerate(recs, 1):
        src = CORPUS / rec["wav"]
        if not src.exists():
            continue
        secs = wav_seconds(src)
        total_sec += secs
        dst = pack / "wav" / f"{i:03d}-{Path(rec['wav']).stem}.wav"
        shutil.copy2(src, dst)

        png = frames / f"{i:03d}.png"
        card(i, len(recs), rec, secs, png)
        items.append((str(png), str(dst), secs))

        lines.append(
            f"[{i:03d}]  {secs:5.1f}s  {rec.get('language') or '?'}  {dst.name}\n"
            f"  wispr : {rec['teacher_text'].strip()}\n"
            f"  local : {(rec.get('asr_text') or '').strip()}\n")

        with open(pack / "review.jsonl", "a", encoding="utf-8") as fh:
            fh.write(json.dumps({**rec, "clip": dst.name,
                                 "measured_seconds": secs}, ensure_ascii=False) + "\n")

    header = (f"Wispr Flow teacher labels — {len(items)} clips, "
              f"{total_sec/60:.1f} min of audio\n"
              f"'wispr' is what Wispr Flow transcribed from the loopback device;\n"
              f"'local' is what the local whisper had said about the same audio.\n"
              + "=" * 72 + "\n\n")
    (pack / "transcripts.txt").write_text(header + "\n".join(lines), encoding="utf-8")

    if not args.no_video and items:
        build_video(pack, items, pack / "review.mp4")
        shutil.rmtree(frames, ignore_errors=True)

    print(f"{len(items)} clips, {total_sec/60:.1f} min → {pack}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
