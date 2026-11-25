#!/usr/bin/env python3
"""Which spoken marker does Wispr Flow reliably write down? — build, drive, score.

    /usr/local/bin/python3 evals/wispr-markers/run.py build              # clips/ + clips/manifest.json
    TART_HOME=~/tart /usr/local/bin/python3 evals/wispr-markers/run.py drive [--only a,b] [--limit N]
    /usr/local/bin/python3 evals/wispr-markers/run.py score              # the table, from results.jsonl
    /usr/local/bin/python3 evals/wispr-markers/run.py fp <flow.sqlite copy>   # false positives on real rows

`build` runs on the host (needs `mlx_whisper` for word timings — `/usr/local/bin/python3` has it, the
system one does not): it splices candidate markers into ~10 of Victor's own dictations, the way
`MicRecorder.insert` does (16 kHz mono int16, butted in, no pad), one marker into a **pause** and one
**mid-phrase** (a word boundary with no pause) per clip, level-matched to his voice. `drive` plays
each clip into the guest's Wispr through `guest.py` (one `tart exec` per clip — the only chain in
the guest with a microphone grant) and appends one row per clip to `results.jsonl`. `score` reads
them back with the regexes a relay would ship (`PATTERNS`).

Reuses `evals/marker-phrases.py`'s `say` → 16 kHz PCM → splice path and `helpers/wispr_loopback.py`
(in the guest) for the push-to-talk + `History` row.
"""
from __future__ import annotations

import difflib
import json
import os
import random
import re
import subprocess
import sys
import time
import unicodedata
import wave

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "helpers"))
import walkie_token  # noqa: E402 — X-Walkie-Token on every call to the relay (2026-11-25)
walkie_token.install()
CLIPS = os.path.join(HERE, "clips")
WORK = os.path.join(HERE, "work")
RESULTS = os.path.join(HERE, "results.jsonl")
MANIFEST = os.path.join(CLIPS, "manifest.json")
CORPUS = os.path.expanduser("~/.walkie-talkie/voice-corpus")
RECORDED = os.path.expanduser("~/.walkie-talkie/markers")   # his own voice, `ShotMarker.recordedDir`
GUEST = "/Users/admin/wt-lab/evals/wispr-markers"
RATE = 16000

# ~10 real dictations, 15–25 s, five per language; none says a candidate word on its own.
BASES = [
    ("2026-09-30/10-42-10-wispr642.wav", "ro"),
    ("2026-09-30/11-54-06-wispr168.wav", "ro"),
    ("2026-09-30/15-09-44-wispr848.wav", "ro"),
    ("2026-09-30/17-21-02-local428.wav", "ro"),
    ("2026-09-30/17-36-59-local903.wav", "ro"),
    ("2026-09-30/10-38-46-wispr707.wav", "en"),
    ("2026-09-29/19-49-03-local55.wav", "en"),
    ("2026-09-30/19-21-48-local577.wav", "en"),
    ("2026-09-30/09-12-47-wispr582.wav", "en"),
    ("2026-09-29/21-22-22-local465.wav", "en"),
]

NUM_WORDS = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
NATO = ["alpha", "bravo", "charlie", "delta", "echo", "foxtrot", "golf", "hotel", "india", "juliet"]

# What is said, per candidate: a function of the index (None = no index spoken).
CANDIDATES = {
    "screenshot": lambda i: "screenshot %s" % NUM_WORDS[i - 1],
    "image": lambda i: "image %s" % NUM_WORDS[i - 1],
    "picture": lambda i: "picture %s" % NUM_WORDS[i - 1],
    "snapshot": lambda i: "snapshot %s" % NUM_WORDS[i - 1],
    "bang": lambda i: "Screenshot!",
    "marker": lambda i: "marker %s" % NUM_WORDS[i - 1],
    "photo-nato": lambda i: "photo %s" % NATO[i - 1],
    "walkieshot": lambda i: "walkieshot %s" % NUM_WORDS[i - 1],
    "his-screenshot": None,          # his own recordings, ~/.walkie-talkie/markers/screenshot-N.wav
    "tone-screenshot": lambda i: "screenshot %s" % NUM_WORDS[i - 1],   # a 1 kHz blip in front
    "his-selected": None,            # his own `selected text N` (~/.walkie-talkie/markers/selected-text-N.wav)
    "his-picked": None,              # his own `picked element N`
    "tone-his-screenshot": None,     # the blip, then his own `screenshot N`
}

# ── what a relay would ship to find them ─────────────────────────────────────
_NUM = (r"(\d{1,2}|one|two|three|four|five|six|seven|eight|nine|ten|"
        r"unu|doi|trei|patru|cinci|șase|sase|șapte|sapte|opt|nouă|noua|zece)")
_SEP = r"[\s,.:;#\-–—]*(?:number\s*|nr\.?\s*|no\.?\s*)?"
PATTERNS = {
    "screenshot": r"\bscreen[\s-]?shots?" + _SEP + _NUM + r"\b",
    "image": r"\bimages?" + _SEP + _NUM + r"\b",
    "picture": r"\bpictures?" + _SEP + _NUM + r"\b",
    "snapshot": r"\bsnap[\s-]?shots?" + _SEP + _NUM + r"\b",
    # a sentence of its own that says only `Screenshot` — index from order
    "bang": r"(?:^|[.!?…]\s+|\n\s*)(screen[\s-]?shot)\s*[.!:]",
    "marker": r"\bmarkers?" + _SEP + _NUM + r"\b",
    "photo-nato": r"\bphotos?" + _SEP + r"(alpha|alfa|bravo|charlie|delta|echo|foxtrot|golf|hotel|india|juliett?)\b",
    "walkieshot": r"\bwalk(?:ie|y|i|e)?[\s-]?(?:talkie[\s-]?)?shots?" + _SEP + _NUM + r"\b",
}
PATTERNS["his-screenshot"] = PATTERNS["screenshot"]
PATTERNS["tone-his-screenshot"] = PATTERNS["screenshot"]
PATTERNS["his-selected"] = r"\bselect(?:ed)?[\s-]+texts?" + _SEP + _NUM + r"\b"
PATTERNS["his-picked"] = r"\bpick(?:ed)?[\s-]+elements?" + _SEP + _NUM + r"\b"
PATTERNS["tone-screenshot"] = PATTERNS["screenshot"]

