#!/usr/bin/env python3
"""Steal Wispr Flow's inputs and outputs before it throws the inputs away.

Wispr Flow keeps every transcript it has ever made — 12k of them going back to
January — but it keeps the **recording** for about a week and then prunes it.
That asymmetry is the whole reason this exists: the text is safe, the audio is
on a timer, and a (audio, text) pair is worth something only while both halves
are still on disk. Measured on 2026-09-01: 12,186 transcripts, 185 recordings,
the oldest recording six days old.

So this runs on a schedule, copies out every pair it has not seen yet, and files
it next to the ones the relay records itself, in one corpus that accumulates:

    ~/.walkie-talkie/voice-corpus/
        2026-08-26/09-52-06-1a2b3c4d.wav   ← what Victor said
        2026-08-26/09-52-06-1a2b3c4d.txt   ← the words Wispr made of it
        corpus.jsonl                        ← the human-readable manifest
        corpus.db                           ← the queryable one, this file's store

No model runs here and none is called. This is a copy, a checksum and an INSERT.

## Why it also comes back to rows it has already taken

`editedText` is the text Victor *fixed by hand* after Wispr got it wrong, and it
is the most valuable column in the source: a free human correction of a machine
transcript, which is exactly the supervision a fine-tune wants. Wispr fills it in
**later**, by watching what he types over the pasted text — so a row harvested
the minute it appeared usually has no correction yet and would be frozen wrong.
Every run therefore re-reads the rows it took in the last fortnight and updates
the text if it has moved. The audio never changes; only the reading of it does.

## Reading a database another app has open

Wispr is usually running with `flow.sqlite` open in WAL mode. Opening it
read-only is safe and is what happens — SQLite is built for one writer and many
readers, and nothing here writes to it, ever. A 3.5 GB copy-then-read would be
the paranoid alternative and is not worth doing every two hours.
"""

import fcntl
import hashlib
import json
import os
import sqlite3
import struct
import sys
import time
from datetime import datetime, timezone

HOME = os.path.expanduser("~")
WISPR_DB = os.path.join(HOME, "Library/Application Support/Wispr Flow/flow.sqlite")
CORPUS = os.environ.get("VOICE_CORPUS_DIR", os.path.join(HOME, ".walkie-talkie/voice-corpus"))
CORPUS_DB = os.path.join(CORPUS, "corpus.db")
MANIFEST = os.path.join(CORPUS, "corpus.jsonl")
LOCK = os.path.join(CORPUS, ".harvest.lock")

# How far back to re-read rows we already have, looking for a late `editedText`.
REFRESH_DAYS = 14
# A blob shorter than this is a WAV header and nothing else.
MIN_WAV_BYTES = 45

SCHEMA = """
CREATE TABLE IF NOT EXISTS samples (
    id            TEXT PRIMARY KEY,   -- Wispr transcriptEntityId, or the relay's stem
    source        TEXT NOT NULL,      -- 'wispr' | 'whisper-local'
    ts            TEXT,               -- ISO 8601, UTC
    wav           TEXT,               -- path relative to the corpus root
    txt           TEXT,
    bytes         INTEGER,
    sha256        TEXT,
    seconds       REAL,               -- measured off the WAV header, not reported
    reported_secs REAL,               -- what the source claimed
    sample_rate   INTEGER,
    channels      INTEGER,
    bits          INTEGER,
    num_words     INTEGER,
    language      TEXT,
    asr_text      TEXT,               -- the recogniser's raw reading
    formatted_text TEXT,              -- after Wispr's LLM formatting
    edited_text   TEXT,               -- what Victor corrected it to, if he did
    final_text    TEXT,               -- best reference available: edited > formatted > asr
    app           TEXT,
    mic           TEXT,
    harvested_at  TEXT,
    refreshed_at  TEXT
);
CREATE INDEX IF NOT EXISTS idx_samples_ts ON samples (ts);
CREATE INDEX IF NOT EXISTS idx_samples_source ON samples (source);

CREATE TABLE IF NOT EXISTS runs (
    started_at   TEXT PRIMARY KEY,
    finished_at  TEXT,
    new_samples  INTEGER,
    new_seconds  REAL,
    refreshed    INTEGER,
    skipped      INTEGER,
    error        TEXT
);

-- Single-row bookkeeping the report reads, so a report never has to guess when
-- the last one went out.
CREATE TABLE IF NOT EXISTS state (key TEXT PRIMARY KEY, value TEXT);
"""


def log(msg):
    print("%s  %s" % (datetime.now().strftime("%Y-%m-%d %H:%M:%S"), msg), flush=True)


