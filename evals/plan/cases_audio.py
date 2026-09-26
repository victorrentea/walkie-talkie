"""Real audio through our Loopback device "🧪 WT Inject" (docs/test-plan.md §6.2, G1), with faults
from the ElevenLabs switch (`POST /test/eleven`, G3) and the local helper on demand
(`POST /test/whisper`, G4): §7.1 T-L 8–14, 16, 25, 29, 30, 32 · §7.3 T-R 9–15, 23–25 · §7.4 LC13
and the live-socket cases B1–B5.

Every case: `loopback_alive()` or SKIP; the recorder overridden onto the Loopback and a witness tab
bound (so nothing lands at the caret); both undone in a `finally`, faults cleared, SIGCONT sent to
the helper where it was stopped. Nothing here pulls cables, sleeps the Mac, kills the app or
touches Wispr."""
import contextlib, os, re, threading, time
from harness import *

INJECT = LOOPBACK.replace("🧪 ", "")  # the substring /test/mic matches; "WT Inject" on the host, "BlackHole 2ch" in the lab                  # mic_override substring of LOOPBACK ("🧪 WT Inject")
EL = ("eleven", "eleven-live")
LIVE = ("eleven-live",)
END = (r"📦 delivery:|dictation abandoned|returned no words|No words detected|"
       r"could not transcribe it either|the recogniser could not be reached")
FALLBACK = r"↪️ .*on this Mac instead"
CORR_START = r"💬 live correction: ([\d.]+)s since the last cut"
CORR_DONE = r"💬 live correction: \d+ → \d+ chars"


# ---------------------------------------------------------------- helpers
def _quiet(fn, *a, **k):
    try:
        return fn(*a, **k)
    except Exception:
        return None

def pre(engines=EL):
    """None when the rig is usable, else the SKIP reason."""
    try:
        if not loopback_alive():
            return f"{LOOPBACK} pass-thru is dead (440 Hz check) — toggle the device in Loopback"
    except Exception as e:
        return f"{LOOPBACK} check failed: {type(e).__name__}: {e}"
    eng = engine().get("engine")
    if engines and eng not in engines:
        return f"engine is {eng}, the case needs {'/'.join(engines)}"
    return None

@contextlib.contextmanager
def rig():
    """Recorder on the Loopback, witness bound; everything undone on the way out."""
    mic_override(INJECT)
    try:
        bind_witness()
        witness_clear()
        yield
    finally:
        _quiet(post, "/test/eleven", {"clear": True})
        _quiet(wait_for, lambda: not state()["busy"], 30, 0.5)
        _quiet(mic_override, None)
        _quiet(unbind)

@contextlib.contextmanager
def engine_as(eid):
    """Switch the engine for one case and put it back (after the relay is idle)."""
    e0 = engine()["engine"]
    try:
        if e0 != eid:
            post("/engine", {"id": eid})
        yield e0
    finally:
        _quiet(wait_for, lambda: not state()["busy"], 60, 0.5)
        if _quiet(lambda: engine()["engine"]) != e0:
            _quiet(post, "/engine", {"id": e0})

def when(mark, pattern, timeout, step=0.05):
    """Wall-clock time the pattern first shows in the log after `mark`, or None."""
    return wait_for(lambda: time.time() if log_has(mark, pattern) else None, timeout, step)

def delivered(mark, timeout=120):
    return when(mark, END, timeout, 0.2)

def count(mark, pattern):
    return len(re.findall(pattern, log_since(mark)))

def mic_device(mark):
    m = re.search(r"mic: recording through ([^\n]+)", log_since(mark))
    return m.group(1).strip() if m else ""

def on_inject(mark):
    return INJECT.lower() in mic_device(mark).lower()

def start(mark=None):
    """F10 and wait for the microphone; returns the mark. Raises if it never opens."""
    mark = log_mark() if mark is None else mark
    gesture("forward-right")
    if not wait_for(lambda: log_has(mark, r"mic: recording through"), 8):
        post("/test/cancel")
        raise RuntimeError("the microphone never opened")
    return mark

def stop():
    """F10 only while our sentence is still listening — otherwise the chord would start a new one."""
    if state()["listening"]:
        gesture("forward-right")
    else:
        post("/test/cancel")

def play_async(wav, **kw):
    th = threading.Thread(target=play, args=(wav,), kwargs=kw, daemon=True)
    th.start()
    return th

def last_delivery(since_iso):
    d = state().get("lastDelivery") or None
    return d if d and d.get("at", "") >= since_iso else None

def settle_out(timeout=60):
    return wait_for(lambda: not state()["busy"], timeout, 0.5)

def helper():
    return state().get("whisper") or {}

def not_inject(mark):
    return "FAIL", f"the recorder opened {mic_device(mark)!r}, not {LOOPBACK}"


# ================================================================ §7.1 T-L
@case("TL8", ("audio", "gesture", "slow"),
      expect="R1: upload > settle ceiling, S2 starts, S1's late reply lands → today: 'dictation abandoned (a new dictation started)', S1's outbox has S2's screen, listening false with isRecording true")
