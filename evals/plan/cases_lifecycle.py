#!/usr/bin/env python3
"""T-L (lifecycle) and T-R (regression) cases of docs/test-plan.md §7.1 / §7.3, driven over the
loopback routes. Loaded by harness.py (`import cases_lifecycle`); never run on its own.

Verdicts: PASS = the app does what the plan expects · BUG = the plan's predicted defect confirmed ·
FAIL = neither · SKIP = precondition missing. Every case restores the engine it found, leaves
nothing listening / settling / held, and puts the whisper helper back up if it touched it.
Audio goes only through the harness's own Loopback (`mic_override(INJECT)` + `play`), never the room."""
import os, re, subprocess, threading, time, wave, datetime, plistlib, glob

from harness import *  # noqa: F401,F403 — get/post/state/engine/gesture/wait_for/log_* /case …

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
INJECT = LOOPBACK.replace("🧪 ", "")  # the substring /test/mic matches; "WT Inject" on the host, "BlackHole 2ch" in the lab                       # substring of the harness's Loopback device
SHOTS = os.path.expanduser("~/Library/Caches/ro.victorrentea.wispr-relay/shots")
HANGS = os.path.expanduser("~/.walkie-talkie/hangs")
APP = "/Applications/Walkie Talkie.app"


# ---------------------------------------------------------------- helpers
def _quiet(s=None):
    s = s or state()
    return not (s["listening"] or s["settling"] or s["isRecording"] or s.get("speculative"))

def _settle_down():
    """End of every case: cancel only if something is in flight; a held sentence goes to the
    witness (never to Victor's session) so `awaitingBind` is never left true."""
    try:
        if not _quiet():
            post("/test/cancel")
            wait_for(lambda: _quiet(), 6, 0.1)
        if state().get("awaitingBind"):
            bind_witness()
            wait_for(lambda: not state()["awaitingBind"], 6, 0.1)
    except Exception:
        pass

def _restore_engine(e0):
    try:
        if e0 and engine()["engine"] != e0:
            _settle_down()
            post("/engine", {"id": e0})
    except Exception:
        pass

def _whisper():
    return state().get("whisper") or {}

def _helper_up(timeout=120):
    """The mlx helper ready and alive; seconds it took (0 if it already was), None if never."""
    t0 = time.time()
    w = _whisper()
    if w.get("ready") and w.get("alive"):
        return 0.0
    post("/test/whisper", {"restart": True})
    ok = wait_for(lambda: (lambda w: w.get("ready") and w.get("alive"))(_whisper()), timeout, 0.25)
    return round(time.time() - t0, 1) if ok else None

def _fallback(wav, timeout=200):
    """POST /test/local-fallback → (answer or None, seconds, error)."""
    t0 = time.time()
    try:
        _, r = post("/test/local-fallback", {"wav": wav}, timeout=timeout)
        return r, round(time.time() - t0, 2), None
    except Exception as e:
        return None, round(time.time() - t0, 2), f"{type(e).__name__}: {e}"

def _clip(src, seconds, out):
    """The first `seconds` of a 16 kHz mono WAV."""
    r = wave.open(src)
    w = wave.open(out, "wb"); w.setparams(r.getparams())
    w.writeframes(r.readframes(int(r.getframerate() * seconds))); w.close(); r.close()
    return out

def _gate(max_wait=20):
    """`relay-restart.sh --dry-run`: exit 0 = gate open (would restart), 3 = gave up waiting."""
    t0 = time.time()
    p = subprocess.run(["./relay-restart.sh", "--dry-run", "--max-wait", str(max_wait)],
                       cwd=REPO, capture_output=True, text=True, timeout=max_wait + 60)
    return p.returncode, (p.stdout + p.stderr).strip(), round(time.time() - t0, 1)

def _iso(v):
    try:
        return datetime.datetime.fromisoformat(v.replace("Z", "+00:00")).timestamp()
    except Exception:
        return None

def _replace_wispr_off():
    """/test/dictation pastes at the caret in Replace Wispr mode — switch it off; True = restore."""
    try:
        v = subprocess.run(["defaults", "read", "ro.victorrentea.wispr-relay", "replaceWispr"],
                           capture_output=True, text=True).stdout.strip()
    except Exception:
        v = ""
    if v in ("1", "true", "YES"):
        post("/test/replace-wispr", {"on": False})
        return True
    return False

def _replace_wispr_restore(was_on):
    if was_on:
        post("/test/replace-wispr", {"on": True})

def _unbound():
    if state().get("bound"):
        unbind()
        wait_for(lambda: not state().get("bound"), 5, 0.1)

def _invariants():
    """The two invariants §1 asks every test to assert."""
    out = []
    try:
        s = state()
        ld = s.get("lastDelivery") or None
        if ld and ld.get("to") != "held" and s.get("awaitingBind"):
            out.append(f"awaitingBind true while lastDelivery.to={ld.get('to')}")
        if ld and str(ld.get("to", "")).startswith(("terminal:", "spawn:")):
            tail = ((outbox_tail(1) or [{}])[0].get("delivery")) or {}
            if tail.get("to") != ld.get("to"):
                out.append(f"outbox tail to={tail.get('to')} ≠ lastDelivery.to={ld.get('to')}")
    except Exception as e:
        out.append(f"invariants unreadable: {e}")
    return out

def _inv_note():
    v = _invariants()
    return ("; invariants: " + " | ".join(v)) if v else "; invariants ok"

def _hold_unbound(text):
    """A /test/dictation with nothing bound → held for a bind. Returns the wall time it became held."""
    post("/test/dictation", {"text": text})
    ok = wait_for(lambda: state()["awaitingBind"], 15, 0.1)
    return time.time() if ok else None

def _stage_cancelled():
    """A real recording through the Loopback, cancelled → staged for Recover. Needs a gesture."""
    mark, _ = dictate_loopback(CLIP_EN, wait_after=0.5, stop=False)
    post("/test/cancel")
    rec = wait_for(lambda: state().get("recoverable"), 6, 0.1)
    return rec, mark

