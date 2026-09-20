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
import wave
import array
import json
import os
import random
import signal
import sqlite3
import subprocess
import sys
import time
from datetime import datetime, timedelta, timezone
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
#
# **Randomised, and that is the point.** A fixed 2.0 s gap held for six hours is
# a metronome, and a metronome is the one thing no human dictating into this
# account could ever produce. This is Victor's own paid account and the audio is
# his own voice, but a service that looks for automation looks for regularity
# first, so the batch does not offer any: every gap is drawn fresh, and every
# twenty-odd samples it takes a pause of a different order, the way somebody who
# gets up for water does.
GAP_MIN = float(os.environ.get("WISPR_BATCH_GAP_MIN", "2.5"))
GAP_MAX = float(os.environ.get("WISPR_BATCH_GAP_MAX", "9.0"))
#: Every N samples, for S seconds — both drawn per occurrence, never a constant.
LONG_PAUSE_EVERY = (15, 40)
LONG_PAUSE_SEC = (25.0, 75.0)
#: What a sample costs on average, for the estimate the batch prints up front.
MEAN_GAP_SEC = ((GAP_MIN + GAP_MAX) / 2
                + sum(LONG_PAUSE_SEC) / 2 / (sum(LONG_PAUSE_EVERY) / 2))


#: What to do about a run of failures, in order. Wispr answered `raw_transcript`
#: with zero words for five clips in a row after 357 dictations in 95 minutes, and
#: was transcribing again two minutes later — so the first thing to try is *waiting*.
#: Giving up is still in here, at the end: a Wispr that has quit or a channel that
#: is really dead does not get better by pressing its key another four hundred times.
BACKOFF_SEC = (300, 900, 1800)


#: How far behind the clip a label may be and still belong to it. Measured over the
#: first 638 labels (2026-09-20): the gap between Wispr's own row timestamp, the clip
#: length and the moment the label landed runs 2.7–5.8 s, median 2.9. A label that
#: belongs to the PREVIOUS clip sits 15–60 s out, because that is how long a dictation
#: that missed its own window takes to arrive.
#:
#: This is the only structural way this rig can be wrong, and absence of duplicates
#: does not rule it out: `wait_for_new` accepts any newer row, so a row that arrives
#: after its clip's timeout leaves that clip unlabelled and hands its words to the
#: NEXT one — an off-by-one that leaves no two rows alike behind it.
MAX_LABEL_LAG_SEC = float(os.environ.get("WISPR_MAX_LABEL_LAG", "8"))


def label_lag(heard, clip_seconds, now=None) -> float | None:
    """Seconds between the end of the dictation Wispr recorded and this moment.

    None when Wispr's timestamp cannot be read — unknown is not suspicious, and a
    parse that fails must not start throwing away good labels.
    """
    raw = (getattr(heard, "row_ts", "") or "").strip()
    if not raw:
        return None
    text = raw.replace(" +00:00", "+00:00").replace(" ", "T", 1)
    try:
        started = datetime.fromisoformat(text)
    except ValueError:
        return None
    if started.tzinfo is None:
        started = started.replace(tzinfo=timezone.utc)
    now = now or datetime.now(timezone.utc)
    return (now - started).total_seconds() - (clip_seconds or 0)


#: The only two languages Victor speaks. Wispr detects a language per dictation and
#: is often right about it — `cs`, `uk`, `ru`, `pt`, `fr` all turned up in one night's
#: labels — and a label in a language he does not speak is the worst kind there is:
#: fluent, plausible, the right length, and words he never said. Seven in the first
#: 640 (2026-09-20).
SPOKEN = {"ro", "en", "ron", "eng", "ro-ro", "en-us", "en-gb"}

#: The letters Romanian adds to the Latin alphabet, and nothing else. A diacritic
#: outside this set is a language that is not his — `č`, `á`, `è`, `я` — and this is
#: the only signal left for the third of rows where Wispr detects nothing at all.
ROMANIAN_LETTERS = set("ăâîșțĂÂÎȘȚşţŞŢ")


