"""**Wispr Flow queues sentences** — QW0–QW4, QW6, QW7 (2026-10-22), for c67d0be + 90e7304 (*the next
sentence is recorded now and handed to Wispr when it is free*, `.claude/rules/dictation-source.md`,
*Wispr queues sentences*). Until these ran the feature was unit-tested only (`WisprDeferralTests`).

**Why a fake Wispr.** The first version (report 2026-10-22 00:50) drove his real Wispr and froze its
main process (SIGSTOP) to keep A in flight. It never deferred B: Wispr finished A's row ≈ 0.5 s after
its microphone closed, before the freeze landed (0.8–1.0 s after A's stop) and before B started at
+1.1 s; freezing earlier is no fix (with Wispr frozen while its microphone is still open,
`verifyStopTook` posts a second toggle that Wispr runs after the thaw). So the deferral cases are
**desk cases** (`evals/plan/cases_wispr.py`, `desk()`): a fresh fake `History` read through a
`WT_WISPR_DB` line in `elevenlabs.env` (`# fake-wispr:` marks, removed by its `CLEANUPS`), **Wispr's
chords muted** (`POST /test/wispr-chord {"mute": true}` — his real Wispr never receives one), the
relay's recorder on the Loopback `🧪 WT Inject`, Wispr's microphone faked through the 100 ms poll
(`POST /test/wispr {"on", "via": "poll"}`). The case holds A's row at `processing` for as long as it
wants, so B **is** deferred (`take N deferred`); finishing A's row releases it (`take N released`);
B's row is then inserted and driven to `formatted` with B's words. Chords are counted from the relay's
own lines (`🧪 fn ⌃ Space muted …`), one per chord it would have posted.

Starts and stops go through the gesture handlers (`/test/gesture {"direct": true}`: `forward-right` =
`toggleDictation`, bound → a prompt into the witness; `forward-click` = the 🔼 that ends it). At a
desk Wispr's input never runs, so the bridge stays held and a relay stop waits 2.5 s for that
input before the (muted) stop chord and the close — ≈ 3 s measured. The cases time
B from **the relay's close of A** (`listening` false), not from the gesture.

Every case: the witness tab bound, Autosend on, **Backup Local Pre-Transcribe off** (its countdown
would hand A to the local model while the case holds A's row) — put back; open sentences cancelled,
fake rows still open dismissed, the case's own Recover staging drained into the witness.

    QW0  LIVE smoke, his real Wispr, no freeze: A (12 s) then B (3.5 s) at +1.1 s → both delivered, in
         order, `via: wispr-history`, nothing in the sink (deferred or not: Wispr is usually free by then)
    QW1  A's row held `processing`; B deferred; A's row finished while B still talks → `released … he is
         still talking`; A then B, both `via: wispr-history`, B's words whole, B's WAV voiced
    QW2  B STOPPED while deferred (`stopped … it waits for Wispr Flow`), then A finished → `released …
         his stop came`, the start AND the stop chord after it; A then B, B whole
    QW3  B stopped and deferred; POST /test/cancel (🔼←) → `take N cancelled while it waited`, Recover
         holds B's WAV; A delivered alone; only A's two chords ever posted
    QW4  B still recording and deferred; POST /test/local-now (⌘⌃X) → B `via: local-forced`, waits
         behind A, A `via: wispr-history`; A then B; only A's two chords
    QW6  📻 `readyForNext` up 0.7–1.1 s after A's close while A's row is in flight; B at +1.1 s opens,
         deferred — no Q16 flash *Wispr Flow takes one sentence at a time*, no `start refused`
    QW7  `WT_WISPR_QUEUE=0` (read ONCE, at launch) → the line in `elevenlabs.env` and a gated restart
         (`relay-restart.sh`), the same fake rows: B refused with the Q16 flash, no microphone for it,
         A delivered alone; then the line out and a second restart. **Opt-in: `WT_QW_RESTART=1`**.
    (QW5 — Wispr killed while B waits — is not here: it kills his Wispr.)

Run (under the locks — QW0 posts real chords into his Wispr and the sink holds the keyboard focus):

    hands-off run "Wispr queue desk cases on a fake Wispr database — chords muted, ~6 min" -- \\
      env HANDS_OFF=1 /Library/Frameworks/Python.framework/Versions/3.12/bin/python3 \\
      evals/plan/harness.py --only 'QW*'
"""
import os, re, sqlite3, subprocess, threading, time, urllib.parse
from harness import *
import fake_wispr_db as fw
from cases_wispr import needs_wispr, needs_desk, desk, live
from cases_wispr_soak import ref_words, recall, _tokens, _quiet

TAGS = ("wispr", "queue", "desk", "gesture", "audio")
TAGS_LIVE = ("wispr", "queue", "live", "gesture", "audio")
_COV = covers("wispr", "gesture", "recorder", "delivery", "chip",
              extra=("WisprDeferral", "AudioBridge", "BridgePacer", "TakeSerial"))
_COV_LOCAL = _COV + covers("local")
_COV_RESTART = _COV + covers("restart")

GAP = float(os.environ.get("WT_QW_GAP", "1.1"))              # B's start after A's close: past the 0.8 s same-click beat
RESTART_OK = os.environ.get("WT_QW_RESTART") == "1"
INJ = LOOPBACK.replace("🧪 ", "")
CLIP_A = CLIP_EN                                             # 3.5 s — A's words come from its fake row
CLIP_B = CLIP_EN                                             # 3.5 s, "If I dictate now, how good is this dictation, I wonder?"
A_TEXT = "Queue alpha: the first sentence of this case, held in flight by the test."
B_TEXT = "Queue bravo: the second sentence, recorded while the first was still being transcribed."
B_VOICED_MIN = float(os.environ.get("WT_QW_B_VOICED", "1.5"))  # CLIP_B's voiced seconds, the take whole
ENV_MARK = "# wispr-queue: written by evals/plan/cases_wispr_queue.py, removed after its case"