_NUMVAL = {w: i + 1 for i, w in enumerate(NUM_WORDS)}
_NUMVAL.update({"unu": 1, "doi": 2, "trei": 3, "patru": 4, "cinci": 5, "șase": 6, "sase": 6,
                "șapte": 7, "sapte": 7, "opt": 8, "nouă": 9, "noua": 9, "zece": 10})
_NUMVAL.update({w: i + 1 for i, w in enumerate(NATO)})
_NUMVAL.update({"alfa": 1, "juliett": 10})


def pattern_of(cand):
    base = cand.split("+")[0].split("@")[0]
    return re.compile(PATTERNS[base], re.IGNORECASE)


def index_value(tok):
    tok = (tok or "").lower()
    return int(tok) if tok.isdigit() else _NUMVAL.get(tok)


# ── audio ────────────────────────────────────────────────────────────────────
def read16(path):
    with wave.open(path) as w:
        assert w.getsampwidth() == 2 and w.getnchannels() == 1 and w.getframerate() == RATE, path
        return np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32) / 32768


def write16(path, a):
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes((np.clip(a, -1, 1) * 32767).astype(np.int16).tobytes())


def to_pcm(src, dst):
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", src, "-ar", str(RATE), "-ac", "1",
                    "-c:a", "pcm_s16le", dst], check=True, capture_output=True)


def frame_rms(a, hop=0.02):
    n = int(RATE * hop)
    k = len(a) // n
    return np.sqrt(np.mean(a[:k * n].reshape(k, n) ** 2, axis=1) + 1e-12)


def active_rms(a):
    """RMS of the louder half of 20 ms frames — the voice, not the room."""
    r = frame_rms(a)
    return float(np.sqrt(np.mean(r[r >= np.median(r)] ** 2)))


def trim(a, rel=0.05):
    r = frame_rms(a, 0.01)
    on = np.where(r > r.max() * rel)[0]
    if not len(on):
        return a
    n = int(RATE * 0.01)
    return a[max(0, (on[0] - 1) * n):(on[-1] + 2) * n]


def tts(phrase, voice="Samantha", rate=190):
    os.makedirs(os.path.join(WORK, "tts"), exist_ok=True)
    key = re.sub(r"[^a-z0-9]+", "-", "%s-%s-%d" % (phrase.lower(), voice.lower(), rate)).strip("-")
    wav = os.path.join(WORK, "tts", key + ".wav")
    if not os.path.exists(wav):
        aiff = wav[:-4] + ".aiff"
        subprocess.run(["/usr/bin/say", "-v", voice, "-r", str(rate), "-o", aiff, phrase],
                       check=True, capture_output=True)
        to_pcm(aiff, wav)
        os.unlink(aiff)
    return trim(read16(wav))


def tone(sec=0.12, hz=1000.0):
    t = np.arange(int(RATE * sec)) / RATE
    env = np.minimum(1, np.minimum(t, sec - t) / 0.01)
    return (np.sin(2 * np.pi * hz * t) * env).astype(np.float32)


def marker_audio(cand, index, voice="Samantha", rate=190):
    base = cand.split("+")[0].split("@")[0]
    mine = {"his-screenshot": "screenshot", "tone-his-screenshot": "screenshot",
            "his-selected": "selected-text", "his-picked": "picked-element"}
    if base in mine:
        a = trim(read16(os.path.join(RECORDED, "%s-%d.wav" % (mine[base], index))))
        if base.startswith("tone-"):
            a = np.concatenate([tone() * active_rms(a) / active_rms(tone()), np.zeros(int(RATE * 0.08)), a])
        return a
    a = tts(CANDIDATES[base](index), voice, rate)
    if base == "tone-screenshot":
        a = np.concatenate([tone() * active_rms(a) / active_rms(tone()), np.zeros(int(RATE * 0.08)), a])
    return a


# ── where it goes ────────────────────────────────────────────────────────────
def word_timings(path, lang):
    """Local Whisper's word timings on the base clip — only to know which two words a splice point
    falls between, and to find the pauses and the unbroken boundaries."""
    cache = os.path.join(WORK, "words", os.path.basename(path) + ".json")
    if os.path.exists(cache):
        return json.load(open(cache))
    import mlx_whisper
    out = mlx_whisper.transcribe(path, path_or_hf_repo="mlx-community/whisper-large-v3-turbo",
                                 language=lang, word_timestamps=True)
    words = [{"w": w["word"].strip(), "s": w["start"], "e": w["end"]}
             for seg in out["segments"] for w in seg.get("words", [])]
    os.makedirs(os.path.dirname(cache), exist_ok=True)
    json.dump({"text": out["text"], "words": words}, open(cache, "w"), ensure_ascii=False, indent=1)
    return json.load(open(cache))


