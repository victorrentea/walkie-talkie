"""Words in a language nobody spoke (2026-11-04, `TranscriptGuard`). Victor: *"se mai întâmplă
uneori să vină prompt-ul în altă limbă"*.

No microphone: `POST /test/transcript-guard {"replay"}` calls the engine's `didTranscribe` and
`didEnd(.delivered)`, in that order, with a garbled text on a real voice WAV. The hold, the fake Scribe,
the real local model and the delivery into the witness tab all run. `engine="wispr"`: Engine ≠ local.

    TF1  a foreign answer → Scribe's words land in the tab, via scribe-guard, nothing Cyrillic
    TF2  the guard off → the garble lands as it came (TF1's garble really was in the way)
    TF3  Scribe fails → the local model's words land, via local-guard
    TF4  the local model's own foreign words → Scribe overrules them, via scribe-guard
"""
import contextlib
import os
import re
import wave
import time
from harness import *
from cases_audio import last_delivery, settle_out

GARBLE = "Я покупал в этом магазине только молочные продукты и овощи."
CYRILLIC = re.compile(r"[Ѐ-ӿ]")
LOG = HOME + "/transcript-guard.jsonl"
_COV = covers("wispr", "local", "delivery", extra=("TranscriptGuard",))


@contextlib.contextmanager
def witness():
    """The witness bound; no recorder involved, so no Loopback either."""
    try:
        bind_witness()
        witness_clear()
        yield
    finally:
        unbind()


def _rows():
    return sum(1 for _ in open(LOG)) if os.path.exists(LOG) else 0


def _replay(**extra):
    fake_script(CLIP_SPEECH, None)
    t0 = now_iso()
    with wave.open(CLIP_SPEECH) as w:
        seconds = w.getnframes() / w.getframerate()
    code, r = post("/test/transcript-guard", dict(text=GARBLE, replay=CLIP_SPEECH, duration=seconds, **extra))
    if not r.get("replayed"):
        return None, r
    d = wait_for(lambda: last_delivery(t0), 30, 0.2)
    if not d and (state().get("prompt") or {}).get("held"):
        post("/test/prompt", {"do": "send"})
        d = wait_for(lambda: last_delivery(t0), 15, 0.2)
    settle_out(30)
    return d, r


@case("TF1", ("delivery",), covers=_COV, engine="wispr",
      expect="a Cyrillic answer never reaches the tab: via scribe-guard, Latin words delivered, one row in transcript-guard.jsonl")
def tf1():
    return _mended("scribe-guard")


def _mended(via, **extra):
    with witness():
        post("/test/transcript-guard", {"on": True})
        m, rows0 = log_mark(), _rows()
        d, r = _replay(**extra)
        text = wait_for(lambda: witness_text().strip() or None, 15, 0.3) or ""
        held = log_has(m, r"🌐 .*words look wrong")
        note = f"via {(d or {}).get('via')}; held {held}; rows {rows0}→{_rows()}; answer {r}; witness {text[:90]!r}"
        ok = ((d or {}).get("via") == via and held and _rows() == rows0 + 1
              and len(text) > 20 and not CYRILLIC.search(text))
        return ("PASS" if ok else "FAIL"), note


@case("TF2", ("delivery",), covers=_COV, engine="wispr",
      expect="with the guard off the same garble is delivered as it came, nothing held")
def tf2():
    with witness():
        post("/test/transcript-guard", {"on": False})
        try:
            m = log_mark()
            d, r = _replay()
            text = wait_for(lambda: witness_text().strip() or None, 15, 0.3) or ""
            held = log_has(m, r"🌐 .*words look wrong")
            note = f"via {(d or {}).get('via')}; held {held}; answer {r}; witness {text[:90]!r}"
            ok = (d or {}).get("via") != "local-guard" and not held and CYRILLIC.search(text)
            return ("PASS" if ok else "FAIL"), note
        finally:
            post("/test/transcript-guard", {"on": True})


@case("TF3", ("delivery",), covers=_COV, engine="wispr",
      expect="Scribe answers 500 twice: the real local model hears it, via local-guard")
def tf3():
    post("/test/eleven", {"fail": "500x2"})
    try:
        return _mended("local-guard")
    finally:
        post("/test/eleven", {"clear": True})


@case("TF4", ("delivery",), covers=_COV, engine="wispr",
      expect="the local model's own Cyrillic is overruled by Scribe, via scribe-guard")
def tf4():
    return _mended("scribe-guard", local=True)