OPENED = r"mic: recording through"
CHORD = r"🧪 fn ⌃ Space muted by POST /test/wispr-chord|⌨️ fn ⌃ Space posted"
CLOSED = r"🎙️ the microphone is closed"
VOICED = r"wispr meter(?: \(take (\d+), deferred\))?: ([\d.]+) s voiced"
DEFERRED = r"🧾 wispr: take (\d+) deferred — ([^\n]*)"
RELEASED = r"🧾 wispr: take (\d+) released — posting the start chord ([\d.]+) s after his gesture([^\n]*)"
STOPPED_WAITING = r"🧾 wispr: take (\d+) stopped ([\d.]+) s after his gesture — it waits for Wispr Flow"
GAVE_UP = r"🧾 wispr: take (\d+) will not be Wispr Flow's — ([^\n]*)"
CANCELLED_DEFERRED = r"🗑️ take (\d+) cancelled while it waited for Wispr Flow"
LOCAL_DEFERRED = r"💻 ⌘⌃X — take (\d+) was waiting for Wispr Flow"
WAITS_TURN = r"🧾 sentence #\d+ landed before #\d+ — it waits its turn"
REFUSED = r"🚫 start refused — ([^\n]*)|🧾 wispr: start refused[^\n]*"
Q16 = "one sentence at a time"

# What this module changed and must put back (also through `CLEANUPS`, whatever a case did).
QW = {"sink": False, "auto0": None, "autosend0": None, "env": False}


# ---------------------------------------------------------------- small helpers
def count(mark, pattern):
    return len(re.findall(pattern, log_since(mark)))

def _excerpt(mark, n=900):
    return " | ".join(re.findall(r"(?:🧾 wispr|🗑️ take|💻 ⌘⌃X|🚫 start refused|📦 delivery|🔀 the stop)[^\n]*",
                                 log_since(mark)))[:n]

def _device(mark):
    m = re.findall(r"mic: recording through ([^\n]+)", log_since(mark))
    return m[-1].strip() if m else ""

def _sleep_until(t):
    d = t - time.time()
    if d > 0:
        time.sleep(d)

def _rows(n0):
    n = outbox_count()
    return outbox_tail(n - n0) if n > n0 else []

def _via(r):
    return (r.get("delivery") or {}).get("via")

def _takes():
    try:
        return ((state().get("wisprLive") or {}).get("takes")) or {}
    except Exception:
        return {}

def _deferred_now():
    """`wisprLive.takes.deferred` — the take waiting for Wispr, or {}."""
    return _takes().get("deferred") or {}

def _wispr_mic():
    """Wispr's last named microphone, read-only from its real History (what `WisprHistory.lastNamedMic`
    reads). None when unreadable."""
    try:
        con = sqlite3.connect("file:%s?mode=ro" % urllib.parse.quote(fw.REAL), uri=True, timeout=2)
        try:
            row = con.execute("select micDevice from History where coalesce(micDevice, '') != '' "
                              "order by rowid desc limit 1").fetchone()
        finally:
            con.close()
        return row[0] if row else None
    except Exception:
        return None

def _staged_after(t0):
    """`state.recoverable` if it was staged after `t0` (expiresAt − 300 s), else None."""
    import datetime
    rec = state().get("recoverable") or {}
    try:
        at = datetime.datetime.fromisoformat(str(rec.get("expiresAt")).replace("Z", "+00:00")).timestamp() - 300
    except Exception:
        return None
    return rec if rec.get("path") and at >= t0 - 0.5 else None

def _who(text):
    """A's and B's fake rows carry `alpha` / `bravo`; anything else (the local model on B's clip) is B."""
    toks = set(_tokens(text))
    return "A" if "alpha" in toks else "B"

def _whole(text, ref):
    got = set(_tokens(text))
    return all(t in got for t in _tokens(ref))

def _pos(txt, pattern, take):
    """Offset of the first `pattern` line for `take` in `txt`, or -1."""
    for mm in re.finditer(pattern, txt):
        if int(mm.group(1)) == take:
            return mm.start()
    return -1

def _line_at(txt, p):
    return txt[p: txt.find("\n", p)] if p >= 0 else ""

def _voiced_after(txt, p):
    """The last `wispr meter … s voiced` after offset `p` (B's), or None."""
    v = re.findall(VOICED, txt[max(p, 0):])
    return float(v[-1][1]) if v else None

def _ab_rows(ctx, want, timeout):
    """Rows since the case began once `want` are in (or the timeout), then 3 s for a stray copy."""
    n0 = ctx["n0"]
    wait_for(lambda: len(_rows(n0)) >= want, timeout, 0.3)
    time.sleep(3.0)
    return _rows(n0)

def _sink_text():
    try:
        return get("/test/sink").get("text") or ""
    except Exception:
        return ""

def _leak_note():
    t = _sink_text()
    leaked = len(_tokens(t)) >= 2
    return leaked, ("LEAK: the sink caught %r" % t[:120]) if leaked else "sink empty"


# ---------------------------------------------------------------- preconditions
def _pre_desk(restart=False):
    def pre():
        why = needs_desk()
        if why:
            return why
        s = state()
        takes = (s.get("wisprLive") or {}).get("takes")
        if not isinstance(takes, dict):
            return "the installed build predates the Wispr queue (no wisprLive.takes — c67d0be)"
        if not s.get("sentenceQueue"):
            return "the sentence queue is off (WT_SENTENCE_QUEUE=0)"
        if restart:
            if not RESTART_OK:
                return "needs two gated app restarts (WT_WISPR_QUEUE is read at launch) — set WT_QW_RESTART=1"
            if not os.path.exists(os.path.join(REPO, "relay-restart.sh")):
                return "no relay-restart.sh at %s" % REPO
        elif not takes.get("queues"):
            return "the app does not queue Wispr sentences (WT_WISPR_QUEUE=0 or WT_BRIDGE=0 at its launch)"
        try:
            if not loopback_alive():
                return "%s pass-thru is dead (440 Hz check)" % LOOPBACK
        except Exception as e:
            return "%s check failed: %s: %s" % (LOOPBACK, type(e).__name__, e)
        return None
    return pre

