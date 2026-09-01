#!/usr/bin/env python3
"""Mail Victor what the corpus has grown into, and how far it still has to go.

Runs daily and almost always decides to do nothing: a report goes out only when
`REPORT_EVERY_DAYS` have passed since the last one. A fortnightly cadence made of
a daily job that checks a date survives a closed lid, a reboot and a week in
another country, where a fortnightly timer just silently misses its slot.

No model is called here either. The numbers are SQL and the prose is a format
string.

## The estimate it carries

The report's second half answers the standing question — *how much is enough?* —
and the answer moves as the corpus grows, so it is recomputed every time rather
than written down once. The tiers in `TIERS` are the received wisdom on
fine-tuning a Whisper-class recogniser for **one known speaker**, which is a far
cheaper problem than training a general one: single voice, single pair of
microphones, a vocabulary that is mostly Romanian software-engineering shop talk.

The caveat in `label_quality` is the part that actually matters, and it is why
the report leads with it rather than burying it. Almost every label in this
corpus is *Wispr's own transcript*. Training on it is distillation: it can teach
a smaller local model to imitate Wispr on Victor's voice — genuinely useful, that
is the offline, free, private recogniser — but it cannot beat Wispr, because a
student never outgrows a teacher it is only ever shown agreeing with. Going past
Wispr needs labels Wispr did not write: the `editedText` column, where he fixed
the transcript by hand, or a deliberate pass of reading and correcting. So the
report counts those separately and always has.
"""

import json
import os
import sqlite3
import ssl
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone

HOME = os.path.expanduser("~")
CORPUS = os.environ.get("VOICE_CORPUS_DIR", os.path.join(HOME, ".walkie-talkie/voice-corpus"))
CORPUS_DB = os.path.join(CORPUS, "corpus.db")
BASELINE = os.path.join(CORPUS, "baseline.json")
ENV_FILE = os.path.join(HOME, ".claude/agentmail.env")

REPORT_EVERY_DAYS = 14
TO = "victorrentea@gmail.com"
INBOX = "victor.flux@agentmail.to"

# Hours of (audio, transcript) pairs, and what each buys for a single-speaker
# fine-tune. `target` marks the one the progress bar is drawn against.
TIERS = [
    (1,  "smoke test", "enough to prove the pipeline and measure a baseline WER. Not enough to train on.", False),
    (5,  "first real gains", "a LoRA adapter on whisper-small/medium starts picking up the accent and the recurring vocabulary.", False),
    (10, "practical critical mass", "a full fine-tune of whisper-small, or a strong LoRA on large-v3, with an hour held out to test on. This is the knee of the curve.", True),
    (25, "robust", "survives a different microphone, a noisy room and a bad day. Enough to hold out a real test set and still train on the rest.", False),
    (50, "past the knee", "only worth chasing if the goal stops being adaptation and becomes a model of its own.", False),
]
TARGET_HOURS = 10.0


def env(key):
    try:
        with open(ENV_FILE) as fh:
            for line in fh:
                if line.startswith(key + "="):
                    return line.split("=", 1)[1].strip()
    except OSError:
        pass
    return os.environ.get(key)


