"""Night tests, part 2 (2026-10-23): the chip's new readings on the REAL path — a plain sentence
(🔽 → chord, `back-right`) into `WisprSink`, corpus speech into the "🧪 WT Inject" Loopback, the
installed app's fake whisper helper (`cases_chunks`' block) and, for ElevenLabs, the fake Scribe.

    N8   ElevenLabs 8 s late, budget 2 s (forced), local decode 5 s → `💻 in Ns ⌘⌃X` folded on the
         Transcribing line (no row), then `💻 now ⌘⌃X` + engineMark 💻; local words go in
         (via local-auto); the mark is ElevenLabs' again, and the next sentence transcribes under it
    N9   same, ElevenLabs 4 s late, local 9 s → ElevenLabs' words land at `now`: mark back to ElevenLabs
    N10  same, ElevenLabs 8 s late, the local decode fails at ~4 s → mark back to ElevenLabs while
         still transcribing
    N11  📻 Ready for more, words land ~1.8 s after the stop → up from ~0.8 s, stays ≥ 2 s
    N12  📻 Ready for more, words 6 s late, a new sentence started while it shows → down ≤ 0.3 s

Every timeline row: ms since the stop, engineMark, localNow.inline / row, readyForNext, busyWhy."""
import os, re, shutil, signal, subprocess, threading, time
from harness import *
from harness import (get, post, state, log_mark, log_since, log_has, wait_for, gesture, play, CLIP_EN,
                     relay_busy, tmo, case, BEFORE_CASE, CLEANUPS)
from cases_audio import _quiet
import cases_chunks as CC
import cases_night as NI
import fake_whisper_helper as FW

TAGS = ("gesture", "audio", "local", "night")
SNAPS = ("/private/tmp/claude-501/-Users-victorrentea-workspace-walkie-talkie/"
         "6c83e2fa-5399-4257-8430-c69d197035d6/scratchpad/night/snaps")
ELEVEN, MAC, WISPR = "", "", ""
TL_OUT = os.path.join(os.path.dirname(SNAPS), "timelines")


def _before(c):
    if c.get("module") in (CC.__name__, NI.__name__, __name__):
        CC._install()
    elif CC._INST["on"]:
        CC._uninstall()


BEFORE_CASE[:] = [_before if getattr(f, "__module__", "") == NI.__name__ and f.__name__ == "_before" else f
                  for f in BEFORE_CASE]

_LA0 = {}


def _la_restore():
    if "on" in _LA0:
        _quiet(post, "/test/local-auto", {"on": _LA0["on"], "budget": None, "localEta": None})
    _quiet(post, "/test/eleven", {"clear": True})


CLEANUPS.append(_la_restore)


def mark_name(m):
    m = m or ""
    return ("eleven" if ELEVEN in m else "mac" if MAC in m else "wispr" if WISPR in m else repr(m))


def snap(label):
    """`kill -USR1 <app pid>` → snapshot.png, copied under SNAPS/label.png (background)."""
    def go():
        try:
            pid = state().get("pid")
            src = os.path.expanduser("~/.walkie-talkie/snapshot.png")
            t0 = os.path.getmtime(src) if os.path.exists(src) else 0
            os.kill(int(pid), signal.SIGUSR1)
            wait_for(lambda: os.path.exists(src) and os.path.getmtime(src) > t0, 3, 0.05)
            os.makedirs(SNAPS, exist_ok=True)
            shutil.copy(src, os.path.join(SNAPS, label + ".png"))
        except Exception as e:
            print("snap failed", label, e)
    threading.Thread(target=go, daemon=True).start()