def _open_then_cancel(hold=0.5, open_timeout=4):
    """forward-right → microphone open → hold → /test/cancel → quiet. (opened, closed, t_open)."""
    mark = log_mark()
    gesture("forward-right")
    t0 = time.time()
    opened = wait_for(lambda: log_has(mark, r"mic: recording through"), open_timeout, 0.05)
    t_open = round(time.time() - t0, 2) if opened else None
    time.sleep(hold)
    post("/test/cancel")
    closed = wait_for(lambda: _quiet(), 4, 0.05)
    return bool(opened), bool(closed), t_open

def _chip():
    try:
        return state().get("chip") or []
    except Exception:
        return []


# ================================================================ §7.1 T-L
@case("TL1", tags=("slow",),
      expect="orphan flush 121 s after /test/area mid-sentence: dictationStartedAt stays non-null (today: null + "
             "'releasing 1 shot(s)' while listening)")
def tl1_orphan_flush_mid_sentence():
    """Orphan flush fires mid-sentence (R6): test-open sentence + an area, wait 121 s."""
    rw = _replace_wispr_off()
    try:
        tty = bind_witness().get("tty") or WITNESS["tty"]
        witness_clear()
        post("/test/dictation/start")
        if not wait_for(lambda: state()["listening"], 3):
            return "FAIL", "/test/dictation/start never set listening"
        started = state()["dictationStartedAt"]
        if not started:
            return "SKIP", "dictationStartedAt null right after start (no destination?) — cannot observe the flush"
        mark = log_mark()
        _, a = post("/test/area", {})
        t_area = time.time()
        if not a.get("ok"):
            return "FAIL", f"/test/area refused: {a}"
        time.sleep(118)
        fired = wait_for(lambda: log_has(mark, r"releasing \d+ shot") or not state()["dictationStartedAt"], 5, 0.1)
        dt = round(time.time() - t_area, 1)
        time.sleep(max(0, t_area + 121 - time.time()))
        s = state()
        released = log_has(mark, r"releasing \d+ shot")
        note = (f"bound {tty}; area at t=0, flush seen at {dt if fired else '—'} s; at 121 s listening={s['listening']} "
                f"dictationStartedAt={s['dictationStartedAt']} released={'yes' if released else 'no'} "
                f"witness got {len(witness_text())} chars")
        if s["listening"] and s["dictationStartedAt"] and not released:
            return "PASS", note + _inv_note()
        if s["listening"] and not s["dictationStartedAt"] and released:
            return "BUG", note + " — envelope wiped while the sentence is still open" + _inv_note()
        return "FAIL", note + _inv_note()
    finally:
        _settle_down()
        _replace_wispr_restore(rw)


@case("TL2", expect="cancel of a test-open sentence → within 200 ms listening/settling false, 'nothing to cancel' line")
def tl2_cancel_test_open():
    """Cancel a /test/dictation/start sentence (no recogniser behind it)."""
    try:
        post("/test/dictation/start")
        if not wait_for(lambda: state()["listening"], 3):
            return "FAIL", "/test/dictation/start never set listening"
        time.sleep(0.3)
        mark = log_mark()
        t0 = time.time()
        post("/test/cancel")
        ok = wait_for(lambda: (lambda s: not s["listening"] and not s["settling"])(state()), 2, 0.02)
        dt = round((time.time() - t0) * 1000)
        line = wait_for(lambda: log_has(mark, r"nothing to cancel"), 2, 0.05)
        note = f"cleared in {dt} ms; 'nothing to cancel' line: {'yes' if line else 'no'}"
        if ok and dt <= 200 and line:
            return "PASS", note
        return "FAIL", note + ("" if ok else " — still listening/settling after 2 s")
    finally:
        _settle_down()


@case("TL3", expect="POST /engine refused mid-sentence; accepted after cancel (whisper.loading:true when cold)")
def tl3_engine_switch_refused_mid_sentence():
    """Engine pick refused while a sentence is open, accepted once it is cancelled."""
    e0 = engine()["engine"]
    target = "whisper" if e0 != "whisper" else "eleven"
    try:
        post("/test/dictation/start")
        if not wait_for(lambda: state()["listening"], 3):
            return "FAIL", "/test/dictation/start never set listening"
        mark = log_mark()
        _, r1 = post("/engine", {"id": target})
        refused = r1.get("engine") == e0 and not log_has(mark, r"dictation engine switched")
        post("/test/cancel")
        wait_for(lambda: _quiet(), 3, 0.05)
        _, r2 = post("/engine", {"id": target})
        accepted = r2.get("engine") == target
        w = r2.get("whisper") or {}
        note = (f"{e0}→{target}: mid-sentence answer engine={r1.get('engine')}, after cancel engine={r2.get('engine')}"
                + (f"; whisper loading={w.get('loading')} ready={w.get('ready')}" if target == "whisper" else ""))
        if refused and accepted:
            return "PASS", note
        return "FAIL", note
    finally:
        _settle_down()
        _restore_engine(e0)


@case("TL4", expect="/test/local-fallback happy path: via:local-fallback, ~6 s cold / ~2 s warm")
def tl4_local_fallback_happy():
    """The local model standing in for a failed cloud call, cold then warm."""
    if not os.path.exists(CLIP_EN):
        return "SKIP", f"missing {CLIP_EN}"
    w0 = _whisper()
    cold = not w0.get("ready")
    r1, t1, e1 = _fallback(CLIP_EN)
    r2, t2, e2 = _fallback(CLIP_EN)
    def ok(r):
        return bool(r and r.get("ok") and r.get("via") == "local-fallback" and "dictat" in (r.get("text") or "").lower())
    note = (f"first ({'cold' if cold else 'warm'}): {t1} s ok={r1 and r1.get('ok')} via={r1 and r1.get('via')} "
            f"text={(r1 or {}).get('text', e1)!r}; second (warm): {t2} s ok={r2 and r2.get('ok')}")
    if ok(r1) and ok(r2) and t2 <= 5:
        return "PASS", note
    return "FAIL", note


@case("TL5", tags=("slow",),
      expect="helper hang (SIGSTOP): the 300 s decode budget is enforced ('timed out after 300s', the helper killed and "
             "replaced), the control surface answers while /test/local-fallback waits, the next decode is in sync. "
             "Before: only the route's 180 s semaphore answered, /up was blocked behind it, no timeout ever")