def tl8():
    """R1 — a slow upload outlives the settle; the next sentence starts under it."""
    why = pre()
    if why: return "SKIP", why
    with rig():
        # the fake answers 500 at 34 s, the retry is real: an upload of ~36 s standing in for the throttle
        post("/test/eleven", {"fail": "500", "delayMs": 34000})
        m1, _ = dictate_loopback(CLIP_EN, wait_after=1.0)
        if not on_inject(m1): return not_inject(m1)
        t_stop = when(m1, r"recording stopped", 10) or time.time()
        if not wait_for(lambda: not state()["settling"], 45, 0.25):
            return "FAIL", "the settle never ended in 45 s"
        s = state()
        gave_up = time.time() - t_stop
        n0 = outbox_count()
        m2 = start()
        post("/test/area", {"x": 200, "y": 200, "w": 400, "h": 300})
        th = play_async(CLIP_EN_LONG, seconds=5)
        flips = []
        end = time.time() + 10
        while time.time() < end:
            x = state()
            if x["isRecording"] and not x["listening"]:
                flips.append(round(time.time() - t_stop, 1))
            time.sleep(0.2)
        th.join()
        ms2 = log_mark()
        stop()
        delivered(ms2, 120)
        settle_out(60)
        log2 = log_since(m2)
        abandoned = re.search(r"dictation abandoned \(a new dictation started\)", log2)
        new = outbox_tail(max(0, outbox_count() - n0)) if outbox_count() > n0 else []
        s1 = [o for o in new if "dictat" in o.get("text", "").lower()]
        s2 = [o for o in new if o not in s1]
        d1 = os.path.dirname(s1[0].get("screen", "")) if s1 else None
        d2 = os.path.dirname(s2[0].get("screen", "")) if s2 else None
        ring2 = count(ms2, r"⚡ ring down")
        note = (f"settle ended {gave_up:.1f} s after stop (phaseStatus {s['phaseStatus']!r}, busy {s['busy']}); "
                f"abandoned line {bool(abandoned)}; listening:false+isRecording:true at {flips[:3]}; "
                f"S1 lines {len(s1)} S2 lines {len(s2)}, same screen dir {d1 is not None and d1 == d2}; ring down after S2 stop {ring2}")
        if abandoned or flips or (d1 and d1 == d2):
            return "BUG", note
        if s1 and s2 and not flips:
            return "PASS", note
        return "FAIL", note


@case("TL9", ("audio", "gesture", "slow"),
      expect="R3: engine switched to whisper after the settle gave up mid-upload → today 'elevenlabs: … chars' with no outbox line (transcript lost)")
def tl9():
    """R3 — an engine switch after the settle expired drops the late transcript."""
    why = pre()
    if why: return "SKIP", why
    with rig(), engine_as(engine()["engine"]) as e0:
        post("/test/eleven", {"fail": "500", "delayMs": 34000})
        m1, _ = dictate_loopback(CLIP_EN, wait_after=1.0)
        if not on_inject(m1): return not_inject(m1)
        if not wait_for(lambda: not state()["settling"], 45, 0.25):
            return "FAIL", "the settle never ended in 45 s"
        busy = state()["busy"]
        n0 = outbox_count()
        ms = log_mark()
        code, r = post("/engine", {"id": "whisper"})
        accepted = r.get("engine") == "whisper"
        late = when(ms, r"elevenlabs: .* chars in", 20)
        time.sleep(3)
        got = log_has(ms, r"📦 delivery:")
        n1 = outbox_count()
        note = f"POST /engine whisper → {code}, engine now {r.get('engine')}; busy while uploading {busy}; late reply logged {bool(late)}; delivery {got}; outbox +{n1 - n0}"
        if not accepted:
            return "PASS", note + " (the switch was refused mid-upload)"
        if late and not got and n1 == n0:
            return "BUG", note
        if got:
            return "PASS", note
        return "FAIL", note


@case("TL10", ("audio", "gesture"),
      expect="R2: cancel during the upload → no delivery, WAV in cancelled/ (today: delivered after 'Cancelled')")
def tl10():
    """R2 — cancel while the upload is in flight."""
    why = pre()
    if why: return "SKIP", why
    with rig():
        post("/test/eleven", {"fail": "500", "delayMs": 8000})   # ~9 s upload, then the real answer
        m, _ = dictate_loopback(CLIP_EN, wait_after=1.0)
        if not on_inject(m): return not_inject(m)
        when(m, r"recording stopped", 10)
        time.sleep(1.5)
        ph = state()["phaseStatus"]
        mc = log_mark()
        post("/test/cancel")
        time.sleep(15)
        late = log_has(mc, r"📦 delivery:|words landed")
        kept = log_has(mc, r"of audio kept")
        rec = state()["recoverable"]
        note = f"phase at cancel {ph!r}; after cancel: delivery {late}, 'audio kept' {kept}, recoverable {bool(rec)}; witness {len(witness_text())} chars"
        if late:
            return "BUG", note
        if kept or rec:
            return "PASS", note
        return "FAIL", note


@case("TL11", ("audio", "gesture"),
      expect="R2 local (through the fallback, engine unchanged): helper SIGSTOP, stop, cancel, SIGCONT → today delivered after 'Cancelled'")
def tl11():
    """R2 on the local model — cancel while the helper is hung, then let it answer."""
    why = pre()
    if why: return "SKIP", why
    h = helper()
    if not (h.get("ready") and h.get("alive")):
        return "SKIP", f"local helper not up ({h})"
    with rig():
        post("/test/eleven", {"fail": "401"})
        post("/test/whisper", {"stop": True})
        try:
            m, _ = dictate_loopback(CLIP_EN, wait_after=1.0)
            if not on_inject(m): return not_inject(m)
            if not when(m, FALLBACK, 20):
                return "FAIL", "no fallback to the local model after the 401"
            time.sleep(1.0)
            mc = log_mark()
            post("/test/cancel")
            time.sleep(1.0)
            post("/test/whisper", {"cont": True})
            time.sleep(15)
        finally:
            post("/test/whisper", {"cont": True})
        late = log_has(mc, r"📦 delivery:|words landed")
        kept = log_has(mc, r"of audio kept")
        note = f"after cancel + SIGCONT: delivery {late}, 'audio kept' {kept}, recoverable {bool(state()['recoverable'])}"
        if late:
            return "BUG", note
        return ("PASS", note) if kept or state()["recoverable"] else ("FAIL", note)


