#!/usr/bin/env python3
"""Label the corpus by dictating it back to Wispr Flow, overnight, in batch.

The student is the local `mlx-community/whisper-large-v3-turbo`; the teacher is
Wispr Flow; the label is whatever Wispr makes of the same audio. That is
knowledge distillation by pseudo-labelling, and the only reason it is worth the
machinery is the asymmetry it breaks: Wispr keeps its transcripts for ever and
its **recordings** for about a week, so harvesting its database can only ever
reach the last seven days. Recording the microphone ourselves and asking for the
label afterwards reaches everything.

    python3 helpers/teacher_label.py --limit 20 --dry-run   # what it would do
    python3 helpers/teacher_label.py --limit 20             # one careful batch
    python3 helpers/teacher_label.py --all                  # the overnight run

**Run `wispr_probe.py` first.** It answers the one question this cannot: whether
Wispr will take played-back audio at all. A batch started before that is a batch
that spends an hour in real time producing nothing.

## It runs in real time, and that is fine

A minute of audio costs a minute. Nothing about this is parallelisable — there
is one Wispr, one microphone and one keyboard — so `--all` over ten hours of
corpus is ten hours. It is a pass over an archive, run once, overnight, and it
is resumable: every sample's label is committed as it arrives, so a batch killed
at 3 a.m. carries on from where it stopped.

## The three things it refuses to do

1. **Type into the wrong window.** Wispr pastes into whatever has focus, so a
   batch is an hour of Victor's own speech typed into whatever was open. It
   checks the front app against an allow-list and stops.
2. **Take the keyboard without saying so.** It synthesises Wispr's push-to-talk
   chord thousands of times, so it raises the 🔒 hands-off locks for the whole
   run and drops them on the way out, including on Ctrl-C. Locks on screen mean
   *Victor does not touch anything* — and the only way he learns that is the
   locks, because he is not reading this terminal.
3. **Hammer somebody's service.** A pause between samples, and a run that gives
   up after enough consecutive failures rather than spending the night pressing
   a key at an app that has stopped answering.

## What it writes, and what it deliberately does not

`teacher_text` is Wispr's **`asrText`** — the recogniser's raw reading. Not
`formattedText`, which has been through Wispr's LLM for punctuation,
capitalisation and its custom dictionary: training a speech model on that would
teach the student to imitate a text model it does not have, and would score as
errors every comma it could not know about.

It never overwrites a label it has already written, and it never touches
`final_text` — for a `wispr` row that column is already Wispr's, and for an
`addons-mic` row the eventual reference may be a hand correction, which is the
only supervision in this whole corpus that could ever teach the student to
**beat** the teacher rather than imitate it.
"""

from __future__ import annotations

import argparse
import os
import signal
import sqlite3
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import wispr_loopback as rig  # noqa: E402

CORPUS = Path(
    os.environ.get(
        "VOICE_CORPUS_DIR", os.path.expanduser("~/.walkie-talkie/voice-corpus")
    )
)
CORPUS_DB = CORPUS / "corpus.db"
HANDS_OFF = Path.home() / "bin" / "hands-off"

SAFE_SINKS = {"TextEdit", "Notes", "Stickies", "Wispr Flow", "Finder"}

# Between samples. Not a rate limit anybody published — a courtesy, and the beat
# Wispr needs to finish pasting and settle before the next key goes down.
GAP_SEC = float(os.environ.get("WISPR_BATCH_GAP", "2.0"))
# Consecutive timeouts before giving up. Wispr having quit, lost its network or
# had its microphone changed all look identical from here, and none of them get
# better by pressing the key another four hundred times.
GIVE_UP_AFTER = int(os.environ.get("WISPR_BATCH_GIVE_UP", "5"))


def log(msg):
    print("%s  %s" % (datetime.now().strftime("%H:%M:%S"), msg), flush=True)


class HandsOff:
    """The four 🔒 on screen for the length of the batch.

    A context manager because the one unacceptable outcome is locks left up: they
    are the app-wide sign that an agent is driving, and a stale set says *do not
    touch your own Mac* for ever. `hands-off run` would do this for a single
    command; a long Python process wants the start/end pair, so the release has
    to be in a `finally` and in the signal handlers both.
    """

    def __init__(self, what):
        self.what = what
        self.up = False

    def __enter__(self):
        if not HANDS_OFF.exists():
            log("⚠️  no ~/bin/hands-off — running WITHOUT the on-screen locks")
            return self
        try:
            subprocess.run([str(HANDS_OFF), "start", self.what],
                           check=False, capture_output=True, timeout=10)
            self.up = True
        except Exception as exc:  # noqa: BLE001
            log(f"⚠️  could not raise the locks: {exc}")
        return self

    def __exit__(self, *exc):
        self.release()
        return False

    def release(self):
        if not self.up:
            return
        self.up = False
        try:
            subprocess.run([str(HANDS_OFF), "end"], check=False,
                           capture_output=True, timeout=10)
        except Exception:
            pass


def ensure_columns(db):
    have = {r[1] for r in db.execute("PRAGMA table_info(samples)")}
    for name, kind in (("teacher_text", "TEXT"), ("teacher_at", "TEXT"),
                       ("teacher_mic", "TEXT")):
        if name not in have:
            db.execute("ALTER TABLE samples ADD COLUMN %s %s" % (name, kind))
    db.commit()