def tl5_helper_hang():
    """SIGSTOP the helper, ask for a decode, measure who gives up first; SIGCONT and check the stream."""
    if not os.path.exists(CLIP_EN) or not os.path.exists(CLIP_EN_LONG):
        return "SKIP", "corpus clips missing"
    up = _helper_up()
    if up is None:
        return "SKIP", "the helper would not come up in 120 s"
    other = _clip(CLIP_EN_LONG, 6, f"{WORK}/tl5-other.wav")   # different words from CLIP_EN
    mark = log_mark()
    stopped = False
    probe = {}
    try:
        _, r = post("/test/whisper", {"stop": True})
        if "SIGSTOP" not in (r.get("did") or []):
            return "SKIP", f"no helper to stop: {r}"
        stopped = True
        def _probe():
            time.sleep(5)
            t = time.time()
            try:
                get("/up", timeout=3); probe["up"] = f"{time.time() - t:.2f} s"
            except Exception as e:
                probe["up"] = f"blocked ({type(e).__name__})"
        threading.Thread(target=_probe, daemon=True).start()
        t0 = time.time()
        ans, dt, err = _fallback(CLIP_EN, timeout=200)
        # "ever": watch past the helper's own 300 s budget before letting it go
        while time.time() - t0 < 305:
            time.sleep(1)
        timed_out = log_has(mark, r"whisper helper timed out after \d+s")
        post("/test/whisper", {"cont": True}); stopped = False
        c_mark = log_mark()
        stale = wait_for(lambda: log_has(c_mark, r"transcribed on this Mac instead of a test|local model heard no words"), 60, 0.2)
        nxt, t_next, e_next = _fallback(other, timeout=120)
        desync = bool(nxt and "dictat" in (nxt.get("text") or "").lower())
        note = (f"route answered after {dt} s ({(ans or {}).get('ok', err)}); control surface at +5 s: {probe.get('up', '?')}; "
                f"'timed out after' by 305 s: {'yes' if timed_out else 'no'}; after SIGCONT stale answer consumed: "
                f"{'yes' if stale else 'no'}; next decode {t_next} s ok={(nxt or {}).get('ok')} "
                f"{'DESYNC (got the stale clip)' if desync else 'in sync'}")
        if dt >= 175 and not timed_out:
            return "BUG", note + " — the helper's 300 s budget is not enforced; only the route's semaphore answered"
        if timed_out and not str(probe.get("up", "")).startswith("blocked") and not desync:
            return "PASS", note
        return "FAIL", note
    finally:
        if stopped:
            post("/test/whisper", {"cont": True})
        _helper_up()


@case("TL6", expect="dead helper (SIGKILL) → /test/local-fallback {ok:false} fast + 'it died', app pid unchanged "
                    "(probable before G4: app dies of SIGPIPE); restart brings it back")
def tl6_dead_helper_sigpipe():
    """SIGKILL the helper, ask for a decode: the app must survive and refuse fast."""
    if _helper_up() is None:
        return "SKIP", "the helper would not come up in 120 s"
    pid0 = state()["pid"]
    hpid = _whisper().get("pid")
    try:
        _, r = post("/test/whisper", {"kill": True})
        if "SIGKILL" not in (r.get("did") or []):
            return "SKIP", f"no helper to kill: {r}"
        wait_for(lambda: not _whisper().get("alive"), 3, 0.05)
        mark = log_mark()
        ans, dt, err = _fallback(CLIP_EN, timeout=200)
        try:
            s = state()
        except Exception:
            s = None
        if s is None:
            subprocess.run(["open", "-g", APP])
            wait_for(lambda: get("/up", timeout=2).get("ok"), 30, 1)
            return "BUG", f"the app died on the dead helper (route: {err or ans}); relaunched via open"
        died_line = log_has(mark, r"whisper helper .*it died")
        ready = (s.get("whisper") or {}).get("ready")
        t_up = _helper_up()
        new_pid = _whisper().get("pid")
        note = (f"route {dt} s → {ans if ans else err}; app pid {pid0}→{s['pid']}; 'it died' line: "
                f"{'yes' if died_line else 'no'}; ready after={ready}; restart up in {t_up} s (helper pid {hpid}→{new_pid})")
        if s["pid"] != pid0:
            return "BUG", note + " — the app was replaced"
        if ans is not None and not ans.get("ok") and dt < 5 and not ready and t_up is not None:
            return "PASS", note
        return "FAIL", note
    finally:
        _helper_up()


@case("TL7", expect="a dead helper must not read ready:true in /engine (plan: today still ready:true until a request fails)")
def tl7_dead_helper_still_ready():
    """SIGKILL the helper and read /engine.whisper before and after the first request."""
    if _helper_up() is None:
        return "SKIP", "the helper would not come up in 120 s"
    try:
        _, r = post("/test/whisper", {"kill": True})
        if "SIGKILL" not in (r.get("did") or []):
            return "SKIP", f"no helper to kill: {r}"
        gone = wait_for(lambda: not _whisper().get("alive"), 3, 0.05)
        e1 = engine().get("whisper") or {}
        ans, dt, _ = _fallback(CLIP_EN, timeout=200)
        e2 = engine().get("whisper") or {}
        note = (f"after SIGKILL (alive={e1.get('alive')}): ready={e1.get('ready')}; after one request "
                f"({dt} s, ok={(ans or {}).get('ok')}): ready={e2.get('ready')}")
        if not gone:
            return "FAIL", note + " — helper still alive 3 s after SIGKILL"
        if e1.get("ready") and not e1.get("alive"):
            return "BUG", note + " — ready stays true on a dead helper until a request trips over it"
        if not e1.get("ready"):
            return "PASS", note
        return "FAIL", note
    finally:
        _helper_up()


@case("TL15", tags=("gesture",),
      expect="a slow upload (45 s) keeps the settle up past the old 30 s ceiling — it waits while the recogniser "
             "works (2026-09-26, item 5) — and both start gestures refuse while the words are in flight, saying so; "
             "the late reply lands in the latched terminal. Before: the settle gave up at 32 s, forward-click refused, "
             "forward-right started a sentence the late reply then landed in")
