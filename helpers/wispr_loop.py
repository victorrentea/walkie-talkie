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
from wispr_loopback import PROBE_CHAR  # noqa: E402

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
# **The ring and the settle parted company on 2026-09-13.** `⚡ ring down` now
# fires at the *microphone's close* — "the words are in flight" — and the settle
# ends later with its own line. So the old `⚡ ring down: … — N ms after the
# recording ended` is the pre-split shape and is still read (old logs, and the
# paths that end at the close), while `✍️ the words landed` is where the
# interesting number lives now.
_LANDED = re.compile(r"✍️ the words landed: (.*) — (\d+) ms after the microphone closed$")
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
    #: The settle's own end, since 2026-09-13: `✍️ the words landed: <why> — N ms
    #: after the microphone closed`. This is the number that used to be the ring's.
    landed_ms: int | None = None
    landed_reason: str = ""
    probes: list[str] = field(default_factory=list)
    #: True when `ring_down_ms` had to come off the wall clock.
    ring_down_estimated: bool = False

    @property
    def done_to_ring_down_ms(self) -> int | None:
        if self.done_ms is None or self.ring_down_ms is None:
            return None
        return self.ring_down_ms - self.done_ms

    @property
    def done_to_landed_ms(self) -> int | None:
        """Wispr finished → the relay had put the words somewhere.

        The number that matters since the split: the ring is already down by
        then, so this is the relay's own tail and not time Victor spends looking
        at lightning.
        """
        if self.done_ms is None or self.landed_ms is None:
            return None
        return self.landed_ms - self.done_ms

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
        m = _LANDED.search(text)
        if m:
            t.landed_reason, t.landed_ms = m.group(1), int(m.group(2))
            continue
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
    #: Wispr's LLM pass — punctuation, capitalisation, its custom dictionary.
    #: **This is the text a dictation delivers**, so it is what the harness
    #: reports.
    formatted_text: str = ""
    #: The recogniser's raw reading, before that pass. Reported beside it and
    #: never instead of it: it is the column `docs/teacher-loopback.md` labels a
    #: corpus with, and the two answer different questions.
    asr_text: str = ""
    duration: float = 0.0
    speech_duration: float = 0.0
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
            "       coalesce(app,''), coalesce(strftime('%s', timestamp), '0'), coalesce(micDevice,''),"
            "       coalesce(formattedText,''), coalesce(asrText,''), coalesce(duration,0),"
            "       coalesce(speechDuration,0)"
            "  from History order by rowid desc limit 1").fetchone()
    except Exception:
        return None
    finally:
        db.close()
    if not row:
        return None
    return HistoryRow(rowid=row[0], status=row[1], pasted_text=row[2],
                      e2e_latency=float(row[3]), app=row[4], started_at=float(row[5] or 0),
                      mic_device=row[6], formatted_text=row[7], asr_text=row[8],
                      duration=float(row[9]), speech_duration=float(row[10]))


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
        ("mic close → words landed", ms(t.landed_ms, t.landed_reason)),
        ("Wispr done → words landed", ms(t.done_to_landed_ms)),
        ("Wispr done → delivery", ms(t.done_to_delivery_ms, t.delivery_via)),
    ]
    width = max(len(name) for name, _ in rows)
    out = ["  %-*s   %s" % (width, name, value) for name, value in rows]
    if t.ring_down_reason:
        out.append("  %-*s   %s" % (width, "ring down reason", t.ring_down_reason))
    if t.landed_reason:
        out.append("  %-*s   %s" % (width, "settle ended with", t.landed_reason))
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


def _device_name(device: str | None) -> str:
    """The name of the device this run plays into, resolved once."""
    try:
        import wispr_loopback as wl
        return wl.resolve_device(device)[1]
    except Exception:
        return ""


def _clip_seconds(path: str) -> float:
    """How long the clip is, without playing it — the probes need it up front."""
    try:
        import wispr_loopback as wl
        audio, rate, _ = wl.read_wav(os.path.expanduser(path))
        return len(audio) / float(rate) + wl.LEAD_SEC + wl.TAIL_SEC
    except Exception:
        return 0.0


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


#: Wispr is finished and there is a sentence.
DONE_STATUSES = ("formatted",)
#: Wispr is still working. `raw_transcript` and `processing` are **not** verdicts
#: — measured 2026-09-13, a row sits in them for seconds and then fills in, and
#: treating either as terminal reports "no transcript" for a dictation that was
#: about to produce one.
BUSY_STATUSES = ("", "raw_transcript", "processing", "recording", "transcribing")
#: How long to let a row stay busy. Wispr's own e2e over 30 days: p99 7.1 s, max
#: 13.7 s — 45 s is that with room for a bad network, and the dead statuses end
#: the wait long before it on the ordinary failures.
HISTORY_TIMEOUT = 45.0


def wispr_history_for(started: float, tolerance: float = 5.0) -> HistoryRow | None:
    """Wispr's row for **this** dictation, or None.

    The row is created at the chord, so one that started before this run did
    belongs to a sentence somebody else spoke — and a chord Wispr ignored leaves
    the previous finished row on top, which is exactly how a harness reports the
    last thing Victor said as its own answer.
    """
    row = wispr_history_newest()
    return row if row and row.started_at >= started - tolerance else None


def wait_for_history(started: float, timeout: float = HISTORY_TIMEOUT,
                     poll: float = 0.3) -> tuple[HistoryRow | None, str]:
    """Poll Wispr's own row until its `status` is terminal. Returns `(row, why)`.

    **This is the primary text source**, and it is a deliberate departure from
    the app's rule. `.claude/rules/dictation-source.md` forbids *the relay*
    reading Wispr's database for words — the relay is a live path where the
    pasteboard is the answer and the row is only the *is it done* signal. This
    is a **test harness**, which has the opposite problem: it wants the text
    Wispr produced regardless of where Wispr put it, and the sink can miss it
    (an insertion by a route no tap sees) or be polluted by the chord's own
    keystrokes. `docs/teacher-loopback.md` labelled a corpus from this same
    table for the same reason. Read-only, `mode=ro`, one query per poll.

    `why` is `done`, one of `DEAD_STATUSES`, `timeout`, or `no-row`.
    """
    deadline = time.monotonic() + timeout
    row = None
    while time.monotonic() < deadline:
        row = wispr_history_for(started)
        if row:
            if row.status in DONE_STATUSES:
                return row, "done"
            if row.status in DEAD_STATUSES:
                return row, row.status
            if row.status not in BUSY_STATUSES:
                # An unknown status is not assumed to be either. Reported by
                # name, because the last one that turned up (`raw_transcript`)
                # cost an evening being read as a failure.
                return row, "unknown:%s" % row.status
        time.sleep(poll)
    return row, ("timeout" if row else "no-row")


# ══ the pasteboard, for the no-sink mode ════════════════════════════════════
def pasteboard_change_count() -> int | None:
    """`NSPasteboard.changeCount` — the one number that says *somebody wrote here*.

    It moves on every write by anybody, so it answers the question `--no-sink`
    exists for: with nothing of ours in front, did Wispr put its sentence on the
    pasteboard at all, or did it insert by a route that never touches it? The
    relay's own `probe:` lines answer the other half — whether a ⌘V was posted.
    """
    try:
        from AppKit import NSPasteboard
        return int(NSPasteboard.generalPasteboard().changeCount())
    except Exception:
        return None


def pasteboard_snapshot():
    """Every item and every flavour, so a restore does not eat an image.

    Deliberately **not** `pbpaste`: the general pasteboard on this Mac was
    holding a TIFF and a PNG when this was written, and a text-only snapshot
    would have handed Victor back a string where his screenshot used to be.
    """
    try:
        from AppKit import NSPasteboard
        items = []
        for item in (NSPasteboard.generalPasteboard().pasteboardItems() or []):
            flavours = {}
            for kind in (item.types() or []):
                data = item.dataForType_(kind)
                if data is not None:
                    flavours[str(kind)] = data
            if flavours:
                items.append(flavours)
        return items
    except Exception:
        return None


def pasteboard_restore(items) -> bool:
    """Put a snapshot back. Only ever called when the change count moved."""
    if items is None:
        return False
    try:
        from AppKit import NSPasteboard, NSPasteboardItem
        board = NSPasteboard.generalPasteboard()
        board.clearContents()
        restored = []
        for flavours in items:
            entry = NSPasteboardItem.alloc().init()
            for kind, data in flavours.items():
                entry.setData_forType_(data, kind)
            restored.append(entry)
        if restored:
            board.writeObjects_(restored)
        return True
    except Exception:
        return False


