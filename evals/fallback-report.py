#!/usr/bin/env python3
"""What the local transcript prepared ahead actually did — read back from `fallback.jsonl`.

Victor, 2026-09-29: *"I want clear logging to understand the actual behaviour retroactively."*
The relay appends one JSON object per armed sentence to `~/.walkie-talkie/fallback.jsonl` at its
outcome (`AutoLocal.Trace`; the same fields as relay.log's `📊 fallback:` line, seconds from the
microphone's close):

    engine audio budget quantile samples unclamped cap localEta specPlanned specStart localReady
    engineAnswer engineFailed budgetExpired rowShown outcome wasted toWords note

    python3 evals/fallback-report.py                 # the summary, per engine
    python3 evals/fallback-report.py --since 2026-09-29T08:00
    python3 evals/fallback-report.py --tail 20       # the last lines, one per sentence
    python3 evals/fallback-report.py --budgets       # replay decode-rate.jsonl: p95 budgets for 5/15/30 s

`--budgets` recomputes `DecodeRate.budget` in Python (Theil–Sen over the engine's newest 100 warm
samples × the 0.95 quantile of the residual ratios, clamped to [1.5 s, 0.3 × audio + 1 s]; under 20
samples the prior × 3) and the local model's `localEta` (the chip's line over its newest 50 warm
samples, + 0.3 s), so the schedule can be checked against his own data without the app.
No dependencies beyond the standard library.
"""
import argparse
import json
import os
import statistics
import sys

HOME = os.path.expanduser(os.environ.get("WT_HOME", "~/.walkie-talkie"))


def quantile(values, p):
    """`DecodeRate.quantile`: linear interpolation between neighbouring order statistics."""
    if not values:
        return 0.0
    s = sorted(values)
    if len(s) == 1:
        return s[0]
    k = p * (len(s) - 1)
    lo, hi = int(k), min(int(k) + 1, len(s) - 1)
    return s[lo] + (s[hi] - s[lo]) * (k - lo)


def clamp(v, lo, hi):
    return min(hi, max(lo, v))


def load_jsonl(path):
    out = []
    try:
        with open(path) as f:
            for line in f:
                try:
                    out.append(json.loads(line))
                except ValueError:
                    pass   # a torn tail line, as DecodeRate.load skips it
    except FileNotFoundError:
        pass
    return out


# ------------------------------------------------------------------ the summary

def pct(n, d):
    return f"{100.0 * n / d:.0f}%" if d else "—"


def secs(v):
    return f"{v:.2f}s" if v is not None else "—"


def summary(rows):
    by = {}
    for r in rows:
        by.setdefault(r.get("engine", "?"), []).append(r)
    if not by:
        print("no sentences in fallback.jsonl yet (the relay writes one per armed sentence at its outcome)")
        return
    for engine, rs in sorted(by.items()):
        n = len(rs)
        outcomes = {}
        for r in rs:
            outcomes[r.get("outcome") or "?"] = outcomes.get(r.get("outcome") or "?", 0) + 1
        started = [r for r in rs if r.get("specStart") is not None]
        wasted = [r for r in started if r.get("wasted")]
        ready = [r for r in rs if r.get("localReady") is not None and r.get("note") != "the local model gave no words"]
        ready_in_time = [r for r in ready if r["localReady"] <= r["budget"] + 1e-6]
        expired = [r for r in rs if r.get("budgetExpired") is not None]
        delivered = [r["toWords"] for r in rs if r.get("toWords") is not None
                     and (r.get("outcome") in ("engine", "local-forced", "local-fallback"))]
        lateness = [r["localReady"] - r["budget"] for r in ready]
        forced_wait = [r["toWords"] - r["localReady"] for r in rs
                       if r.get("outcome") == "local-forced" and r.get("localReady") is not None and r.get("toWords") is not None]
        print(f"\n{engine}: {n} sentences")
        print("  outcome      " + ", ".join(f"{k} {v} ({pct(v, n)})" for k, v in sorted(outcomes.items(), key=lambda kv: -kv[1])))
        print(f"  local-forced {pct(outcomes.get('local-forced', 0), n)} (⌘⌃X on the words decoded ahead, or by hand)")
        print(f"  decodes      {len(started)} run ahead, {len(wasted)} wasted ({pct(len(wasted), len(started))} of those run)")
        print(f"  local ready  before the budget {len(ready_in_time)}/{len(ready)} ({pct(len(ready_in_time), len(ready))}); "
              f"localReady − budget p50 {secs(quantile(lateness, 0.5) if lateness else None)}, "
              f"p95 {secs(quantile(lateness, 0.95) if lateness else None)}")
        print(f"  budget       expired on {len(expired)}/{n} ({pct(len(expired), n)}); budget p50 "
              f"{secs(quantile([r['budget'] for r in rs], 0.5))}, localEta p50 {secs(quantile([r['localEta'] for r in rs], 0.5))}")
        print(f"  toWords      p50 {secs(quantile(delivered, 0.5) if delivered else None)}, "
              f"p95 {secs(quantile(delivered, 0.95) if delivered else None)} (from the close, delivered sentences)")
        if forced_wait:
            print(f"  ⌘⌃X          pressed {secs(quantile(forced_wait, 0.5))} (p50) after Use local went up")


