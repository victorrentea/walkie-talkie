"""**Wispr Flow as the engine** — TW1–TW21 (2026-09-28), the outline in
`evals/plan/wispr/D-state.md` §3, mapped to the findings of the four adversarial reviews
(`A-lifecycle.md` W-A*, `B-errors.md` W-B*, `C-firewall.md` W-C*, `D-state.md` W-D*).

Two kinds of case:

- **desk** — run on the host, Engine = Wispr, but Wispr's real process never hears a thing:
  the app reads a **fake `History`** (`fake_wispr_db.py`, switched in through a `WT_WISPR_DB=`
  line in `elevenlabs.env` between two `# fake-wispr:` marks, removed after every case) and
  **Wispr's chords are muted** (`POST /test/wispr-chord {"mute": true}` — only their stamped
  trailing `flagsChanged []` goes out). Rows are inserted and rewritten by the case the way Wispr
  writes them (B §1). The relay's own recorder is pointed at the Loopback (`/test/mic`) so no
  real microphone opens. Assertions read `GET /test/state` (`wisprLive`, `pasteboard`, the
  usual fields), the log and the witness tab — never a screenshot.
- **lab** (`lab_only=True`) — the real Wispr in the Tart guest, audio through BlackHole
  (`docs/vm-lab.md`, `docs/vm-wispr.md`); SKIP on the host.

Every case needs Wispr running (`needs_wispr`: a host without it SKIPs); a desk case also needs
an installed build with the hooks (`wisprLive` in `/test/state`). Verdicts: **BUG** = the
review's prediction confirmed (most of these are expected-fail today), **PASS** = the app does
what the review asks for, **FAIL** = neither."""
import glob, os, subprocess, time
from harness import *
import fake_wispr_db as fw

WISPR_EXE = "/Applications/Wispr Flow.app/Contents/MacOS/Wispr Flow"
FAKE_DB = os.path.join(WORK, "fake-wispr", "flow.sqlite")
WMARK = "# fake-wispr: written by evals/plan/cases_wispr.py, removed after each case"
CACHES = os.path.expanduser("~/Library/Caches/ro.victorrentea.wispr-relay")
KILL_OK = IN_LAB or os.environ.get("WT_ALLOW_WISPR_KILL") == "1"
# A sentence that ended with no words, for good — nothing will reach the witness after it.
NO_WORDS = r"kept for Recover|dictation abandoned|No words heard|No words came back|No speech"

# What these cases exercise, for `harness.py --changed-since` (evals/plan/README.md).
_COV = covers("wispr", "gesture", "recorder", "local", "delivery", "chip")
_COV_EL = covers("eleven", "gesture", "recorder", "delivery")


# ---------------------------------------------------------------- preconditions
def wispr_pid():
    try:
        pid = (state().get("wisprLive") or {}).get("wisprPid")
        if pid is not None:
            return pid
    except Exception:
        pass
    out = subprocess.run(["pgrep", "-f", "^" + WISPR_EXE], capture_output=True, text=True).stdout.split()
    return int(out[0]) if out else 0

def needs_wispr():
    """SKIP reason when Wispr Flow's main process is not running (a host without it)."""
    return None if wispr_pid() else "Wispr Flow is not running (host without Wispr — the lab has it)"

def needs_desk():
    return needs_wispr() or (None if "wisprLive" in state() else
                             "the installed build has no Wispr test hooks (/test/state.wisprLive)")

def needs_standalone(on=True):
    def pre():
        why = needs_desk()
        if why:
            return why
        if bool(state().get("wisprStandalone")) != on:
            return "needs Q9 standalone %s (state.wisprStandalone)" % ("ON" if on else "OFF")
        return None
    return pre


# ---------------------------------------------------------------- the desk rig
def _env_block(lines):
    """Our `WT_WISPR_DB` block in `elevenlabs.env` set to `lines` (or removed); everything else
    — his key, the fake-Scribe block — byte for byte."""
    try:
        cur = open(ELEVEN_ENV, encoding="utf-8").read().splitlines()
        mode = os.stat(ELEVEN_ENV).st_mode & 0o777
    except FileNotFoundError:
        cur, mode = [], 0o600
    keep, inside = [], False
    for l in cur:
        if l.startswith(WMARK):
            inside = not l.endswith("(end)")
            continue
        if not inside:
            keep.append(l)
    if lines:
        keep += [WMARK] + lines + [WMARK + " (end)"]
    if keep == cur:
        return
    tmp = ELEVEN_ENV + ".wispr-tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write("\n".join(keep) + ("\n" if keep else ""))
    os.chmod(tmp, mode)
    os.replace(tmp, ELEVEN_ENV)

DESK = {"db": None}

def desk(engine_wispr=True, wal=False):
    """Fresh fake History, the app reading it, Wispr's chords muted, the relay's recorder on the
    Loopback, Engine = Wispr. Returns the FakeWisprDB. `wal`: Wispr's own journal mode (a holder
    connection keeps `flow.sqlite-wal` alive until `desk_off`) — the relay's WAL watch sees it."""
    if DESK.get("db"):
        DESK["db"].close()
    db = fw.FakeWisprDB(FAKE_DB).create(wal=wal)
    DESK["db"] = db
    _env_block(["WT_WISPR_DB=" + FAKE_DB])
    post("/test/wispr-chord", {"mute": True, "seconds": 300})
    if not wait_for(lambda: state()["wisprLive"]["db"] == FAKE_DB, 5):
        raise RuntimeError("the app did not pick up WT_WISPR_DB within 5 s")
    try:
        mic_override(LOOPBACK)
    except Exception:
        pass
    if engine_wispr and not set_engine("wispr"):
        raise RuntimeError("POST /engine wispr was not taken")
    return db

def desk_off():
    """After every case (harness CLEANUPS): a capture still standing on a fake row is let go
    first (its row made terminal), then the real `flow.sqlite` and live chords are back."""
    try:
        db = DESK.get("db")
        if db:
            live = state().get("wisprLive") or {}
            if live.get("captureOpen") and live.get("newestRowId"):
                db.update(live["newestRowId"], status="dismissed")
                wait_for(lambda: not state()["wisprLive"]["captureOpen"], 8, 0.3)
        if db:
            db.close()
        DESK["db"] = None
        _env_block(None)
        s = state()
        if (s.get("wisprLive") or {}).get("chordsMuted"):
            post("/test/wispr-chord", {"mute": False})
        if (s.get("wisprLive") or {}).get("db"):
            wait_for(lambda: state()["wisprLive"]["db"] is None, 3)
    except Exception as e:
        print(f"  (desk_off: {type(e).__name__}: {e})")

CLEANUPS.append(desk_off)

def chord(post_=None, state_=None):
    return post("/test/wispr-chord", {"post": post_ or "none", "state": state_ or "none"})[1]

def live():
    return state()["wisprLive"]

def open_sentence(db, adopt=True):
    """The relay's own Wispr gesture (no chord on the wire) and, as Wispr does at the gesture,
    a row with `status` NULL. Returns the rowid (None with `adopt=False`: no row)."""
    chord(state_="start")
    if not wait_for(lambda: state()["listening"], 3):
        raise RuntimeError("the relay did not open the sentence")
    if not adopt:
        return None
    rid = db.insert(at=time.time())
    if not wait_for(lambda: live()["captureRow"] == rid, 3):
        raise RuntimeError(f"fake row {rid} was not adopted (captureRow {live()['captureRow']})")
    return rid

def close_sentence(db, rid, text=None, status="formatted"):
    chord(state_="stop")
    db.update(rid, status="processing", speech=1.5)
    if text is not None:
        time.sleep(0.3)
        db.finish(rid, text, status=status)

def wav_count():
    return len(glob.glob(os.path.join(CACHES, "**", "wispr-*.wav"), recursive=True))


# ---------------------------------------------------------------- TW1–TW3: the held right ⌘⌥ (W-D1, W-C6)
@case("TW1", covers=_COV, tags=("gesture", "desk"), engine="wispr", pre=needs_standalone(True),
      expect="right ⌘⌥ held 3 s on Engine=Wispr stays one sentence: no 🧼 release before the real one, listening ≥ 2.5 s")
def tw1():
    """W-D1 / W-C6a (desk). Standalone ON, Engine = Wispr: the held pair is `onCleanHold` →
    `wisprSource.start()` → `postWisprHandsFree`, whose trailing `flagsChanged []` (muted here to
    that tail alone) carries no right-hand bits — read by the PTT branch as the pair's release
    ≈ 0.25 s after the press → quiet cancel. Held with `/test/modifiers` (unstamped, device bits).
    Cancelled before the real release so nothing lands at his caret."""
    desk()
    post("/test/key-trace", {"on": True})
    mark = log_mark(); t0 = time.time()
    post("/test/modifiers", {"keys": [54], "holdMs": 3000})
    seen = []
    while time.time() - t0 < 2.6:
        s = state(); seen.append((round(time.time() - t0, 2), s["listening"]))
        time.sleep(0.1)
    post("/test/cancel")
    wait_for(lambda: not state()["listening"], 3)
    time.sleep(0.8)   # the real release at 3.0 s
    post("/test/key-trace", {"on": False})
    txt = log_since(mark)
    held = "🧼 right ⌘⌥ held" in txt
    i_rel, i_cancel = txt.find("🧼 right ⌘⌥ released"), txt.find("cancelled via POST /test/cancel")
    early = i_rel >= 0 and (i_cancel < 0 or i_rel < i_cancel)
    quiet = re.search(r"dictation cancelled via (?!POST /test/cancel)([^\n]*)", txt)
    up = [t for t, l in seen if l]
    lasted = (up[-1] - up[0]) if up else 0
    # Lab wave 3: measured from the moment listening began (Wispr's row can lag the press by
    # ~0.8 s), not against a fixed bar — a hold that stays one sentence never drops back.
    dropped_back = bool(up) and any(not l for t, l in seen if t > up[0])
    note = f"held seen {held}; listening from {up[0] if up else '-'} s for {lasted:.1f} s; " \
           f"release line before the case's cancel {early}; other cancel: {quiet.group(1)[:60] if quiet else None}"
    if not held:
        return "FAIL", "the tap never saw the pair — " + note
    if early or dropped_back or not up:
        return "BUG", note + f"; dropped back to not-listening {dropped_back}"
    note += f"; listening from {up[0]} s to the end of sampling, never dropped"
    return "PASS", note

@case("TW2", covers=_COV, tags=("gesture", "desk", "unit"), pre=lambda: None if "wisprLive" in state() else "no Wispr hooks in this build",
      expect="a stamped flagsChanged [] under a held right ⌘⌥ is not its release")
def tw2():
    """W-D1 as a unit test (GW6 → `/test/modifiers {"keys": [], "stamped": true}`): hold right
    ⌘⌥ (unstamped, device bits), post one **stamped** `flagsChanged []` 200 ms in — the tail every
    chord this app posts ends with — and read whether the PTT branch fired `.release`. Local
    engine (no Wispr needed); cancelled before the real release."""
    mic_override(LOOPBACK)
    mark = log_mark()
    post("/test/modifiers", {"keys": [54], "holdMs": 1500})
    time.sleep(0.2)
    post("/test/modifiers", {"keys": [], "stamped": True})
    time.sleep(0.7)
    txt = log_since(mark)
    post("/test/cancel")
    time.sleep(1.0)
    held = "🧼 right ⌘⌥ held" in txt
    released = "🧼 right ⌘⌥ released" in txt
    if not held:
        return "FAIL", "the held pair never reached the tap (Secure Input? sessionFlags %s)" % state()["sessionFlags"]
    if released:
        return "BUG", "the stamped flagsChanged [] 0.2 s into the hold was read as the release (no stamp check in the PTT branch)"
    return "PASS", "the stamped tail was ignored; the pair stayed held"

def _retired_tw3():
    return ("retired 2026-09-28 (lab wave 2): Q9 step 2 deleted `WT_WISPR_STANDALONE` and the tap's "
            "Wispr push-to-talk branch — the held right ⌘⌥ is always Walkie's clean hold, which TW1 covers; "
            "the ptt-mismatch check is HK11's (README §4.2)")

@case("TW3", covers=_COV, tags=("gesture", "audio"), engine="wispr", lab_only=True, pre=_retired_tw3,
      expect="RETIRED — was: standalone OFF, right ⌘⌥ held 2 s: a Wispr row within 1 s, or a flash")
def tw3():
    """W-D1 (standalone OFF) / W-C7 — **retired** with Q9 step 2 (the standalone-off world is
    gone: `state.wisprStandalone` always answers true). Kept as a body for the record only."""
    e = engine()
    mark = log_mark()
    post("/test/modifiers", {"keys": [54], "holdMs": 2000})
    time.sleep(3.0)
    s = state()
    txt = log_since(mark)
    row = "wispr history: row" in txt
    note = f"wisprShortcuts.ptt {e.get('wisprShortcuts', {}).get('ptt')}; row {row}; ringUp at +3 s {s['ringUp']}"
    wait_for(lambda: not state()["ringUp"], 15)
    if row or not s["ringUp"]:
        return "PASS", note
    return "BUG", note


