#!/usr/bin/env python3
"""One real Wispr Flow dictation, driven end to end, and asserted.

`tools/wispr-test.sh` proves the **channel**: a WAV reaches Wispr and a
transcript comes back. This proves the **behaviour** — that the words went where
the gesture said they should, that the ring came down when Wispr was finished
and not twelve seconds later, and that nothing leaked into the window in front.
Those are the two bugs of 2026-09-13, and neither of them is visible from a
transcript alone.

    WAV ──sd.play()──▶ Loopback device ──mic──▶ Wispr Flow ──⌘V / AX insert──┐
                              ▲                                             │
               system default input                        Walkie Talkie ◀──┘
          (POST /test/input, restored on exit)                     │
                                                   sink window · bound tty · spawn
    Wispr is on Auto-detect, so it follows the system default input — that one
    setting is the whole reason this is scriptable at all.

Nothing here synthesises a keystroke of its own. Every gesture goes through
`POST /test/gesture`, which makes the **app** post the real ⌃⌥⌘F-key chord: the
app holds the Accessibility grant, this script holds none and needs none.

The pure half — text similarity, `relay.log` parsing, the timing arithmetic — is
importable and has no relay behind it, because those are the parts that can be
got wrong quietly and `evals/test_wispr_loop.py` is what catches them.
"""

from __future__ import annotations

import difflib
import json
import os
import re
import sqlite3
import string
import subprocess
import sys
import time
from dataclasses import dataclass, field
from datetime import datetime

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
sys.path.insert(0, HERE)

import wispr_preflight as pf  # noqa: E402

HOME = os.path.expanduser("~")
RELAY_LOG = os.path.join(HOME, ".walkie-talkie/relay.log")
OUTBOX = os.path.join(HOME, ".walkie-talkie/outbox.jsonl")
WISPR_DB = os.path.join(HOME, "Library/Application Support/Wispr Flow/flow.sqlite")
FIXTURES = os.path.join(REPO, "evals/fixtures/wispr-loop.json")

#: How close a transcript has to be to the fixture's known reading. Wispr's
#: formatting pass moves punctuation and capitalisation around between two
#: readings of the same audio, and the loopback adds a little of its own, so an
#: exact match would fail on a channel that is working perfectly.
SIMILARITY_FLOOR = 0.8

#: The ring must be down this soon after Wispr says it is finished. It is the
#: number incident 1 broke: `speculativeGrace` is 12 s and a dictation Wispr
#: never opened a microphone for burns all of it with the lightning on screen.
RING_DOWN_BUDGET_MS = 2000


# ══ pure: the words ══════════════════════════════════════════════════════════
_PUNCT = str.maketrans("", "", string.punctuation + "„”“”‘’—–…«»")


def normalise(text: str) -> str:
    """Lowercased, punctuation-stripped, whitespace-collapsed.

    Both sides of the comparison have been through an LLM formatting pass that
    is free to re-punctuate; comparing the punctuation would be scoring Wispr's
    mood, not the channel.
    """
    return " ".join(str(text or "").translate(_PUNCT).lower().split())


def similarity(a: str, b: str) -> float:
    """`difflib.SequenceMatcher` over the normalised forms. 1.0 is identical."""
    na, nb = normalise(a), normalise(b)
    if not na and not nb:
        return 1.0
    return difflib.SequenceMatcher(None, na, nb).ratio()


# ══ pure: the log ════════════════════════════════════════════════════════════
@dataclass
class LogLine:
    at: datetime
    text: str
    raw: str


_LINE = re.compile(r"^(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2}) \[relay\] (.*)$")


def parse_log(blob: str, year: int | None = None) -> list[LogLine]:
    """`MM-dd HH:mm:ss [relay] …` into lines with a timestamp.

    The log carries no year. The current one is assumed and rolled back when
    that would put the line in the future — which is what a run spanning New
    Year's Eve would otherwise produce, and a negative interval in a timing
    table is worse than a wrong year nobody reads.
    """
    now = datetime.now()
    year = year or now.year
    out: list[LogLine] = []
    for raw in blob.splitlines():
        m = _LINE.match(raw)
        if not m:
            continue
        month, day, hh, mm, ss = (int(g) for g in m.groups()[:5])
        try:
            at = datetime(year, month, day, hh, mm, ss)
        except ValueError:
            continue
        if (at - now).days > 180:
            at = at.replace(year=year - 1)
        out.append(LogLine(at=at, text=m.group(6), raw=raw))
    return out


# Every measurement the relay already prints, so nothing here re-derives a
# number the app has itself. Second-resolution timestamps are only ever the
# anchor; the milliseconds come out of the sentence.
_ASKED = "the relay asked for a dictation"
_MIC_EDGE = re.compile(r"⚡ mic edge confirms the ring (\d+) ms after the gesture")
_MIC_OPEN = "wispr flow opened the microphone"
_MIC_CLOSE = "wispr flow closed the microphone"
_FORMATTED = re.compile(r"wispr history: formatted (\d+) ms after the microphone closed")
_CMD_V = re.compile(r"⌘V from Wispr Flow — (\d+) ms after the microphone closed")
_TRANSCRIPT = re.compile(r"🗣️ wispr transcript via (.+?) — (\d+) chars, (\d+) ms after the microphone closed")
_RING_DOWN_MS = re.compile(r"⚡ ring down: (.*) — (\d+) ms after the recording ended$")
_RING_DOWN = re.compile(r"⚡ ring down: (.*)$")
_PROBE = re.compile(r"probe: synthetic key (\d+) flags (\S+) from pid (\d+) \((.*)\)")


@dataclass
class Timings:
    """What the run took, in the relay's own numbers.

    Every offset is **milliseconds after the microphone closed**, because that is
    the one instant the relay stamps precisely in three separate sentences. The
    table the runner prints is arithmetic over these, never over the
    second-resolution clock, unless one of them is missing — in which case the
    row says so rather than printing a smooth lie.
    """

    gesture_at: datetime | None = None
    mic_open_at: datetime | None = None
    mic_close_at: datetime | None = None
    gesture_to_mic_open_ms: int | None = None
    #: Wispr is finished. From the History poll when Wispr inserted invisibly,
    #: from the ⌘V when it pasted — `done_source` says which.
    done_ms: int | None = None
    done_source: str = ""
    delivery_ms: int | None = None
    delivery_via: str = ""
    delivery_chars: int | None = None
    ring_down_ms: int | None = None
    ring_down_reason: str = ""
    ring_down_at: datetime | None = None
    probes: list[str] = field(default_factory=list)
    #: True when `ring_down_ms` had to come off the wall clock.
    ring_down_estimated: bool = False

    @property
    def done_to_ring_down_ms(self) -> int | None:
        if self.done_ms is None or self.ring_down_ms is None:
            return None
        return self.ring_down_ms - self.done_ms

    @property
    def done_to_delivery_ms(self) -> int | None:
        if self.done_ms is None or self.delivery_ms is None:
            return None
        return self.delivery_ms - self.done_ms


def read_timings(lines: list[LogLine]) -> Timings:
    """Pull every number out of one run's worth of log lines."""
    t = Timings()
    for line in lines:
        text = line.text
        if _ASKED in text and t.gesture_at is None:
            t.gesture_at = line.at
        m = _MIC_EDGE.search(text)
        if m:
            t.gesture_to_mic_open_ms = int(m.group(1))
        if _MIC_OPEN in text and t.mic_open_at is None:
            t.mic_open_at = line.at
        if _MIC_CLOSE in text:
            t.mic_close_at = line.at
        m = _FORMATTED.search(text)
        if m:
            t.done_ms, t.done_source = int(m.group(1)), "formatted (Wispr's History row)"
        m = _CMD_V.search(text)
        if m and t.done_source != "formatted (Wispr's History row)":
            t.done_ms, t.done_source = int(m.group(1)), "⌘V from Wispr Flow"
        m = _TRANSCRIPT.search(text)
        if m:
            t.delivery_via = m.group(1)
            t.delivery_chars = int(m.group(2))
            t.delivery_ms = int(m.group(3))
        m = _PROBE.search(text)
        if m:
            t.probes.append("key %s flags %s from %s" % (m.group(1), m.group(2), m.group(4)))
        m = _RING_DOWN_MS.search(text)
        if m:
            t.ring_down_reason, t.ring_down_ms = m.group(1), int(m.group(2))
            t.ring_down_at, t.ring_down_estimated = line.at, False
            continue
        m = _RING_DOWN.search(text)
        if m:
            # The reasons with no measurement are the interesting ones: a chord
            # Wispr ignored never had a recording to end. Fall back to the wall
            # clock against the microphone's close, or against the gesture.
            t.ring_down_reason = m.group(1)
            t.ring_down_at = line.at
            t.ring_down_estimated = True
            anchor = t.mic_close_at or t.gesture_at
            t.ring_down_ms = int((line.at - anchor).total_seconds() * 1000) if anchor else None

    if t.gesture_to_mic_open_ms is None and t.gesture_at and t.mic_open_at:
        t.gesture_to_mic_open_ms = int((t.mic_open_at - t.gesture_at).total_seconds() * 1000)
    return t