def _pre_live():
    why = needs_wispr()
    if why:
        return why
    s = state()
    lv = s.get("wisprLive")
    if lv is None:
        return "the installed build has no Wispr test hooks (/test/state.wisprLive)"
    if lv.get("db"):
        return "a fake History is in force (%s) — a desk case's WT_WISPR_DB line is still in elevenlabs.env" % lv["db"]
    if s.get("tapFailingOpen"):
        return "the firewall tap is failing open — Wispr's ⌘V would reach the front app"
    mic = _wispr_mic()
    if mic and not re.search(r"walkie|feed", mic, re.I):
        return "Wispr Flow's microphone is %r, not From Walkie — the bridge cannot feed it" % mic
    try:
        if not loopback_alive():
            return "%s pass-thru is dead (440 Hz check)" % LOOPBACK
    except Exception as e:
        return "%s check failed: %s: %s" % (LOOPBACK, type(e).__name__, e)
    return None


# ---------------------------------------------------------------- what a case changes, and puts back
def _sink_off():
    if QW["sink"]:
        try:
            post("/test/sink", {"restore": True})
            time.sleep(0.2)
            post("/test/sink", {"on": False})
        except Exception:
            pass
        QW["sink"] = False

def _auto_back():
    """His Backup Local Pre-Transcribe (written to the defaults) and Autosend (this run only) back."""
    if QW["auto0"] is not None:
        try:
            post("/test/local-auto", {"on": bool(QW["auto0"])})
        except Exception:
            pass
        QW["auto0"] = None
    if QW["autosend0"] is not None:
        try:
            post("/test/autosend", {"on": bool(QW["autosend0"])})
        except Exception:
            pass
        QW["autosend0"] = None

def _env_block(lines):
    """Our block in `elevenlabs.env` set to `lines` (or removed) — everything else byte for byte."""
    try:
        cur = open(ELEVEN_ENV, encoding="utf-8").read().splitlines()
        mode = os.stat(ELEVEN_ENV).st_mode & 0o777
    except FileNotFoundError:
        cur, mode = [], 0o600
    keep, inside = [], False
    for l in cur:
        if l.startswith(ENV_MARK):
            inside = not l.endswith("(end)")
            continue
        if not inside:
            keep.append(l)
    if lines:
        keep += [ENV_MARK] + list(lines) + [ENV_MARK + " (end)"]
    if keep != cur:
        tmp = ELEVEN_ENV + ".qw-tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            f.write("\n".join(keep) + ("\n" if keep else ""))
        os.chmod(tmp, mode)
        os.replace(tmp, ELEVEN_ENV)
    QW["env"] = bool(lines)

def _env_present():
    try:
        return ENV_MARK in open(ELEVEN_ENV, encoding="utf-8").read()
    except OSError:
        return False

def _queues():
    try:
        return bool(_takes().get("queues"))
    except Exception:
        return None

def _drain_recover():
    """The case's own cancelled WAV into the witness (`/test/recover`): staged, it holds `busy` five
    minutes and the restart gate. Only a staging this case made."""
    try:
        s = state()
        if s.get("recoverable") and s.get("bound") and recover_is_ours(s):
            m = log_mark()
            post("/test/recover")
            wait_for(lambda: log_has(m, r"📦 delivery:|No speech|no speech|No words"), tmo("q14_terminal") + 10, 0.5)
            _quiet(20)
    except Exception as e:
        print("  (qw: recover drain: %s: %s)" % (type(e).__name__, e))

def _restart():
    """`relay-restart.sh` — gated (5 s quiet, nothing in flight); never `--force`. (ok, note)"""
    _drain_recover()
    try:
        p = subprocess.run(["./relay-restart.sh", "--max-wait", "180"], cwd=REPO, capture_output=True,
                           text=True, timeout=320)
    except Exception as e:
        return False, "relay-restart.sh: %s: %s" % (type(e).__name__, e)
    tail = (p.stdout.strip().splitlines() or [""])[-1][:160]
    if p.returncode != 0:
        return False, "relay-restart.sh exit %d: %s" % (p.returncode, tail)
    if not wait_for(lambda: get("/up", timeout=2).get("ok"), 60, 0.5):
        return False, "no relay on port %s after the restart" % PORT
    wait_for(lambda: "wisprLive" in state(), 30, 0.5)
    return True, "restarted (%s)" % tail

def _qw_cleanup():
    """After every case (harness `CLEANUPS`): the sink closed, his Backup Local Pre-Transcribe back, our
    env line out — and the app restarted if it still reads the queue as off."""
    _sink_off()
    _auto_back()
    if QW["env"] or _env_present():
        _env_block(None)
        if _queues() is False and RESTART_OK:
            ok, note = _restart()
            print("  (qw cleanup: WT_WISPR_QUEUE line removed, restart → %s)" % note)

CLEANUPS.append(_qw_cleanup)