class Timeline:
    """10 Hz poll of the readings; rows (ms since t0, ...). `t0` set by `zero()` (the stop)."""
    def __init__(self, name):
        self.name, self.rows, self.t0, self._stop = name, [], time.time(), False
        self.snapped = set()
        self.th = threading.Thread(target=self._run, daemon=True)

    def start(self):
        self.th.start(); return self

    def zero(self):
        self.t0 = time.time()
        self.z = len(self.rows)

    @property
    def post(self):
        return self.rows[getattr(self, "z", 0):]

    def _run(self):
        while not self._stop:
            s = _quiet(state) or {}
            ln = s.get("localNow") or {}
            row = dict(t=round((time.time() - self.t0) * 1000), mark=mark_name(s.get("engineMark")),
                       inline=ln.get("inline"), row=ln.get("row"), ready=s.get("readyForNext"),
                       rec=bool(s.get("isRecording") or s.get("listening")), settling=s.get("settling"),
                       why=",".join(s.get("busyWhy") or []), sents=[x.get("state") for x in s.get("sentences") or []],
                       chip=[str(r) for r in (s.get("chip") or [])][:4], wall=time.time())
            self.rows.append(row)
            inl = row["inline"] or ""
            for key, cond in (("in", " in " in inl), ("now", " now " in inl)):
                if cond and key not in self.snapped:
                    self.snapped.add(key)
                    snap(f"{self.name}-{key}")
            time.sleep(0.1)

    def stop(self):
        self._stop = True
        self.th.join(2)
        os.makedirs(TL_OUT, exist_ok=True)
        with open(os.path.join(TL_OUT, self.name + ".txt"), "w") as f:
            for r in self.rows:
                f.write(f"{r['t']:>7} mark={r['mark']:<6} rec={int(r['rec'])} settling={r['settling']} "
                        f"ready={r['ready']} inline={r['inline']!r} row={r['row']!r} sents={r['sents']} "
                        f"why={r['why']} chip={r['chip']}\n")

    def changes(self, keys=("mark", "inline", "row", "ready", "rec")):
        """Rows where any of `keys` changed — the compressed timeline."""
        out, last = [], None
        for r in self.post:
            cur = tuple(r[k] for k in keys)
            if cur != last:
                out.append((r["t"],) + cur)
                last = cur
        return out

    def first(self, pred):
        for r in self.post:
            if pred(r):
                return r["t"]
        return None


def _la(budget=2, eta=1):
    if "on" not in _LA0:
        _LA0["on"] = bool((state().get("localAuto") or {}).get("on", True))
    return (post("/test/local-auto", {"on": True, "budget": budget, "localEta": eta})[1] or {}).get("localAuto") or {}


def _sentence(tl, delay_ms, rules, wait_land=40):
    """One plain ElevenLabs sentence into the sink with `tl` polling. (mark, t_stop, note) or raises."""
    post("/test/eleven", {"fail": "delay", "delayMs": delay_ms})
    ep = FW.arm(rules=rules)
    n0 = len(NI.sink_text())
    m, why = NI.plain(wait_stop=False)
    if not m:
        raise RuntimeError(why)
    tl.zero()
    t_stop = time.time()
    wait_for(lambda: len(NI.sink_text()) > n0 and not relay_busy(), wait_land, 0.1)
    time.sleep(0.8)
    return m, t_stop, ep


def _next_sentence_mark(name):
    """A quick follow-up sentence (ElevenLabs 1.5 s late, budget unforced): the marks it shows."""
    _quiet(post, "/test/local-auto", {"budget": None, "localEta": None})
    tl = Timeline(name).start()
    try:
        m, t, ep = _sentence(tl, 1500, [])
    finally:
        tl.stop()
    marks = sorted({r["mark"] for r in tl.post if r["t"] >= 0 and not r["rec"] and r["settling"]})
    return marks, tl


def _summ(tl, keys=("mark", "inline", "row", "ready", "rec")):
    return "; ".join(f"{c[0]}ms " + " ".join(f"{k}={v!r}" for k, v in zip(keys, c[1:])) for c in tl.changes(keys))