@case("TL12", ("audio", "gesture"),
      expect="401 → 'HTTP 401', '↪️ … on this Mac instead', via local-fallback (no retry); next sentence back on ElevenLabs")
def tl12():
    """A bad key: the local model stands in, and the next sentence is ElevenLabs again."""
    why = pre()
    if why: return "SKIP", why
    with rig():
        t0 = now_iso()
        post("/test/eleven", {"fail": "401"})
        m, _ = dictate_loopback(CLIP_EN, wait_after=1.0)
        if not on_inject(m): return not_inject(m)
        t_stop = when(m, r"recording stopped", 10) or time.time()
        t_end = delivered(m, 120)
        settle_out(60)
        d1 = last_delivery(t0)
        retried = count(m, r"attempt 1 failed")
        has401 = log_has(m, r"HTTP 401")
        fb = log_has(m, FALLBACK)
        t1 = now_iso()
        m2, _ = dictate_loopback(CLIP_EN, wait_after=1.0)
        delivered(m2, 60)
        settle_out(60)
        d2 = last_delivery(t1)
        v1, v2 = (d1 or {}).get("via"), (d2 or {}).get("via")
        note = (f"401 {has401}, ↪️ {fb}, retries {retried}, via {v1} in {(t_end or time.time()) - t_stop:.1f} s; "
                f"next sentence via {v2}; the stale-warning half needs G5 (prompt state)")
        ok = has401 and fb and retried == 0 and v1 and "local" in v1 and v2 and "eleven" in v2
        return ("PASS" if ok else "FAIL"), note


@case("TL13", ("audio", "gesture"),
      expect="transport error retried once: 'attempt 1 failed … retrying', failure ≤ 2 s after stop, fallback delivers")
def tl13():
    """A transport error: one retry, then the local model, fast."""
    why = pre()
    if why: return "SKIP", why
    with rig():
        t0 = now_iso()
        post("/test/eleven", {"fail": "transportx2"})
        m, _ = dictate_loopback(CLIP_EN, wait_after=1.0)
        if not on_inject(m): return not_inject(m)
        t_stop = when(m, r"recording stopped", 10)
        t_fb = when(m, FALLBACK, 30)
        delivered(m, 120)
        settle_out(60)
        d = last_delivery(t0)
        n = count(m, r"attempt 1 failed .*retrying")
        dt = (t_fb - t_stop) if t_fb and t_stop else None
        note = f"retries {n}, failure → fallback {dt and round(dt, 2)} s after stop, via {(d or {}).get('via')}"
        ok = n == 1 and dt is not None and dt <= 2.0 and d and "local" in d.get("via", "")
        return ("PASS" if ok else "FAIL"), note


@case("TL14", ("audio", "gesture"),
      expect="blackhole (fake timeout after 20 s): failure at 20±1 s, no retry, 'still uploading — 8 s in', fallback delivers")
def tl14():
    """A hung connection: the 20 s timeout, never retried, then the local model."""
    why = pre()
    if why: return "SKIP", why
    with rig():
        t0 = now_iso()
        post("/test/eleven", {"fail": "timeout", "delayMs": 20000})
        m, _ = dictate_loopback(CLIP_EN, wait_after=1.0)
        if not on_inject(m): return not_inject(m)
        t_stop = when(m, r"recording stopped", 10)
        t_fb = when(m, FALLBACK, 40)
        delivered(m, 120)
        settle_out(60)
        d = last_delivery(t0)
        dt = (t_fb - t_stop) if t_fb and t_stop else None
        n = count(m, r"attempt 1 failed")
        still = log_has(m, r"still uploading — 8 s in")
        note = (f"failure {dt and round(dt, 1)} s after stop, retries {n}, 'still uploading — 8 s in' {still}, "
                f"via {(d or {}).get('via')} (the fake's delay, not URLSession's own timeout — G13 for that)")
        ok = dt is not None and 19 <= dt <= 21.5 and n == 0 and still and d and "local" in d.get("via", "")
        return ("PASS" if ok else "FAIL"), note


@case("TL16", ("audio", "gesture"),
      expect="3 s of silence → 'returned no words', no ↪️, nothing kept in cancelled/ (documents the loss, §3.8)")
def tl16():
    """An empty transcript: today the audio is deleted with no fallback."""
    why = pre()
    if why: return "SKIP", why
    with rig():
        rec0 = (state().get("recoverable") or {}).get("path")   # an earlier case's cancel stays 5 min
        m, _ = dictate_loopback(silence_wav(3), wait_after=0.5)
        if not on_inject(m): return not_inject(m)
        delivered(m, 60)
        settle_out(60)
        log = log_since(m)
        empty = bool(re.search(r"returned no words|No words detected", log))
        fb = bool(re.search(FALLBACK, log))
        kept = bool(re.search(r"of audio kept", log))
        rec = state()["recoverable"]
        if rec and rec.get("path") == rec0:
            rec = None
        words = bool(re.search(r"📦 delivery:", log))
        note = f"no-words line {empty}, ↪️ {fb}, audio kept {kept}, recoverable {bool(rec)}, delivered {words}"
        if empty and not fb and not kept and not rec:
            return "BUG", note + " — the audio is gone"
        if kept or rec:
            return "PASS", note
        return "FAIL", note