# ---------------------------------------------------------------- the rig
def _rig(db=None, sink=False):
    """The witness bound and cleared, the recorder on the Loopback, Autosend on, Backup Local off;
    `sink` (QW0 only): the relay's sink as the key window, so a ⌘V past the firewall lands there."""
    s = state()
    ctx = {"notes": [], "db": db, "open_rows": set()}
    if sink and (s.get("wisprLive") or {}).get("chordsMuted"):
        post("/test/wispr-chord", {"mute": False})
        ctx["notes"].append("chords were muted — unmuted")
    if engine().get("engine") != "wispr" and not set_engine("wispr"):
        raise RuntimeError("POST /engine wispr was not taken")
    bind_witness()
    witness_clear()
    r = mic_override(LOOPBACK) or {}
    if INJ.lower() not in str(r.get("override") or r).lower():
        ctx["notes"].append("mic override answer %s" % r)   # `_start` checks the device that really opened
    if s.get("autosend") is not None:
        QW["autosend0"] = bool(s.get("autosend"))
    post("/test/autosend", {"on": True})
    if (s.get("localAuto") or {}).get("on"):
        QW["auto0"] = True
        post("/test/local-auto", {"on": False})
    if sink:
        post("/test/sink", {"on": True})
        QW["sink"] = True
        time.sleep(0.3)
        code, rr = post("/test/sink", {"key": True})
        if code != 200:
            raise RuntimeError("the sink refused the key window: %s" % rr)
        time.sleep(0.3)
        post("/test/sink/clear")
    ctx.update(t0=time.time(), n0=outbox_count(), mark=log_mark())
    return ctx

def _teardown(ctx):
    """Every fake row still open dismissed (its capture lets go), whatever is still open cancelled
    (≤ 3 cancels: two may be in flight), the relay let settle, our Recover staging drained; the sink,
    Autosend and Backup Local back."""
    try:
        db = ctx.get("db")
        if db:
            for rid in sorted(ctx.get("open_rows") or ()):
                try:
                    db.update(rid, status="dismissed")
                except Exception:
                    pass
            ctx["open_rows"] = set()
        for _ in range(3):
            s = state()
            if not (s.get("listening") or s.get("isRecording") or s.get("settling")):
                break
            post("/test/cancel")
            time.sleep(0.6)
        if db:
            post("/test/wispr", {"on": False, "via": "poll"})
        _quiet(tmo("q14_terminal") + 10)
        _drain_recover()
    except Exception as e:
        print("  (qw teardown: %s: %s)" % (type(e).__name__, e))
    finally:
        _sink_off()
        _auto_back()

def _start(mark):
    """`toggleDictation` (bound → a prompt into the witness); True once a microphone opened after it."""
    n = count(mark, OPENED)
    post("/test/gesture", {"name": "forward-right", "direct": True})
    return bool(wait_for(lambda: count(mark, OPENED) > n, tmo("mic_open"), 0.05))

def _stop():
    """The 🔼 that ends it — only while a sentence records (at rest it would open a caret prompt)."""
    s = state()
    if s.get("listening") or s.get("isRecording"):
        post("/test/gesture", {"name": "forward-click", "direct": True})
        return time.time()
    return None

def _say(wav, seconds=None):
    time.sleep(0.4)
    play(wav, seconds=seconds)
    time.sleep(0.6)

def _play_bg(wav, seconds=None):
    th = threading.Thread(target=lambda: play(wav, seconds=seconds), daemon=True)
    th.start()
    return th


# ---------------------------------------------------------------- the desk's sentences
def _a_desk(ctx, before_stop=None):
    """A on the fake Wispr: the gesture, Wispr's microphone open (the poll), its row adopted, the clip
    said, the 🔼 stop; waited for the relay's close (≈ 3 s at a desk — the stop waits for an input
    that never runs, then a held drain), then Wispr's microphone shut and **the row `processing`** —
    held there until `_finish_a`. Raises with why."""
    db, m = ctx["db"], ctx["mark"]
    if not _start(m):
        raise RuntimeError("A's microphone never opened — " + _excerpt(m))
    dev = _device(m)
    if INJ.lower() not in dev.lower():
        raise RuntimeError("the recorder opened %r, not %s" % (dev, LOOPBACK))
    post("/test/wispr", {"on": True, "via": "poll"})
    time.sleep(0.4)
    rid = db.insert(at=time.time())
    ctx["open_rows"].add(rid)
    if not wait_for(lambda: live()["captureRow"] == rid, 3, 0.05):
        raise RuntimeError("A's fake row %s was not adopted (captureRow %s)" % (rid, live().get("captureRow")))
    _say(CLIP_A)
    ctx["chords_at_a_stop"] = count(m, CHORD)
    if before_stop:
        before_stop()
    t = _stop()
    if not t:
        raise RuntimeError("A ended before its stop — " + _excerpt(m))
    if not wait_for(lambda: not state().get("listening"), 15, 0.05):
        raise RuntimeError("the relay never closed A (still listening 15 s after its stop) — " + _excerpt(m))
    t_close = time.time()
    post("/test/wispr", {"on": False, "via": "poll"})
    db.update(rid, status="processing", duration=4.5, speech=3.0)
    ctx.update(t_a=t, t_close=t_close, ra=rid, a_close_after=t_close - t)
    return rid

def _finish_a(ctx):
    ctx["db"].finish(ctx["ra"], A_TEXT)
    ctx["open_rows"].discard(ctx["ra"])
    ctx["t_a_finished"] = time.time()

def _b_start(ctx):
    """B's gesture `GAP` after the relay's close of A. (opened, take, why) — take/why from the
    `deferred` line, None when B was not deferred."""
    m = ctx["mark"]
    _sleep_until(ctx["t_close"] + GAP)
    ctx["t_b"] = time.time()
    opened = _start(m)
    d = None
    if opened:
        wait_for(lambda: re.search(DEFERRED, log_since(m)), 1.0, 0.05)
        d = re.findall(DEFERRED, log_since(m))
    tb, why = (int(d[-1][0]), d[-1][1]) if d else (None, None)
    ctx["tb"] = tb
    return opened, tb, why

