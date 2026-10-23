"""Night tests (2026-10-23): the 🎤 marker and the ✍️ dictation editor on the REAL delivery path of a
plain (clean) local-engine dictation — 🔽 → (`back-right`, ⌃⌥⌘F5) at rest opens the microphone on the
Loopback, real speech (`CLIP_EN`) plays into it, 🔽 → again stops it, the installed app decodes it with
`fake_whisper_helper.py` (installed through `cases_chunks`' block) and pastes at the caret into
`WisprSink`. Not `/test/editor`: the words go through `deliver`'s caret branch.

    N1  mean -0.40, editor OFF                          → the sink ends with " 🎤"
    N2  mean -0.10, worst segment -0.90, editor OFF      → no 🎤 (the whole-take mean wins)
    N3  no mean, worst segment -0.40, editor OFF         → 🎤 (fallback to the worst segment)
    N4  mean -0.40, editor ON, "please deploy it to gvt and devox now"
                                                         → edited (JWT, Devoxx) + " 🎤"; clipboard = the paste;
                                                           editor.inFlight back to 0; busyWhy says "editing"
    N5  editor ON, "gvt token"                           → "JWT token", replacements, no model, fast
    N6  two plain sentences, the second started while the first decodes (Q12) → spoken order, own 🎤 each
    N7  a caret prompt (🔼 at rest, direct) with mean -0.40 (and worst -0.70) → no 🎤 on the prompt

Gestures are real chords: run under `hands-off` with HANDS_OFF=1. The editor switch is the
`dictationEditor` default (absent on this Mac = on); every case puts it back as it found it."""
import os, re, subprocess, threading, time
from harness import *
from harness import (get, post, state, log_mark, log_since, log_has, wait_for, gesture, mic_override, play,
                     CLIP_EN, relay_busy, tmo, case, BEFORE_CASE, CLEANUPS)
from cases_audio import INJECT, on_inject, _quiet
import cases_chunks as CC
import fake_whisper_helper as FW

TAGS = ("gesture", "audio", "local", "night")
DOM = "ro.victorrentea.wispr-relay"
OPENED = r"mic: recording through"
MIC = " 🎤"


# ---------------------------------------------------------------- the fake helper for these cases too
def _before(c):
    if c.get("module") in (CC.__name__, __name__):
        CC._install()
    elif CC._INST["on"]:
        CC._uninstall()


BEFORE_CASE[:] = [_before if f is CC._before else f for f in BEFORE_CASE]


