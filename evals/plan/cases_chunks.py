"""The local model's chunks against in-flight gestures (2026-10-22) — `LocalWhisperSource`'s takes,
the chunks cut while he speaks and the Q12 queue (a78a02f, 1b789d9, 90e7304, 5da8bcb), driven hard and
deterministically: the installed app runs **`fake_whisper_helper.py`** instead of the model.

How the fake gets in: a `WT_WHISPER_HELPER=<this folder>/fake_whisper_helper.py` line in
`elevenlabs.env` (between two `# fake-whisper:` marks) and `POST /test/whisper {"restart": true}` —
the app reads the line at every helper spawn (both helpers: the sentence's and the live caption's).
`BEFORE_CASE` puts it in before each of these cases and takes it out (real model back, restart) before
any other case; `atexit` takes it out at the end. Even left behind, it never answers a sentence of
his: with no live harness lock the fake execs the real helper (`fake_whisper_helper.harness_alive`).
Its decodes go to `DecodeRate`'s `whisper-local-test` line and never to the voice corpus.

The answers say which audio they decoded — `r<n> <wav|chunk|tail> <seconds>s <md5[:6]>` — so a
delivered sentence is checked token by token against the fake's own log
(`~/.walkie-talkie/fake-whisper.jsonl`), the `✂️ local:` lines and `GET /test/state`.

The audio is real speech through the Loopback, as in `cases_audio`: `CLIP_EN_LONG` cut into 9.5 s
stretches with 1.4 s of digital silence between them, so the planner (trigger 10 s, gap ≥ 0.9 s,
chunk ≥ 8 s) cuts once per gap: a 3-stretch take (≈ 31 s) is 2 chunks + the tail, a 4-stretch one
(≈ 42 s) 3 + the tail. Start = `POST /test/gesture {"name": "forward-right", "direct": true}`
(`toggleDictation`, bound), stop = `forward-click` direct (`endDictation`), cancel = `POST /test/cancel`
(the ✕ / 🔼 ←'s `cancelDictationInFlight`) — handlers, no chord on the wire, so no hands-off needed.

    C1  chunks cut while recording; delivered = the chunk answers + the tail, in order; tail with `language`; no `words`
    C2  cancel while recording, a chunk in flight → nothing delivered, answers dropped, Recover has the WAV, no .pcm left
    C3  cancel after the stop, the tail decoding (slow) → nothing delivered, Recover has the WAV
    C4  queue: A (chunked, slow tail) stopped, B at +1.5 s → 📻 Ready from +0.8 s, A then B, a third start refused
    C5  cancel B (stopped, queued) while A still decodes → A delivered, B recoverable
    C6  one chunk fails → the whole WAV decoded → delivered
    C7  the helper dies on a chunk → brought back up, the whole take decoded, delivered (1b789d9)
    C8  a highlight mid-take → chunks cut after the cue ask `words`, earlier ones not; no word lost
    C9  ⌘⌃X (`POST /test/local-now`) while recording and while the tail decodes → one delivery, nothing lost
    C10 `POST /engine` mid-take and mid-settle → refused, or safe: one delivery, nothing lost
    C11 a 6 s take → one `wav` request, no chunk, delivered
    C12 `relay-restart.sh --dry-run --max-wait 4` while chunks are pending → refused (exit 3); never restarts

    python3 evals/plan/harness.py --only 'C[0-9]*'                # the installed app on 8917, this Mac's "🧪 WT Inject"
    WT_LOOPBACK="BlackHole 2ch" … (the Tart guest, docs/vm-lab.md)
"""
import atexit, glob, json, os, re, subprocess, threading, time, wave
from harness import *
from cases_audio import pre, rig, count, on_inject, not_inject, _quiet
import fake_whisper_helper as FW

HERE = os.path.dirname(os.path.abspath(__file__))
FAKE = os.path.join(HERE, "fake_whisper_helper.py")
MARK = "# fake-whisper: written by evals/plan/cases_chunks.py, removed after its cases"
_COV = covers("local", "recorder", "delivery", "gesture", "chip",
              extra=("ChunkPlanner", "VoiceCorpus", "relay-restart.sh", "tools/restart_gate.py"))
TAGS = ("audio", "chunks", "local")

TOKEN = re.compile(r"\br(\d+) (wav|chunk|tail) (\d+\.\d\d)s ([0-9a-f]{6})\b")
OPENED = r"mic: recording through"
CUT = r"✂️ local: chunk \d+ cut at"
ASSEMBLED = r"✂️ local: take (\d+) assembled from (\d+) piece"
WHOLE = r"✂️ local: a chunk of take \d+ got no answer — decoding the whole take"
STOPPED = r"🎙️ local recording stopped — ([\d.]+)s \(take (\d+)\)"
REFUSED = r"start refused — two sentences are already in flight"
MODEL_READY = r"local model ready — "


