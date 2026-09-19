#!/usr/bin/env python3
"""Export the corpus as a fine-tuning dataset, in the one layout everybody reads.

The corpus is a SQLite table and a tree of WAVs; every trainer — MLX, HF
`transformers`, `peft`, and the upload format every cloud vendor asks for — wants
the same two things instead: a flat audio folder and a JSONL manifest with one
`{audio, text}` per line. This writes that, and nothing else.

    python3 helpers/corpus_export.py --out ~/voice-dataset
    python3 helpers/corpus_export.py --out … --label teacher   # Wispr's reading
    python3 helpers/corpus_export.py --out … --label edited    # only hand fixes

## Which column is the label, and why it is a flag rather than a default

Three columns could be the reference and they are not interchangeable:

| `--label` | column | what a model trained on it learns |
|---|---|---|
| `teacher` | `teacher_text` | to **imitate Wispr Flow** on this voice — Wispr's raw `asrText`, no formatting |
| `final` (default) | `final_text` | the best reference on hand: a hand correction where one exists, else the recogniser that produced the row |
| `edited` | `edited_text` | only what Victor corrected **by hand** — the one supervision that could beat the teacher, and the smallest |

Mixing them silently would produce a set whose labels come from three different
processes with no column saying which, and every evaluation after that is
measuring the mixture.

## The validation split is by DAY, not by clip

A random split puts two clips recorded forty seconds apart on either side of it,
and a model that has heard the room, the microphone gain and the sentence before
it is not being tested on anything. Whole days go to validation, so the held-out
set is a day the model has never heard.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sqlite3
import sys
import wave
from collections import defaultdict
from pathlib import Path

CORPUS = Path(os.environ.get(
    "VOICE_CORPUS_DIR", os.path.expanduser("~/.walkie-talkie/voice-corpus")))
CORPUS_DB = CORPUS / "corpus.db"

LABEL_COLUMN = {"teacher": "teacher_text", "final": "final_text",
                "edited": "edited_text"}


def wav_seconds(path):
    with wave.open(str(path)) as w:
        return w.getnframes() / float(w.getframerate())


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--out", required=True)
    ap.add_argument("--label", choices=sorted(LABEL_COLUMN), default="final")
    ap.add_argument("--language", help="keep only this language (ro, en, …)")
    ap.add_argument("--min-seconds", type=float, default=1.0)
    ap.add_argument("--max-seconds", type=float, default=30.0,
                    help="Whisper's encoder window is 30 s; longer clips are "
                         "truncated by the model, so they are dropped here "
                         "rather than silently mislabelled (default 30)")
    ap.add_argument("--val-fraction", type=float, default=0.1)
    ap.add_argument("--copy-audio", action="store_true",
                    help="copy the WAVs beside the manifest instead of "
                         "referencing them where they already live")
    args = ap.parse_args(argv)

    col = LABEL_COLUMN[args.label]
    db = sqlite3.connect(f"file:{CORPUS_DB}?mode=ro", uri=True)
    db.row_factory = sqlite3.Row
    recs = [dict(r) for r in db.execute(
        f"SELECT id, wav, seconds, source, language, {col} AS label"
        "  FROM samples"
        f" WHERE {col} IS NOT NULL AND {col} != ''"
        "   AND wav IS NOT NULL"
        " ORDER BY ts ASC")]

    out = Path(os.path.expanduser(args.out))
    audio_dir = out / "audio"
    audio_dir.mkdir(parents=True, exist_ok=True)

    kept, by_day = [], defaultdict(list)
    dropped = defaultdict(int)
    for rec in recs:
        src = CORPUS / rec["wav"]
        if not src.exists():
            dropped["missing wav"] += 1
            continue
        if args.language and (rec.get("language") or "") != args.language:
            dropped["other language"] += 1
            continue
        try:
            secs = wav_seconds(src)
        except Exception:
            dropped["unreadable wav"] += 1
            continue
        if not (args.min_seconds <= secs <= args.max_seconds):
            dropped["outside the duration window"] += 1
            continue

        day = rec["wav"].split("/")[0]
        rel = f"audio/{rec['id']}.wav"
        if args.copy_audio:
            shutil.copy2(src, out / rel)
        item = {"audio": rel if args.copy_audio else str(src),
                "text": rec["label"].strip(), "duration": round(secs, 3),
                "language": rec.get("language") or "", "id": rec["id"],
                "source": rec["source"], "day": day}
        kept.append(item)
        by_day[day].append(item)

    if not kept:
        raise SystemExit(f"nothing to export with --label {args.label}")

    # Whole days to validation, newest first, until the fraction is met.
    target = sum(i["duration"] for i in kept) * args.val_fraction
    val_ids, got = set(), 0.0
    for day in sorted(by_day, reverse=True):
        if got >= target:
            break
        for i in by_day[day]:
            val_ids.add(i["id"])
            got += i["duration"]

    for name, items in (("train", [i for i in kept if i["id"] not in val_ids]),
                        ("validation", [i for i in kept if i["id"] in val_ids])):
        with open(out / f"{name}.jsonl", "w", encoding="utf-8") as fh:
            for i in items:
                fh.write(json.dumps(i, ensure_ascii=False) + "\n")
        hours = sum(x["duration"] for x in items) / 3600
        print(f"{name:<11} {len(items):5d} clips  {hours:5.2f} h")

    (out / "README.md").write_text(
        f"# Voice dataset — label column `{col}`\n\n"
        f"{len(kept)} clips, {sum(i['duration'] for i in kept)/3600:.2f} h.\n"
        f"Validation is **whole days** ({len(val_ids)} clips), so no clip in it "
        f"shares a session with a training clip.\n\n"
        "`train.jsonl` / `validation.jsonl`: one `{audio, text, duration, "
        "language, id, source, day}` per line.\n", encoding="utf-8")

    for why, n in sorted(dropped.items(), key=lambda kv: -kv[1]):
        print(f"  dropped {n:5d}  {why}")
    print(f"→ {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