@case("TL25", ("audio", "gesture", "slow"),
      expect="10-min ceiling on real audio at 600±1 s; record `via` (the 20 s request timeout on a 19 MB WAV)")
def tl25():
    """The ten-minute ceiling on a real recording, and what a long upload does."""
    why = pre()
    if why: return "SKIP", why
    import sounddevice as sd
    with rig():
        t0i = now_iso()
        m = log_mark()
        gesture("forward-right")
        t0 = time.time()
        if not wait_for(lambda: log_has(m, r"mic: recording through"), 8):
            post("/test/cancel"); return "FAIL", "the microphone never opened"
        if not on_inject(m): return not_inject(m)
        stop_play = threading.Event()
        def loop():
            while not stop_play.is_set():
                play(CLIP_EN_LONG)
        th = threading.Thread(target=loop, daemon=True); th.start()
        t_c = when(m, r"⏱️ ten minutes", 640, 0.2)
        stop_play.set(); _quiet(sd.stop); th.join(5)
        if not t_c:
            return "FAIL", "no ceiling line within 640 s"
        t_end = delivered(m, 600)
        settle_out(120)
        d = last_delivery(t0i)
        up = re.search(r"elevenlabs: .*chars in ([\d.]+)s", log_since(m))
        note = (f"ceiling at {t_c - t0:.1f} s after the chord, delivered {t_end and round(t_end - t_c)} s later via {(d or {}).get('via')}; "
                f"ElevenLabs upload {up.group(1) + ' s' if up else 'failed/absent'}; fallback {log_has(m, FALLBACK)}")
        return ("PASS" if 599 <= t_c - t0 <= 601.5 and d else "FAIL"), note


@case("TL29", ("audio", "gesture"),
      expect="live socket drop mid-sentence (fault live:drop) → ≤ 1 'send failed' line (today ~11/s); batch still delivers")
def tl29():
    """The live socket drops: one error line, not one per buffer; the sentence still arrives."""
    why = pre(LIVE)
    if why: return "SKIP", why
    with rig():
        t0 = now_iso()
        post("/test/eleven", {"live": "drop"})
        m, _ = dictate_loopback(CLIP_EN_LONG, seconds=8, wait_after=0.5)
        if not on_inject(m): return not_inject(m)
        t_drop = when(m, r"live caption: drop", 3)
        delivered(m, 120)
        settle_out(60)
        n = count(m, r"live caption: send failed")
        d = last_delivery(t0)
        span = 9.0 - 1.0
        note = f"drop injected {bool(t_drop)}, {n} 'send failed' lines (~{n / span:.1f}/s over ~{span:.0f} s), batch via {(d or {}).get('via')}"
        if not t_drop:
            return "FAIL", note + " (the socket never opened, so the drop never fired)"
        if n > 5:
            return "BUG", note
        return ("PASS" if n <= 1 and d else "FAIL"), note


@case("TL30", ("audio", "gesture"),
      expect="live socket that never opens (live:never-open stands in for no key) → today: band open and empty the whole sentence, `pending` grows unbounded (§3.14, F13)")
def tl30():
    """A socket that never opens: the band sits open and empty, chunks pile up."""
    why = pre(LIVE)
    if why: return "SKIP", why
    with rig():
        t0 = now_iso()
        post("/test/eleven", {"live": "never-open"})
        m = start()
        if not on_inject(m): return not_inject(m)
        th = play_async(CLIP_EN_LONG, seconds=6)
        S = sample(7.0, hz=4, fn=state)
        th.join()
        stop()
        delivered(m, 120)
        settle_out(60)
        rec = [s for s in S if s["isRecording"]]
        opened = [s["liveCaption"]["open"] for s in rec]
        words = max((s["liveCaption"]["words"] for s in rec), default=0)
        pend = [((s.get("live") or {}).get("pending", 0)) for s in rec]
        sock = {(s.get("live") or {}).get("socket") for s in rec}
        d = last_delivery(t0)
        note = f"band open {sum(opened)}/{len(opened)} samples, max words {words}, socket {sock}, pending {pend[:1]} → {pend[-1:]}, batch via {(d or {}).get('via')}"
        if opened and all(opened) and words == 0 and pend and pend[-1] > pend[0] + 10:
            return "BUG", note
        if d and (not all(opened) or (pend and pend[-1] <= 64)):
            return "PASS", note
        return "FAIL", note


@case("TL32", ("audio", "gesture"),
      expect="normal cancel keeps the audio: 'N s of audio kept', one cancelled-*.wav")
def tl32():
    """A cancel mid-sentence stages the recording for Recover."""
    why = pre()
    if why: return "SKIP", why
    with rig():
        m, _ = dictate_loopback(CLIP_EN, wait_after=0.5, stop=False)
        if not on_inject(m): return not_inject(m)
        post("/test/cancel")
        t = when(m, r"of audio kept", 5)
        settle_out(30)
        rec = state()["recoverable"] or {}
        path = rec.get("path", "")
        exists = bool(path) and os.path.exists(path)
        kept = re.search(r"([\d.]+)s of audio kept", log_since(m))
        landed = log_has(m, r"📦 delivery:")
        note = f"'audio kept' {kept.group(1) + ' s' if kept else None}, recoverable {os.path.basename(path) or None} exists {exists}, delivered {landed}"
        ok = t and exists and "cancelled" in os.path.basename(path) and not landed
        return ("PASS" if ok else "FAIL"), note