# ---------------------------------------------------------------- the fake in, the model back
_INST = {"on": False, "why": None}


def _env_block(on):
    """Our two marks and the line between them in `elevenlabs.env`, in or out; every other line
    (his key, the fake Scribe's block) byte for byte."""
    try:
        lines = open(ELEVEN_ENV, encoding="utf-8").read().splitlines()
        mode = os.stat(ELEVEN_ENV).st_mode & 0o777
    except FileNotFoundError:
        lines, mode = [], 0o600
    keep, inside = [], False
    for l in lines:
        if l.startswith(MARK):
            inside = not l.endswith("(end)")
            continue
        if not inside:
            keep.append(l)
    if on:
        keep += [MARK, f"WT_WHISPER_HELPER={FAKE}", MARK + " (end)"]
    if keep == lines:
        return
    tmp = ELEVEN_ENV + ".chunks-tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write("\n".join(keep) + ("\n" if keep else ""))
    os.chmod(tmp, mode)
    os.replace(tmp, ELEVEN_ENV)


def _helper():
    return state().get("whisper") or {}


def _fake_up():
    h = _helper()
    return h.get("ready") and "fake-whisper" in str(h.get("model") or "")


def _install():
    if _INST["why"]:                 # the installed build cannot take it: every case SKIPs, no retry
        return
    FW.reset()
    if _INST["on"] and _fake_up():
        return
    _env_block(True)
    post("/test/whisper", {"restart": True})
    # The stop is queued behind a real model still loading (an uninstall just before): its hello.
    if wait_for(_fake_up, tmo(20), 0.25):
        _INST.update(on=True, why=None)
        return
    model = _helper().get("model")
    _env_block(False)
    post("/test/whisper", {"restart": True})
    _INST.update(on=False, why=f"the installed app did not run WT_WHISPER_HELPER (model {model!r}) — "
                                 "install a build from 2026-10-22 or later")


def _uninstall():
    _env_block(False)
    if _INST["on"]:
        _quiet(post, "/test/whisper", {"restart": True})
        _INST["on"] = False


def _before(c):
    if c.get("module") == __name__:
        _install()
    elif _INST["on"]:
        _uninstall()


def _reset_after():
    if _INST["on"]:
        FW.reset()


BEFORE_CASE.append(_before)
CLEANUPS.append(_reset_after)
atexit.register(lambda: _quiet(_uninstall) if (_INST["on"] or _block_present()) else None)


def _block_present():
    try:
        return MARK in open(ELEVEN_ENV, encoding="utf-8").read()
    except OSError:
        return False


# A crashed run's line, with no run alive to own it: out at import (the fake would not answer as
# the fake anyway — `harness_alive` — but his helper should not be spawned through it at all).
if _block_present() and not FW.harness_alive():
    _env_block(False)


# ---------------------------------------------------------------- audio
def take_wav(blocks=3, block=9.5, gap=1.4, offset=0.0):
    """`blocks` stretches of his speech (`CLIP_EN_LONG` from `offset` s), `gap` s of digital silence
    between them — one cut per gap. **Offsets 0–60 only** (2026-10-22): the clip goes quiet around
    80–108 s (RMS ~105, hiss), and a take built there ends in silence — the app rightly drops
    that tail, which read as lost words in C9/C12."""
    assert offset <= 60, "CLIP_EN_LONG is hiss from ~80 s to ~108 s"
    path = f"{WORK}/chunks-{blocks}x{block}-{gap}-{int(offset)}.wav"
    if os.path.exists(path):
        return path
    r = wave.open(CLIP_EN_LONG)
    sr, width, ch = r.getframerate(), r.getsampwidth(), r.getnchannels()
    frames = r.readframes(r.getnframes())
    r.close()
    step = width * ch
    out = b""
    for i in range(blocks):
        a = int((offset + i * block) * sr) * step
        out += frames[a: a + int(block * sr) * step]
        if i < blocks - 1:
            out += b"\x00" * (int(gap * sr) * step)
    w = wave.open(path, "wb")
    w.setnchannels(ch); w.setsampwidth(width); w.setframerate(sr)
    w.writeframes(out)
    w.close()
    return path


def play_bg(wav, **kw):
    kw.setdefault("tail", 0.0)   # speech up to the stop — see `say`
    th = threading.Thread(target=play, args=(wav,), kwargs=kw, daemon=True)
    th.start()
    return th


# ---------------------------------------------------------------- the relay
def _pre():
    why = pre(("whisper",))
    if why:
        return why
    if _INST["why"]:
        return _INST["why"]
    s = state()
    if "readyForNext" not in s or "sentences" not in s:
        return "the installed build predates the local queue and chunks (2026-10-21)"
    if not s.get("sentenceQueue"):
        return "the sentence queue is off (WT_SENTENCE_QUEUE=0)"
    return None