def splice_points(words, audio):
    """(gap, mid): the middle of the longest real pause near 40 % of the clip, and an unbroken word
    boundary ≥ 3 s away from it. Each as (seconds, words-before count)."""
    dur = len(audio) / RATE
    r = frame_rms(audio)
    floor = np.percentile(r, 10)
    quiet = r <= max(floor * 2.5, 1e-3)
    # pauses from the energy (Whisper stretches a word's end over the silence after it)
    gaps, s = [], None
    for i, q in enumerate(list(quiet) + [False]):
        if q and s is None:
            s = i
        elif not q and s is not None:
            a, b = s * 0.02, i * 0.02
            t = (a + b) / 2
            before = sum(1 for w in words if (w["s"] + w["e"]) / 2 < t)
            if b - a >= 0.24 and 2.0 <= t <= dur - 2.0 and 0 < before < len(words):
                gaps.append((t, before, b - a))
            s = None
    tight = []
    for i in range(len(words) - 1):
        a, b = words[i]["e"], words[i + 1]["s"]
        f = int((a + b) / 2 / 0.02)
        voiced = not quiet[max(0, f - 3):f + 4].any()
        if 2.0 <= a <= dur - 2.0 and b - a <= 0.04 and voiced:
            tight.append(((a + b) / 2, i + 1))
    gap = min(gaps, key=lambda g: abs(g[0] - 0.4 * dur)) if gaps else None
    far = [t for t in tight if not gap or abs(t[0] - gap[0]) >= 3.0]
    mid = min(far, key=lambda t: abs(t[0] - (0.7 if gap and gap[0] < dur / 2 else 0.3) * dur)) if far else None
    return (gap[:2] if gap else None), mid


def splice(audio, inserts):
    """`inserts`: [(seconds in the base, samples)], any order. Butted in, no pad
    (`ShotMarker.padSeconds` = 0). Returns the clip and each insert's start in the clip."""
    out, cursor, shift, at = [], 0, 0, {}
    for k, (t, clip) in sorted(enumerate(inserts), key=lambda kv: kv[1][0]):
        cut = int(t * RATE)
        out += [audio[cursor:cut], clip]
        at[k] = (cut + shift) / RATE
        shift += len(clip)
        cursor = cut
    out.append(audio[cursor:])
    return np.concatenate(out), [at[k] for k in range(len(inserts))]


# ── build ────────────────────────────────────────────────────────────────────
def variant_label(cand, voice, rate, level, pad=0.0):
    tags = []
    if pad:
        tags.append("pad%d" % int(pad * 1000))
    if voice != "Samantha":
        tags.append(voice.lower())
    if rate != 190:
        tags.append("r%d" % rate)
    if level:
        tags.append("%+ddB" % level)
    return cand + ("@" + ",".join(tags) if tags else "")


def build_one(base, lang, cand, idx_gap, idx_mid, voice="Samantha", rate=190, level=0,
              positions=("gap", "mid"), rep=0, back_to_back=False, pad=0.0):
    path = os.path.join(CORPUS, base)
    audio = read16(path)
    info = word_timings(path, lang)
    gap, mid = splice_points(info["words"], audio)
    spots = {"gap": gap, "mid": mid}
    target = active_rms(audio) * 10 ** (level / 20)
    inserts, markers = [], []
    for pos, idx in (("gap", idx_gap), ("mid", idx_mid)):
        if pos not in positions or spots[pos] is None:
            continue
        t, before = spots[pos]
        m = marker_audio(cand, idx, voice, rate)
        m = m * target / active_rms(m)
        if pad:
            m = np.concatenate([np.zeros(int(RATE * pad)), m, np.zeros(int(RATE * pad))])
        if back_to_back:     # two markers in one pause: idx, then idx+1, 0.25 s apart
            m2 = marker_audio(cand, idx % 10 + 1, voice, rate)
            m2 = m2 * target / active_rms(m2)
            inserts.append((t, np.concatenate([m, np.zeros(int(RATE * 0.25)), m2])))
            markers.append({"pos": pos, "index": idx, "then": idx % 10 + 1, "base_t": round(t, 3),
                            "before": before})
        else:
            inserts.append((t, m))
            markers.append({"pos": pos, "index": idx, "base_t": round(t, 3), "before": before})
    if not inserts:
        return None
    clip, starts = splice(audio, inserts)
    for mk, s, (_, m) in zip(markers, starts, inserts):
        mk["clip_t"], mk["dur"] = round(s, 3), round(len(m) / RATE, 3)
    label = variant_label(cand, voice, rate, level, pad) + ("+b2b" if back_to_back else "")
    name = "%s__%s__%d%s.wav" % (re.sub(r"[^A-Za-z0-9+,@-]", "_", label),
                                 os.path.basename(base)[:-4], idx_gap, ("-r%d" % rep) if rep else "")
    write16(os.path.join(CLIPS, name), clip)
    return {"clip": name, "cand": cand, "label": label, "base": base, "lang": lang,
            "voice": voice, "rate": rate, "level": level, "pad": pad, "rep": rep, "markers": markers}


def build(argv):
    os.makedirs(CLIPS, exist_ok=True)
    manifest = []
    # the baselines: the base clips themselves, twice each (Wispr's own run-to-run noise)
    for base, lang in BASES:
        name = "base__%s.wav" % os.path.basename(base)[:-4]
        write16(os.path.join(CLIPS, name), read16(os.path.join(CORPUS, base)))
        for rep in (1, 2):
            manifest.append({"clip": name, "cand": "base", "label": "base", "base": base,
                             "lang": lang, "markers": [], "rep": rep})
    # phase 1: every candidate × every base, one marker in a pause and one mid-phrase
    for cand in CANDIDATES:
        for b, (base, lang) in enumerate(BASES):
            e = build_one(base, lang, cand, b % 10 + 1, (b + 5) % 10 + 1)
            if e:
                e["phase"] = 1
                manifest.append(e)
    json.dump(manifest, open(MANIFEST, "w"), ensure_ascii=False, indent=1)
    for base, lang in BASES:
        info = word_timings(os.path.join(CORPUS, base), lang)
        g, m = splice_points(info["words"], read16(os.path.join(CORPUS, base)))
        print("%-38s gap %s  mid %s" % (base, g, m))
    print("%d clips in %s" % (len(manifest), MANIFEST))