# ================================================================ §7.3 T-R
@case("TR9", ("audio", "gesture"),
      expect="offline (transport ×2 + live drop) → ↪️, via local-fallback, no 'abandoned'")
def tr9():
    """Offline end to end: the local model delivers."""
    why = pre()
    if why: return "SKIP", why
    with rig():
        t0 = now_iso()
        post("/test/eleven", {"fail": "transportx2", "live": "drop"})
        m, _ = dictate_loopback(CLIP_EN, wait_after=1.0)
        if not on_inject(m): return not_inject(m)
        delivered(m, 120)
        settle_out(60)
        d = last_delivery(t0)
        fb, ab = log_has(m, FALLBACK), log_has(m, r"dictation abandoned")
        note = f"↪️ {fb}, abandoned {ab}, via {(d or {}).get('via')}, witness {len(witness_text())} chars"
        return ("PASS" if fb and not ab and d and "local" in d.get("via", "") else "FAIL"), note


@case("TR10", ("audio", "gesture", "slow"),
      expect="fallback with a cold model (helper SIGKILLed first) → delivered before fallbackCeiling (180 s)")
def tr10():
    """The fallback has to bring the local model up from nothing."""
    why = pre()
    if why: return "SKIP", why
    was_alive = bool(helper().get("alive"))
    with rig():
        t0 = now_iso()
        post("/test/whisper", {"kill": True})
        wait_for(lambda: not helper().get("alive"), 3, 0.1)
        post("/test/eleven", {"fail": "401"})
        m, _ = dictate_loopback(CLIP_EN, wait_after=1.0)
        if not on_inject(m): return not_inject(m)
        t_stop = when(m, r"recording stopped", 10) or time.time()
        t_end = delivered(m, 200)
        settle_out(60)
        d = last_delivery(t0)
        up = log_has(m, r"did not come up in 90 s")
        h = helper()
        note = f"delivered {t_end and round(t_end - t_stop, 1)} s after stop via {(d or {}).get('via')}, 'did not come up' {up}, helper now alive {h.get('alive')} pid {h.get('pid')}"
        if not was_alive:
            _quiet(post, "/test/whisper", {"kill": True})   # it was down when we came
        elif not h.get("alive"):
            _quiet(post, "/test/whisper", {"restart": True})  # it was up when we came: put it back
        ok = t_end and t_end - t_stop < 180 and d and "local" in d.get("via", "")
        return ("PASS" if ok else "FAIL"), note


@case("TR11", ("audio", "gesture", "slow"),
      expect="slow failure (transport after 19 s, twice) passes the 30 s settle ceiling → expected to fail today: the settle times out before the fallback")
def tr11():
    """A failure slower than the settle: 19 + 0.8 + 19 s > 30 s."""
    why = pre()
    if why: return "SKIP", why
    with rig():
        t0 = now_iso()
        post("/test/eleven", {"fail": "transportx2", "delayMs": 19000})
        m, _ = dictate_loopback(CLIP_EN, wait_after=1.0)
        if not on_inject(m): return not_inject(m)
        t_stop = when(m, r"recording stopped", 10) or time.time()
        t_to = when(m, r"timed out waiting for the text", 50, 0.2)
        t_fb = when(m, FALLBACK, 50, 0.2)
        t_end = delivered(m, 150)
        settle_out(60)
        d = last_delivery(t0)
        rel = lambda t: t and round(t - t_stop, 1)
        note = f"settle timed out at {rel(t_to)} s, ↪️ at {rel(t_fb)} s, end at {rel(t_end)} s, via {(d or {}).get('via')}, to {(d or {}).get('to')}"
        if t_to and (not t_fb or t_to < t_fb):
            return "BUG", note
        ok = t_fb and not t_to and d and "local" in d.get("via", "")
        return ("PASS" if ok else "FAIL"), note


@case("TR12", ("audio", "gesture", "slow"),
      expect="4xx not retried, 5xx/429 retried once: 'attempt 1 failed' 0/0/1/1 for 401/422/500/429, all end in the fallback")
def tr12():
    """Which failures earn a retry."""
    why = pre()
    if why: return "SKIP", why
    rows, ok = [], True
    with rig():
        for spec, want in (("401", 0), ("422", 0), ("500x2", 1), ("429x2", 1)):
            t0 = now_iso()
            post("/test/eleven", {"fail": spec})
            m, _ = dictate_loopback(CLIP_EN, wait_after=1.0)
            if not on_inject(m): return not_inject(m)
            delivered(m, 120)
            settle_out(60)
            n = count(m, r"attempt 1 failed")
            v = (last_delivery(t0) or {}).get("via")
            rows.append(f"{spec}: {n} retr{'y' if n == 1 else 'ies'}, via {v}")
            ok = ok and n == want and bool(v) and "local" in v
    return ("PASS" if ok else "FAIL"), "; ".join(rows)


@case("TR13", ("audio", "gesture"),
      expect="empty Scribe answer on 20 s of speech → WAV staged, Recover returns it (fails today: 'returned no words', audio deleted)")
