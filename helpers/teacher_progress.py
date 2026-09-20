#!/usr/bin/env python3
"""Where the teacher-labelling has got to, in one line per fact.

    python3 helpers/teacher_progress.py

Victor asks for this at every pause, stop and restart (2026-09-20), and the number he
asks for is **the share of the corpus's audio LENGTH**, not of its clips. The two say
very different things and the clip count is the flattering one: the batch takes the
shortest clip first, so after a night it had 23% of the clips and 7.6% of the hours.

It is a program rather than a handful of queries so that two reports an hour apart are
comparable — a denominator improvised each time is how a progress report starts
disagreeing with itself.
"""

from __future__ import annotations

import os
import sqlite3
import sys

CORPUS_DB = os.path.expanduser(
    os.environ.get("VOICE_CORPUS_DB", "~/.walkie-talkie/voice-corpus/corpus.db"))

#: Below this a clip is never dictated: Wispr returns nothing for a tap that short.
MIN_SECONDS = float(os.environ.get("WISPR_MIN_SECONDS", "3"))


def figures(db):
    def one(where, args=()):
        row = db.execute(
            f"SELECT COUNT(*), COALESCE(SUM(seconds), 0) FROM samples WHERE {where}",
            args).fetchone()
        return row[0], row[1] / 3600.0

    total = one("1=1")
    # Rows harvested from Wispr arrive with Wispr's own reading already on them.
    theirs = one("source = 'wispr'")
    queue = one("source <> 'wispr'")
    done = one("teacher_text IS NOT NULL AND teacher_text <> ''")
    tiny = one("source <> 'wispr' AND seconds < ? AND (teacher_text IS NULL"
               " OR teacher_text = '')", (MIN_SECONDS,))
    left = one("source <> 'wispr' AND seconds >= ? AND (teacher_text IS NULL"
               " OR teacher_text = '')", (MIN_SECONDS,))
    return total, theirs, queue, done, tiny, left


def main():
    db = sqlite3.connect(f"file:{CORPUS_DB}?mode=ro", uri=True)
    total, theirs, queue, done, tiny, left = figures(db)

    def pct(part, whole):
        return 0.0 if not whole else 100.0 * part / whole

    print(f"corpus total          {total[0]:5d} clipuri  {total[1]:6.2f} h")
    print(f"  cu eticheta lui Wispr{theirs[0]:4d} clipuri  {theirs[1]:6.2f} h")
    print(f"  de etichetat de noi {queue[0]:5d} clipuri  {queue[1]:6.2f} h")
    print()
    print(f"ETICHETAT             {done[0]:5d} clipuri  {done[1]:6.2f} h")
    print(f"  din audio-ul de etichetat   {pct(done[1], queue[1]):5.1f} %")
    print(f"  din tot corpusul            {pct(done[1], total[1]):5.1f} %")
    print(f"  (pe clipuri, pentru comparație: {pct(done[0], queue[0]):.1f} % din coadă)")
    print()
    print(f"rămas de dictat       {left[0]:5d} clipuri  {left[1]:6.2f} h audio")
    print(f"  sub {MIN_SECONDS:.0f}s, nu se dictează  {tiny[0]:5d} clipuri  {tiny[1]:6.2f} h")
    # Measured 2026-09-20: a clip costs its own length plus ~10.6 s of round trip,
    # paste, and the randomised gap that keeps the rig from looking like a metronome.
    hours = left[1] + left[0] * 10.6 / 3600.0
    print(f"  ≈ {hours:.1f} h de ceas la ritmul măsurat")
    return 0


if __name__ == "__main__":
    sys.exit(main())