def build_phase2(entries):
    """Append phase-2 clips (called with a list of build_one kwargs dicts)."""
    manifest = json.load(open(MANIFEST))
    have = {e["clip"] for e in manifest}
    for kw in entries:
        phase = kw.pop("phase", 2)
        e = build_one(**kw)
        if e and e["clip"] not in have:
            e["phase"] = phase
            manifest.append(e)
            have.add(e["clip"])
    json.dump(manifest, open(MANIFEST, "w"), ensure_ascii=False, indent=1)
    return manifest


def phase2(argv):
    """What phase 1 pointed at (2026-09-30 21:30): his own voice survives, Samantha is dropped by
    the recogniser itself — so more of his voice, his other two kinds, back-to-back pairs, and the
    TTS knobs that might make a synthetic marker sound like more of the same speaker."""
    entries = []
    for b, (base, lang) in enumerate(BASES):
        g, m = b % 10 + 1, (b + 5) % 10 + 1
        entries += [
            dict(base=base, lang=lang, cand="his-screenshot", idx_gap=g, idx_mid=m, rep=2),
            dict(base=base, lang=lang, cand="his-screenshot", idx_gap=g, idx_mid=m, back_to_back=True),
            dict(base=base, lang=lang, cand="his-selected", idx_gap=g, idx_mid=m),
            dict(base=base, lang=lang, cand="his-picked", idx_gap=g, idx_mid=m),
            dict(base=base, lang=lang, cand="tone-screenshot", idx_gap=g, idx_mid=m, rep=2),
            dict(base=base, lang=lang, cand="screenshot", idx_gap=g, idx_mid=m, voice="Daniel"),
            dict(base=base, lang=lang, cand="screenshot", idx_gap=g, idx_mid=m, level=6),
            dict(base=base, lang=lang, cand="screenshot", idx_gap=g, idx_mid=m, pad=0.3),
            dict(base=base, lang=lang, cand="screenshot", idx_gap=g, idx_mid=m, rate=150),
        ]
    man = build_phase2(entries)
    print(len([e for e in man if e.get("phase") == 2]), "phase-2 clips")


def phase3_dictionary(argv):
    """`walkieshot` again, after the one Dictionary entry `walkieshot` was added in the guest."""
    entries = [dict(base=base, lang=lang, cand="walkieshot", idx_gap=b % 10 + 1, idx_mid=(b + 5) % 10 + 1,
                    rep=3, phase=3) for b, (base, lang) in enumerate(BASES)]
    man = build_phase2(entries)
    print(len([e for e in man if e.get("phase") == 3]), "phase-3 clips")


# ── drive ────────────────────────────────────────────────────────────────────
def done_keys():
    keys = set()
    if os.path.exists(RESULTS):
        for l in open(RESULTS):
            if l.strip():
                r = json.loads(l)
                if (r.get("text") or r.get("asr")) and not r.get("host"):
                    keys.add((r["clip"], r.get("rep", 0)))
    return keys


def gate_ok():
    """The VM is ours while nobody else holds it (busy file) — checked before every clip."""
    busy = os.path.expanduser("~/.walkie-talkie/scheduled/wt-lab.busy")
    if os.path.exists(busy) and "wt-wispr-markers" not in open(busy).read():
        return False
    return True


def single_driver():
    """One player at a time: two drivers playing into the same device gave rows that mixed two
    clips (21:02, 2026-09-30) — dropped, listed in work/dropped-rows.json."""
    import fcntl
    os.makedirs(WORK, exist_ok=True)
    f = open(os.path.join(WORK, "drive.lock"), "w")
    try:
        fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        sys.exit("another driver holds work/drive.lock")
    return f


def drive(argv):
    _lock = single_driver()  # noqa: F841 — held for the life of the process
    manifest = json.load(open(MANIFEST))
    only = set(argv[argv.index("--only") + 1].split(",")) if "--only" in argv else None
    phase = int(argv[argv.index("--phase") + 1]) if "--phase" in argv else None
    limit = int(argv[argv.index("--limit") + 1]) if "--limit" in argv else 10 ** 6
    todo = [e for e in manifest
            if (only is None or e["label"] in only or e["cand"] in only)
            and (phase is None or e.get("phase", 0 if e["cand"] == "base" else 1) == phase)
            and (e["clip"], e.get("rep", 0)) not in done_keys()]
    random.Random(7).shuffle(todo)      # spread any drift in Wispr's service across candidates
    n = 0
    for e in todo[:limit]:
        if not gate_ok():
            print("⏸ VM taken — stopping", flush=True)
            return
        t0 = time.time()
        cmd = ["tart", "exec", "wt-lab", "/usr/bin/python3", GUEST + "/guest.py", GUEST + "/clips/" + e["clip"],
               os.environ.get("WISPR_DEV", "BlackHole 2ch")]
        try:
            p = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
            line = (p.stdout.strip().splitlines() or [""])[-1]
            row = json.loads(line)
        except Exception as ex:  # noqa: BLE001
            row = {"error": str(ex)[-400:] + " " + (locals().get("p") and (p.stderr or "")[-400:] or "")}
        row.update({k: e[k] for k in ("clip", "cand", "label", "base", "lang", "markers") if k in e})
        row.update(rep=e.get("rep", 0), phase=e.get("phase", 0),
                   at=time.strftime("%F %T", time.localtime(t0)))
        with open(RESULTS, "a") as f:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")
        n += 1
        hits = [m.group(0) for m in pattern_of(e["cand"]).finditer(row.get("text") or "")] if e["cand"] != "base" else []
        print("%s %3d %-44s %-5s %s | %s" % (row["at"][11:], n, e["clip"][:44], row.get("mic", "")[-14:],
                                            hits, (row.get("text") or row.get("error", ""))[:120]), flush=True)