def tr13():
    """An empty answer must not cost the recording."""
    why = pre()
    if why: return "SKIP", why
    with rig():
        rec0 = (state().get("recoverable") or {}).get("path")   # an earlier case's cancel stays 5 min
        post("/test/eleven", {"fail": "empty"})
        m, _ = dictate_loopback(CLIP_EN_LONG, seconds=20, wait_after=1.0)
        if not on_inject(m): return not_inject(m)
        delivered(m, 120)
        settle_out(60)
        empty = log_has(m, r"returned no words")
        rec = state()["recoverable"]
        if rec and rec.get("path") == rec0:
            rec = None
        if not rec:
            return ("BUG" if empty else "FAIL"), f"'returned no words' {empty}, nothing recoverable"
        t0 = now_iso()
        mr = log_mark()
        post("/test/recover")
        delivered(mr, 150)
        settle_out(60)
        d = last_delivery(t0)
        note = f"'returned no words' {empty}, staged {os.path.basename(rec.get('path', ''))} ({rec.get('duration')} s), Recover via {(d or {}).get('via')}"
        return ("PASS" if d else "FAIL"), note


@case("TR14", ("audio", "gesture", "slow"),
      expect="helper killed mid-decode → .failed with the audio, app alive, helper restarts, the next sentence delivers")
def tr14():
    """The local helper dies with a request in it."""
    why = pre()
    if why: return "SKIP", why
    h = helper()
    if not (h.get("ready") and h.get("alive")):
        return "SKIP", f"local helper not up ({h})"
    pid0, hpid0 = state()["pid"], h.get("pid")
    rec0 = (state().get("recoverable") or {}).get("path")   # an earlier case's cancel stays 5 min
    with rig():
        post("/test/eleven", {"fail": "401"})
        post("/test/whisper", {"stop": True})    # the request is surely in flight when the kill lands
        try:
            m, _ = dictate_loopback(CLIP_EN_LONG, seconds=10, wait_after=1.0)
            if not on_inject(m): return not_inject(m)
            if not when(m, FALLBACK, 20):
                return "FAIL", "no fallback after the 401"
            time.sleep(0.2)
            post("/test/whisper", {"kill": True})
        finally:
            _quiet(post, "/test/whisper", {"cont": True})
        delivered(m, 60)
        settle_out(60)
        failed = log_has(m, r"could not transcribe it either|heard no words")
        rec = state()["recoverable"]
        if rec and rec.get("path") == rec0:
            rec = None
        alive_pid = state()["pid"]
        t1 = now_iso()
        post("/test/eleven", {"fail": "401"})
        m2, _ = dictate_loopback(CLIP_EN, wait_after=1.0)
        delivered(m2, 150)
        settle_out(60)
        d2 = last_delivery(t1)
        h2 = helper()
        note = (f"failed line {failed}, recoverable {bool(rec)}, app pid {pid0} → {alive_pid}, helper pid {hpid0} → {h2.get('pid')} alive {h2.get('alive')}, "
                f"next sentence via {(d2 or {}).get('via')}")
        ok = rec and alive_pid == pid0 and d2 and "local" in d2.get("via", "") and h2.get("pid") != hpid0
        if alive_pid == pid0 and not rec and failed:
            return "BUG", note + " — the audio was not kept (§3.8)"
        return ("PASS" if ok else "FAIL"), note


@case("TR15", ("audio", "gesture", "slow"),
      expect="local engine: 3 s, cancel, 3.6 s within 3 s, ×20 → no 'gave no answer', every second sentence gets its own words")
def tr15():
    """Helper desync after a cancel (24 'gave no answer' since 08-28)."""
    why = pre(None)
    if why: return "SKIP", why
    n = int(os.environ.get("WT_TR15_N", "20"))
    with rig(), engine_as("whisper"):
        if not wait_for(lambda: engine().get("ready"), 90, 1.0):
            return "SKIP", "the local engine did not get ready in 90 s"
        m0 = log_mark()
        good, wrong = 0, []
        for i in range(n):
            mi, _ = dictate_loopback(CLIP_EN_LONG, seconds=3, wait_after=0.0, stop=False)
            if i == 0 and not on_inject(mi): return not_inject(mi)
            post("/test/cancel")
            wait_for(lambda: not state()["isRecording"], 2.5, 0.05)
            t0 = now_iso()
            m2, _ = dictate_loopback(CLIP_EN, wait_after=0.1)
            delivered(m2, 60)
            settle_out(60)
            d = last_delivery(t0)
            text = (outbox_tail(1) or [{}])[0].get("text", "") if d else ""
            if d and "dictat" in text.lower():
                good += 1
            else:
                wrong.append((i, (d or {}).get("via"), text[:40]))
        gna = count(m0, r"gave no answer")
    note = f"{good}/{n} sentences delivered their own words, 'gave no answer' ×{gna}, misses {wrong[:3]}"
    if gna or wrong:
        return ("BUG" if gna else "FAIL"), note
    return "PASS", note


@case("TR23", ("audio", "gesture"),
      expect="three more chords during the settle (within 0.5 s) → no new dictation, one delivery")
def tr23():
    """A second gesture while the words are in flight."""
    why = pre()
    if why: return "SKIP", why
    with rig():
        post("/test/eleven", {"fail": "500", "delayMs": 3000})   # widen the settle to ~4 s
        m, _ = dictate_loopback(CLIP_EN, wait_after=1.0)
        if not on_inject(m): return not_inject(m)
        when(m, r"recording stopped", 10)
        ms = log_mark()
        for _ in range(3):
            gesture("forward-right"); time.sleep(0.15)
        delivered(m, 60)
        time.sleep(5)
        opened = count(ms, r"mic: recording through")
        dels = count(m, r"📦 delivery:")
        still = state()["isRecording"]
        settle_out(60)
    note = f"new microphones after the stop {opened}, deliveries {dels}, recording at the end {still}"
    return ("PASS" if opened == 0 and dels == 1 else "FAIL"), note