def _b_adopt(ctx, timeout):
    """After A's row finished: B's release awaited; then — as Wispr does at a start chord — its
    microphone open (the poll) and a row inserted, adopted by B's capture. (rowid, release line);
    rowid None when no release came."""
    db, m, tb = ctx["db"], ctx["mark"], ctx["tb"]
    if tb is None or not wait_for(lambda: _pos(log_since(m), RELEASED, tb) >= 0, timeout, 0.05):
        return None, ""
    txt = log_since(m)
    p = _pos(txt, RELEASED, tb)
    ctx["p_rel"] = p
    post("/test/wispr", {"on": True, "via": "poll"})
    rid = db.insert(at=time.time())
    ctx["open_rows"].add(rid)
    ctx["rb"] = rid
    if not wait_for(lambda: live()["captureRow"] == rid, 3, 0.05):
        ctx["notes"].append("B's fake row %s not adopted (captureRow %s)" % (rid, live().get("captureRow")))
    return rid, _line_at(txt, p)

def _b_finish(ctx, text=B_TEXT):
    """B's machine closes (its stop chord, after the release: `🎙️ the microphone is closed` past the
    release line), then Wispr's microphone shut, B's row `processing`, then `formatted` with `text`."""
    db, m, rid = ctx["db"], ctx["mark"], ctx.get("rb")
    if rid is None:
        return False
    p = ctx.get("p_rel", 0)
    closed = wait_for(lambda: re.search(CLOSED, log_since(m)[p:]), 15, 0.05)
    post("/test/wispr", {"on": False, "via": "poll"})
    db.update(rid, status="processing", duration=4.5, speech=3.0)
    time.sleep(0.3)
    db.finish(rid, text)
    ctx["open_rows"].discard(rid)
    return bool(closed)


# ================================================================ QW0 — the live smoke
@case("QW0", TAGS_LIVE, covers=_COV, engine="wispr", pre=_pre_live,
      expect="LIVE (his real Wispr, From Walkie): A (12 s) stopped, B (3.5 s) started at +1.1 s → both delivered, A then "
             "B, both via wispr-history; nothing in the sink")
def qw0():
    """Two quick sentences on live Wispr — whether B was deferred depends on how fast Wispr finishes A
    (usually before B starts); only the outcome is asserted."""
    ctx = _rig(sink=True)
    try:
        m = ctx["mark"]
        ra, rb = ref_words(CLIP_SPEECH), ref_words(CLIP_EN)
        bw = [w for w in rb if len(w) >= 5 and w not in set(ra)] or rb[-2:]
        if not _start(m):
            return "ERROR", "A's microphone never opened — " + _excerpt(m)
        dev = _device(m)
        if INJ.lower() not in dev.lower():
            return "ERROR", "the recorder opened %r, not %s" % (dev, LOOPBACK)
        _say(CLIP_SPEECH)
        t_a = _stop()
        if not t_a:
            return "ERROR", "A ended before its stop — " + _excerpt(m)
        _sleep_until(t_a + GAP)
        if not _start(m):
            return "FAIL", "B's microphone never opened — " + _excerpt(m)
        d = re.findall(DEFERRED, log_since(m))
        _say(CLIP_EN)
        _stop()
        rows = _ab_rows(ctx, 2, 2 * tmo("terminal") + tmo("wispr_row"))
        order = ["B" if set(_tokens(r.get("text") or "")) & set(bw) else "A" for r in rows]
        vias = [_via(r) for r in rows]
        leaked, leak = _leak_note()
        note = ("rows %s via %s; B deferred %s; chords %d; %s"
                % (order, vias, d[-1][0] if d else None, count(m, CHORD), leak))
        ok = order == ["A", "B"] and vias == ["wispr-history"] * 2 and not leaked
        return ("PASS" if ok else "FAIL"), note + ("" if ok else " || " + _excerpt(m))
    finally:
        _teardown(ctx)


# ================================================================ QW1
@case("QW1", TAGS, covers=_COV, engine="wispr", pre=_pre_desk(),
      expect="fake Wispr: A's row held `processing`; B at +1.1 s after A's close → `take N deferred`; A's row finished "
             "while B still talks → `released … he is still talking`; A then B in the outbox, both via wispr-history, "
             "B's words whole, B's WAV voiced ≥ 1.5 s")
def qw1():
    """B deferred while A is still Wispr's, released into the bridge while he still talks."""
    db = desk()
    ctx = _rig(db)
    th = None
    try:
        m = ctx["mark"]
        try:
            _a_desk(ctx)
        except RuntimeError as e:
            return "ERROR", str(e)
        opened, tb, why = _b_start(ctx)
        if not opened:
            return "FAIL", "B's microphone never opened — " + _excerpt(m)
        th = _play_bg(CLIP_B)
        time.sleep(1.4)
        dn = _deferred_now()
        waiting = dn.get("take") == tb and bool(dn.get("recording"))
        _finish_a(ctx)
        rb, rel = _b_adopt(ctx, tmo("terminal") + 5)
        th.join(15)
        th = None
        time.sleep(0.6)
        _stop()
        closed = _b_finish(ctx)
        rows = _ab_rows(ctx, 2, 2 * tmo("terminal") + 5)
        txt = log_since(m)
        p_def = _pos(txt, DEFERRED, tb) if tb else -1
        voiced = _voiced_after(txt, p_def)
        gave = re.findall(GAVE_UP, txt)
        order = [_who(r.get("text") or "") for r in rows]
        vias = [_via(r) for r in rows]
        b_text = next((r.get("text") or "" for r in rows if _who(r.get("text") or "") == "B"), "")
        note = ("A closed %.1f s after its stop; B take %s deferred (%s); deferred and recording at A's finish %s; "
                "release %r; B closed %s; B voiced %s s; gave up %s; rows %s via %s; B whole %s; chords %d"
                % (ctx["a_close_after"], tb, why, waiting, rel[:150] or None, closed, voiced, gave or None,
                   order, vias, _whole(b_text, B_TEXT), count(m, CHORD)))
        if tb is None:
            return "FAIL", "B was not deferred with A's row processing — " + note + " || " + _excerpt(m)
        ok = (waiting and rel and "still talking" in rel and not gave and order == ["A", "B"]
              and vias == ["wispr-history"] * 2 and _whole(b_text, B_TEXT) and (voiced or 0) >= B_VOICED_MIN)
        return ("PASS" if ok else "FAIL"), note + ("" if ok else " || " + _excerpt(m))
    finally:
        if th:
            th.join(10)
        _teardown(ctx)