# ---------------------------------------------------------------- TW4–TW5: the cold, deaf opening (W-D2, W-A1)
@case("TW4", covers=_COV, tags=("gesture", "audio", "cold"), engine="wispr", lab_only=True, pre=needs_wispr,
      expect="a cold Wispr: the first 3 s he says reach the witness; the chip names the warming")
def tw4():
    """W-D2 (lab): relaunch Wispr, 🔼→ within 1 s of `ready`, 12 s of speech; sample the state
    at 20 Hz — every `listening` sample while `wispr.state == warming` is a moment the chip lied."""
    old = wispr_pid()
    post("/test/wispr-proc", {"relaunch": True})
    # Lab wave 2 (2026-09-28): `wispr_pid()` answered the OLD pid for ~2 s after the relaunch
    # request, so W1/W1r/W3r1 chorded a Wispr that did not exist yet (16:03:58 chord, new pid at
    # 16:04:00). Wait for a NEW pid, as the docstring says ("within 1 s of ready").
    if not wait_for(lambda: engine()["ready"] and wispr_pid() not in (0, old), tmo("wispr_relaunch"), 0.2):
        return "ERROR", "Wispr did not come back within %.0f s" % tmo("wispr_relaunch")
    time.sleep(0.5)
    bind_witness(); witness_clear()
    mic_override(LOOPBACK)
    mark = log_mark(); gesture("forward-right")
    samples = []
    import threading
    stop = threading.Event()
    def poll():
        while not stop.is_set():
            try:
                s = state(); samples.append((s["listening"], s["wispr"]["state"], s["historyRow"], list(s["chip"])))
            except Exception:
                pass
            time.sleep(0.05)
    th = threading.Thread(target=poll, daemon=True); th.start()
    time.sleep(0.2); play(CLIP_SPEECH); time.sleep(1.0)
    # The stop is a toggle: sent to a relay that already gave up (a cold Wispr ignoring the chord →
    # `done(timeout)` at 12 s) it opens a stray sentence that runs to the 10-min ceiling (lab
    # 2026-09-28 07:18, 10 min lost). Stop only a sentence that is still open.
    still = state()["listening"]
    if still:
        gesture("forward-right")
    wait_delivered(mark); stop.set(); th.join(2)
    lie = [x for x in samples if x[0] and x[1] == "warming" and x[2] is None]
    first = open(os.path.splitext(CLIP_EN_LONG)[0] + ".txt", errors="replace").read().split()[:5] \
        if os.path.exists(os.path.splitext(CLIP_EN_LONG)[0] + ".txt") else []
    got = witness_text().lower()
    head = sum(1 for w in first if re.sub(r"\W", "", w.lower()) in got)
    named = any(re.search(r"warm|waking|starting|opening", " ".join(x[3]), re.I) for x in lie)   # Q20: `Opening Wispr Flow...`
    note = f"{len(lie)}/{len(samples)} samples listening+warming+no row ({len(lie) * 0.05:.1f} s); first-5-words hit {head}/{len(first)}; chip named it {named}; still listening at the stop {still}"
    return ("PASS" if head >= max(1, len(first) - 1) and (not lie or named) else "BUG"), note

@case("TW5", covers=_COV, tags=("desk",), engine="wispr", pre=needs_desk,
      expect="while Wispr has no row and no microphone, the chip does not say Listening (or names the warming)")
def tw5():
    """W-D2 / W-A1 (desk): the relay's own gesture with the chord muted and no row — Wispr
    never heard it — polled at 20 Hz for 3 s. Documents the lie: `listening` + chip `Listening`
    + a breathing ring over `wispr.state == warming` with `historyRow == null`. Expected BUG."""
    db = desk()
    open_sentence(db, adopt=False)
    t0, lie, n, rows = time.time(), 0, 0, set()
    while time.time() - t0 < 3:
        s = state(); n += 1
        if s["listening"] and s["wispr"]["state"] == "warming" and s["historyRow"] is None:
            lie += 1
            rows.update(r for r in s["chip"] if r)
        time.sleep(0.05)
    post("/test/cancel")
    # Any row but one naming the wait is a claim of a live sentence ("Listening to …",
    # "Prompting to … →", measured 2026-09-28 09:03: the chip said *Prompting to* for 40/40).
    named = any(re.search(r"warm|waking|starting|waiting for wispr|opening", r, re.I) for r in rows)   # Q20: `Opening Wispr Flow...`
    note = f"{lie}/{n} samples listening while warming with no row; chip rows then: {sorted(rows)[:3]}"
    if lie and rows and not named:
        return "BUG", note
    return "PASS", note


# ---------------------------------------------------------------- TW6–TW7: the relay's WAV on every failure (W-D3, W-B3)
def _tw6(kind):
    def fn():
        """W-D3 / W-B3 (lab, audio): the relay's own recording of the sentence on a Wispr failure —
        (a) 🔼← mid-sentence, (b) 🔼← 0.3 s after the stop, (c) Wispr killed 0.2 s after the stop,
        (d) as (c) with a shot and the witness bound (no bare screenshot message)."""
        bind_witness(); witness_clear(); mic_override(LOOPBACK)
        n0 = wav_count(); mark = log_mark()
        gesture("forward-right")
        if not wait_for(lambda: log_has(mark, r"opening the dictation"), 8):
            return "ERROR", "the sentence never opened"
        if kind == "d":
            post("/test/area", {})
        import threading
        th = threading.Thread(target=lambda: play(CLIP_SPEECH, seconds=6), daemon=True); th.start()
        time.sleep(3.0)
        if kind == "a":
            gesture("forward-left")
        th.join(10)
        if kind != "a":
            gesture("forward-right"); time.sleep(0.2 if kind in "cd" else 0.3)
            if kind == "b":
                gesture("forward-left")
            else:
                post("/test/wispr-proc", {"kill": True})
        time.sleep(3.0)
        if kind in "cd":
            # Q14 (2026-09-28): Wispr quitting with ≥ 1.5 s voiced hands the relay's own WAV to the
            # local model, delivered `via: local-fallback` — the sentence is not a failure to Recover.
            wait_for(lambda: log_has(mark, r"📦 delivery: local-fallback|under the floor|staged"), 30, 0.3)
        s = state()
        txt = log_since(mark)
        n1 = wav_count()
        fallback = re.search(r"📦 delivery: local-fallback", txt) is not None
        wtxt = witness_text()
        bare = kind == "d" and re.search(r"screenshot", wtxt, re.I) is not None and not fallback
        note = (f"recoverable {bool(s['recoverable'])}; 'nothing had been recorded' {('nothing had been recorded' in txt)}; "
                f"wispr-*.wav {n0}→{n1}; lastFailure {s['lastFailure']}" + (f"; bare screenshot message {bare}" if kind == "d" else "")
                + (f"; local-fallback delivery {fallback}, witness {len(wtxt.strip())} chars" if kind in "cd" else ""))
        if kind in "cd":
            post("/test/wispr-proc", {"relaunch": True}); wait_for(lambda: wispr_pid(), 30)
            ok = (fallback and wtxt.strip() != "") or (s["recoverable"] and n1 == n0)
            return ("PASS" if ok and not bare else "BUG"), note
        ok = s["recoverable"] and n1 == n0 and not bare
        return ("PASS" if ok else "BUG"), note
    return fn

for _k in "abcd":
    case("TW6" + _k, covers=_COV, tags=("gesture", "audio"), engine="wispr", lab_only=True, pre=needs_wispr,
         expect="the relay's WAV reaches Recover; no orphan wispr-*.wav" + ("; no bare screenshot message" if _k == "d" else ""))(_tw6(_k))

@case("TW7", covers=_COV, tags=("desk",), engine="wispr", pre=needs_desk,
      expect="a cancelled / abandoned Wispr sentence leaves its WAV to Recover, no orphan file, no false 'nothing recorded'")
def tw7():
    """W-D3 / W-B3 (desk): (a) cancel while listening — the relay's meter WAV is deleted and the
    log says *nothing had been recorded yet*; (b) cancel in the settle — the WAV is orphaned;
    (c) only with `WT_ALLOW_WISPR_KILL=1` or in the lab: Wispr relaunched mid-settle
    (`/test/wispr-proc {"relaunch"}`) → *the sentence is lost* while the audio is on disk."""
    db = desk()
    parts, bugs = [], 0
    # (a)
    n0, mark = wav_count(), log_mark()
    rid = open_sentence(db); time.sleep(1.5)
    post("/test/cancel"); wait_for(lambda: not state()["listening"], 3); time.sleep(1.0)
    s, txt = state(), log_since(mark)
    db.update(rid, status="dismissed")                  # Wispr's answer to the ⌃Esc: the capture lets go
    wait_for(lambda: not live()["captureOpen"], 8, 0.3)
    a_bug = not s["recoverable"] or "nothing had been recorded" in txt
    bugs += a_bug
    parts.append(f"(a) recoverable {bool(s['recoverable'])}, 'nothing had been recorded' {'nothing had been recorded' in txt}, wav {n0}→{wav_count()}")
    # (b)
    n0, mark = wav_count(), log_mark()
    rid = open_sentence(db); time.sleep(1.5)
    close_sentence(db, rid)
    wait_for(lambda: state()["settling"] or live()["captureOpen"], 2)
    post("/test/cancel"); time.sleep(0.5)
    db.update(rid, status="dismissed")
    wait_for(lambda: not live()["captureOpen"], 8, 0.3); time.sleep(0.5)
    s = state(); n1 = wav_count()
    b_bug = not s["recoverable"] or n1 > n0
    bugs += b_bug
    parts.append(f"(b) recoverable {bool(s['recoverable'])}, wav {n0}→{n1}")
    # (c)
    if KILL_OK:
        n0, mark = wav_count(), log_mark()
        rid = open_sentence(db); time.sleep(1.5)
        close_sentence(db, rid)
        post("/test/wispr-proc", {"relaunch": True})
        wait_for(lambda: log_has(mark, r"Wispr Flow quit"), 8)
        time.sleep(1.0)
        s, txt = state(), log_since(mark)
        n1 = wav_count()
        c_bug = "the sentence is lost" in txt and (not s["recoverable"] or n1 > n0)
        bugs += c_bug
        parts.append(f"(c) 'the sentence is lost' {'the sentence is lost' in txt}, recoverable {bool(s['recoverable'])}, wav {n0}→{n1}")
        wait_for(lambda: wispr_pid(), 30)
    else:
        parts.append("(c) not run — kills his Wispr: WT_ALLOW_WISPR_KILL=1 or the lab")
    return ("BUG" if bugs else "PASS"), "; ".join(parts)


# ---------------------------------------------------------------- TW8–TW11: his own sentence vs the relay's (W-D4..D7, W-C4, W-B1)
def his_ptt_keys():
    """Wispr's own push-to-talk as its config says (`/engine.wisprShortcuts.ptt`): right ⌥⇧
    `61+60` since Q23 (2026-09-28), right ⌘⇧ `54+60` before."""
    ptt = (engine().get("wisprShortcuts") or {}).get("ptt") or "61+60"
    return [int(k) for k in ptt.split("+")]

def _his_ptt(seconds, clip=None):
    """His Wispr push-to-talk held for `seconds`, optionally with a clip."""
    post("/test/modifiers", {"keys": his_ptt_keys(), "holdMs": int(seconds * 1000)})
    if clip:
        time.sleep(0.4); play(clip)
    time.sleep(max(0, seconds - (0.4 if clip else 0)) + 0.3)

@case("TW8a", covers=_COV, tags=("gesture", "audio"), engine="wispr", lab_only=True, pre=needs_standalone(True),
      expect="his own ptt sentence 1 s after the relay's lands at the caret, not in the witness or the outbox")
def tw8a():
    """W-D4 / W-C4 (lab): inside the relay-owned window (gesture → idle + 10 s) his own Wispr ⌘V
    is dropped and rescued into the bound terminal."""
    return _tw8(1.0)

@case("TW8b", covers=_COV, tags=("gesture", "audio"), engine="wispr", lab_only=True, pre=needs_standalone(True),
      expect="his sentence 5 s after the relay's delivery (the 10 s tail) is Wispr's paste, no 🛡️ rescue")
def tw8b():
    """W-D4 (lab): the 10 s tail after the relay's sentence went idle."""
    return _tw8(5.0, after_delivery=True)

