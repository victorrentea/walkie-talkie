"""The sentence queue (Q12, fix batch 6, 2026-09-26): a sentence may start while the previous one is
still transcribing; at most 2 in flight; each keeps its own envelope; deliveries strictly in the order
spoken; with Autosend off the panels one at a time, in order; a third start refused with a flash;
🔼← cancels the recording sentence, or with none recording the most recent one in flight.

Real audio through our Loopback (like `cases_audio`), the witness tab bound, faults from
`POST /test/eleven` — `{"fail": "delay", "delayMs": n}` is the real call made n ms late (batch 6) —
and `POST /test/autosend {"on"}` (gap G6, batch 6, this run only). Every case SKIPs on a build without
`state.sentenceQueue` (installed before batch 6) or with the queue off (`WT_SENTENCE_QUEUE=0`).

Not run the night it was written (the teacher batch had the Mac): run after the morning install,
`HANDS_OFF=1 python3 evals/plan/harness.py --only 'Q[1-6]'` under the hands-off locks."""
import re, time
from harness import *
from cases_audio import pre, rig, delivered, settle_out, on_inject, not_inject, when, count, _quiet

CLIP_A = CLIP_EN                     # "If I dictate now, how good is this dictation, I wonder?"
A_WORD = "wonder"                    # in A's words, not in B's
OPENED = r"mic: recording through"
PARKED = r"🧾 sentence #\d+ .*goes on transcribing behind the next one"
WAITS = r"🧾 sentence #\d+ landed before #\d+ — it waits its turn"
REFUSED = r"start refused — two sentences are already in flight"


def _queue_off():
    s = state()
    if "sentenceQueue" not in s:
        return "the installed build predates the sentence queue (no state.sentenceQueue) — install batch 6"
    if not s["sentenceQueue"]:
        return "the sentence queue is off (WT_SENTENCE_QUEUE=0)"
    return None


def _skip():
    return pre() or _queue_off()


def _open(mark, timeout=8):
    """F10 and wait for a microphone opened after `mark`."""
    n0 = count(mark, OPENED)
    post("/test/gesture", {"name": "forward-right", "direct": True})
    return wait_for(lambda: count(mark, OPENED) > n0, timeout, 0.05)


def _say(wav, seconds=None):
    time.sleep(0.4)
    play(wav, seconds=seconds)
    time.sleep(1.0)


def _rows_since(n0):
    return outbox_tail(max(0, outbox_count() - n0)) if outbox_count() > n0 else []


def _two_delivered(n0, timeout=120):
    return wait_for(lambda: outbox_count() >= n0 + 2, timeout, 0.3)


@case("Q1", ("audio", "gesture"),
      expect="a start while the last sentence transcribes opens the microphone (it used to be refused: batch 3); "
             "state.sentences lists 2; both sentences delivered, the first first")
def q1():
    """Start during transcription is allowed."""
    why = _skip()
    if why: return "SKIP", why
    with rig():
        post("/test/eleven", {"fail": "delay", "delayMs": 6000})
        n0 = outbox_count()
        m = log_mark()
        if not _open(m): return "FAIL", "the first microphone never opened"
        if not on_inject(m): return not_inject(m)
        _say(CLIP_A)
        post("/test/gesture", {"name": "forward-click", "direct": True})                       # stop A — its upload is 6 s late
        time.sleep(1.2)                                # past the 0.8 s same-click window
        opened2 = _open(m)
        s = state()
        listed = len(s.get("sentences") or [])
        parked = log_has(m, PARKED)
        if opened2:
            _say(CLIP_EN_LONG, seconds=4)
            post("/test/gesture", {"name": "forward-click", "direct": True})
        both = _two_delivered(n0)
        rows = _rows_since(n0)
        first_is_a = bool(rows) and A_WORD in (rows[0].get("text") or "").lower()
        note = (f"second microphone opened={bool(opened2)}, parked line={parked}, sentences listed={listed}, "
                f"delivered {len(rows)} (first is A={first_is_a})")
        return ("PASS" if opened2 and parked and listed == 2 and both and first_is_a else "FAIL"), note