def transcribe(wav: str, device: str | None = None, port: int | None = None,
               timeout: float | None = None, verbose: bool = False,
               dry_run: bool = False, no_sink: bool = False) -> dict:
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

    `no_sink` opens nothing of ours at all: the text still comes from the History
    row, and the run additionally reports the pasteboard's `changeCount` before
    and after plus the relay's `probe:` lines, so it can say **where Wispr's
    output went when there was nothing of ours in front** — onto the pasteboard
    and through a ⌘V, or by a route that touches neither. The pasteboard is
    snapshotted with every flavour and put back if anything wrote to it.
    **The relay is bound to Victor's terminal**, so in this mode a ⌘V the tap
    swallows is routed *there*: use it deliberately, not by default.

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
    out: dict = {"ok": False, "wav": wav, "text": "", "route": "", "status": "", "reason": "",
                 "noSink": bool(no_sink)}
    clipboard = None
    try:
        if no_sink:
            out["pasteboardBefore"] = pasteboard_change_count()
            clipboard = None if dry_run else pasteboard_snapshot()
        else:
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
        if not no_sink:
            relay.sink_clear()
        if not opened:
            out["reason"] = ("Wispr's microphone never opened — the clip was played at a "
                             "recorder that was not listening")

        seconds = play_wav(wav, device, dry_run)
        out["seconds"] = round(seconds, 2)
        relay.post("/test/wispr-handsfree")   # the chord is a toggle

        # ── the answer, from Wispr's own row ────────────────────────────
        # A dry run played nothing, so there is no row coming and waiting 45 s
        # for one is 45 s of a walkthrough nobody can read.
        row, why = ((None, "dry-run") if dry_run
                    else wait_for_history(started, timeout or HISTORY_TIMEOUT))
        out["status"] = row.status if row else ""
        out["outcome"] = why
        out["wisprApp"] = row.app if row else ""
        out["wisprMic"] = row.mic_device if row else ""
        text = ""
        if row:
            # `formattedText` is what a dictation actually delivers; `pastedText`
            # is the same sentence when Wispr has already inserted it. `asrText`
            # is reported beside them and never instead: it is the raw reading,
            # the column a corpus is labelled with, and a different question.
            text = (row.formatted_text or row.pasted_text or "").strip()
            out["asrText"] = row.asr_text
            out["speechDuration"] = row.speech_duration
            out["wisprDuration"] = row.duration

        # ── the sink, now a cross-check and not the source ──────────────
        sink_text, sink_events = ("", []) if no_sink else sink_arrival(relay.sink_read() or {})
        out["sinkText"] = sink_text
        out["sinkRoute"] = (sink_events[-1].get("route") if sink_events else "") or ""
        # **Inverted 2026-09-13.** The swallow is armed at the *start* chord now,
        # so on a correct run Wispr's ⌘V never reaches the window in front and
        # the sink stays **empty** — the row is the text. A sink with something
        # in it is the failure it used to be the proof of.
        out["sinkClean"] = not sink_events
        out["sinkMatched"] = bool(text) and similarity(sink_text, text) >= SIMILARITY_FLOOR
        out["events"] = sink_events

        t = read_timings(mark.lines())
        out["text"], out["route"] = text, out["sinkRoute"]
        if no_sink:
            # Where did it go, with nothing of ours in front? Two independent
            # witnesses: the pasteboard's counter, and the tap's own record of
            # every synthetic key it saw.
            out["pasteboardAfter"] = pasteboard_change_count()
            before, after = out.get("pasteboardBefore"), out["pasteboardAfter"]
            out["pasteboardWritten"] = (before is not None and after is not None and after != before)
            out["probes"] = t.probes
        out["timings"] = {
            "gestureToMicOpenMs": t.gesture_to_mic_open_ms,
            "micOpenWaitMs": out.get("micOpenWaitMs"),
            "micCloseToArrivalMs": t.delivery_ms if t.delivery_ms is not None else t.done_ms,
            "e2eLatencyMs": row.e2e_latency if row else None,
            "ringDownReason": t.ring_down_reason,
        }

        # **Wispr's own record of the microphone it used, against the device we
        # played into.** Not a hint list: the preflight reads `config.json` and
        # that turned out not to predict what Wispr does with it, so the run
        # asserts the two names are the same device and reports it either way.
        out["playedInto"] = _device_name(device)
        wrong_mic = bool(out["wisprMic"]) and not pf._same_device(out["wisprMic"], out["playedInto"])
        if text:
            out["ok"] = True
        elif wrong_mic:
            # The root cause outranks the symptom: an empty row is what a
            # recogniser says about silence, and the reason there was silence is
            # that Wispr was listening to a different microphone.
            out["reason"] = ("Wispr recorded through %r, but the clip was played into %r — it never "
                            "heard it. Pin its microphone: Wispr → Settings → Microphone → 🎓 TO Wispr."
                            % (out["wisprMic"], out["playedInto"]))
        elif why in DEAD_STATUSES:
            out["reason"] = "Wispr finished with status %r — there is no transcript" % why
        elif why == "no-row":
            out["reason"] = "Wispr never opened a row for this chord — it ignored it"
        elif why == "timeout":
            out["reason"] = ("Wispr's row was still %r after %.0f s"
                            % (out["status"] or "(blank)", timeout or HISTORY_TIMEOUT))
        else:
            out["reason"] = "Wispr's row ended %s with no text" % why
        out["log"] = [line.raw for line in mark.lines()]
    finally:
        # Before anything else: a microphone this run opened and did not close.
        if stand_down(relay):
            out["stoodDown"] = True
            out["reason"] = (out.get("reason") or "") + \
                " — a dictation was still open at the end and was cancelled"
        if no_sink:
            # Only if somebody wrote: an untouched pasteboard is left untouched,
            # rather than rewritten with a copy of itself.
            if out.get("pasteboardWritten") and clipboard is not None:
                out["pasteboardRestored"] = pasteboard_restore(clipboard)
        else:
            _sink_restore(relay)
            _close_sink(relay)
    return out


# ══ Wispr's Scratchpad: the notes, the windows, the front app ═══════════════
def wispr_notes() -> dict:
    """A snapshot of `Notes` and `NoteVersions`, read-only, for diffing.

    The Scratchpad is a note, so a sentence dictated into it lands here rather
    than in whatever had focus — which is the entire point of the experiment.
    `content` is kept whole: the question is not only *did a row change* but
    *did our sentence appear in it*.
    """
    if not os.path.exists(WISPR_DB):
        return {"notes": {}, "versions": {}}
    uri = "file:%s?mode=ro" % WISPR_DB.replace("?", "%3f").replace("#", "%23")
    try:
        db = sqlite3.connect(uri, uri=True, timeout=15)
        db.row_factory = sqlite3.Row
    except Exception:
        return {"notes": {}, "versions": {}}
    try:
        notes = {r["id"]: {"title": r["title"] or "", "content": r["content"] or "",
                           "preview": r["contentPreview"] or "", "modifiedAt": str(r["modifiedAt"])}
                 for r in db.execute("select id, title, contentPreview, content, modifiedAt from Notes")}
        versions = {r["id"]: {"noteId": r["noteId"], "content": r["content"] or "",
                              "source": r["source"] or "", "createdAt": str(r["createdAt"])}
                    for r in db.execute("select id, noteId, content, source, createdAt from NoteVersions")}
        return {"notes": notes, "versions": versions}
    except Exception:
        return {"notes": {}, "versions": {}}
    finally:
        db.close()


def notes_diff(before: dict, after: dict) -> list[dict]:
    """What changed between two snapshots — new rows and modified ones alike.

    Kept pure so `evals/test_wispr_loop.py` can hold it to the one behaviour
    that matters: a note whose `content` gained our sentence must be reported
    even though its `id` was there before, because the Scratchpad is a *single*
    note that is appended to, not a new note per dictation.
    """
    changes = []
    for table in ("notes", "versions"):
        old, new = before.get(table) or {}, after.get(table) or {}
        for key, row in new.items():
            if key not in old:
                changes.append(dict(row, table=table, id=key, change="new"))
            elif row != old[key]:
                changes.append(dict(row, table=table, id=key, change="modified",
                                    was=(old[key].get("content") or "")[:80],
                                    was_full=old[key].get("content") or ""))
    return changes


def wispr_windows() -> list[str]:
    """Wispr Flow's window titles. `Status` is its pill and is always there."""
    out = _osascript('tell application "System Events" to tell process "Wispr Flow" to '
                     "name of windows")
    return [w.strip() for w in (out or "").split(",") if w.strip()]


def frontmost_app() -> str:
    return _osascript('tell application "System Events" to name of first application '
                      "process whose frontmost is true")


# ══ the product path: Scratchpad mode ═══════════════════════════════════════
class FocusWatch:
    """Samples the frontmost app in the background for the length of a run.

    *Focus never moves* is a claim about the **whole** dictation, not about the
    two instants either side of it, and the failure it guards against — a window
    that flashes to the front and back while Victor is mid-sentence on a
    projector — is invisible to a before/after pair. So it is sampled, and what
    is reported is the set of everything seen.
    """

    def __init__(self, every: float = 0.4):
        self.every = every
        self.seen: list[str] = []
        self._stop = None
        self._thread = None

    def start(self):
        import threading

        self._stop = threading.Event()

        def loop():
            while not self._stop.is_set():
                app = frontmost_app()
                if app and (not self.seen or self.seen[-1] != app):
                    self.seen.append(app)
                self._stop.wait(self.every)

        self._thread = threading.Thread(target=loop, daemon=True)
        self._thread.start()
        return self

    def stop(self) -> list[str]:
        if self._stop is not None:
            self._stop.set()
        if self._thread is not None:
            self._thread.join(timeout=2)
        return self.seen


def wrap_mode(relay: Relay) -> str:
    return (relay.state() or {}).get("wrapMode") or ""


def set_wrap_mode(relay: Relay, mode: str) -> dict:
    """`scratchpad` · `sink` · `off` — the tick's three settings, from a desk."""
    return relay.post("/test/wrap-mode", {"mode": mode})


def _await_scratchpad_closed(timeout: float = 3.0) -> tuple[bool, float]:
    """Wispr's window list back to just the pill.

    The product path closes the Scratchpad with a 250 ms press after delivering,
    and *within three seconds of delivery* is the difference between a window
    that blinked and a window Victor now has to close.
    """
    got, waited = wait_for(lambda: wispr_windows() == ["Status"], timeout, poll=0.1)
    return bool(got), waited


def added_portion(changes: list[dict]) -> str:
    """The text a changed note **gained** — which is exactly what gets delivered.

    `🗒️ wispr scratchpad: note … (typed) — N chars` is the relay saying it took
    the newly added portion and nothing else, so the delivered string is
    reconstructible here without guessing: the note's content after, minus its
    content before. A new note contributes all of itself.
    """
    parts = []
    for change in changes:
        if change.get("table") != "notes":
            continue
        after = change.get("content") or ""
        before = change.get("was_full") or ""
        parts.append(after[len(before):] if after.startswith(before) else after)
    return "".join(parts)