def _tw8(delay, after_delivery=False):
    bind_witness(); witness_clear(); mic_override(LOOPBACK)
    n0 = outbox_count(); mark = log_mark()
    dictate_loopback(CLIP_EN)
    t_close = time.time()
    if after_delivery:
        wait_delivered(mark)
    else:
        # Lab wave 2 (2026-09-28): the relay's OWN ⌘V is dropped ~1.1 s after the close; with the
        # mark taken at +1.0 s W1 counted that drop as a rescue of his sentence. Take the mark
        # after the relay's drop (≤ 3 s), then keep at least `delay` from the close.
        wait_for(lambda: log_has(mark, r"🛡️ ⌘V from .* dropped — .* the History row delivers"), 3, 0.05)
    time.sleep(max(0.0, delay - (time.time() - t_close)) if not after_delivery else delay)
    m2 = log_mark()
    _his_ptt(4.5, CLIP_EN)
    # Was a flat 6 s. His ⌘V is one event and the firewall logs its verdict either way (`passed`, or
    # a drop): wait for that line (his sentence at the caret, p99 3 s), then 1 s for anything after.
    when(m2, r"⌘V from Wispr Flow passed|⌘V[^\n]*dropped|the dropped ⌘V", tmo("caret"), 0.1)
    time.sleep(1.0)
    txt = log_since(m2)
    rescued = "🛡️ ⌘V from" in txt and "dropped" in txt
    # Lab wave 3: inside the tail the pass line says "(B, Q19)", not "(standalone, Q9)".
    passed = re.search(r"⌘V from Wispr Flow passed — [^\n]*\((?:standalone, Q9|B, Q19)\)", txt) is not None
    extra = outbox_count() - n0
    note = f"outbox +{extra} (the relay's sentence is 1); rescue/drop line {rescued}; Wispr's own paste passed {passed}"
    return ("PASS" if passed and not rescued and extra <= 1 else "BUG"), note

@case("TW9", covers=_COV, tags=("gesture", "audio"), engine="wispr", lab_only=True, pre=needs_standalone(True),
      expect="🔼→ during his own Wispr sentence (his ptt held): 'one engine at a time', no chord posted")
def tw9():
    """W-D5 (lab): `startDictation`'s exclusivity check is skipped on Engine = Wispr, and under Q9
    his sentence never sets `isRecording` — the relay posts its toggle into his PTT."""
    bind_witness(); mic_override(LOOPBACK)
    post("/test/key-trace", {"on": True})
    mark = log_mark()
    post("/test/modifiers", {"keys": his_ptt_keys(), "holdMs": 5000})
    time.sleep(1.5)
    gesture("forward-right")   # 🔼→ = ⌘⌃D's path (toggleDictation)
    time.sleep(4.5)
    post("/test/key-trace", {"on": False})
    txt = log_since(mark)
    refused = re.search(r"one engine at a time|Wispr Flow is listening|microphone is already open", txt) is not None
    opened = "opening the dictation on the gesture" in txt
    return ("PASS" if refused and not opened else "BUG"), f"refused {refused}; relay opened a sentence {opened}"

@case("TW10", covers=_COV, tags=("gesture", "cold"), engine="wispr", lab_only=True, pre=needs_wispr,
      expect="a stop 1 s into a cold Wispr leaves no ghost dictation: no row with words, nothing delivered for 40 s")
def tw10():
    """W-D6 / W-A4 / W-B8 (lab): the toggle posted blind before a cold Wispr opened anything."""
    post("/test/wispr-proc", {"relaunch": True})
    wait_for(lambda: engine()["ready"] and wispr_pid(), 30, 0.2)
    bind_witness(); witness_clear(); mic_override(LOOPBACK)
    before = live()["newestRowId"]; last0 = state()["lastDelivery"]
    gesture("forward-click"); time.sleep(1.0); gesture("forward-click")
    time.sleep(0.5); play(CLIP_EN)
    time.sleep(40)
    s = state(); lv = live()
    ghost = lv["newestRowId"] != before and (lv["newestRowText"] or 0) > 0
    note = f"new row with words {ghost}; lastDelivery changed {s['lastDelivery'] != last0}; witness {len(witness_text())} chars"
    return ("PASS" if not ghost and s["lastDelivery"] == last0 and not witness_text().strip() else "BUG"), note

@case("TW11", covers=_COV, tags=("gesture", "audio"), engine="wispr", lab_only=True, pre=needs_wispr,
      expect="relay 🔼→ A (with a shot) then relay 🔽 B 0.3 s after A's stop, during A's settle: A in the witness, B delivered or held, never lost")
def tw11():
    """W-D7 / W-B1 (lab). **Rewritten 2026-09-28 (lab wave 2)** as README §4.2 asked: the old
    precondition (standalone OFF, his own hands-free chord adopted as sentence B) went with Q9
    step 2 — his own chord is now Wispr's alone (TW8a/b). The overlap that remains is the relay's
    own: 🔼→ A with an area shot, stop, and 0.3 s later the relay's 🔽 plain dictation B while A's
    row is still settling."""
    bind_witness(); witness_clear(); mic_override(LOOPBACK)
    mark = log_mark(); n0 = outbox_count()
    gesture("forward-right"); time.sleep(0.5)
    post("/test/area", {}); play(CLIP_SPEECH, seconds=8)
    gesture("forward-right"); time.sleep(0.3)
    # 🔽 → = the plain dictation (b2d9bbd, 2026-09-28: the back click is Return again)
    gesture("back-right"); time.sleep(0.4); play(CLIP_EN, seconds=3)
    time.sleep(0.5); gesture("back-right")
    # Both sentences landed (or held) — or B was refused out loud and A is in the witness, which is
    # the other PASS below: B never opened, so nothing more can come (wave 5: this waited out 45 s).
    def settled():
        t = log_since(mark)
        n_ = len(re.findall(r"📦 delivery:|held for the next bind", t))
        return n_ >= 2 or (n_ >= 1 and re.search(r"refused|one engine at a time", t) and witness_text().strip())
    wait_for(settled, tmo("q14_terminal"), 0.5)
    time.sleep(3)
    txt = log_since(mark)
    lost = re.search(r"No words came back|the sentence is lost|No speech", txt) is not None
    refused = re.search(r"refused|one engine at a time", txt) is not None
    deliveries = len(re.findall(r"📦 delivery:", txt))
    held = "held for the next bind" in txt
    n = outbox_count() - n0
    wt = len(witness_text())
    note = (f"outbox +{n}; 📦 lines {deliveries}; held {held}; witness {wt} chars; "
            f"lost-line {lost}; B refused {refused}")
    if refused and not lost and wt:
        return "PASS", note + " (B refused out loud while A settles — not silent)"
    return ("PASS" if (deliveries >= 2 or (deliveries >= 1 and held)) and not lost and wt else "BUG"), note


@case("TW12", covers=_COV, tags=("desk",), engine="wispr", pre=needs_desk,
      expect="two Wispr sentences overlapping on an ungated path: both delivered, in spoken order")
def tw12():
    """W-D7 / W-B1 / W-A5 (desk): sentence A in the settle (row `processing`), a second sentence
    opened on an ungated path (the relay's own gesture straight into the source — what a mic
    edge or his chord does with standalone off), row B `formatted` **before** A. D predicts the
    new sentence keeps A's capture, B's row is never adopted and B is lost after 30 s."""
    db = desk()
    bind_witness(); witness_clear()
    ra = open_sentence(db); time.sleep(0.8)
    close_sentence(db, ra)
    time.sleep(0.5)
    mark = log_mark()
    chord(state_="start")                               # B, ungated
    wait_for(lambda: state()["listening"], 3)
    rb = db.insert(at=time.time()); time.sleep(1.0)
    chord(state_="stop")
    db.finish(rb, "tw twelve sentence bee")
    time.sleep(1.0)
    db.finish(ra, "tw twelve sentence ay")
    wait_for(lambda: "sentence bee" in witness_text() and "sentence ay" in witness_text(), 36, 0.5)
    got = witness_text()
    ia, ib = got.find("sentence ay"), got.find("sentence bee")
    txt = log_since(mark)
    note = f"A at {ia}, B at {ib} in the witness; 'No words came back' {'No words came back' in txt}"
    if ia >= 0 and ib >= 0 and ia < ib:
        return "PASS", note
    return "BUG", note


# ---------------------------------------------------------------- TW13–TW16: panel, refusals, not running (W-D8..D10)
@case("TW13", covers=_COV, tags=("desk",), engine="wispr", pre=needs_desk,
      expect="a Wispr sentence does not force-send a held panel being edited; A then B, in order")
def tw13():
    """W-D8 / W-C11 (desk): Autosend off, panel A held (`/test/dictation`) and opened for
    editing; a Wispr sentence B lands — `showSentPrompt` → `resolvePrompt(send: true)` sends A
    as it stands (F4: Wispr's answers skip `runAnswer`'s panel rule)."""
    db = desk()
    bind_witness(); witness_clear()
    autosend0 = bool(state().get("autosend"))
    post("/test/autosend", {"on": False})
    try:
        post("/test/dictation", {"text": "tw thirteen panel ay"})
        if not wait_for(lambda: (state().get("prompt") or {}).get("held"), 8):
            return "ERROR", "panel A never held"
        post("/test/prompt", {"do": "edit"})
        rb = open_sentence(db); time.sleep(0.8)
        close_sentence(db, rb, "tw thirteen wispr bee")
        time.sleep(3.0)
        s = state(); got = witness_text()
        a_sent = "panel ay" in got
        held = (s.get("prompt") or {}).get("held")
        note = f"A in the witness before its send {a_sent}; panel held {held}; prompt text {str((s.get('prompt') or {}).get('text'))[:40]!r}"
        verdict = "BUG" if a_sent else "PASS"
        if held:
            post("/test/prompt", {"do": "send"}); time.sleep(2.0)
            post("/test/prompt", {"do": "send"}); time.sleep(1.0)
        return verdict, note
    finally:
        post("/test/autosend", {"on": autosend0})
        if (state().get("prompt") or {}).get("held"):
            post("/test/prompt", {"do": "cancel"})

@case("TW14", covers=_COV, tags=("desk", "gesture"), engine="wispr", pre=needs_desk,
      expect="🔼→ during Wispr's settle is refused on the chip (the wait named), not only in the log")
def tw14():
    """W-D9 (desk): Engine = Wispr does not queue (F3) — a start in the settle is refused with a
    log line and nothing on the chip; ElevenLabs would open a queued sentence."""
    db = desk()
    bind_witness()
    # Past `gestureStopDwellSeconds` (2 s): a 🔼→ inside it is the stop guard's
    # "only N ms old — not stopping it", not the settle's refusal this case is about.
    rid = open_sentence(db); time.sleep(2.3)
    close_sentence(db, rid)
    wait_for(lambda: state()["settling"], 3)
    mark = log_mark()
    gesture("forward-right")
    rows = set()
    t0 = time.time()
    while time.time() - t0 < 1.5:
        rows.update(r for r in state()["chip"] if r); time.sleep(0.1)
    txt = log_since(mark)
    db.finish(rid, "tw fourteen")
    wait_for(lambda: not relay_busy(), 10)
    second = "opening the dictation on the gesture" in txt
    named = any(re.search(r"in flight|one sentence at a time|still (coming|transcribing)|wait", r, re.I) for r in rows)
    note = f"second sentence opened {second}; chip named the wait {named}; refusal logged {'refused' in txt or 'in flight' in txt}"
    if second:
        return "FAIL", note
    return ("PASS" if named else "BUG"), note

@case("TW15", covers=_COV, tags=("gesture",), engine="wispr", pre=lambda: needs_wispr() or (None if KILL_OK else "stops his Wispr: WT_ALLOW_WISPR_KILL=1 or the lab"),
      expect="with Wispr quit, 🔼↑ leaves no spawnPending and no folder menu; ⌘⌃D flashes 'not running'")
def tw15():
    """W-D10 (lab, or the desk with `WT_ALLOW_WISPR_KILL=1`): `startDictation` sets the spawn /
    paste flags and opens the folder menu **before** `source.start()` refuses."""
    post("/test/wispr-proc", {"kill": True})
    wait_for(lambda: not wispr_pid(), 5)
    try:
        mark = log_mark()
        gesture("forward-up"); time.sleep(0.8)
        s = state()
        gesture("forward-left")   # close whatever opened
        txt = log_since(mark)
        note = f"spawnPending {s['spawnPending']}; 'not running' {'not running' in txt}"
        return ("BUG" if s["spawnPending"] else "PASS"), note
    finally:
        post("/test/wispr-proc", {"relaunch": True}); wait_for(lambda: wispr_pid(), 30)

@case("TW16", covers=_COV, tags=("gesture",), engine="wispr", lab_only=True, pre=needs_wispr,
      expect="only Wispr's helper alive: ⌘⌃D says 'not running', never 'the sentence is lost'")