# ================================================================ QW2
@case("QW2", TAGS, covers=_COV, engine="wispr", pre=_pre_desk(),
      expect="fake Wispr: A's row held `processing`; B deferred, recorded and STOPPED before its release (`stopped … it "
             "waits for Wispr Flow`); A finished → `released … his stop came`, then a start and a stop chord (Wispr "
             "would hear all of B); A then B via wispr-history, B whole")
def qw2():
    """B stopped before its release: replayed to Wispr, then the stop chord."""
    db = desk()
    ctx = _rig(db)
    try:
        m = ctx["mark"]
        try:
            _a_desk(ctx)
        except RuntimeError as e:
            return "ERROR", str(e)
        opened, tb, why = _b_start(ctx)
        if not opened:
            return "FAIL", "B's microphone never opened — " + _excerpt(m)
        _say(CLIP_B)
        _stop()
        stopped = wait_for(lambda: tb is not None and _pos(log_since(m), STOPPED_WAITING, tb) >= 0, 3, 0.05)
        time.sleep(1.0)
        dn = _deferred_now()
        waiting = dn.get("take") == tb and not dn.get("recording")
        _finish_a(ctx)
        rb, rel = _b_adopt(ctx, tmo("terminal") + 5)
        closed = _b_finish(ctx)
        rows = _ab_rows(ctx, 2, 2 * tmo("terminal") + 5)
        txt = log_since(m)
        p_stop = _pos(txt, STOPPED_WAITING, tb) if tb else -1
        p_rel = _pos(txt, RELEASED, tb) if tb else -1
        chords_after = len(re.findall(CHORD, txt[p_rel:])) if p_rel >= 0 else 0
        voiced = _voiced_after(txt, _pos(txt, DEFERRED, tb) if tb else -1)
        gave = re.findall(GAVE_UP, txt)
        order = [_who(r.get("text") or "") for r in rows]
        vias = [_via(r) for r in rows]
        b_text = next((r.get("text") or "" for r in rows if _who(r.get("text") or "") == "B"), "")
        note = ("A closed %.1f s after its stop; B take %s deferred (%s); stopped-while-waiting line %s, before the release "
                "%s; still deferred 1 s after his stop %s; release %r; chords after it %d; B closed %s; B voiced %s s; "
                "gave up %s; rows %s via %s; B whole %s"
                % (ctx["a_close_after"], tb, why, bool(stopped), 0 <= p_stop < p_rel, waiting, rel[:170] or None,
                   chords_after, closed, voiced, gave or None, order, vias, _whole(b_text, B_TEXT)))
        if tb is None:
            return "FAIL", "B was not deferred with A's row processing — " + note + " || " + _excerpt(m)
        ok = (stopped and waiting and 0 <= p_stop < p_rel and "his stop came" in rel and chords_after >= 2
              and not gave and order == ["A", "B"] and vias == ["wispr-history"] * 2 and _whole(b_text, B_TEXT)
              and (voiced or 0) >= B_VOICED_MIN)
        return ("PASS" if ok else "FAIL"), note + ("" if ok else " || " + _excerpt(m))
    finally:
        _teardown(ctx)


# ================================================================ QW3
@case("QW3", TAGS, covers=_COV, engine="wispr", pre=_pre_desk(),
      expect="fake Wispr: A's row held `processing`; B deferred, stopped, waiting; POST /test/cancel → `take N cancelled "
             "while it waited`, Recover holds B's WAV; A finished → delivered alone via wispr-history; B never released; "
             "only A's two chords ever posted")
def qw3():
    """🔼← on the deferred take: B dropped to Recover, A untouched."""
    db = desk()
    ctx = _rig(db)
    try:
        m = ctx["mark"]
        try:
            _a_desk(ctx)
        except RuntimeError as e:
            return "ERROR", str(e)
        opened, tb, why = _b_start(ctx)
        if not opened:
            return "FAIL", "B's microphone never opened — " + _excerpt(m)
        _say(CLIP_B)
        _stop()
        wait_for(lambda: tb is not None and _pos(log_since(m), STOPPED_WAITING, tb) >= 0, 3, 0.05)
        time.sleep(0.6)
        dn = _deferred_now()
        still = tb is not None and dn.get("take") == tb and not dn.get("recording")
        post("/test/cancel")
        cancelled = wait_for(lambda: tb is not None and _pos(log_since(m), CANCELLED_DEFERRED, tb) >= 0, 3, 0.05)
        rec = wait_for(lambda: _staged_after(ctx["t_b"]), tmo("recover_staged") + 2, 0.1)
        time.sleep(1.0)
        _finish_a(ctx)
        _ab_rows(ctx, 1, 2 * tmo("terminal"))
        time.sleep(2.0)
        rows = _rows(ctx["n0"])
        txt = log_since(m)
        order = [_who(r.get("text") or "") for r in rows]
        vias = [_via(r) for r in rows]
        released_b = tb is not None and _pos(txt, RELEASED, tb) >= 0
        chords = count(m, CHORD)
        note = ("B take %s deferred (%s), cancelled while stopped and waiting (still deferred then: %s); cancel line %s; "
                "Recover %s; B released anyway %s; rows %s via %s; chords %d"
                % (tb, why, still, bool(cancelled), {k: rec.get(k) for k in ("path", "duration")} if rec else None,
                   released_b, order, vias, chords))
        if tb is None:
            return "FAIL", "B was not deferred with A's row processing — " + note + " || " + _excerpt(m)
        if not still:
            return "ERROR", "rig: B was no longer deferred at the cancel — " + note + " || " + _excerpt(m)
        ok = (cancelled and rec and float(rec.get("duration") or 99) < 9 and not released_b and order == ["A"]
              and vias == ["wispr-history"] and chords == 2)
        return ("PASS" if ok else "FAIL"), note + ("" if ok else " || " + _excerpt(m))
    finally:
        _teardown(ctx)


