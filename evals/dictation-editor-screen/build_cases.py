"""Cases for the screenshot eval: prompts from the outbox (raw recognition, never edited)
whose context frame 📸0 is still in the shots cache.
usage: build_cases.py out/cases.jsonl [n_general]"""
import json, os, re, sys, random
HOME = os.path.expanduser("~/.walkie-talkie")
rows = [json.loads(l) for l in open(f"{HOME}/outbox.jsonl") if l.strip()]
vocab_lines = [l.strip() for l in open(f"{HOME}/vocabulary.txt") if l.strip() and not l.startswith("#")]
pairs = [tuple(x.strip() for x in l.split("→")) for l in vocab_lines if "→" in l]
pairs = [(h, w) for h, w in pairs if not re.fullmatch(r"[a-z]+", h) or not w.isdigit()]  # not "two → 2"

def words(t):
    t = re.sub(r"\[[^\]]*\]", " ", t)
    return re.sub(r"\s+", " ", t).strip()

def shot(r):
    s = r.get("screen") or ""
    p = s.replace("-original.jpg", "-800px.jpg")
    return p if p and os.path.exists(p) else None

cands = []
for r in rows:
    via = (r.get("delivery") or {}).get("via", "")
    if via not in ("elevenlabs-scribe", "local-whisper", "local-fallback", "local-forced", "local-auto"):
        continue
    w, p = words(r.get("text") or ""), shot(r)
    if not p or len(w.split()) < 5 or len(w) > 1500:
        continue
    cands.append({"id": r["ts"], "words": w, "shot": p, "via": via,
                  "app": ((r.get("sources") or {}).get(os.path.basename(r["screen"])) or "")[:120]})

targeted, used = [], set()
for heard, written in pairs:
    hit = [c for c in cands if re.search(r"\b" + re.escape(heard) + r"\b", c["words"], re.I)]
    if hit:
        c = dict(hit[-1]); c["heard"], c["written"] = heard, written
        targeted.append(c); used.add(c["id"])
random.seed(7)
rest = [c for c in cands if c["id"] not in used]
general = random.sample(rest, min(int(sys.argv[2]) if len(sys.argv) > 2 else 40, len(rest)))
os.makedirs(os.path.dirname(sys.argv[1]) or ".", exist_ok=True)
with open(sys.argv[1], "w") as f:
    for c in targeted: f.write(json.dumps({**c, "kind": "targeted"}, ensure_ascii=False) + "\n")
    for c in general: f.write(json.dumps({**c, "kind": "general"}, ensure_ascii=False) + "\n")
print(f"{len(cands)} candidates with a frame; {len(targeted)} targeted ({', '.join(t['heard']+'→'+t['written'] for t in targeted)}), {len(general)} general")
