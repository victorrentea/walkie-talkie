#!/usr/bin/env python3
"""Where do the student and the teacher agree, on the same audio?

Victor's plan is to use Wispr Flow as the teacher for a fine-tune of the local
recogniser. Before an overnight batch (`helpers/teacher_label.py`) is worth
running, one number decides the whole thing: **how often do the two already say
the same words?**

The 1197 clips of `source='wispr'` carry Wispr's own raw reading in `asr_text`,
so the teacher's label is already there and only the student's is missing. This
decodes each of them locally and scores the two against each other.

There is no ground truth here and the script does not pretend there is. WER is a
**disagreement rate**, not an error rate; it says where the two recognisers part
company, which is the only thing that can be measured without Victor reading.
What it buys:

- **high agreement** -> those clips are free labels: two independent recognisers
  agreeing on the same audio is about as good as pseudo-labelling gets, and
  nobody has to read them.
- **the disagreements** are the review pile, and their size is the real cost of
  the plan.

**Decoded through `helpers/whisper_helper.py`**, not through bare `mlx_whisper`:
the shipped decoder pins the language to {ro, en} and passes `VOCABULARY` as
`initial_prompt`, and a number measured on any other decoder is about a program
Victor does not run (the lesson `evals/marker-phrases.py` paid for).

    python3 evals/teacher-agreement.py --limit 100     # a first read, ~8 min
    python3 evals/teacher-agreement.py                 # all of them
    python3 evals/teacher-agreement.py --report        # re-print, decode nothing

Resumable: every clip is appended to `evals/work/teacher-agreement.jsonl` as it
finishes, and a second run skips what is already there.
"""
from __future__ import annotations
import argparse
import json
import os
import re
import sqlite3
import sys
import unicodedata
import wave

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CORPUS = os.path.expanduser("~/.walkie-talkie/voice-corpus")
DB = os.path.join(CORPUS, "corpus.db")
OUT = os.path.join(ROOT, "evals", "work", "teacher-agreement.jsonl")


def norm(s):
    """Compare words, not typography. Diacritics stay -- they are phonemic in Romanian."""
    s = unicodedata.normalize("NFC", (s or "").lower())
    s = re.sub(r"[^\w\săâîșțĂÂÎȘȚ]", " ", s)
    return re.sub(r"\s+", " ", s).strip().split()


def fold(s):
    """`norm`, with the diacritics taken off as well.

    Romanian diacritics are phonemic, so folding them would be wrong in a real
    WER -- but this is not one. Both sides here are *recognisers writing down the
    same sound*, and `Da-mi` against `Dă-mi` is a spelling both of them chose, not
    a word one of them misheard. Reported beside the strict figure rather than
    instead of it.
    """
    t = unicodedata.normalize("NFD", (s or "").lower())
    t = "".join(c for c in t if unicodedata.category(c) != "Mn")
    t = t.replace("ș", "s").replace("ț", "t")
    t = re.sub(r"[^\w\s]", " ", t)
    return re.sub(r"\s+", " ", t).strip().split()


def numeric_gap(ref, hyp):
    """Did exactly one of them write a number as digits?

    `cincizeci de mii de euro` against `50.000 de euro` is four substitutions and
    zero mishearings, and Wispr's raw output and Whisper's differ on this
    systematically. It inflates every WER in this file, so it is counted rather
    than corrected -- spelling one side into the other is its own guess.
    """
    dr = bool(re.search(r"\d", ref or ""))
    dh = bool(re.search(r"\d", hyp or ""))
    return dr != dh


def edit_rate(r, h):
    if not r:
        return None, 0
    prev = list(range(len(h) + 1))
    for i in range(1, len(r) + 1):
        cur = [i] + [0] * len(h)
        for j in range(1, len(h) + 1):
            cur[j] = min(prev[j] + 1, cur[j - 1] + 1,
                         prev[j - 1] + (r[i - 1] != h[j - 1]))
        prev = cur
    return prev[len(h)] / len(r), len(r)


def wer(ref, hyp):
    return edit_rate(norm(ref), norm(hyp))


def wer_folded(ref, hyp):
    return edit_rate(fold(ref), fold(hyp))


def dbfs(path):
    """Mean level of the WAV, because a quiet clip is a different measurement.

    Wispr-harvested recordings sit around -35 dB and this app's own around -27;
    a student that looks bad on quiet audio is being told about the gain, not
    about the model. Reported per clip so the split can be checked afterwards.
    """
    try:
        import array
        import math
        with wave.open(path, "rb") as w:
            if w.getsampwidth() != 2:
                return None
            data = array.array("h", w.readframes(w.getnframes()))
        if not data:
            return None
        rms = math.sqrt(sum(float(s) * s for s in data) / len(data))
        return round(20 * math.log10(max(rms, 1e-9) / 32768.0), 1)
    except Exception:
        return None