def start():
    """A bound prompt (`toggleDictation`, no chord). The mark, or None if no microphone opened."""
    m = log_mark()
    post("/test/gesture", {"name": "forward-right", "direct": True})
    return m if wait_for(lambda: log_has(m, OPENED), tmo("mic_open"), 0.05) else None


def stop():
    """`endDictation` through the forward click's handler — only while a sentence records (at rest
    it would open a caret prompt)."""
    s = state()
    if s.get("listening") or s.get("isRecording"):
        post("/test/gesture", {"name": "forward-click", "direct": True})
        return time.time()
    return None


def say(wav, **kw):
    """Speech right up to the stop: the clip with no silent tail and a 0.15 s beat after it
    (2026-10-22). With 0.5 + 0.6 s of silence the planner (gap ≥ 0.9 s) rightly cut in that
    last pause and the tail was empty, so no case ever met a tail still decoding."""
    time.sleep(0.4)
    kw.setdefault("tail", 0.0)
    play(wav, **kw)
    time.sleep(0.15)


def rows_since(n0):
    n = outbox_count()
    return outbox_tail(n - n0) if n > n0 else []


def tokens(text):
    """`[(n, kind, seconds, md5)]` in the order they stand in the words, markers taken out."""
    bare = re.sub(r"\[[^\]]*\]", " ", text or "")
    return [(int(n), k, float(s), h) for n, k, s, h in TOKEN.findall(re.sub(r"\s+", " ", bare))]


def answered_tokens(epoch):
    return [t for a in FW.answers(epoch) if a.get("action") == "ok" for t in tokens(a.get("text"))]


def takes_stopped(mark):
    """`{take: seconds}` from `🎙️ local recording stopped`."""
    return {int(t): float(s) for s, t in re.findall(STOPPED, log_since(mark))}


def covers_take(toks, seconds):
    """The delivered pieces are one take whole: one `wav`, or chunks then one tail, numbered up,
    adding up to the recording (±0.5 s). (ok, why)"""
    kinds = [k for _, k, _, _ in toks]
    total = sum(s for _, _, s, _ in toks)
    shape = kinds == ["wav"] or (len(kinds) >= 2 and kinds[-1] == "tail" and set(kinds[:-1]) == {"chunk"})
    ordered = [n for n, _, _, _ in toks] == sorted(n for n, _, _, _ in toks)
    near = seconds is not None and abs(total - seconds) <= 0.5
    return (shape and ordered and near,
            f"pieces {kinds} = {total:.2f} s against the {seconds} s recording (shape {shape}, in order {ordered})")


def tmp_chunks():
    d = subprocess.run(["getconf", "DARWIN_USER_TEMP_DIR"], capture_output=True, text=True).stdout.strip()
    return set(glob.glob(os.path.join(d or "/tmp", "walkie-chunk-*.pcm")))


def pcm_left(epoch, before):
    """Chunk files the app wrote and did not remove: the fake's paths still on disk, plus any new
    `walkie-chunk-*.pcm` in the app's temp folder."""
    paths = {r["path"] for r in FW.requests(epoch) if r.get("kind") in ("chunk", "tail")}
    return sorted({p for p in paths if p and os.path.exists(p)} | (tmp_chunks() - before))


def recoverable_after(t0):
    rec = state().get("recoverable") or {}
    at = None
    try:
        import datetime
        at = datetime.datetime.fromisoformat(str(rec.get("expiresAt")).replace("Z", "+00:00")).timestamp() - 300
    except Exception:
        pass
    ok = rec.get("path") and os.path.exists(rec["path"]) and at is not None and at >= t0 - 0.5
    return (rec if ok else None)


def wait_requests(epoch, pred, timeout):
    return wait_for(lambda: [r for r in FW.requests(epoch) if pred(r)], timeout, 0.1)


def delivered_since(t_iso):
    d = state().get("lastDelivery") or {}
    return d if d.get("at", "") >= t_iso else None


def settle(timeout=None):
    return wait_for(lambda: not relay_busy(), timeout or tmo("terminal"), 0.3)


# ================================================================ C1
@case("C1", TAGS, covers=_COV,
      expect="a 42 s take is cut while he speaks (≥ 2 `✂️ … cut` lines, every chunk asked before the stop); "
             "the tail asked with the chunks' language, nothing asks `words`; delivered = the chunk answers + the "
             "tail in order, one take whole (±0.5 s); `assembled from N piece(s)`; busy clears")