# ================================================================ QW4
@case("QW4", TAGS, covers=_COV_LOCAL, engine="wispr", pre=_pre_desk(),
      expect="fake Wispr: A's row held `processing`; B still recording and deferred; POST /test/local-now (⌘⌃X) → `take N "
             "was waiting for Wispr Flow` → B via local-forced, held behind A until A's row finishes; A via wispr-history; "
             "A then B; no chord for B")
def qw4():
    """⌘⌃X on the deferred take: the relay's own WAV to the local model, A stays Wispr's."""
    db = desk()
    ctx = _rig(db)
    try:
        m = ctx["mark"]
        rb = ref_words(CLIP_B)
        try:
            _a_desk(ctx)
        except RuntimeError as e:
            return "ERROR", str(e)
        opened, tb, why = _b_start(ctx)
        if not opened:
            return "FAIL", "B's microphone never opened — " + _excerpt(m)
        time.sleep(0.4)
        play(CLIP_B)                             # all of B said, the microphone still open
        time.sleep(0.4)
        dn = _deferred_now()
        still = tb is not None and dn.get("take") == tb and bool(dn.get("recording")) and state().get("listening")
        code, r = post("/test/local-now")
        handed = wait_for(lambda: tb is not None and _pos(log_since(m), LOCAL_DEFERRED, tb) >= 0, 3, 0.05)
        if state().get("listening"):
            _stop()                              # ⌘⌃X did not close it: end it, so the case stays bounded
        # B's end lands while A's row is still in flight: it must wait its turn behind A (Q12).
        waits = wait_for(lambda: re.search(WAITS_TURN, log_since(m)), 5, 0.1)
        time.sleep(2.0)
        before_a = [_who(x.get("text") or "") for x in _rows(ctx["n0"])]
        p_fin = len(log_since(m))
        _finish_a(ctx)
        rows = _ab_rows(ctx, 2, tmo("q14_terminal") + tmo("terminal"))
        txt = log_since(m)
        # Where the ⌘⌃X decode itself ran: ahead, while A was in flight, or only at B's turn.
        p_dec = txt.find("💻 ⌘⌃X — transcribing the")
        decoded = "not seen" if p_dec < 0 else ("ahead of A's words" if p_dec < p_fin else "only at its turn, after A")
        order = [_who(x.get("text") or "") for x in rows]
        vias = [_via(x) for x in rows]
        b_text = next((x.get("text") or "" for x in rows if _who(x.get("text") or "") == "B"), "")
        rc = recall(rb, b_text) or 0.0
        released_b = tb is not None and _pos(txt, RELEASED, tb) >= 0
        chords = count(m, CHORD)
        note = ("B take %s deferred (%s), still deferred and recording at ⌘⌃X %s; local-now answered %s %s; hand-off line "
                "%s; B's end waited its turn behind A %s; B's local decode ran %s; delivered before A's row finished %s; B released anyway %s; rows %s "
                "via %s; B recall %.2f; chords %d"
                % (tb, why, bool(still), code, {k: r.get(k) for k in ("ok", "error", "why") if k in r}, bool(handed),
                   bool(waits), decoded, before_a or None, released_b, order, vias, rc, chords))
        if tb is None:
            return "FAIL", "B was not deferred with A's row processing — " + note + " || " + _excerpt(m)
        if not still:
            return "ERROR", "rig: B was no longer deferred at ⌘⌃X — " + note + " || " + _excerpt(m)
        ok = (handed and waits and not released_b and not before_a and order == ["A", "B"]
              and vias == ["wispr-history", "local-forced"] and rc >= 0.6 and chords == 2)
        return ("PASS" if ok else "FAIL"), note + ("" if ok else " || " + _excerpt(m))
    finally:
        _teardown(ctx)


# ================================================================ QW6
class _Sampler(object):
    """`readyForNext`, `listening` and the chip's rows at 20 Hz on a thread."""
    def __init__(self):
        self.rows, self.ev, self.t0 = [], threading.Event(), time.time()
        self.th = threading.Thread(target=self._run, daemon=True)

    def _run(self):
        while not self.ev.is_set():
            try:
                s = state()
                self.rows.append((time.time() - self.t0, bool(s.get("readyForNext")), bool(s.get("listening")),
                                  " | ".join(str(x) for x in (s.get("chip") or []) if x)))
            except Exception:
                pass
            time.sleep(0.05)

    def start(self, t0=None):
        self.t0 = t0 or time.time()
        self.th.start()
        return self

    def stop(self):
        self.ev.set()
        self.th.join(3)
        return self

    def first(self, pred, after=0.0):
        return next((t for t, rd, ls, c in self.rows if t >= after and pred(rd, ls, c)), None)


@case("QW6", TAGS, covers=_COV, engine="wispr", pre=_pre_desk(),
      expect="fake Wispr: after A's close, its row `processing`: 📻 readyForNext up between +0.7 and +1.1 s after the close "
             "(never before +0.7); B at +1.1 s opens, deferred — no Q16 flash `Wispr Flow takes one sentence at a time`, "
             "no `start refused`; A then B delivered")
