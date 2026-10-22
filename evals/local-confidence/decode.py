#!/usr/bin/env python3
"""Decode recent cloud-labelled takes with the local model, for the 🎤 threshold.

    python3 evals/local-confidence/decode.py <python-with-mlx_whisper> 400 out/turbo-lora-400.jsonl [model-dir]

Takes from `~/.walkie-talkie/voice-corpus/corpus.jsonl` since 2026-10-04 (after the
Turbo LoRA was trained, so none of them taught it) whose engine was Wispr Flow or
ElevenLabs, 2–60 s, shuffled with seed 7. Each is decoded by this repo's
`helpers/whisper_helper.py`; the line keeps the helper's answer and the cloud text
as `ref`. The output holds Victor's words: it stays in `out/` (ignored, public repo).
"""
import json, os, random, subprocess, sys

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.expanduser("~/.walkie-talkie/voice-corpus")
python, limit, out_path = sys.argv[1], int(sys.argv[2]), sys.argv[3]
model = sys.argv[4] if len(sys.argv) > 4 else os.path.expanduser("~/.walkie-talkie/models/whisper-turbo-victor")
rows = []
for line in open(f"{root}/corpus.jsonl"):
    try:
        d = json.loads(line)
    except ValueError:
        continue
    if d.get("ts", "") < "2026-10-04" or d.get("engine") not in ("wispr-flow", "elevenlabs"):
        continue
    if not 2 <= d.get("duration", 0) <= 60:
        continue
    wav = f"{root}/{d['wav']}"
    if os.path.exists(wav) and d.get("text"):
        rows.append((wav, d["text"], d["duration"], d["id"]))
random.seed(7)
random.shuffle(rows)
helper = os.path.join(here, "..", "..", "helpers", "whisper_helper.py")
p = subprocess.Popen([python, helper], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True,
                     env=dict(os.environ, RELAY_WHISPER_MODEL=model))
print(p.stdout.readline().strip()[:200], flush=True)
with open(out_path, "w") as out:
    for i, (wav, ref, dur, id_) in enumerate(rows[:limit]):
        p.stdin.write(json.dumps({"wav": wav}) + "\n")
        p.stdin.flush()
        r = json.loads(p.stdout.readline())
        r.pop("memory", None)
        out.write(json.dumps({"id": id_, "duration": dur, "ref": ref, **r}, ensure_ascii=False) + "\n")
        out.flush()
        if i % 25 == 0:
            print(i, flush=True)
p.stdin.close()
p.wait()