_HELPER = None


def local(path):
    global _HELPER
    if _HELPER is None:
        # The helper is a daemon: its last statement iterates stdin. Handing it
        # an empty one lets the import finish instead of blocking here.
        sys.stdin = open(os.devnull)
        sys.path.insert(0, os.path.join(ROOT, "helpers"))
        import whisper_helper
        _HELPER = whisper_helper
    return _HELPER.transcribe(path)


def rows(limit, shuffle):
    db = sqlite3.connect("file:" + DB + "?mode=ro", uri=True)
    q = ("SELECT id, wav, asr_text, seconds, language FROM samples"
         " WHERE source='wispr' AND asr_text IS NOT NULL AND trim(asr_text) != ''"
         " ORDER BY id")
    out = [r for r in db.execute(q) if r[1]]
    if shuffle:
        # Deterministic, so a --limit read and the full run share their prefix.
        import random
        random.Random(20260915).shuffle(out)
    return out[:limit] if limit else out


def load():
    if not os.path.exists(OUT):
        return {}
    done = {}
    with open(OUT) as f:
        for line in f:
            try:
                r = json.loads(line)
            except ValueError:
                continue
            done[r["id"]] = r
    return done


def report(done):
    recs = [r for r in done.values() if r.get("wer") is not None]
    if not recs:
        print("nothing measured yet")
        return
    vals = sorted(r["wer"] for r in recs)
    n = len(recs)

    def pct(p):
        return 100 * vals[min(n - 1, int(p * n))]

    words = sum(r["words"] for r in recs)
    pooled = 100 * sum(r["wer"] * r["words"] for r in recs) / max(words, 1)
    print("\n%d clips, %d reference words, %.1f h of audio"
          % (n, words, sum(r["seconds"] or 0 for r in recs) / 3600))
    print("pooled disagreement (WER vs Wispr's raw asr): %.1f%%" % pooled)
    fold_recs = [r for r in recs if r.get("wer_folded") is not None]
    if fold_recs:
        fw = sum(r["words"] for r in fold_recs) or 1
        print("the same with diacritics folded:               %.1f%%"
              % (100 * sum(r["wer_folded"] * r["words"] for r in fold_recs) / fw))
    gaps = [r for r in recs if r.get("numeric_gap")]
    if gaps:
        print("clips where only one side wrote a number in digits: %d (%.1f%%)"
              % (len(gaps), 100 * len(gaps) / n))
    print("median %.1f%%   p25 %.1f%%   p75 %.1f%%   p90 %.1f%%"
          % (pct(.5), pct(.25), pct(.75), pct(.9)))

    print("\nwhere the two stand:")
    bands = [("identical (word for word)", lambda e: e == 0),
             ("<= 5%  — free labels", lambda e: 0 < e <= .05),
             ("5-15%  — a word or two", lambda e: .05 < e <= .15),
             ("15-40% — the review pile", lambda e: .15 < e <= .40),
             ("> 40%  — one of them is wrong", lambda e: e > .40)]
    for name, f in bands:
        k = len([r for r in recs if f(r["wer"])])
        print("  %-30s %4d  %5.1f%%" % (name, k, 100 * k / n))

    print("\nfree labels at a threshold (no reading required):")
    for t in (.00, .05, .10, .15, .20):
        k = len([r for r in recs if r["wer"] <= t])
        print("  WER <= %2d%%   %4d clips  (%.1f%%)  -> %4d left to review"
              % (100 * t, k, 100 * k / n, n - k))

    print("\nby language:")
    for lang in sorted({r.get("language") or "?" for r in recs}):
        sub = [r for r in recs if (r.get("language") or "?") == lang]
        w = sum(r["words"] for r in sub) or 1
        print("  %-3s %4d clips  pooled %.1f%%  median %.1f%%"
              % (lang, len(sub),
                 100 * sum(r["wer"] * r["words"] for r in sub) / w,
                 100 * sorted(r["wer"] for r in sub)[len(sub) // 2]))

    print("\nby duration:")
    for lo, hi in ((0, 3), (3, 5), (5, 10), (10, 20), (20, 1e9)):
        sub = [r for r in recs if lo <= (r["seconds"] or 0) < hi]
        if not sub:
            continue
        w = sum(r["words"] for r in sub) or 1
        print("  %5s-%-5s s  %4d clips  pooled %.1f%%  median %.1f%%"
              % (lo, "" if hi > 1e8 else hi, len(sub),
                 100 * sum(r["wer"] * r["words"] for r in sub) / w,
                 100 * sorted(r["wer"] for r in sub)[len(sub) // 2]))

    lv = [r["dbfs"] for r in recs if r.get("dbfs") is not None]
    if lv:
        lv.sort()
        print("\nlevel: median %.1f dBFS  (p10 %.1f, p90 %.1f)"
              % (lv[len(lv) // 2], lv[int(.1 * len(lv))], lv[int(.9 * len(lv))]))

    # A collapse is the student failing, not the two disagreeing, and it is the
    # one failure a pseudo-label pipeline must never file as a label.
    coll = [r for r in recs if r["wer"] > 1.0]
    print("\ncollapses (student produced more wrong words than the reference has): %d"
          % len(coll))
    worst = sorted(recs, key=lambda r: -r["wer"])[:5]
    print("\nthe five furthest apart:")
    for r in worst:
        print("  %.2f  %5.1fs  %s" % (r["wer"], r["seconds"] or 0, r["id"][:8]))
        print("      wispr: %s" % (r["ref"] or "")[:150])
        print("      local: %s" % (r["hyp"] or "")[:150])


def gold(done):
    """The one place in this corpus with something better than a vote.

    `edited_text` is what Victor changed Wispr's transcript to by hand, and it is
    the only column neither recogniser wrote. It is **not clean ground truth**:
    83 of the 149 differ from `asr_text` in their words at all, and among those
    are him tidying his own stutters (`Vreau să, vreau să` -> `Vreau să`) as well
    as him fixing a mishearing. It is also selected *for* Wispr having been
    wrong, which is exactly the set Wispr scores worst on.

    So the absolute numbers here mean little. What means something is that both
    recognisers are scored against the **same** biased reference, on the same
    audio: if the teacher is not clearly ahead here, distilling from it buys
    nothing.
    """
    db = sqlite3.connect("file:" + DB + "?mode=ro", uri=True)
    ref = {r[0]: r[1] for r in db.execute(
        "SELECT id, edited_text FROM samples"
        " WHERE edited_text IS NOT NULL AND trim(edited_text) != ''")}
    pairs = []
    for sid, victor in ref.items():
        rec = done.get(sid)
        if not rec:
            continue
        w, n = wer(victor, rec["ref"])          # teacher against Victor
        l, _ = wer(victor, rec["hyp"])          # student against Victor
        if w is None or l is None:
            continue
        pairs.append((sid, n, w, l, norm(victor) != norm(rec["ref"])))
    if not pairs:
        print("no hand-edited clip has been decoded yet")
        return
    for label, sub in (("all hand-edited clips", pairs),
                       ("only those Victor really changed", [p for p in pairs if p[4]])):
        if not sub:
            continue
        words = sum(p[1] for p in sub) or 1
        tw = 100 * sum(p[2] * p[1] for p in sub) / words
        sw = 100 * sum(p[3] * p[1] for p in sub) / words
        better = len([p for p in sub if p[3] < p[2]])
        tie = len([p for p in sub if p[3] == p[2]])
        print("\n%s (%d clips, %d words)" % (label, len(sub), words))
        print("  Wispr  vs Victor's own text: %.1f%%" % tw)
        print("  local  vs Victor's own text: %.1f%%" % sw)
        print("  clips where the student is closer: %d   tied: %d   teacher closer: %d"
              % (better, tie, len(sub) - better - tie))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--shuffle", action="store_true", default=True)
    ap.add_argument("--report", action="store_true", help="print what is measured, decode nothing")
    ap.add_argument("--gold", action="store_true",
                    help="score both recognisers against Victor's hand-edited text")
    a = ap.parse_args()

    done = load()
    if a.gold:
        return gold(done)
    if a.report:
        report(done)
        return gold(done)

    todo = [r for r in rows(a.limit, a.shuffle) if r[0] not in done]
    print("%d clips already measured, %d to decode" % (len(done), len(todo)), flush=True)

    with open(OUT, "a") as f:
        for i, (sid, wav, ref, secs, lang) in enumerate(todo, 1):
            path = os.path.join(CORPUS, wav)
            if not os.path.exists(path):
                continue
            try:
                res = local(path)
                hyp = (res.get("text") or "").strip()
            except Exception as exc:  # noqa: BLE001 — one bad clip is not the run
                print("  %s failed: %s" % (sid[:8], exc), flush=True)
                continue
            e, n = wer(ref, hyp)
            ef, _ = wer_folded(ref, hyp)
            rec = {"id": sid, "seconds": secs, "language": lang, "wer": e,
                   "wer_folded": ef, "numeric_gap": numeric_gap(ref, hyp),
                   "words": n, "ref": ref, "hyp": hyp, "dbfs": dbfs(path),
                   "avg_logprob": res.get("avg_logprob"),
                   "compression_ratio": res.get("compression_ratio"),
                   "local_language": res.get("language")}
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
            f.flush()
            done[sid] = rec
            if i % 10 == 0 or i == len(todo):
                print("%4d/%d  %s  wer=%.2f" % (i, len(todo), sid[:8], e or 0), flush=True)

    report(done)
    gold(done)


if __name__ == "__main__":
    sys.exit(main())
