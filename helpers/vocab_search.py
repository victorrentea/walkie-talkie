#!/usr/bin/env python3
"""Search for the `initial_prompt` vocabulary that helps the local recogniser most.

This is the harness behind `VOCABULARY_RO` in `whisper_helper.py`. Re-run it
before changing either prompt; the dev set overstated that change by 4x, and
only the held-out sets caught it.

Reference is Wispr's RAW `asr_text` (and, on the holdout, Victor's own
`edited_text` where he corrected it) — never the LLM-formatted text, which would
measure the formatter.

Everything is measured at parity with `helpers/whisper_helper.py`:
`condition_on_previous_text=False`, language pinned, turbo model.

Resumable: every (condition, clip) result is appended to a JSONL cache and
skipped on a re-run, so a kill (this Mac OOM-kills background work) costs only
the clip in flight.

  vocab_search.py split                 # build/print the dev/holdout split
  vocab_search.py run conds.json [dev|holdout]
  vocab_search.py score [dev|holdout]
  vocab_search.py subs <condition>      # mine substitutions ref->hyp
"""
import json
import os
import re
import sqlite3
import sys
import time
import unicodedata
import contextlib
import collections

CORPUS = os.path.expanduser("~/.walkie-talkie/voice-corpus")
DB = os.path.join(CORPUS, "corpus.db")
OUT = os.environ.get("VOCAB_SEARCH_OUT", os.path.join(CORPUS, "vocab-search"))
os.makedirs(OUT, exist_ok=True)
CACHE = os.path.join(OUT, "results.jsonl")
SPLIT = os.path.join(OUT, "split.json")
TURBO = "mlx-community/whisper-large-v3-turbo"

# ── scoring, lifted verbatim from helpers/corpus_baseline.py ────────────────


# Romanian is written with TWO encodings of the same two letters: the correct
# comma-below (ș U+0219, ț U+021B) and the legacy cedilla (ş U+015F, ţ U+0163).
# Wispr's transcripts mix them, so scoring without unifying them marks the local
# model wrong for spelling the letter the right way — 3 of the top-20 Romanian
# "errors" on the dev set were exactly this. Unify, then compare.
CEDILLA = str.maketrans({"\u015f": "\u0219", "\u015e": "\u0218",
                         "\u0163": "\u021b", "\u0162": "\u021a"})


def norm(s):
    s = unicodedata.normalize("NFC", (s or "").lower()).translate(CEDILLA)
    s = re.sub(r"[^\w\săâîșțĂÂÎȘȚ]", " ", s)
    return re.sub(r"\s+", " ", s).strip().split()


def strip_dia(words):
    t = str.maketrans("ăâîșț", "aaist")
    return [w.translate(t) for w in words]


def wer(ref, hyp):
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


def align(ref, hyp):
    """Levenshtein backtrace -> list of (op, ref_word, hyp_word)."""
    r, h = norm(ref), norm(hyp)
    n, m = len(r), len(h)
    d = [[0] * (m + 1) for _ in range(n + 1)]
    for i in range(n + 1):
        d[i][0] = i
    for j in range(m + 1):
        d[0][j] = j
    for i in range(1, n + 1):
        for j in range(1, m + 1):
            d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1,
                          d[i - 1][j - 1] + (r[i - 1] != h[j - 1]))
    i, j, ops = n, m, []
    while i > 0 or j > 0:
        if i > 0 and j > 0 and d[i][j] == d[i - 1][j - 1] + (r[i - 1] != h[j - 1]):
            ops.append(("ok" if r[i - 1] == h[j - 1] else "sub", r[i - 1], h[j - 1]))
            i, j = i - 1, j - 1
        elif i > 0 and d[i][j] == d[i - 1][j] + 1:
            ops.append(("del", r[i - 1], None)); i -= 1
        else:
            ops.append(("ins", None, h[j - 1])); j -= 1
    return list(reversed(ops))


# ── the sample set ──────────────────────────────────────────────────────────


def samples():
    con = sqlite3.connect(DB)
    con.row_factory = sqlite3.Row
    rows = con.execute("""
        select id, wav, seconds, language, asr_text, edited_text, app
        from samples
        where source='wispr'
          and trim(coalesce(asr_text,'')) <> ''
          and wav is not null
          and seconds between 1.0 and 60.0
        order by ts
    """).fetchall()
    con.close()
    out = []
    for r in rows:
        p = os.path.join(CORPUS, r["wav"])
        if os.path.exists(p):
            out.append(dict(r))
    return out


