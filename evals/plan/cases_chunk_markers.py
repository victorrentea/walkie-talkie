"""A picture taken inside chunk 2 and chunk 3 lands between the right words (2026-10-22) — the
real local model, not the fake: Victor, *"dacă poți să aterizezi la punctul corect, chiar dacă a
fost făcută într-un text care a fost transcris în chunk-ul 2 sau 3"*.

The take is built so the right place is unambiguous: three stretches of his speech with 1.4 s of
digital silence between them (the planner cuts there — gap ≥ 0.9 s), and inside stretches 2 and 3 a
0.6 s silence of their own (too short to be cut at), spliced at the quietest 64 ms of the clip so it
falls between two words. A screenshot (`POST /test/area`) is taken in the middle of each 0.6 s
silence, so the first lands in chunk 2 and the second in chunk 3. The truth is the same model on the
halves alone (`POST /test/local-fallback`, nothing delivered): the token must sit after the last
words of the first half and before the first words of the second, within one word either side.
Lives in its own module so `cases_chunks`' fake helper is never in for it.
"""
import difflib, os, re, time, wave
import numpy as np
from harness import *
from cases_audio import on_inject, not_inject, pre, INJECT
from cases_chunks import start, stop, play_bg

TAGS = ("audio", "chunks", "local", "markers")
SR = 16000


def _clip():
    w = wave.open(CLIP_EN_LONG)
    assert w.getframerate() == SR and w.getnchannels() == 1
    x = np.frombuffer(w.readframes(w.getnframes()), np.int16)
    w.close()
    return x


def _quietest(x, a, b):
    """The middle of the quietest 64 ms hop in [a, b) seconds."""
    hop = 1024
    i, j = int(a * SR), int(b * SR)
    seg = x[i:j].astype(np.float32)
    n = len(seg) // hop
    rms = np.sqrt((seg[: n * hop].reshape(n, hop) ** 2).mean(axis=1))
    k = int(np.argmin(rms))
    return i + k * hop + hop // 2


def _write(path, x):
    w = wave.open(path, "wb")
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes(x.astype(np.int16).tobytes())
    w.close()


def build():
    """The take and its pieces' files; `marks` = the file times (s) of the two 0.6 s gaps' middles."""
    x = _clip()
    z = lambda s: np.zeros(int(s * SR), np.int16)
    s1 = x[0: int(9.5 * SR)]
    c2 = _quietest(x, 14.0, 15.0)
    s2a, s2b = x[int(10.0 * SR): c2], x[c2: c2 + int(4.5 * SR)]
    b3 = c2 + int(5.0 * SR)
    c3 = _quietest(x, b3 / SR + 4.0, b3 / SR + 5.0)
    s3a, s3b = x[b3: c3], x[c3: c3 + int(4.5 * SR)]
    parts = [s1, z(1.4), s2a, z(0.6), s2b, z(1.4), s3a, z(0.6), s3b]
    t = 0.0
    times = []
    for p in parts:
        times.append(t)
        t += len(p) / SR
    marks = [times[3] + 0.3, times[7] + 0.3]
    take = f"{WORK}/chunk-markers-take.wav"
    _write(take, np.concatenate(parts))
    halves = {}
    for name, p in (("2a", s2a), ("2b", s2b), ("3a", s3a), ("3b", s3b)):
        halves[name] = f"{WORK}/chunk-markers-{name}.wav"
        _write(halves[name], p)
    return take, marks, halves


def _words(text):
    return [w for w in re.sub(r"[^\w\s']", " ", (text or "").lower()).split() if w]


def _near(a, options):
    return any(difflib.SequenceMatcher(None, a, o).ratio() >= 0.8 for o in options)


TOKEN = re.compile(r"\[📸(\d+)✂️[^\]]*\]")


@case("CM1", TAGS,
      expect="a 32 s take on the REAL local model, cut in 3 chunks at its 1.4 s silences; a screenshot "
             "taken mid-chunk-2 and one mid-chunk-3 (inside 0.6 s silences that are not cut) land "
             "between the same words as the model hears around those silences (± one word)")
def cm1():
    why = pre(("whisper",))
    if why: return "SKIP", why
    take, marks, halves = build()
    truth = {}
    for name, path in halves.items():
        code, r = post("/test/local-fallback", {"wav": path}, timeout=200)
        if code != 200 or not r.get("ok"):
            return "ERROR", f"rig: the model did not decode half {name}: {code} {r}"
        truth[name] = _words(r.get("text"))
    # **No Terminal, no delivery** (2026-10-22: Terminal was hung): Autosend off for the run, the
    # prompt is read off the held panel (`state.prompt.text`) and cancelled — nothing is pasted or
    # typed anywhere. The cancel writes the envelope to the clipboard (Q17); his text is put back.
    import subprocess
    clip0 = subprocess.run(["pbpaste"], capture_output=True, text=True).stdout
    text, m = "", log_mark()
    try:
        post("/test/autosend", {"on": False})
        mic_override(INJECT)
        m = start()
        if not m: return "FAIL", "the microphone never opened"
        if not on_inject(m): stop(); return not_inject(m)
        lead = 0.5
        t0 = time.time()
        th = play_bg(take, lead=lead)
        shots = []
        try:
            for mk in marks:
                delay = t0 + lead + mk - time.time()
                if delay > 0: time.sleep(delay)
                code, r = post("/test/area", {})
                shots.append((code, round(time.time() - t0 - lead, 2)))
        finally:
            th.join(60)
        time.sleep(0.15)
        stop()
        wait_for(lambda: (state().get("prompt") or {}).get("held"), tmo("local") + 60, 0.2)
        text = (state().get("prompt") or {}).get("text") or ""
    finally:
        if (state().get("prompt") or {}).get("held"):
            post("/test/prompt", {"do": "cancel"})
        post("/test/autosend", {"on": True})
        mic_override(None)
        wait_for(lambda: not relay_busy(), 30, 0.5)
        subprocess.run(["pbcopy"], input=clip0, text=True)
    log = log_since(m)
    cuts = [float(c) for c in re.findall(r"✂️ local: chunk \d+ cut at ([\d.]+) s", log)]
    cues = [float(c) for c in re.findall(r"marker cue: shot \d+ at ([\d.]+)s into the recording", log)]
    found = list(TOKEN.finditer(text))
    notes = [f"cuts at {cuts}, cues at {cues} (recording s), shots {shots}"]
    oks = [len(cuts) >= 2, len(cues) == 2, len(found) == 2,
           bool(cuts) and len(cues) == 2 and cues[0] > cuts[0] and cues[1] > cuts[0]]
    for i, (a, b) in enumerate((("2a", "2b"), ("3a", "3b"))):
        if i >= len(found):
            notes.append(f"token {i + 1}: not in the words")
            continue
        before = _words(text[: found[i].start()])[-1:] or [""]
        after = _words(TOKEN.sub(" ", text[found[i].end():]))[:1] or [""]
        good_before = _near(before[0], truth[a][-2:])
        good_after = _near(after[0], truth[b][:2])
        oks.append(good_before and good_after)
        notes.append(f"📸{found[i].group(1)}: …{before[0]} [📸] {after[0]}… — truth …{' '.join(truth[a][-2:])} | "
                     f"{' '.join(truth[b][:2])}… (before {good_before}, after {good_after})")
    notes.append(f"chunked text: {re.sub(r'\s+', ' ', TOKEN.sub('[📸]', text))[:400]!r}")
    return ("PASS" if all(oks) else "FAIL"), " · ".join(notes)