def c1():
    """Chunks cut while recording, joined in order."""
    why = _pre()
    if why: return "SKIP", why
    with rig():
        ep = FW.arm(language="en")
        n0 = outbox_count()
        m = start()
        if not m: return "FAIL", "the microphone never opened"
        if not on_inject(m): stop(); return not_inject(m)
        say(take_wav(4))
        t_stop = stop()
        rows = wait_for(lambda: rows_since(n0), tmo("terminal"), 0.3) or []
        settled = settle()
        reqs = FW.requests(ep)
        cuts = count(m, CUT)
        chunks = [r for r in reqs if r["kind"] == "chunk"]
        tails = [r for r in reqs if r["kind"] == "tail"]
        wavs = [r for r in reqs if r["kind"] == "wav"]
        early = all(r["t"] < (t_stop or 0) for r in chunks)
        got = tokens(rows[0].get("text")) if rows else []
        want = answered_tokens(ep)
        whole, why_cov = covers_take(got, next(iter(takes_stopped(m).values()), None))
        asm = re.search(ASSEMBLED, log_since(m))
        no_words = not any(r["words"] for r in reqs)
        tail_lang = len(tails) == 1 and tails[0]["language"] == "en" and all(r["language"] is None for r in chunks)
        note = (f"{cuts} cut line(s), requests {[r['kind'] for r in reqs]} (chunks asked before the stop: {early}); "
                f"tail language {[r['language'] for r in tails]}, words asked {[r['words'] for r in reqs]}; "
                f"delivered {len(rows)} row(s), tokens {[t[0] for t in got]} vs answered {[t[0] for t in want]}; "
                f"{why_cov}; assembled {asm.groups() if asm else None}; busy cleared {bool(settled)}; "
                f"live windows {len(FW.requests(ep, live=True)) - len(reqs)}")
        ok = (cuts >= 2 and len(chunks) == cuts and early and not wavs and tail_lang and no_words and len(rows) == 1
              and got == want and whole and asm and int(asm.group(2)) == cuts + 1 and settled)
        return ("PASS" if ok else "FAIL"), note


# ================================================================ C2
@case("C2", TAGS, covers=_COV,
      expect="POST /test/cancel while recording, chunk 1 still decoding (6 s): nothing delivered, the chunk's late "
             "answer dropped (no `answered` line), Recover holds the WAV, no walkie-chunk .pcm left, busy clears")
def c2():
    """Cancel mid-take with a chunk in flight."""
    why = _pre()
    if why: return "SKIP", why
    th = None
    with rig():
        ep = FW.arm(rules=[{"kind": "chunk", "nth": 1, "delay": 6}])
        before = tmp_chunks()
        n0, t0, t0_iso = outbox_count(), time.time(), now_iso()
        m = start()
        if not m: return "FAIL", "the microphone never opened"
        if not on_inject(m): stop(); return not_inject(m)
        th = play_bg(take_wav(3), lead=0.4)
        try:
            inflight = wait_requests(ep, lambda r: r["kind"] == "chunk", 9.5 + 1.4 + tmo(2))
            time.sleep(0.5)
            post("/test/cancel")
            stopped = wait_for(lambda: not state().get("isRecording"), tmo(2), 0.1)
            time.sleep(6 + 1.0)                                  # the chunk's answer comes and must be dropped
            answered = wait_for(lambda: [a for a in FW.answers(ep) if a.get("nth") == 1 and a["kind"] == "chunk"], 3, 0.2)
            settled = settle()
            rec = recoverable_after(t0)
            rows = rows_since(n0)
            left = pcm_left(ep, before)
            dropped = not log_has(m, r"✂️ local: chunk 1 of take \d+ answered")
            note = (f"chunk in flight {bool(inflight)}, mic shut {bool(stopped)}, fake answered it {bool(answered)}, "
                    f"answer dropped {dropped}; delivered rows {len(rows)}, lastDelivery after {delivered_since(t0_iso)}; "
                    f"recoverable {rec}; .pcm left {left}; busy cleared {bool(settled)}")
            ok = inflight and stopped and answered and dropped and not rows and not delivered_since(t0_iso) and rec \
                and not left and settled
            return ("PASS" if ok else "FAIL"), note
        finally:
            if th: th.join(40)


# ================================================================ C3
@case("C3", TAGS, covers=_COV,
      expect="POST /test/cancel after the stop while the tail decodes (10 s): nothing delivered, the tail's answer "
             "dropped, Recover holds the whole WAV (± 1 s of the recording), busy clears")
def c3():
    """Cancel during the settle, the tail decoding."""
    why = _pre()
    if why: return "SKIP", why
    with rig():
        ep = FW.arm(rules=[{"kind": "tail", "delay": 10}])
        before = tmp_chunks()
        n0, t0, t0_iso = outbox_count(), time.time(), now_iso()
        m = start()
        if not m: return "FAIL", "the microphone never opened"
        if not on_inject(m): stop(); return not_inject(m)
        say(take_wav(3))
        stop()
        tail = wait_requests(ep, lambda r: r["kind"] == "tail", tmo("local"))
        post("/test/cancel")
        time.sleep(10 + 1.0)                                     # the tail's answer arrives and must go nowhere
        settled = settle()
        rec = recoverable_after(t0)
        dur = next(iter(takes_stopped(m).values()), None)
        rows = rows_since(n0)
        note = (f"tail asked {bool(tail)}, cuts {count(m, CUT)}; delivered rows {len(rows)}, "
                f"lastDelivery after {delivered_since(t0_iso)}; recording {dur} s, recoverable {rec}; "
                f".pcm left {pcm_left(ep, before)}; busy cleared {bool(settled)}")
        ok = (tail and not rows and not delivered_since(t0_iso) and rec and dur
              and abs(float(rec.get("duration") or 0) - dur) <= 1.0 and settled and not pcm_left(ep, before))
        return ("PASS" if ok else "FAIL"), note