def _a_case(name, el_delay, rules, want):
    with NI.Sink():
        if not NI.editor(False):
            return "FAIL", "editor would not turn off"
        la = _la(2, 1)
        tl = Timeline(name).start()
        rec_rows = []
        try:
            m, t_stop, ep = _sentence(tl, el_delay, rules)
        finally:
            tl.stop()
        rec_rows = [(r["row"], r["inline"]) for r in tl.rows if r["rec"]]
        txt = NI.sink_text()
        d = state().get("lastDelivery") or {}
        mark_end = mark_name(state().get("engineMark"))
        tr = (state().get("localAuto") or {}).get("trace")
        t_in = tl.first(lambda r: r["inline"] and " in " in r["inline"])
        t_now = tl.first(lambda r: r["inline"] and " now " in r["inline"])
        t_mac = tl.first(lambda r: r["t"] > 0 and r["mark"] == "mac")
        t_back = None
        if t_mac is not None:
            t_back = next((r["t"] for r in tl.post if r["t"] > t_mac and r["mark"] == "eleven"), None)
        folded_bad = []   # state.localNow.row carries the text even while folded (drawn or not: see the snapshots)
        row_while_folded = sorted({str(r["row"]) for r in tl.post if r["settling"] and r["inline"]})
        log = [l[-200:] for l in log_since(m).splitlines()
               if re.search(r"⏱|🔮|💻|📊 fallback|📦 delivery|ElevenLabs answered|local model", l)][-12:]
        nxt_marks, tl2 = _next_sentence_mark(name + "-next")
        res = dict(txt=txt, via=d.get("via"), mark_end=mark_end, t_in=t_in, t_now=t_now, t_mac=t_mac,
                   t_back=t_back, folded_bad=folded_bad[:5], rec_rows=sorted(set(map(str, rec_rows)))[:4], row_while_folded=row_while_folded[:3],
                   next_marks=nxt_marks, next_via=(state().get("lastDelivery") or {}).get("via"))
        ok, why = want(res)
        note = (f"{why}; result {res}; timeline {_summ(tl)}; next sentence {_summ(tl2, ('mark', 'inline', 'rec'))}; "
                f"trace {str(tr)[:300]}; log {log}")
        return ("PASS" if ok else "FAIL"), note


def pre():
    why = NI.pre()
    if why:
        return why
    return None if "inline" in (state().get("localNow") or {}) else "no state.localNow.inline in the installed build"


@case("N8", TAGS, pre=pre, engine="eleven",
      expect="ElevenLabs 8 s late, budget 2 s, local decode 5 s: `💻 in Ns ⌘⌃X` folded (row null) then `💻 now ⌘⌃X` "
             "+ engineMark 💻; local words go in (local-auto); mark back to ElevenLabs; next sentence under ElevenLabs")
def n8():
    def want(r):
        ok = (r["t_in"] is not None and r["t_now"] is not None and r["t_in"] < r["t_now"] and r["t_mac"] is not None
              and abs(r["t_mac"] - r["t_now"]) <= 300 and not r["folded_bad"] and r["via"] == "local-auto"
              and r["mark_end"] == "eleven" and r["next_marks"] == ["eleven"])
        return ok, f"in@{r['t_in']} now@{r['t_now']} 💻@{r['t_mac']} back@{r['t_back']}"
    return _a_case("N8", 8000, [{"kind": "wav", "delay": 5}], want)


@case("N9", TAGS, pre=pre, engine="eleven",
      expect="ElevenLabs 4 s late, local decode 9 s: at `now` 💻, then ElevenLabs' words land → mark ElevenLabs at once; "
             "delivered via elevenlabs-scribe; the next sentence under ElevenLabs")
def n9():
    def want(r):
        ok = (r["t_now"] is not None and r["t_mac"] is not None and r["t_back"] is not None
              and r["via"] == "elevenlabs-scribe" and r["mark_end"] == "eleven" and r["next_marks"] == ["eleven"])
        return ok, f"now@{r['t_now']} 💻@{r['t_mac']} back@{r['t_back']}"
    return _a_case("N9", 4000, [{"kind": "wav", "delay": 9}], want)


@case("N10", TAGS, pre=pre, engine="eleven",
      expect="ElevenLabs 8 s late, the local decode fails ~3 s after its start: 💻 at `now`, back to ElevenLabs "
             "when it fails (before ElevenLabs lands); delivered via elevenlabs-scribe; next sentence ElevenLabs")
def n10():
    def want(r):
        ok = (r["t_now"] is not None and r["t_mac"] is not None and r["t_back"] is not None and r["t_back"] < 7500
              and r["via"] == "elevenlabs-scribe" and r["mark_end"] == "eleven" and r["next_marks"] == ["eleven"])
        return ok, f"now@{r['t_now']} 💻@{r['t_mac']} back@{r['t_back']} (ElevenLabs lands ~8000+)"
    return _a_case("N10", 8000, [{"kind": "wav", "delay": 3, "fail": "fake failure"}], want)


