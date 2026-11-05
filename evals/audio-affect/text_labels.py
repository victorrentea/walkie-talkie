"""A weak, independent witness for *tense*: does the speaker's TEXT read annoyed? Haiku over the transcripts,
in batches. It is never a feature — Victor's rule stands, no tag from the words — only a way to ask whether
the audio rises on clips that are annoyed for reasons the audio did not see."""
import json, os, re, subprocess, sys
from concurrent.futures import ThreadPoolExecutor
from common import *
P = """Below are numbered voice dictations by one person (a developer) to a coding agent, Romanian or English.
Score each for how annoyed, frustrated or angry the WRITER sounds at the agent or the situation, from the words only:
0 = neutral or friendly, 1 = mildly impatient, 2 = clearly frustrated, 3 = angry.
Plain technical problem reports ("this fails", "nu merge") are 0 unless the wording itself is irritated.
Answer with one JSON object mapping number to score, nothing else.

"""
rows = list(clips())
path = OUT + '/text_labels.jsonl'
done = {json.loads(l)['id'] for l in open(path)} if os.path.exists(path) else set()
rows = [r for r in rows if r['id'] not in done and r.get('text')]
if len(sys.argv) > 1: rows = rows[:int(sys.argv[1])]
B = [rows[i:i + 50] for i in range(0, len(rows), 50)]

def go(b):
    body = P + '\n'.join(f"{i}: {r['text'][:600]}" for i, r in enumerate(b))
    for _ in range(3):
        o = subprocess.run(['claude', '-p', '--model', 'claude-haiku-5-5', '--no-session-persistence', '--tools', ''],
                           input=body, capture_output=True, text=True, cwd=sys.argv[2] if len(sys.argv) > 2 else None, timeout=240)
        m = re.search(r'\{.*\}', o.stdout, re.S)
        if m:
            try:
                j = json.loads(m.group(0))
                return [{'id': r['id'], 'annoyed': int(j[str(i)])} for i, r in enumerate(b) if str(i) in j]
            except Exception: pass
    print('batch failed', o.stderr[:200], o.stdout[:200], flush=True); return []

with ThreadPoolExecutor(5) as ex, open(path, 'a') as f:
    for k, res in enumerate(ex.map(go, B), 1):
        for x in res: f.write(json.dumps(x) + '\n')
        f.flush()
        if k % 5 == 0: print(k, '/', len(B), flush=True)