def tl15_inconsistent_start_gates():
    """Delay the final upload 45 s (fault switch); at 33 s after the stop try both start gestures."""
    if not loopback_alive():
        return "SKIP", "Loopback pass-thru dead (440 Hz check failed)"
    e0 = engine()["engine"]
    try:
        if not e0.startswith("eleven"):
            post("/engine", {"id": "eleven"})
        if not engine().get("ready"):
            return "SKIP", "ElevenLabs has no key — the case needs a real upload"
        tty = bind_witness().get("tty") or WITNESS["tty"]
        mic_override(INJECT)
        post("/test/eleven", {"fail": "500", "delayMs": 45000, "scope": "final"})
        mark, _ = dictate_loopback(CLIP_EN, wait_after=1.0)
        t_stop = time.time()
        time.sleep(max(0, t_stop + 33 - time.time()))
        s33 = state()
        waiting = s33["settling"] and s33["phase"] == "transcribing"
        m2 = log_mark()
        gesture("forward-click")
        time.sleep(1.5)
        click_refused = log_has(m2, r"still in flight")
        click_started = state()["listening"] or state()["isRecording"]
        if click_started:
            post("/test/cancel"); wait_for(lambda: _quiet(), 4)
        time.sleep(0.7)
        m3 = log_mark()
        gesture("forward-right")
        right_started = bool(wait_for(lambda: state()["isRecording"] or state()["listening"], 3, 0.05))
        right_refused = log_has(m3, r"start refused — .*still in flight")
        if right_started:
            time.sleep(0.5)
            post("/test/cancel"); wait_for(lambda: _quiet(), 4)
        late = wait_for(lambda: log_has(mark, r"elevenlabs: .* chars|↪️"), 40, 0.3)
        landed = wait_for(lambda: (state().get("lastDelivery") or {}).get("to") == f"terminal:{tty}", 30, 0.3)
        s = state()
        note = (f"{engine()['engine']}: at 33 s after the stop settling={s33['settling']} phase={s33['phase']}/"
                f"{s33['phaseStatus']}; forward-click {'refused' if click_refused else ('STARTED' if click_started else 'no-op')}, "
                f"forward-right {'STARTED' if right_started else ('refused' if right_refused else 'no-op')}; late reply "
                f"{'landed' if late else 'not seen'}, lastDelivery.to={(s.get('lastDelivery') or {}).get('to')} (bound {tty})")
        if waiting and click_refused and not click_started and right_refused and not right_started and landed:
            return "PASS", note + _inv_note()
        if click_refused and right_started:
            return "BUG", note + " — the two start gates disagree" + _inv_note()
        return "FAIL", note + _inv_note()
    finally:
        post("/test/eleven", {"clear": True})
        _settle_down()
        _restore_engine(e0)


@case("TL17", tags=("gesture",),
      expect="Recover with the model down transcribes (brings it up); today: 'produced no transcript', file still present")
def tl17_recover_model_down():
    """Stage a cancelled recording, kill the helper, Recover."""
    if not loopback_alive():
        return "SKIP", "Loopback pass-thru dead (440 Hz check failed)"
    try:
        bind_witness()                      # a successful Recover types into the witness, not the caret
        witness_clear()
        mic_override(INJECT)
        rec, _ = _stage_cancelled()
        if not rec:
            return "FAIL", "the cancel staged nothing (state.recoverable null)"
        post("/test/whisper", {"kill": True})
        wait_for(lambda: not _whisper().get("alive"), 3, 0.05)
        _fallback(CLIP_EN, timeout=30)      # trips over the dead pipe → ready false: the model is now down
        w_before = _whisper()
        mark = log_mark()
        post("/test/recover")
        seen = wait_for(lambda: log_has(mark, r"recovered audio produced no transcript|↩️ recovered \d+ chars"), 30, 0.2)
        w_after = _whisper()
        failed = log_has(mark, r"recovered audio produced no transcript")
        recovered = log_has(mark, r"↩️ recovered \d+ chars")
        present = os.path.exists(rec["path"])
        note = (f"staged {rec.get('duration', 0):.1f} s at {os.path.basename(rec['path'])}; model before Recover "
                f"ready={w_before.get('ready')} alive={w_before.get('alive')}; after: loading={w_after.get('loading')} "
                f"ready={w_after.get('ready')}; outcome={'no transcript' if failed else 'recovered' if recovered else 'nothing logged'}; "
                f"file still present={present}; witness {len(witness_text())} chars")
        if recovered:
            return "PASS", note
        if failed and present:
            return "BUG", note + " — Recover never loads the model"
        return "FAIL", note
    finally:
        _settle_down()
        _helper_up()


@case("TL18", tags=("gesture",),
      expect="the restart gate blocks while audio is staged for Recover; today: --dry-run opens (busy:false) "
             "and a restart would wipe cancelled/")
def tl18_gate_ignores_recover_staging():
    """Stage a cancelled recording, then ask the restart gate."""
    if not loopback_alive():
        return "SKIP", "Loopback pass-thru dead (440 Hz check failed)"
    try:
        mic_override(INJECT)
        rec, _ = _stage_cancelled()
        if not rec:
            return "FAIL", "the cancel staged nothing (state.recoverable null)"
        s = state()
        rc, out, secs = _gate(20)
        still = state().get("recoverable")
        note = (f"staged {rec.get('duration', 0):.1f} s; busy={s['busy']} busyWhy={s['busyWhy']}; dry-run exit {rc} "
                f"after {secs} s ({out.splitlines()[-1] if out else ''}); recoverable still set={bool(still)}")
        if rc == 3:
            return "PASS", note
        if rc == 0 and still:
            return "BUG", note + " — the gate opened over staged audio"
        return "FAIL", note
    finally:
        _settle_down()


@case("TL21", tags=("gesture",),
      expect="start+stop coalesced inside a 6 s main stall → 'under 0.35s' or a dwell refusal, and a banner; "
             "today: no banner")