def qw6():
    """The 📻 Ready row tells the truth on Wispr: a start now is taken, not refused."""
    db = desk()
    ctx = _rig(db)
    smp, th = _Sampler(), None
    try:
        m = ctx["mark"]
        try:
            _a_desk(ctx, before_stop=lambda: smp.start())
        except RuntimeError as e:
            return "ERROR", str(e)
        opened, tb, why = _b_start(ctx)
        a_in_flight = not _rows(ctx["n0"])
        if opened:
            th = _play_bg(CLIP_B)
            time.sleep(1.4)
            _finish_a(ctx)
            _b_adopt(ctx, tmo("terminal") + 5)
            th.join(15)
            th = None
            time.sleep(0.6)
            _stop()
            _b_finish(ctx)
        else:
            time.sleep(3.0)                      # the flash's 3 s, sampled
            _finish_a(ctx)
        smp.stop()
        rows = _ab_rows(ctx, 2 if opened else 1, 2 * tmo("terminal") + 5)
        t_close = smp.first(lambda rd, ls, c: not ls)
        ready_at = smp.first(lambda rd, ls, c: rd, after=t_close or 0)
        rel = (ready_at - t_close) if (ready_at is not None and t_close is not None) else None
        early = [t for t, rd, ls, c in smp.rows if rd and t_close is not None and t < t_close + 0.7]
        flash = [c for _, _, _, c in smp.rows if Q16 in c]
        refused = re.findall(REFUSED, log_since(m))
        order = [_who(r.get("text") or "") for r in rows]
        note = ("A closed %.1f s after its stop; 📻 ready first at +%s s after A's close (up before +0.7: %d samples); "
                "A in flight at B's start %s; Q16 flash seen %s; refusal lines %s; B opened %s, deferred take %s (%s); "
                "rows %s via %s"
                % (ctx["a_close_after"], round(rel, 2) if rel is not None else None, len(early), a_in_flight,
                   flash[:1] or None, refused or None, opened, tb, why, order, [_via(r) for r in rows]))
        if not a_in_flight:
            return "ERROR", "rig: A was delivered before B's start — " + note
        ok = (rel is not None and 0.7 <= rel <= GAP + 0.1 and not early and not flash and not refused and opened
              and tb is not None and order == ["A", "B"])
        return ("PASS" if ok else "FAIL"), note + ("" if ok else " || " + _excerpt(m))
    finally:
        if not smp.ev.is_set() and smp.th.is_alive():
            smp.stop()
        if th:
            th.join(10)
        _teardown(ctx)


# ================================================================ QW7
@case("QW7", TAGS + ("restart",), covers=_COV_RESTART, engine="wispr", pre=_pre_desk(restart=True),
      expect="WT_WISPR_QUEUE=0 in elevenlabs.env + a gated restart → wisprLive.takes.queues false; fake Wispr, A's row "
             "held `processing`: B at +1.1 s after A's close is refused (`start refused`, chip flash `Wispr Flow takes one "
             "sentence at a time`, no microphone for B); A delivered alone; the line removed and the app restarted → "
             "queues true again")
def qw7():
    """Q16 still holds with the queue switched off."""
    notes = []
    _env_block(["WT_WISPR_QUEUE=0"])
    ok_r, why_r = _restart()
    notes.append("restart with the line: " + why_r)
    if not ok_r:
        return "ERROR", "; ".join(notes)
    if _queues() is not False:
        return "ERROR", "the app still queues after the restart with WT_WISPR_QUEUE=0; " + "; ".join(notes)
    ctx, smp = None, None
    verdict, note = "ERROR", "not reached"
    try:
        db = desk()
        ctx = _rig(db)
        m = ctx["mark"]
        try:
            _a_desk(ctx)
        except RuntimeError as e:
            note = str(e)
        else:
            smp = _Sampler().start(ctx["t_close"])
            _sleep_until(ctx["t_close"] + GAP)
            a_in_flight = not _rows(ctx["n0"])
            n_open = count(m, OPENED)
            post("/test/gesture", {"name": "forward-right", "direct": True})
            refused = wait_for(lambda: re.search(REFUSED, log_since(m)), 3, 0.05)
            time.sleep(3.0)
            smp.stop()
            b_opened = count(m, OPENED) > n_open
            if state().get("listening"):
                post("/test/cancel")             # a B that opened after all: not delivered into the witness
            _finish_a(ctx)
            rows = _ab_rows(ctx, 1, 2 * tmo("terminal"))
            flash = [c for _, _, _, c in smp.rows if Q16 in c]
            note = ("A in flight at B's start %s; refusal %r; Q16 flash %s; B microphone opened %s; deferred lines %d; "
                    "rows %d via %s"
                    % (a_in_flight, refused.group(0)[:120] if refused else None, bool(flash), b_opened,
                       count(m, DEFERRED), len(rows), [_via(r) for r in rows]))
            if not a_in_flight:
                verdict, note = "ERROR", "rig: A was delivered before B's start — " + note
            else:
                ok = (refused and flash and not b_opened and not count(m, DEFERRED) and len(rows) == 1
                      and [_via(r) for r in rows] == ["wispr-history"])
                verdict = "PASS" if ok else "FAIL"
                if not ok:
                    note += " || " + _excerpt(m)
    finally:
        if smp and not smp.ev.is_set():
            smp.stop()
        if ctx is not None:
            _teardown(ctx)
        _env_block(None)
        ok_b, why_b = _restart()
        back = _queues()
        notes.append("restart without the line: %s, queues %s" % (why_b, back))
    if not ok_b or back is not True:
        verdict = "ERROR"
        notes.append("THE APP MAY STILL READ WT_WISPR_QUEUE=0 — restart it with ./relay-restart.sh")
    return verdict, note + " · " + "; ".join(notes)