# ================================================================ C4
@case("C4", TAGS, covers=_COV,
      expect="A (31 s, chunked, tail 14 s slow) stopped; 📻 readyForNext comes up 0.8–1.4 s after; B starts at +1.5 s "
             "(state.sentences = 2), 6 s, stopped; a third start is refused (`two sentences … in flight`, no mic); "
             "delivered A then B; B's wav reached the helper only after A's tail answered")
def c4():
    """The queue behind a chunked take."""
    why = _pre()
    if why: return "SKIP", why
    with rig():
        ep = FW.arm(rules=[{"kind": "tail", "delay": 14}])
        n0 = outbox_count()
        m = start()
        if not m: return "FAIL", "A's microphone never opened"
        if not on_inject(m): stop(); return not_inject(m)
        say(take_wav(3, offset=40))
        t_a = stop()
        ready_at = None
        while time.time() - t_a < 1.45:
            if state().get("readyForNext") and ready_at is None:
                ready_at = time.time() - t_a
            time.sleep(0.05)
        time.sleep(max(0, 1.5 - (time.time() - t_a)))
        mb = start()
        listed = len(state().get("sentences") or [])
        if not mb: return "FAIL", f"B's microphone never opened (ready at {ready_at})"
        say(CLIP_SPEECH, seconds=6)
        t_b = stop()
        time.sleep(1.2)
        opened = count(m, OPENED)
        post("/test/gesture", {"name": "forward-right", "direct": True})
        refused = wait_for(lambda: log_has(m, REFUSED), 3, 0.05)
        time.sleep(1.0)
        third = count(m, OPENED) > opened
        both = wait_for(lambda: len(rows_since(n0)) >= 2, 14 + tmo("terminal"), 0.3)
        settle()
        rows = rows_since(n0)
        order = [("B" if [k for _, k, _, _ in tokens(r.get("text"))] == ["wav"] else "A") for r in rows]
        reqs, ans = FW.requests(ep), FW.answers(ep)
        tail_done = next((a["t"] for a in ans if a["kind"] == "tail"), None)
        b_req = next((r["t"] for r in reqs if r["kind"] == "wav"), None)
        waited = tail_done is not None and b_req is not None and b_req >= tail_done
        note = (f"readyForNext at +{ready_at and round(ready_at, 2)} s; sentences listed with B open {listed}; "
                f"third start refused {bool(refused)}, third mic {third}; delivered order {order}; "
                f"B's wav asked {b_req and round(b_req - t_a, 1)} s after A's stop, A's tail answered "
                f"{tail_done and round(tail_done - t_a, 1)} s after (B waited {waited})")
        ok = (ready_at is not None and 0.7 <= ready_at <= 1.45 and listed == 2 and refused and not third and both
              and order[:2] == ["A", "B"] and waited)
        return ("PASS" if ok else "FAIL"), note


# ================================================================ C5
@case("C5", TAGS, covers=_COV,
      expect="A (chunked, tail 12 s slow) stopped, B (4 s) recorded and stopped, then POST /test/cancel → the newest "
             "in flight (B) cancelled: A delivered alone, Recover holds B's WAV (< 8 s), B's late answer dropped")
def c5():
    """Cancel B while A still decodes."""
    why = _pre()
    if why: return "SKIP", why
    with rig():
        ep = FW.arm(rules=[{"kind": "tail", "delay": 12}])
        n0, t0 = outbox_count(), time.time()
        m = start()
        if not m: return "FAIL", "A's microphone never opened"
        if not on_inject(m): stop(); return not_inject(m)
        say(take_wav(3, offset=60))
        t_a = stop()
        time.sleep(1.5)
        if not start(): return "FAIL", "B's microphone never opened"
        say(CLIP_SPEECH, seconds=4)
        stop()
        time.sleep(1.0)
        post("/test/cancel")
        cancelled = wait_for(lambda: log_has(m, r"dictation cancelled|🗑️"), 3, 0.05)
        one = wait_for(lambda: rows_since(n0), 12 + tmo("terminal"), 0.3)
        time.sleep(5.0)                                          # B's answer, if it were delivered, is in by now
        settle()
        rows = rows_since(n0)
        kinds = [[k for _, k, _, _ in tokens(r.get("text"))] for r in rows]
        rec = recoverable_after(t0)
        a_whole = len(rows) == 1 and kinds[0] and kinds[0][-1] == "tail"
        note = (f"cancel line {bool(cancelled)}; delivered {kinds}; recoverable {rec}; "
                f"B's late answer dropped {log_has(m, r'answered a cancelled decode — dropped')}; "
                f"requests {[r['kind'] for r in FW.requests(ep)]}")
        ok = one and a_whole and rec and float(rec.get("duration") or 99) < 8
        return ("PASS" if ok else "FAIL"), note