def tl21_stall_coalescing():
    """Two F10s inside /test/stall 6 (both before the 3 s fail-open), then read the log."""
    try:
        mic_override(INJECT)
        mark = log_mark()
        post("/test/stall", {"seconds": 6})
        t0 = time.time()
        time.sleep(0.5)
        gesture("forward-right")
        time.sleep(max(0, t0 + 1.7 - time.time()))
        gesture("forward-right")
        # no /test/state during the stall
        time.sleep(max(0, t0 + 7.5 - time.time()))
        time.sleep(2.5)                      # the audio queue's close and the source's end
        chip = _chip()
        s = state()
        discarded = log_has(mark, r"discarded — under")
        dwell = log_has(mark, r"not stopping it")
        opened = log_has(mark, r"mic: recording through")
        banner = [r for r in chip if re.search(r"0\.35|too short|nothing was recorded|under", str(r), re.I)]
        note = (f"mic opened={opened}; 'discarded — under 0.35s'={discarded}; dwell refusal={dwell}; after the stall "
                f"listening={s['listening']} isRecording={s['isRecording']}; banner rows={banner or 'none'}")
        if dwell and (s["listening"] or s["isRecording"]):
            return "PASS", note + " — the second F10 was refused, the sentence stayed open"
        if discarded and banner:
            return "PASS", note
        if discarded and not banner:
            return "BUG", note + " — the stall coalesced start+stop into a silent sub-0.35 s discard"
        return "FAIL", note
    finally:
        _settle_down()


@case("TL22", tags=("gesture",),
      expect="a cold local model never delays the microphone (2026-09-26 decision): forward-right opens it within "
             "0.5 s while the model loads, nothing is banked; /test/cancel cancels it; an engine switch afterwards "
             "opens nothing. Before (R7): the gesture was banked, /test/cancel had nothing to cancel, and the switch "
             "opened the ElevenLabs microphone with no gesture")
def tl22_cold_model_records_at_once():
    """Engine whisper while the model restarts: forward-right, cancel, switch to eleven."""
    e0 = engine()["engine"]
    try:
        mic_override(INJECT)
        if e0 != "whisper":
            post("/engine", {"id": "whisper"})
        post("/test/whisper", {"restart": True})       # the model is cold for the next few seconds
        if _whisper().get("ready"):
            return "SKIP", "the model was ready before the gesture — nothing cold to test"
        mark = log_mark()
        t0 = time.time()
        gesture("forward-right")
        opened = wait_for(lambda: log_has(mark, r"mic: recording through"), 3, 0.02)
        t_open = round(time.time() - t0, 2) if opened else None
        cold = not _whisper().get("ready")
        anyway = log_has(mark, r"recording anyway")
        banked = log_has(mark, r"not ready — bringing it up")
        time.sleep(0.5)
        c_mark = log_mark()
        post("/test/cancel")
        quiet = wait_for(lambda: _quiet(), 3, 0.05)
        cancel_logged = log_has(c_mark, r"🗑️ dictation cancelled")
        _, r = post("/engine", {"id": "eleven"})
        reopened = wait_for(lambda: state()["isRecording"], 2.5, 0.02)
        chip = _chip()
        wispr_flash = any("Wispr Flow is not running" in str(x) for x in chip)
        note = (f"mic {'opened %.2f s after the gesture' % t_open if opened else 'did not open in 3 s'} "
                f"(model still loading={cold}, 'recording anyway' line={anyway}, banked line={banked}); "
                f"/test/cancel {'cancelled it' if cancel_logged else 'had nothing to cancel'}, quiet={bool(quiet)}; "
                f"switched to {r.get('engine')}: microphone {'OPENED' if reopened else 'stayed shut'}"
                f"{'; flash: Wispr Flow is not running' if wispr_flash else ''}")
        if banked or reopened or wispr_flash:
            return "BUG", note + " — the gesture was banked and outlived the cancel/engine"
        if opened and t_open <= 0.5 and cold and cancel_logged and quiet:
            return "PASS", note
        return "FAIL", note
    finally:
        _settle_down()
        _restore_engine(e0)
        _helper_up()


@case("TL23", tags=("env",),
      expect="broken Python (RELAY_WHISPER_PYTHON=/nonexistent): ≤ 1 'did not come up' line per 10 s (~20 today)")
def tl23_broken_python():
    """Needs the app relaunched with a bad RELAY_WHISPER_PYTHON — not done from a running harness."""
    return "SKIP", "needs an env change + relaunch of the app (RELAY_WHISPER_PYTHON=/nonexistent); out of scope for HTTP"


@case("TL24", tags=("slow",), expect="10-min ceiling on a test sentence fires at 600±1 s")
def tl24_ceiling_test_sentence():
    """/test/dictation/start and wait for the ten-minute ceiling to put it down."""
    try:
        mark = log_mark()
        post("/test/dictation/start")
        t0 = time.time()
        if not wait_for(lambda: state()["listening"], 3):
            return "FAIL", "/test/dictation/start never set listening"
        time.sleep(max(0, t0 + 598 - time.time()))
        down = wait_for(lambda: not state()["listening"], 4, 0.1)
        dt = round(time.time() - t0, 2)
        line = log_has(mark, r"⏱️ ten minutes")
        note = f"listening fell at {dt if down else '>602'} s; ceiling line: {'yes' if line else 'no'}"
        if down and 599 <= dt <= 601 and line:
            return "PASS", note
        return "FAIL", note
    finally:
        _settle_down()


@case("TL26", tags=("slow",), expect="held sentence (unbound /test/dictation) expires at 300 s: 'held dictation expired'")
def tl26_held_expiry():
    """Hold a sentence for a bind and watch the five-minute expiry."""
    rw = _replace_wispr_off()
    try:
        _unbound()
        mark = log_mark()
        t_held = _hold_unbound(f"tl26 held probe {int(time.time())}")
        if not t_held:
            return "FAIL", f"never held (lastDelivery={state().get('lastDelivery')})"
        ld = (state().get("lastDelivery") or {}).get("to")
        time.sleep(max(0, t_held + 298 - time.time()))
        gone = wait_for(lambda: not state()["awaitingBind"], 4 + max(0, t_held + 298 - time.time()), 0.1)
        dt = round(time.time() - t_held, 1)
        line = log_has(mark, r"held dictation expired")
        note = f"held (lastDelivery.to={ld}); released at {dt if gone else '>302'} s; expiry line: {'yes' if line else 'no'}"
        if gone and 298 <= dt <= 302 and line:
            return "PASS", note + _inv_note()
        return "FAIL", note + _inv_note()
    finally:
        _settle_down()
        _replace_wispr_restore(rw)