def build_split():
    rows = samples()
    edited = [r for r in rows if (r["edited_text"] or "").strip()]
    rest = [r for r in rows if not (r["edited_text"] or "").strip()]
    # dev: stratified by language and duration bucket, deterministic.
    def bucket(r):
        s = r["seconds"] or 0
        return (r["language"] or "?", "s" if s < 5 else "m" if s < 15 else "l")
    by = collections.defaultdict(list)
    for r in rest:
        by[bucket(r)].append(r)
    dev, extra = [], []
    per = int(os.environ.get("DEV_PER_BUCKET", "20"))
    for k in sorted(by):
        v = by[k]
        step = max(1, len(v) // per)
        picked = v[::step][:per]
        dev += picked
        extra += [r for r in v if r not in picked]
    split = {"dev": [r["id"] for r in dev],
             "holdout_edited": [r["id"] for r in edited],
             "holdout_rest": [r["id"] for r in extra[:400]]}
    json.dump(split, open(SPLIT, "w"), indent=1)
    idx = {r["id"]: r for r in rows}
    for name in ("dev", "holdout_edited", "holdout_rest"):
        sel = [idx[i] for i in split[name]]
        secs = sum(r["seconds"] or 0 for r in sel)
        langs = collections.Counter(r["language"] for r in sel)
        print("%-16s %4d clips  %6.1f min  %s"
              % (name, len(sel), secs / 60, dict(langs)))
    return split


def load_split(which):
    split = json.load(open(SPLIT))
    ids = set(split[which] if which != "holdout" else
              split["holdout_edited"] + split["holdout_rest"])
    return [r for r in samples() if r["id"] in ids]


def reference(r, which):
    if which == "holdout_edited" and (r["edited_text"] or "").strip():
        return r["edited_text"]
    return r["asr_text"]


# ── running ─────────────────────────────────────────────────────────────────


def done_keys():
    keys = set()
    if os.path.exists(CACHE):
        for line in open(CACHE, encoding="utf8", errors="replace"):
            try:
                d = json.loads(line)
                keys.add((d["cond"], d["id"]))
            except Exception:
                pass
    return keys


def run(conds_path, which):
    conds = json.load(open(conds_path))
    rows = load_split(which)
    done = done_keys()
    with open(os.devnull, "w") as d, contextlib.redirect_stdout(d), \
            contextlib.redirect_stderr(d):
        import mlx_whisper
        from mlx_whisper import audio as A
    todo = [(c, r) for c in conds for r in rows if (c["name"], r["id"]) not in done]
    print("conditions %d × clips %d -> %d to run (%d cached)"
          % (len(conds), len(rows), len(todo), len(conds) * len(rows) - len(todo)),
          flush=True)
    t0 = time.time()
    fh = open(CACHE, "a", encoding="utf8")
    for n, (c, r) in enumerate(todo, 1):
        path = os.path.join(CORPUS, r["wav"])
        kw = dict(path_or_hf_repo=c.get("model", TURBO), verbose=False,
                  condition_on_previous_text=False,
                  language=r["language"] if r["language"] in ("ro", "en") else None)
        if c.get("prompt"):
            kw["initial_prompt"] = c["prompt"]
        try:
            with open(os.devnull, "w") as dn, contextlib.redirect_stdout(dn), \
                    contextlib.redirect_stderr(dn):
                res = mlx_whisper.transcribe(A.load_audio(path), **kw)
            txt = res["text"]
            cr = max([s.get("compression_ratio", 0) for s in res.get("segments", [])] or [0])
        except Exception as e:
            txt, cr = "", -1.0
            print("  !! %s %s: %s" % (c["name"], r["id"][:8], e), flush=True)
        fh.write(json.dumps({"cond": c["name"], "id": r["id"], "split": which,
                             "text": txt, "cr": cr}, ensure_ascii=False) + "\n")
        fh.flush()
        if n % 25 == 0 or n == len(todo):
            el = time.time() - t0
            print("  %d/%d  %.0fs elapsed  eta %.0fs"
                  % (n, len(todo), el, el / n * (len(todo) - n)), flush=True)
    fh.close()


# ── scoring ─────────────────────────────────────────────────────────────────


def results(which):
    rows = {r["id"]: r for r in load_split(which)}
    by = collections.defaultdict(dict)
    if os.path.exists(CACHE):
        for line in open(CACHE, encoding="utf8", errors="replace"):
            try:
                d = json.loads(line)
            except Exception:
                continue
            if d["id"] in rows:
                by[d["cond"]][d["id"]] = d
    return rows, by


def score(which):
    rows, by = results(which)
    print("%-22s %6s %7s %7s %7s %6s" %
          ("condition", "n", "WER", "median", "loops", "words"))
    out = []
    for cond in sorted(by):
        errs = wds = 0
        pers, loops = [], 0
        for i, d in by[cond].items():
            e, n = wer(reference(rows[i], which), d["text"])
            if e is None:
                continue
            errs += e * n
            wds += n
            pers.append(e)
            if d.get("cr", 0) > 2.4:
                loops += 1
                if os.environ.get("LOOP_GUARD", "1") == "1":
                    errs -= e * n; wds -= n; pers.pop()
        if not wds:
            continue
        pers.sort()
        med = pers[len(pers) // 2]
        out.append((errs / wds, cond, len(pers), med, loops, wds))
        print("%-22s %6d %6.1f%% %6.1f%% %7d %6d"
              % (cond, len(pers), 100 * errs / wds, 100 * med, loops, wds))
    return out


def subs(cond, which="dev", top=40):
    rows, by = results(which)
    cnt = collections.Counter()
    for i, d in by.get(cond, {}).items():
        for op, rw, hw in align(reference(rows[i], which), d["text"]):
            if op == "sub":
                cnt[(rw, hw)] += 1
            elif op == "del":
                cnt[(rw, "∅")] += 1
    print("%-28s %-28s %s" % ("reference", "heard as", "n"))
    for (rw, hw), n in cnt.most_common(top):
        print("%-28s %-28s %d" % (rw, hw, n))
    return cnt


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "split"
    if cmd == "split":
        build_split()
    elif cmd == "run":
        run(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else "dev")
    elif cmd == "score":
        score(sys.argv[2] if len(sys.argv) > 2 else "dev")
    elif cmd == "subs":
        subs(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else "dev")