# ══ pure: Wispr's own row ════════════════════════════════════════════════════
@dataclass
class HistoryRow:
    rowid: int
    status: str
    pasted_text: str
    e2e_latency: float
    app: str
    started_at: float
    #: **Wispr's own record of which microphone it used.** The one column that
    #: catches the failure that wasted 2026-09-13: the system default pointed at
    #: the Loopback device and this still said `Built-in mic (recommended)`.
    mic_device: str = ""


def wispr_history_newest() -> HistoryRow | None:
    """The newest `History` row. **Read-only, one query, after the run.**

    `mode=ro` on a WAL file — a reader never blocks Wispr's writer, and nothing
    here writes, ever. The columns are the ones `WisprHistory.swift` reads.
    """
    if not os.path.exists(WISPR_DB):
        return None
    uri = "file:%s?mode=ro" % WISPR_DB.replace("?", "%3f").replace("#", "%23")
    try:
        db = sqlite3.connect(uri, uri=True, timeout=15)
    except Exception:
        return None
    try:
        row = db.execute(
            "select rowid, coalesce(status,''), coalesce(pastedText,''), coalesce(e2eLatency,0),"
            "       coalesce(app,''), coalesce(strftime('%s', timestamp), '0'), coalesce(micDevice,'')"
            "  from History order by rowid desc limit 1").fetchone()
    except Exception:
        return None
    finally:
        db.close()
    if not row:
        return None
    return HistoryRow(rowid=row[0], status=row[1], pasted_text=row[2],
                      e2e_latency=float(row[3]), app=row[4], started_at=float(row[5] or 0),
                      mic_device=row[6])


# ══ the relay, as this runner talks to it ════════════════════════════════════
class Relay:
    """Thin wrapper over the loopback routes, with a dry-run mode that posts nothing."""

    def __init__(self, port: int, dry_run: bool = False, verbose: bool = False):
        self.port, self.dry_run, self.verbose = port, dry_run, verbose
        self.steps: list[str] = []
        self._polled: set[str] = set()

    def _note(self, what: str, once: bool = False):
        if once:
            if what in self._polled:
                return
            self._polled.add(what)
        self.steps.append(what)
        if self.dry_run or self.verbose:
            print("   · %s" % what)

    def get(self, path: str):
        if self.dry_run:
            # A poll is one step however many times it goes round, or the dry
            # run's transcript is three hundred identical lines and the two that
            # matter are lost in them.
            self._note("GET %s (polled)" % path, once=True)
            return {}
        return pf.get(self.port, path) or {}

    def post(self, path: str, body=None):
        self._note("POST %s %s" % (path, json.dumps(body or {}, ensure_ascii=False)))
        if self.dry_run:
            return {}
        return pf.post(self.port, path, body) or {}

    # — the vocabulary, named after the gesture and not after the key —
    def gesture(self, name: str):
        """One of `forward-click` · `forward-up` · `forward-left` · `forward-right` · `back-right`.

        `HotkeyTap` reads them as ⌃⌥⌘F7 · F8 · F11 · F10 · F5. The click and the
        right-move are **toggles** (`onPasteToggle`, `onLocalToggle`), so the
        same gesture that opens a dictation ends it; the spawn is not, which is
        why scenario 3 stops with a click.
        """
        return self.post("/test/gesture", {"name": name})

    def state(self):
        return self.get("/test/state")

    def sink(self, on: bool):
        return self.post("/test/sink", {"on": on})

    def sink_read(self):
        return self.get("/test/sink")

    def sink_clear(self):
        return self.post("/test/sink/clear")


def wait_for(predicate, timeout: float, poll: float = 0.15, label: str = "", dry: bool = False):
    """Poll `predicate` until it is truthy. **Never a fixed sleep.**

    Returns `(value, seconds_waited)`; the value is falsy when it timed out, and
    the caller reports the timeout as a failed assertion rather than pretending
    the step happened. A dry run posted nothing, so there is nothing to wait on
    and it returns at once.
    """
    if dry:
        # A string, not True: some callers use the value as the thing they were
        # waiting for (the text typed into a bound tty), and a bool there is an
        # AttributeError three frames later.
        return ("(dry run)", 0.0)
    started = time.monotonic()
    while time.monotonic() - started < timeout:
        value = predicate()
        if value:
            return value, time.monotonic() - started
        time.sleep(poll)
    return None, time.monotonic() - started


# ══ the log, from the run's own high-water mark ══════════════════════════════
class LogMark:
    """A byte offset into `relay.log`, so a run reads only its own lines."""

    def __init__(self, path: str = RELAY_LOG):
        self.path = path
        self.offset = os.path.getsize(path) if os.path.exists(path) else 0

    def fresh(self) -> str:
        if not os.path.exists(self.path):
            return ""
        with open(self.path, "rb") as handle:
            handle.seek(self.offset)
            return handle.read().decode("utf-8", "replace")

    def lines(self) -> list[LogLine]:
        return parse_log(self.fresh())


class OutboxMark:
    """The same, for `outbox.jsonl` — one JSON object per delivery."""

    def __init__(self, path: str = OUTBOX):
        self.path = path
        self.offset = os.path.getsize(path) if os.path.exists(path) else 0

    def fresh(self) -> list[dict]:
        if not os.path.exists(self.path):
            return []
        with open(self.path, "rb") as handle:
            handle.seek(self.offset)
            blob = handle.read().decode("utf-8", "replace")
        rows = []
        for line in blob.splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                rows.append(json.loads(line))
            except ValueError:
                continue
        return rows


# ══ assertions ═══════════════════════════════════════════════════════════════
@dataclass
class Check:
    ok: bool
    label: str
    measured: str

    def render(self) -> str:
        mark = "\033[32m✓\033[0m" if self.ok else "\033[31m✗\033[0m"
        if not sys.stdout.isatty():
            mark = "✓" if self.ok else "✗"
        return "%s %-52s %s" % (mark, self.label, self.measured)


@dataclass
class Result:
    scenario: str
    checks: list[Check] = field(default_factory=list)
    timings: Timings = field(default_factory=Timings)
    notes: list[str] = field(default_factory=list)
    log: list[str] = field(default_factory=list)
    expected_red: bool = False
    #: A dry run posted nothing, so every "measurement" would be of a run that
    #: never happened. It collects the assertions it *would* make and returns
    #: neither a pass nor a fail.
    dry: bool = False
    #: Which repetition this is, when `--repeat` asked for more than one.
    run_index: int = 1
    #: For a scenario that exists to answer an open question rather than to
    #: guard a known-good behaviour: the hypothesis this run supports. It is the
    #: payload of such a run — the ✓/✗ rows only say the harness worked.
    answer: str = ""

    def check(self, ok: bool, label: str, measured) -> bool:
        if self.dry:
            self.checks.append(Check(True, label, "(would assert)"))
            return True
        self.checks.append(Check(bool(ok), label, str(measured)))
        return bool(ok)

    def note(self, text: str):
        self.notes.append(text)

    @property
    def passed(self) -> bool:
        return all(c.ok for c in self.checks) and bool(self.checks)

    def as_dict(self):
        t = self.timings
        return {
            "scenario": self.scenario,
            "run": self.run_index,
            "answer": self.answer,
            "pass": self.passed,
            "expectedRed": self.expected_red,
            "checks": [{"ok": c.ok, "label": c.label, "measured": c.measured} for c in self.checks],
            "notes": self.notes,
            "timings": {
                "gestureToMicOpenMs": t.gesture_to_mic_open_ms,
                "micCloseToDoneMs": t.done_ms,
                "doneSource": t.done_source,
                "doneToRingDownMs": t.done_to_ring_down_ms,
                "doneToDeliveryMs": t.done_to_delivery_ms,
                "ringDownMsAfterMicClose": t.ring_down_ms,
                "ringDownEstimated": t.ring_down_estimated,
                "ringDownReason": t.ring_down_reason,
                "deliveryVia": t.delivery_via,
                "deliveryChars": t.delivery_chars,
                "probes": t.probes,
            },
            "log": self.log,
        }