def tw16():
    """W-D10 (lab): `isReady` matches the bundle-id prefix (the helper too) while death is judged
    on the anchored main executable."""
    post("/test/wispr-proc", {"kill": True})
    wait_for(lambda: not wispr_pid(), 5)
    helper = subprocess.run(["pgrep", "-f", "swift-helper-app-dist/Wispr Flow.app"], capture_output=True, text=True).stdout.split()
    try:
        if not helper:
            return "SKIP", "no helper survived the main process"
        mark = log_mark(); gesture("forward-right"); time.sleep(1.5)
        txt = log_since(mark)
        return ("BUG" if "the sentence is lost" in txt else "PASS"), f"'not running' {'not running' in txt}; 'lost' {'the sentence is lost' in txt}"
    finally:
        post("/test/wispr-proc", {"relaunch": True}); wait_for(lambda: wispr_pid(), 30)


# ---------------------------------------------------------------- TW17–TW21
@case("TW17", covers=_COV, tags=("gesture", "audio"), engine="wispr", lab_only=True, pre=needs_wispr,
      expect="a Wispr corpus row is written only when Wispr's micDevice is the relay's device")
def tw17():
    """W-D11 (lab): the corpus pairs the relay meter's WAV with Wispr's text from another mic."""
    corpus = os.path.join(HOME, "voice-corpus", "corpus.jsonl")
    n0 = sum(1 for _ in open(corpus)) if os.path.exists(corpus) else 0
    bind_witness(); mic_override("Built-in")   # the relay on another input than Wispr's BlackHole
    mark = log_mark(); dictate_loopback(CLIP_EN); wait_delivered(mark, 40)
    time.sleep(2)
    rows = open(corpus).read().splitlines()[n0:] if os.path.exists(corpus) else []
    wis = [json.loads(r) for r in rows if '"wispr"' in r]
    s = state()
    note = f"new wispr corpus rows {len(wis)}; micOpened {s['micOpened']}; Wispr's mic {rows and wis and wis[-1].get('device')}"
    return ("BUG" if wis else "PASS"), note

@case("TW18", covers=_COV, tags=("desk",), pre=needs_desk,
      expect="after a pick away from Wispr the Engine list still offers Wispr")
def tw18():
    """W-D12 (host, Codex): the Engine submenu lists Wispr only while it is the engine. No route
    reads the menu's rows (only `micRowsForTest`), so this stays a Codex check (S1)."""
    return "SKIP", "no route reads the Engine menu's rows — a Codex menu check (D-state S1)"

@case("TW19", covers=_COV, tags=("desk",), pre=needs_desk,
      expect="/engine refused while listening / settling; accepted in state X with the swallow standing and nothing delivered")
def tw19():
    """Engine switch × Wispr state (desk, D §1 row `POST /engine`): mid `listening` and in the
    settle the switch is refused and `source` stays Wispr; after a cancel in the settle (state X,
    a discarding capture) it is accepted, the capture keeps swallowing and the late row delivers
    nothing."""
    db = desk()
    bind_witness(); witness_clear()
    parts, bad = [], []
    rid = open_sentence(db)
    _, r = post("/engine", {"id": "whisper"}); s = state()
    parts.append(f"L: engine→{r.get('engine')}, source {s['source']}")
    if r.get("engine") == "whisper":
        bad.append("L")
    close_sentence(db, rid)
    wait_for(lambda: state()["settling"], 3)
    _, r = post("/engine", {"id": "whisper"}); s = state()
    parts.append(f"S: engine→{r.get('engine')}, source {s['source']}")
    if r.get("engine") == "whisper":
        bad.append("S")
    post("/test/cancel"); time.sleep(0.5)
    ok = set_engine("whisper", 5)
    lv = live(); n0 = outbox_count(); last0 = state()["lastDelivery"]
    parts.append(f"X: switched {ok}, capture still open {lv['captureOpen']} (discarding {lv['discarding']})")
    db.finish(rid, "tw nineteen must not arrive")
    time.sleep(6)
    arrived = "nineteen" in witness_text() or state()["lastDelivery"] != last0 or outbox_count() != n0
    parts.append(f"late row delivered {arrived}")
    if not ok or arrived:
        bad.append("X")
    return ("PASS" if not bad else "FAIL"), "; ".join(parts)

@case("TW20", covers=_COV, tags=("gesture", "audio"), engine="wispr", lab_only=True, pre=needs_wispr,
      expect="Wispr killed mid-sentence: the quit noticed within 0.6 s (`wisprLive.ownTake`, a flash) and NOT taken as "
             "his stop — the relay records on; his stop after the clip delivers the whole take via local-fallback "
             "into the witness; the next 🔼→ delivers")
def tw20():
    """Wispr quit mid-sentence (lab; D TW20, W-B3 row *quit*). Batch 4 (2026-09-29) changed the bar:
    until wave 4 the quit ended the sentence (`listening` down ≤ 0.6 s) and the relay's recording with
    it — 0.2 s voiced, Recover only. Now the quit is noticed at once (the exit watch; ≤ 0.6 s is still
    the bar, read off `ownTake`) and the relay's own recording carries the sentence to his stop."""
    bind_witness(); witness_clear(); mic_override(LOOPBACK)
    old_pid = wispr_pid()
    mark = log_mark(); gesture("forward-right")
    time.sleep(0.5)
    import threading
    th = threading.Thread(target=lambda: play(CLIP_SPEECH, seconds=8), daemon=True); th.start()
    time.sleep(2.0)
    post("/test/wispr-proc", {"kill": True}); t0 = time.time()
    held = wait_for(lambda: bool(live().get("ownTake")), 5, 0.05)
    dt = time.time() - t0
    still = state()["listening"]
    th.join(15)
    if state()["listening"]:
        gesture("forward-right")
    # The words in the witness, or a line saying none will come (Recover / no words) — waves 4–5 sat
    # out the full 40 s + 10 s on that second outcome.
    wait_for(lambda: witness_text().strip() or log_has(mark, NO_WORDS), tmo("q14_terminal"), 0.5)
    ok1 = bool(witness_text().strip())
    if ok1:
        wait_for(lambda: log_has(mark, r"📦 delivery: "), tmo("terminal"), 0.3)
    txt = log_since(mark)
    d = re.search(r"📦 delivery: (\S+) → (\S+)", txt)
    v = re.findall(r"wispr meter: ([\d.]+) s voiced", txt)
    post("/test/wispr-proc", {"relaunch": True})
    wait_for(lambda: engine()["ready"] and wispr_pid() not in (0, old_pid), tmo("wispr_relaunch"))   # a NEW pid (wave 2)
    time.sleep(3)
    witness_clear(); m2 = log_mark()
    dictate_loopback(CLIP_EN)
    # Lab wave 2 (2026-09-28): W1r read the witness at `words landed`, 6 s before the local
    # fallback's `📦 delivery` reached the tab — wait for the witness text itself.
    ok2 = bool(wait_for(lambda: witness_text().strip() or log_has(m2, NO_WORDS), tmo("q14_terminal"), 0.5)) \
        and bool(witness_text().strip())
    note = (f"quit noticed in {dt:.2f} s ({bool(held)}), still listening {still}; first sentence {d.groups() if d else None}, "
            f"voiced {v[-1] if v else '-'} s, witness {ok1}; next sentence delivered {ok2}; capture {live()['captureOpen']}")
    ok = held and dt <= 0.6 and still and ok1 and d and d.group(1) == "local-fallback" and ok2
    return ("PASS" if ok else "BUG"), note

@case("TW21", covers=_COV_EL, tags=("gesture", "audio"), engine="eleven", pre=lambda: None if "wisprLive" in state() else "no hooks",
      expect="after /test/dictation/start {clock} + cancel, a real sentence's marker cue is on the recorder's ruler")
def tw21():
    """D §W-D13 note (desk, Engine ElevenLabs → the fake Scribe): `/test/dictation/start
    {"clock": true}` swaps `markerClock` for the wall clock and nothing puts it back until the
    next `wireDictationSource` — a real sentence after it files its shot at the wall clock's
    offset, not the recorder's (off by the microphone's open latency)."""
    post("/test/dictation/start", {"clock": True}); time.sleep(0.5)
    post("/test/cancel"); wait_for(lambda: not state()["listening"], 5); time.sleep(1.0)
    mic_override(LOOPBACK)
    mark = log_mark()
    gesture("forward-right")
    t_mic = wait_for(lambda: log_has(mark, r"mic: recording through") and time.time(), 8, 0.02)
    started = state().get("dictationStartedAt")
    if not t_mic or not started:
        post("/test/cancel")
        return "ERROR", "the recorder never opened"
    time.sleep(1.2)
    t_shot = time.time()
    post("/test/area", {})
    play(CLIP_EN)
    gesture("forward-right")
    wait_delivered(mark, 40)
    m = re.search(r"⏱️ marker cue: \S+ \d+ at ([\d.]+)s", log_since(mark))
    if not m:
        return "FAIL", "no marker cue line"
    cue = float(m.group(1))
    st = datetime.datetime.fromisoformat(started.replace("Z", "+00:00")).timestamp()
    wall, rec = t_shot - st, t_shot - t_mic
    note = f"cue {cue:.2f} s; wall-clock offset {wall:.2f} s; recorder offset ≈ {rec:.2f} s (±0.1)"
    if abs(wall - rec) < 0.15:
        return "SKIP", note + " — the mic opened within 0.15 s of the gesture; the two rulers cannot be told apart"
    if abs(cue - rec) <= 0.15:
        return "PASS", note
    if abs(cue - wall) <= 0.15:
        return "BUG", note
    return "FAIL", note


# ---------------------------------------------------------------- TW22: W2 + Q14 (2026-09-28)
@case("TW22", covers=_COV, tags=("desk", "audio"), engine="wispr", pre=needs_desk,
      expect="a NULL row with no microphone behind it gives up within ~3 s of the close and the relay's own "
             "recording (≥ 1.5 s voiced) is transcribed by the local model and delivered (Q14), not a 30 s wait")
def tw22():
    """W2 / W3 / Q14 (desk): Wispr makes its row at the chord and never opens its microphone (the row
    stays NULL). The relay records the sentence itself from the gesture (Loopback clip); at the stop
    the NULL-no-mic ceiling (3 s) ends it and `endWithRecording` hands the WAV to the local model,
    delivered to the bound witness with `via: local-fallback`. Before 2026-09-28: `Transcribing` for
    30 s, then *No words came back*, the audio thrown away."""
    db = desk()
    bind_witness(); witness_clear()
    mark = log_mark()
    rid = open_sentence(db)                     # row NULL, never updated
    play(CLIP_SPEECH, seconds=6)
    t_stop = time.time()
    chord(state_="stop")
    gave_up = wait_for(lambda: log_has(mark, r"never opened its microphone"), 12, 0.2)
    dt = time.time() - t_stop
    delivered = wait_for(lambda: witness_text().strip() != "", 90, 0.5)
    wait_for(lambda: log_has(mark, r"📦 delivery: "), 10, 0.3)
    txt = log_since(mark)
    # Since the auto p98 fallback (AutoLocal, 2026-09-28) the clock may hand the take over first.
    fell_back = re.search(r"local model (stands in \(Q14\)|takes it)", txt) is not None
    m = re.search(r"📦 delivery: (\S+)", txt)
    via = m.group(1) if m else None
    note = (f"gave up {bool(gave_up)} {dt:.1f} s after the stop; fallback line {fell_back}; delivered {bool(delivered)} "
            f"({len(witness_text())} chars, via {via}); 'No words came back' {'No words came back' in txt}")
    db.update(rid, status="dismissed")
    return ("PASS" if gave_up and dt < 8 and fell_back and delivered and via in ("local-fallback", "local-auto") else "BUG"), note


# ---------------------------------------------------------------- TW32: B, the row-aware tail (2026-09-28, wave 3)
@case("TW32", covers=_COV, tags=("desk",), engine="wispr", pre=needs_desk,
      expect="in the relay's 10 s tail: a Wispr ⌘V with no newer row is the relay's (dropped, said so); "
             "once his newer row exists, his ⌘V passes (B / Q19) — never dropped silently")