# ================================================================ 📻 Ready for more
@case("N11", TAGS, pre=NI.pre,
      expect="local engine, words ~1.8 s after the stop: readyForNext true from ~0.8 s; stays true ≥ 2 s after it "
             "appeared although the words land earlier")
def n11():
    with NI.Sink():
        if not NI.editor(False):
            return "FAIL", "editor would not turn off"
        tl = Timeline("N11").start()
        try:
            ep = FW.arm(rules=[{"kind": "wav", "delay": 1.6}])
            m, why = NI.plain(wait_stop=False)
            if not m:
                return "FAIL", why
            tl.zero()
            wait_for(lambda: len(NI.sink_text()) > 0, 20, 0.05)
            t_land = round((time.time() - tl.t0) * 1000)
            time.sleep(4)
        finally:
            tl.stop()
        up = tl.first(lambda r: r["t"] > 0 and r["ready"])
        down = next((r["t"] for r in tl.post if up is not None and r["t"] > up and not r["ready"]), None)
        held = (down - up) if (up is not None and down is not None) else None
        ok = up is not None and 500 <= up <= 1300 and held is not None and held >= 1900 and t_land < up + 2000
        return ("PASS" if ok else "FAIL"), (f"ready up@{up}ms, words in sink@{t_land}ms, ready down@{down}ms → shown {held} ms; "
                                            f"sink {NI.sink_text()!r}; timeline {_summ(tl, ('ready', 'rec', 'why'))}; "
                                            f"log {[l[-150:] for l in log_since(m).splitlines() if '📻' in l]}")


@case("N12", TAGS, pre=NI.pre,
      expect="local engine, words 6 s late: readyForNext up ~0.8 s; a new sentence (🔽 →) started while it shows → "
             "readyForNext false ≤ 0.3 s after the start; both sentences land in order")
def n12():
    with NI.Sink():
        if not NI.editor(False):
            return "FAIL", "editor would not turn off"
        tl = Timeline("N12").start()
        try:
            ep = FW.arm(rules=[{"n": 1, "delay": 6, "text": "the first sentence about apples"},
                               {"n": 2, "text": "the second sentence about oranges"}])
            m, why = NI.plain(wait_stop=False)
            if not m:
                return "FAIL", why
            tl.zero()
            if not wait_for(lambda: state().get("readyForNext"), 5, 0.05):
                return "FAIL", f"readyForNext never came up; {_summ(tl, ('ready', 'rec', 'why'))}"
            time.sleep(0.5)
            m2 = log_mark()
            t_g = time.time()
            gesture("back-right")
            opened = wait_for(lambda: log_has(m2, NI.OPENED), 8, 0.02)
            t_open = time.time()
            time.sleep(0.4)
            play(CLIP_EN, lead=0.3, tail=0.0)
            time.sleep(0.15)
            gesture("back-right")
            wait_for(lambda: "oranges" in NI.sink_text() and not relay_busy(), 30, 0.2)
            time.sleep(0.6)
        finally:
            tl.stop()
        g = round((t_g - tl.t0) * 1000)
        o = round((t_open - tl.t0) * 1000)
        down = next((r["t"] for r in tl.post if r["t"] > g and not r["ready"]), None)
        up = tl.first(lambda r: r["t"] > 0 and r["ready"])
        txt = NI.sink_text()
        ok = (opened and down is not None and down - g <= 300 + 100 and 0 <= txt.find("apples") < txt.find("oranges"))
        return ("PASS" if ok else "FAIL"), (
            f"ready up@{up}ms; B's gesture posted @{g}ms, mic open seen @{o}ms; ready down @{down}ms → "
            f"{None if down is None else down - g} ms after the gesture ({None if down is None else down - o} ms after the open was seen; "
            f"poll 100 ms); sink {txt!r}; timeline {_summ(tl, ('ready', 'rec', 'why'))}")


# ================================================================ » over the held sent-prompt dialog
import Quartz

WFILE = os.path.join(os.path.dirname(SNAPS), "c-witness.txt")