# ── drive on the host (only while Victor is away) ────────────────────────────
HOST_STATE = os.path.join(WORK, "host-session.json")
QUIET_S = 300          # teacher_label.Gate's five minutes


def relay_get(path, body=None):
    import urllib.request
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request("http://127.0.0.1:8917/" + path, data=data,
                                 method="POST" if data is not None else "GET")
    with urllib.request.urlopen(req, timeout=10) as r:
        return json.loads(r.read())


def osa(script):
    return subprocess.run(["osascript", "-e", script], capture_output=True, text=True).stdout.strip()


def front_tty():
    app = osa('tell application "System Events" to get name of first process whose frontmost is true')
    if app != "Terminal":
        return app, None
    return app, osa('tell application "Terminal" to get tty of selected tab of front window')


def host_setup(argv):
    """Once, before the host batches: a throwaway `cat > /dev/null` tab in front and bound, the
    bridge disarmed (his room would otherwise be carried into From Walkie beside the clip), the
    pasteboard's text saved (Q17 leaves every finished sentence on it)."""
    st = relay_get("test/state")
    prior = (st.get("bound") or {}).get("tty")
    clip = subprocess.run(["pbpaste"], capture_output=True).stdout
    os.makedirs(WORK, exist_ok=True)
    open(os.path.join(WORK, "pasteboard.bak"), "wb").write(clip)
    tty = osa('tell application "Terminal"\n set t to do script "printf \'\\\\e]0;wispr-markers sink\\\\a\'; cat > /dev/null"\n'
              ' activate\n delay 1\n return tty of t\nend tell')
    time.sleep(1.5)
    bound = relay_get("bind", {"tty": tty.replace("/dev/", "")})
    bridge = relay_get("test/bridge", {"on": False})
    json.dump({"prior_tty": prior, "sink_tty": tty, "bound": bound, "bridge": bridge,
               "at": time.strftime("%F %T")}, open(HOST_STATE, "w"), indent=1)
    print(json.dumps(json.load(open(HOST_STATE)), indent=1))


def host_teardown(argv):
    s = json.load(open(HOST_STATE))
    out = {}
    out["bridge"] = relay_get("test/bridge", {"on": True})
    if s.get("prior_tty"):
        out["rebind"] = relay_get("bind", {"tty": s["prior_tty"]})
    tty = s["sink_tty"]
    subprocess.run(["pkill", "-t", tty.replace("/dev/", ""), "-x", "cat"])
    time.sleep(0.5)
    out["close"] = osa('tell application "Terminal"\n repeat with w in windows\n  repeat with t in tabs of w\n'
                       '   if tty of t is "%s" then do script "exit" in t\n  end repeat\n end repeat\nend tell' % tty)
    bak = os.path.join(WORK, "pasteboard.bak")
    if os.path.exists(bak):
        subprocess.run(["pbcopy"], input=open(bak, "rb").read())
        out["pasteboard"] = "restored"
    out["target"] = relay_get("target")
    print(json.dumps(out, indent=1, ensure_ascii=False))


def host_drive(argv):
    """One batch (≤ `--limit` clips, sized to fit `hands-off run`'s 900 s). Every clip is gated on
    his absence (HumanWatch ≥ 5 min quiet, the relay idle, the sink tab still in front); a gate that
    fails ends the batch with exit 3, a clip he interrupts is dismissed and ends it with exit 4."""
    sys.path.insert(0, os.path.join(HERE, "..", "..", "helpers"))
    import human_watch
    import wispr_loopback as wl
    s = json.load(open(HOST_STATE))
    watch = human_watch.HumanWatch()
    if not watch.start():
        print("human watch failed to start: %s" % watch.failed)
        sys.exit(3)
    manifest = json.load(open(MANIFEST))
    only = set(argv[argv.index("--only") + 1].split(",")) if "--only" in argv else None
    phase = int(argv[argv.index("--phase") + 1]) if "--phase" in argv else None
    limit = int(argv[argv.index("--limit") + 1]) if "--limit" in argv else 20
    todo = [e for e in manifest
            if (only is None or e["label"] in only or e["cand"] in only)
            and (phase is None or e.get("phase", 0) == phase)
            and (e["clip"], e.get("rep", 0)) not in done_keys()]
    random.Random(7).shuffle(todo)
    idx, name = wl.resolve_device("From Walkie")
    n = 0
    for e in todo[:limit]:
        why = None
        if watch.since_human < QUIET_S:
            why = "he was at the Mac %.0f s ago" % watch.since_human
        else:
            st = relay_get("test/state")
            if st.get("busy") or st.get("listening") or st.get("dictationStartedAt"):
                why = "relay busy %s" % st.get("busyWhy")
            else:
                app, tty = front_tty()
                if tty != s["sink_tty"]:
                    why = "front is %s %s, not the sink tab" % (app, tty)
        if why:
            print("⏸ gate: %s — stopping" % why, flush=True)
            sys.exit(3)
        t0 = time.time()
        started = time.monotonic()
        try:
            h = wl.dictate(os.path.join(CLIPS, e["clip"]), idx, timeout=60,
                           abort=lambda: watch.active_since(started))
        except wl.PlaybackAborted:
            print("✋ he touched the Mac mid-clip — dismissed, stopping", flush=True)
            sys.exit(4)
        extra = None
        if h:
            db = wl._open_wispr()
            try:
                extra = db.execute("SELECT rowid, pastedText, status FROM History WHERE transcriptEntityId = ?",
                                   (h.id,)).fetchone()
            finally:
                db.close()
        row = {"row": h.id if h else None, "rowid": extra[0] if extra else None,
               "asr": h.asr if h else "", "text": (h.formatted or h.asr) if h else "",
               "pasted": extra[1] if extra else None, "status": extra[2] if extra else None,
               "seconds": h.seconds if h else 0, "mic": h.mic if h else "", "device": name, "host": True}
        row.update({k: e[k] for k in ("clip", "cand", "label", "base", "lang", "markers") if k in e})
        row.update(rep=e.get("rep", 0), phase=e.get("phase", 0), at=time.strftime("%F %T", time.localtime(t0)))
        if row["mic"] and "walkie" not in row["mic"].lower():
            row["error"] = "Wispr recorded from %s, not From Walkie" % row["mic"]
            row["text_wrong_mic"], row["text"] = row["text"], ""
        with open(RESULTS, "a") as f:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")
        n += 1
        hits = [m.group(0) for m in pattern_of(e["cand"]).finditer(row["text"])] if e["cand"] != "base" else []
        print("%s %3d %-44s %s | %s" % (row["at"][11:], n, e["clip"][:44], hits,
                                       (row["text"] or row.get("error", ""))[:110]), flush=True)
        # the relay delivers his "own" sentence into the sink tab; let it finish before the next
        end = time.monotonic() + 20
        while time.monotonic() < end and relay_get("test/state").get("busy"):
            time.sleep(0.5)
    watch.stop()


