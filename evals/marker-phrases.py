#!/usr/bin/env python3
"""Which spoken marker does the local model actually write down?

    python3 evals/marker-phrases.py            # the standard sweep
    python3 evals/marker-phrases.py --quick    # one base clip, fewer candidates

**The question, and why it needs an eval rather than an argument.** A shot
marker comes back from `whisper-large-v3-turbo` almost every time; `selected
text one` and `picked element one` mostly do not. Measured on Victor's dictation
of 23:06 — five markers spliced into the recording, and the raw transcript in
`corpus.jsonl` contains `Screenshot 1 Screenshot 2` and nothing else. Not
mis-heard: **absent**. Whichever property makes `screenshot` survive is not one
anybody here can reason their way to, so this measures it.

Victor: *"De ce nu poți să iterezi tu pe diverse combinații de sunete pe care
[modelul] să le recunoască? Nu îmi pasă să fie exact un anumit text, să fie ceva
recognoscibil. Iterează tu până găsești."*

**It runs on his own voice, off his microphone.** The base clips are real
dictations out of `voice-corpus/` — Romanian, his room, his gain — and the
candidate is spliced into them exactly as `MicRecorder.insert` splices it: 16 kHz
mono int16, butted against the speech with no padding (padding was measured worse
on 2026-09-14, see `ShotMarker.padSeconds`). So a candidate that scores here is a
candidate under the conditions that matter.

**A hit is the phrase appearing in the transcript**, normalised for case and for
the digit/word spelling of the number — which is what `ShotMarker.resolve` has to
cope with anyway (`Screenshot 1` and `Screenshot one` are the same marker).
"""

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import wave

HOME = os.path.expanduser("~")
CORPUS = os.path.join(HOME, ".walkie-talkie/voice-corpus")
RATE = 16000

# The number is always `one`: this measures the **prefix**, which is the part
# that differs between the three kinds and the part that is failing.
CANDIDATES = [
    "screenshot one",       # the control — the one that works
    "selected text one",    # shipping, failing
    "picked element one",   # shipping, failing
    "marker one",
    "bookmark one",
    "snapshot one",
    "capture one",
    "highlight one",
    "clip one",
    "tag one",
    "anchor one",
    "checkpoint one",
    "insert one",
    "quote one",
    "item one",
    "flag one",
]

# Where in the base clip the marker goes when splicing blind, as a fraction.
# Kept as the **control**: it is what the app did before the gap gate, and the
# difference between the two columns is the whole question.
POSITIONS = (0.25, 0.5, 0.75)

# What counts as a gap, in the recorder's own terms — `ShotMarker.gapNeeded` is
# 0.12 s of `MicRecorder.quietSeconds`, so the same number here.
GAP_SECONDS = 0.12
# The meter's shape, roughly: RMS per hop against a floor taken from the clip's
# own quietest tenth. `MicRecorder` tracks an adaptive floor per recording; this
# is that idea without the state, which is enough to find pauses.
HOP = 0.02

NUMBER_WORDS = {"one": "1", "two": "2", "three": "3"}


def say(phrase, path, rate=190):
    """`ShotMarker.synthesise`'s voice; its rate unless `--rate` says otherwise."""
    subprocess.run(["/usr/bin/say", "-v", "Samantha", "-r", str(rate), "-o", path, phrase],
                   check=True, capture_output=True)


def to_pcm(src, dst):
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", src,
                    "-ar", str(RATE), "-ac", "1", "-c:a", "pcm_s16le", dst],
                   check=True, capture_output=True)


def frames(path):
    with wave.open(path) as w:
        return w.readframes(w.getnframes()), w.getframerate()