def _count_occurrences(haystack: str, needle: str) -> int:
    """How many times the sentence appears, normalised.

    `wrap-caret` is the one scenario where the victim **is** the destination, so
    "did it arrive" is not the question — *exactly once* is. A wrap that swallows
    Wispr's own insertion and then adds its own delivers twice, and a test that
    only asks whether the text is there calls that a pass.
    """
    hay, pin = normalise(haystack), normalise(needle)
    return hay.count(pin) if pin else 0


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

    **Not `⚡ ring down` any more** (2026-09-13): that fires at the microphone's
    close now — *the words are in flight* — so waiting on it would return before
    Wispr had said anything at all. The settle has its own line, `✍️ the words
    landed`, and `/test/state.settling` is the belt to its braces.
    """
    def done():
        if "✍️ the words landed" in mark.fresh():
            return True
        state = relay.state()
        return state and not state.get("listening") and not state.get("settling")

    got, waited = wait_for(done, timeout, poll=0.2, dry=relay.dry_run)
    if got and not relay.dry_run:
        # The delivery line is written a beat after the ring comes down; give the
        # tail of the run a moment to land in the log rather than racing it.
        time.sleep(1.0)
    return bool(got), waited


def _assert_ring(result: Result, t: Timings, budget_ms: int = RING_DOWN_BUDGET_MS):
    """The ring and the settle, asserted separately — because they are separate now.

    Before 2026-09-13 one line carried both: the lightning stayed on screen until
    the words arrived, so *when did the ring go down* and *when was the sentence
    delivered* were the same question, and incident 1 was the ring burning 12 s
    over a sentence nobody was waiting for. The app split them — the ring goes at
    the **microphone's close** (`the words are in flight`) and the settle ends
    with `✍️ the words landed`. So this asserts:

    * the ring came down at all, and not on *Wispr ignored the chord*;
    * the **settle** ended within the budget of Wispr finishing, which is the
      relay's own tail and the only part still worth a stopwatch.
    """
    result.check(bool(t.ring_down_reason), "the ring came down",
                 t.ring_down_reason or "(no ring down line at all)")
    result.check("ignored the chord" not in (t.ring_down_reason or ""),
                 "the ring did not come down on 'Wispr ignored the chord'",
                 t.ring_down_reason or "(no ring down line)")
    gap = t.done_to_landed_ms
    if gap is None:
        result.check(False, "the words landed within %d ms of Wispr finishing" % budget_ms,
                     "no measurement — settle end %r, Wispr done %s"
                     % (t.landed_reason or "never", t.done_ms))
    else:
        result.check(gap <= budget_ms, "the words landed within %d ms of Wispr finishing" % budget_ms,
                     "%d ms — %s" % (gap, t.landed_reason or "?"))


def _assert_text(result: Result, label: str, got: str, want: str) -> float:
    score = similarity(got, want)
    result.check(score >= SIMILARITY_FLOOR, label,
                 "similarity %.2f — %r" % (score, (got or "")[:70]))
    return score


def scenario_caret(ctx, wait_for_mic: bool = True) -> Result:
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
    if wait_for_mic:
        _await_microphone(ctx)
    else:
        # **Deliberately not waiting** — this is the incident, not an oversight.
        # See `caret-short-cold` below.
        result.note("played on the chord, without waiting for Wispr's microphone")
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
    """Run one AppleScript. **A timeout is an empty answer, never an exception.**

    These calls are teardown as often as they are measurement, and a teardown
    that raises leaves the victim open, the binding in place and the locks on
    screen. TextEdit in particular can stop answering for a while — measured
    2026-09-14, a close sent while it was busy blocked for 20 s and took the
    whole scenario's `finally` down with it.
    """
    try:
        out = subprocess.run(["/usr/bin/osascript", "-e", script],
                             capture_output=True, text=True, timeout=timeout)
        return (out.stdout or "").strip()
    except Exception:
        return ""


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
    """Close the window whose tab has that tty, and only that one.

    **Kill the `cat` first, and kill it by tty.** Terminal will not close a tab
    with a live process without putting a confirmation dialog on screen, and
    `close … saving no` does not suppress it — so every run of `wrap-bound` left
    its scratch window behind, nine of them before anyone counted (2026-09-14).

    **Not `pkill -f bound-sink.txt`.** The redirection is the shell's, so it
    never appears in `cat`'s own command line: that pattern matches no `cat` at
    all, and does match any *harness shell* whose command line happens to
    mention the file — which on 2026-09-14 was the very shell running the
    cleanup. Matching `tty` plus a `comm` of exactly `cat` can only ever hit the
    one process this function opened.
    """
    try:
        out = subprocess.run(["/bin/ps", "-Ao", "pid=,tty=,comm="],
                             capture_output=True, text=True, timeout=10).stdout
        for line in out.splitlines():
            parts = line.split()
            if len(parts) >= 3 and parts[1] == tty and parts[2].rsplit("/", 1)[-1] == "cat":
                subprocess.run(["/bin/kill", parts[0]], capture_output=True, timeout=5)
        time.sleep(0.4)
    except Exception:
        pass
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
    """Open a **fresh** scratch document and return the name TextEdit gave it.

    A new file name every run, and that is not fastidiousness: TextEdit keys a
    document by path, so re-opening `victim.txt` after truncating it hands back
    the *same in-memory document*, still holding the previous run's text.
    Measured 2026-09-14 — `wrap-bound` reported `'Qzjkwyvqzjkwyv'` and looked
    exactly like every keystroke being delivered twice, which is a far more
    alarming bug than the one that was actually there.
    """
    path = os.path.join(scratch, "victim-%d.txt" % int(time.time() * 1000))
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


def _textedit_running() -> bool:
    """Is TextEdit up? **Ask before telling.**

    `tell application "TextEdit" to …` *launches* it when it is not running, and
    a close sent to an app that has already quit therefore hangs waiting for a
    launch nobody wanted. Measured 2026-09-14: the last victim document was
    closed, macOS auto-quit the documentless app, and the teardown's own close
    then blocked for 20 s and left two `osascript` processes hanging about.
    """
    try:
        return subprocess.run(["/usr/bin/pgrep", "-x", "TextEdit"],
                              capture_output=True, timeout=5).returncode == 0
    except Exception:
        return False


def _close_victim(name: str):
    if not _textedit_running():
        return
    _osascript('tell application "TextEdit" to close document "%s" saving no' % name, timeout=10)


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
    #: Per-scenario knobs from the command line (`--dismiss-delay`, `--no-dismiss`).
    options: dict = field(default_factory=dict)
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


def scenario_dismiss_before_paste(ctx) -> Result:
    """**Can the relay take the sentence out of Wispr's mouth before it speaks?**

    A candidate wrap that needs no permission change and no app change, which is
    the constraint: Wispr must go on working standalone.

    The opening it aims at is one today's runs measured by accident. Wispr writes
    `formattedText` into its row at `status = formatted`, and **inserts only
    later** — every insertion today came a second or more after. That gap is also
    why the sink "mismatched" on the long clip: the ⌘V arrived after the relay
    had closed its capture at formatted + 1 s. So the text exists, in a place we
    can read, before anybody has been given it.

    The experiment: let Wispr finish, read the row the instant it says
    `formatted`, wait `--dismiss-delay` ms, and post Wispr's own **⌃Escape**
    (`53+59`, from its own shortcuts) — *discard this*. Then ask two questions
    with two independent witnesses:

    * **did it insert anyway?** The victim is a real TextEdit document, front and
      key for the whole run, read afterwards with `osascript` (a read; it
      activates nothing). The pasteboard's `changeCount` and the tap's `probe:`
      lines say whether a ⌘V was ever posted.
    * **is the text still ours?** The row is re-read after the dismiss: if
      `formattedText` survives, the sentence is readable and Wispr has been told
      to keep it to itself.

    `--no-dismiss` is the control, and it is the run that matters most: it
    measures the natural formatted → paste gap, which is the whole budget this
    idea has to live inside.

    **No sink here, deliberately.** The question is what Wispr does with nothing
    of ours in front — a window of ours in the way is the thing being replaced.
    """
    relay, result, mark = ctx.relay, ctx.result, ctx.mark
    delay_ms = ctx.options.get("dismiss_delay_ms", 0)
    dismiss = not ctx.options.get("no_dismiss", False)
    victim = None
    clipboard = None
    try:
        import wispr_loopback as wl

        if not relay.dry_run and dismiss and not wl.accessibility_ok():
            result.check(False, "this interpreter may synthesise ⌃Escape",
                         "Accessibility is NOT granted — CGEventPost would fail silently")
            return result

        if not relay.dry_run:
            victim = _open_victim(ctx.scratch)
            clipboard = pasteboard_snapshot()
        else:
            print("   · osascript: open %s/victim.txt in TextEdit" % ctx.scratch)
            victim = "victim.txt"
        result.check(bool(victim), "a victim document, front and key for the whole run", victim or "none")
        if not victim:
            return result
        board_before = pasteboard_change_count()

        # Wispr's own chord, not a relay gesture: the relay must only watch.
        relay.post("/test/wispr-handsfree")
        opened, waited = await_microphone(relay, mark)
        result.check(opened or relay.dry_run, "Wispr's microphone opened before the clip played",
                     "after %.0f ms" % (waited * 1000) if opened else "never opened")
        seconds = play_wav(ctx.fixture["wav"], ctx.device, relay.dry_run)
        relay.post("/test/wispr-handsfree")
        stopped_at = time.monotonic()

        # ── the row, polled at 50 ms, and the instant it says `formatted` ──
        formatted_at = None
        row = None
        deadline = time.monotonic() + (seconds + 45)
        while time.monotonic() < deadline and not relay.dry_run:
            row = wispr_history_for(ctx.started)
            if row and row.status in DONE_STATUSES:
                formatted_at = time.monotonic()
                break
            if row and row.status in DEAD_STATUSES:
                break
            time.sleep(0.05)
        result.check(bool(formatted_at) or relay.dry_run, "Wispr reached `formatted`",
                     "%.0f ms after the stop chord" % ((formatted_at - stopped_at) * 1000)
                     if formatted_at else "status %r" % (row.status if row else "no row"))
        text_at_formatted = (row.formatted_text or row.pasted_text or "") if row else ""
        result.note("row at `formatted`: %d chars — %r" % (len(text_at_formatted), text_at_formatted[:60]))

        # ── the dismiss, `--dismiss-delay` ms later ────────────────────────
        dismissed_at = None
        if dismiss and (formatted_at or relay.dry_run):
            if delay_ms and not relay.dry_run:
                time.sleep(delay_ms / 1000.0)
            if relay.dry_run:
                print("   · CGEventPost ⌃Escape (Wispr's dismiss) %d ms after formatted" % delay_ms)
            else:
                wl.post_wispr_dismiss()
            dismissed_at = time.monotonic()
            result.note("⌃Escape posted %d ms after `formatted`" % delay_ms)
        elif not dismiss:
            result.note("control run — no dismiss; measuring the natural formatted → paste gap")

        # ── did a ⌘V ever come? watch the tap's own probe lines ───────────
        paste_at = None
        watch_until = time.monotonic() + 6.0
        while time.monotonic() < watch_until and not relay.dry_run:
            fresh = mark.fresh()
            if "from pid" in fresh and "Wispr Flow)" in fresh and "probe: synthetic key 9 " in fresh:
                paste_at = time.monotonic()
                break
            time.sleep(0.05)

        # ── three seconds later, ask the victim ───────────────────────────
        if not relay.dry_run:
            time.sleep(max(0.0, 3.0 - (time.monotonic() - (dismissed_at or formatted_at or stopped_at))))
        victim_text = "" if relay.dry_run else _victim_text(victim)
        board_after = pasteboard_change_count()
        final = wispr_history_for(ctx.started) if not relay.dry_run else None

        inserted = bool(victim_text.strip())
        kept = bool(final and (final.formatted_text or final.pasted_text))
        result.check(not inserted, "nothing was inserted into the victim",
                     "%d chars — %r" % (len(victim_text), victim_text[:60]))
        result.check(kept or not dismiss, "the sentence is still in Wispr's row after the dismiss",
                     "%d chars, status %r"
                     % (len((final.formatted_text or final.pasted_text) if final else ""),
                        final.status if final else "no row"))

        result.timings = read_timings(mark.lines())
        result.note("formatted → dismiss: %s" % (
            "%d ms" % ((dismissed_at - formatted_at) * 1000) if dismissed_at and formatted_at else "—"))
        result.note("formatted → ⌘V: %s" % (
            "%d ms" % ((paste_at - formatted_at) * 1000) if paste_at and formatted_at
            else "no ⌘V seen in 6 s"))
        result.note("pasteboard changeCount: %s → %s (%s)" % (
            board_before, board_after,
            "written" if board_before != board_after else "unchanged"))
        result.note("row's final status: %r" % (final.status if final else "—"))
        result.answer = ("inserted into victim: %s; text still in row: %s"
                         % ("YES" if inserted else "no", "YES" if kept else "no"))
    finally:
        if clipboard is not None and pasteboard_change_count() != board_before:
            pasteboard_restore(clipboard)
        stand_down(relay)
        if victim and not relay.dry_run:
            _close_victim(victim)
    return result


def scenario_scratchpad_hold(ctx) -> Result:
    """**Dictate into Wispr's own Scratchpad, and let nothing else be touched.**

    Victor's chosen direction after the other two closed. Wispr's *Open
    Scratchpad* shortcut has three readings on one binding, per Wispr's own
    documentation: **tap** opens and closes the window, **hold** is push-to-talk
    dictating *into the Scratchpad*, double-tap is hands-free into it. The hold
    is the one that matters, because it names a destination that is **not
    "whatever has focus"** — which is the problem every wrap so far has been
    trying to work around.

    The binding is being moved to a single **F18** (keycode 79) for a reason
    worth keeping: a held ⌘⌥ chord would hijack every key Victor pressed for the
    length of a sentence. F18 is a key no keyboard here sends by itself, so
    holding it costs him nothing.

    The run holds the key across the microphone wait **and** the whole clip, so
    `HeldKey` carries a watchdog and an idempotent release: a key left down is
    the one failure here that outlives the process.

    Four questions, each with its own witness, and all four have to be answered
    before this is a wrap and not a hope:

    * **did the text reach a note?** `Notes` / `NoteVersions`, diffed around the
      run — and the Scratchpad is *one* note that gets appended to, so a
      modified row counts as much as a new one.
    * **was the victim left alone?** A real TextEdit document, front and key
      throughout, read with `osascript` afterwards.
    * **did a window open?** Wispr's window list before, during and after. A
      Scratchpad that steals the screen mid-sentence is not usable on a
      projector.
    * **did focus move?** The frontmost app, sampled during the run. It must
      stay TextEdit.

    No sink: a window of ours in front is the thing this would replace.
    """
    relay, result, mark = ctx.relay, ctx.result, ctx.mark
    victim = None
    clipboard = None
    held = None
    board_before = None
    try:
        import wispr_loopback as wl

        keys = wl.scratchpad_keys()
        result.note("Open Scratchpad is bound to keycode(s) %s" % keys)
        if not relay.dry_run and not wl.accessibility_ok():
            result.check(False, "this interpreter may synthesise the held key",
                         "Accessibility is NOT granted — CGEventPost would fail silently")
            return result

        if relay.dry_run:
            print("   · osascript: open %s/victim.txt in TextEdit" % ctx.scratch)
            victim = "victim.txt"
        else:
            victim = _open_victim(ctx.scratch)
            clipboard = pasteboard_snapshot()
        result.check(bool(victim), "a victim document, front and key for the whole run",
                     victim or "none")
        if not victim:
            return result

        board_before = pasteboard_change_count()
        notes_before = wispr_notes()
        windows_before = [] if relay.dry_run else wispr_windows()
        result.note("Wispr windows before: %s" % (windows_before or "—"))

        # ── hold the key ────────────────────────────────────────────────
        if relay.dry_run:
            print("   · CGEventPost keyDown %s (held), wait for the mic edge, play, keyUp" % keys)
            opened, waited = True, 0.0
        else:
            held = wl.HeldKey(keys, max_seconds=60.0)
            held.__enter__()
            opened, waited = await_microphone(relay, mark, timeout=8.0)

        if not opened and not relay.dry_run:
            held.release()
            result.check(False, "Wispr reacted to the held key",
                         "no microphone edge in %.1f s — Wispr did not react to the held key" % waited)
            return result
        result.check(True, "Wispr reacted to the held key",
                     "microphone open after %.0f ms" % (waited * 1000))

        windows_during = [] if relay.dry_run else wispr_windows()
        front_during = "TextEdit" if relay.dry_run else frontmost_app()
        result.note("Wispr windows during: %s" % (windows_during or "—"))

        play_wav(ctx.fixture["wav"], ctx.device, relay.dry_run)
        if held is not None:
            held.release()
        result.note("key released after the clip")

        # ── what Wispr made of it ───────────────────────────────────────
        row, why = ((None, "dry-run") if relay.dry_run
                    else wait_for_history(ctx.started, timeout=45))
        text = ""
        if row:
            text = (row.formatted_text or row.pasted_text or "").strip()
        result.check(bool(text) or relay.dry_run, "Wispr produced a sentence",
                     "%r (status %s, app %s)" % (text[:50], row.status if row else why,
                                                 row.app if row else "—"))
        if row:
            result.note("History row %d: app=%s, mic=%s, e2e %.0f ms"
                        % (row.rowid, row.app or "—", row.mic_device or "—", row.e2e_latency))

        # Notes are written a beat after the row; wait on the change rather than
        # guessing at a sleep, and fall through with an empty diff if none comes.
        changes = []
        if not relay.dry_run:
            found, _ = wait_for(lambda: notes_diff(notes_before, wispr_notes()) or None,
                                timeout=10, poll=0.3)
            changes = found or []
        for change in changes:
            result.note("%s %s %s — %r (modifiedAt %s)"
                        % (change["change"], change["table"], change["id"][:8],
                           (change.get("content") or "")[-80:], change.get("modifiedAt")
                           or change.get("createdAt")))

        in_notes = any(similarity(c.get("content") or "", ctx.fixture.get("transcript", "")) >= 0.5
                       or normalise(ctx.fixture.get("transcript", "")) in normalise(c.get("content") or "")
                       for c in changes)
        victim_text = "" if relay.dry_run else _victim_text(victim)
        board_after = pasteboard_change_count()
        windows_after = [] if relay.dry_run else wispr_windows()
        front_after = "TextEdit" if relay.dry_run else frontmost_app()

        window_opened = len(windows_during) > len(windows_before) or len(windows_after) > len(windows_before)
        focus_moved = (front_during or "").strip() not in ("TextEdit", "")

        result.check(in_notes or relay.dry_run, "the sentence reached a Wispr note",
                     "%d note change(s); match=%s" % (len(changes), in_notes))
        result.check(not victim_text.strip(), "the victim document was left alone",
                     "%d chars — %r" % (len(victim_text), victim_text[:60]))
        result.check(not window_opened, "no Wispr window opened",
                     "before %s / during %s / after %s" % (windows_before, windows_during, windows_after))
        result.check(not focus_moved, "focus stayed on the victim",
                     "during: %r, after: %r" % (front_during, front_after))

        result.timings = read_timings(mark.lines())
        result.note("pasteboard changeCount: %s → %s (%s)"
                    % (board_before, board_after,
                       "written" if board_before != board_after else "unchanged"))
        result.note("probe: %s" % ("; ".join(result.timings.probes) or "none"))
        result.answer = ("text in Notes: %s; victim untouched: %s; window opened: %s; focus moved: %s"
                         % ("YES" if in_notes else "no",
                            "YES" if not victim_text.strip() else "no",
                            "YES" if window_opened else "no",
                            "YES" if focus_moved else "no"))
    finally:
        # **The key first, before anything that could itself throw.**
        if held is not None:
            held.release()
        if clipboard is not None and board_before is not None \
                and pasteboard_change_count() != board_before:
            pasteboard_restore(clipboard)
        stand_down(relay)
        if victim and not relay.dry_run:
            _close_victim(victim)
    return result


def _wrap_run(ctx, destination: str) -> Result:
    """The product path, once, at one destination.

    **Scratchpad mode**, with *Wrap Wispr Flow* on: the relay holds the
    scratchpad chord itself, so Wispr dictates into its own note instead of into
    whatever has focus; the relay then delivers the newest note
    (`delivery.via = "wispr-notes"`) and closes the Scratchpad with a 250 ms
    press. The whole point is that the words arrive **where the gesture said**
    and nowhere else, so every one of these runs keeps a real TextEdit document
    front and key and asks what happened to it.

    `destination` is `caret` · `bound` · `spawn` · `cancel`. Everything except
    the destination assertion is shared, because everything except the
    destination assertion *is* the same claim four times: one note made, one
    delivery by `wispr-notes`, the Scratchpad shut again within three seconds,
    the ring down at the release, the words landed inside two seconds of Wispr
    finishing, and Victor's focus never taken.
    """
    relay, result, mark, outbox = ctx.relay, ctx.result, ctx.mark, ctx.outbox
    victim = None
    tty = None
    was_mode = None
    focus = FocusWatch()
    sink_file = os.path.join(ctx.scratch, "bound-sink.txt")
    try:
        was_mode = wrap_mode(relay)
        answer = set_wrap_mode(relay, "scratchpad")
        result.check(relay.dry_run or (wrap_mode(relay) == "scratchpad"),
                     "the relay is in Scratchpad wrap mode",
                     "was %r, now %r" % (was_mode or "—", (answer or {}).get("mode")
                                         or wrap_mode(relay) or "—"))

        if destination == "bound":
            if relay.dry_run:
                print("   · osascript: a Terminal running `cat >> %s`" % sink_file)
                tty = "ttysNNN"
            else:
                open(sink_file, "w").close()
                tty = _open_scratch_terminal(sink_file)
            relay.post("/bind", {"tty": tty})
            result.check(bool(tty), "a scratch terminal, bound", tty or "none")

        if relay.dry_run:
            print("   · osascript: open %s/victim.txt in TextEdit" % ctx.scratch)
            victim = "victim.txt"
        else:
            victim = _open_victim(ctx.scratch)
        result.check(bool(victim), "a victim document, front and key", victim or "none")
        if not victim:
            return result

        notes_before = wispr_notes()
        windows_before = [] if relay.dry_run else wispr_windows()
        # **Baselines for the probe letters.** A bare `"j" in text` matches the
        # `.jpg` in an envelope's screenshot line and the `k` in `walkie_shot`,
        # and on 2026-09-14 that reported five letters as *arrived* in a run
        # where all seven were lost. A letter counts only if its count went
        # **up**, which prose it was already sitting in cannot do.
        sink_before = _read(sink_file) if destination == "bound" else ""
        if not relay.dry_run:
            focus.start()

        gesture = {"caret": "forward-click", "bound": "forward-right",
                   "spawn": "forward-up", "cancel": "forward-click"}[destination]
        relay.gesture(gesture)
        _await_listening(relay, result)
        _await_microphone(ctx)

        # **The probes are scheduled from the start of playback, not from the
        # stop gesture**, so a *negative* offset can reach back into the
        # recording. That matters now: the Scratchpad is open from the moment
        # the relay takes the hold, so the window in which a keystroke can be
        # stolen begins while Victor is still talking — not after he stops.
        # Every offset is relative to the stop, which lands `seconds` from here.
        typed_probe = destination in ("caret", "bound", "spawn")
        offsets = ctx.options.get("probe_offsets") or [1.5]
        seconds = _clip_seconds(ctx.fixture["wav"])
        probes: list[tuple[str, float]] = []
        probe_deadline = 0.0
        if typed_probe:
            import wispr_loopback as wl

            for (char, code), offset in zip(wl.PROBE_LETTERS, offsets):
                probes.append((char, offset))
                delay = max(0.05, seconds + offset)
                when = "%.1f s %s the stop" % (abs(offset), "before" if offset < 0 else "after")
                if relay.dry_run:
                    print("   · CGEventPost `%s` %s (%.1f s into the run)" % (char, when, delay))
                else:
                    import threading
                    threading.Timer(delay, wl.tap_key, args=(code,)).start()
            # **The run has to outlive its own last probe.** A letter scheduled
            # 4 s after the stop fires *after* a fast settle has finished, and
            # reading the victim before then reports it LOST when it simply had
            # not been typed yet. Measured: the whole settle took 0.7 s.
            probe_deadline = time.monotonic() + max(0.05, seconds + max(offsets)) + 0.6
            result.note("probe letters: %s"
                        % ", ".join("`%s` %s" % (c, "%+.1fs" % o) for c, o in probes))

        seconds = play_wav(ctx.fixture["wav"], ctx.device, relay.dry_run)

        if destination == "cancel":
            relay.gesture("forward-left")
        elif destination == "spawn":
            relay.gesture("forward-click")     # the spawn is not a toggle
        else:
            relay.gesture(gesture)             # click and right-move both toggle

        # **One harmless keystroke, 1.5 s into the settle.** The Scratchpad opens
        # while Wispr writes the note; if it takes the keyboard, this `x` lands
        # there instead of in the document Victor was typing into — which is the
        # failure he would notice first and forgive last.


        settled, waited = _await_settled(relay, mark, timeout=seconds + 60)
        result.check(settled or relay.dry_run, "the run ended", "after %.1f s" % waited)

        closed, closed_after = (True, 0.0) if relay.dry_run else _await_scratchpad_closed()
        result.check(closed, "the Scratchpad closed again within 3 s of delivery",
                     "after %.1f s — windows now %s"
                     % (closed_after, [] if relay.dry_run else wispr_windows()))

        if probe_deadline and not relay.dry_run:
            remaining = probe_deadline - time.monotonic()
            if remaining > 0:
                time.sleep(remaining)
                result.note("waited %.1f s more for the last probe letter" % remaining)

        seen = [] if relay.dry_run else focus.stop()
        result.note("frontmost during the run: %s" % (" → ".join(seen) or "—"))
        strays = [a for a in seen if a not in ("TextEdit", "")]
        if destination == "spawn":
            # A spawn opens a Terminal and that window is *meant* to come
            # forward — it is the session Victor is about to talk to. Anything
            # else in the list is a wrap stealing focus.
            result.check(all(a in ("TextEdit", "Terminal") for a in seen),
                         "focus only ever moved to the spawned Terminal", seen or "—")
        else:
            result.check(not strays, "focus never moved off the victim", seen or "—")

        t = read_timings(mark.lines())
        result.timings = t
        state = relay.state() or {}
        delivery = state.get("lastDelivery") or {}
        changes = notes_diff(notes_before, wispr_notes())
        victim_text = "" if relay.dry_run else _victim_text(victim)
        rows = outbox.fresh()
        # Wispr's own row for this run — the dictated sentence, without the
        # envelope the relay wraps round it on the way to a bound session.
        row = None if relay.dry_run else ctx.history()

        if destination == "cancel":
            result.check(not changes or relay.dry_run, "no note was delivered",
                         "%d note change(s)" % len(changes))
            result.check(not victim_text.strip(), "nothing in the victim",
                         "%d chars — %r" % (len(victim_text), victim_text[:60]))
            result.check(not rows, "no delivery was written to the outbox", "%d line(s)" % len(rows))
            result.answer = "cancelled cleanly: no note, no delivery, victim untouched"
            return result

        # **Not an assertion any more.** Under row-first delivery the sentence
        # comes from Wispr's row as soon as it is terminal, so whether a note is
        # also written is Wispr's business and no longer on the path — and on
        # build b0028d6 it often is not written at all, because the Scratchpad is
        # closed before Wispr gets round to it. Reported, because a note that
        # *does* appear is where a stolen keystroke would show up.
        result.note("notes changed: %d" % len(changes))
        # **`wispr-history`, not `wispr-notes`** (row-first delivery): the words
        # come from Wispr's own row as soon as it is terminal, rather than from
        # the note after the Scratchpad has written it. The note is still
        # written — it is just no longer on the path the sentence travels, which
        # is the whole point of the change and the reason the probe letters
        # should stop appearing in it.
        result.check(delivery.get("via") == "wispr-history" or relay.dry_run,
                     "the delivery came by `wispr-history` (row-first)",
                     "via=%s kind=%s to=%s" % (delivery.get("via") or "—",
                                               delivery.get("kind") or "—",
                                               delivery.get("to") or "—"))

        want = ctx.fixture.get("transcript", "")
        if destination == "caret":
            # The victim *is* the caret here, so the question is not whether the
            # words arrived but whether they arrived **once**. A wrap that
            # swallows Wispr's insertion and adds its own delivers twice.
            times = _count_occurrences(victim_text, want)
            result.check(times == 1 or relay.dry_run, "the words landed in the caret exactly once",
                         "%d occurrence(s) — %r" % (times, victim_text[:70]))
            # `z` is in neither the sentence nor the note, so one anywhere is
            # this rig's. In the victim: the keyboard stayed where Victor left
            # it. In the note: the Scratchpad took it.
            chars = [c for c, _ in probes] or [PROBE_CHAR]
            tail = "".join((c.get("content") or "")[-200:] for c in changes).lower()
            in_victim = all(ch in victim_text.lower() for ch in chars)
            in_note = any(ch in tail for ch in chars)
            result.check((in_victim and not in_note) or relay.dry_run,
                         "every probe letter reached the victim, none the Scratchpad",
                         "victim=%s note=%s — %r" % (in_victim, in_note, victim_text[:70]))
        elif destination == "bound":
            typed, _ = wait_for(lambda: _read(sink_file).strip(), timeout=10, poll=0.25,
                                dry=relay.dry_run)
            # **Containment, not similarity.** What reaches a bound session is
            # the sentence *inside the envelope* — `dictatedHint`, the focused
            # window, the shots — so scoring the whole thing against the bare
            # fixture reads 0.12 on a delivery that is perfectly correct.
            result.check(normalise(want) in normalise(typed or "") or relay.dry_run,
                         "the words reached the bound tty",
                         "%d chars — %r" % (len(typed or ""), (typed or "")[:60]))
            # Here the victim should hold **only** the probe: the sentence went
            # to the tty, so anything else in it is a leak.
            chars = [c for c, _ in probes] or [PROBE_CHAR]
            result.check(_count_occurrences(victim_text, want) == 0 or relay.dry_run,
                         "the sentence did not leak into the victim", "%r" % victim_text[:60])
            result.check(all(ch in victim_text.lower() for ch in chars) or relay.dry_run,
                         "every probe letter reached the victim", "%r" % victim_text[:60])
            # **Against the sentence, not the payload.** What reaches a bound
            # session is the transcript *inside* an English envelope — the
            # dictated-automatically clause, the focused-window line — and that
            # prose contains `w`, `y`, `v`… So the claim that means anything is
            # that no probe letter was folded into the **dictated sentence**,
            # which is the row's own text.
            sentence = (row.formatted_text or row.pasted_text or "") if row else ""
            fouled = [ch for ch in chars if ch in sentence.lower()]
            result.check(not fouled or relay.dry_run,
                         "no probe letter was folded into the dictated sentence",
                         "found %s in %r" % (", ".join(fouled) or "none", sentence[:50]))
        elif destination == "spawn":
            spawned = [r for r in rows
                       if str(((r.get("delivery") or {}).get("to")) or "").startswith("spawn:")]
            result.check(bool(spawned) or relay.dry_run, "the outbox has a `spawn:` delivery",
                         "%d line(s), %d spawn" % (len(rows), len(spawned)))
            if spawned:
                _assert_text(result, "the spawned session got the words",
                             spawned[-1].get("text") or spawned[-1].get("line") or "", want)
                result.note("spawned destination: %s — close that Terminal when you are done"
                            % ((spawned[-1].get("delivery") or {}).get("to")))
            result.check(not victim_text.strip(), "the victim was left alone",
                         "%d chars — %r" % (len(victim_text), victim_text[:60]))

        # Relaxed to 4 s while the product path settles: measured ~2.8 s after
        # the row is terminal, because the Scratchpad opens (~2 s after
        # `formatted`) and is closed again before the relay delivers. The actual
        # number is printed either way — a bar nobody can see the distance to is
        # not a measurement.
        # ── where did each probe letter end up? ────────────────────────
        if probes and not relay.dry_run:
            delivered = added_portion(changes)
            note_tail = "".join((c.get("content") or "")[-200:] for c in changes)
            if destination == "bound":
                landed_in, landed_base = _read(sink_file), sink_before
            elif destination == "spawn":
                landed_in = " ".join(str(r.get("text") or r.get("line") or "") for r in rows)
                landed_base = ""
            else:
                landed_in, landed_base = victim_text, ""
            note_base = "".join((c.get("was_full") or "")[-200:] for c in changes)

            def gained(char: str, after: str, before: str) -> bool:
                """Did this letter *appear*, rather than already being there?"""
                return after.lower().count(char) > before.lower().count(char)

            lost = []
            for char, offset in probes:
                where = {
                    "victim": gained(char, victim_text, ""),
                    "note": gained(char, note_tail, note_base),
                    "delivered": gained(char, delivered, ""),
                }
                # **Only where it can be computed honestly.** For `caret` the
                # victim *is* the destination and its baseline is empty, so the
                # count means something. For `bound` and `spawn` the destination
                # receives the sentence inside an English envelope — which
                # brings its own `j` (`.jpg`), `k` (`walkie_shot`), `w`, `y`,
                # `v` — and no baseline separates that prose from a typed
                # letter, because both are new text. Reporting it anyway said
                # five letters *arrived* in a run where all seven were lost.
                if destination == "caret":
                    where["destination"] = gained(char, landed_in, landed_base)
                if not any(where.values()):
                    lost.append(char)
                result.note("probe `%s` @ %.1fs → %s"
                            % (char, offset,
                               ", ".join(k for k, v in where.items() if v) or "LOST — reached nothing"))
            # A letter in the note is a letter the Scratchpad took off Victor.
            stolen = [c for c, _ in probes if gained(c, note_tail, note_base)]
            result.check(not stolen, "no probe letter was taken by the Scratchpad",
                         "taken: %s" % (", ".join(stolen) or "none"))
            # And none of them may be in what was *delivered* — that is the
            # difference between a keystroke that was merely overheard and one
            # that was posted to Victor's agent inside his own sentence.
            in_delivered = [c for c, _ in probes if gained(c, delivered, "")]
            result.check(not in_delivered, "the note's added portion contains no probe letter",
                         "found: %s — added %r" % (", ".join(in_delivered) or "none", delivered[:60]))
            # The ones typed **during the recording** are the sharpest case: the
            # Scratchpad is already open by then, so a letter that goes astray
            # here was stolen while Victor was still speaking.
            during = [c for c, o in probes if o < 0]
            astray = [c for c in during
                      if gained(c, note_tail, note_base) or not gained(c, victim_text, "")]
            if during:
                result.check(not astray, "letters typed during the recording reached the victim",
                             "astray: %s of %s" % (", ".join(astray) or "none", ", ".join(during)))
            if lost:
                result.note("letters that reached nothing at all: %s" % ", ".join(lost))

        _assert_ring(result, t, budget_ms=4000)
        result.note("Wispr done → words landed: %s"
                    % ("%d ms" % t.done_to_landed_ms if t.done_to_landed_ms is not None else "—"))
        # What the app itself saw of its own Scratchpad, which no amount of
        # `osascript` polling can answer: a window that is parked off-screen is
        # still "open", and one that never became key never took anything.
        pad = (state.get("scratchpad") or {}) if isinstance(state, dict) else {}
        if pad:
            # The raw object, once, verbatim — the field names have moved twice
            # and a note that prints "—" for a key that was renamed is worse than
            # no note, because it reads as "the app reported nothing".
            result.note("scratchpad (raw): %s" % json.dumps(pad, sort_keys=True))
            result.note("scratchpad: open %s ms, visible on the main display %s ms, closed in %s ms, "
                        "%s open(s), parked at %s, reopenedElsewhere=%s, screens=%s"
                        % (pad.get("lastOpenMs", "—"), pad.get("visibleMs", "—"),
                           pad.get("closeMs", "—"), pad.get("opens", "—"),
                           pad.get("parkedFrame") or "—", pad.get("reopenedElsewhere"),
                           pad.get("screens")))
            # **`everBecameKey` is true by design on this build** — the window
            # does take key focus and the *redirect* is what protects the keys.
            # So it is reported and not asserted: the assertions that matter are
            # where the probe letters ended up, and how long the window was
            # actually visible on the display Victor is looking at.
            result.note("everBecameKey=%s (true by design — the redirect is the protection), "
                        "lastKeyAt=%s" % (pad.get("everBecameKey"), pad.get("lastKeyAt") or "—"))
            visible = pad.get("visibleMs")
            result.check((visible is not None and visible <= 50) or relay.dry_run,
                         "the Scratchpad was visible on the main display ≤ 50 ms",
                         "%s ms" % (visible if visible is not None else "not reported"))
        redirect = (state.get("keyRedirect") or {}) if isinstance(state, dict) else {}
        if redirect:
            result.note("key redirect: pid=%s, %s key(s) re-posted"
                        % (redirect.get("pid"), redirect.get("keys")))
        result.note("windows before %s, after %s"
                    % (windows_before, [] if relay.dry_run else wispr_windows()))
        for change in changes:
            result.note("%s %s %s — %r" % (change["change"], change["table"], change["id"][:8],
                                           (change.get("content") or "")[-70:]))
        result.answer = ("delivered to %s via %s; victim %s; Scratchpad closed: %s"
                         % (destination, delivery.get("via") or "—",
                            "untouched" if not victim_text.strip() else "%d chars" % len(victim_text),
                            "yes" if closed else "NO"))
    finally:
        focus.stop()
        if destination == "bound":
            relay.post("/unbind")
            if tty and not relay.dry_run:
                _close_scratch_terminal(tty)
        stand_down(relay)
        if was_mode and was_mode != "scratchpad":
            set_wrap_mode(relay, was_mode)
        if victim and not relay.dry_run:
            _close_victim(victim)
    return result


def scenario_wrap_caret(ctx) -> Result:
    return _wrap_run(ctx, "caret")


def scenario_wrap_bound(ctx) -> Result:
    return _wrap_run(ctx, "bound")


def scenario_wrap_spawn(ctx) -> Result:
    return _wrap_run(ctx, "spawn")


def scenario_wrap_cancel(ctx) -> Result:
    return _wrap_run(ctx, "cancel")


def scenario_wrap_off(ctx) -> Result:
    """**The tick off: Wispr does what Wispr always did, and the relay watches.**

    `wrap-off` is the control for every other `wrap-*` scenario. With the wrap
    off the relay still opens a dictation on the gesture and still draws the
    ring, but it posts Wispr's chord raw and swallows nothing — so the sentence
    goes where Wispr puts it, which is the window in front, and nothing is
    delivered, logged to the outbox or written to a note.

    It is worth a scenario of its own because "the wrap did not break Wispr" is
    only believable if the un-wrapped path is *also* measured, on the same build,
    the same minute. Otherwise a passing `wrap-caret` proves the wrap works and
    says nothing about what Victor gets when he unticks it.
    """
    relay, result, mark, outbox = ctx.relay, ctx.result, ctx.mark, ctx.outbox
    victim = None
    was_mode = None
    focus = FocusWatch()
    try:
        was_mode = wrap_mode(relay)
        set_wrap_mode(relay, "off")
        result.check(relay.dry_run or wrap_mode(relay) == "off", "the wrap is off",
                     "was %r, now %r" % (was_mode or "—", wrap_mode(relay) or "—"))

        if relay.dry_run:
            print("   · osascript: open %s/victim.txt in TextEdit" % ctx.scratch)
            victim = "victim.txt"
        else:
            victim = _open_victim(ctx.scratch)
        result.check(bool(victim), "a victim document, front and key", victim or "none")
        if not victim:
            return result

        notes_before = wispr_notes()
        if not relay.dry_run:
            focus.start()
        before_delivery = (relay.state() or {}).get("lastDelivery")

        relay.gesture("forward-click")
        _await_listening(relay, result)
        _await_microphone(ctx)
        seconds = play_wav(ctx.fixture["wav"], ctx.device, relay.dry_run)
        relay.gesture("forward-click")

        settled, waited = _await_settled(relay, mark, timeout=seconds + 60)
        result.check(settled or relay.dry_run, "the run ended", "after %.1f s" % waited)
        seen = [] if relay.dry_run else focus.stop()

        t = read_timings(mark.lines())
        result.timings = t
        state = relay.state() or {}
        victim_text = "" if relay.dry_run else _victim_text(victim)
        want = ctx.fixture.get("transcript", "")

        # Wispr's own ⌘V, *not* swallowed — the probe line is the proof, and the
        # sentence arriving exactly once is the proof that nobody added a second.
        wispr_paste = [p for p in t.probes if "Wispr Flow" in p and "key 9" in p]
        result.check(bool(wispr_paste) or relay.dry_run, "Wispr posted its own ⌘V",
                     "; ".join(t.probes) or "no probe lines at all")
        result.check(_count_occurrences(victim_text, want) == 1 or relay.dry_run,
                     "Wispr pasted the sentence into the victim exactly once",
                     "%d occurrence(s) — %r" % (_count_occurrences(victim_text, want),
                                                victim_text[:70]))
        result.check(state.get("lastDelivery") == before_delivery or relay.dry_run,
                     "the relay delivered nothing", "lastDelivery %s"
                     % ("unchanged" if state.get("lastDelivery") == before_delivery else "MOVED"))
        result.check(not outbox.fresh(), "no outbox line was written",
                     "%d line(s)" % len(outbox.fresh()))
        result.check(not notes_diff(notes_before, wispr_notes()) or relay.dry_run,
                     "no note was written", "%d note change(s)"
                     % len(notes_diff(notes_before, wispr_notes())))
        result.check(state.get("intercepting") is False or relay.dry_run,
                     "the relay is not intercepting", "intercepting=%s" % state.get("intercepting"))
        result.check(bool(t.ring_down_reason), "the ring came down at the stop",
                     t.ring_down_reason or "(no ring down line)")
        result.note("frontmost during the run: %s" % (" → ".join(seen) or "—"))
        result.answer = ("wrap off: Wispr pasted into the victim itself, the relay delivered nothing")
    finally:
        focus.stop()
        stand_down(relay)
        # **Back to `auto`**, which is the tick's own setting — not to whatever
        # this run happened to find, in case it found a mode a previous run left.
        set_wrap_mode(relay, "auto")
        if victim and not relay.dry_run:
            _close_victim(victim)
    return result


def scenario_wispr_alone(ctx) -> Result:
    """**Does Wispr still work with Walkie Talkie switched off?**

    Victor's guarantee, and the reason it belongs in the suite rather than in
    somebody's memory: every wrap so far has been a way of standing between him
    and an app he relies on, and the day one of them leaves Wispr broken with the
    relay *not running* is the day the whole idea has to be abandoned. A suite
    that only ever tests the wrapped path cannot notice that.

    So this one stands the app all the way down — `relay-restart.sh`'s own
    stand-down and re-bind, reused rather than reimplemented — drives Wispr with
    its own `fn ⌃ Space` posted from here, and checks the sentence lands in the
    front window exactly once, the way it did before any of this existed.

    **The bound tty is read before the stand-down and put back after**, because
    `~/.walkie-talkie/bound-tty` is cleared at quit: losing it would leave Victor
    pointed at nothing with no sign of why.
    """
    relay, result = ctx.relay, ctx.result
    victim = None
    tty = None
    relaunched = False
    try:
        import wispr_loopback as wl

        bound_file = os.path.expanduser("~/.walkie-talkie/bound-tty")
        tty = (_read(bound_file).split(" ")[0] or "").strip() or None
        result.note("bound tty before the stand-down: %s" % (tty or "nothing"))

        if relay.dry_run:
            print("   · pkill -f '/Applications/Walkie Talkie.app'  (stand the app down)")
            victim = "victim.txt"
        else:
            victim = _open_victim(ctx.scratch)
            subprocess.run(["/usr/bin/pkill", "-f", "/Applications/Walkie Talkie.app"],
                           capture_output=True, timeout=10)
            time.sleep(1.0)
        result.check(bool(victim), "a victim document, front and key", victim or "none")

        down, waited = wait_for(lambda: not pf.relay_process()[0], timeout=15, poll=0.5,
                                dry=relay.dry_run)
        result.check(bool(down), "Walkie Talkie is not running",
                     "after %.1f s — %s" % (waited, pf.relay_process()[1]))

        # ── Wispr, on its own ───────────────────────────────────────────
        started = time.time()
        if relay.dry_run:
            print("   · CGEventPost fn ⌃ Space (Wispr's own chord)")
            print("   · poll flow.sqlite for a new row (the relay is down)")
        else:
            wl.post_wispr_handsfree()

        # The relay is down, so there is no microphone edge to watch: Wispr's own
        # row appearing is the only signal that it heard the chord.
        row_seen, waited = wait_for(lambda: wispr_history_for(started), timeout=10, poll=0.2,
                                    dry=relay.dry_run)
        result.check(bool(row_seen), "Wispr opened a row for the chord",
                     "after %.1f s" % waited if row_seen else "no row in %.1f s" % waited)

        play_wav(ctx.fixture["wav"], ctx.device, relay.dry_run)
        if not relay.dry_run:
            wl.post_wispr_handsfree()

        row, why = ((None, "dry-run") if relay.dry_run
                    else wait_for_history(started, timeout=45))
        result.check((row is not None and row.status in DONE_STATUSES) or relay.dry_run,
                     "Wispr's row reached `formatted`",
                     "status %r (%s)" % (row.status if row else "no row", why))

        want = ctx.fixture.get("transcript", "")
        typed, _ = wait_for(lambda: _victim_text(victim).strip(), timeout=10, poll=0.4,
                            dry=relay.dry_run)
        times = _count_occurrences(typed or "", want)
        result.check(times == 1 or relay.dry_run,
                     "Wispr pasted the sentence into the victim exactly once",
                     "%d occurrence(s) — %r" % (times, (typed or "")[:70]))
        result.answer = ("Wispr alone: row %s, sentence in the front window %d time(s)"
                         % (row.status if row else "—", times))
    finally:
        # **Whatever happened above, the app comes back.** This is the one
        # scenario that leaves Victor's Mac without its relay, and an exception
        # in the middle must not be how he finds out.
        if not relay.dry_run:
            subprocess.run(["/usr/bin/open", "/Applications/Walkie Talkie.app"],
                           capture_output=True, timeout=20)
            relaunched = True
            up, waited = wait_for(pf.relay_port, timeout=40, poll=1.0)
            ctx.result.check(bool(up), "Walkie Talkie came back up",
                             "port %s after %.1f s" % (up, waited))
            if up and tty:
                pf.post(up, "/bind", {"tty": tty})
                target = pf.get(up, "/target") or {}
                ctx.result.check(bool(target.get("bound")), "the binding was put back",
                                 "%s" % (target.get("address") or "—"))
            if up:
                engine = pf.get(up, "/engine") or {}
                ctx.result.check(engine.get("wrapMode") == "scratchpad",
                                 "the wrap came back up in Scratchpad mode",
                                 "wrapMode=%s" % (engine.get("wrapMode") or "—"))
        elif relay.dry_run:
            print("   · open '/Applications/Walkie Talkie.app', wait for /up, re-bind %s" % tty)
        if victim and not relay.dry_run:
            _close_victim(victim)
        result.note("relaunched: %s" % relaunched)
    return result


SCENARIOS = {
    # Green since 2026-09-13: ring down 1053 ms after Wispr finished. It waits
    # for the microphone before playing, so it measures the caret path without
    # ever creating incident 1 — `caret-short-cold` is the one that does.
    "caret-short": (scenario_caret,
                    "a 2–3 s dictation at the caret, played once Wispr is listening", False),
    # **The real incident-1 condition, and the reason `caret-short` stopped
    # reproducing it.** The incident is a sentence that is *over before Wispr's
    # microphone opens* — measured 2026-09-13, the chord-to-edge gap was 2913 ms
    # against a 2.2 s clip, exactly the shape. Every other scenario waits for
    # that edge before playing, which is right for measuring anything else and
    # is precisely what stops the bug from happening. This one plays on the
    # chord, like Victor's own hand does.
    "caret-short-cold": (lambda ctx: scenario_caret(ctx, wait_for_mic=False),
                         "the 2–3 s clip played on the chord, without waiting for Wispr's "
                         "microphone — incident 1's condition; green since the ring/settle split", False),
    "caret-long": (scenario_caret,
                   "a 15–25 s dictation at the caret — the control", False),
    "spawn-click-in-settle": (scenario_spawn_click_in_settle,
                              "a spawn, stopped, then clicked again mid-settle — incident 2; "
                              "green since the swallow moved to the start chord", False),
    "bound": (scenario_bound, "a dictation typed into a bound scratch terminal", False),
    "cancel": (scenario_cancel, "🔼 ← throws the sentence away", False),
    # The two that answer a question rather than guard a behaviour. Run them
    # `--repeat 3`: Wispr's round trip is 0.7–13 s and one sample of a race is
    # an anecdote.
    "sink-key-at-start": (scenario_sink_key_at_start,
                          "the sink is key BEFORE the chord — the control for the two below", False),
    # The product path: *Wrap Wispr Flow* on, Scratchpad mode, one per destination.
    "wrap-caret": (scenario_wrap_caret,
                   "Scratchpad mode, 🔼 click — the words land in the caret exactly once", False),
    "wrap-bound": (scenario_wrap_bound,
                   "Scratchpad mode, 🔼 → — the words are typed into the bound tty", False),
    "wrap-spawn": (scenario_wrap_spawn,
                   "Scratchpad mode, 🔼 ↑ — the words go to a session that did not exist", False),
    "wrap-cancel": (scenario_wrap_cancel,
                    "Scratchpad mode, 🔼 ← mid-dictation — no note, no delivery, nothing anywhere", False),
    "wrap-off": (scenario_wrap_off,
                 "the tick off — Wispr pastes into the front window itself and the relay "
                 "delivers nothing; the control for every wrap-* above", False),
    "wispr-alone": (scenario_wispr_alone,
                    "Walkie Talkie stood all the way down — does Wispr still work on its own? "
                    "Victor's guarantee, and it relaunches and re-binds afterwards", False),
    "scratchpad-hold": (scenario_scratchpad_hold,
                        "hold Wispr's Open Scratchpad key and dictate into the Scratchpad — "
                        "a destination that is not 'whatever has focus'", False),
    "dismiss-before-paste": (scenario_dismiss_before_paste,
                             "let Wispr finish, read its row, then post its own ⌃Escape before it "
                             "inserts — the wrap that needs no permission and no app change", False),
    "sink-key-at-stop": (scenario_sink_key_at_stop,
                         "the sink is made key just AFTER the stop chord — does Wispr choose its "
                         "target at the start or at the end?", False),
}


def run_scenario(name: str, port: int, device: str | None, wav: str | None,
                 transcript: str | None, scratch: str, dry_run: bool,
                 verbose: bool, run_index: int = 1, options: dict | None = None) -> Result:
    if name not in SCENARIOS:
        raise SystemExit("unknown scenario %r — one of: %s" % (name, ", ".join(SCENARIOS)))
    func, _blurb, expected_red = SCENARIOS[name]
    fixture = fixture_for(name, wav, transcript)
    relay = Relay(port, dry_run=dry_run, verbose=verbose)
    result = Result(scenario=name, expected_red=expected_red, dry=dry_run, run_index=run_index)
    mark, outbox = LogMark(), OutboxMark()
    started = time.time()
    ctx = Context(relay=relay, result=result, mark=mark, outbox=outbox,
                  fixture=fixture, device=device, scratch=scratch, started=started,
                  options=options or {})
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
                # `e2eLatency` is **milliseconds** — 737.0 is 0.7 s, not 12 minutes.
                result.note("Wispr History row %d: status=%s, e2e %.0f ms, mic=%s, app=%s"
                            % (row.rowid, row.status or "(empty)", row.e2e_latency,
                               row.mic_device or "—", row.app or "—"))
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


def _expected_for(wav: str, given: str | None) -> str:
    """The known transcript for this clip: `--transcript`, else the fixture's."""
    if given is not None:
        return given
    if not os.path.exists(FIXTURES):
        return ""
    with open(FIXTURES, encoding="utf-8") as handle:
        data = json.load(handle)
    for entry in data.values():
        if isinstance(entry, dict) and os.path.expanduser(entry.get("wav") or "") == os.path.abspath(wav):
            return entry.get("transcript") or ""
    return ""


