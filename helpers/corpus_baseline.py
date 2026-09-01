#!/usr/bin/env python3
"""How far behind Wispr is the local recogniser, on Victor's own voice?

Nothing about a fine-tune can be decided before this number exists. If the local
model already matches Wispr on these WAVs there is nothing to train; if it is far
behind, this is the bar the training has to clear, measured on the same audio.

The reference is Wispr's `asrText` — its *raw* recogniser output, not the
`formattedText` an LLM punctuated afterwards. Scoring a raw transcript against a
formatted one measures the formatter, which is not what is being asked.

Two conditions, because the cheap one might be enough:
  plain    — the local model as the relay runs it today
  prompted — the same model, handed Victor's 67-word Wispr dictionary as an
             `initial_prompt`. Whisper conditions on that text, so names it has
             never heard ("Rentea", "JPQL", "agentmail") stop being guessed
             phonetically. This costs no training at all.
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
MODEL = os.environ.get("RELAY_WHISPER_MODEL", "mlx-community/whisper-large-v3-turbo")
N = int(os.environ.get("BASELINE_N", "60"))


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
    print("scoring %d samples against Wispr's raw ASR, model=%s" % (len(rows), MODEL), flush=True)

    w = sqlite3.connect("file:%s?mode=ro" % WISPR, uri=True)
    terms = [r[0] for r in w.execute(
        "SELECT phrase FROM Dictionary WHERE isDeleted=0 ORDER BY frequencyUsed DESC LIMIT 60")]
    prompt = ", ".join(terms)
    print("dictionary prompt: %d terms\n" % len(terms), flush=True)

    import mlx_whisper
    out = []
    for i, (sid, wav, ref, secs, lang) in enumerate(rows, 1):
        path = os.path.join(CORPUS, wav)
        rec = {"id": sid, "seconds": secs, "language": lang}
        for cond, kw in (("plain", {}), ("prompted", {"initial_prompt": prompt})):
            try:
                txt = mlx_whisper.transcribe(path, path_or_hf_repo=MODEL, **kw)["text"]
            except Exception as e:
                print("  %s failed on %s: %s" % (cond, sid[:8], e), flush=True)
                txt = ""
            e, n = wer(ref, txt)
            rec[cond] = {"wer": e, "words": n, "text": txt}
        print("%3d/%d  %-8s plain=%.3f prompted=%.3f" %
              (i, len(rows), sid[:8], rec["plain"]["wer"] or 0, rec["prompted"]["wer"] or 0),
              flush=True)
        out.append(rec)

    with open(os.path.join(CORPUS, "baseline.json"), "w") as f:
        json.dump({"model": MODEL, "n": len(out), "samples": out}, f, ensure_ascii=False, indent=1)

    for cond in ("plain", "prompted"):
        errs = sum((r[cond]["wer"] or 0) * r[cond]["words"] for r in out)
        words = sum(r[cond]["words"] for r in out)
        print("\n%-9s corpus WER = %.1f%%  (%d reference words)" % (cond, 100 * errs / words, words))


if __name__ == "__main__":
    sys.exit(main())