# ================================================================ C6
@case("C6", TAGS, covers=_COV,
      expect="chunk 1 answered ok:false → `a chunk of take … got no answer — decoding the whole take`, a `wav` request "
             "after the tail, delivered = that wav's answer alone, the whole recording")
def c6():
    """A failed chunk falls back to the whole WAV."""
    why = _pre()
    if why: return "SKIP", why
    with rig():
        ep = FW.arm(rules=[{"kind": "chunk", "nth": 1, "fail": "fake chunk failure"}])
        n0 = outbox_count()
        m = start()
        if not m: return "FAIL", "the microphone never opened"
        if not on_inject(m): stop(); return not_inject(m)
        say(take_wav(3, offset=10))
        stop()
        rows = wait_for(lambda: rows_since(n0), tmo("terminal") + tmo("local"), 0.3) or []
        settle()
        reqs = FW.requests(ep)
        got = tokens(rows[0].get("text")) if rows else []
        whole, why_cov = covers_take(got, next(iter(takes_stopped(m).values()), None))
        note = (f"requests {[r['kind'] for r in reqs]}; whole-take line {log_has(m, WHOLE)}; delivered {len(rows)} "
                f"row(s) {[t[1] for t in got]}; {why_cov}")
        ok = log_has(m, WHOLE) and reqs and reqs[-1]["kind"] == "wav" and len(rows) == 1 and whole and \
            [t[1] for t in got] == ["wav"]
        return ("PASS" if ok else "FAIL"), note


# ================================================================ C7
@case("C7", TAGS, covers=_COV,
      expect="the helper exits 0.5 s into chunk 1 → a new helper (second pid, `local model ready`), the whole take "
             "decoded once the model is up, delivered, nothing staged for Recover (1b789d9)")
def c7():
    """The helper dies mid-chunk."""
    why = _pre()
    if why: return "SKIP", why
    with rig():
        ep = FW.arm(rules=[{"kind": "chunk", "nth": 1, "delay": 0.5, "die": 1}])
        n0, t0 = outbox_count(), time.time()
        m = start()
        if not m: return "FAIL", "the microphone never opened"
        if not on_inject(m): stop(); return not_inject(m)
        say(take_wav(3, offset=10))
        stop()
        rows = wait_for(lambda: rows_since(n0), tmo("terminal") + tmo("local"), 0.3) or []
        settle()
        lines = FW.log_lines(ep)
        died = [l for l in lines if l.get("event") == "die"]
        pids = [l["pid"] for l in lines if l.get("event") == "hello"]
        reqs = FW.requests(ep)
        got = tokens(rows[0].get("text")) if rows else []
        whole, why_cov = covers_take(got, next(iter(takes_stopped(m).values()), None))
        note = (f"died {len(died)}, hellos (sentence + live helpers) {len(pids)}, `local model ready` lines "
                f"{count(m, MODEL_READY)}; requests {[(r['kind'], r['pid']) for r in reqs]}; delivered {len(rows)} "
                f"{[t[1] for t in got]}; {why_cov}; recoverable {recoverable_after(t0)}")
        ok = died and count(m, MODEL_READY) >= 1 and len({r["pid"] for r in reqs}) >= 2 and len(rows) == 1 \
            and whole and [t[1] for t in got] == ["wav"] and not recoverable_after(t0)
        return ("PASS" if ok else "FAIL"), note


# ================================================================ C8
SEL = "CHUNK-CUE-SELECTION-42"


@case("C8", TAGS, covers=_COV,
      expect="POST /test/selection after chunk 1 was cut: chunk 1 asked without `words`, every later chunk and the tail "
             "with them (or, a marker spliced into the WAV, one whole `wav` with them); the highlight inline or in the "
             "footer; every answered token delivered, in order")