def _reliability_table(runs: list[dict], expected: str) -> str:
    """The deliverable: is **WAV → text** reliable, and how reliable.

    One row per run and a verdict, because the question is not whether a
    transcription can work — it plainly can — but whether five in a row do. A
    single green run of something with a 0.7–13 s round trip in it is an
    anecdote.
    """
    head = ("  %-4s %9s %9s %-15s %9s %6s  %s"
            % ("run", "mic open", "speech", "status", "e2e", "simil", "sink"))
    rows = [head, "  " + "-" * (len(head) - 2)]
    good = 0
    for i, r in enumerate(runs, 1):
        t = r.get("timings") or {}
        score = similarity(r.get("text") or "", expected) if expected else float("nan")
        if expected and score >= SIMILARITY_FLOOR:
            good += 1
        rows.append("  %-4d %9s %9s %-15s %9s %6s  %s"
                    % (i,
                       _ms(t.get("gestureToMicOpenMs")),
                       "%.1f s" % r["speechDuration"] if r.get("speechDuration") else "—",
                       (r.get("status") or r.get("outcome") or "—")[:15],
                       "%.0f ms" % t["e2eLatencyMs"] if t.get("e2eLatencyMs") else "—",
                       "%.2f" % score if expected else "—",
                       "clean" if r.get("sinkClean") else
                       "LEAKED via %s" % (r.get("sinkRoute") or "?")))
    rows.append("")
    rows.append("  %d/%d runs at similarity >= %.2f%s"
                % (good, len(runs), SIMILARITY_FLOOR,
                   "   PASS" if good == len(runs) and runs else "   FAIL"))
    mics = {r.get("wisprMic") for r in runs if r.get("wisprMic")}
    if mics:
        rows.append("  Wispr recorded through: %s" % ", ".join(sorted(mics)))
    return "\n".join(rows)