def timing_table(t: Timings) -> str:
    def ms(value, note=""):
        if value is None:
            return "        —  (not measured)"
        return "%9s ms%s" % (value, ("  " + note) if note else "")

    rows = [
        ("gesture → mic open", ms(t.gesture_to_mic_open_ms)),
        ("mic close → Wispr done", ms(t.done_ms, t.done_source)),
        ("Wispr done → ring down", ms(t.done_to_ring_down_ms,
                                      "(wall clock)" if t.ring_down_estimated else "")),
        ("Wispr done → delivery", ms(t.done_to_delivery_ms, t.delivery_via)),
    ]
    width = max(len(name) for name, _ in rows)
    out = ["  %-*s   %s" % (width, name, value) for name, value in rows]
    if t.ring_down_reason:
        out.append("  %-*s   %s" % (width, "ring down reason", t.ring_down_reason))
    return "\n".join(out)


# ══ fixtures ═════════════════════════════════════════════════════════════════
def fixture_for(scenario: str, wav: str | None = None, transcript: str | None = None) -> dict:
    """The clip this scenario dictates. `--wav` / `--transcript` override.

    The WAVs are **Victor's own voice and stay out of the repo** — this file
    holds absolute paths into `~/.walkie-talkie/voice-corpus/` and the transcript
    beside them, nothing more.
    """
    data = {}
    if os.path.exists(FIXTURES):
        with open(FIXTURES, encoding="utf-8") as handle:
            data = json.load(handle)
    entry = dict(data.get(scenario) or data.get("default") or {})
    if wav:
        entry["wav"] = os.path.abspath(os.path.expanduser(wav))
        if transcript is None:
            entry.pop("transcript", None)
    if transcript is not None:
        entry["transcript"] = transcript
    if not entry.get("wav"):
        raise SystemExit("no fixture for %r and no --wav — see %s" % (scenario, FIXTURES))
    entry["wav"] = os.path.expanduser(entry["wav"])
    if not os.path.exists(entry["wav"]):
        raise SystemExit("fixture WAV is gone: %s" % entry["wav"])
    return entry


def play_wav(path: str, device_name: str | None, dry_run: bool = False) -> float:
    """Play the clip into the virtual input, blocking. Returns its length in seconds."""
    import wispr_loopback as wl

    audio, rate, _ = wl.read_wav(path)
    seconds = len(audio) / float(rate)
    if dry_run:
        print("   · play %s (%.1fs) into %s" % (os.path.basename(path), seconds, device_name or "(resolved)"))
        return seconds
    idx, _name = wl.resolve_device(device_name)
    wl.play(audio, rate, idx)
    return seconds


# ══ the primitive ════════════════════════════════════════════════════════════
#: How long the sink's text has to stop changing before it counts as arrived.
#: Wispr inserts a sentence in more than one event on some paths (a paste, then
#: a trailing space), so the first event is not the end of it.
STABLE_MS = 300

#: Wispr's own verdicts that mean *there is no transcript and there never will
#: be one*. Waiting past them is waiting for a key that is not coming.
DEAD_STATUSES = ("dismissed", "empty", "no_audio", "error")

#: The routes the sink attributes to *a key being pressed*, as opposed to a
#: delivery. The chord this harness posts arrives on both of them.
KEYSTROKE_ROUTES = ("keyDown", "typed")

#: **`raw_transcript` is a status nothing in this repo knew about** until a run
#: on 2026-09-13 19:23 sat in it: `duration 20.56`, `speechDuration 19.08`,
#: `calledExternalAsr 1`, `clientNetworkLatency 176` — Wispr heard the whole
#: clip and called its recogniser — and then never wrote `asrText`,
#: `pastedText` or `formatted`. The relay's settle only ends on `formatted`, so
#: it waited its whole `settleTimeout` (`ring down: timed out waiting for the
#: text — 8006 ms`). Not dead, because the row may still fill in; not done
#: either. It is named so a run that stalls here says *that*, rather than
#: reporting a bare timeout and sending whoever reads it to look at the audio.
STALLED_STATUSES = ("raw_transcript",)


def sink_arrival(sink: dict) -> tuple[str, list[dict]]:
    """What actually *arrived* in the sink, with the chord's own leakage removed.

    `POST /test/wispr-handsfree` posts **fn ⌃ Space**, and with the sink key that
    Space is delivered into it as a one-character `keyDown`. Measured
    2026-09-13: two chords, two stray characters, and a run where Wispr never
    opened its microphone at all reported the transcript `"tu"` — the harness
    reading its own keystrokes back and calling them an answer. That is the
    worst failure a test rig has, because it is green.

    The chord arrives on **both** keystroke routes, not one: measured
    2026-09-13 19:42, a single `fn ⌃ Space` produced
    `typed+keyDown+typed+keyDown — 4 chars`, and a filter that dropped only
    `keyDown` kept the other half and reported it as a transcript. So a
    one-character event on **any keystroke route** does not count.

    A *paste* still counts at any length — a one-character paste is Wispr
    delivering something, a one-character keystroke is us. Belt to the braces of
    `clear_sink_after_microphone()`, which removes the leakage at source.
    """
    events = [e for e in (sink.get("events") or [])
              if e.get("route") not in KEYSTROKE_ROUTES or (e.get("chars") or 0) > 1]
    return "".join(e.get("text") or "" for e in events), events


class StableText:
    """Has the text stopped changing?

    Kept as an object with an injectable clock rather than a sleep loop, because
    the rule — *non-empty, and unchanged for `stable_ms`* — is the one piece of
    the wait that can be wrong quietly, and `evals/test_wispr_loop.py` can only
    test it if it does not own the clock.
    """

    def __init__(self, stable_ms: int = STABLE_MS):
        self.stable_ms = stable_ms
        self.text = ""
        self.since: float | None = None

    def observe(self, text: str, now: float) -> bool:
        text = text or ""
        if text != self.text:
            self.text, self.since = text, now
            return False
        if not text or self.since is None:
            return False
        return (now - self.since) * 1000 >= self.stable_ms


def stand_down(relay: Relay) -> bool:
    """**Never leave a microphone open.** Returns True if it had to close one.

    The chord is a *toggle*, and every path between the two halves of one — a
    timeout, a Ctrl-C, an exception in the playback, a kill — leaves Wispr
    recording with nobody coming back for it. Measured 2026-09-13: a row of
    **495 seconds** with an empty `app`, which read at first like Victor
    dictating for eight minutes and was this rig's own chord left open.

    `POST /test/cancel` and not a second chord: a chord Wispr *missed* the first
    time would be *started* by the second one, which is the same bug with a
    longer fuse. Cancel is idempotent — it is the ✕, and the ✕ on nothing is
    nothing.

    Gated on the state, so it can never take away a dictation Victor started in
    the moment the rig was finishing.
    """
    if relay.dry_run:
        return False
    state = relay.state() or {}
    if not (state.get("isRecording") or state.get("listening") or state.get("speculative")):
        return False
    relay.post("/test/cancel")
    time.sleep(0.3)
    after = relay.state() or {}
    if after.get("isRecording") or after.get("listening"):
        relay.post("/test/cancel")
    return True


def _sink_key(relay: Relay) -> dict:
    """Make the relay's sink the key window, remembering what was in front."""
    return relay.post("/test/sink", {"key": True})


def _sink_restore(relay: Relay) -> dict:
    """Put the app that was in front back in front."""
    return relay.post("/test/sink", {"restore": True})


