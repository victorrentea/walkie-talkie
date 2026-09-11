#!/usr/bin/env python3
"""The ten-minute go/no-go for using Wispr Flow as a teacher.

Everything downstream — the batch labeller, the WERs, the LoRA — rests on one
question that no amount of design settles: **will Wispr transcribe audio that
did not come from a real microphone?** If it filters by device, or refuses a
virtual input, or garbles played-back audio badly enough that its transcript is
no better than the local model's, the idea dies here and nothing else should be
built.

So this is the first thing to run and it answers four questions in order,
stopping at the first `NO-GO`:

    1. is the channel there?        a virtual output/input device, Accessibility,
                                    a harmless place for the paste to land
    2. does Wispr hear it at all?   play one WAV, get a row out of flow.sqlite
    3. is the channel clean?        replay N samples Wispr has ALREADY
                                    transcribed from its own microphone and
                                    compare its two readings of the same audio
    4. is it worth it?              compare Wispr's reading against the local
                                    model's on the same clips — a teacher that
                                    agrees with the student teaches nothing

Question 3 is the one worth being careful about, and it is why this probe exists
rather than "play a file and look at the output". A transcript that comes back
*plausible* proves only that something was heard. The corpus already holds
hundreds of clips with Wispr's own reading of them attached — so replaying those
compares Wispr to Wispr on identical audio, and any difference is the loopback.

    python3 helpers/wispr_probe.py            # all four, 5 replay samples
    python3 helpers/wispr_probe.py --n 20     # the 20 he actually asked for
    python3 helpers/wispr_probe.py --stage 1  # just the setup check

Needs the framework interpreter (numpy, sounddevice, Quartz), not
`/usr/bin/python3`.
"""

from __future__ import annotations

import argparse
import os
import random
import sqlite3
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import wispr_loopback as rig  # noqa: E402

CORPUS = Path(
    os.environ.get(
        "VOICE_CORPUS_DIR", os.path.expanduser("~/.walkie-talkie/voice-corpus")
    )
)
CORPUS_DB = CORPUS / "corpus.db"

# Apps whose windows can absorb a paste without damage. Wispr types its result
# into whatever has focus, and a batch that types an hour of speech into an
# editor is not a batch, it is an incident.
SAFE_SINKS = {"TextEdit", "Notes", "Stickies", "Wispr Flow", "Finder"}


def say(ok, text):
    print(("  ✅ " if ok else "  ❌ ") + text)
    return ok


def words(text):
    return [w for w in "".join(c.lower() if c.isalnum() or c.isspace() else " "
                              for c in (text or "")).split() if w]


def wer(reference, hypothesis):
    """Levenshtein over words, normalised by the reference. 0.0 is identical.

    Written out rather than pulled in, for `corpus_baseline.py`'s reason: this
    is twenty lines and a dependency in a probe is one more thing that can be
    the reason the probe did not run.
    """
    r, h = words(reference), words(hypothesis)
    if not r:
        return 0.0 if not h else 1.0
    prev = list(range(len(h) + 1))
    for i, rw in enumerate(r, 1):
        cur = [i] + [0] * len(h)
        for j, hw in enumerate(h, 1):
            cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (rw != hw))
        prev = cur
    return prev[-1] / len(r)


# ── 1 · the channel ──────────────────────────────────────────────────────────
def stage_setup(device_name):
    print("1 · the channel")
    ok = True
    try:
        idx, name = rig.resolve_device(device_name)
        ok &= say(True, f"virtual device: {name} (index {idx})")
    except SystemExit as exc:
        say(False, str(exc).splitlines()[0])
        print(
            "\n     Loopback is installed on this Mac and already publishes\n"
            "     🎙️TO Zoom / 🔊OS Output. Create a device named '🎓 TO Wispr'\n"
            "     and point Wispr's microphone at it, or pass --device."
        )
        return False, None

    ok &= say(rig.accessibility_ok(),
              "Accessibility granted (CGEventPost can press Wispr's key)")
    if not rig.accessibility_ok():
        print("     System Settings → Privacy & Security → Accessibility → "
              "add this terminal.")

    ok &= say(os.path.exists(rig.WISPR_DB), f"Wispr database readable")

    front = rig.paste_sink()
    safe = front in SAFE_SINKS
    say(safe, f"front app is {front!r}" + ("" if safe else " — NOT a safe paste target"))
    if not safe:
        print("     Wispr pastes its transcript into whatever has focus.")
        print("     Open a blank TextEdit document and click into it first.")
    ok &= safe
    return ok, idx