@case("TR24", ("audio", "gesture"),
      expect="bind B during the settle → the words go where the latch said at the stop (A); R11 predicts they follow the bind")
def tr24():
    """Rebinding while the words are in flight."""
    why = pre()
    if why: return "SKIP", why
    fb = WORK + "/witness-b.txt"
    open(fb, "w").close()
    script = f"printf '\\\\e]0;wt-witness-b\\\\a'; stty -echo; exec cat >> {fb}"
    ttyb = None
    try:
        with rig():
            ttyb = osa(f'tell application "Terminal" to set t to do script "{script}"',
                       'tell application "Terminal" to get tty of t').replace("/dev/", "")
            time.sleep(0.8)
            post("/bind", {"tty": WITNESS["tty"]})
            t0 = now_iso()
            post("/test/eleven", {"fail": "500", "delayMs": 3000})
            m, _ = dictate_loopback(CLIP_EN, wait_after=1.0)
            if not on_inject(m): return not_inject(m)
            when(m, r"recording stopped", 10)
            time.sleep(0.5)
            post("/bind", {"tty": ttyb})
            delivered(m, 60)
            settle_out(60)
            time.sleep(1.0)
            d = last_delivery(t0) or {}
            a, b = witness_text(), open(fb, errors="replace").read()
    finally:
        # Kill the tab's `cat` first — Terminal will not close a window with a running process.
        if ttyb:
            _quiet(subprocess.run, ["pkill", "-t", ttyb], capture_output=True)
            time.sleep(0.3)
        _quiet(osa, 'tell application "Terminal" to close (every window whose name contains "wt-witness-b") saving no')
    inA, inB = "dictat" in a.lower(), "dictat" in b.lower()
    note = f"A ({WITNESS['tty']}) {len(a)} chars, B ({ttyb}) {len(b)} chars, delivery to {d.get('to')}"
    if inA and not inB: return "PASS", note
    if inB and not inA: return "BUG", note
    return "FAIL", note


@case("TR25", ("audio",),
      expect="device switch refused → system input: the chip shows the device really recording; a silent device is flagged, not uploaded as silence")
def tr25():
    """A refused device switch — not injectable through /test/eleven."""
    return "SKIP", "needs a refused CoreAudio switch (G11 failNextOpen or hardware); /test/eleven cannot inject it"


# ================================================================ §7.4 LC13 + live socket
@case("LC13", ("audio", "gesture"),
      expect="live integration: band words > 0 while isRecording; the band closes when listening goes false")
def lc13():
    """The band follows a real sentence and closes with it."""
    why = pre(LIVE)
    if why: return "SKIP", why
    with rig():
        m = start()
        if not on_inject(m): return not_inject(m)
        th = play_async(CLIP_EN, tail=1.0)
        S = sample(4.5, hz=10, fn=state)
        th.join()
        gesture("forward-right")
        S2 = sample(4.0, hz=20, fn=state)
        delivered(m, 60)
        settle_out(60)
    words = max((s["liveCaption"]["words"] for s in S if s["isRecording"]), default=0)
    t_l = next((s["t"] for s in S2 if not s["listening"]), None)
    t_c = next((s["t"] for s in S2 if not s["liveCaption"]["open"]), None)
    note = f"max band words while recording {words}; after stop: listening false at {t_l} s, band closed at {t_c} s"
    ok = words > 0 and t_c is not None and (t_l is None or t_c <= t_l + 0.3)
    return ("PASS" if ok else "FAIL"), note


@case("B1", ("audio", "gesture"),
      expect="first live partial ≤ 2 s after speech starts (plan: ≤ 1.5 s)")
def b1():
    """How soon the caption shows the first words."""
    why = pre(LIVE)
    if why: return "SKIP", why
    with rig():
        m = start()
        if not on_inject(m): return not_inject(m)
        time.sleep(0.4)
        t_play = time.time()
        th = play_async(CLIP_EN, tail=1.5)
        t_speech = t_play + 0.5            # play()'s lead silence; the clip's own lead-in counts against us
        t_first = wait_for(lambda: time.time() if lc()["words"] > 0 else None, 8, 0.03)
        live = state().get("live") or {}
        th.join()
        gesture("forward-right")
        delivered(m, 60)
        settle_out(60)
    t_open = re.search(r"session open, (\d+) chunk", log_since(m))
    lat = t_first and t_first - t_speech
    note = (f"first band word {lat and round(lat, 2)} s after the WAV started; socket {live.get('socket')}, chunks {live.get('chunksSent')}, "
            f"segments {live.get('segments')}, caught up {t_open.group(1) if t_open else '?'} chunk(s) at session open")
    return ("PASS" if lat is not None and lat <= 2.0 else "FAIL"), note


@case("B2", ("audio", "gesture"),
      expect="a VAD commit → '💬 live correction: … → scribe_v2', live.corrections ≥ 1, elevenCost.total grows, band corrections ≥ 0")