def wait_for_arrival(relay: Relay, timeout: float, started: float,
                     stable_ms: int = STABLE_MS) -> tuple[str, list, str]:
    """Wait for the sink to settle, or for Wispr to say there will be nothing.

    Returns `(text, events, status)`. `status` is `""` while Wispr is still
    working, one of `DEAD_STATUSES` when it has given up, `"timeout"` when
    neither happened.

    Two exits and no fixed sleep between them. The sink one is the answer; the
    History one is what keeps a dismissed dictation from costing the caller a
    whole timeout — that was the 20-second wait the `WisprHistory` work removed
    from the app, and a harness has no business reintroducing it.
    """
    if relay.dry_run:
        return ("(dry run)", [], "")
    stable = StableText(stable_ms)
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        text, events = sink_arrival(relay.sink_read() or {})
        if events and stable.observe(text, time.monotonic()):
            return (text, events, "")
        row = wispr_history_newest()
        if row and row.started_at >= started - 5 and row.status in DEAD_STATUSES:
            return (text, events, row.status)
        time.sleep(0.1)
    text, events = sink_arrival(relay.sink_read() or {})
    return (text, events, "timeout")


def transcribe(wav: str, device: str | None = None, port: int | None = None,
               timeout: float | None = None, verbose: bool = False,
               dry_run: bool = False) -> dict:
    """**Feed Wispr an arbitrary WAV and hand back what it transcribed.**

    The one primitive the whole harness is built on, and the one Victor's
    teacher-labelling batch wants: `helpers/teacher_label.py`'s `rig.dictate()`
    synthesises Wispr's push-to-talk chord itself and then reads `flow.sqlite`.
    This needs no Accessibility grant of its own and reads no transcript out of
    Wispr's database — the app posts the chord, and the words come back through
    the sink, which is a window we own.

    **The chord is `POST /test/wispr-handsfree`, deliberately not a relay
    gesture.** A gesture would make the relay *start* a dictation and route the
    words at a destination; this is Wispr's own raw chord, so the relay treats
    it as a dictation Victor began by hand — it draws the ring and watches, and
    nothing is delivered anywhere. `listening` is reported back so a caller can
    see which of the two it got.

    Returns a dict; `ok` is False with a `reason` when there is no transcript,
    and `status` carries Wispr's own verdict when it had one.
    """
    port = port or pf.relay_port()
    if port is None:
        return {"ok": False, "reason": "the relay is not listening on 8917-8919"}
    relay = Relay(port, dry_run=dry_run, verbose=verbose)
    wav = os.path.expanduser(wav)
    if not os.path.exists(wav) and not dry_run:
        return {"ok": False, "reason": "no such WAV: %s" % wav}

    mark = LogMark()
    started = time.time()
    out: dict = {"ok": False, "wav": wav, "text": "", "route": "", "status": "", "reason": ""}
    try:
        _open_sink(relay)
        _sink_key(relay)

        relay.post("/test/wispr-handsfree")
        # Not a relay gesture: `listening` should stay false and only the ring
        # should come up. Recorded rather than asserted — the relay is allowed
        # to adopt a hand-started dictation, and which it did is information.
        state = relay.state() or {}
        out["relayListening"] = bool(state.get("listening"))
        out["relayRingUp"] = bool(state.get("ringUp"))

        opened, waited = await_microphone(relay, mark)
        out["micOpenWaitMs"] = round(waited * 1000)
        out["micOpened"] = opened
        # **Clear the sink once the microphone is open, not before.** The chord
        # is delivered into it as four one-character events, and clearing before
        # posting the chord leaves them in front of whatever Wispr sends later.
        # After the edge, anything in the sink can only be about this audio.
        relay.sink_clear()
        if not opened:
            out["reason"] = ("Wispr's microphone never opened — the clip was played at a "
                             "recorder that was not listening")

        seconds = play_wav(wav, device, dry_run)
        out["seconds"] = round(seconds, 2)
        relay.post("/test/wispr-handsfree")   # the chord is a toggle

        text, events, outcome = wait_for_arrival(relay, timeout or (seconds + 60), started)
        # `status` is **Wispr's** word and only ever Wispr's; `outcome` is ours.
        # Printing our own "timeout" under a heading that says *Wispr's History
        # status* is how a harness invents a fact about somebody else's app.
        out["text"], out["outcome"] = text, outcome
        out["route"] = (events[-1].get("route") if events else "") or ""
        out["events"] = events

        t = read_timings(mark.lines())
        row = wispr_history_newest()
        row = row if row and row.started_at >= started - 5 else None
        out["status"] = row.status if row else ""
        out["timings"] = {
            "gestureToMicOpenMs": t.gesture_to_mic_open_ms,
            "micCloseToArrivalMs": t.delivery_ms if t.delivery_ms is not None else t.done_ms,
            "micCloseToWisprDoneMs": t.done_ms,
            "wisprDoneSource": t.done_source,
            # Wispr's column is in **milliseconds** — 937.0 on a 20 s clip, and
            # 470 in the relay's own `Wispr's own e2e 470 ms`. Reporting it as
            # seconds turned a 0.9 s round trip into "937 s".
            "e2eLatencyMs": row.e2e_latency if row else None,
            "ringDownReason": t.ring_down_reason,
        }
        out["wisprApp"] = row.app if row else ""
        # **Which microphone Wispr actually used.** Asked after the fact because
        # it is the only place the answer is written, and because the preflight's
        # reading of `config.json` turned out not to predict it.
        out["wisprMic"] = row.mic_device if row else ""
        wrong_mic = bool(out["wisprMic"]) and not any(
            hint in out["wisprMic"].lower() for hint in ("zoom", "wispr", "loopback", "os output"))
        if wrong_mic:
            # **The root cause outranks the symptom.** `raw_transcript` and
            # `no_audio` are what a recogniser says about silence; the reason
            # there was silence is that Wispr was listening to a different
            # microphone, and reporting the symptom sends the reader to the
            # network, the ASR and the channel in that order — all three fine.
            out["reason"] = (
                "Wispr recorded through %r, not the Loopback device — it never heard the clip. "
                "Pin its microphone: Wispr → Settings → Microphone." % out["wisprMic"])
        elif outcome in DEAD_STATUSES:
            out["reason"] = "Wispr finished with status %r — there is no transcript" % outcome
        elif text.strip():
            out["ok"] = True
        elif out["status"] in STALLED_STATUSES:
            out["reason"] = (
                "Wispr's row stalled at %r — it heard the audio (%s s of speech) and called its "
                "recogniser, then never wrote the text. Nothing is wrong with the channel."
                % (out["status"], out.get("seconds")))
        elif outcome == "timeout":
            out["reason"] = ("nothing arrived in the sink within the timeout"
                             + (" (ring down: %s)" % t.ring_down_reason if t.ring_down_reason else ""))
        else:
            out["reason"] = "the sink settled empty"
        out["log"] = [line.raw for line in mark.lines()]
    finally:
        # Before anything else: a microphone this run opened and did not close.
        if stand_down(relay):
            out["stoodDown"] = True
            out["reason"] = (out.get("reason") or "") + \
                " — a dictation was still open at the end and was cancelled"
        _sink_restore(relay)
        _close_sink(relay)
    return out


# ══ scenarios ════════════════════════════════════════════════════════════════
def _open_sink(relay: Relay):
    """Make the relay's own window key, and empty it.

    Whatever Wispr inserts into "the front app" then lands somewhere this runner
    can read and attribute to a route, instead of into whatever Victor left in
    front of him.
    """
    relay.sink(True)
    relay.sink_clear()


def _close_sink(relay: Relay):
    try:
        relay.sink(False)
    except Exception:
        pass


def _sink_text(relay: Relay) -> tuple[str, list[dict]]:
    """One read, for the scenarios that assert the sink stayed *empty*.

    Through `sink_arrival`, so the chord this harness posts is never counted as
    something having leaked into the window.
    """
    return sink_arrival(relay.sink_read() or {})


def _settled_sink(ctx, grace: float = 4.0) -> tuple[str, list[dict]]:
    """What the sink ended up holding, through the primitive's own stability rule.

    Shared with `transcribe()` on purpose: reading the sink once, the instant the
    ring goes down, catches a sentence Wispr is still halfway through inserting
    and scores it as a bad transcript.
    """
    text, events, _status = wait_for_arrival(ctx.relay, grace, ctx.started)
    return text, events