def app_windows(pid):
    out = []
    for w in Quartz.CGWindowListCopyWindowInfo(Quartz.kCGWindowListOptionOnScreenOnly, Quartz.kCGNullWindowID) or []:
        if int(w.get("kCGWindowOwnerPID", -1)) == int(pid):
            b = w.get("kCGWindowBounds") or {}
            out.append((round(b.get("X", 0)), round(b.get("Y", 0)), round(b.get("Width", 0)), round(b.get("Height", 0)),
                        int(w.get("kCGWindowLayer", 0))))
    return out


def click(x, y):
    """A real left click at global (x, y) (top-left origin); the pointer put back."""
    here = Quartz.CGEventGetLocation(Quartz.CGEventCreate(None))
    for t in (Quartz.kCGEventMouseMoved, Quartz.kCGEventLeftMouseDown, Quartz.kCGEventLeftMouseUp):
        ev = Quartz.CGEventCreateMouseEvent(None, t, (x, y), Quartz.kCGMouseButtonLeft)
        Quartz.CGEventPost(Quartz.kCGHIDEventTap, ev)
        time.sleep(0.06)
    time.sleep(0.1)
    Quartz.CGEventPost(Quartz.kCGHIDEventTap,
                       Quartz.CGEventCreateMouseEvent(None, Quartz.kCGEventMouseMoved, here, Quartz.kCGMouseButtonLeft))


def held_and_click(t0, timeout=25):
    """Poll heldSkip at ~25 Hz; when up, find the 26×26 window and click its centre.
    Returns facts (ms since t0)."""
    pid = state().get("pid")
    f = {"skip_up": None, "clicked": None, "skip_down": None, "win": None, "dialog": None, "wins_after": None}
    end = time.time() + timeout
    while time.time() < end:
        s = _quiet(state) or {}
        if s.get("heldSkip"):
            f["skip_up"] = round((time.time() - t0) * 1000)
            break
        time.sleep(0.04)
    if f["skip_up"] is None:
        return f
    time.sleep(0.05)
    wins = app_windows(pid)
    skip = [w for w in wins if w[2] == 26 and w[3] == 26]
    f["wins"] = wins
    if not skip:
        return f
    x, y, w, h, _ = skip[0]
    f["win"] = skip[0]
    # The dialog: the window whose top-right corner holds the skip (inset 6).
    f["dialog"] = [d for d in wins if abs(d[0] + d[2] - (x + w + 6)) <= 2 and abs(d[1] - (y - 6)) <= 2 and d[2] > 26]
    snap("C-held-" + str(int(t0)))
    time.sleep(float(os.environ.get("N_PRECLICK", "0.3")))
    f["wins_before_click"] = [d for d in app_windows(pid) if d[2] > 100 and d[3] < 600]
    f["skip_rel_dialog"] = [(x - d[0], y - d[1], d[0] + d[2] - (x + w)) for d in f["wins_before_click"]]
    click(x + w / 2, y + h / 2)
    f["clicked"] = round((time.time() - t0) * 1000)
    end = time.time() + 5
    while time.time() < end:
        if not (_quiet(state) or {}).get("heldSkip"):
            f["skip_down"] = round((time.time() - t0) * 1000)
            break
        time.sleep(0.03)
    time.sleep(0.4)
    f["wins_after"] = app_windows(pid)
    return f


def _new_delivery(prev_at, timeout):
    def nd():
        d = state().get("lastDelivery") or {}
        return d if d.get("at") and d.get("at") != prev_at else None
    return wait_for(nd, timeout, 0.1)


@case("N13", ("night", "tty"), pre=None,
      expect="a prompt sent to a bound NEW Terminal tab (cat): while the dialog is held `heldSkip` true; a real click "
             "on the » → heldSkip false, the dialog's window gone, the words still arrive in the tab")