def b2():
    """A rolling batch correction at the first pause."""
    why = pre(LIVE)
    if why: return "SKIP", why
    with rig():
        cost0 = state()["elevenCost"]["total"]
        m, _ = dictate_loopback(CLIP_EN, wait_after=0.0, stop=False)
        if not on_inject(m): return not_inject(m)
        t_s = when(m, CORR_START + r".* → scribe_v2", 10)
        t_d = when(m, CORR_DONE, 10)
        s = state()
        live, cost1, band = s.get("live") or {}, s["elevenCost"]["total"], s["liveCaption"]
        stop()
        delivered(m, 60)
        settle_out(60)
    note = (f"correction started {bool(t_s)}, applied {bool(t_d)} ({t_d and t_s and round(t_d - t_s, 2)} s), live.corrections {live.get('corrections')}, "
            f"cost {cost0:.5f} → {cost1:.5f}, band corrections {band.get('corrections')} words {band.get('words')}")
    ok = t_s and t_d and (live.get("corrections") or 0) >= 1 and cost1 > cost0
    return ("PASS" if ok else "FAIL"), note


@case("B3", ("audio", "gesture"),
      expect="stop while a correction is in flight (500 after 4 s, then the real retry) → no update after close, no crash (pid unchanged), the sentence delivers")
def b3():
    """R20 — a correction answering after the socket closed is dropped."""
    why = pre(LIVE)
    if why: return "SKIP", why
    pid0 = state()["pid"]
    with rig():
        t0 = now_iso()
        post("/test/eleven", {"fail": "500", "scope": "correction", "delayMs": 4000})
        m, _ = dictate_loopback(CLIP_EN, wait_after=0.0, stop=False)
        if not on_inject(m): return not_inject(m)
        if not when(m, CORR_START, 10):
            stop(); return "FAIL", "no correction started within 10 s of the clip"
        injected = when(m, r"injected HTTP 500 .*on correction", 2)
        ms = log_mark()
        stop()
        time.sleep(9)                    # 4 s fake + 0.8 s backoff + the real retry
        delivered(m, 60)
        settle_out(60)
        after = log_since(ms)
        applied = bool(re.search(CORR_DONE, after))
        retried = bool(re.search(r"attempt 1 failed", after))
        d = last_delivery(t0)
        pid1 = state()["pid"]
    note = f"fault taken {bool(injected)}, retry after close {retried}, correction applied after close {applied}, pid {pid0} → {pid1}, delivered via {(d or {}).get('via')} (no discard line exists in the code)"
    return ("PASS" if not applied and pid1 == pid0 and d else "FAIL"), note


@case("B4", ("audio", "gesture"),
      expect="correction failure (500 ×2, the call and its retry) → 'after 5 s' hold, cut unchanged, the next upload ≥ 5 s later covers the longer span")
def b4():
    """A failed correction holds 5 s, then re-uploads from the same cut."""
    why = pre(LIVE)
    if why: return "SKIP", why
    with rig():
        # plain "500" is retried once inside transcribe() and would succeed; x2 makes the correction fail
        post("/test/eleven", {"fail": "500x2", "scope": "correction"})
        m, _ = dictate_loopback(CLIP_EN, wait_after=0.0, stop=False)
        if not on_inject(m): return not_inject(m)
        t_f = when(m, r"live correction failed .*after 5 s", 15)
        if not t_f:
            stop(); return "FAIL", "no failed correction within 15 s"
        cut = (state().get("live") or {}).get("cutSeconds")
        mf = log_mark()
        t_n = when(mf, CORR_START, 12)
        stop()
        delivered(m, 60)
        settle_out(60)
    spans = [float(x) for x in re.findall(CORR_START, log_since(m))]
    gap = t_n and t_n - t_f
    note = f"hold {gap and round(gap, 2)} s, cut after the failure {cut}, spans {spans}"
    ok = gap is not None and 4.8 <= gap <= 7.0 and cut == 0 and len(spans) >= 2 and spans[1] > spans[0]
    return ("PASS" if ok else "FAIL"), note


@case("B5", ("audio", "gesture"),
      expect="elevenCost.total grows by (live s × 0.39 × (1 + 0.2 with keyterms) + batch s × 0.22)/3600 (±25 %)")
def b5():
    """The cost row grows by what one sentence costs."""
    why = pre(LIVE)
    if why: return "SKIP", why
    with rig():
        c0 = state()["elevenCost"]
        m = start()
        if not on_inject(m): return not_inject(m)
        th = play_async(CLIP_EN, tail=2.5)
        kt = 0
        while th.is_alive():
            kt = max(kt, (state().get("live") or {}).get("keyterms") or 0)
            time.sleep(0.3)
        gesture("forward-right")
        delivered(m, 60)
        settle_out(60)
        c1 = state()["elevenCost"]
    log = log_since(m)
    dur = re.search(r"recording stopped — ([\d.]+)s", log)
    d = float(dur.group(1)) if dur else 0.0
    starts = [float(x) for x in re.findall(CORR_START, log)]
    done = len(re.findall(CORR_DONE, log))
    corr = sum(starts[:done])
    want = (d * 0.39 * (1 + (0.2 if kt else 0)) + (d + corr) * 0.22) / 3600
    got = c1["total"] - c0["total"]
    note = f"Δ ${got:.6f} vs expected ${want:.6f} (recording {d} s, corrections {corr:.1f} s, keyterms {kt}); label {c0['label']} → {c1['label']}"
    ok = d > 0 and got > 0 and abs(got - want) <= max(0.25 * want, 0.00002)
    return ("PASS" if ok else "FAIL"), note