def await_microphone(relay: Relay, mark: LogMark, timeout: float = 10.0) -> tuple[bool, float]:
    """Wait for **Wispr's own microphone** to open before a note of the clip plays.

    Not the relay's `listening`, which goes up on the chord: this is the
    CoreAudio edge, `wispr flow opened the microphone`. Measured on this Mac the
    same evening: **1042 ms, 3341 ms, 3694 ms** — and 324–674 ms warm, 5–6 s cold
    per the 2026-09-12 measurements. Playing on the chord therefore throws the
    first three seconds of a clip at a recorder that is not open yet, and the
    0.6 s of lead silence `wispr_loopback` adds is nowhere near enough. A short
    fixture could be over before Wispr starts listening at all, which is
    incident 1 with the harness as the cause rather than the subject.

    Returns `(opened, seconds_waited)`. It plays anyway on a timeout — a clipped
    head is still evidence, and the caller reports that it did not see the edge.
    """
    if relay.dry_run:
        return (True, 0.0)

    def open_now():
        if "wispr flow opened the microphone" in mark.fresh():
            return True
        return bool((relay.state() or {}).get("isRecording"))

    got, waited = wait_for(open_now, timeout, poll=0.1)
    return (bool(got), waited)


def _await_listening(relay: Relay, result: Result, timeout: float = 8.0) -> bool:
    """Wait for the relay to say the dictation is open, rather than sleeping at it.

    `listening` is the **relay's** flag — *this app has a sentence in flight* —
    and it is raised on the gesture, not on the microphone, so it is up within
    a frame or two of the chord even when Wispr is cold.
    """
    got, waited = wait_for(lambda: relay.state().get("listening"), timeout,
                           label="listening", dry=relay.dry_run)
    result.check(bool(got) or relay.dry_run, "the dictation opened on the gesture",
                 "listening after %.0f ms" % (waited * 1000) if got else "never listening (%.1fs)" % waited)
    return bool(got)


def _await_microphone(ctx) -> bool:
    """The scenarios' wrapper: wait for Wispr's microphone, and say so either way.

    It also empties the sink at that instant, so the chord's own four characters
    are never in front of what Wispr sends afterwards.
    """
    opened, waited = await_microphone(ctx.relay, ctx.mark)
    ctx.relay.sink_clear()
    ctx.result.check(opened or ctx.relay.dry_run, "Wispr's microphone opened before the clip played",
                     "after %.0f ms" % (waited * 1000) if opened else
                     "never opened (%.1f s) — the clip was played at a recorder that was not listening"
                     % waited)
    return opened


def _await_settled(relay: Relay, mark: LogMark, timeout: float) -> tuple[bool, float]:
    """Wait for the run to be over: the relay's ring is down and it is not listening.

    `⚡ ring down` in the log is the authoritative end — it is written on every
    path including the ones where nothing was delivered — and `/test/state` is
    the belt to its braces for a build whose log wording has moved on.
    """
    def done():
        if "⚡ ring down" in mark.fresh():
            return True
        state = relay.state()
        return state and not state.get("listening") and not state.get("ringUp") and not state.get("settling")

    got, waited = wait_for(done, timeout, poll=0.2, dry=relay.dry_run)
    if got and not relay.dry_run:
        # The delivery line is written a beat after the ring comes down; give the
        # tail of the run a moment to land in the log rather than racing it.
        time.sleep(1.0)
    return bool(got), waited


def _assert_ring(result: Result, t: Timings, budget_ms: int = RING_DOWN_BUDGET_MS):
    gap = t.done_to_ring_down_ms
    if gap is None:
        result.check(False, "ring down within %d ms of Wispr finishing" % budget_ms,
                     "no measurement — Wispr never reported finishing (reason: %s)"
                     % (t.ring_down_reason or "none"))
    else:
        result.check(gap <= budget_ms, "ring down within %d ms of Wispr finishing" % budget_ms,
                     "%d ms%s" % (gap, " (wall clock)" if t.ring_down_estimated else ""))
    result.check("ignored the chord" not in (t.ring_down_reason or ""),
                 "the ring did not come down on 'Wispr ignored the chord'",
                 t.ring_down_reason or "(no ring down line)")


def _assert_text(result: Result, label: str, got: str, want: str) -> float:
    score = similarity(got, want)
    result.check(score >= SIMILARITY_FLOOR, label,
                 "similarity %.2f — %r" % (score, (got or "")[:70]))
    return score


def scenario_caret(ctx) -> Result:
    """1 & 2 — a dictation at the caret, short and long.

    **The short one reproduces incident 1** (2026-09-13 18:18:04): a sentence
    over before Wispr's microphone ever opened leaves the relay inside
    `speculativeGrace`, and the ring stays up for its whole 12 s. The long one is
    the same choreography with time for Wispr to answer, and is the control.

    The sink **is** the caret here, which is the point: the relay's own window is
    key, so whatever Wispr inserts "where the focus is" lands somewhere this
    runner can read instead of in whatever Victor left in front.
    """
    relay, result, mark, outbox = ctx.relay, ctx.result, ctx.mark, ctx.outbox
    _open_sink(relay)
    relay.gesture("forward-click")
    _await_listening(relay, result)
    _await_microphone(ctx)
    seconds = play_wav(ctx.fixture["wav"], ctx.device, relay.dry_run)
    relay.gesture("forward-click")

    settled, waited = _await_settled(relay, mark, timeout=seconds + 60)
    result.check(settled or relay.dry_run, "the run ended (ring down)", "after %.1f s" % waited)

    t = read_timings(mark.lines())
    result.timings = t

    text, events = _settled_sink(ctx)
    state = relay.state()
    delivery = (state.get("lastDelivery") or {})
    kind = delivery.get("kind") or ""
    paste_events = [e for e in events if e.get("route") == "paste"]

    if text:
        _assert_text(result, "the words reached the sink at the caret", text, ctx.fixture.get("transcript", ""))
        result.check(bool(paste_events) or not events,
                     "it arrived by a route the tap can name", ", ".join(sorted({e.get("route", "?") for e in events})) or "(no events)")
    else:
        # No ⌘V is not a failure by itself — Wispr inserts invisibly often enough
        # that `WisprHistory` exists for it. The delivery has to say so, though.
        # A caret delivery writes **no outbox line** (CLAUDE.md, 2026-09-13), so
        # `/test/state.lastDelivery` is the only trace it leaves.
        ok = kind in ("alreadyInserted", "insertedElsewhere") and (delivery.get("to") == "caret")
        result.check(ok, "the words were delivered at the caret",
                     "lastDelivery=%s via=%s to=%s" % (kind or "—", delivery.get("via") or "—", delivery.get("to") or "—"))
        row = ctx.history()
        if row and row.pasted_text:
            _assert_text(result, "Wispr's History row carries the sentence",
                         row.pasted_text, ctx.fixture.get("transcript", ""))

    _assert_ring(result, t)
    result.note("outbox lines this run: %d" % len(outbox.fresh()))
    _close_sink(relay)
    return result


def scenario_spawn_click_in_settle(ctx) -> Result:
    """3 — the second click, made while the sentence is still settling.

    **Incident 2**: Victor opened a spawn dictation, stopped it, and clicked
    again before Wispr had answered. The words went to the caret — into the
    window in front — and no `outbox` line was ever written, so the sentence that
    was supposed to open a new session simply vanished into whatever was focused.

    The click is deliberately posted the moment `settling` goes up, which is the
    window the bug lives in. A real spawn **opens a Terminal window with
    `claude` in it**; that is a side effect on Victor's desktop and the runner
    reports the tty so it can be closed.
    """
    relay, result, mark, outbox = ctx.relay, ctx.result, ctx.mark, ctx.outbox
    _open_sink(relay)
    relay.gesture("forward-up")
    _await_listening(relay, result)
    _await_microphone(ctx)
    seconds = play_wav(ctx.fixture["wav"], ctx.device, relay.dry_run)
    relay.gesture("forward-click")

    # The window the bug lives in: settling up, or listening already down.
    def settling():
        state = relay.state()
        return state.get("settling") or not state.get("listening")

    got, waited = wait_for(settling, timeout=15, poll=0.05, dry=relay.dry_run)
    result.check(bool(got) or relay.dry_run, "the dictation entered the settle",
                 "settling after %.0f ms" % (waited * 1000) if got else "never settled (%.1fs)" % waited)
    relay.gesture("forward-click")   # ← the second click Victor made

    settled, waited = _await_settled(relay, mark, timeout=seconds + 60)
    result.check(settled or relay.dry_run, "the run ended (ring down)", "after %.1f s" % waited)

    t = read_timings(mark.lines())
    result.timings = t

    text, events = _sink_text(relay)
    result.check(not events, "nothing leaked into the window in front",
                 "sink events: %d%s" % (len(events), (" — %r" % text[:60]) if text else ""))

    rows = outbox.fresh()
    spawned = [r for r in rows if str(((r.get("delivery") or {}).get("to")) or r.get("session") or "").startswith("spawn:")]
    result.check(bool(spawned), "the sentence was delivered to the spawned session",
                 "outbox lines: %d, spawn deliveries: %d" % (len(rows), len(spawned)))
    if spawned:
        row = spawned[-1]
        _assert_text(result, "the spawned session got the words",
                     row.get("text") or row.get("line") or "", ctx.fixture.get("transcript", ""))
        result.note("spawned destination: %s — close that Terminal window when you are done"
                    % ((row.get("delivery") or {}).get("to") or row.get("session")))
    else:
        bound = (relay.state() or {}).get("bound")
        if bound:
            result.note("a Terminal window was spawned (%s) — close it when you are done" % bound)

    _assert_ring(result, t)
    _close_sink(relay)
    return result