@case("TL27", tags=("tty",), expect="held sentence released by POST /bind {\"tty\"} within 1 s")
def tl27_held_released_by_bind():
    """Hold a sentence unbound, then bind the witness by tty."""
    rw = _replace_wispr_off()
    try:
        _unbound()
        tty = witness_open()
        witness_clear()
        phrase = f"tl27 held probe {int(time.time())}"
        if not _hold_unbound(phrase):
            return "FAIL", "never held"
        time.sleep(1.0)
        t0 = time.time()
        post("/bind", {"tty": tty})
        released = wait_for(lambda: not state()["awaitingBind"], 3, 0.02)
        dt = round(time.time() - t0, 2)
        landed = wait_for(lambda: phrase in witness_text(), 10, 0.1)
        ld = state().get("lastDelivery") or {}
        note = (f"released {dt} s after the bind; words in the witness: {'yes' if landed else 'no'}; "
                f"lastDelivery.to={ld.get('to')}")
        if released and dt <= 1.0 and landed and ld.get("to") == f"terminal:{tty}":
            return "PASS", note + _inv_note()
        return "FAIL", note + _inv_note()
    finally:
        _settle_down()
        _replace_wispr_restore(rw)


@case("TL28", tags=("hw", "slow"),
      expect="held sentence across sleep (6 wall-clock min) expires; today still awaitingBind (uptime clock)")
def tl28_held_across_sleep():
    """Hold a sentence, `pmset sleepnow`, wake after ≥ 6 min (by hand), read awaitingBind."""
    if os.environ.get("WT_SLEEP_OK") != "1":
        return "SKIP", "puts the Mac to sleep and needs a hand to wake it after ≥ 6 min — set WT_SLEEP_OK=1"
    rw = _replace_wispr_off()
    try:
        _unbound()
        mark = log_mark()
        t_held = _hold_unbound(f"tl28 held probe {int(time.time())}")
        if not t_held:
            return "FAIL", "never held"
        subprocess.run(["pmset", "sleepnow"])
        while time.time() - t_held < 360:
            time.sleep(5)
        s = state()
        note = f"{time.time() - t_held:.0f} s of wall clock since the hold; awaitingBind={s['awaitingBind']}; " \
               f"expiry line: {'yes' if log_has(mark, r'held dictation expired') else 'no'}"
        if s["awaitingBind"]:
            return "BUG", note + " — the 300 s hold counts awake time only"
        return "PASS", note
    finally:
        _settle_down()
        _replace_wispr_restore(rw)


@case("TL31", tags=("gesture", "slow"),
      expect="a hung helper (SIGSTOP) no longer wedges the app: the 300 s decode budget kills it, a new helper comes up, "
             "the sentence ends failed with its WAV staged for Recover, phase leaves `transcribing`, busy goes false "
             "and the restart gate opens — without a SIGCONT. Before: at 35 s phase transcribing, busy, the gate "
             "blocked until the helper was resumed by hand")
def tl31_stuck_phase_blocks_restart():
    """SIGSTOP the helper, dictate a clip on the local engine, wait out the decode budget."""
    if not loopback_alive():
        return "SKIP", "Loopback pass-thru dead (440 Hz check failed)"
    e0 = engine()["engine"]
    stopped = False
    try:
        bind_witness()
        mic_override(INJECT)
        if e0 != "whisper":
            post("/engine", {"id": "whisper"})
        if _helper_up() is None:
            return "SKIP", "the helper would not come up in 120 s"
        hpid = _whisper().get("pid")
        _, r = post("/test/whisper", {"stop": True})
        if "SIGSTOP" not in (r.get("did") or []):
            return "SKIP", f"no helper to stop: {r}"
        stopped = True
        rec0 = (state().get("recoverable") or {}).get("path")
        mark, _ = dictate_loopback(CLIP_EN, wait_after=1.0)
        t_stop = time.time()
        time.sleep(max(0, t_stop + 35 - time.time()))
        s35 = state()
        timed = wait_for(lambda: log_has(mark, r"whisper helper timed out after \d+s"), 300, 1.0)
        t_to = round(time.time() - t_stop, 1) if timed else None
        stopped = False                          # killed by the budget, not resumed
        ended = wait_for(lambda: (lambda s: s["phase"] != "transcribing" and not s["settling"])(state()), 20, 0.2)
        s = state()
        rec = s.get("recoverable") or {}
        staged = bool(rec.get("path")) and rec.get("path") != rec0
        failed = log_has(mark, r"did not answer within \d+ s")
        rc, out, secs = _gate(40)
        up = wait_for(lambda: (lambda w: w.get("ready") and w.get("alive"))(_whisper()), 90, 0.5)
        new_pid = _whisper().get("pid")
        note = (f"at 35 s: settling={s35['settling']} phase={s35['phase']}/{s35['phaseStatus']} (the settle waits); "
                f"'timed out' at {t_to} s after the stop; then phase={s['phase']} settling={s['settling']} "
                f"busyWhy={s['busyWhy']}; failed-with-budget line={failed}; WAV staged for Recover={staged}; "
                f"dry-run exit {rc} in {secs} s; helper {hpid}→{new_pid} ready={bool(up)}")
        if timed and ended and not s["busy"] and staged and rc == 0 and up and new_pid != hpid:
            return "PASS", note + _inv_note()
        if not timed:
            return "BUG", note + " — the decode budget was not enforced" + _inv_note()
        return "FAIL", note + _inv_note()
    finally:
        if stopped:
            post("/test/whisper", {"cont": True})
        _settle_down()
        _restore_engine(e0)
        _helper_up()


@case("TL33", tags=("gui",),
      expect="key hot-add under eleven-live reloads the live source too; today: 'key went away mid-sentence' + local-fallback")
def tl33_key_hot_add():
    """The hot-add is the menu's `elevenReady` read — a GUI path (Codex), not reachable over HTTP."""
    return "SKIP", "the key hot-add runs when the menu opens (status.elevenReady); needs Codex + moving elevenlabs.env"


# ================================================================ §7.3 T-R
def _nudge_tap():
    """A zero-delta scroll: something for the tap to see after 3 s, harmless if it passes through."""
    try:
        import Quartz
        ev = Quartz.CGEventCreateScrollWheelEvent(None, Quartz.kCGScrollEventUnitLine, 1, 0)
        Quartz.CGEventPost(Quartz.kCGHIDEventTap, ev)
        return True
    except Exception:
        return False