def pending(db, limit, sources):
    """Unlabelled samples, shortest first.

    Shortest first is the whole scheduling policy and it is deliberate: the run
    is charged in wall-clock seconds of audio, so the cheap half of the corpus is
    labelled in the first fraction of the night. A batch that is killed early
    therefore leaves the most samples behind it, not the most *minutes*.
    """
    marks = ",".join("?" * len(sources))
    rows = db.execute(
        "SELECT id, wav, seconds, source, asr_text FROM samples"
        f" WHERE source IN ({marks})"
        "   AND (teacher_text IS NULL OR teacher_text = '')"
        "   AND wav IS NOT NULL AND seconds IS NOT NULL"
        "   AND seconds BETWEEN 1 AND 120"
        " ORDER BY seconds ASC" + (" LIMIT ?" if limit else ""),
        (*sources, limit) if limit else tuple(sources),
    ).fetchall()
    return [dict(r) for r in rows]


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--limit", type=int, default=20)
    ap.add_argument("--all", action="store_true", help="no limit — the overnight run")
    ap.add_argument("--device", help="virtual output device (substring)")
    ap.add_argument("--dry-run", action="store_true",
                    help="list what would be dictated, press nothing")
    ap.add_argument(
        "--source", action="append",
        help="which samples to label (default: addons-mic and whisper-local — "
             "the ones with no teacher reading. 'wispr' rows already have one)")
    args = ap.parse_args(argv)

    sources = args.source or ["addons-mic", "whisper-local"]
    limit = None if args.all else args.limit

    if not CORPUS_DB.exists():
        raise SystemExit(f"no corpus at {CORPUS_DB}")
    db = sqlite3.connect(CORPUS_DB, timeout=30)
    db.row_factory = sqlite3.Row
    ensure_columns(db)

    todo = pending(db, limit, sources)
    total_sec = sum(s["seconds"] or 0 for s in todo)
    log(f"{len(todo)} sample(s) to label, {total_sec/60:.0f} min of audio "
        f"→ about {(total_sec + len(todo) * (GAP_SEC + 3))/3600:.1f} h of wall clock")

    if args.dry_run:
        for s in todo[:40]:
            print(f"  {s['seconds']:6.1f}s  {s['source']:<13} {s['wav']}")
        if len(todo) > 40:
            print(f"  … and {len(todo) - 40} more")
        return 0
    if not todo:
        return 0

    idx, name = rig.resolve_device(args.device)
    log(f"device: {name}")
    if not rig.accessibility_ok():
        raise SystemExit(
            "Accessibility is not granted to this interpreter — CGEventPost does\n"
            "nothing and Wispr would never start recording. Grant it in System\n"
            "Settings → Privacy & Security → Accessibility.")
    front = rig.paste_sink()
    if front not in SAFE_SINKS:
        raise SystemExit(
            f"the front app is {front!r}, which is not a safe paste target.\n"
            "Wispr types its transcript into whatever has focus, and this batch is\n"
            f"about to do that {len(todo)} times. Open a blank TextEdit document,\n"
            "click into it, and start again. (Safe: " + ", ".join(sorted(SAFE_SINKS)) + ")")
    log(f"paste sink: {front}")

    locks = HandsOff(f"labelling {len(todo)} voice samples with Wispr Flow")
    # The locks have to come down on Ctrl-C and on a SIGTERM too, not only on a
    # clean exit — a killed batch that leaves them up is the failure this whole
    # wrapper exists to prevent.
    for sig in (signal.SIGINT, signal.SIGTERM):
        signal.signal(sig, lambda *_: (locks.release(), sys.exit(130)))

    done = failed = streak = 0
    started = time.monotonic()
    with locks:
        for i, s in enumerate(todo, 1):
            wav = CORPUS / s["wav"]
            if not wav.exists():
                log(f"  {i}/{len(todo)} missing {s['wav']} — skipped")
                continue
            heard = rig.dictate(wav, idx)
            if heard is None or not heard.asr.strip():
                failed += 1
                streak += 1
                log(f"  {i}/{len(todo)} ✗ no transcript ({s['seconds']:.1f}s) "
                    f"[{streak} in a row]")
                if streak >= GIVE_UP_AFTER:
                    log(f"giving up after {streak} consecutive failures — "
                        "check that Wispr is running and on the right microphone")
                    break
            else:
                streak = 0
                done += 1
                # Committed per sample, not per batch: the run is hours long and
                # a crash at 3 a.m. must cost one sample, not the night.
                db.execute(
                    "UPDATE samples SET teacher_text = ?, teacher_at = ?,"
                    " teacher_mic = ? WHERE id = ?",
                    (heard.asr, datetime.now(timezone.utc).isoformat(),
                     heard.mic, s["id"]))
                db.commit()
                log(f"  {i}/{len(todo)} ✓ {s['seconds']:5.1f}s  {heard.asr[:70]}")
            time.sleep(GAP_SEC)

    elapsed = (time.monotonic() - started) / 60
    log(f"done: {done} labelled, {failed} failed, {elapsed:.0f} min")
    left = db.execute(
        "SELECT COUNT(*) FROM samples WHERE (teacher_text IS NULL OR teacher_text = '')"
        f" AND source IN ({','.join('?' * len(sources))})", sources).fetchone()[0]
    log(f"{left} sample(s) still unlabelled")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