def scenario_bound(ctx) -> Result:
    """4 — dictate at a bound terminal, and prove the words went *there*.

    A scratch Terminal window running `cat >> …/bound-sink.txt` is the bound
    session: it is a real tty the relay types into, and the file is the evidence.
    Opening it steals focus — `osascript` has to bring Terminal forward — which
    is one more reason the whole act phase is under the 🔒 locks.

    `forward-right` is `VK_F10` → `onLocalToggle` → `toggleDictation`, which is
    the **same call ⌘⌃D makes**: it starts and it ends, so the gesture that opens
    a bound dictation is the gesture that closes it.
    """
    relay, result, mark, outbox = ctx.relay, ctx.result, ctx.mark, ctx.outbox
    sink_file = os.path.join(ctx.scratch, "bound-sink.txt")
    tty = None
    try:
        if not relay.dry_run:
            open(sink_file, "w").close()
            tty = _open_scratch_terminal(sink_file)
        else:
            print("   · osascript: open a Terminal running `cat >> %s`" % sink_file)
            tty = "ttysNNN"
        result.check(bool(tty) or relay.dry_run, "a scratch terminal to bind",
                     tty or "(dry run)")
        if not tty and not relay.dry_run:
            return result

        bound = relay.post("/bind", {"tty": tty})
        target = relay.get("/target")
        result.check(bool(target.get("bound")) or relay.dry_run, "the relay is bound to it",
                     "%s (guarded=%s)" % (target.get("address") or bound.get("address") or "—",
                                          target.get("guarded")))
        if target.get("guarded"):
            result.note("the shell guard applies to this tty — the relay may refuse to type "
                        "into a session that is not an agent; `GET /target.guarded` said true")

        _open_sink(relay)
        relay.gesture("forward-right")
        _await_listening(relay, result)
        _await_microphone(ctx)
        seconds = play_wav(ctx.fixture["wav"], ctx.device, relay.dry_run)
        relay.gesture("forward-right")

        settled, waited = _await_settled(relay, mark, timeout=seconds + 60)
        result.check(settled or relay.dry_run, "the run ended (ring down)", "after %.1f s" % waited)

        t = read_timings(mark.lines())
        result.timings = t

        typed, _ = wait_for(lambda: _read(sink_file).strip(), timeout=10, poll=0.25,
                            dry=relay.dry_run)
        _assert_text(result, "the words were typed into the bound tty",
                     typed or "", ctx.fixture.get("transcript", ""))

        text, events = _sink_text(relay)
        result.check(not events, "nothing leaked into the window in front",
                     "sink events: %d%s" % (len(events), (" — %r" % text[:60]) if text else ""))
        _assert_ring(result, t)
        result.note("outbox lines this run: %d" % len(outbox.fresh()))
    finally:
        _close_sink(relay)
        relay.post("/unbind")
        if tty and not relay.dry_run:
            _close_scratch_terminal(tty)
    return result


def scenario_cancel(ctx) -> Result:
    """5 — 🔼 ← throws the sentence away, and nothing is left behind.

    The mirror gesture of the one that starts it, by design. What is asserted is
    the *absence*: no words in the sink, no line in the outbox, and a ring that
    is down within a second of the gesture rather than at the end of a settle
    nobody is waiting for.
    """
    relay, result, mark, outbox = ctx.relay, ctx.result, ctx.mark, ctx.outbox
    _open_sink(relay)
    relay.gesture("forward-click")
    _await_listening(relay, result)
    _await_microphone(ctx)
    play_wav(ctx.fixture["wav"], ctx.device, relay.dry_run)
    cancelled_at = time.monotonic()
    relay.gesture("forward-left")

    down, waited = wait_for(lambda: not (relay.state().get("ringUp") or relay.state().get("listening")),
                            timeout=10, poll=0.05, dry=relay.dry_run)
    elapsed_ms = (time.monotonic() - cancelled_at) * 1000
    result.check((bool(down) and elapsed_ms <= 1000) or relay.dry_run,
                 "the ring came down within 1000 ms of the gesture",
                 "%.0f ms" % elapsed_ms if down else "still up after %.1f s" % waited)

    if not relay.dry_run:
        time.sleep(1.0)     # the ring-down line is written a beat after the state flips
    t = read_timings(mark.lines())
    result.timings = t
    result.check("cancel" in (t.ring_down_reason or "").lower(),
                 "the ring's reason says it was cancelled", t.ring_down_reason or "(none)")

    text, events = _sink_text(relay)
    result.check(not events and not text, "no words anywhere in the sink",
                 "sink events: %d%s" % (len(events), (" — %r" % text[:60]) if text else ""))
    rows = outbox.fresh()
    result.check(not rows, "no delivery was written to the outbox", "outbox lines: %d" % len(rows))
    _close_sink(relay)
    return result


def _read(path: str) -> str:
    try:
        return open(path, encoding="utf-8", errors="replace").read()
    except Exception:
        return ""


def _osascript(script: str, timeout: float = 20) -> str:
    out = subprocess.run(["/usr/bin/osascript", "-e", script],
                         capture_output=True, text=True, timeout=timeout)
    return (out.stdout or "").strip()


def _open_scratch_terminal(sink_file: str) -> str | None:
    """A Terminal window running `cat >> <file>`, and its tty.

    `do script` returns the tab, and `tty of` it is the address `POST /bind`
    wants — the same string `~/.walkie-talkie/bound-tty` holds. Asked of the tab
    object itself rather than found through `ps`, because two `cat`s in two
    windows are indistinguishable from the outside.
    """
    command = "cat >> %s" % _sh_quote(sink_file)
    tty = _osascript(
        'tell application "Terminal"\n'
        '  activate\n'
        '  set t to do script "%s"\n'
        '  delay 0.6\n'
        '  return tty of t\n'
        'end tell' % command.replace('"', '\\"'))
    return tty.split("/")[-1] if tty.startswith("/dev/") else (tty or None)


def _close_scratch_terminal(tty: str):
    """Close the window whose tab has that tty, and only that one."""
    _osascript(
        'tell application "Terminal"\n'
        '  repeat with w in windows\n'
        '    repeat with t in tabs of w\n'
        '      if (tty of t) contains "%s" then\n'
        '        close w saving no\n'
        '        return "closed"\n'
        '      end if\n'
        '    end repeat\n'
        '  end repeat\n'
        'end tell' % tty)


# ── the victim app ───────────────────────────────────────────────────────────
# Scenarios 6 and 7 need a *second* window that could plausibly receive the
# insertion, so that "the sink got it" is a fact and not a tautology. It is a
# TextEdit document opened **from a scratch file**, never `make new document`
# and never `document 1` by position: TextEdit may already be holding something
# of Victor's, and a harness that clears the front document is a harness that
# eats his notes. Addressing it by its file name means this can only ever read,
# write and close the one it opened.


def _open_victim(scratch: str) -> str | None:
    """Open the scratch document and return the name TextEdit gave it."""
    path = os.path.join(scratch, "victim.txt")
    with open(path, "w", encoding="utf-8") as handle:
        handle.write("")
    name = _osascript(
        'tell application "TextEdit"\n'
        '  activate\n'
        '  open POSIX file "%s"\n'
        '  delay 0.6\n'
        '  return name of front document\n'
        'end tell' % path)
    return name or None


def _victim_text(name: str) -> str:
    """What is in the victim now. A **read** — it activates nothing and steals no focus."""
    return _osascript('tell application "TextEdit" to get text of document "%s"' % name)


def _close_victim(name: str):
    _osascript('tell application "TextEdit" to close document "%s" saving no' % name)