@case("Q2", ("audio", "gesture"),
      expect="with two sentences in flight a third start is refused: the `two sentences are already in flight` "
             "line and the flash, no third microphone; both still delivered")
def q2():
    """The third start is refused."""
    why = _skip()
    if why: return "SKIP", why
    with rig():
        post("/test/eleven", {"fail": "delayx2", "delayMs": 12000})   # A's and B's uploads both late
        n0 = outbox_count()
        m = log_mark()
        if not _open(m): return "FAIL", "the first microphone never opened"
        if not on_inject(m): return not_inject(m)
        _say(CLIP_A)
        post("/test/gesture", {"name": "forward-click", "direct": True})
        time.sleep(1.2)
        if not _open(m): return "FAIL", "the second microphone never opened"
        _say(CLIP_EN_LONG, seconds=3)
        post("/test/gesture", {"name": "forward-click", "direct": True})
        time.sleep(1.2)
        opened_before = count(m, OPENED)
        post("/test/gesture", {"name": "forward-right", "direct": True})                       # the third start
        refused = wait_for(lambda: log_has(m, REFUSED), 3, 0.05)
        time.sleep(1.0)
        third = count(m, OPENED) > opened_before
        n_listed = len(state().get("sentences") or [])
        both = _two_delivered(n0)
        note = f"refused line={bool(refused)}, a third microphone opened={third}, sentences listed={n_listed}, both delivered={bool(both)}"
        return ("PASS" if refused and not third and n_listed == 2 and both else "FAIL"), note


@case("Q3", ("audio", "gesture"),
      expect="the second sentence lands first (the first's upload `delay` 9 s): it waits (`landed before`), and "
             "the outbox/witness get A then B")
def q3():
    """Order kept when the second lands first."""
    why = _skip()
    if why: return "SKIP", why
    with rig():
        post("/test/eleven", {"fail": "delay", "delayMs": 9000})    # only A's upload
        n0 = outbox_count()
        m = log_mark()
        if not _open(m): return "FAIL", "the first microphone never opened"
        if not on_inject(m): return not_inject(m)
        _say(CLIP_A)
        post("/test/gesture", {"name": "forward-click", "direct": True})
        time.sleep(1.2)
        if not _open(m): return "FAIL", "the second microphone never opened"
        _say(CLIP_EN_LONG, seconds=3)
        post("/test/gesture", {"name": "forward-click", "direct": True})
        waited = wait_for(lambda: log_has(m, WAITS), 12, 0.1)
        both = _two_delivered(n0)
        rows = _rows_since(n0)
        order = [("A" if A_WORD in (r.get("text") or "").lower() else "B") for r in rows]
        a_seen = A_WORD in witness_text().lower()
        note = f"B waited={bool(waited)}, outbox order={order}, witness has A={a_seen}"
        return ("PASS" if waited and both and order[:2] == ["A", "B"] else "FAIL"), note


@case("Q4", ("audio", "gesture"),
      expect="🔼← while B records and A transcribes cancels B (the recording), and A is still delivered")
def q4():
    """Cancel with a sentence recording: that one."""
    why = _skip()
    if why: return "SKIP", why
    with rig():
        post("/test/eleven", {"fail": "delay", "delayMs": 6000})
        n0 = outbox_count()
        m = log_mark()
        if not _open(m): return "FAIL", "the first microphone never opened"
        if not on_inject(m): return not_inject(m)
        _say(CLIP_A)
        post("/test/gesture", {"name": "forward-click", "direct": True})
        time.sleep(1.2)
        if not _open(m): return "FAIL", "the second microphone never opened"
        time.sleep(1.5)
        post("/test/cancel")                        # 🔼← — cancel
        cancelled = wait_for(lambda: log_has(m, r"dictation cancelled"), 3, 0.05)
        one = wait_for(lambda: outbox_count() >= n0 + 1, 60, 0.3)
        time.sleep(3)
        rows = _rows_since(n0)
        a_only = len(rows) == 1 and A_WORD in (rows[0].get("text") or "").lower()
        note = f"cancel line={bool(cancelled)}, delivered {len(rows)} row(s), A only={a_only}"
        return ("PASS" if cancelled and one and a_only else "FAIL"), note