def _transcribe_cli(args, port: int) -> int:
    """`--transcribe`: the primitive, printed. 0 words, 1 nothing arrived,
    3 Wispr itself said there would be nothing (`dismissed` / `empty` / …)."""
    repeat = max(1, args.repeat)
    if repeat > 1:
        expected = _expected_for(args.transcribe, args.transcript)
        runs = []
        for i in range(repeat):
            if i:
                time.sleep(5)   # a few seconds apart, never two chords in flight
            print("── run %d of %d ─────────────────────────────" % (i + 1, repeat), file=sys.stderr)
            run = transcribe(args.transcribe, device=args.device, port=port,
                             verbose=args.verbose, dry_run=args.dry_run, no_sink=args.no_sink)
            runs.append(run)
            print("   %s" % (run.get("text") or ("✗ " + (run.get("reason") or "no transcript"))),
                  file=sys.stderr)
        if args.json:
            print(json.dumps({"runs": runs, "expected": expected}, ensure_ascii=False, indent=2))
        else:
            print("", file=sys.stderr)
            print(_reliability_table(runs, expected), file=sys.stderr)
        if args.dry_run:
            return 0
        return 0 if all(r.get("ok") for r in runs) else 1

    out = transcribe(args.transcribe, device=args.device, port=port,
                     verbose=args.verbose, dry_run=args.dry_run, no_sink=args.no_sink)
    if args.json:
        print(json.dumps(out, ensure_ascii=False, indent=2))
    else:
        t = out.get("timings") or {}
        if out.get("ok"):
            print(out["text"])
        else:
            print("✗ %s" % (out.get("reason") or "no transcript"), file=sys.stderr)
        print("", file=sys.stderr)
        print("  Wispr's History status   %s  (%s)" % (out.get("status") or "—", out.get("outcome") or "—"),
              file=sys.stderr)
        print("  speechDuration           %s" % (
            "%.2f s" % out["speechDuration"] if out.get("speechDuration") else "—"), file=sys.stderr)
        print("  raw asrText              %r" % ((out.get("asrText") or "")[:70]), file=sys.stderr)
        if out.get("noSink"):
            before, after = out.get("pasteboardBefore"), out.get("pasteboardAfter")
            print("  pasteboard changeCount   %s → %s   %s" % (
                before, after,
                "WRITTEN — Wispr put the sentence on the pasteboard"
                if out.get("pasteboardWritten") else
                "unchanged — Wispr inserted by a route that never touches it"), file=sys.stderr)
            if out.get("pasteboardWritten"):
                print("  pasteboard restored      %s" % out.get("pasteboardRestored"), file=sys.stderr)
            probes = out.get("probes") or []
            print("  probe: lines             %s" % ("; ".join(probes) if probes else
                                                     "none — no synthetic key was posted at all"),
                  file=sys.stderr)
        else:
            print("  sink cross-check         %s%s" % (
                "clean — the swallow held, nothing reached the window in front"
                if out.get("sinkClean") else
                "LEAKED via %s" % (out.get("sinkRoute") or "?"),
                (" — %r" % out["sinkText"][:50]) if out.get("sinkText") else ""), file=sys.stderr)
        print("  gesture → mic open       %s%s" % (
            _ms(t.get("gestureToMicOpenMs")),
            "" if out.get("micOpened", True) else "   ← never opened; the clip was played anyway"),
            file=sys.stderr)
        print("  mic close → arrival      %s" % _ms(t.get("micCloseToArrivalMs")), file=sys.stderr)
        print("  Wispr's own e2eLatency   %s" % (
            "%.0f ms" % t["e2eLatencyMs"] if t.get("e2eLatencyMs") else "—"), file=sys.stderr)

        if out.get("wisprApp"):
            print("  Wispr says it inserted into  %s" % out["wisprApp"], file=sys.stderr)
    if out.get("wisprMic"):
        print("  Wispr recorded through   %s%s" % (
            out["wisprMic"],
            "" if pf._same_device(out["wisprMic"], out.get("playedInto") or "")
            else "   ← NOT %r, the device the clip was played into" % (out.get("playedInto") or "?")),
            file=sys.stderr)
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
    ap.add_argument("--no-sink", action="store_true",
                    help="open nothing of ours: text from Wispr's History row only, plus the "
                         "pasteboard's changeCount and the tap's probe: lines, so the run can say "
                         "where Wispr's output went with nothing of ours in front. The relay is "
                         "bound, so a ⌘V it swallows is routed to that terminal — deliberate use only")
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
    ap.add_argument("--probe-offsets", default="", metavar="S1,S2,…",
                    help="wrap-*: type one distinct letter at each of these many seconds after "
                         "the stop gesture (e.g. 0.3,0.8,1.5,2.5,4) and report where each one "
                         "ended up. Default: a single letter at 1.5 s")
    ap.add_argument("--dismiss-delay", type=int, default=0, metavar="MS",
                    help="dismiss-before-paste: how long after `formatted` to post Wispr's ⌃Escape")
    ap.add_argument("--no-dismiss", action="store_true",
                    help="dismiss-before-paste: the control run — post nothing, and measure the "
                         "natural formatted → paste gap this idea has to live inside")
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
            results.append(run_scenario(
                name, port, args.device, args.wav, args.transcript, args.scratch,
                args.dry_run, args.verbose, run_index=index,
                options={"dismiss_delay_ms": args.dismiss_delay, "no_dismiss": args.no_dismiss,
                         "probe_offsets": [float(x) for x in args.probe_offsets.split(",")
                                           if x.strip()]}))

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