def c8():
    """A cue mid-take turns the word timings on for what follows."""
    why = _pre()
    if why: return "SKIP", why
    th = None
    with rig():
        ep = FW.arm()
        n0 = outbox_count()
        m = start()
        if not m: return "FAIL", "the microphone never opened"
        if not on_inject(m): stop(); return not_inject(m)
        th = play_bg(take_wav(3, offset=20), lead=0.4)
        try:
            first = wait_requests(ep, lambda r: r["kind"] == "chunk", 9.5 + 1.4 + tmo(2))
            code, sel = post("/test/selection", {"text": SEL})
            t_sel = time.time()
        finally:
            th.join(40)
        time.sleep(0.15)
        stop()
        rows = wait_for(lambda: rows_since(n0), tmo("terminal"), 0.3) or []
        settle()
        reqs = FW.requests(ep)
        spliced = log_has(m, r"the chunks are let go — a marker was spliced")
        before = [r["words"] for r in reqs if r["t"] < t_sel]
        after = [r["words"] for r in reqs if r["t"] >= t_sel]
        text = rows[0].get("text") if rows else ""
        got, want = tokens(text), answered_tokens(ep)
        if spliced:
            want = [t for t in want if t[1] == "wav"]
        inline = bool(re.search(r'\[selected: "' + SEL, text))
        shown = SEL in text or SEL in str((rows[0] if rows else {}).get("selection") or "")
        note = (f"selection → {code} {sel}; words before the cue {before}, after {after}; spliced {spliced}; "
                f"delivered tokens {[t[0] for t in got]} vs answered {[t[0] for t in want]}; highlight shown {shown} "
                f"(inline in the words {inline}, selectionAt {(rows[0] if rows else {}).get('selectionAt')})")
        ok = (code == 200 and first and before and not any(before) and after and all(after) and len(rows) == 1
              and got == want and shown)
        return ("PASS" if ok else "FAIL"), note


# ================================================================ C9
def _one_delivery(n0, m, ep, wait_extra):
    """(ok, note) — exactly one row for the take, its pieces one take whole."""
    rows = wait_for(lambda: rows_since(n0), tmo("terminal") + wait_extra, 0.3) or []
    time.sleep(5.0)                                              # a second copy, if any, is in by now
    settle()
    rows = rows_since(n0)
    got = tokens(rows[0].get("text")) if rows else []
    whole, why_cov = covers_take(got, next(iter(takes_stopped(m).values()), None))
    known = set(answered_tokens(ep))
    return (len(rows) == 1 and whole and set(got) <= known,
            f"{len(rows)} row(s) via {[(r.get('delivery') or {}).get('via') for r in rows]}, {why_cov}, all from the fake {set(got) <= known}")


@case("C9", TAGS, covers=_COV,
      expect="⌘⌃X (POST /test/local-now) after chunk 1 while recording, and again while a slow tail (5 s) decodes: "
             "whatever the local engine does with it, each take is delivered exactly once, whole")
def c9():
    """⌘⌃X on the local engine mid-take and mid-settle."""
    why = _pre()
    if why: return "SKIP", why
    notes, oks = [], []
    with rig():
        # (a) while recording
        ep = FW.arm()
        n0 = outbox_count()
        m = start()
        if not m: return "FAIL", "the microphone never opened (a)"
        if not on_inject(m): stop(); return not_inject(m)
        th = play_bg(take_wav(3, offset=40), lead=0.4)
        try:
            wait_requests(ep, lambda r: r["kind"] == "chunk", 9.5 + 1.4 + tmo(2))
            post("/test/local-now")
        finally:
            th.join(40)
        time.sleep(0.15)
        stop()
        ok, note = _one_delivery(n0, m, ep, tmo("local"))
        oks.append(ok); notes.append(f"(a) recording: {note}; requests {[r['kind'] for r in FW.requests(ep)]}")
        settle()
        # (b) while the tail decodes
        ep = FW.arm(rules=[{"kind": "tail", "delay": 5}])
        n0 = outbox_count()
        m = start()
        if not m: return "FAIL", "the microphone never opened (b); " + "; ".join(notes)
        say(take_wav(3, offset=20))
        stop()
        wait_requests(ep, lambda r: r["kind"] == "tail", tmo("local"))
        post("/test/local-now")
        ok, note = _one_delivery(n0, m, ep, 5 + tmo("local"))
        oks.append(ok); notes.append(f"(b) settling: {note}; requests {[r['kind'] for r in FW.requests(ep)]}")
    return ("PASS" if all(oks) else "FAIL"), " · ".join(notes)


# ================================================================ C10
@case("C10", TAGS, covers=_COV,
      expect="POST /engine {\"id\": \"eleven\"} after chunk 1 while recording, and while a slow tail (6 s) decodes: "
             "refused both times (the answer still says whisper), each take delivered once, whole")