# ── score ────────────────────────────────────────────────────────────────────
def norm_words(s):
    s = unicodedata.normalize("NFKD", (s or "").lower())
    s = "".join(c for c in s if not unicodedata.combining(c))
    return re.findall(r"[a-z0-9]+", s)


def tokens_with_spans(s):
    s2 = unicodedata.normalize("NFKD", (s or "").lower())
    # keep a map from normalised to original offsets by normalising char by char
    out = []
    for m in re.finditer(r"\w+", s or ""):
        w = "".join(c for c in unicodedata.normalize("NFKD", m.group(0).lower()) if not unicodedata.combining(c))
        w = re.sub(r"[^a-z0-9]", "", w)
        if w:
            out.append((w, m.start(), m.end()))
    return out


def map_index(src, dst, k):
    """Word index k in `src` → the corresponding index in `dst`, by alignment."""
    sm = difflib.SequenceMatcher(a=src, b=dst, autojunk=False)
    best = None
    for a, b, size in sm.get_matching_blocks():
        for j in range(size + 1):
            d = abs(a + j - k)
            if best is None or d < best[0]:
                best = (d, b + j + (k - (a + j)))
    return max(0, min(len(dst), best[1] if best else k))


def wer(r, h):
    if not r:
        return 0.0 if not h else 1.0
    d = list(range(len(h) + 1))
    for i in range(1, len(r) + 1):
        prev, d[0] = d[0], i
        for j in range(1, len(h) + 1):
            cur = min(d[j] + 1, d[j - 1] + 1, prev + (r[i - 1] != h[j - 1]))
            prev, d[j] = d[j], cur
    return d[len(h)] / len(r)


def score_row(row, base_text, base2_text, words_info):
    """Per marker: recovered, index right, in place (exact / ±1), no damage (±3 words)."""
    text = row.get("text") or ""
    pat = pattern_of(row["cand"])
    found = list(pat.finditer(text))
    toks = tokens_with_spans(text)
    # the text with every match taken out, and each match's position in that word stream
    kept, match_pos = [], []
    mi = 0
    for w, s, e in toks:
        while mi < len(found) and found[mi].end() <= s:
            match_pos.append(len(kept))
            mi += 1
        if mi < len(found) and found[mi].start() <= s < found[mi].end():
            continue
        kept.append(w)
    while mi < len(found):
        match_pos.append(len(kept))
        mi += 1
    ref = norm_words(base_text)
    wl = [re.sub(r"[^a-z0-9]", "", "".join(c for c in unicodedata.normalize("NFKD", w["w"].lower())
                                           if not unicodedata.combining(c))) for w in words_info["words"]]
    out = []
    used = set()
    bang = row["cand"].startswith("bang")
    pos_of = [map_index(kept, ref, match_pos[j]) for j in range(len(found))]
    idx_of = [None if bang else index_value(found[j].group(found[j].lastindex or 0)) for j in range(len(found))]
    marks = sorted(row["markers"], key=lambda m: m["clip_t"])
    expect = [map_index(wl, ref, mk["before"]) for mk in marks]
    pick = {}
    # 1) a match that says this marker's number, nearest first; 2) any match within 5 words
    for k, mk in enumerate(marks):
        if bang:
            continue
        c = [(abs(pos_of[j] - expect[k]), j) for j in range(len(found)) if j not in used and idx_of[j] == mk["index"]]
        if c:
            pick[k] = min(c)[1]
            used.add(pick[k])
    for k, mk in enumerate(marks):
        if k in pick:
            continue
        c = [(abs(pos_of[j] - expect[k]), j) for j in range(len(found)) if j not in used and abs(pos_of[j] - expect[k]) <= 5]
        if c:
            pick[k] = min(c)[1]
            used.add(pick[k])
    for k, mk in enumerate(marks):
        exp_ref = expect[k]
        res = {"pos": mk["pos"], "index": mk["index"], "recovered": False, "index_ok": False,
               "in_place": False, "near_place": False, "damage": None}
        if k in pick:
            j = pick[k]
            got_ref = pos_of[j]
            res.update(recovered=True, index_ok=bang or idx_of[j] == mk["index"], in_place=got_ref == exp_ref,
                       near_place=abs(got_ref - exp_ref) <= 1, got=found[j].group(0).strip())
            if mk.get("then"):
                nxt = [q for q in range(len(found)) if q not in used and q > j]
                res["then_ok"] = bool(nxt) and (bang or idx_of[nxt[0]] == mk["then"])
                if nxt:
                    used.add(nxt[0])
        # damage: the 3 words either side of where it belongs, marker removed, against the baseline
        at_kept = map_index(ref, kept, exp_ref)
        win_ref = ref[max(0, exp_ref - 3):exp_ref + 3]
        win_got = kept[max(0, at_kept - 3):at_kept + 3]
        res["damage"] = win_ref != win_got
        if base2_text:
            r2 = norm_words(base2_text)
            at2 = map_index(ref, r2, exp_ref)
            res["noise"] = win_ref != r2[max(0, at2 - 3):at2 + 3]
        res["ctx"] = " ".join(kept[max(0, at_kept - 3):at_kept]) + " ‸ " + " ".join(kept[at_kept:at_kept + 3])
        out.append(res)
    extra = len(found) - len(used)
    return out, extra, wer(ref, kept)