def recognition_quality():
    """The last measured gap between the local recogniser and Wispr.

    Written by `corpus_baseline.py`, which is run by hand rather than on a
    timer — the number only moves when a model or a decoding flag changes, and
    re-scoring an hour of audio to watch a constant is not worth the fans.
    Reported here so the fortnightly mail is the only thing worth opening.

    Clips scoring above 1.0 produced more wrong words than the reference holds:
    that is a collapse, not a bad transcript, so they are counted rather than
    averaged in, where a single one would swamp sixty good clips.
    """
    try:
        with open(BASELINE) as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        return None
    samples = data.get("samples") or []
    if not samples:
        return None
    conds = [k for k, v in samples[0].items() if isinstance(v, dict) and "wer" in v]
    when = datetime.utcfromtimestamp(os.path.getmtime(BASELINE)).strftime("%Y-%m-%d")
    rows = []
    for c in conds:
        vals = sorted(s[c]["wer"] or 0 for s in samples)
        ok = [s for s in samples if (s[c]["wer"] or 0) <= 1.0]
        words = sum(s[c]["words"] for s in ok) or 1
        rows.append((c,
                     100 * sum(s[c]["wer"] * s[c]["words"] for s in ok) / words,
                     100 * vals[len(vals) // 2],
                     len(samples) - len(ok)))
    return dict(when=when, n=len(samples), rows=rows)


def stats(db, since=None):
    where, args = "", []
    if since:
        where, args = " WHERE harvested_at >= ?", [since]
    row = db.execute(
        "SELECT COUNT(*), COALESCE(SUM(seconds),0), COALESCE(SUM(num_words),0),"
        " COALESCE(SUM(bytes),0) FROM samples" + where, args).fetchone()
    return dict(n=row[0], seconds=row[1], words=row[2], bytes=row[3])


def label_quality(db):
    corrected = db.execute(
        "SELECT COUNT(*), COALESCE(SUM(seconds),0) FROM samples"
        " WHERE edited_text IS NOT NULL AND trim(edited_text) <> ''").fetchone()
    return dict(n=corrected[0], seconds=corrected[1])


def daily_rate(db):
    """Minutes of audio per calendar day, over the span the corpus covers.

    Calendar days, not active days: the question the estimate answers is "how
    long until", and the silent days are part of how long.
    """
    row = db.execute(
        "SELECT COALESCE(SUM(seconds),0)/60.0, julianday(MAX(ts))-julianday(MIN(ts))"
        " FROM samples").fetchone()
    minutes, span = row[0], (row[1] or 0)
    return minutes / span if span and span >= 1 else 0.0


def fmt_hm(seconds):
    h, m = int(seconds // 3600), int((seconds % 3600) // 60)
    return ("%dh %02dm" % (h, m)) if h else ("%dm" % m)


def eta(hours_needed, rate_min_per_day):
    if rate_min_per_day <= 0:
        return "unknown — no measurable rate yet"
    days = hours_needed * 60.0 / rate_min_per_day
    if days <= 0:
        return "already there"
    if days < 60:
        return "~%d days" % round(days)
    return "~%.1f months" % (days / 30.4)


def build(db):
    st = db.execute("SELECT value FROM state WHERE key='last_report_at'").fetchone()
    last = st[0] if st else None
    total = stats(db)
    delta = stats(db, last) if last else total
    lq = label_quality(db)
    rate = daily_rate(db)
    hours = total["seconds"] / 3600.0
    pct = min(100.0, 100.0 * hours / TARGET_HOURS)

    by_src = db.execute(
        "SELECT source, COUNT(*), COALESCE(SUM(seconds),0) FROM samples"
        " GROUP BY source ORDER BY 3 DESC").fetchall()
    by_lang = db.execute(
        "SELECT COALESCE(language,'?'), COUNT(*), COALESCE(SUM(seconds),0) FROM samples"
        " GROUP BY 1 ORDER BY 3 DESC LIMIT 5").fetchall()
    runs = db.execute(
        "SELECT COUNT(*), SUM(error IS NOT NULL) FROM runs WHERE started_at >= ?",
        (last or "1970",)).fetchone()

    period = ("since the last report (%s)" % last[:10]) if last else "since collection began"
    subject = "Voice corpus — %s, %s of audio (%.0f%% of critical mass)" % (
        "{:,}".format(total["n"]), fmt_hm(total["seconds"]), pct)

    bar_w = 34
    filled = int(round(bar_w * pct / 100.0))
    bar = "█" * filled + "·" * (bar_w - filled)

    tier_rows = []
    for h, name, why, is_target in TIERS:
        need = max(0.0, h - hours)
        when = "reached" if need <= 0 else eta(need, rate)
        tier_rows.append((h, name, why, when, is_target))

    L = []
    L.append("VOICE CORPUS — fortnightly report")
    L.append("=" * 60)
    L.append("")
    L.append("New %s:" % period)
    L.append("  %s dictations, %s of audio, %s words"
             % ("{:,}".format(delta["n"]), fmt_hm(delta["seconds"]), "{:,}".format(delta["words"])))
    L.append("  harvest ran %d times, %d failed" % (runs[0] or 0, runs[1] or 0))
    L.append("")
    L.append("Corpus total:")
    L.append("  %s dictations, %s of audio, %s words, %.1f GB on disk"
             % ("{:,}".format(total["n"]), fmt_hm(total["seconds"]),
                "{:,}".format(total["words"]), total["bytes"] / 1073741824.0))
    for src, n, secs in by_src:
        L.append("    %-14s %5d  %s" % (src, n, fmt_hm(secs)))
    L.append("  languages: " + ", ".join("%s %d" % (l, n) for l, n, _ in by_lang))
    L.append("  current rate: %.1f min/day" % rate)
    L.append("")
    L.append("Progress to critical mass (%.0f h)" % TARGET_HOURS)
    L.append("  [%s] %.1f%%   %s of %.0fh" % (bar, pct, fmt_hm(total["seconds"]), TARGET_HOURS))
    L.append("  at the current rate: %s" % eta(max(0.0, TARGET_HOURS - hours), rate))
    L.append("")
    L.append("How much is enough")
    L.append("-" * 60)
    for h, name, why, when, is_target in tier_rows:
        L.append("  %s%2dh  %-24s %s" % (">" if is_target else " ", h, name, when))
        L.append("        %s" % why)
    L.append("")
    rq = recognition_quality()
    if rq:
        L.append("Local recogniser vs Wispr  (%d clips, measured %s)" % (rq["n"], rq["when"]))
        L.append("-" * 60)
        for name, wer, med, collapses in rq["rows"]:
            L.append("  %-12s WER %5.1f%%   median %5.1f%%   collapses %d"
                     % (name, wer, med, collapses))
        L.append("  Lower is closer to Wispr. Re-measure with:")
        L.append("    python3 walkie-talkie/helpers/corpus_baseline.py")
        L.append("")
    L.append("The label problem")
    L.append("-" * 60)
    L.append("  Human-corrected labels: %d of %d samples (%s)."
             % (lq["n"], total["n"], fmt_hm(lq["seconds"])))
    L.append("  Everything else is labelled with Wispr's own transcript, which")
    L.append("  makes this a distillation set: it can teach a local model to")
    L.append("  match Wispr on your voice — offline, free, private — but it")
    L.append("  cannot teach it to beat Wispr. For that the labels have to come")
    L.append("  from somewhere Wispr isn't: the text you fixed by hand, or a")
    L.append("  deliberate correction pass over a held-out hour.")
    L.append("")
    L.append("  Corpus: %s" % CORPUS)
    L.append("  Query it:  sqlite3 %s" % CORPUS_DB)
    return subject, "\n".join(L)


def send(subject, body):
    key = env("AGENTMAIL_API_KEY")
    if not key:
        raise RuntimeError("AGENTMAIL_API_KEY not found in %s" % ENV_FILE)
    payload = json.dumps({
        "to": [TO],
        "subject": subject,
        "text": body,
        "html": "<pre style=\"font:13px ui-monospace,SFMono-Regular,Menlo,monospace;"
                "line-height:1.45;white-space:pre-wrap\">%s</pre>"
                % body.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"),
    }).encode("utf-8")
    req = urllib.request.Request(
        "https://api.agentmail.to/v0/inboxes/%s/messages/send" % INBOX,
        data=payload, method="POST",
        headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=45, context=ssl.create_default_context()) as r:
        return r.status


def main():
    argv = sys.argv[1:]
    force = "--force" in argv
    dry = "--dry-run" in argv

    if not os.path.exists(CORPUS_DB):
        print("no corpus database yet at %s" % CORPUS_DB)
        return 0
    db = sqlite3.connect(CORPUS_DB, timeout=30)
    db.execute("CREATE TABLE IF NOT EXISTS state (key TEXT PRIMARY KEY, value TEXT)")

    now = datetime.now(timezone.utc)
    row = db.execute("SELECT value FROM state WHERE key='last_report_at'").fetchone()
    if row and not force and not dry:
        try:
            last = datetime.fromisoformat(row[0])
            age = (now - last).total_seconds() / 86400.0
            if age < REPORT_EVERY_DAYS:
                print("last report was %.1f days ago; next one at %d" % (age, REPORT_EVERY_DAYS))
                return 0
        except ValueError:
            pass

    subject, body = build(db)
    if dry:
        print(subject)
        print()
        print(body)
        return 0
    try:
        send(subject, body)
    except (urllib.error.URLError, RuntimeError) as exc:
        # Leave the watermark alone so the next daily run tries again.
        print("send failed, will retry tomorrow: %s" % exc)
        return 1
    db.execute("INSERT OR REPLACE INTO state (key, value) VALUES ('last_report_at', ?)",
               (now.isoformat(),))
    db.commit()
    print("report sent to %s" % TO)
    return 0


if __name__ == "__main__":
    sys.exit(main())