def _buttons_down():
    try:
        import Quartz
        return [b for b in range(5)
                if Quartz.CGEventSourceButtonState(Quartz.kCGEventSourceStateCombinedSessionState, b)]
    except Exception:
        return None


@case("TR4", tags=("gesture",),
      expect="fail-open proves itself (/test/stall 6 + input) → 🧊 within 3.5 s, one hangs/ file, no button left down")
def tr4_fail_open():
    """Stall main 6 s; a gesture at 1 s (swallowed, before the gate), a harmless scroll at 3.3 s to trip it."""
    before = set(glob.glob(HANGS + "/*"))
    mark = log_mark()
    try:
        post("/test/stall", {"seconds": 6})
        t0 = time.time()
        time.sleep(1.0)
        gesture("back-down")                 # before the 3 s gate: swallowed, handler waits for main
        time.sleep(max(0, t0 + 3.3 - time.time()))
        nudged = _nudge_tap()
        time.sleep(max(0, t0 + 8.5 - time.time()))   # past the stall — no /test/state inside it
        wait_for(lambda: log_has(mark, r"🧊 main thread back"), 5, 0.2)
        text = log_since(mark)
        m_silent = re.search(r"🧊 main thread silent for ([\d.]+) s", text)
        m_back = re.search(r"🧊 main thread back after ([\d.]+) s", text)
        new = sorted(set(glob.glob(HANGS + "/*")) - before)
        s = state()
        buttons = _buttons_down()
        note = (f"nudge posted={nudged}; silent line={m_silent.group(1) + ' s' if m_silent else 'none'}; back line="
                f"{m_back.group(1) + ' s' if m_back else 'none'}; new hangs files={len(new)}; sessionFlags={s.get('sessionFlags')}; "
                f"buttons down={buttons}")
        if m_silent and float(m_silent.group(1)) <= 3.5 and m_back and len(new) == 1 and not buttons \
                and not s.get("sessionFlags"):
            return "PASS", note
        return "FAIL", note + ("" if m_silent else " — no event reached the tap after 3 s, or the gate did not open")
    finally:
        _settle_down()


@case("TR17", tags=("tty",),
      expect="restart gate: blocked while a sentence is open; opens no sooner than 10 s after the delivery "
             "(dry-run only — the SIGTERM / kill -9 halves are not run from the harness)")
def tr17_restart_gate():
    """--dry-run against an open test sentence, then right after a delivered one."""
    rw = _replace_wispr_off()
    try:
        tty = bind_witness().get("tty") or WITNESS["tty"]
        post("/test/dictation/start")
        if not wait_for(lambda: state()["listening"], 3):
            return "FAIL", "/test/dictation/start never set listening"
        rc_a, out_a, secs_a = _gate(20)
        post("/test/cancel"); wait_for(lambda: _quiet(), 4)
        before = (state().get("lastDelivery") or {}).get("at")
        post("/test/dictation", {"text": f"tr17 gate probe {int(time.time())}"})
        got = wait_for(lambda: (lambda d: d and d.get("at") != before and str(d.get("to", "")).startswith("terminal:"))(
            state().get("lastDelivery")), 20, 0.1)
        if not got:
            return "FAIL", f"the probe sentence never landed in the witness ({tty})"
        t_deliv = _iso(state()["lastDelivery"]["at"])
        rc_b, out_b, secs_b = _gate(40)
        gap = round(time.time() - t_deliv, 1) if t_deliv else None
        note = (f"open sentence: exit {rc_a} after {secs_a} s ({out_a.splitlines()[-1] if out_a else ''}); "
                f"after delivery: exit {rc_b}, gate opened {gap} s after lastDelivery.at")
        if rc_a == 3 and rc_b == 0 and gap is not None and gap >= 10:
            return "PASS", note + _inv_note()
        return "FAIL", note + _inv_note()
    finally:
        _settle_down()
        _replace_wispr_restore(rw)


@case("TR18", tags=("gesture",),
      expect="sticky `listening` is loud and short-lived: a log line naming the refusing flag, cleared well "
             "under 10 min (today: silent, lasts to the ceiling)")
def tr18_sticky_listening():
    """A test-open sentence (listening, no recogniser), then forward-right: what does the relay say?"""
    try:
        post("/test/dictation/start")
        if not wait_for(lambda: state()["listening"], 3):
            return "FAIL", "/test/dictation/start never set listening"
        time.sleep(2.5)                      # past the 2 s stop dwell
        mark = log_mark()
        gesture("forward-right")
        time.sleep(1.5)
        text = log_since(mark)
        named = re.search(r"(refus\w*|ignor\w*|stuck|sticky|no-op).{0,80}(listening|settling|speculative|isRecording)"
                          r"|(listening|settling|speculative|isRecording).{0,80}(refus\w*|ignor\w*|stuck|sticky)", text)
        t0 = time.time()
        cleared = wait_for(lambda: not state()["listening"], 45, 0.25)
        note = (f"log after the gesture: {'names the flag' if named else 'silent about it'} "
                f"({len(text.splitlines())} line(s)); listening {'cleared after %.0f s' % (time.time() - t0) if cleared else 'still up 45 s later'}")
        if named and cleared:
            return "PASS", note
        if not named and not cleared:
            return "BUG", note
        return "FAIL", note
    finally:
        _settle_down()


@case("TR19", tags=("gesture",),
      expect="MicrophoneAfterACancel: after a cancel, a start 0.2 s later opens the microphone — EL and local")
def tr19_mic_after_cancel():
    """Start, cancel, start again 0.2 s later — three times per engine."""
    e0 = engine()["engine"]
    el = e0 if e0.startswith("eleven") else "eleven"
    results = {}
    try:
        mic_override(INJECT)
        for eng in (el, "whisper"):
            post("/engine", {"id": eng})
            if eng == "whisper" and _helper_up() is None:
                results[eng] = "helper down"
                continue
            reps = []
            for _ in range(3):
                o1, c1, _ = _open_then_cancel()
                time.sleep(0.2)
                o2, c2, t2 = _open_then_cancel()
                reps.append((o1, o2, t2))
                time.sleep(0.8)
            results[eng] = reps
        bad = {e: r for e, r in results.items() if not isinstance(r, list) or not all(o1 and o2 for o1, o2, _ in r)}
        note = "; ".join(f"{e}: " + (r if isinstance(r, str) else ", ".join(
            f"{'ok' if o1 else 'NO'}→{'ok %.2fs' % t2 if o2 else 'NO'}" for o1, o2, t2 in r)) for e, r in results.items())
        return ("PASS" if not bad else "FAIL"), note
    finally:
        _settle_down()
        _restore_engine(e0)