def tail(rows, n):
    for r in rows[-n:]:
        def s(k):
            v = r.get(k)
            return f"{v:.2f}" if isinstance(v, (int, float)) and not isinstance(v, bool) else "never"
        print(f"{r.get('at', '?')}  {r.get('engine')} audio={s('audio')} budget={s('budget')}(n={r.get('samples')}) "
              f"localEta={s('localEta')} specStart={s('specStart')} localReady={s('localReady')} "
              f"engineAnswer={s('engineAnswer')} budgetExpired={s('budgetExpired')} outcome={r.get('outcome')} "
              f"wasted={r.get('wasted')} toWords={s('toWords')}" + (f" — {r['note']}" if r.get("note") else ""))


# ------------------------------------------------------------------ --budgets: DecodeRate, replayed

PRIORS = {"elevenlabs": (0.9, 0.08), "wispr-flow": (0.6, 0.004)}
FALLBACK_PRIOR = (0.3, 0.045)
MIN_GAP = 1.0


def engine_key(d):
    return d.get("engine") or "whisper-local"


def theil_sen(window):
    slopes = []
    for i in range(len(window)):
        for j in range(i + 1, len(window)):
            dx = window[j]["audio"] - window[i]["audio"]
            if abs(dx) >= MIN_GAP:
                slopes.append((window[j]["decode"] - window[i]["decode"]) / dx)
    slope = clamp(quantile(slopes, 0.5), 0.0, 0.6) if slopes else 0.0
    intercept = clamp(quantile([w["decode"] - slope * w["audio"] for w in window], 0.5), 0.0, 5.0)
    return intercept, slope


def budget(samples, engine, audio, q=0.95):
    window = [d for d in samples if not d.get("cold") and engine_key(d) == engine][-100:]
    cap = 0.3 * audio + 1.0
    if len(window) < 20:
        i, s = PRIORS.get(engine, FALLBACK_PRIOR)
        unclamped, line, tail_x = (i + s * audio) * 3.0, (i, s), 3.0
    else:
        line = theil_sen(window)
        tail_x = clamp(quantile([w["decode"] / max(0.05, line[0] + line[1] * w["audio"]) for w in window], q), 1.0, 6.0)
        unclamped = (line[0] + line[1] * audio) * tail_x
    b = max(1.5, min(cap, unclamped))
    if engine == "wispr-flow":
        b *= 1.1  # AutoLocal.wisprPatience (2026-10-27)
    return b, unclamped, cap, len(window), line, tail_x


def local_typical(samples, audio):
    """`DecodeRate.fit(...).typical` on the local model's newest 50 warm samples."""
    window = [d for d in samples if not d.get("cold") and engine_key(d) == "whisper-local"][-50:]
    pi, ps = FALLBACK_PRIOR
    if not window:
        return max(0.3, pi + ps * audio)
    if len(window) < 8:
        scale = clamp(quantile([w["decode"] / max(0.05, pi + ps * w["audio"]) for w in window], 0.5), 0.33, 3.0)
        return max(0.3, (pi + ps * audio) * scale)
    i, s = theil_sen(window)
    return max(0.3, i + s * audio)


def budgets(path, audios=(5, 15, 30)):
    samples = load_jsonl(path)
    print(f"{path}: {len(samples)} lines")
    for engine in ("elevenlabs", "wispr-flow"):
        _, _, _, n, line, tail_x = budget(samples, engine, 10)
        print(f"\n{engine}: {n} warm samples in the window — line {line[0]:.2f} + {line[1]:.3f} × a, tail × {tail_x:.2f} (p95)")
        for a in audios:
            b, unc, cap, _, _, _ = budget(samples, engine, a)
            eta = local_typical(samples, a) + 0.3
            print(f"  {a:>3} s: budget {b:.1f} s (unclamped {unc:.1f}, cap {cap:.1f}) · localEta {eta:.2f} s "
                  f"→ the local decode starts +{max(0.0, b - eta):.1f} s after the close")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--file", default=os.path.join(HOME, "fallback.jsonl"))
    ap.add_argument("--since", help="ISO-8601 prefix; only lines at or after it")
    ap.add_argument("--tail", type=int, help="print the last N sentences, one line each")
    ap.add_argument("--budgets", action="store_true", help="replay decode-rate.jsonl: p95 budgets for 5/15/30 s")
    ap.add_argument("--decode-rate", default=os.path.join(HOME, "decode-rate.jsonl"))
    ap.add_argument("--include-test", action="store_true",
                    help="keep desk runs' sentences (\"test\": true — the fake Scribe, a fake History, a forced budget)")
    args = ap.parse_args()
    if args.budgets:
        budgets(args.decode_rate)
        return
    rows = load_jsonl(args.file)
    skipped = 0 if args.include_test else sum(1 for r in rows if r.get("test"))
    if not args.include_test:
        rows = [r for r in rows if not r.get("test")]
    if args.since:
        rows = [r for r in rows if str(r.get("at", "")) >= args.since]
    if args.tail:
        tail(rows, args.tail)
        return
    print(f"{args.file}: {len(rows)} sentences" + (f" ({skipped} desk-run lines left out; --include-test)" if skipped else ""))
    summary(rows)


if __name__ == "__main__":
    sys.exit(main())