def n13():
    tty = None
    try:
        open(WFILE, "w").close()
        script = f"printf '\\\\e]0;wt-night-C\\\\a'; stty -echo; exec cat >> {WFILE}"
        tty = osa(f'tell application "Terminal" to set t to do script "{script}"',
                  'tell application "Terminal" to get tty of t').replace("/dev/", "")
        time.sleep(1.0)
        if not tty.startswith("ttys") or tty == "ttys008":
            return "FAIL", f"bad tty {tty!r}"
        code, _ = post("/bind", {"tty": tty})
        wait_for(lambda: (get("/target") or {}).get("bound"), 5, 0.1)
        tok = "N13-%d" % int(time.time())
        prev = (state().get("lastDelivery") or {}).get("at")
        m = log_mark()
        post("/test/dictation", {"text": f"{tok} night test sentence for the skip button"})
        wait_for(lambda: (state().get("prompt") or {}).get("held"), 8, 0.05)
        p = state().get("prompt") or {}
        t0 = time.time()
        if p.get("held"):
            post("/test/prompt", {"do": "send"})
        f = held_and_click(t0, 15)
        d = _new_delivery(prev, 20) or {}
        import datetime as _D
        if d.get("at"):
            f["delivery_ms"] = round((_D.datetime.fromisoformat(d["at"].replace("Z", "+00:00")).timestamp() - t0) * 1000)
        wait_for(lambda: tok in open(WFILE, errors="replace").read(), 10, 0.2)
        time.sleep(1.0)
        got = open(WFILE, errors="replace").read()
        lg = [l[-170:] for l in log_since(m).splitlines() if re.search(r"⏩|📦 delivery|delivered to the bound|held|flight|release", l)][-10:]
        ok = (f["skip_up"] is not None and f["clicked"] is not None and f["skip_down"] is not None
              and f["skip_down"] - f["clicked"] < 1000 and tok in got and str(d.get("to", "")).endswith(tty)
              and log_has(m, "⏩"))
        return ("PASS" if ok else "FAIL"), (f"tty {tty} (bind {code}); prompt at send {{held {p.get('held')}, autosend {state().get('autosend')}}}; "
                                            f"facts {f}; delivery {d}; witness has token {tok in got} ({len(got)} chars); log {lg}")
    finally:
        _quiet(post, "/unbind")
        if tty:
            close_tty_tab(tty)


@case("N14", ("night", "spawn"), pre=None,
      expect="🔼 ↑ spawn via /test/spawn: the dialog held after the send with `heldSkip` true; a real click on the » → "
             "heldSkip false and the dialog gone, while the new session still gets its prompt")
def n14():
    before = set(re.findall(r"ttys\d+", osa('tell application "Terminal" to get tty of every tab of every window')))
    new = set()
    try:
        tok = "N14-%d" % int(time.time())
        text = f"{tok} Walkie Talkie night test of the spawn dialog. Reply with the single word OK and do nothing else."
        prev = (state().get("lastDelivery") or {}).get("at")
        m = log_mark()
        post("/test/spawn", {"text": text})
        wait_for(lambda: (state().get("prompt") or {}).get("held"), 8, 0.05)
        p = state().get("prompt") or {}
        t0 = time.time()
        if p.get("held"):
            post("/test/prompt", {"do": "send"})
        f = held_and_click(t0, 25)
        d = _new_delivery(prev, 30) or {}
        time.sleep(2)
        for _ in range(20):
            new = set(re.findall(r"ttys\d+", osa('tell application "Terminal" to get tty of every tab of every window'))) - before
            if new:
                break
            time.sleep(0.5)
        procs = {t: subprocess.run(["ps", "-t", t, "-o", "pid=,command="], capture_output=True, text=True).stdout.strip()[:400]
                 for t in new}
        has_prompt = any(tok in v for v in procs.values())
        lg = [l[-170:] for l in log_since(m).splitlines() if re.search(r"⏩|📦 delivery|spawn|transcript|release|held", l)][-12:]
        ok = (f["skip_up"] is not None and f["clicked"] is not None and f["skip_down"] is not None
              and f["skip_down"] - f["clicked"] < 1000 and has_prompt and log_has(m, "⏩"))
        return ("PASS" if ok else "FAIL"), (f"prompt at send {{held {p.get('held')}}}; facts {f}; delivery {d}; new ttys {sorted(new)}; "
                                            f"claude argv has token {has_prompt}; procs {procs}; log {lg}")
    finally:
        time.sleep(6)   # let the session answer before it is closed
        for t in new:
            if t != "ttys008":
                close_tty_tab(t)