@case("TR21", tags=("tty",),
      expect="agent exited to the shell → '⛔️ refused', no delivery row in the outbox, still pastable "
             "(plan §3.11: today the row is written at commit)")
def tr21_shell_refused():
    """Bind a tab whose foreground is zsh and send a harmless sentence."""
    rw = _replace_wispr_off()
    tty = ""
    try:
        tty = osa('tell application "Terminal" to set t to do script ""',
                  'tell application "Terminal" to get tty of t').replace("/dev/", "")
        if not tty:
            return "SKIP", "could not open a shell tab"
        time.sleep(1.5)
        post("/bind", {"tty": tty})
        b = state().get("bound") or {}
        if b.get("tty") != tty:
            return "FAIL", f"bind to {tty} did not take: {b}"
        n0 = outbox_count()
        mark = log_mark()
        post("/test/dictation", {"text": "tr21-guard-probe please ignore"})
        wait_for(lambda: log_has(mark, r"⛔️ .*refused|⌨️ delivered to the bound terminal"), 20, 0.1)
        refused = log_has(mark, r"⛔️ .*refused")
        delivered = log_has(mark, r"⌨️ delivered to the bound terminal")
        n1 = outbox_count()
        ld = state().get("lastDelivery") or {}
        note = (f"guarded={b.get('guarded')}; refused={refused}; typed into zsh={delivered}; outbox rows +{n1 - n0}; "
                f"lastDelivery.to={ld.get('to')}")
        if delivered:
            return "FAIL", note + " — the guard let the sentence into the shell"
        if refused and n1 == n0:
            return "PASS", note
        if refused and n1 > n0:
            return "BUG", note + " — a refused sentence left a delivery receipt"
        return "FAIL", note
    finally:
        _settle_down()
        unbind()
        if tty:                              # by tty: zsh's prompt hooks may rename the window
            osa('tell application "Terminal"', 'repeat with w in windows', 'repeat with t in tabs of w',
                f'if tty of t is "/dev/{tty}" then', 'close w', 'return', 'end if',
                'end repeat', 'end repeat', 'end tell')
        _replace_wispr_restore(rw)


@case("TR22", tags=("tty",),
      expect="a spawn that fails re-offers the sentence; no spawn: receipt before the window exists")
def tr22_spawn_fails():
    """No fault hook makes SpawnTerminal fail from a desk."""
    return "SKIP", "no route or fault switch fails a spawn (SpawnTerminal has no test hook) — needs a new gap"


@case("TR27", tags=("gesture", "slow"),
      expect="50 start/cancel cycles within a second each: every start opens the mic, every cancel keeps its audio, "
             "no mic-<epoch>.wav collision or leftover, pid unchanged")
def tr27_filename_collision():
    """mic-<epoch>.wav is named by the second: hammer it."""
    try:
        mic_override(INJECT)
        pid0 = state()["pid"]
        t_start = time.time()
        mark = log_mark()
        opened = closed = 0
        starts = []
        for _ in range(50):
            starts.append(int(time.time()))
            o, c, _ = _open_then_cancel(hold=0.5, open_timeout=3)
            opened += o; closed += c
        text = log_since(mark)
        kept = len(re.findall(r"audio kept", text))
        errors = re.findall(r".*(could not keep the cancelled audio|did not start|could not open|recording failed).*", text)
        leftovers = [p for p in glob.glob(SHOTS + "/mic-*.wav") if os.path.getmtime(p) >= t_start]
        same_second = sum(1 for a, b in zip(starts, starts[1:]) if a == b)
        pid1 = state()["pid"]
        note = (f"{opened}/50 opened, {closed}/50 quiet after cancel, {kept} 'audio kept', {len(errors)} error line(s), "
                f"{len(leftovers)} leftover mic-*.wav, {same_second} back-to-back starts in the same second, pid {pid0}→{pid1}, "
                f"{time.time() - t_start:.0f} s")
        if opened == 50 and closed == 50 and kept == 50 and not errors and not leftovers and pid0 == pid1:
            return "PASS", note
        return "FAIL", note
    finally:
        _settle_down()


@case("TR28", expect="TCC identity: the launch line says bundle=ro.victorrentea.wispr-relay trusted=true eventTap=true "
                     "(the concurrent build-app.sh half is not run from the harness)")
def tr28_tcc_identity():
    """Read the running app's launch line and the installed bundle's identifier."""
    lines = [l for l in open(LOG, encoding="utf-8", errors="replace") if "accessibility trusted=" in l]
    if not lines:
        return "FAIL", "no launch line in relay.log"
    last = lines[-1].strip()
    pid = state()["pid"]
    try:
        started = subprocess.run(["ps", "-o", "lstart=", "-p", str(pid)], capture_output=True, text=True).stdout.strip()
        started_at = datetime.datetime.strptime(started, "%a %b %d %H:%M:%S %Y")
        logged_at = datetime.datetime.strptime(f"{started_at.year}-{last[:14]}", "%Y-%m-%d %H:%M:%S")
        fresh = logged_at >= started_at - datetime.timedelta(seconds=5)
    except Exception as e:
        started, fresh = f"? ({e})", None
    try:
        bid = plistlib.load(open(APP + "/Contents/Info.plist", "rb")).get("CFBundleIdentifier")
    except Exception as e:
        bid = f"unreadable ({e})"
    ok_line = all(t in last for t in ("trusted=true", "eventTap=true", "bundle=ro.victorrentea.wispr-relay"))
    note = f"last launch line: {last!r}; pid {pid} started {started}; line from this launch={fresh}; Info.plist id={bid}"
    if ok_line and fresh is not False and bid == "ro.victorrentea.wispr-relay":
        return "PASS", note
    return "FAIL", note