def gaps(path, want):
    """Byte offsets at the middle of `want` pauses, spread through the clip.

    This is what the app does since the gap gate — `ShotMarker.afterGap` holds
    the clip back until `quietSeconds` says he has stopped — so a sweep that
    splices blind is measuring a case that no longer happens.
    """
    import array
    data, rate = frames(path)
    pcm = array.array("h")
    pcm.frombytes(data)
    hop = int(rate * HOP)
    energies = []
    for i in range(0, len(pcm) - hop, hop):
        window = pcm[i:i + hop]
        energies.append(sum(abs(v) for v in window) / hop)
    if not energies:
        return []
    floor = sorted(energies)[max(0, len(energies) // 10)]
    quiet = [e <= max(floor * 2.5, 40) for e in energies]

    need = max(1, int(GAP_SECONDS / HOP))
    runs, start = [], None
    for i, q in enumerate(quiet + [False]):
        if q and start is None:
            start = i
        elif not q and start is not None:
            if i - start >= need:
                runs.append((start, i))
            start = None
    if not runs:
        return []
    # Spread: the longest pause in each third of the clip, so three markers do
    # not all land in the same breath.
    picked, thirds = [], len(energies) / 3
    for t in range(3):
        here = [r for r in runs if thirds * t <= r[0] < thirds * (t + 1)]
        if here:
            picked.append(max(here, key=lambda r: r[1] - r[0]))
    picked = (picked or runs)[:want]
    return [(((a + b) // 2) * hop * 2) & ~1 for a, b in picked]


def splice_at(base_pcm, marker_pcm, byte_offset, dst):
    data, rate = frames(base_pcm)
    clip, _ = frames(marker_pcm)
    cut = min(max(0, byte_offset), len(data)) & ~1
    with wave.open(dst, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(data[:cut] + clip + data[cut:])


def splice(base_pcm, marker_pcm, fraction, dst):
    """Butted in, exactly as `MicRecorder.insert` writes it — no padding."""
    data, rate = frames(base_pcm)
    clip, _ = frames(marker_pcm)
    cut = int(len(data) * fraction) & ~1          # even, so never mid-sample
    with wave.open(dst, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(data[:cut] + clip + data[cut:])


_HELPER = None


def transcribe(path, model):
    """**Through the app's own helper, settings and all** (2026-09-14).

    The first version of this file called `mlx_whisper.transcribe` bare, and
    every number it produced was about a different decoder: `whisper_helper.py`
    pins the language to `{ro, en}` and passes `VOCABULARY` as `initial_prompt`,
    both measured (`evals/short-clip-lid.md`). It showed as a rate that would not
    reconcile — `screenshot` hits 75% in his real dictations and 33% here — and
    a sweep whose decoder is not the shipped one ranks candidates for a model
    nobody runs.

    `RELAY_WHISPER_VOCABULARY` is the knob this makes reachable: the prompt is
    decoder *context*, not a filter, so putting the marker's own words in it is
    the one lever aimed directly at the thing being measured.
    """
    global _HELPER
    if _HELPER is None:
        sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(
            os.path.abspath(__file__))), "helpers"))
        import whisper_helper
        _HELPER = whisper_helper
    out = _HELPER.transcribe(path)
    return (out.get("text") or "").strip()


def hit(phrase, text):
    """Case-insensitive, and `one` counts as `1` — `ShotMarker.resolve`'s rule."""
    low = " ".join(text.lower().split())
    words = phrase.lower().split()
    tail = words[-1]
    for spelling in (tail, NUMBER_WORDS.get(tail, tail)):
        needle = " ".join(words[:-1] + [spelling])
        # Punctuation between the words is the recogniser's, not a miss.
        pattern = r"\W+".join(re.escape(w) for w in needle.split())
        if re.search(pattern, low):
            return True
    return False


def base_clips(limit):
    """**Recent recordings this app made itself**, newest first.

    Not merely "a real dictation": the first version took the longest clips in
    the corpus and got one harvested from Wispr Flow (`engine: None`) at
    **-34.8 dB** and another at **-41.6 dB**, against his current recordings at
    -26 to -30. The marker clip is -15.7 dB, so the sweep was measuring a marker
    20-26 dB above the speech around it where production is about 10 — a
    different signal, and a plausible part of why `screenshot` scored 33% here
    and 75% in his real dictations.

    So: `whisper-local` only (the app's own microphone path, the one the marker
    is spliced into), newest first, long enough to have speech either side of
    the insertion and short enough to decode quickly.
    """
    rows = []
    with open(os.path.join(CORPUS, "corpus.jsonl")) as f:
        for line in f:
            try:
                d = json.loads(line)
            except Exception:
                continue
            p = os.path.join(CORPUS, d.get("wav", ""))
            if d.get("engine") != "whisper-local" or not os.path.exists(p):
                continue
            # Clips that already carry a marker would score themselves.
            if any(k in (d.get("text") or "").lower()
                   for k in ("screenshot", "selected text", "picked element")):
                continue
            if 15 <= d.get("duration", 0) <= 45:
                rows.append(p)
    return rows[-limit:]


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--quick", action="store_true")
    ap.add_argument("--bases", type=int, default=2,
                    help="how many recent recordings to splice into. Six trials "
                         "is not enough to tell 4/6 from 6/6; widen before "
                         "optimising against a difference that may be noise.")
    ap.add_argument("--rate", type=int, default=190,
                    help="`say -r`. A slower clip is longer and gives the decoder "
                         "more to hold on to; 190 is what ShotMarker uses.")
    ap.add_argument("--candidates",
                    help="comma-separated, instead of the built-in list")
    ap.add_argument("--clip",
                    help="a ready-made 16 kHz mono WAV to splice instead of "
                         "synthesising the candidate — how a marker recorded in "
                         "**his own voice** is measured against the TTS one. The "
                         "candidate string is then only what the hit is scored "
                         "against.")
    ap.add_argument("--where", choices=("gap", "blind", "both"), default="both",
                    help="gap: into a pause, as the app does since the gap gate. "
                         "blind: at a fixed fraction, which is what it did before.")
    ap.add_argument("--model", default=os.environ.get(
        "RELAY_WHISPER_MODEL", "mlx-community/whisper-large-v3-turbo"))
    args = ap.parse_args(argv[1:])

    if args.candidates:
        candidates = [c.strip() for c in args.candidates.split(",") if c.strip()]
    else:
        candidates = CANDIDATES[:6] if args.quick else CANDIDATES
    positions = POSITIONS[:1] if args.quick else POSITIONS
    bases = base_clips(1 if args.quick else args.bases)
    if not bases:
        print("no usable base clips in the corpus", file=sys.stderr)
        return 2

    print("base clips:")
    for b in bases:
        print("  ", os.path.basename(b))
    runs = len(candidates) * len(bases) * len(positions)
    print(f"{len(candidates)} candidates × {len(bases)} clips × {len(positions)} positions"
          f" = {runs} transcriptions\n")

    modes = ("gap", "blind") if args.where == "both" else (args.where,)
    # Worked out once per clip: finding pauses is cheap but not free, and every
    # candidate is spliced into the same ones, which is what makes the columns
    # comparable.
    cuts = {b: gaps(b, len(positions)) for b in bases} if "gap" in modes else {}
    for b, c in cuts.items():
        if not c:
            print(f"  (no pause of {GAP_SECONDS}s found in {os.path.basename(b)})")

    work = tempfile.mkdtemp(prefix="marker-phrases-")
    results = []
    for phrase in candidates:
        aiff = os.path.join(work, "m.aiff")
        clip = os.path.join(work, "m.wav")
        if args.clip:
            to_pcm(args.clip, clip)
        else:
            say(phrase, aiff, args.rate)
            to_pcm(aiff, clip)
        score = {}
        for mode in modes:
            hits = total = 0
            for base in bases:
                places = cuts.get(base, []) if mode == "gap" else positions
                for place in places:
                    mixed = os.path.join(work, "mixed.wav")
                    if mode == "gap":
                        splice_at(base, clip, place, mixed)
                    else:
                        splice(base, clip, place, mixed)
                    total += 1
                    if hit(phrase, transcribe(mixed, args.model)):
                        hits += 1
            score[mode] = (hits, total)
        results.append((score, phrase))
        print("  " + "  ".join(f"{m}: {score[m][0]}/{score[m][1]}" for m in modes)
              + f"   {phrase}")

    key = "gap" if "gap" in modes else modes[0]
    print("\n── ranked by where the app actually puts it ───────────")
    for score, phrase in sorted(results, key=lambda r: -r[0][key][0]):
        hits, total = score[key]
        bar = "█" * hits + "·" * (total - hits)
        other = ""
        if len(modes) > 1:
            b, bt = score["blind"]
            other = f"   (blind {b}/{bt})"
        print(f"  {bar}  {hits}/{total}  {phrase}{other}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