def _sh_quote(value: str) -> str:
    return "'" + value.replace("'", "'\\''") + "'"


@dataclass
class Context:
    relay: Relay
    result: Result
    mark: LogMark
    outbox: OutboxMark
    fixture: dict
    device: str | None
    scratch: str
    #: Wall clock at the start of the run. Wispr's `History` row is created at
    #: the gesture, so a row that started before this is somebody else's
    #: sentence — a chord Wispr ignored leaves the previous finished row on top,
    #: and taking it would report the last thing Victor said as this run's answer.
    started: float = 0.0

    def history(self) -> HistoryRow | None:
        """Wispr's own row for **this** run, or None. One read-only query."""
        if self.relay.dry_run:
            return None
        row = wispr_history_newest()
        return row if row and row.started_at >= self.started - 5 else None


def _sink_question(ctx, key_at_start: bool) -> Result:
    """6 & 7 — **does Wispr pick its insertion target at the start or at the end?**

    This is the question the whole wrap now rests on. Victor has decided the sink
    becomes the wrap mechanism — Walkie's own key text field receives whatever
    Wispr inserts, and Walkie routes it onward — and that design only works if
    the target is chosen **when the transcript is ready**. If Wispr latches the
    front app at the chord instead, making the sink key after the microphone
    closes is too late and the words go to whatever Victor was looking at.

    The two runs are the same choreography with one difference, which is the
    whole experiment:

    * `sink-key-at-start` — the sink is made key **before** the chord. The
      control: whichever way Wispr decides, the sink should get the words. If it
      does not, something more basic is wrong and the other run means nothing.
    * `sink-key-at-stop` — the victim is front for the whole dictation and the
      sink is made key in the ~100 ms after the **stop** chord. Text in the sink
      says Wispr chose at the end; text in the victim says it chose at the start.

    A second window has to be genuinely able to receive the insertion or "the
    sink got it" proves nothing, so there is a real TextEdit document in front,
    and it is read with `osascript` — a read, which activates nothing.

    Wispr's own `History` row carries an `app` column: **its** record of where it
    put the sentence. It is reported beside the observation as a third opinion.
    """
    relay, result, mark = ctx.relay, ctx.result, ctx.mark
    victim = None
    try:
        _open_sink(relay)
        if not relay.dry_run:
            victim = _open_victim(ctx.scratch)
        else:
            print("   · osascript: open %s/victim.txt in TextEdit" % ctx.scratch)
            victim = "victim.txt"
        result.check(bool(victim), "a victim document that could have received the text",
                     victim or "TextEdit would not open one")
        if not victim:
            return result

        if key_at_start:
            answer = _sink_key(relay)
            result.check(relay.dry_run or answer.get("ok") is not False,
                         "the sink was made key before the chord", json.dumps(answer, ensure_ascii=False)[:60])

        relay.gesture("forward-click")
        _await_listening(relay, result)
        _await_microphone(ctx)
        seconds = play_wav(ctx.fixture["wav"], ctx.device, relay.dry_run)
        relay.gesture("forward-click")
        grabbed_ms = None
        if not key_at_start:
            # The stop chord's response returning is the trigger, and the gap is
            # reported: an answer that took 400 ms to grab the keyboard says
            # something different from one that took 40.
            started = time.monotonic()
            answer = _sink_key(relay)
            grabbed_ms = (time.monotonic() - started) * 1000
            result.check(relay.dry_run or answer.get("ok") is not False,
                         "the sink was made key right after the stop chord",
                         "%.0f ms" % grabbed_ms)

        settled, waited = _await_settled(relay, mark, timeout=seconds + 60)
        result.check(settled or relay.dry_run, "the run ended (ring down)", "after %.1f s" % waited)

        result.timings = read_timings(mark.lines())

        sink_text, events = _settled_sink(ctx)
        victim_text = "" if relay.dry_run else _victim_text(victim)
        routes = ", ".join(sorted({e.get("route", "?") for e in events})) or "(none)"

        in_sink = similarity(sink_text, ctx.fixture.get("transcript", "")) >= SIMILARITY_FLOOR
        in_victim = similarity(victim_text, ctx.fixture.get("transcript", "")) >= SIMILARITY_FLOOR

        _assert_text(result, "the words landed in the sink", sink_text, ctx.fixture.get("transcript", ""))
        result.check(not victim_text.strip(), "nothing landed in the victim document",
                     "%d chars%s" % (len(victim_text), (" — %r" % victim_text[:60]) if victim_text.strip() else ""))
        result.note("sink routes: %s" % routes)

        row = ctx.history()
        if row:
            result.note("Wispr's own History row says it inserted into: %s" % (row.app or "(blank)"))

        # The payload. Said in words, because the ✓/✗ rows above only report
        # whether the harness worked — either outcome here is a finding.
        if relay.dry_run:
            result.answer = "(dry run — nothing was dictated, so there is nothing to conclude)"
        elif key_at_start:
            result.answer = ("control: the sink was key from the chord and %s"
                             % ("got the words" if in_sink else
                                ("did NOT get them — the victim did" if in_victim else
                                 "got nothing; neither did the victim")))
        elif in_victim and not in_sink:
            result.answer = ("Wispr chose its target at the START (the chord): the victim was front "
                             "when the dictation opened and the words went there, %s after the sink "
                             "took the keyboard" % ("%.0f ms" % grabbed_ms if grabbed_ms else "shortly"))
        elif in_sink and not in_victim:
            result.answer = ("Wispr chose its target at the END: the sink took the keyboard "
                             "%s after the stop chord and still received the words — the wrap design works"
                             % ("%.0f ms" % grabbed_ms if grabbed_ms else "shortly"))
        elif in_sink and in_victim:
            result.answer = "the words landed in BOTH — Wispr inserted twice, or the sink echoed the victim"
        else:
            result.answer = ("inconclusive: the words reached neither window. Check the ring-down "
                             "reason above before reading anything into it.")

        _assert_ring(result, result.timings)
    finally:
        _sink_restore(relay)
        _close_sink(relay)
        if victim and not relay.dry_run:
            _close_victim(victim)
    return result


def scenario_sink_key_at_start(ctx) -> Result:
    return _sink_question(ctx, key_at_start=True)


def scenario_sink_key_at_stop(ctx) -> Result:
    return _sink_question(ctx, key_at_start=False)


SCENARIOS = {
    "caret-short": (scenario_caret,
                    "a 2–3 s dictation at the caret — incident 1 (expected red today)", True),
    "caret-long": (scenario_caret,
                   "a 15–25 s dictation at the caret — the control", False),
    "spawn-click-in-settle": (scenario_spawn_click_in_settle,
                              "a spawn, stopped, then clicked again mid-settle — incident 2 (expected red today)", True),
    "bound": (scenario_bound, "a dictation typed into a bound scratch terminal", False),
    "cancel": (scenario_cancel, "🔼 ← throws the sentence away", False),
    # The two that answer a question rather than guard a behaviour. Run them
    # `--repeat 3`: Wispr's round trip is 0.7–13 s and one sample of a race is
    # an anecdote.
    "sink-key-at-start": (scenario_sink_key_at_start,
                          "the sink is key BEFORE the chord — the control for the two below", False),
    "sink-key-at-stop": (scenario_sink_key_at_stop,
                         "the sink is made key just AFTER the stop chord — does Wispr choose its "
                         "target at the start or at the end?", False),
}


def run_scenario(name: str, port: int, device: str | None, wav: str | None,
                 transcript: str | None, scratch: str, dry_run: bool,
                 verbose: bool, run_index: int = 1) -> Result:
    if name not in SCENARIOS:
        raise SystemExit("unknown scenario %r — one of: %s" % (name, ", ".join(SCENARIOS)))
    func, _blurb, expected_red = SCENARIOS[name]
    fixture = fixture_for(name, wav, transcript)
    relay = Relay(port, dry_run=dry_run, verbose=verbose)
    result = Result(scenario=name, expected_red=expected_red, dry=dry_run, run_index=run_index)
    mark, outbox = LogMark(), OutboxMark()
    started = time.time()
    ctx = Context(relay=relay, result=result, mark=mark, outbox=outbox,
                  fixture=fixture, device=device, scratch=scratch, started=started)
    result.note("clip: %s (%.1fs) — %r"
                % (os.path.basename(fixture["wav"]), float(fixture.get("seconds") or 0),
                   (fixture.get("transcript") or "")[:60]))
    try:
        func(ctx)
    finally:
        if stand_down(relay):
            result.note("a dictation was still open at the end of the scenario and was cancelled")
        if not dry_run:
            row = ctx.history()
            if row:
                result.note("Wispr History row %d: status=%s, e2e %.1f s, app=%s"
                            % (row.rowid, row.status or "(empty)", row.e2e_latency, row.app or "—"))
            else:
                newest = wispr_history_newest()
                result.note("no History row for this run — Wispr never opened one"
                            + (" (newest is rowid %d, %.0f s older)" % (newest.rowid, started - newest.started_at)
                               if newest else ""))
        result.log = [line.raw for line in mark.lines()]
    return result