def strip_matches(text, pat):
    """Word tokens of `text` with every marker match taken out, plus each match's position."""
    found = list(pat.finditer(text))
    kept, pos, mi = [], [], 0
    for w, st, en in tokens_with_spans(text):
        while mi < len(found) and found[mi].end() <= st:
            pos.append(len(kept))
            mi += 1
        if mi < len(found) and found[mi].start() <= st < found[mi].end():
            continue
        kept.append(w)
    while mi < len(found):
        pos.append(len(kept))
        mi += 1
    return found, kept, pos


def asr_anchor(row, base_text, words_info):
    """What a relay could ship: find each marker in `asrText` (by its number), carry its position
    into `formattedText` by aligning the two (markers removed from both), and ask whether that
    lands where the marker belongs in Wispr's formatted baseline. Returns per marker: placed ±1."""
    pat = pattern_of(row["cand"])
    af, akept, apos = strip_matches(row.get("asr") or "", pat)
    ff, fkept, fpos = strip_matches(row.get("text") or "", pat)
    ref = norm_words(base_text)
    wl = [re.sub(r"[^a-z0-9]", "", "".join(c for c in unicodedata.normalize("NFKD", w["w"].lower())
                                           if not unicodedata.combining(c))) for w in words_info["words"]]
    out = []
    for mk in sorted(row["markers"], key=lambda m: m["clip_t"]):
        exp = map_index(wl, ref, mk["before"])
        hit = [j for j in range(len(af)) if index_value(af[j].group(af[j].lastindex or 0)) == mk["index"]]
        if not hit:
            out.append(False)
            continue
        at_f = map_index(akept, fkept, apos[hit[0]])     # asr position → formatted (marker-free)
        at_ref = map_index(fkept, ref, at_f)              # → the formatted baseline
        out.append(abs(at_ref - exp) <= 1)
    return out


def load_rows():
    return [json.loads(l) for l in open(RESULTS) if l.strip()] if os.path.exists(RESULTS) else []


def score(argv):
    rows = [r for r in load_rows() if r.get("text") and not r.get("host")]
    bases, bases_asr = {}, {}
    for r in rows:
        if r["cand"] == "base":
            bases.setdefault(r["base"], []).append(r["text"])
            bases_asr.setdefault(r["base"], []).append(r.get("asr") or r["text"])
    table = {}
    detail = []
    for r in rows:
        if r["cand"] == "base" or r["base"] not in bases:
            continue
        b = bases[r["base"]]
        info = word_timings(os.path.join(CORPUS, r["base"]), r["lang"])
        per, extra, w = score_row(r, b[0], b[1] if len(b) > 1 else None, info)
        # the same markers looked for in `asrText` — the recogniser's words before Wispr's
        # formatter, in the same History row the relay already reads
        per_asr, _, _ = score_row(dict(r, text=r.get("asr") or ""), bases_asr[r["base"]][0], None, info)
        anchored = asr_anchor(r, b[0], info) if not r["cand"].startswith("bang") else [False] * len(per)
        for m, a in zip(per, anchored):
            m["anchored"] = a
        for m, ma in zip(per, per_asr):
            m["asr_recovered"], m["asr_index_ok"] = ma["recovered"], ma["recovered"] and ma["index_ok"]
            m["asr_place"] = ma["recovered"] and ma["index_ok"] and ma["near_place"]
        for m in per:
            key = (r["label"], m["pos"], r["lang"])
            t = table.setdefault(key, {"n": 0, "rec": 0, "idx": 0, "place": 0, "near": 0, "dmg": 0, "noise": 0,
                                       "extra": 0, "b2b": 0, "b2b_n": 0, "asr": 0, "asr_idx": 0, "asr_place": 0, "anch": 0})
            t["n"] += 1
            t["rec"] += m["recovered"]
            t["idx"] += m["recovered"] and m["index_ok"]
            t["place"] += m["in_place"]
            t["asr"] += m["asr_recovered"]
            t["asr_idx"] += m["asr_index_ok"]
            t["asr_place"] += m["asr_place"]
            t["anch"] += m["anchored"]
            t["near"] += m["near_place"]
            t["dmg"] += bool(m["damage"])
            t["noise"] += bool(m.get("noise"))
            if "then_ok" in m:
                t["b2b_n"] += 1
                t["b2b"] += m["then_ok"]
            detail.append(dict(clip=r["clip"], **m))
        if per:
            table[(r["label"], per[0]["pos"], r["lang"])]["extra"] += extra
    if "--summary" in argv:
        summary(rows, bases, bases_asr)
        return table
    if "--detail" in argv:
        for d in detail:
            print(json.dumps(d, ensure_ascii=False))
    # base false positives: the regex of every candidate over Wispr's text of the un-spliced clips
    fp = {c: sum(len(list(pattern_of(c).finditer(t))) for ts in bases.values() for t in ts) for c in PATTERNS}
    print("%-34s %-4s %-3s %4s %8s %8s %8s %8s %8s %6s %10s %6s" % ("candidate", "pos", "lng", "n", "found", "index", "place",
                                                          "±1word", "damage", "extra", "asr f/i/±1", "anchor"))
    for key in sorted(table):
        t = table[key]
        print("%-34s %-4s %-3s %4d %8s %8s %8s %8s %8s %6d %10s %6d%s" % (
            key[0], key[1], key[2], t["n"], "%d" % t["rec"], "%d" % t["idx"], "%d" % t["place"], "%d" % t["near"],
            "%d/%d" % (t["dmg"], t["noise"]), t["extra"], "%d/%d/%d" % (t["asr"], t["asr_idx"], t["asr_place"]), t["anch"], ("  b2b %d/%d" % (t["b2b"], t["b2b_n"])) if t["b2b_n"] else ""))
    print("\nfalse positives in %d baseline texts:" % sum(len(v) for v in bases.values()),
          {k: v for k, v in fp.items() if v})
    return table