def tw32():
    """B (lab wave 2, 8/8 of his sentences eaten): the firewall's tail after a relay sentence went
    idle was a clock. Desk: relay sentence A on the fake row, delivered; a ⌘V through the firewall's
    decision (`POST /test/wispr-paste`, no key on the wire) at +0.5 s → the relay's own late paste
    (dropped, the claim says so, nothing pasted); then his row F (newer, `formatted`) and a second
    ⌘V inside the tail → **passed** (Wispr pastes it itself). Nothing is pasted at his caret here:
    the pass is a verdict only (no key exists), the drop's claim finds no row of his."""
    db = desk()
    bind_witness(); witness_clear()
    mark = log_mark()
    ra = open_sentence(db); time.sleep(0.8)
    close_sentence(db, ra, text="tw thirty two relay sentence")
    wait_for(lambda: "thirty two relay" in witness_text(), 15, 0.3)
    idle = wait_for(lambda: not live()["captureOpen"] and live()["relayOwned"], 10, 0.1)
    time.sleep(0.5)
    own = post("/test/wispr-paste", {})[1]
    time.sleep(0.2)
    rf = db.insert(at=time.time()); time.sleep(0.6)
    db.finish(rf, "his own sentence in the tail")
    noted = wait_for(lambda: live().get("foreignRow") == rf, 4, 0.1)
    lv = live()
    his = post("/test/wispr-paste", {})[1]
    wait_for(lambda: log_has(mark, r"the dropped ⌘V is not his"), 3, 0.1)
    txt = log_since(mark)
    in_tail = lv["relayOwned"] is False and lv["relayOwnedUntil"] is not None
    relay_said = re.search(r"the relay's own late ⌘V", txt) is not None
    passed_line = re.search(r"⌘V from Wispr Flow passed — row \d+ is newer than the relay's", txt) is not None
    note = (f"idle {bool(idle)}; relay's tail ⌘V {own.get('verdict')} ({own.get('why')}); said relay's own {relay_said}; "
            f"his row {rf} noted {bool(noted)}; his ⌘V {his.get('verdict')} ({his.get('why')}); pass line {passed_line}; "
            f"still inside the tail window {in_tail}")
    ok = own.get("verdict") == "dropped" and relay_said and noted and his.get("verdict") == "passed" and passed_line
    return ("PASS" if ok else "BUG"), note


# ---------------------------------------------------------------- TW33: D, a fallback in flight is parked (wave 3)
@case("TW33", covers=_COV, tags=("desk", "audio"), engine="wispr", pre=needs_desk,
      expect="sentence A's Wispr row never moves → Q14 local fallback; 🔼→ B 1 s into that decode: A is parked, "
             "not closed; both in the witness, A first; no 'which is over — dropped'")
def tw33():
    """D (lab wave 2: TS1 #11 and #20, 948 chars lost silently). `dictationBegan` closed a live sentence
    whose Q14 local decode was still out, and the decode's answer was dropped. Desk: A = NULL row + the
    clip on the Loopback → the NULL-no-mic ceiling → the local model (TW22's path); 1 s after the fallback
    line, 🔼→ B (the real gesture → `startDictation`), a fake row finished with words."""
    db = desk()
    bind_witness(); witness_clear()
    mark = log_mark()
    # A opened by the real gesture (🔼→ → `startDictation`, as in the lab), its row NULL for good.
    gesture("forward-right")
    if not wait_for(lambda: state()["listening"], 4):
        return "FAIL", "A did not open"
    ra = db.insert(at=time.time())
    wait_for(lambda: live()["captureRow"] == ra, 3)
    time.sleep(2.3)                                     # past the 2 s stop dwell
    # 45 s of speech: a warm local model decodes 10 s in 0.8 s (0.077×), so A's decode has to be
    # long enough (~3–4 s) for B to open inside it.
    play(CLIP_EN_LONG, seconds=45)
    gesture("forward-right")
    fb = wait_for(lambda: log_has(mark, r"the local model stands in \(Q14\)"), 15, 0.1)
    if not fb:
        db.update(ra, status="dismissed")
        return "FAIL", "A never fell back to the local model"
    time.sleep(0.5)
    m2 = log_mark()
    gesture("forward-right")
    opened = wait_for(lambda: state()["listening"], 4)
    if not opened:
        wait_for(lambda: len(witness_text().strip()) > 20, 60, 0.5)
        wait_for(lambda: not relay_busy(), 60, 0.5)
        txt = log_since(mark)
        loud = re.search(r"🚫 start refused[^\n]*still being transcribed locally[^\n]*", log_since(m2))
        dropped = "which is over — dropped" in txt
        db.update(ra, status="dismissed")
        note = (f"B not opened; refusal {loud.group(0)[:120] if loud else None}; A in the witness "
                f"{len(witness_text().strip())} chars; 'dropped' {dropped}")
        ok = loud is not None and not dropped and len(witness_text().strip()) > 20
        return ("PASS" if ok else "BUG"), note + (" (D's second option: refused out loud, A delivered)" if ok else "")
    rb = db.insert(at=time.time())
    adopted = wait_for(lambda: live()["captureRow"] == rb, 3)
    time.sleep(2.3)                                     # past the 2 s stop dwell
    gesture("forward-right")
    db.update(rb, status="processing", speech=1.5); time.sleep(0.3)
    db.finish(rb, "tw thirty three sentence bee")
    wait_for(lambda: "sentence bee" in witness_text() and len(witness_text()) > 60, 90, 0.5)
    wait_for(lambda: not relay_busy(), 60, 0.5)
    got = witness_text()
    txt = log_since(mark)
    ib = got.find("sentence bee")
    a_len = len(got[:ib].strip()) if ib >= 0 else len(got.strip())
    parked = "goes on transcribing behind the next one" in log_since(m2)
    dropped = "which is over — dropped" in txt
    refused = re.search(r"🚫 start refused[^\n]*", log_since(m2))
    note = (f"B opened {bool(opened)} (row adopted {bool(adopted)}); A parked {parked}; B refused "
            f"{refused.group(0)[:90] if refused else False}; A {a_len} chars before B at {ib}; 'dropped' {dropped}")
    db.update(ra, status="dismissed")
    return ("PASS" if opened and parked and not dropped and ib > 0 and a_len > 20 else "BUG"), note


# ---------------------------------------------------------------- TW34: A, the relay's recorder right after a Wispr launch (wave 3)
KEEP_MARK = "# keep-takes: written by evals/plan/cases_wispr.py TW34, removed after it"

def _keep_takes(on):
    """`WT_KEEP_TAKES=1` in `elevenlabs.env` between two marks (every relay Wispr take copied to
    ~/.walkie-talkie/kept-takes/ before any delete); removed with `on=False`."""
    try:
        cur = open(ELEVEN_ENV, encoding="utf-8").read().splitlines()
        mode = os.stat(ELEVEN_ENV).st_mode & 0o777
    except FileNotFoundError:
        cur, mode = [], 0o600
    keep, inside = [], False
    for l in cur:
        if l.startswith(KEEP_MARK):
            inside = not l.endswith("(end)")
            continue
        if not inside:
            keep.append(l)
    if on:
        keep += [KEEP_MARK, "WT_KEEP_TAKES=1", KEEP_MARK + " (end)"]
    tmp = ELEVEN_ENV + ".keep-tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write("\n".join(keep) + ("\n" if keep else ""))
    os.chmod(tmp, mode)
    os.replace(tmp, ELEVEN_ENV)

CLEANUPS.append(lambda: _keep_takes(False))

@case("TW34", covers=_COV, tags=("desk", "audio", "cold"), engine="wispr",
      pre=lambda: needs_desk() or (None if KILL_OK else "relaunches his Wispr: WT_ALLOW_WISPR_KILL=1 or the lab"),
      expect="a relay sentence opened +1/+3/+5 s after a Wispr relaunch records the clip (≥ 1.5 s voiced, "
             "never DEAF, never 'No speech was heard'); any mid-take device change restarts the tap, logged")
def tw34():
    """A (lab wave 2: 4× `0.0 s voiced` within ~5 s of a Wispr launch, BlackHole itself not silent).
    Desk rig (fake History, chords muted, recorder on the Loopback): relaunch the real Wispr, wait for
    the new pid, then at +1 / +3 / +5 s open a relay Wispr sentence with no row (nothing is adopted —
    the relay's own recording is the whole point), play CLIP_SPEECH 6 s, stop. Reads per take the
    `wispr meter:` health line (buffers, peak, tap restarts, device), `micOpened`, any `🔁 mic:` line;
    the WAVs are kept (`WT_KEEP_TAKES=1`)."""
    db = desk()
    _keep_takes(True)
    bind_witness(); witness_clear()
    rows = []
    for d in (1.0, 3.0, 5.0):
        old = wispr_pid()
        post("/test/wispr-proc", {"relaunch": True})
        if not wait_for(lambda: wispr_pid() and wispr_pid() != old, 30, 0.1):
            rows.append(f"+{d:.0f}s: Wispr did not come back"); continue
        t_new = time.time()
        time.sleep(max(0.0, d - (time.time() - t_new)))
        mark = log_mark()
        chord(state_="start")
        wait_for(lambda: state()["listening"], 3)
        play(CLIP_SPEECH, seconds=6)
        chord(state_="stop")
        wait_for(lambda: log_has(mark, r"wispr meter: "), 15, 0.2)
        wait_for(lambda: not relay_busy(), 90, 0.5)
        txt = log_since(mark)
        m = re.search(r"wispr meter: ([\d.]+) s voiced — ([^\n]*)", txt)
        voiced = float(m.group(1)) if m else -1.0
        health = m.group(2) if m else "no meter line"
        restarts = re.findall(r"🔁 mic: ([^\n]*)", txt)
        mo = state().get("micOpened") or {}
        nospeech = "No speech was heard" in txt
        deaf = "DEAF" in health
        rows.append({"d": d, "voiced": voiced, "health": health, "restarts": restarts, "nospeech": nospeech,
                     "deaf": deaf, "micOpened": f"{mo.get('device')} {mo.get('rate')} Hz × {mo.get('channels')}"})
        time.sleep(2)
    _keep_takes(False)
    lines = []
    bad = False
    for r in rows:
        if isinstance(r, str):
            lines.append(r); bad = True; continue
        lines.append(f"+{r['d']:.0f}s: {r['voiced']:.1f} s voiced ({r['health']}); opened {r['micOpened']}; "
                     f"restarts {r['restarts'] or 0}; 'No speech' {r['nospeech']}")
        bad |= r["voiced"] < 1.5 or r["deaf"] or r["nospeech"]
    return ("BUG" if bad else "PASS"), " | ".join(lines)


# ---------------------------------------------------------------- TW35–TW39: batch 3 (2026-09-28, night)
# `evals/plan/wispr/integration-surfaces.md`, "Recommended change to WisprFlowSource" 1–4.

def _ended(t0, timeout):
    """Seconds from t0 until the capture let go (None: it did not within `timeout`)."""
    return (time.time() - t0) if wait_for(lambda: not live()["captureOpen"], timeout, 0.05) else None

@case("TW35", covers=_COV, tags=("desk",), engine="wispr", pre=needs_desk,
      expect="raw_transcript with no words ends the sentence at once (Q14 path, not an 8 s wait); "
             "`fallback` with words is delivered at once from the row (it used to be an unknown status → failure)")
def tw35():
    """Batch 3 item 1. Wispr's own code writes `raw_transcript`, `fallback`, `verification_failed`,
    `timeout` only in its final update; `WisprState` read `raw_transcript` as progress (8 s
    `silenceCeiling` when empty, 0.8 s `rawTextGrace` with words) and did not know `fallback` at all
    (→ the unknown-status failure: Wispr's words thrown away, the local model instead). Desk: (a)
    sentence A, row → `processing` → `raw_transcript` with every text column empty: the capture must
    let go within ~1 s, through `endWithRecording` (Recover — the Loopback is silent); (b) sentence
    B, row → `fallback` with words: delivered to the witness, `via: wispr-history`, at once."""
    db = desk()
    bind_witness(); witness_clear()
    mark = log_mark()
    ra = open_sentence(db); time.sleep(0.5)
    chord(state_="stop"); db.update(ra, status="processing", duration=1.5); time.sleep(0.3)
    t0 = time.time(); db.update(ra, status="raw_transcript", asr="", formatted="", pasted="", e2e=300.0)
    da = _ended(t0, 10)
    wait_for(lambda: not relay_busy(), 15, 0.2)
    txt_a = log_since(mark)
    a_line = re.search(r"raw_transcript with no words[^\n]*", txt_a)
    time.sleep(2.2)                                     # past the 2 s stop dwell
    m2 = log_mark()
    rb = open_sentence(db); time.sleep(0.5)
    chord(state_="stop"); db.update(rb, status="processing", duration=1.5); time.sleep(0.3)
    t1 = time.time(); db.finish(rb, "tw thirty five fallback words", status="fallback")
    db_ = _ended(t1, 10)
    got = wait_for(lambda: "thirty five fallback" in witness_text(), 10, 0.1)
    wait_for(lambda: log_has(m2, r"📦 delivery: "), 10, 0.2)
    txt_b = log_since(m2)
    via = re.search(r"📦 delivery: (\S+)", txt_b)
    unknown = re.search(r"wispr history: fallback — ", txt_b) is not None
    note = (f"(a) raw_transcript empty: capture let go {('%.2f s' % da) if da is not None else 'NOT within 10 s'} after the "
            f"write, line {bool(a_line)}; (b) fallback: let go {('%.2f s' % db_) if db_ is not None else 'NOT'}, "
            f"witness {bool(got)}, via {via.group(1) if via else None}, unknown-status line {unknown}")
    ok = da is not None and da < 1.5 and a_line and db_ is not None and db_ < 1.5 and got \
        and via and via.group(1) == "wispr-history" and not unknown
    return ("PASS" if ok else "BUG"), note

