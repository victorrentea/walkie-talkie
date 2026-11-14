#!/usr/bin/env python3
"""Synthetic clips for a wake phrase (2026-11-14, "hey gepetto"): the positives and the
confusables `train_whisper_wake.py --data <name>` trains on, said by macOS `say`.

    python3 evals/wake-word/make_phrase_clips.py gepetto

pos/<Voice>-<rate>-<variant>-<pitch>.wav and adv/<Voice>-<words>.wav under
~/.walkie-talkie/wake/<name>/, 16 kHz mono. The phrase is spelled per language so each
voice says it the way a person of that language would (Ioana: "Hei Gepeto").
"""
import subprocess, sys, tempfile
from pathlib import Path

PHRASES = {
    "gepetto": {
        "pos": {"en": ["Hey Geppetto", "Hey, Geppetto!", "Hey Jepetto"],
                "ro": ["Hei Gepeto", "Hei, Gepeto!", "Hei Gepetto"],
                "it": ["Ehi Geppetto", "Hey Geppetto!", "Hei Geppetto"],
                "es": ["Jei Yepeto", "Jei, Yepeto!", "Jei Yepetto"]},
        "adv": ["Geppetto", "hey spaghetti", "hey ghetto", "get to", "hey Pedro", "hey petal", "hey Jeff",
                "the depot", "hey Claude", "hey Santa", "hey there", "hey, can you", "hey Siri", "hey Jupiter",
                "hey Greta", "Pinocchio", "hey Gemini", "hey GPT", "hey chat GPT", "Jeopardy", "libretto",
                "stiletto", "falsetto", "hey Loretta", "hey Beppe", "repeat that", "je peux", "hai pe to",
                "repetă", "hey Jennifer", "a pet too", "hey Jessica"],
    },
}
VOICES = {"Albert": "en", "Aman": "en", "Daniel": "en", "Fred": "en", "Junior": "en", "Karen": "en", "Kathy": "en",
          "Moira": "en", "Ralph": "en", "Rishi": "en", "Samantha": "en", "Tara": "en", "Tessa": "en",
          "Ioana": "ro", "Alice": "it", "Mónica": "es", "Paulina": "es"}
RATES, PITCHES = (150, 185, 220), (0.94, 1.0, 1.07)


def clip(voice, rate, text, pitch, out):
    with tempfile.NamedTemporaryFile(suffix=".aiff") as t:
        if subprocess.run(["say", "-v", voice, "-r", str(rate), "-o", t.name, text]).returncode:
            return False
        # Pitch by resampling (a different speaker, not the same one sped up: tempo put back).
        return subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", t.name, "-af",
                               f"aresample=16000,asetrate={int(16000 * pitch)},aresample=16000,atempo={1 / pitch:.4f}",
                               "-ac", "1", "-ar", "16000", "-c:a", "pcm_s16le", str(out)]).returncode == 0


def main():
    name = sys.argv[1]
    spec = PHRASES[name]
    root = Path.home() / ".walkie-talkie" / "wake" / name
    (root / "pos").mkdir(parents=True, exist_ok=True)
    (root / "adv").mkdir(parents=True, exist_ok=True)
    have = set(subprocess.run(["say", "-v", "?"], capture_output=True, text=True).stdout.split())
    made = 0
    for voice, lang in VOICES.items():
        if voice not in have:
            print(f"no voice {voice} on this Mac — skipped")
            continue
        for rate in RATES:
            for n, text in enumerate(spec["pos"][lang], 1):
                for pitch in PITCHES:
                    out = root / "pos" / f"{voice}-{rate}-{n}-{pitch}.wav"
                    made += out.exists() or clip(voice, rate, text, pitch, out)
        if lang == "en":
            for text in spec["adv"]:
                out = root / "adv" / f"{voice}-{text.replace(' ', '_').replace(',', '')}.wav"
                made += out.exists() or clip(voice, 175, text, 1.0, out)
    print(f"{made} clips under {root}: {len(list((root / 'pos').glob('*.wav')))} pos, {len(list((root / 'adv').glob('*.wav')))} adv")


if __name__ == "__main__":
    main()