def summary(rows, bases, bases_asr):
    """One line per candidate: markers found / number right / within one word, in the formatted
    text and via `asrText`; and whole clips where every marker came back clean (the rule a relay
    would ship: all or nothing, else the footer with clocks)."""
    agg = {}
    for r in rows:
        if r["cand"] == "base" or r["base"] not in bases:
            continue
        info = word_timings(os.path.join(CORPUS, r["base"]), r["lang"])
        per, extra, _ = score_row(r, bases[r["base"]][0], None, info)
        bang = r["cand"].startswith("bang")
        anch = asr_anchor(r, bases[r["base"]][0], info) if not bang else [False] * len(per)
        per_asr, _, _ = score_row(dict(r, text=r.get("asr") or ""), bases_asr[r["base"]][0], None, info)
        want = []
        for m in sorted(r["markers"], key=lambda m: m["clip_t"]):
            want += [m["index"]] + ([m["then"]] if m.get("then") else [])
        a = agg.setdefault(r["label"], dict(clips=0, n=0, f=0, fi=0, fp=0, a=0, ai=0, anch=0, cf=0, ca=0))
        a["clips"] += 1
        a["n"] += len(per)
        a["f"] += sum(m["recovered"] for m in per)
        a["fi"] += sum(m["recovered"] and m["index_ok"] for m in per)
        a["fp"] += sum(m["recovered"] and m["index_ok"] and m["near_place"] for m in per)
        a["a"] += sum(m["recovered"] for m in per_asr)
        a["ai"] += sum(m["recovered"] and m["index_ok"] for m in per_asr)
        a["anch"] += sum(anch)
        pat = pattern_of(r["cand"])
        fnums = [index_value(m.group(m.lastindex or 0)) for m in pat.finditer(r.get("text") or "")]
        anums = [index_value(m.group(m.lastindex or 0)) for m in pat.finditer(r.get("asr") or "")]
        a["cf"] += (not bang) and fnums == want and all(m["near_place"] for m in per)
        a["ca"] += (not bang) and anums == want and all(anch)
    print("%-26s %5s %5s | %-16s | %-16s %7s | %-10s %-10s" % ("candidate", "clips", "marks", "formatted f/i/±1",
                                                                 "asrText f/i", "anchor", "clean fmt", "clean asr"))
    for k, a in sorted(agg.items(), key=lambda kv: -(kv[1]["anch"] / max(1, kv[1]["n"]))):
        print("%-26s %5d %5d | %4d %4d %4d     | %4d %4d        %7d | %4d/%-5d %4d/%-5d" % (
            k, a["clips"], a["n"], a["f"], a["fi"], a["fp"], a["a"], a["ai"], a["anch"],
            a["cf"], a["clips"], a["ca"], a["clips"]))


def fp(argv):
    """Every candidate's regex over Victor's real History rows (a COPY of flow.sqlite, never the live file)."""
    import sqlite3
    db = sqlite3.connect("file:%s?mode=ro" % argv[argv.index("fp") + 1], uri=True)
    rows = [r[0] for r in db.execute("SELECT formattedText FROM History WHERE formattedText IS NOT NULL "
                                     "AND formattedText != ''")]
    print("%d History rows with formattedText" % len(rows))
    for c in PATTERNS:
        pat = pattern_of(c)
        hits = [(t, m.group(0)) for t in rows for m in pat.finditer(t)]
        print("%-16s %4d hits in %d rows" % (c, len(hits), len({id(t) for t, _ in hits})))
        for t, g in hits[:6]:
            i = t.find(g)
            print("      …%s[%s]%s…" % (t[max(0, i - 50):i].replace("\n", " "), g, t[i + len(g):i + len(g) + 30].replace("\n", " ")))


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    {"build": build, "drive": drive, "score": score, "fp": fp,
     "phase2": phase2, "phase3": phase3_dictionary, "host-setup": host_setup, "host-drive": host_drive, "host-teardown": host_teardown}.get(cmd, lambda a: print(__doc__))(sys.argv)