def c10():
    """An engine switch with a chunked take in flight."""
    why = _pre()
    if why: return "SKIP", why
    notes, oks = [], []
    fake_env(True)                                               # an accepted switch must reach the fake Scribe only
    try:
        with rig():
            for phase in ("recording", "settling"):
                ep = FW.arm(rules=[{"kind": "tail", "delay": 6}] if phase == "settling" else [])
                n0 = outbox_count()
                m = start()
                if not m: return "FAIL", f"the microphone never opened ({phase})"
                if not on_inject(m): stop(); return not_inject(m)
                if phase == "recording":
                    th = play_bg(take_wav(3, offset=30), lead=0.4)
                    try:
                        wait_requests(ep, lambda r: r["kind"] == "chunk", 9.5 + 1.4 + tmo(2))
                        _, ans = post("/engine", {"id": "eleven"})
                    finally:
                        th.join(40)
                    time.sleep(0.15)
                    stop()
                else:
                    say(take_wav(3, offset=60))
                    stop()
                    wait_requests(ep, lambda r: r["kind"] == "tail", tmo("local"))
                    _, ans = post("/engine", {"id": "eleven"})
                time.sleep(0.5)                                  # the pick lands on main after the answer
                kept = (ans or {}).get("engine") == LOCAL_ENGINE and engine().get("engine") == LOCAL_ENGINE
                ok, note = _one_delivery(n0, m, ep, 6 + tmo("local"))
                oks.append(ok and kept)
                notes.append(f"({phase}) /engine answered {ans.get('engine') if ans else None} "
                             f"{('— ' + str(ans.get('error') or ans.get('refused') or '')) if ans else ''}; {note}")
                if engine().get("engine") != LOCAL_ENGINE:
                    set_engine(LOCAL_ENGINE)
    finally:
        fake_env(False)
    return ("PASS" if all(oks) else "FAIL"), " · ".join(notes)


# ================================================================ C11
@case("C11", TAGS, covers=_COV,
      expect="a 6 s take is never cut: no `✂️ … cut` line, exactly one `wav` request (no chunk, no tail), delivered "
             "= its answer, the whole recording")
def c11():
    """A short take is decoded whole."""
    why = _pre()
    if why: return "SKIP", why
    with rig():
        ep = FW.arm()
        n0 = outbox_count()
        m = start()
        if not m: return "FAIL", "the microphone never opened"
        if not on_inject(m): stop(); return not_inject(m)
        say(CLIP_SPEECH, seconds=6)
        stop()
        rows = wait_for(lambda: rows_since(n0), tmo("terminal"), 0.3) or []
        settle()
        reqs = FW.requests(ep)
        got = tokens(rows[0].get("text")) if rows else []
        whole, why_cov = covers_take(got, next(iter(takes_stopped(m).values()), None))
        note = f"cuts {count(m, CUT)}; requests {[r['kind'] for r in reqs]}; delivered {len(rows)}; {why_cov}"
        ok = count(m, CUT) == 0 and [r["kind"] for r in reqs] == ["wav"] and len(rows) == 1 and whole
        return ("PASS" if ok else "FAIL"), note


# ================================================================ C12
def _dry_run():
    """`relay-restart.sh --dry-run --max-wait 4` — read-only: it waits on the gate and touches nothing.
    The harness's own runner lock does not hold it (the gate ignores an ancestor's lock)."""
    try:
        r = subprocess.run([os.path.join(REPO, "relay-restart.sh"), "--dry-run", "--max-wait", "4"],
                           capture_output=True, text=True, timeout=40, cwd=REPO)
        tail = (r.stdout + r.stderr).strip().splitlines()[-1:] or [""]
        return r.returncode, tail[0][:160]
    except Exception as e:
        return None, f"{type(e).__name__}: {e}"


@case("C12", TAGS + ("restart",), covers=_COV,
      expect="`relay-restart.sh --dry-run --max-wait 4` exits 3 (gave up waiting) with a chunk of a recording take in "
             "flight, and again while its tail decodes (10 s); state.busyWhy names the sentence; nothing restarts "
             "(same pid after)")
def c12():
    """The restart gate holds while chunks are pending."""
    why = _pre()
    if why: return "SKIP", why
    pid0 = state().get("pid")
    with rig():
        ep = FW.arm(rules=[{"kind": "chunk", "nth": 1, "delay": 8}, {"kind": "tail", "delay": 10}])
        n0 = outbox_count()
        m = start()
        if not m: return "FAIL", "the microphone never opened"
        if not on_inject(m): stop(); return not_inject(m)
        th = play_bg(take_wav(3, offset=30), lead=0.4)
        try:
            wait_requests(ep, lambda r: r["kind"] == "chunk", 9.5 + 1.4 + tmo(2))
            busy1 = busy_why()
            rc1, out1 = _dry_run()
        finally:
            th.join(40)
        time.sleep(0.15)
        stop()
        wait_requests(ep, lambda r: r["kind"] == "tail", tmo("local") + 8)
        busy2 = busy_why()
        rc2, out2 = _dry_run()
        rows = wait_for(lambda: rows_since(n0), 10 + tmo("terminal"), 0.3)
        settle()
        pid1 = state().get("pid")
        note = (f"recording: exit {rc1} «{out1}», busyWhy {busy1}; tail decoding: exit {rc2} «{out2}», busyWhy {busy2}; "
                f"delivered {bool(rows)}; pid {pid0} → {pid1}")
        ok = rc1 == 3 and rc2 == 3 and busy1 and busy2 and rows and pid0 == pid1
        return ("PASS" if ok else "FAIL"), note
