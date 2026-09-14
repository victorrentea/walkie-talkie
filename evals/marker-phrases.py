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

# Where in the base clip the marker goes, as a fraction. Three, because a marker
# landing in the middle of a word and one landing in a pause are different
# questions and the relay does not fully control which it gets.
POSITIONS = (0.25, 0.5, 0.75)

NUMBER_WORDS = {"one": "1", "two": "2", "three": "3"}


def say(phrase, path):
    """The same voice and rate `ShotMarker.synthesise` uses."""
    subprocess.run(["/usr/bin/say", "-v", "Samantha", "-r", "190", "-o", path, phrase],
                   check=True, capture_output=True)


def to_pcm(src, dst):
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", src,
                    "-ar", str(RATE), "-ac", "1", "-c:a", "pcm_s16le", dst],
                   check=True, capture_output=True)


def frames(path):
    with wave.open(path) as w:
        return w.readframes(w.getnframes()), w.getframerate()


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


def transcribe(path, model):
    import mlx_whisper
    out = mlx_whisper.transcribe(path, path_or_hf_repo=model, verbose=False)
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
    """Real dictations, longest first — a marker needs speech around it."""
    rows = []
    with open(os.path.join(CORPUS, "corpus.jsonl")) as f:
        for line in f:
            try:
                d = json.loads(line)
            except Exception:
                continue
            p = os.path.join(CORPUS, d.get("wav", ""))
            # Clips that already carry a marker would score themselves.
            if not os.path.exists(p) or "screenshot" in (d.get("text") or "").lower():
                continue
            if 12 <= d.get("duration", 0) <= 60:
                rows.append((d["duration"], p))
    rows.sort(reverse=True)
    return [p for _, p in rows[:limit]]


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--quick", action="store_true")
    ap.add_argument("--model", default=os.environ.get(
        "RELAY_WHISPER_MODEL", "mlx-community/whisper-large-v3-turbo"))
    args = ap.parse_args(argv[1:])

    candidates = CANDIDATES[:6] if args.quick else CANDIDATES
    positions = POSITIONS[:1] if args.quick else POSITIONS
    bases = base_clips(1 if args.quick else 2)
    if not bases:
        print("no usable base clips in the corpus", file=sys.stderr)
        return 2

    print("base clips:")
    for b in bases:
        print("  ", os.path.basename(b))
    runs = len(candidates) * len(bases) * len(positions)
    print(f"{len(candidates)} candidates × {len(bases)} clips × {len(positions)} positions"
          f" = {runs} transcriptions\n")

    work = tempfile.mkdtemp(prefix="marker-phrases-")
    results = []
    for phrase in candidates:
        aiff = os.path.join(work, "m.aiff")
        clip = os.path.join(work, "m.wav")
        say(phrase, aiff)
        to_pcm(aiff, clip)
        hits, misses = 0, []
        for base in bases:
            for frac in positions:
                mixed = os.path.join(work, "mixed.wav")
                splice(base, clip, frac, mixed)
                text = transcribe(mixed, args.model)
                if hit(phrase, text):
                    hits += 1
                else:
                    misses.append((os.path.basename(base), frac))
        results.append((hits, runs // len(candidates), phrase, misses))
        print(f"  {hits}/{runs // len(candidates)}  {phrase}")

    print("\n── ranked ─────────────────────────────────────────")
    for hits, total, phrase, _ in sorted(results, reverse=True):
        bar = "█" * hits + "·" * (total - hits)
        print(f"  {bar}  {hits}/{total}  {phrase}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