@case("Q5", ("audio", "gesture"),
      expect="🔼← with nothing recording and two in flight cancels the most recent (B, disowned), A delivered")
def q5():
    """Cancel with none recording: the most recent in flight."""
    why = _skip()
    if why: return "SKIP", why
    with rig():
        post("/test/eleven", {"fail": "delayx2", "delayMs": 7000})
        n0 = outbox_count()
        m = log_mark()
        if not _open(m): return "FAIL", "the first microphone never opened"
        if not on_inject(m): return not_inject(m)
        _say(CLIP_A)
        post("/test/gesture", {"name": "forward-click", "direct": True})
        time.sleep(1.2)
        if not _open(m): return "FAIL", "the second microphone never opened"
        _say(CLIP_EN_LONG, seconds=3)
        post("/test/gesture", {"name": "forward-click", "direct": True})
        time.sleep(1.0)
        post("/test/cancel")                        # 🔼← — nothing recording
        cancelled = wait_for(lambda: log_has(m, r"dictation cancelled"), 3, 0.05)
        wait_for(lambda: outbox_count() >= n0 + 1, 60, 0.3)
        time.sleep(10)                                 # B's late answer, if it were delivered, is in by now
        rows = _rows_since(n0)
        a_only = len(rows) == 1 and A_WORD in (rows[0].get("text") or "").lower()
        note = f"cancel line={bool(cancelled)}, delivered {len(rows)} row(s), A only={a_only}"
        return ("PASS" if cancelled and a_only else "FAIL"), note


@case("Q6", ("audio", "gesture"),
      expect="Autosend off: the panels come one at a time, in order — A's panel first while B waits (`waits for the "
             "prompt panel`), B's after A's is sent (POST /test/prompt send)")
def q6():
    """Panels in order with Autosend off."""
    why = _skip()
    if why: return "SKIP", why
    was = state().get("autosend")
    try:
        post("/test/autosend", {"on": False})
        with rig():
            post("/test/eleven", {"fail": "delay", "delayMs": 6000})
            n0 = outbox_count()
            m = log_mark()
            if not _open(m): return "FAIL", "the first microphone never opened"
            if not on_inject(m): return not_inject(m)
            _say(CLIP_A)
            post("/test/gesture", {"name": "forward-click", "direct": True})
            time.sleep(1.2)
            if not _open(m): return "FAIL", "the second microphone never opened"
            _say(CLIP_EN_LONG, seconds=3)
            post("/test/gesture", {"name": "forward-click", "direct": True})
            first = wait_for(lambda: (state().get("prompt") or {}).get("held"), 30, 0.1)
            p1 = state().get("prompt") or {}
            first_is_a = A_WORD in str(p1).lower()
            b_waits = wait_for(lambda: log_has(m, r"waits for the prompt panel|waits its turn"), 5, 0.1)
            post("/test/prompt", {"do": "send"})
            second = wait_for(lambda: (state().get("prompt") or {}).get("held") and A_WORD not in str(state().get("prompt")).lower(), 30, 0.1)
            post("/test/prompt", {"do": "send"})
            both = _two_delivered(n0, 30)
            rows = _rows_since(n0)
            order = [("A" if A_WORD in (r.get("text") or "").lower() else "B") for r in rows]
            note = (f"first panel is A={first_is_a}, B waited={bool(b_waits)}, second panel={bool(second)}, "
                    f"outbox order={order}")
            return ("PASS" if first and first_is_a and b_waits and second and order[:2] == ["A", "B"] else "FAIL"), note
    finally:
        _quiet(post, "/test/autosend", {"on": bool(was)})