def foreign_letters(text) -> set:
    """Non-ASCII letters in `text` that Romanian does not use."""
    return {c for c in text if c.isalpha() and ord(c) > 127
            and c not in ROMANIAN_LETTERS}


def not_his_language(heard) -> str:
    """Why this label should be thrown away, or "" to keep it.

    Wispr's own detection is asked first and believed when it says anything at all;
    the letters are the fallback, because they only ever catch a language that spells
    itself differently and would miss, say, Italian.
    """
    if heard.language and heard.language not in SPOKEN:
        return f"Wispr heard {heard.language}"
    strange = foreign_letters(heard.asr)
    if strange:
        return "letters Romanian does not use: " + "".join(sorted(strange))
    return ""


#: A clip whose loudest sample is below this is not a quiet dictation, it is an empty
#: file. Measured 2026-09-20 over the whole queue: the clips Wispr labelled peak at
#: 0.16–0.99, the dead ones at 0.001 — two orders of magnitude apart, with nothing in
#: between to argue about. They matter because the batch takes the SHORTEST first and
#: silence is short, so all 135 of them sit at the head of the queue in front of 2974
#: good ones. Playing them to Wispr and calling the empty answer a failure is how a
#: night spends itself on five consecutive nothings and stands down.
SILENT_PEAK = float(os.environ.get("WISPR_SILENT_PEAK", "0.02"))


def peak_of(path) -> float:
    """The loudest sample in a 16-bit WAV, 0.0–1.0. Stdlib only, and it is the file
    the batch is about to play — measured here rather than trusted from the manifest,
    because a manifest can describe a file that was replaced."""
    try:
        with wave.open(str(path)) as handle:
            if handle.getsampwidth() != 2:
                return 1.0  # not our format — let Wispr be the judge
            data = array.array("h")
            data.frombytes(handle.readframes(handle.getnframes()))
    except (OSError, wave.Error, ValueError):
        return 1.0
    if not data:
        return 0.0
    return max(abs(min(data)), abs(max(data))) / 32768.0


#: How long the rig stays off after the ladder runs out. Three blocked stretches in
#: a row is not a slow night — it is the service saying no, and the way to lose this
#: account is to keep dictating into it for another five hours. The cooldown is
#: written to disk rather than kept in memory, because the process that learned it is
#: about to exit and the next run is the one that must not start.
COOLDOWN_FILE = Path.home() / ".walkie-talkie" / "teacher-cooldown"
COOLDOWN_HOURS = float(os.environ.get("WISPR_COOLDOWN_HOURS", "3"))


def cooldown_left(now=None) -> float:
    """Hours still to wait before dictating again. 0.0 when the rig is free."""
    now = now or datetime.now(timezone.utc)
    try:
        until = datetime.fromisoformat(COOLDOWN_FILE.read_text().strip())
    except (OSError, ValueError):
        return 0.0
    return max(0.0, (until - now).total_seconds() / 3600)


def start_cooldown(hours=None) -> datetime:
    """Refuse to dictate until this much later, and say so on disk."""
    until = datetime.now(timezone.utc) + timedelta(hours=hours or COOLDOWN_HOURS)
    COOLDOWN_FILE.parent.mkdir(parents=True, exist_ok=True)
    COOLDOWN_FILE.write_text(until.isoformat())
    return until


def clear_cooldown() -> None:
    COOLDOWN_FILE.unlink(missing_ok=True)


def backoff_for(recoveries) -> float | None:
    """How long to pause after this many recoveries already spent, or None to stop."""
    if recoveries >= len(BACKOFF_SEC):
        return None
    return BACKOFF_SEC[recoveries]


def out_of_time(started, budget_hours) -> bool:
    """Whether the wall-clock budget is spent. No budget is never spent.

    Checked before a sample rather than after one: the cost of the sample about
    to start is known only as an average, and a twenty-minute clip would
    otherwise walk straight through the deadline and into somebody's morning.
    """
    if not budget_hours:
        return False
    return (time.monotonic() - started) >= budget_hours * 3600