# ── 2 · does Wispr hear it ───────────────────────────────────────────────────
def stage_hears(idx, db):
    print("\n2 · does Wispr hear a played-back file at all")
    row = pick_samples(db, 1)
    if not row:
        return say(False, "no corpus sample with a Wispr transcript to try")
    sample = row[0]
    wav = CORPUS / sample["wav"]
    print(f"     playing {sample['wav']} ({sample['seconds']:.1f}s) …")
    started = time.monotonic()
    heard = rig.dictate(wav, idx)
    took = time.monotonic() - started
    if heard is None:
        say(False, f"no transcript after {took:.0f}s — Wispr heard nothing")
        print("\n     THIS IS THE NO-GO. Either Wispr's microphone is not set to")
        print("     the virtual device, or its push-to-talk keys have moved")
        print("     (WISPR_PTT_KEYS, currently %s)." % rig.PTT_KEYS)
        return False
    say(True, f"heard {len(words(heard.asr))} words in {took:.0f}s, mic={heard.mic!r}")
    print(f"     wispr (loopback): {heard.asr[:100]}")
    print(f"     wispr (original): {(sample['asr'] or '')[:100]}")
    return True


# ── 3 · is the channel clean ─────────────────────────────────────────────────
def pick_samples(db, n, seed=20260911):
    """Corpus rows Wispr transcribed from its *own* microphone, with the WAV.

    Only `source='wispr'` rows qualify: they are the ones where the reference is
    Wispr's own reading of that exact audio, which is what makes stage 3 a
    comparison of the channel rather than of two recognisers.
    """
    rows = db.execute(
        "SELECT id, wav, seconds, asr_text AS asr, final_text FROM samples"
        " WHERE source = 'wispr' AND asr_text IS NOT NULL AND asr_text != ''"
        "   AND seconds BETWEEN 3 AND 25"
        " ORDER BY ts DESC LIMIT 400"
    ).fetchall()
    rows = [dict(r) for r in rows if (CORPUS / r["wav"]).exists()]
    random.Random(seed).shuffle(rows)
    return rows[:n]


def stage_clean(idx, db, n):
    print(f"\n3 · is the channel clean — {n} clips Wispr has already read once")
    samples = pick_samples(db, n)
    if not samples:
        return say(False, "no usable samples"), []
    results = []
    for i, s in enumerate(samples, 1):
        heard = rig.dictate(CORPUS / s["wav"], idx)
        got = heard.asr if heard else ""
        score = wer(s["asr"], got)
        results.append({**s, "loopback": got, "wer": score})
        mark = "·" if score <= 0.1 else ("~" if score <= 0.3 else "!")
        print(f"  {mark} {i:2d}/{n}  WER {score:.3f}  {s['wav']}")
        if score > 0.3:
            print(f"        was: {s['asr'][:90]}")
            print(f"        now: {got[:90]}")
    scores = sorted(r["wer"] for r in results)
    median = scores[len(scores) // 2]
    lost = sum(1 for r in results if not r["loopback"])
    ok = say(median <= 0.15 and lost == 0,
             f"median WER against Wispr's own earlier reading: {median:.3f}"
             f" ({lost} clip(s) came back empty)")
    if not ok:
        print("     A clean channel should be near zero: it is the same audio,")
        print("     the same recogniser. Anything above ~0.15 is the loopback")
        print("     losing something — check the device's sample rate and that")
        print("     the WAV is not being clipped or resampled on the way in.")
    return ok, results


# ── 4 · is it worth it ───────────────────────────────────────────────────────
def stage_worth(results, db):
    print("\n4 · is the teacher better than the student on these clips")
    # The local model's reading is already in the corpus for `whisper-local`
    # rows, but not for Wispr's own. Rather than run a model here — this probe
    # deliberately loads none — report the measured gap and say where the real
    # comparison lives.
    print("     Measured 2026-09-01 over 60 clips (`corpus_baseline.py`):")
    print("       local turbo   WER 19.7%   ro 22.7%   en 7.1%")
    print("     The teacher is worth having exactly as far as that gap is real.")
    print("     Re-run `python3 helpers/corpus_baseline.py` for today's number;")
    print("     this probe does not load a model, on purpose.")
    return True


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--device", help="virtual output device (substring)")
    ap.add_argument("--n", type=int, default=5, help="clips for stage 3")
    ap.add_argument("--stage", type=int, help="run one stage only")
    args = ap.parse_args(argv)

    if not CORPUS_DB.exists():
        raise SystemExit(f"no corpus at {CORPUS_DB}")
    db = sqlite3.connect(f"file:{CORPUS_DB}?mode=ro", uri=True)
    db.row_factory = sqlite3.Row

    ok, idx = stage_setup(args.device)
    if args.stage == 1:
        return 0 if ok else 1
    if not ok:
        print("\nNO-GO at stage 1 — the channel is not set up.")
        return 1

    if not stage_hears(idx, db):
        print("\nNO-GO at stage 2 — Wispr will not take played-back audio.")
        return 1
    if args.stage == 2:
        return 0

    clean, results = stage_clean(idx, db, args.n)
    if args.stage == 3:
        return 0 if clean else 1
    stage_worth(results, db)

    print("\nGO" if clean else "\nNO-GO at stage 3 — the channel degrades the audio.")
    return 0 if clean else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
