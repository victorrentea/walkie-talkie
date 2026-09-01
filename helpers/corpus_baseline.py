#!/usr/bin/env python3
"""How far behind Wispr is the local recogniser, on Victor's own voice?

Nothing about a fine-tune can be decided before this number exists. If the local
model already matches Wispr on these WAVs there is nothing to train; if it is far
behind, this is the bar the training has to clear, measured on the same audio.

The reference is Wispr's `asrText` — its *raw* recogniser output, not the
`formattedText` an LLM punctuated afterwards. Scoring a raw transcript against a
formatted one measures the formatter, which is not what is being asked.

Every condition is measured **at parity with the relay**, which is the lesson
the first version of this script taught the hard way: it left
`condition_on_previous_text` at the library default of True, where
`whisper_helper.py` has always set it False. Two clips in sixty collapsed into a
repetition loop and dragged the corpus figure from 20% to 42% — a defect of the
measurement, not of anything Victor runs. A benchmark that does not match
production measures the benchmark.

The conditions are the levers that cost no training: which model, and the
decoding thresholds that decide when Whisper retries a segment it is unsure of.
"""

import json
import os
import re
import sqlite3
import sys
import unicodedata

CORPUS = os.path.expanduser("~/.walkie-talkie/voice-corpus")
DB = os.path.join(CORPUS, "corpus.db")
WISPR = os.path.expanduser("~/Library/Application Support/Wispr Flow/flow.sqlite")
N = int(os.environ.get("BASELINE_N", "60"))

TURBO = "mlx-community/whisper-large-v3-turbo"   # what the relay runs today
LARGE = "mlx-community/whisper-large-v3-mlx"     # slower, better on non-English

# How the relay actually calls it. Anything measured against something else is
# measuring a program Victor does not run.
RELAY = dict(language=None, verbose=False, condition_on_previous_text=False)

CONDITIONS = [
    ("turbo", TURBO, RELAY),
    ("large-v3", LARGE, RELAY),
]


def norm(s):
    """Compare words, not typography. Diacritics stay — they are phonemic in Romanian."""
    s = unicodedata.normalize("NFC", (s or "").lower())
    s = re.sub(r"[^\w\săâîșțĂÂÎȘȚ]", " ", s)
    return re.sub(r"\s+", " ", s).strip().split()


def wer(ref, hyp):
    """Word error rate by Levenshtein over tokens."""
    r, h = norm(ref), norm(hyp)
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


def main():
    db = sqlite3.connect(DB)
    rows = db.execute(
        "SELECT id, wav, asr_text, seconds, language FROM samples"
        " WHERE source='wispr' AND asr_text IS NOT NULL AND length(trim(asr_text)) > 40"
        "   AND seconds BETWEEN 4 AND 30"
        " ORDER BY id LIMIT ?", (N,)).fetchall()
    print("scoring %d samples against Wispr's raw ASR" % len(rows), flush=True)

    import mlx_whisper
    out = []
    for i, (sid, wav, ref, secs, lang) in enumerate(rows, 1):
        path = os.path.join(CORPUS, wav)
        rec = {"id": sid, "seconds": secs, "language": lang}
        for cond, model, kw in CONDITIONS:
            try:
                txt = mlx_whisper.transcribe(path, path_or_hf_repo=model, **kw)["text"]
            except Exception as exc:
                print("  %s failed on %s: %s" % (cond, sid[:8], exc), flush=True)
                txt = ""
            e, n = wer(ref, txt)
            rec[cond] = {"wer": e, "words": n, "text": txt}
        print("%3d/%d  %-8s  %s" % (i, len(rows), sid[:8],
              "  ".join("%s=%.3f" % (c, rec[c]["wer"] or 0) for c, _, _ in CONDITIONS)),
              flush=True)
        out.append(rec)

    with open(os.path.join(CORPUS, "baseline.json"), "w") as f:
        json.dump({"n": len(out), "samples": out}, f, ensure_ascii=False, indent=1)

    print("")
    for cond, model, _ in CONDITIONS:
        vals = sorted(r[cond]["wer"] or 0 for r in out)
        errs = sum((r[cond]["wer"] or 0) * r[cond]["words"] for r in out)
        words = sum(r[cond]["words"] for r in out)
        # A clip scoring above 1.0 produced more wrong words than the reference
        # has: that is a collapse, not a bad transcript, and it is reported
        # separately rather than allowed to swamp the average.
        ok = [r for r in out if (r[cond]["wer"] or 0) <= 1.0]
        oke = sum(r[cond]["wer"] * r[cond]["words"] for r in ok)
        okw = sum(r[cond]["words"] for r in ok)
        print("%-10s WER %.1f%%  median %.1f%%  p90 %.1f%%  collapses %d/%d"
              % (cond, 100 * oke / okw, 100 * vals[len(vals) // 2],
                 100 * vals[int(0.9 * len(vals))], len(out) - len(ok), len(out)))


if __name__ == "__main__":
    sys.exit(main())