def wav_facts(blob):
    """Sample rate, channels, bit depth and true length, read off the header.

    The `duration` column is what Wispr believed; the header is what the file
    actually contains, and the corpus is judged on the file.
    """
    try:
        if blob[0:4] != b"RIFF" or blob[8:12] != b"WAVE":
            return None
        fmt = blob.find(b"fmt ", 12)
        if fmt < 0:
            return None
        _, channels, rate, byte_rate, _, bits = struct.unpack("<HHIIHH", blob[fmt + 8:fmt + 24])
        data = blob.find(b"data", 12)
        n = struct.unpack("<I", blob[data + 4:data + 8])[0] if data >= 0 else 0
        # A truncated file lies in its header; trust whichever is smaller.
        n = min(n, len(blob) - (data + 8)) if data >= 0 else 0
        return dict(sample_rate=rate, channels=channels, bits=bits,
                    seconds=(n / byte_rate) if byte_rate else 0.0)
    except Exception:
        return None


def parse_ts(raw):
    """Wispr writes '2026-08-26 08:52:06.399 +00:00'. Return an aware UTC datetime."""
    if not raw:
        return None
    s = str(raw).strip().replace(" +00:00", "+00:00").replace(" ", "T", 1)
    for cut in (s, s.split(".")[0] + "+00:00", s.split(".")[0]):
        try:
            d = datetime.fromisoformat(cut)
            return d if d.tzinfo else d.replace(tzinfo=timezone.utc)
        except ValueError:
            continue
    return None


def best_text(edited, formatted, asr):
    for t in (edited, formatted, asr):
        if t and t.strip():
            return t.strip()
    return ""


def open_corpus():
    os.makedirs(CORPUS, exist_ok=True)
    db = sqlite3.connect(CORPUS_DB, timeout=30)
    db.executescript(SCHEMA)
    db.commit()
    return db


def import_manifest(db):
    """Fold the pre-existing corpus.jsonl into the table, once.

    The relay's Swift side and an earlier one-off backfill both wrote only the
    manifest. Those samples are already on disk and are part of the corpus; the
    database is not complete until it knows about them too.
    """
    if not os.path.exists(MANIFEST):
        return 0
    known = set(r[0] for r in db.execute("SELECT id FROM samples"))
    added = 0
    with open(MANIFEST, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                o = json.loads(line)
            except ValueError:
                continue
            sid = o.get("id")
            if not sid or sid in known:
                continue
            wav_rel = o.get("wav") or ""
            wav_abs = os.path.join(CORPUS, wav_rel)
            # Header only: the format fields live in the first bytes, and the
            # length is already in the manifest. Reading 669 whole WAVs to
            # recompute a number we were handed would be silly.
            facts = {}
            if os.path.exists(wav_abs):
                with open(wav_abs, "rb") as f:
                    facts = wav_facts(f.read(4096)) or {}
            text = o.get("text") or ""
            db.execute(
                "INSERT OR IGNORE INTO samples (id, source, ts, wav, txt, bytes, seconds,"
                " reported_secs, sample_rate, channels, bits, num_words, language, asr_text,"
                " formatted_text, edited_text, final_text, app, mic, harvested_at)"
                " VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                (sid,
                 "wispr" if o.get("wisprTs") else "whisper-local",
                 o.get("ts"), wav_rel, o.get("txt"), o.get("bytes"),
                 o.get("duration"), o.get("duration"),
                 facts.get("sample_rate"), facts.get("channels"), facts.get("bits"),
                 o.get("words"), o.get("detectedLanguage"), o.get("asr"),
                 None, None, text, o.get("app"), o.get("mic"),
                 datetime.now(timezone.utc).isoformat()))
            known.add(sid)
            added += 1
    db.commit()
    if added:
        log("manifest: adopted %d sample(s) written before this store existed" % added)
    return added


def open_wispr():
    if not os.path.exists(WISPR_DB):
        raise SystemExit("Wispr Flow database not found at %s" % WISPR_DB)
    uri = "file:%s?mode=ro" % WISPR_DB.replace("?", "%3f").replace("#", "%23")
    db = sqlite3.connect(uri, uri=True, timeout=30)
    db.row_factory = sqlite3.Row
    return db