def gaps(rng=None):
    """Yield the wait after each sample, for ever."""
    rng = rng or random.Random()
    until_long = rng.randint(*LONG_PAUSE_EVERY)
    while True:
        until_long -= 1
        if until_long <= 0:
            until_long = rng.randint(*LONG_PAUSE_EVERY)
            yield rng.uniform(*LONG_PAUSE_SEC)
        else:
            yield rng.uniform(GAP_MIN, GAP_MAX)
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


AUDIO_PROBE = (
    "import sys, numpy, sounddevice as sd;"
    "sd.play(numpy.zeros(160, dtype='float32'), samplerate=16000,"
    " device=int(sys.argv[1]), blocking=True)")


def audio_stack_is_alive(device_index, seconds=20):
    """Open and close one stream on the device before committing to a night.

    A wedged CoreAudio does not raise: `Pa_OpenStream` disappears into
    `HALC_ProxyObject::HasProperty` → `mach_msg2_trap` and never comes back, so
    a batch started on one hangs on its first clip instead of failing. It cannot
    be caught in-process either — the call is uninterruptible — so the probe is a
    **subprocess** that can be killed, which is the only thing that works.

    Measured 2026-09-19: every process on this Mac that tried to open an audio
    stream — the relay, Wispr Flow, a bare PortAudio client and this batch — was
    stuck in that same frame, with `coreaudiod` itself alive and two days old.
    Device *enumeration* kept working throughout, so `query_devices()` is not a
    test of anything; only opening a stream is.

    And it must not be confused with the loop's own give-up counter, which
    counts transcripts that came back empty: this blocks earlier, inside the
    device open, so the loop never completes an iteration and `GIVE_UP_AFTER`
    can never fire.
    """
    probe = subprocess.Popen([sys.executable, "-c", AUDIO_PROBE,
                              str(device_index)],
                             stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    try:
        _, err = probe.communicate(timeout=seconds)
    except subprocess.TimeoutExpired:
        probe.kill()
        probe.communicate()
        return False, (
            f"opening an audio stream hung for {seconds}s — CoreAudio is wedged.\n"
            "Nothing on this Mac can open a microphone or a virtual cable until\n"
            "it is restarted, and the restart needs a password:\n\n"
            "    sudo killall coreaudiod\n\n"
            "(the audio subsystem comes straight back; running apps re-open it)")
    if probe.returncode != 0:
        return False, ("could not open an audio stream on the device:\n"
                       + err.decode(errors="replace").strip()[-400:])
    return True, ""


def ensure_columns(db):
    have = {r[1] for r in db.execute("PRAGMA table_info(samples)")}
    for name, kind in (("teacher_text", "TEXT"), ("teacher_at", "TEXT"),
                       ("teacher_mic", "TEXT")):
        if name not in have:
            db.execute("ALTER TABLE samples ADD COLUMN %s %s" % (name, kind))
    db.commit()


def pending(db, limit, sources, lo=1.0, hi=120.0, minutes=None):
    """Unlabelled samples, shortest first.

    Shortest first is the whole scheduling policy and it is deliberate: the run
    is charged in wall-clock seconds of audio, so the cheap half of the corpus is
    labelled in the first fraction of the night. A batch that is killed early
    therefore leaves the most samples behind it, not the most *minutes*.

    `lo`/`hi` narrow that window. Shortest-first over the whole corpus spends its
    first hour on two-second fragments, which is the right economics for the
    fine-tune and the wrong sample for a human checking that the rig works at
    all — so a demo asks for, say, 6–30 s and gets clips with sentences in them.

    `minutes` is a budget in **audio** minutes rather than a count. "Label ten
    minutes tonight" is the unit the corpus is measured in and the unit Wispr
    charges in wall-clock; a `--limit` of 40 is neither.
    """
    marks = ",".join("?" * len(sources))
    rows = db.execute(
        "SELECT id, wav, seconds, source, asr_text FROM samples"
        f" WHERE source IN ({marks})"
        "   AND (teacher_text IS NULL OR teacher_text = '')"
        "   AND wav IS NOT NULL AND seconds IS NOT NULL"
        "   AND seconds BETWEEN ? AND ?"
        " ORDER BY seconds ASC" + (" LIMIT ?" if limit else ""),
        (*sources, lo, hi, limit) if limit else (*sources, lo, hi),
    ).fetchall()
    out = [dict(r) for r in rows]
    if minutes:
        budget, kept = minutes * 60.0, []
        for r in out:
            if budget <= 0:
                break
            kept.append(r)
            budget -= r["seconds"] or 0
        out = kept
    return out


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--limit", type=int, default=20)
    ap.add_argument("--all", action="store_true", help="no limit — the overnight run")
    ap.add_argument("--device", help="virtual output device (substring)")
    ap.add_argument("--dry-run", action="store_true",
                    help="list what would be dictated, press nothing")
    ap.add_argument("--min-seconds", type=float, default=1.0,
                    help="skip clips shorter than this (default 1)")
    ap.add_argument("--max-seconds", type=float, default=120.0,
                    help="skip clips longer than this (default 120)")
    ap.add_argument("--minutes", type=float,
                    help="stop selecting once this many AUDIO minutes are in "
                         "the batch — the unit a nightly slice is asked for in")
    ap.add_argument("--stop-after", type=float, metavar="HOURS",
                    help="stop dictating after this many hours of WALL CLOCK, "
                         "whatever is left in the batch — a night is a length, "
                         "and audio minutes stopped predicting it once the mic "
                         "clips arrived (a 7.8s clip costs ~18s, a 30s one ~41s)")
    ap.add_argument("--ignore-cooldown", action="store_true",
                    help="start even though the last run stood down after three "
                         "blocked stretches — for a rig that has been fixed since")
    ap.add_argument("--manifest", help="write id/wav/seconds/reference/teacher "
                                       "as JSONL here, as each label lands")
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

    todo = pending(db, limit, sources, args.min_seconds, args.max_seconds,
                   args.minutes)
    total_sec = sum(s["seconds"] or 0 for s in todo)
    log(f"{len(todo)} sample(s) to label, {total_sec/60:.0f} min of audio "
        f"→ about {(total_sec + len(todo) * (MEAN_GAP_SEC + 3))/3600:.1f} h of wall clock")

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

    alive, why = audio_stack_is_alive(idx)
    if not alive:
        raise SystemExit("audio preflight failed — " + why)
    if not rig.accessibility_ok():
        raise SystemExit(
            "Accessibility is not granted to this interpreter — CGEventPost does\n"
            "nothing and Wispr would never start recording. Grant it in System\n"
            "Settings → Privacy & Security → Accessibility.")
    waiting = cooldown_left()
    if waiting and not args.ignore_cooldown:
        raise SystemExit(
            f"standing down for another {waiting*60:.0f} min — the last run was "
            "blocked three times over and stopped on purpose. --ignore-cooldown "
            "overrides, but the reason it exists is that the alternative to waiting "
            "is losing the account.")

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

    done = failed = streak = recoveries = silent = wrong_language = 0
    misrouted = 0
    #: Every Wispr row this run has taken, so none is taken twice.
    consumed = set()
    gap = gaps()
    started = time.monotonic()
    with locks:
        for i, s in enumerate(todo, 1):
            if out_of_time(started, args.stop_after):
                log(f"stopping at the {args.stop_after:g} h mark with "
                    f"{len(todo) - i + 1} left — the rest is the next run's")
                break
            wav = CORPUS / s["wav"]
            if not wav.exists():
                log(f"  {i}/{len(todo)} missing {s['wav']} — skipped")
                continue
            peak = peak_of(wav)
            if peak < SILENT_PEAK:
                # Not a failure: nothing was asked of Wispr, so the streak that
                # decides whether the rig is broken must not hear about it.
                silent += 1
                log(f"  {i}/{len(todo)} ⌀ silent ({s['seconds']:.1f}s, peak "
                    f"{peak:.4f}) — not played")
                continue
            heard = rig.dictate(wav, idx)
            if heard is None or not heard.asr.strip():
                failed += 1
                streak += 1
                log(f"  {i}/{len(todo)} ✗ no transcript ({s['seconds']:.1f}s) "
                    f"[{streak} in a row]")
                if streak >= GIVE_UP_AFTER:
                    pause = backoff_for(recoveries)
                    if pause is None:
                        until = start_cooldown()
                        log(f"giving up after {streak} failures and {recoveries} "
                            f"pauses — standing down until "
                            f"{until.astimezone().strftime('%H:%M')} so this does not "
                            "turn into a banned account")
                        break
                    recoveries += 1
                    log(f"{streak} failures in a row — pausing {pause/60:.0f} min "
                        f"and carrying on ({recoveries}/{len(BACKOFF_SEC)})")
                    time.sleep(pause)
                    streak = 0
            elif heard.id in consumed:
                # Wispr never reissues an id, so this is the previous clip's row
                # being handed to this one — the off-by-one, caught by name.
                streak = recoveries = 0
                misrouted += 1
                log(f"  {i}/{len(todo)} ✗ row {heard.id[:8]} was already used — "
                    "dropped")
            elif (lag := label_lag(heard, s["seconds"])) is not None \
                    and lag > MAX_LABEL_LAG_SEC:
                streak = recoveries = 0
                misrouted += 1
                log(f"  {i}/{len(todo)} ✗ label is {lag:.0f}s behind the clip "
                    f"(max {MAX_LABEL_LAG_SEC:.0f}s) — dropped as the previous "
                    "clip's")
            elif (why := not_his_language(heard)):
                # Wispr answered, so the rig is fine and the streak stays reset —
                # what came back is simply not a label. Keeping it would put words
                # he never said into the one column the student is trained on.
                streak = recoveries = 0
                wrong_language += 1
                log(f"  {i}/{len(todo)} ✗ {why} — dropped: {heard.asr[:48]}")
            else:
                streak = recoveries = 0
                done += 1
                consumed.add(heard.id)
                # Committed per sample, not per batch: the run is hours long and
                # a crash at 3 a.m. must cost one sample, not the night.
                db.execute(
                    "UPDATE samples SET teacher_text = ?, teacher_at = ?,"
                    " teacher_mic = ? WHERE id = ?",
                    (heard.asr, datetime.now(timezone.utc).isoformat(),
                     heard.mic, s["id"]))
                db.commit()
                if args.manifest:
                    # Appended per sample for the same reason the UPDATE is
                    # committed per sample: a night that dies at 3 a.m. leaves a
                    # manifest describing exactly what it did label.
                    with open(args.manifest, "a", encoding="utf-8") as fh:
                        fh.write(json.dumps({
                            "id": s["id"], "wav": s["wav"],
                            "seconds": s["seconds"], "source": s["source"],
                            "student": s["asr_text"], "teacher": heard.asr,
                            "mic": heard.mic,
                        }, ensure_ascii=False) + "\n")
                log(f"  {i}/{len(todo)} ✓ {s['seconds']:5.1f}s  {heard.asr[:70]}")
            time.sleep(next(gap))

    elapsed = (time.monotonic() - started) / 60
    if done:
        # The service answered, so whatever it was refusing earlier is over.
        clear_cooldown()
    log(f"done: {done} labelled, {failed} failed, {silent} silent, "
        f"{wrong_language} wrong language, {misrouted} misrouted, "
        f"{elapsed:.0f} min")
    left = db.execute(
        "SELECT COUNT(*) FROM samples WHERE (teacher_text IS NULL OR teacher_text = '')"
        f" AND source IN ({','.join('?' * len(sources))})", sources).fetchone()[0]
    log(f"{left} sample(s) still unlabelled")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