# ══ rendering ════════════════════════════════════════════════════════════════
def render(result: Result, verbose: bool = False) -> str:
    """One line per assertion, then the timing table, then the verdict."""
    title = result.scenario + ("  (run %d)" % result.run_index if result.run_index > 1 else "")
    out = ["", "── %s ─────────────────────────────────────────" % title]
    out += [c.render() for c in result.checks]
    if not result.dry:
        out += ["", "  timings", timing_table(result.timings)]
    if result.timings.probes:
        out.append("  probes: " + "; ".join(result.timings.probes))
    for note in result.notes:
        out.append("  · " + note)
    if result.answer:
        out += ["", "  ➤ " + result.answer]
    if verbose and result.log:
        out += ["", "  relay.log ─────────────────────────────────"]
        out += ["  " + line for line in result.log]
    if result.dry:
        verdict = "DRY RUN — nothing was posted and nothing was asserted"
    else:
        verdict = "PASS" if result.passed else "FAIL"
        if not result.passed and result.expected_red:
            verdict += "  (expected red today — this scenario reproduces a live bug)"
    out += ["", verdict]
    return "\n".join(out)


def summary(results: list[Result]) -> str:
    labels = ["%s%s" % (r.scenario, "#%d" % r.run_index if r.run_index > 1 else "") for r in results]
    width = max(len(x) for x in labels)
    rows = ["", "── summary ─────────────────────────────────────────"]
    dry = any(r.dry for r in results)
    for label, r in zip(labels, results):
        if r.dry:
            rows.append("  %-*s  would run  (%s)" % (width, label, SCENARIOS[r.scenario][1]))
            continue
        mark = "PASS" if r.passed else ("FAIL*" if r.expected_red else "FAIL")
        gap = r.timings.done_to_ring_down_ms
        rows.append("  %-*s  %-6s  ring down %s"
                    % (width, label, mark,
                       ("%d ms after Wispr finished" % gap) if gap is not None else "not measured"))
    if not dry:
        rows.append("  (* a FAIL this run expected — the scenario reproduces a live bug)")
    # The open question, gathered across every repetition, because one sample of
    # a race is an anecdote and the disagreement between runs *is* the finding.
    answers = [(label, r.answer) for label, r in zip(labels, results) if r.answer]
    if answers:
        rows += ["", "── where Wispr put the words ───────────────────────"]
        rows += ["  %-*s  %s" % (width, label, answer) for label, answer in answers]
    return "\n".join(rows)


def _transcribe_cli(args, port: int) -> int:
    """`--transcribe`: the primitive, printed. 0 words, 1 nothing arrived,
    3 Wispr itself said there would be nothing (`dismissed` / `empty` / …)."""
    out = transcribe(args.transcribe, device=args.device, port=port,
                     verbose=args.verbose, dry_run=args.dry_run)
    if args.json:
        print(json.dumps(out, ensure_ascii=False, indent=2))
    else:
        t = out.get("timings") or {}
        if out.get("ok"):
            print(out["text"])
        else:
            print("✗ %s" % (out.get("reason") or "no transcript"), file=sys.stderr)
        print("", file=sys.stderr)
        print("  route                    %s" % (out.get("route") or "—"), file=sys.stderr)
        print("  gesture → mic open       %s%s" % (
            _ms(t.get("gestureToMicOpenMs")),
            "" if out.get("micOpened", True) else "   ← never opened; the clip was played anyway"),
            file=sys.stderr)
        print("  mic close → arrival      %s" % _ms(t.get("micCloseToArrivalMs")), file=sys.stderr)
        print("  Wispr's own e2eLatency   %s" % (
            "%.0f ms" % t["e2eLatencyMs"] if t.get("e2eLatencyMs") else "—"), file=sys.stderr)
        print("  Wispr's History status   %s" % (out.get("status") or "—"), file=sys.stderr)
        print("  how this run ended       %s" % (out.get("outcome") or "the sink settled"),
              file=sys.stderr)
        if out.get("wisprApp"):
            print("  Wispr says it inserted into  %s" % out["wisprApp"], file=sys.stderr)
    if out.get("wisprMic"):
        print("  Wispr recorded through   %s" % out["wisprMic"], file=sys.stderr)
    if True:
        print("  relay listening / ring   %s / %s"
              % (out.get("relayListening"), out.get("relayRingUp")), file=sys.stderr)
        if args.verbose:
            for line in out.get("log") or []:
                print("  " + line, file=sys.stderr)
    if args.dry_run:
        return 0
    if out.get("ok"):
        return 0
    return 3 if out.get("outcome") in DEAD_STATUSES else 1


def _ms(value):
    return "%d ms" % value if value is not None else "—"


def _die_politely(signum, _frame):
    """Turn a SIGTERM into an exception, so every `finally` above still runs.

    Without this a `kill` skips the stand-down and the sink restore, and leaves
    Wispr recording and Victor's keyboard pointed at a 40×20 window in a corner.
    """
    raise SystemExit("signal %d" % signum)


def main(argv):
    import argparse
    import signal

    signal.signal(signal.SIGTERM, _die_politely)
    signal.signal(signal.SIGHUP, _die_politely)

    ap = argparse.ArgumentParser(
        prog="wispr-loop",
        description="Drive one real Wispr Flow dictation end to end and assert the outcome.")
    ap.add_argument("scenario", nargs="?", help="one of: " + ", ".join(SCENARIOS))
    ap.add_argument("--transcribe", metavar="WAV",
                    help="the primitive on its own: feed Wispr this WAV and print what it "
                         "transcribed. No scenario, no assertions.")
    ap.add_argument("--all", action="store_true", help="every scenario, then a summary table")
    ap.add_argument("--wav", help="override the fixture's clip")
    ap.add_argument("--transcript", help="override the fixture's known transcript")
    ap.add_argument("--device", help="virtual output device (substring)")
    ap.add_argument("--scratch", default="/tmp", help="where the bound scenario's sink file goes")
    ap.add_argument("--json", action="store_true", help="the same result, machine-readable")
    ap.add_argument("--verbose", action="store_true", help="every relay.log line the run produced")
    ap.add_argument("--repeat", type=int, default=1, metavar="N",
                    help="run each scenario N times. Wispr's round trip is 0.7-13 s, so one "
                         "sample of anything that is a race (sink-key-at-stop) is an anecdote")
    ap.add_argument("--dry-run", action="store_true", help="print the steps, post nothing")
    ap.add_argument("--list", action="store_true", help="the scenarios and what each one is for")
    args = ap.parse_args(argv)

    if args.list:
        for name, (_f, blurb, red) in SCENARIOS.items():
            print("  %-24s %s%s" % (name, blurb, "" if not red else ""))
        return 0
    port = pf.relay_port()
    if port is None:
        print("✗ the relay is not listening on 8917–8919", file=sys.stderr)
        return 2

    if args.transcribe:
        return _transcribe_cli(args, port)

    names = list(SCENARIOS) if args.all else ([args.scenario] if args.scenario else [])
    if not names:
        ap.error("a scenario, --all, or --transcribe <wav>")

    results = []
    for index in range(1, max(1, args.repeat) + 1):
        for name in names:
            results.append(run_scenario(name, port, args.device, args.wav, args.transcript,
                                        args.scratch, args.dry_run, args.verbose, run_index=index))

    if args.json:
        print(json.dumps({"pass": all(r.passed for r in results),
                          "results": [r.as_dict() for r in results]}, ensure_ascii=False, indent=2))
    else:
        for result in results:
            print(render(result, verbose=args.verbose))
        if len(results) > 1:
            print(summary(results))
    if args.dry_run:
        return 0
    return 0 if all(r.passed for r in results) else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