def harvest(corpus, wispr):
    known = set(r[0] for r in corpus.execute("SELECT id FROM samples"))
    rows = wispr.execute(
        "SELECT transcriptEntityId AS id, timestamp, duration, numWords, app, micDevice,"
        "       language, detectedLanguage, asrText, formattedText, editedText,"
        "       length(audio) AS n"
        "  FROM History"
        " WHERE audio IS NOT NULL AND length(audio) > ?"
        " ORDER BY timestamp", (MIN_WAV_BYTES,)).fetchall()

    new = skipped = 0
    new_secs = 0.0
    manifest = open(MANIFEST, "a", encoding="utf-8")
    try:
        for r in rows:
            if r["id"] in known:
                skipped += 1
                continue
            blob = wispr.execute(
                "SELECT audio FROM History WHERE transcriptEntityId = ?", (r["id"],)).fetchone()[0]
            if not blob or len(blob) <= MIN_WAV_BYTES:
                skipped += 1
                continue

            when = parse_ts(r["timestamp"]) or datetime.now(timezone.utc)
            local = when.astimezone()
            day = local.strftime("%Y-%m-%d")
            stem = "%s-%s" % (local.strftime("%H-%M-%S"), str(r["id"])[:8])
            os.makedirs(os.path.join(CORPUS, day), exist_ok=True)
            wav_rel = "%s/%s.wav" % (day, stem)
            txt_rel = "%s/%s.txt" % (day, stem)

            text = best_text(r["editedText"], r["formattedText"], r["asrText"])
            with open(os.path.join(CORPUS, wav_rel), "wb") as f:
                f.write(blob)
            with open(os.path.join(CORPUS, txt_rel), "w", encoding="utf-8") as f:
                f.write(text + "\n")

            facts = wav_facts(blob) or {}
            secs = facts.get("seconds") or (r["duration"] or 0.0)
            now = datetime.now(timezone.utc).isoformat()
            corpus.execute(
                "INSERT OR REPLACE INTO samples (id, source, ts, wav, txt, bytes, sha256,"
                " seconds, reported_secs, sample_rate, channels, bits, num_words, language,"
                " asr_text, formatted_text, edited_text, final_text, app, mic, harvested_at)"
                " VALUES (?,'wispr',?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                (r["id"], when.isoformat(), wav_rel, txt_rel, len(blob),
                 hashlib.sha256(blob).hexdigest(), secs, r["duration"],
                 facts.get("sample_rate"), facts.get("channels"), facts.get("bits"),
                 r["numWords"], r["detectedLanguage"] or r["language"],
                 r["asrText"], r["formattedText"], r["editedText"], text,
                 r["app"], r["micDevice"], now))

            manifest.write(json.dumps({
                "id": r["id"], "session": "harvest", "engine": "wispr",
                "ts": when.isoformat(), "wisprTs": r["timestamp"],
                "wav": wav_rel, "txt": txt_rel, "bytes": len(blob),
                "duration": secs, "words": r["numWords"],
                "detectedLanguage": r["detectedLanguage"] or r["language"],
                "app": r["app"], "mic": r["micDevice"],
                "asr": r["asrText"], "text": text,
            }, ensure_ascii=False) + "\n")

            known.add(r["id"])
            new += 1
            new_secs += secs
    finally:
        manifest.close()
    corpus.commit()
    return new, new_secs, skipped


def refresh(corpus, wispr):
    """Pick up corrections Wispr wrote after we had already taken the row."""
    cutoff = time.time() - REFRESH_DAYS * 86400
    since = datetime.fromtimestamp(cutoff, timezone.utc).isoformat()
    rows = corpus.execute(
        "SELECT id, asr_text, formatted_text, edited_text FROM samples"
        " WHERE source = 'wispr' AND ts >= ?", (since,)).fetchall()
    changed = 0
    for sid, asr, fmt, edited in rows:
        src = wispr.execute(
            "SELECT asrText, formattedText, editedText, numWords FROM History"
            " WHERE transcriptEntityId = ?", (sid,)).fetchone()
        if src is None:
            continue
        if (src["asrText"], src["formattedText"], src["editedText"]) == (asr, fmt, edited):
            continue
        text = best_text(src["editedText"], src["formattedText"], src["asrText"])
        corpus.execute(
            "UPDATE samples SET asr_text=?, formatted_text=?, edited_text=?, final_text=?,"
            " num_words=?, refreshed_at=? WHERE id=?",
            (src["asrText"], src["formattedText"], src["editedText"], text,
             src["numWords"], datetime.now(timezone.utc).isoformat(), sid))
        row = corpus.execute("SELECT txt FROM samples WHERE id=?", (sid,)).fetchone()
        if row and row[0]:
            path = os.path.join(CORPUS, row[0])
            try:
                with open(path, "w", encoding="utf-8") as f:
                    f.write(text + "\n")
            except OSError:
                pass
        changed += 1
    corpus.commit()
    return changed


def main():
    os.makedirs(CORPUS, exist_ok=True)
    lock = open(LOCK, "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except IOError:
        log("another harvest is already running; leaving it to it")
        return 0

    started = datetime.now(timezone.utc).isoformat()
    corpus = open_corpus()
    corpus.execute("INSERT OR REPLACE INTO runs (started_at) VALUES (?)", (started,))
    corpus.commit()

    err = None
    new = refreshed = skipped = 0
    new_secs = 0.0
    try:
        import_manifest(corpus)
        wispr = open_wispr()
        new, new_secs, skipped = harvest(corpus, wispr)
        refreshed = refresh(corpus, wispr)
        wispr.close()
        log("took %d new sample(s), %.1f min; refreshed %d; already had %d"
            % (new, new_secs / 60.0, refreshed, skipped))
    except Exception as exc:  # a failed run must still leave a trace
        err = "%s: %s" % (type(exc).__name__, exc)
        log("FAILED — %s" % err)
    finally:
        corpus.execute(
            "UPDATE runs SET finished_at=?, new_samples=?, new_seconds=?, refreshed=?,"
            " skipped=?, error=? WHERE started_at=?",
            (datetime.now(timezone.utc).isoformat(), new, new_secs, refreshed,
             skipped, err, started))
        corpus.commit()
        corpus.close()
    return 1 if err else 0


if __name__ == "__main__":
    sys.exit(main())