# ---------------------------------------------------------------- the editor switch
def _editor_default():
    r = subprocess.run(["defaults", "read", DOM, "dictationEditor"], capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else None


EDITOR0 = _editor_default()   # None = absent (on)


def editor(on):
    """Write the switch (True/False) or put the original back (None); wait for `state.editor.on`."""
    if on is None:
        if EDITOR0 is None:
            subprocess.run(["defaults", "delete", DOM, "dictationEditor"], capture_output=True)
        else:
            subprocess.run(["defaults", "write", DOM, "dictationEditor", "-bool",
                            "true" if EDITOR0 == "1" else "false"], capture_output=True)
        want = EDITOR0 != "0"
    else:
        subprocess.run(["defaults", "write", DOM, "dictationEditor", "-bool", "true" if on else "false"],
                       capture_output=True)
        want = on
    return wait_for(lambda: (state().get("editor") or {}).get("on") == want, 5, 0.1)


CLEANUPS.append(lambda: editor(None) if _editor_default() != EDITOR0 else None)


# ---------------------------------------------------------------- the sink
def sink_text():
    return get("/test/sink").get("text") or ""


def clip():
    return subprocess.run(["pbpaste"], capture_output=True, text=True).stdout


class Sink:
    """Recorder on the Loopback, WisprSink open and key, emptied; all undone on exit."""
    def __enter__(self):
        mic_override(INJECT)
        post("/test/sink", {"on": True})
        time.sleep(0.3)
        post("/test/sink", {"key": True})
        time.sleep(0.3)
        post("/test/sink/clear")
        return self

    def __exit__(self, *exc):
        s = _quiet(state) or {}
        if s.get("listening") or s.get("isRecording"):
            _quiet(post, "/test/cancel")
        _quiet(wait_for, lambda: not relay_busy(), 30, 0.3)
        _quiet(post, "/test/sink", {"restore": True})
        time.sleep(0.2)
        _quiet(post, "/test/sink", {"on": False})
        _quiet(mic_override, None)
        return False


def pre():
    why = CC._pre()
    if why:
        return why
    if "editor" not in state():
        return "the installed build predates the dictation editor (state.editor)"
    return None


def plain(clipwav=CLIP_EN, wait_stop=True):
    """🔽 → start, the clip, 🔽 → stop. The mark, or (None, why)."""
    m = log_mark()
    gesture("back-right")
    if not wait_for(lambda: log_has(m, OPENED), tmo("mic_open"), 0.05):
        return None, "the microphone never opened (🔽 → at rest)"
    if not on_inject(m):
        post("/test/cancel")
        return None, f"the recorder did not open {INJECT}"
    time.sleep(0.4)
    play(clipwav, lead=0.3, tail=0.0)
    time.sleep(0.15)
    gesture("back-right")
    if wait_stop:
        wait_for(lambda: not state().get("isRecording"), tmo(3), 0.05)
    return m, None


def landed(n_chars=1, timeout=None):
    """The sink holds words and the relay is idle."""
    return wait_for(lambda: len(sink_text()) >= n_chars and not relay_busy(), timeout or tmo("terminal") + 6, 0.2)


def lines(m, pat):
    return [l for l in log_since(m).splitlines() if re.search(pat, l)][-6:]


def short(l):
    return l[-220:]


def one_plain(rules, editor_on, n_text=1):
    """One plain sentence with these fake rules. (sink text, mark, note) or raises."""
    with Sink():
        if not editor(editor_on):
            return None, None, f"state.editor.on never became {editor_on}"
        ep = FW.arm(rules=rules)
        m, why = plain()
        if not m:
            return None, None, why
        landed(n_text)
        time.sleep(0.6)
        txt = sink_text()
        reqs = [(r["kind"], r.get("rules")) for r in FW.answers(ep)]
        return txt, m, f"fake answers {reqs}"


def verdict_mic(want_mic, rules, editor_on):
    txt, m, note = one_plain(rules, editor_on)
    if txt is None:
        return "FAIL", note
    has = txt.endswith(MIC)
    ed = [short(l) for l in lines(m, r"✍️ editor")]
    ok = has == want_mic and txt.count("🎤") == (1 if want_mic else 0)
    return ("PASS" if ok else "FAIL"), (f"sink {txt!r} (ends with 🎤: {has}, want {want_mic}); {note}; "
                                        f"lastDelivery {(state().get('lastDelivery') or {})}; editor lines {ed}")


# ================================================================ N1–N3
@case("N1", TAGS, pre=pre, expect="editor OFF, fake mean_logprob -0.40 (worst segment -0.2) → the sink's text ends with ' 🎤'")
def n1():
    """Unsure whole take → 🎤."""
    return verdict_mic(True, [{"mean": -0.40}], False)


@case("N2", TAGS, pre=pre, expect="editor OFF, mean -0.10 but worst segment -0.90 → no 🎤 (the whole-take mean wins)")
def n2():
    """Sure mean, a bad segment → no 🎤."""
    return verdict_mic(False, [{"mean": -0.10, "logprob": -0.90}], False)


@case("N3", TAGS, pre=pre, expect="editor OFF, no mean_logprob, worst segment -0.40 → 🎤 (the fall-back)")
def n3():
    """No mean: the worst segment decides."""
    return verdict_mic(True, [{"logprob": -0.40}], False)


# ================================================================ N4
@case("N4", TAGS, pre=pre,
      expect="editor ON, mean -0.40, text 'please deploy it to gvt and devox now' → the sink gets the edited words "
             "(JWT, Devoxx) + ' 🎤'; pbpaste = what was pasted; editor.inFlight back to 0; busyWhy has 'editing' "
             "while the edit runs")
def n4():
    """Edited words keep the 🎤."""
    with Sink():
        if not editor(True):
            return "FAIL", "state.editor.on never became true"
        ep = FW.arm(rules=[{"mean": -0.40, "text": "please deploy it to gvt and devox now"}])
        seen = {"why": set(), "inflight": set(), "stop": False}

        def poll():
            while not seen["stop"]:
                s = _quiet(state) or {}
                for w in s.get("busyWhy") or []:
                    seen["why"].add(str(w))
                seen["inflight"].add((s.get("editor") or {}).get("inFlight"))
                time.sleep(0.04)
        th = threading.Thread(target=poll, daemon=True)
        m, why = plain(wait_stop=False)
        if not m:
            return "FAIL", why
        th.start()
        t_stop = time.time()
        landed(10, tmo("terminal") + 8)
        t_land = time.time()
        time.sleep(0.8)
        seen["stop"] = True
        th.join(2)
        txt, cb = sink_text(), clip()
        ed = [short(l) for l in lines(m, r"✍️ editor")]
        infl = (state().get("editor") or {}).get("inFlight")
        editing = any("edit" in w for w in seen["why"])
        ok = (txt.endswith(MIC) and "JWT" in txt and "Devoxx" in txt and cb.strip() == txt.strip()
              and infl == 0 and editing)
        return ("PASS" if ok else "FAIL"), (
            f"sink {txt!r}; pbpaste {cb!r} (same: {cb.strip() == txt.strip()}); inFlight now {infl}, seen "
            f"{sorted(x for x in seen['inflight'] if x is not None)}; busyWhy seen {sorted(seen['why'])}; "
            f"stop→sink {t_land - t_stop:.1f}s; editor lines {ed}; fake {[(a['kind'], a.get('decode_s')) for a in FW.answers(ep)]}")


# ================================================================ N5
@case("N5", TAGS, pre=pre,
      expect="editor ON, 2-word text 'gvt token' → 'JWT token' (no 🎤 at mean -0.10), log '(replacements, no model)', "
             "the editor line under ~50 ms")
def n5():
    """Under three words: local replacements only."""
    txt, m, note = one_plain([{"mean": -0.10, "text": "gvt token"}], True)
    if txt is None:
        return "FAIL", note
    ed = [short(l) for l in lines(m, r"✍️ editor")]
    ms = [int(x) for l in ed for x in re.findall(r" in (\d+) ms", l)]
    nomodel = any("replacements, no model" in l for l in ed)
    ok = "JWT token" in txt and "🎤" not in txt and nomodel and ms and max(ms) < 200
    return ("PASS" if ok else "FAIL"), f"sink {txt!r}; editor lines {ed}; {note}"


# ================================================================ N6
@case("N6", TAGS, pre=pre,
      expect="editor ON; A (mean -0.40, decode 7 s) stopped, B started ~1 s later while A decodes (mean -0.10), "
             "stopped → the sink has A then B, A with 🎤 and B without; inFlight 0 at the end")
def n6():
    """Two plain sentences queued: spoken order, each its own 🎤."""
    with Sink():
        if not editor(True):
            return "FAIL", "state.editor.on never became true"
        A, B = "the first sentence is about apples", "the second sentence is about oranges"
        ep = FW.arm(rules=[{"n": 1, "mean": -0.40, "text": A, "delay": 7},
                           {"n": 2, "mean": -0.10, "text": B}])
        m, why = plain(wait_stop=False)
        if not m:
            return "FAIL", why
        t_a = time.time()
        time.sleep(1.1)
        sents = (state().get("sentences") or [])
        m2 = log_mark()
        gesture("back-right")
        opened = wait_for(lambda: log_has(m2, OPENED), tmo("mic_open"), 0.05)
        if not opened:
            time.sleep(10)
            return "FAIL", (f"B's microphone never opened while A decoded; sentences then {sents}; "
                            f"log {[short(l) for l in lines(m2, r'🔽|back click|refused|🧼|in flight')]}; sink {sink_text()!r}")
        mid = state().get("sentences") or []
        time.sleep(0.4)
        play(CLIP_EN, lead=0.3, tail=0.0)
        time.sleep(0.15)
        gesture("back-right")
        t_b = time.time()
        a_pending = not any(a.get("n") == 1 for a in FW.answers(ep))
        wait_for(lambda: "oranges" in sink_text() and not relay_busy(), 30, 0.2)
        time.sleep(1.0)
        txt = sink_text()
        ia, ib = txt.find("apples"), txt.find("oranges")
        # Each sentence's own tail: A's text up to B's start, B's to the end.
        a_part = txt[:txt.lower().find("the second")] if "the second" in txt.lower() else txt[:ib]
        b_part = txt[len(a_part):]
        infl = (state().get("editor") or {}).get("inFlight")
        ed = [short(l) for l in lines(m, r"✍️ editor")]
        ok = (0 <= ia < ib and a_part.rstrip().endswith("🎤") and "🎤" not in b_part and infl == 0 and a_pending)
        return ("PASS" if ok else "FAIL"), (
            f"sink {txt!r}; A part {a_part!r}, B part {b_part!r}; A still decoding when B stopped: {a_pending} "
            f"(B stopped {t_b - t_a:.1f}s after A); sentences while B recorded {[(x.get('id'), x.get('state')) for x in mid]}; "
            f"inFlight {infl}; editor lines {ed}; fake {[(a['n'], a['kind'], a.get('t')) for a in FW.answers(ep)]}")


# ================================================================ N7
def _prompt(rules):
    with Sink():
        ep = FW.arm(rules=rules)
        m = log_mark()
        post("/test/gesture", {"name": "forward-click", "direct": True})
        if not wait_for(lambda: log_has(m, OPENED), tmo("mic_open"), 0.05):
            return None, None, "the caret prompt's microphone never opened"
        time.sleep(0.4)
        play(CLIP_EN, lead=0.3, tail=0.0)
        time.sleep(0.15)
        if state().get("listening") or state().get("isRecording"):
            post("/test/gesture", {"name": "forward-click", "direct": True})
        landed(5, tmo("terminal") + 6)
        time.sleep(1.0)
        txt = sink_text()
        return txt, m, f"lastDelivery {state().get('lastDelivery')}; fake {[(a['kind'], a.get('text')) for a in FW.answers(ep)]}"


@case("N7", TAGS, pre=pre,
      expect="a caret prompt (🔼 at rest, direct handler) with mean -0.40: no 🎤 anywhere in the prompt; "
             "then with worst segment -0.70 too: no 🎤, and what the envelope says about the low confidence")
def n7():
    """A prompt never carries the 🎤."""
    t1, m1, note1 = _prompt([{"mean": -0.40, "text": "what does this function return"}])
    if t1 is None:
        return "FAIL", note1
    time.sleep(1.5)
    t2, m2, note2 = _prompt([{"mean": -0.40, "logprob": -0.70, "text": "what does this method return"}])
    if t2 is None:
        return "FAIL", f"first {t1!r}; second: {note2}"
    warn1, warn2 = "low confidence" in t1, "low confidence" in t2
    ok = "🎤" not in t1 and "🎤" not in t2 and "function" in t1 and "method" in t2
    return ("PASS" if ok else "FAIL"), (f"prompt 1 {t1!r} (⚠️: {warn1}); prompt 2 {t2!r} (⚠️: {warn2}); "
                                        f"warn log {[short(l) for l in lines(m2, r'low confidence')]}; {note1}; {note2}")