@case("TW36", covers=_COV, tags=("desk",), engine="wispr", pre=needs_desk,
      expect="the relay's row still `processing` when a newer row appears (his own dictation) is dead at once: "
             "the sentence ends through Q14 within ~1 s, no 'waiting on (Q2)', and Wispr's ⌘V is not held for 5 min")
def tw36():
    """Batch 3 item 2(a). Wispr keeps one live dictation: a newer row means the relay's was superseded
    and Wispr abandons it (*"Skipping finalization — dictation was superseded while transcribing"*) —
    it stays `processing` for ever. Q24 waited on it (≤ 300 s), then `watchLateRow` held every Wispr
    ⌘V as the relay's for 5 more minutes. Desk: relay sentence A, row `processing`; 1 s later his row
    B (NULL). Asserts the capture lets go ≤ 1.5 s after B, the dead-row line, the late-row hold let go
    (`the row the relay gave up on is dead`), and a ⌘V through the firewall's decision afterwards is
    not held (`/test/wispr-paste`: no 'a row the relay gave up on is still being watched')."""
    db = desk()
    mark = log_mark()
    ra = open_sentence(db); time.sleep(0.5)
    chord(state_="stop"); db.update(ra, status="processing", duration=1.5)
    time.sleep(1.0)
    t0 = time.time(); rb = db.insert(at=time.time())
    d = _ended(t0, 10)
    wait_for(lambda: log_has(mark, r"its hold on Wispr's ⌘V is let go"), 5, 0.1)
    wait_for(lambda: not relay_busy(), 15, 0.2)
    txt = log_since(mark)
    dead = re.search(r"row %d is still processing and row %d is newer[^\n]*" % (ra, rb), txt)
    let_go = "its hold on Wispr's ⌘V is let go" in txt
    q2 = "waiting on" in txt
    time.sleep(1.8)                                    # past the relay's 1.5 s paste wait in the tail
    v = post("/test/wispr-paste", {"dryClaim": True})[1]
    held = "still being watched" in (v.get("why") or "")
    note = (f"capture let go {('%.2f s' % d) if d is not None else 'NOT within 10 s'} after the newer row; dead line {bool(dead)}; "
            f"late-row hold let go {let_go}; Q2 wait {q2}; a later ⌘V: {v.get('verdict')} ({v.get('why')})")
    db.update(rb, status="dismissed")
    ok = d is not None and d < 1.5 and dead and let_go and not q2 and not held
    return ("PASS" if ok else "BUG"), note

@case("TW37", covers=_COV, tags=("desk",), engine="wispr", pre=needs_desk,
      expect="a cancel during the settle (the relay's own ⌃Escape) with the row still `processing`: "
             "the discard capture closes ~1 s after the dismiss, not at the 30 s capture timeout")
def tw37():
    """Batch 3 item 2(c). Wispr abandons a dictation dismissed during processing — the row stays
    `processing`. The cancel keeps the swallow armed until Wispr is done (`discardOnArrival`), and
    'done' never came: the capture stood 30 s (`captureTimeout`). Desk: sentence A stopped, row
    `processing`, `POST /test/cancel` 0.3 s later (chords muted: the ⌃Escape is its stamped tail only);
    the capture must close 1.0–2.0 s after the cancel, with the dead-row line naming the dismiss."""
    db = desk()
    mark = log_mark()
    ra = open_sentence(db); time.sleep(0.5)
    chord(state_="stop"); db.update(ra, status="processing", duration=1.5)
    time.sleep(0.3)
    t0 = time.time(); post("/test/cancel")
    d = _ended(t0, 35)
    txt = log_since(mark)
    line = re.search(r"still processing [\d.]+ s after the relay's dismiss[^\n]*", txt)
    note = f"discard capture closed {('%.2f s' % d) if d is not None else 'NOT within 35 s'} after the cancel; line {bool(line)}"
    db.update(ra, status="dismissed")
    return ("PASS" if d is not None and 0.9 <= d < 2.5 and line else "BUG"), note

@case("TW38", covers=_COV, tags=("desk",), engine="wispr", pre=needs_desk,
      expect="WAL watch: every row change the capture reads is seen ≤ 50 ms after the fake's commit "
             "(Wispr's journal mode), woken by `flow.sqlite-wal`, not the 1 s tick")
def tw38():
    """Batch 3 item 3. The row readers woke on a 150 ms timer (a row seen 75 ms late on average,
    the timer running whether or not Wispr wrote). Now a kqueue source on `flow.sqlite-wal` (+ the
    main file) wakes them, gated by `PRAGMA data_version`, with a 1 s safety tick. Desk: the fake in
    **WAL mode** (a holder connection, as under a running Wispr); two relay sentences, each: insert
    (adoption), `processing`, `formatted` — six commits. Per commit, `wisprLive.rowSeen.epoch` (the
    reader's wall clock) minus the harness's time just before the commit."""
    db = desk(wal=True)
    bind_witness(); witness_clear()
    lat, wake0 = [], live().get("historyWake") or {}
    def seen(rid, status, t):
        # `epoch` after the write: a fresh fake reuses rowid 1, and the last case's rowSeen may match.
        ok = wait_for(lambda: (live().get("rowSeen") or {}).get("rowid") == rid
                      and (live().get("rowSeen") or {}).get("status") == status
                      and (live().get("rowSeen") or {}).get("epoch", 0) >= t - 0.002, 3, 0.02)
        if ok:
            lat.append(((live()["rowSeen"]["epoch"]) - t) * 1000)
        return ok
    watching = None
    for i in (1, 2):
        chord(state_="start")
        wait_for(lambda: state()["listening"], 3)
        watching = (live().get("historyWake") or {}).get("watching")
        t = time.time(); rid = db.insert(at=time.time()); seen(rid, "", t)
        time.sleep(0.4)
        chord(state_="stop")
        time.sleep(0.2)
        t = time.time(); db.update(rid, status="processing", duration=1.5); seen(rid, "processing", t)
        time.sleep(0.2)
        # `formatted` ends the capture in the same pass that sees it: rowSeen is set first.
        t = time.time(); db.finish(rid, "tw thirty eight sentence %d" % i); seen(rid, "formatted", t)
        wait_for(lambda: "sentence %d" % i in witness_text(), 10, 0.1)
        wait_for(lambda: not relay_busy(), 15, 0.2)
        time.sleep(2.2)
    wake1 = live().get("historyWake") or {}
    ev = wake1.get("events", 0) - wake0.get("events", 0)
    lat_s = ", ".join("%.0f" % x for x in lat)
    note = (f"{len(lat)}/6 changes seen; latency ms [{lat_s}] (max {max(lat) if lat else -1:.0f}); watching {watching}; "
            f"file events +{ev}, queries {wake1.get('queries')}, cache hits {wake1.get('cacheHits')}")
    ok = len(lat) == 6 and max(lat) <= 50 and watching and "flow.sqlite-wal" in watching and ev > 0
    return ("PASS" if ok else "BUG"), note

@case("TW39", covers=_COV, tags=("desk",), engine="wispr", pre=needs_desk,
      expect="a ⌘V dropped in the relay's tail while his newer row is still NULL: the pasteboard is read once "
             "and kept; the row's words win if they come, the pasteboard's only if they do not; never pasted twice")
def tw39():
    """Batch 3 item 4 (dry claim: nothing reaches his caret). Wispr pastes *before* its final write, so
    at the dropped ⌘V his row is often still NULL/`processing` while its promised pasteboard item is
    there — gone at Wispr's restore 500 ms later. Desk, twice after a relay sentence A delivered (the
    tail's first 1.5 s, so the ⌘V is dropped and claimed): (a) his row B NULL, the clipboard set to
    `PB-A`, the ⌘V, then B finished with other words 0.3 s later → the claim pastes **the row's**
    words; (b) his row C NULL for good, clipboard `PB-C` → after the claim's 5 s, **the pasteboard's**;
    then C finished and a second ⌘V → nothing pasted a second time. His clipboard text is put back."""
    db = desk()
    bind_witness(); witness_clear()
    saved = subprocess.run(["pbpaste"], capture_output=True).stdout
    def pb(text):
        subprocess.run(["pbcopy"], input=text.encode())
    def claim_after(ra_text, prepare):
        # 2.5 s, not 0.5: his row is inserted the moment the capture lets go, and a row opened
        # within ~1 s of the relay's own chord is the relay's (B-risk, TX6b) — never claimed.
        ra = open_sentence(db); time.sleep(2.5)
        close_sentence(db, ra, text=ra_text)
        # Lab wave 4 (batch 4): the tail's 1.5 s runs from the capture's end, not from the words
        # reaching the witness — on a slow guest the prompt panel took ~4 s, the tail watch had
        # already noted his row, and the ⌘V passed (B), correctly. Claim as soon as the capture
        # lets go; the witness is checked afterwards.
        wait_for(lambda: not live()["captureOpen"], 15, 0.02)
        rid = db.insert(at=time.time())
        board = prepare(rid)
        v = post("/test/wispr-paste", {"dryClaim": True})[1]
        return rid, board, v
    try:
        mark = log_mark()
        rb, _, va = claim_after("tw thirty nine relay a", lambda rid: pb("PB-A pasteboard words"))
        time.sleep(0.3)
        db.finish(rb, "row b words of his own")
        wait_for(lambda: (live().get("lastForeignClaim") or {}).get("row") == rb, 6, 0.1)
        ca = live().get("lastForeignClaim") or {}
        wait_for(lambda: "tw thirty nine relay a" in witness_text(), 15, 0.1)
        wait_for(lambda: not relay_busy(), 15, 0.2)
        time.sleep(2.2)
        rc, _, vc = claim_after("tw thirty nine relay c", lambda rid: pb("PB-C pasteboard words"))
        wait_for(lambda: (live().get("lastForeignClaim") or {}).get("row") == rc, 8, 0.1)
        cc = live().get("lastForeignClaim") or {}
        db.finish(rc, "row c words, too late")
        time.sleep(0.5)
        v2 = post("/test/wispr-paste", {"dryClaim": True})[1]
        time.sleep(1.5)
        txt = log_since(mark)
        claims_c = len(re.findall(r"dry claim[^\n]*row %d's" % rc, txt))
        read_once = len(re.findall(r"the pasteboard read once", txt))
    finally:
        subprocess.run(["pbcopy"], input=saved)
    # A slow guest can still be past the tail's 1.5 s at the ⌘V: his row noted, the ⌘V passed —
    # right by B (wave 4). Then (a) did not exercise the claim; said, not failed.
    a_passed_b = va.get("verdict") == "passed" and re.search(r"row %d [^\n]*is his[^\n]*passes now \(B\)" % rb, txt)
    note = (f"(a) ⌘V {va.get('verdict')}{' (his row already noted — B, the tail outran on this machine)' if a_passed_b else ''}; "
            f"claim row {ca.get('row')} from {ca.get('source')} ({ca.get('chars')} chars); "
            f"(b) ⌘V {vc.get('verdict')}; claim row {cc.get('row')} from {cc.get('source')} ({cc.get('chars')} chars); "
            f"second ⌘V {v2.get('verdict')}; dry claims of C {claims_c}; pasteboard reads {read_once}")
    ok_a = (va.get("verdict") == "dropped" and ca.get("row") == rb and str(ca.get("source", "")).startswith("the row")
            and ca.get("chars") == len("row b words of his own")) or bool(a_passed_b)
    ok = (ok_a
          and vc.get("verdict") == "dropped" and cc.get("row") == rc and str(cc.get("source", "")).startswith("the pasteboard")
          and cc.get("chars") == len("PB-C pasteboard words") and claims_c == 1 and read_once == (1 if a_passed_b else 2))
    return ("PASS" if ok else "BUG"), note


# ---------------------------------------------------------------- TW40: D2, the sentence behind a parked fallback (lab wave 3)
@case("TW40", covers=_COV, tags=("desk", "audio"), engine="wispr", pre=needs_desk,
      expect="A's Wispr row never moves → Q14 local decode, parked by B; B's row formatted BEFORE A's decode ends: "
             "when A is delivered, B follows at once — both in the witness, A first; no 'wait for the one before' past A")
