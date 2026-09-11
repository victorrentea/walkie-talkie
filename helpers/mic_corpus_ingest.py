#!/usr/bin/env python3
"""Adopt the addons app's microphone samples into `corpus.db`.

Two processes, one corpus, and the line between them is ownership:
**Victor Addons produces files, Walkie Talkie owns the database.**

`victor-macos-addons/whisper-transcribe/corpus_recorder.py` runs inside the live
transcription process, on a Mac in front of a room, and writes utterance WAVs
plus one JSONL line each into `<corpus>/mic/`. It does not touch `corpus.db` —
a realtime audio process should not be a second writer on a SQLite file that a
LaunchAgent, a report and a labeller all also open, and the failure mode of
getting that wrong is a stalled audio callback in front of an audience.

So this reads the manifest that process appends to and does the INSERTs, exactly
as `corpus_harvest.py` does for Wispr's database. Idempotent, cheap, and safe to
run beside the harvester:

    /usr/bin/python3 helpers/mic_corpus_ingest.py

Stdlib only, and therefore Apple's interpreter — the same call
`recent_projects.py` makes and for the same reason.
"""

import hashlib
import json
import os
import sqlite3
import struct
import sys
from datetime import datetime, timezone

HOME = os.path.expanduser("~")
CORPUS = os.environ.get("VOICE_CORPUS_DIR", os.path.join(HOME, ".walkie-talkie/voice-corpus"))
MIC_DIR = os.path.join(CORPUS, "mic")
MANIFEST = os.path.join(MIC_DIR, "mic-corpus.jsonl")
CORPUS_DB = os.path.join(CORPUS, "corpus.db")

# `corpus_harvest.py` owns the schema; this only adds the columns the mic corpus
# needs and the teacher fills in. Adding rather than altering, because the
# harvester runs every two hours and must keep working against whichever of the
# two touched the file last.
EXTRA_COLUMNS = {
    # The gate's own readings, kept per sample so the filter can be re-tuned
    # against real data instead of re-guessed — the same argument that made the
    # raw recorder record *before* the RMS gate.
    "voiced_ratio": "REAL",
    "speech_band": "REAL",
    "speaker": "TEXT",
    "speaker_score": "REAL",
    "forced_cut": "INTEGER",
    # Filled in later by `teacher_label.py`; see its docstring.
    "teacher_text": "TEXT",
    "teacher_at": "TEXT",
    "teacher_mic": "TEXT",
}


def log(msg):
    print("%s  %s" % (datetime.now().strftime("%Y-%m-%d %H:%M:%S"), msg), flush=True)


def wav_facts(blob):
    """Sample rate, channels, depth and true length off the header.

    Lifted from `corpus_harvest.py` deliberately rather than imported: that file
    is a script with a lock and a `main`, and importing it to borrow one pure
    function would run none of that and couple the two anyway.
    """
    try:
        if blob[0:4] != b"RIFF" or blob[8:12] != b"WAVE":
            return None
        fmt = blob.find(b"fmt ", 12)
        if fmt < 0:
            return None
        _, channels, rate, byte_rate, _, bits = struct.unpack(
            "<HHIIHH", blob[fmt + 8:fmt + 24])
        data = blob.find(b"data", 12)
        n = struct.unpack("<I", blob[data + 4:data + 8])[0] if data >= 0 else 0
        return dict(sample_rate=rate, channels=channels, bits=bits,
                    seconds=(n / byte_rate) if byte_rate else 0.0)
    except Exception:
        return None


def ensure_columns(db):
    have = {r[1] for r in db.execute("PRAGMA table_info(samples)")}
    for name, kind in EXTRA_COLUMNS.items():
        if name not in have:
            db.execute("ALTER TABLE samples ADD COLUMN %s %s" % (name, kind))
    db.commit()


def main():
    if not os.path.exists(MANIFEST):
        log("no mic manifest at %s — nothing collected yet" % MANIFEST)
        return 0
    if not os.path.exists(CORPUS_DB):
        log("no corpus.db — run corpus_harvest.py first, it owns the schema")
        return 1

    db = sqlite3.connect(CORPUS_DB, timeout=30)
    ensure_columns(db)
    known = {r[0] for r in db.execute("SELECT id FROM samples")}

    added = skipped = missing = 0
    seconds = 0.0
    with open(MANIFEST, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                o = json.loads(line)
            except ValueError:
                # A `kill -9` between the write and the newline costs one line,
                # which is the whole reason the manifest is JSONL.
                continue
            sid = o.get("id")
            if not sid or sid in known:
                skipped += 1
                continue
            rel = o.get("wav") or ""
            path = os.path.join(MIC_DIR, rel)
            if not os.path.exists(path):
                # Expected, not an error: the WAVs may live on an external disk
                # that is not plugged in. Counted and left for the next run,
                # rather than inserted as a row pointing at nothing.
                missing += 1
                continue
            with open(path, "rb") as f:
                blob = f.read()
            facts = wav_facts(blob[:4096]) or {}

            db.execute(
                "INSERT OR IGNORE INTO samples"
                " (id, source, ts, wav, bytes, sha256, seconds, reported_secs,"
                "  sample_rate, channels, bits, mic, harvested_at,"
                "  voiced_ratio, speech_band, speaker, speaker_score, forced_cut)"
                " VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                (sid, "addons-mic", o.get("ts"),
                 # Relative to the corpus root like every other row, so one join
                 # of root + `wav` resolves a sample whatever wrote it.
                 "mic/" + rel,
                 len(blob), hashlib.sha256(blob).hexdigest(),
                 facts.get("seconds"), o.get("seconds"),
                 facts.get("sample_rate"), facts.get("channels"), facts.get("bits"),
                 o.get("device"), datetime.now(timezone.utc).isoformat(),
                 o.get("voiced_ratio"), o.get("speech_band"),
                 o.get("speaker"), o.get("speaker_score"),
                 1 if o.get("forced_cut") else 0))
            known.add(sid)
            added += 1
            seconds += facts.get("seconds") or 0.0

    db.commit()
    log("mic corpus: +%d sample(s), %.1f min, %d known, %d waiting for their WAV"
        % (added, seconds / 60, skipped, missing))
    total = db.execute(
        "SELECT COUNT(*), COALESCE(SUM(seconds),0)/3600 FROM samples").fetchone()
    log("corpus now: %d samples, %.2f h" % (total[0], total[1]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
