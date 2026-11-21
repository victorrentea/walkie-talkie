"""Cases for the "talk before the dictation" arm: raw dictated prompts whose minutes before hold
transcribed speech in victor-mac's continuous transcript (addons-output/<day>-transcription.txt,
[HH:MM] lines, local time). The dictation's own minute is left out — the room transcript hears the
dictation too, and it must not leak in.
usage: build_pre.py out/cases-pre.jsonl [n] [minutes]"""
import datetime as dt, json, os, random, re, sys
HOME = os.path.expanduser("~/.walkie-talkie")
TR = os.path.expanduser("~/workspace/victor-mac/addons-output")
N = int(sys.argv[2]) if len(sys.argv) > 2 else 40
MIN = int(sys.argv[3]) if len(sys.argv) > 3 else 5
RAW = ("elevenlabs-scribe", "local-whisper", "local-fallback", "local-forced", "local-auto")
days = {}
def lines(day):
    if day not in days:
        p = f"{TR}/{day}-transcription.txt"
        out = []
        if os.path.exists(p):
            for l in open(p, errors="replace"):
                m = re.match(r"\[(\d\d):(\d\d)\]\s*(.*)", l.strip())
                if m and len(m.group(3)) > 1: out.append((int(m.group(1)) * 60 + int(m.group(2)), m.group(3)))
        days[day] = out
    return days[day]
def words(t): return re.sub(r"\s+", " ", re.sub(r"\[[^\]]*\]", " ", t)).strip()
cands = []
for l in open(f"{HOME}/outbox.jsonl"):
    if not l.strip(): continue
    r = json.loads(l)
    if (r.get("delivery") or {}).get("via") not in RAW: continue
    w = words(r.get("text") or "")
    if len(w.split()) < 5 or len(w) > 1500: continue
    end = dt.datetime.fromisoformat(r["ts"].replace("Z", "+00:00")).astimezone()
    start = end - dt.timedelta(seconds=len(w.split()) / 2.3 + 3)   # ~2.3 words/s spoken
    m0 = start.hour * 60 + start.minute
    pre = [t for m, t in lines(start.strftime("%Y-%m-%d")) if m0 - MIN <= m < m0]
    text = " ".join(pre)[-1500:]
    if len(text) >= 300:
        cands.append({"id": r["ts"], "words": w, "pre": text, "kind": "pre"})
random.seed(7)
pick = random.sample(cands, min(N, len(cands)))
with open(sys.argv[1], "w") as f:
    for c in pick: f.write(json.dumps(c, ensure_ascii=False) + "\n")
print(f"{len(cands)} prompts with ≥300 chars of talk in the {MIN} min before; {len(pick)} taken")