def tw40():
    """D2 (lab wave 3, TW33: B's words waited behind parked A for 151 s, then were dropped). The desk
    TW33 never had B's words arrive while A was still decoding — a warm model finished first. Here
    the local helper is SIGSTOPped (`/test/whisper {"stop"}`) the moment A falls back, B is opened,
    stopped and finished on its fake row, and only then is the helper resumed."""
    db = desk()
    bind_witness(); witness_clear()
    was_auto = bool(state().get("autosend"))
    post("/test/autosend", {"on": True})
    mark = log_mark()
    chord(state_="start")   # the relay's own gesture, no key (the screen may be locked)
    if not wait_for(lambda: state()["listening"], 4):
        return "FAIL", "A did not open"
    ra = db.insert(at=time.time())
    wait_for(lambda: live()["captureRow"] == ra, 3)
    time.sleep(2.3)
    play(CLIP_SPEECH, seconds=6)
    chord(state_="stop")
    # Q14's NULL-row fallback, or the auto p98 hand-over (AutoLocal) — both park A while it decodes.
    if not wait_for(lambda: log_has(mark, r"the local model (stands in \(Q14\)|takes it)"), 15, 0.05):
        db.update(ra, status="dismissed")
        return "FAIL", "A never fell back to the local model"
    stopped = post("/test/whisper", {"stop": True})[0] == 200
    try:
        time.sleep(0.9)
        m2 = log_mark()
        chord(state_="start")
        if not wait_for(lambda: state()["listening"], 4):
            return "FAIL", "B did not open (%s)" % (re.search(r"🚫 start refused[^\n]*", log_since(m2)) or [None])[0]
        rb = db.insert(at=time.time())
        wait_for(lambda: live()["captureRow"] == rb, 3)
        time.sleep(2.3)
        chord(state_="stop")
        db.update(rb, status="processing", duration=1.5); time.sleep(0.3)
        db.finish(rb, "tw forty sentence bee")
        waited = wait_for(lambda: log_has(m2, r"landed before #\d+ — it waits its turn"), 6, 0.1)
        time.sleep(1.0)
    finally:
        if stopped:
            post("/test/whisper", {"cont": True})
    t_cont = time.time()
    got_b = wait_for(lambda: "sentence bee" in witness_text(), 20, 0.3)
    queue = state().get("sentences")
    dt = time.time() - t_cont
    wait_for(lambda: not relay_busy(), 30, 0.5)
    got = witness_text()
    ib = got.find("sentence bee")
    a_len = len(got[:ib].strip()) if ib >= 0 else len(got.strip())
    txt = log_since(mark)
    stuck = len(re.findall(r"words wait for the one before", txt))
    dropped = "which is over — dropped" in txt or "cancelled and dropped" in txt
    post("/test/autosend", {"on": was_auto})
    db.update(ra, status="dismissed")
    note = (f"helper stopped {stopped}; B waited its turn {bool(waited)}; B in the witness {bool(got_b)} "
            f"{dt:.1f} s after the resume; A {a_len} chars before B at {ib}; 'wait for the one before' ×{stuck}; dropped {dropped}; "
            f"queue after the resume {queue}")
    return ("PASS" if stopped and waited and got_b and ib > 0 and a_len > 20 and not dropped else "BUG"), note


# ---------------------------------------------------------------- batch 4 (2026-09-29): lab wave 4's findings at a desk
def _direct(name):
    """The gesture's own handler, no chord on the wire (`/test/gesture {"direct": true}`, batch 4) —
    a locked screen's Secure Input hides every posted key from the tap."""
    code, body = post("/test/gesture", {"name": name, "direct": True})
    if code != 200:
        raise RuntimeError(f"direct {name}: {code} {body}")
    return body

def _bg_play(clip, seconds=None):
    import threading
    th = threading.Thread(target=lambda: play(clip, seconds=seconds), daemon=True)
    th.start()
    return th

@case("TW41", covers=_COV, tags=("desk", "audio"), engine="wispr", pre=needs_desk,
      expect="F1: after a cancelled caret sentence, a bound relay sentence Wispr never answers (no row, no microphone) "
             "is NOT ended at 12 s — the relay's own recording carries it (listening, `ownTake`); his stop 🔼→ at ~15 s "
             "closes it and latches the witness; the Q14 answer lands in the witness via local-fallback, never at the caret")
def tw41():
    """F1 (lab wave 4, TW4 run 1): `done(timeout)` at 12 s ended the sentence under him — the relay's
    recording cut, a Q14 decode with `listening` still up, nothing latched (Q2), and the case's stop 🔼→
    at 16 s met `🧷 stuck listening? … no recorder behind it` while the answer went to the caret the
    previous (clean, cancelled) sentence had latched: `📦 delivery: local-fallback → caret`. Desk, keyless:
    (1) a caret prompt opened and cancelled (`forward-click` direct) — the stale caret latch; (2) the
    bound sentence (`forward-right` direct), no row ever, CLIP_SPEECH into the Loopback; at 13 s the
    sentence must still be listening with `wisprLive.ownTake`; (3) the stop (`forward-right` direct) at
    ~15 s; the words land in the witness, `local-fallback → terminal:…`, no `→ caret`, no `🧷 stuck`."""
    db = desk()
    bind_witness(); witness_clear()
    mark = log_mark()
    _direct("forward-click")
    if not wait_for(lambda: state()["listening"], 4):
        return "ERROR", "the caret sentence did not open"
    time.sleep(1.0)
    post("/test/cancel")
    if not wait_for(lambda: not state()["listening"] and not state()["settling"], 10, 0.2):
        return "ERROR", "the caret sentence did not close"
    time.sleep(1.5)
    m1 = log_mark()
    _direct("forward-right")
    if not wait_for(lambda: state()["listening"], 4):
        return "ERROR", "the bound sentence did not open (%s)" % (re.search(r"🚫 start refused[^\n]*", log_since(m1)) or [None])[0]
    t0 = time.time()
    th = _bg_play(CLIP_SPEECH)
    wait_for(lambda: time.time() - t0 >= 13.0, 15, 0.1)
    s13 = state()
    held = s13["listening"] and bool((s13.get("wisprLive") or {}).get("ownTake"))
    early = log_has(m1, r"📦 delivery:")
    th.join(15)
    wait_for(lambda: time.time() - t0 >= 15.0, 5, 0.1)
    _direct("forward-right")
    got = wait_for(lambda: witness_text().strip(), 40, 0.3)
    wait_for(lambda: log_has(m1, r"📦 delivery: "), 10, 0.3)
    txt = log_since(m1)
    d = re.search(r"📦 delivery: (\S+) → (\S+)", txt)
    stuck = "🧷 stuck" in txt
    caret = re.search(r"📦 delivery: \S+ → caret", txt) is not None
    voiced = re.findall(r"wispr meter: ([\d.]+) s voiced", txt)
    note = (f"at 13 s: listening {s13['listening']}, ownTake {(s13.get('wisprLive') or {}).get('ownTake')}; delivered before "
            f"the stop {early}; delivery {d.groups() if d else None}; witness {len(witness_text().strip())} chars; "
            f"voiced {voiced[-1] if voiced else '-'} s; stuck line {stuck}; caret {caret}")
    ok = held and not early and got and d and d.group(1) == "local-fallback" and d.group(2).startswith("terminal:") \
        and not stuck and not caret
    return ("PASS" if ok else "BUG"), note

def _landed(mark, timeout=40):
    """The sentence's delivery line after `mark`: (via, to) or None."""
    wait_for(lambda: log_has(mark, r"📦 delivery: "), timeout, 0.3)
    d = re.search(r"📦 delivery: (\S+) → (\S+)", log_since(mark))
    return d.groups() if d else None

def _open_with_mic(db):
    """A relay sentence whose Wispr microphone the relay SAW open (the simulated CoreAudio edge,
    while the ring is still a guess — once the row confirms it the fake edge is not delivered, so
    its close would have no matching open), then Wispr's row adopted."""
    chord(state_="start")
    if not wait_for(lambda: state()["listening"], 3):
        raise RuntimeError("the relay did not open the sentence")
    post("/test/wispr", {"on": True})
    time.sleep(0.4)
    rid = db.insert(at=time.time())
    if not wait_for(lambda: live()["captureRow"] == rid, 3):
        raise RuntimeError(f"fake row {rid} was not adopted")
    return rid

@case("TW42", covers=_COV, tags=("desk", "audio"), engine="wispr", pre=needs_desk,
      expect="item 3: Wispr quitting mid-sentence (fakeExit + its microphone closing) is not his stop — the relay's "
             "own recording goes on (`ownTake` ≤ 0.6 s), his stop closes it, the WHOLE take is decoded locally into the "
             "witness; the exit a beat after the close (inside the grace) is caught too; a close with Wispr alive still ends the "
             "sentence when the 1.0 s grace runs out (control)")
def tw42():
    """Item 3 (lab wave 4: TQ2 closed the relay's recording at the kill, 1.0 s voiced → Recover only;
    TW20 0.2 s). At a desk his real Wispr is never killed: `POST /test/wispr-proc {"fakeExit"}` makes the
    sentence's Wispr read as exited, `/test/wispr {"on": false}` is the microphone closing with it.
    (a) exit then close, 3 s into CLIP_SPEECH: held, still listening 2 s later, stop after the clip →
    `local-fallback → terminal`, ≥ 3 s voiced (the whole clip is ~4.2 s voiced). (b) close, then the exit 0.1 s later: the 0.3 s grace
    holds it. (c) control: a close with Wispr alive → the sentence closes (no ownTake), row delivered."""
    db = desk()
    bind_witness(); witness_clear()
    notes, bad = [], []
    # (a)
    m = log_mark()
    ra = _open_with_mic(db)
    th = _bg_play(CLIP_SPEECH)
    time.sleep(3.0)
    post("/test/wispr-proc", {"fakeExit": True})
    post("/test/wispr", {"on": False}); tq = time.time()
    held = wait_for(lambda: bool(live().get("ownTake")), 2, 0.05)
    dq = time.time() - tq
    time.sleep(2.0)
    still = state()["listening"]
    th.join(20)
    _direct("forward-right")
    got = wait_for(lambda: witness_text().strip(), 40, 0.3)
    d = _landed(m)
    txt = log_since(m)
    v = re.findall(r"wispr meter: ([\d.]+) s voiced", txt)
    voiced = float(v[-1]) if v else 0.0
    notes.append(f"(a) held {bool(held)} in {dq:.2f} s, listening 2 s on {still}, delivery {d}, voiced {voiced:.1f} s, "
                 f"witness {len(witness_text().strip())} chars")
    if not (held and dq <= 0.6 and still and got and d and d[0] == "local-fallback" and d[1].startswith("terminal:")
            and voiced >= 3.0):   # the whole 12 s clip measures ~4.2 s voiced (TW41); cut at 3 s it was ~1
        bad.append("a")
    db.update(ra, status="dismissed")
    wait_for(lambda: not state()["listening"] and not state()["settling"], 15, 0.2)
    time.sleep(2.2)
    # (b)
    witness_clear(); m = log_mark()
    rb = _open_with_mic(db)
    th = _bg_play(CLIP_SPEECH, seconds=6)
    time.sleep(2.0)
    post("/test/wispr", {"on": False}); time.sleep(0.1)
    post("/test/wispr-proc", {"fakeExit": True})
    held_b = wait_for(lambda: bool(live().get("ownTake")), 2, 0.05)
    th.join(15)
    _direct("forward-right")
    d_b = _landed(m)
    notes.append(f"(b) close then exit: held {bool(held_b)}, delivery {d_b}")
    if not (held_b and d_b and d_b[0] == "local-fallback"):
        bad.append("b")
    db.update(rb, status="dismissed")
    wait_for(lambda: not state()["listening"] and not state()["settling"], 15, 0.2)
    time.sleep(2.2)
    # (c) control
    witness_clear(); m = log_mark()
    rc = _open_with_mic(db); time.sleep(1.2)
    post("/test/wispr", {"on": False}); tc = time.time()
    # Wispr's own end writes `processing` + `duration` ~0.1 s after its microphone closes (2026-09-29:
    # a close the row does not confirm is a blip and waits — `nullRowHold`, TW45).
    time.sleep(0.1); db.update(rc, status="processing", duration=1.5)
    closed = wait_for(lambda: not state()["listening"], 2, 0.05)
    dc = time.time() - tc
    own_c = live().get("ownTake")
    time.sleep(0.3)
    db.finish(rc, "tw forty two control words")
    got_c = wait_for(lambda: "forty two control" in witness_text(), 15, 0.2)
    notes.append(f"(c) Wispr alive: closed {bool(closed)} in {dc:.2f} s, ownTake {own_c}, row delivered {bool(got_c)}")
    # Batch 5: Wispr alive now closes when the 1.0 s grace runs out (`WisprState.quitCloseGrace`).
    if not (closed and dc <= 1.6 and not own_c and got_c):
        bad.append("c")
    return ("PASS" if not bad else "BUG"), "; ".join(notes) + (f" — failed {','.join(bad)}" if bad else "")

def _open_with_poll(db):
    """A relay sentence whose Wispr microphone the relay's 100 ms POLL saw open (`/test/wispr
    {"via": "poll"}`, batch 5) — the witness the real kill closes first — then Wispr's row adopted."""
    chord(state_="start")
    if not wait_for(lambda: state()["listening"], 3):
        raise RuntimeError("the relay did not open the sentence")
    post("/test/wispr", {"on": True, "via": "poll"})
    time.sleep(0.4)
    rid = db.insert(at=time.time())
    if not wait_for(lambda: live()["captureRow"] == rid, 3):
        raise RuntimeError(f"fake row {rid} was not adopted")
    return rid

@case("TW44", covers=_COV, tags=("desk", "audio"), engine="wispr", pre=needs_desk,
      expect="batch 5: the real kill's order — the 100 ms POLL sees Wispr's microphone close FIRST and the exit "
             "comes 0.15 / 0.3 / 0.4 s later: held (`ownTake`), the phase never left listening (no `listening → "
             "transcribing — the 100 ms poll`), his stop after the clip → the WHOLE take `local-fallback → "
             "terminal` (≥ 3 s voiced); control: the poll's close with Wispr alive closes at the 1.0 s grace, no hold")
def tw44():
    """Batch 5 (lab wave 5, TW20 / TQ2 on a real SIGKILL: `listening → transcribing — the 100 ms poll saw
    the microphone close`, the exit event 0.35–0.39 s after it — batch 4's 0.3 s grace had already
    closed the take, 0.5 s voiced → Recover). TW42 delivers the edge, and its exit first; here the
    poll's close comes first, `fakeExit` after (his real Wispr is never killed at a desk)."""
    db = desk()
    bind_witness(); witness_clear()
    notes, bad = [], []
    for tag, gap in (("a", 0.15), ("b", 0.3), ("c", 0.4)):
        witness_clear(); m = log_mark()
        r = _open_with_poll(db)
        th = _bg_play(CLIP_SPEECH)
        time.sleep(3.0)
        post("/test/wispr", {"on": False, "via": "poll"}); tq = time.time()
        time.sleep(gap)
        post("/test/wispr-proc", {"fakeExit": True})
        held = wait_for(lambda: bool(live().get("ownTake")), 2, 0.05)
        dq = time.time() - tq
        time.sleep(1.5)
        still = state()["listening"]
        th.join(20)
        _direct("forward-right")
        got = wait_for(lambda: witness_text().strip(), 40, 0.3)
        d = _landed(m)
        txt = log_since(m)
        v = re.findall(r"wispr meter: ([\d.]+) s voiced", txt)
        voiced = float(v[-1]) if v else 0.0
        moved = re.search(r"listening → transcribing — the 100 ms poll", txt) is not None
        waited = "⏳ the 100 ms poll saw the microphone close under a relay sentence" in txt
        notes.append(f"({tag}) exit {gap:.2f} s after the poll's close: held {bool(held)} {dq:.2f} s after the close, "
                     f"grace line {waited}, phase moved by the poll {moved}, listening 1.5 s on {still}, delivery {d}, "
                     f"voiced {voiced:.1f} s, witness {len(witness_text().strip())} chars")
        if not (held and dq <= gap + 0.5 and waited and not moved and still and got and d
                and d[0] == "local-fallback" and d[1].startswith("terminal:") and voiced >= 3.0):
            bad.append(tag)
        db.update(r, status="dismissed")
        wait_for(lambda: not state()["listening"] and not state()["settling"], 15, 0.2)
        time.sleep(2.2)
    # (d) control: the poll's close with Wispr alive — Wispr's own end, its row moving 0.3 s after
    # (inside the grace, as Wispr writes `processing` + `duration` at its stop): closed by the row,
    # no hold. (Until 2026-09-29 the row moved only after the grace and `outlived` closed it; a close
    # its row does not confirm is now a blip that waits — TW45.)
    witness_clear(); m = log_mark()
    rc = _open_with_poll(db); time.sleep(1.2)
    post("/test/wispr", {"on": False, "via": "poll"}); tc = time.time()
    time.sleep(0.3); db.update(rc, status="processing", duration=1.5)
    closed = wait_for(lambda: not state()["listening"], 3, 0.05)
    dc = time.time() - tc
    own_c = live().get("ownTake")
    time.sleep(0.3)
    db.finish(rc, "tw forty four control words")
    got_c = wait_for(lambda: "forty four control" in witness_text(), 15, 0.2)
    moved = "Wispr's row moved after the close" in log_since(m)
    notes.append(f"(d) Wispr alive: closed {bool(closed)} in {dc:.2f} s (row-moved line {moved}), ownTake {own_c}, "
                 f"row delivered {bool(got_c)}")
    if not (closed and dc <= 1.6 and moved and not own_c and got_c):
        bad.append("d")
    return ("PASS" if not bad else "BUG"), "; ".join(notes) + (f" — failed {','.join(bad)}" if bad else "")

@case("TW43", covers=_COV, tags=("desk", "audio"), engine="wispr", pre=needs_desk,
      expect="item 5: Wispr's process exiting while the relay's words are in flight is told at once — the capture lets "
             "go ≤ 0.3 s after the exit (not at the next WAL commit / 1 s tick) and the take goes to Q14: "
             "`local-fallback → terminal`, before the auto p98 budget")
def tw43():
    """Item 5 (lab wave 4, TW20: the quit noticed 1.48 s after the kill — the quit check rode `pollHistory`,
    which since batch 3 runs on WAL commits and a 1 s tick). The exit is now the kernel's event
    (`ProcessExitWatch`); `POST /test/wispr-proc {"fakeExit"}` delivers it at a desk with no signal. The
    sentence is stopped, its fake row `processing`, and the exit comes 0.5 s later."""
    db = desk()
    bind_witness(); witness_clear()
    m = log_mark()
    ra = open_sentence(db)
    post("/test/wispr", {"on": True}); time.sleep(0.3)
    play(CLIP_SPEECH, seconds=6)
    chord(state_="stop")
    db.update(ra, status="processing", duration=6.0)
    time.sleep(0.5)
    t0 = time.time()
    post("/test/wispr-proc", {"fakeExit": True})
    d = _ended(t0, 5)
    dl = _landed(m)
    txt = log_since(m)
    fired = re.search(r"⏱ .+ over budget", txt) is not None
    told = "the sentence given to it is told at once" in txt
    db.update(ra, status="dismissed")
    note = (f"capture let go {('%.2f s' % d) if d is not None else 'NOT within 5 s'} after the exit; exit line {told}; "
            f"delivery {dl}; auto p98 fired first {fired}; witness {len(witness_text().strip())} chars")
    ok = d is not None and d <= 0.3 and told and dl and dl[0] == "local-fallback" and dl[1].startswith("terminal:") \
        and not fired
    return ("PASS" if ok else "BUG"), note


# ---------------------------------------------------------------- 2026-09-29 evening: the day's Wispr incidents
@case("TW45", covers=_COV, tags=("desk", "audio"), engine="wispr", pre=needs_desk,
      expect="a Wispr microphone blip (poll: off, back 2 s later) with the row still NULL does not end the sentence: "
             "still listening, no ownTake, `Wispr's input is back`, the WHOLE take metered (≥ 3 s voiced), the row "
             "delivered; with no reopen, 4 s after the input went off the relay's own take carries it (ownTake) and "
             "his stop → local-fallback → terminal")
def tw45():
    """12:20 and 12:34 on 2026-09-29, right ⌘⌥ + F19 on Engine = Wispr: the 100 ms poll saw Wispr's input
    go off ~1 s in, the 1 s grace saw Wispr alive and closed the relay's take at 2.8 s; the input came back
    and Wispr recorded to 8.7 / 10 s. `nullRowHold`: a close whose row is still NULL with no duration waits.
    (a) off at 2 s, back at 4 s, row finished after the clip → delivered from the row, one sentence.
    (b) off at 2 s, never back → `ownTake` at ~4 s after the close, his stop → the local model."""
    db = desk()
    bind_witness(); witness_clear()
    notes, bad = [], []
    # (a) the blip
    m = log_mark()
    ra = _open_with_poll(db)
    th = _bg_play(CLIP_SPEECH)   # the whole clip: ~3.6–4.2 s voiced; cut at the 2 s off, < 1 s
    time.sleep(2.0)
    post("/test/wispr", {"on": False, "via": "poll"}); t_off = time.time()
    time.sleep(2.0)
    listening_mid = state()["listening"]
    post("/test/wispr", {"on": True, "via": "poll"})
    back = wait_for(lambda: log_has(m, r"Wispr's input is back"), 2, 0.05)
    own_a = live().get("ownTake")
    th.join(20)
    close_sentence(db, ra, "tw forty five blip words")
    got_a = wait_for(lambda: "forty five blip" in witness_text(), 15, 0.2)
    txt = log_since(m)
    v = re.findall(r"wispr meter: ([\d.]+) s voiced", txt)
    voiced = float(v[-1]) if v else 0.0
    d_a = _landed(m, 5)
    notes.append(f"(a) blip: listening 2 s after the off {listening_mid}, back line {bool(back)}, ownTake {own_a}, "
                 f"voiced {voiced:.1f} s, delivery {d_a}, witness has the row {bool(got_a)}")
    if not (listening_mid and back and not own_a and voiced >= 3.0 and got_a and d_a and d_a[0] == "wispr-history"):
        bad.append("a")
    wait_for(lambda: not state()["listening"] and not state()["settling"], 15, 0.2)
    time.sleep(2.2)
    # (b) never back
    witness_clear(); m = log_mark()
    rb = _open_with_poll(db)
    th = _bg_play(CLIP_SPEECH)   # the whole clip: ~3.6–4.2 s voiced; cut at the 2 s off, < 1 s
    time.sleep(2.0)
    post("/test/wispr", {"on": False, "via": "poll"}); t_off = time.time()
    held = wait_for(lambda: bool(live().get("ownTake")), 6, 0.05)
    dh = time.time() - t_off
    still = state()["listening"]
    th.join(20)
    _direct("forward-right")
    got_b = wait_for(lambda: witness_text().strip(), 40, 0.3)
    d_b = _landed(m)
    txt = log_since(m)
    v = re.findall(r"wispr meter: ([\d.]+) s voiced", txt)
    voiced_b = float(v[-1]) if v else 0.0
    notes.append(f"(b) never back: ownTake {bool(held)} {dh:.2f} s after the off, listening {still}, delivery {d_b}, "
                 f"voiced {voiced_b:.1f} s, witness {len(witness_text().strip())} chars")
    if not (held and 3.5 <= dh <= 5.0 and still and got_b and d_b and d_b[0] == "local-fallback"
            and d_b[1].startswith("terminal:") and voiced_b >= 3.0):
        bad.append("b")
    db.update(rb, status="dismissed")
    return ("PASS" if not bad else "BUG"), "; ".join(notes) + (f" — failed {','.join(bad)}" if bad else "")


@case("TW46", covers=_COV, tags=("desk", "audio"), engine="wispr", pre=needs_desk,
      expect="a relay start Wispr never takes (no row, no microphone): the 📮 probe at 1.5 s names the chord; his stop "
             "posts no chord and the local model delivers at once (local-fallback → terminal within the Q14 p99), "
             "never the 30 s capture timeout")
def tw46():
    """09:51 on 2026-09-29: the start was lost, the stop chord went out anyway (09:45: it started a ghost
    Wispr recording) and the sentence waited 30 s for a row that could not come. W6's check asked
    `!isRecording`, which a relay start sets at the gesture. Desk: chords muted, no row ever inserted."""
    db = desk()
    bind_witness(); witness_clear()
    m = log_mark()
    open_sentence(db, adopt=False)
    th = _bg_play(CLIP_SPEECH, seconds=6)
    probe = wait_for(lambda: log_has(m, r"📮 Wispr has not answered the start chord"), 3, 0.1)
    th.join(20)
    ms = log_mark(); t0 = time.time()
    _direct("forward-right")   # the real stop (`stop()`); `/test/wispr-chord {state: stop}` goes around it
    d = _landed(ms, tmo("q14"))
    dt = time.time() - t0
    txt = log_since(ms)
    said = "stop without a chord — Wispr never took the start" in txt
    chord_after = re.search(r"fn ⌃ Space", txt) is not None
    timed_out = "nothing came back within 30 s" in txt
    note = (f"probe line {bool(probe)}; stop line {said}; a chord after the stop {chord_after}; delivery {d} "
            f"{dt:.1f} s after the stop; 30 s timeout {timed_out}; witness {len(witness_text().strip())} chars")
    ok = probe and said and not chord_after and not timed_out and d and d[0] == "local-fallback" \
        and d[1].startswith("terminal:") and dt < 10
    return ("PASS" if ok else "BUG"), note
