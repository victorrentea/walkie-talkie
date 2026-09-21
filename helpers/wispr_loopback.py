#!/usr/bin/env python3
"""Play a WAV *into* Wispr Flow and read back what it heard.

Wispr has no API. It transcribes a microphone and pastes the result into
whatever has focus — that is the entire interface. So the only way to use it as
a **teacher** for the local model is to become its microphone: route a recorded
WAV into a virtual input device, hold its push-to-talk key while the file plays,
let go, and read the row it writes into its own database.

    ┌──────────────┐   sd.play()   ┌────────────────────┐   mic   ┌────────────┐
    │ corpus WAV   │ ────────────▶ │ Loopback device    │ ──────▶ │ Wispr Flow │
    └──────────────┘               │ (out side→in side) │         └─────┬──────┘
                                   └────────────────────┘               │
    ┌──────────────┐                                                    │
    │ flow.sqlite  │ ◀──────────────── it writes the transcript ────────┘
    └──────────────┘

That is knowledge distillation by pseudo-labelling: Wispr is the teacher, the
local whisper is the student, and the label costs nothing but wall-clock.

## What this buys that `corpus_harvest.py` cannot

The harvester can only ever take what Wispr still has. Wispr keeps transcripts
forever and prunes **recordings** after about a week — 12,186 against 185 on
2026-09-01, so 98 % of the material it has ever produced is text with no audio
and is useless for training. This inverts the dependency: the audio is ours,
recorded by the addons app and kept as long as we like, and the label is
requested afterwards, including months afterwards.

## The three things that make it awkward, and what is done about them

1. **It runs in real time.** A minute of audio costs a minute. That is fine —
   it is a one-off pass over an archive, run overnight, and a corpus is
   transcribed once, not daily.
2. **Wispr pastes.** Whatever has keyboard focus when the key is released
   receives the text. Running this against Victor's actual desktop would type an
   hour of his own speech into whatever was open. `paste_sink()` reports what is
   in front — it does not open documents on somebody's desktop unasked — and
   `teacher_label.py` refuses to start unless the front app is on its allow-list
   of harmless sinks.
3. **It synthesises keystrokes**, which means Accessibility permission for the
   interpreter running it *and* the 🔒 hands-off locks up while it runs — Victor
   must not touch the keyboard mid-batch, and the only way he learns that is the
   locks (see `victor-macos-addons/docs/hands-off.md`). `teacher_label.py` raises
   them; this module refuses to guess on his behalf.

## The one-time setup this cannot do for itself

Wispr's microphone is chosen in Wispr's own UI and nothing else can set it. So:

    1. Loopback (already installed) → new virtual device, name it `🎓 TO Wispr`
    2. Wispr → Settings → Microphone → `🎓 TO Wispr`
    3. VICTOR: put it back on `Built-in mic (recommended)` when the batch is done

Until that is done, `--device` can be pointed at one of the Loopback devices that
already exist on this Mac (`🎙️TO Zoom`, `🔊OS Output`) to *probe* the channel —
see `wispr_probe.py`, which is the ten-minute go/no-go for the whole idea.
"""

from __future__ import annotations

import os
import sqlite3
import sys
import time
import wave
from dataclasses import dataclass
from datetime import datetime, timezone

import numpy as np

HOME = os.path.expanduser("~")
WISPR_DB = os.path.join(HOME, "Library/Application Support/Wispr Flow/flow.sqlite")

# Wispr's own push-to-talk binding, read out of its config on 2026-09-11:
#   ~/Library/Application Support/Wispr Flow/config.json
#   prefs.user.shortcuts = { ..., "54+61": "ptt", ... }
# 54 = Right Command, 61 = Right Option (macOS virtual keycodes). Overridable,
# because it is a setting in an app we do not control and it will move one day.
PTT_KEYS = [
    int(k) for k in os.environ.get("WISPR_PTT_KEYS", "54,61").split(",") if k.strip()
]
# Preferred virtual input devices, most specific first.
#
# **`🎓 TO Wispr` is the topology now** (2026-09-13): a Loopback device whose
# sources are the physical `MacBook Pro Microphone` *and* Pass-Thru, with Wispr's
# microphone pinned to it permanently. Victor's daily dictation goes mic →
# device → Wispr unchanged, and the rig plays WAVs into the same device. Nothing
# has to touch the system default input any more, which is the point: the switch
# was only ever a way to steer Auto-detect, and Auto-detect turned out to mean
# the built-in microphone (measured: RMS 1714 played against 59 stored).
#
# The rest are the devices that existed before it and are kept only as a
# fallback, which needs `--switch-input` because they are not what Wispr is
# pinned to.
DEVICE_PREFERENCE = ["🎓 TO Wispr", "TO Wispr", "🎙️TO Zoom", "🔊OS Output"]

#: The name that means "Wispr is already pinned to this one, leave the system
#: default input alone".
PINNED_DEVICE_HINT = "to wispr"


def is_pinned_device(name: str) -> bool:
    """Is this the device Wispr itself is pinned to, rather than a fallback?"""
    return PINNED_DEVICE_HINT in (name or "").lower()

SAMPLE_RATE = 16000
# Silence played after the file, so Wispr's endpointing sees an ending rather
# than a key release in the middle of a word.
TAIL_SEC = float(os.environ.get("WISPR_TAIL_SECONDS", "0.5"))
# Silence played *before* it, for the opposite reason: Wispr drops the first
# fraction of a second while its recorder spins up, and the corpus WAVs start on
# a word. **About a second**, per Victor, who watches the indicator every day —
# the 0.6 s this used to be was inside that window, so every clip lost its first
# syllable and the teacher was scored on a word it never heard whole.
LEAD_SEC = float(os.environ.get("WISPR_LEAD_SECONDS", "1.3"))
# How long to wait for a transcript after the key comes up. Wispr is a network
# round-trip plus an LLM formatting pass; measured at 1.5–4 s, and a long clip
# is slower.
RESULT_TIMEOUT_SEC = float(os.environ.get("WISPR_RESULT_TIMEOUT", "45"))

#: How often `play(abort=…)` asks whether to stop. 50 ms is a twentieth of the
#: reaction time it exists to beat — the hand arriving at the mouse before the
#: click that would put Victor's own window under Wispr's paste.
ABORT_POLL_SEC = 0.05

#: How long an abandoned clip's row is waited for. Short on purpose: nothing is
#: wanted from it, it is only taken off the table so the NEXT clip cannot be
#: handed a row that belongs to this one.
ABORT_ROW_TIMEOUT_SEC = 12.0


class PlaybackAborted(Exception):
    """A clip was cut short on purpose — not a failure, and never a label.

    Raised rather than returned because the one thing that must not happen is a
    caller mistaking a half-played clip for a labelled one: an exception cannot
    be ignored by accident, a sentinel can.
    """


# ── the channel ──────────────────────────────────────────────────────────────
def output_devices():
    import sounddevice as sd

    return [
        (i, d["name"])
        for i, d in enumerate(sd.query_devices())
        if d["max_output_channels"] > 0
    ]


def resolve_device(name: str | None):
    """Device index for `name`, or the best of `DEVICE_PREFERENCE` that exists.

    Substring, case-insensitive, first match — CoreAudio names carry emoji and
    trailing model numbers, and asking a caller to type them exactly is asking
    for a typo that looks like "Wispr heard nothing".
    """
    devices = output_devices()
    wanted = [name] if name else DEVICE_PREFERENCE
    for candidate in wanted:
        for idx, dev_name in devices:
            if candidate.lower() in dev_name.lower():
                return idx, dev_name
    raise SystemExit(
        "no usable virtual output device.\n"
        "  looked for: %s\n  have: %s\n"
        "Create one in Loopback and point Wispr's microphone at it — see the "
        "module docstring." % (", ".join(wanted), ", ".join(n for _, n in devices))
    )


def read_wav(path):
    with wave.open(str(path), "rb") as w:
        if w.getsampwidth() != 2:
            raise ValueError(f"{path}: expected 16-bit PCM")
        rate = w.getframerate()
        frames = w.readframes(w.getnframes())
    audio = np.frombuffer(frames, dtype=np.int16).astype(np.float32) / 32768.0
    channels = 1
    return audio, rate, channels


#: Peak the clip is normalised to before it is played. **Not cosmetic.**
#: Measured 2026-09-13: the corpus clips sit at peak ≈ 0.087 of full scale — a
#: laptop microphone across a room — and what came back out of Wispr's own
#: `audio` blob was quieter again: RMS **297 → 109** and the fraction of frames
#: over the relay's own speech threshold **11% → 1%**. Wispr recorded it, called
#: its recogniser and got nothing, leaving the row at `raw_transcript` with no
#: text. A virtual cable has no reason to reproduce the room's distance, so the
#: clip is normalised to a healthy line level and there is still 6 dB of
#: headroom above it.
PLAY_PEAK = float(os.environ.get("WISPR_PLAY_PEAK", "0.5"))


def resample(audio, rate, target_rate):
    """Band-limited resample to the device's own rate, or linear if scipy is gone.

    **Not optional.** The corpus is 16 kHz and the Loopback devices run at 48 kHz,
    and what PortAudio does with a mismatch is up to the host API: CoreAudio may
    refuse the stream outright, or open it at the device's rate and play the
    samples through unchanged — which is the same audio at 3× the speed and a
    recogniser's worst case, because it comes back as confident nonsense rather
    than as an error. Doing it here means the answer is the same on every Mac.

    `scipy.signal.resample_poly` when scipy is there (it is, 1.17); linear
    interpolation otherwise, which for a 3× integer ratio is good enough for
    speech and far better than the wrong rate.
    """
    if not target_rate or int(target_rate) == int(rate):
        return audio, rate
    target_rate = int(target_rate)
    try:
        from math import gcd
        from scipy.signal import resample_poly

        g = gcd(target_rate, int(rate))
        out = resample_poly(audio, target_rate // g, int(rate) // g)
    except Exception:
        n = int(round(len(audio) * target_rate / float(rate)))
        out = np.interp(np.linspace(0, len(audio) - 1, n),
                        np.arange(len(audio)), audio)
    return np.asarray(out, dtype=np.float32), target_rate


def play(audio, rate, device_index, gain=1.0, peak=None, abort=None):
    """Play through to the end, blocking. Real time, by construction.

    Returns True if the clip was played whole, False if `abort` cut it short —
    `abort` being a predicate polled while the audio runs (Victor's hand landing
    on the mouse, in the batch that uses it). A cut clip is not a shorter clip:
    Wispr heard half a sentence, so whatever comes back describes audio the
    corpus does not contain and the caller must throw it away.

    Three things beyond `sd.play`, all learned the hard way on 2026-09-13:

    * **Resampled to the device's own rate.** See `resample` — a rate mismatch
      is not an error PortAudio is obliged to raise.
    * **Normalised to `PLAY_PEAK`.** A clip at the level a room microphone
      recorded it (peak 0.087 of full scale) lands under Wispr's own voice
      activity threshold. A virtual cable has no reason to reproduce the
      distance.
    * **Matched to the device's channel count.** These devices are
      two-channel; handing PortAudio a mono array leaves the signal on one side,
      and anything downstream that averages the two loses 6 dB.
    """
    import sounddevice as sd

    device_rate = rate
    channels = 1
    try:
        info = sd.query_devices(device_index)
        device_rate = int(info.get("default_samplerate") or rate)
        channels = max(1, int(info["max_output_channels"]))
    except Exception:
        pass

    signal = np.asarray(audio, dtype=np.float32) * gain
    signal, rate = resample(signal, rate, device_rate)

    target = PLAY_PEAK if peak is None else peak
    if target:
        loudest = float(np.max(np.abs(signal))) or 1.0
        signal = signal * (target / loudest)
    lead = np.zeros(int(rate * LEAD_SEC), dtype=np.float32)
    tail = np.zeros(int(rate * TAIL_SEC), dtype=np.float32)
    signal = np.clip(np.concatenate([lead, signal, tail]), -1.0, 1.0)

    if channels > 1:
        signal = np.repeat(signal[:, None], channels, axis=1)
    if abort is None:
        sd.play(signal, samplerate=rate, device=device_index, blocking=True)
        return True

    sd.play(signal, samplerate=rate, device=device_index, blocking=False)
    # The deadline is the belt: a stream that ends without saying so must not
    # leave the key held down for the rest of the night.
    deadline = time.monotonic() + len(signal) / float(rate) + 1.0
    while time.monotonic() < deadline:
        if abort():
            sd.stop()
            return False
        try:
            if not sd.get_stream().active:
                break
        except Exception:  # noqa: BLE001 — no stream is "finished" too
            break
        time.sleep(ABORT_POLL_SEC)
    sd.wait(ignore_errors=True)
    return True


# ── the key ──────────────────────────────────────────────────────────────────
def _post(keycode: int, down: bool):
    import Quartz

    event = Quartz.CGEventCreateKeyboardEvent(None, keycode, down)
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, event)


class PushToTalk:
    """Holds Wispr's PTT chord down for the length of a `with` block.

    A context manager and not two functions, because the failure that matters is
    a key left down: an exception between press and release would leave Right
    Command held for the rest of the session, which turns every subsequent
    keystroke on the machine into a shortcut.
    """

    def __init__(self, keys=None):
        self.keys = list(keys or PTT_KEYS)

    def __enter__(self):
        for key in self.keys:
            _post(key, True)
            time.sleep(0.02)
        # Wispr needs a beat between "key is down" and "audio is arriving", or
        # the first word lands before its recorder is open.
        time.sleep(0.35)
        return self

    def __exit__(self, *exc):
        for key in reversed(self.keys):
            _post(key, False)
            time.sleep(0.02)
        return False


# Wispr's *dismiss* chord, read out of the same `prefs.user.shortcuts` map as the
# push-to-talk one: `"53+59": "dismiss"` — macOS keycodes 53 (Escape) and 59
# (Left Control), i.e. ⌃Escape. `WISPR_DISMISS_KEYS` overrides.
DISMISS_KEYS = [
    int(k) for k in os.environ.get("WISPR_DISMISS_KEYS", "59,53").split(",") if k.strip()
]


#: Wispr's hands-free chord, from its own `shortcuts` map: `"49+59+63"` — Space
#: (49), Control (59), Fn (63). The one Victor's own dictation uses when nothing
#: of ours is running.
HANDSFREE_KEYS = [
    int(k) for k in os.environ.get("WISPR_HANDSFREE_KEYS", "59,63,49").split(",") if k.strip()
]


def _chord_flags(modifiers) -> int:
    """The CGEvent flag mask for a set of modifier keycodes, and nothing else.

    **Explicit, not inherited.** `CGEventCreateKeyboardEvent` picks up whatever
    the hardware thinks is held, which on this rig is whatever Wispr happens to
    be pressing at that instant — the reason a probe once went out as ⌘X. Here
    the chord must carry *its own* modifiers and no others, or Wispr sees a
    shortcut nobody bound.
    """
    import Quartz

    masks = {
        59: Quartz.kCGEventFlagMaskControl,      # left control
        62: Quartz.kCGEventFlagMaskControl,      # right control
        63: Quartz.kCGEventFlagMaskSecondaryFn,  # fn
        55: Quartz.kCGEventFlagMaskCommand,
        54: Quartz.kCGEventFlagMaskCommand,
        58: Quartz.kCGEventFlagMaskAlternate,
        61: Quartz.kCGEventFlagMaskAlternate,
        56: Quartz.kCGEventFlagMaskShift,
        60: Quartz.kCGEventFlagMaskShift,
    }
    flags = 0
    for code in modifiers:
        flags |= masks.get(code, 0)
    return flags


def post_chord(keys=None, flags=None):
    """Post a chord: modifiers down, key with explicit flags, everything up.

    The last keycode is the key; the ones before it are its modifiers. The key
    event's flags are **set**, not inherited, so the chord is exactly itself.
    """
    import Quartz

    keys = list(keys or HANDSFREE_KEYS)
    if not keys:
        return False
    modifiers, key = keys[:-1], keys[-1]
    mask = _chord_flags(modifiers) if flags is None else flags
    for code in modifiers:
        _post(code, True)
        time.sleep(0.01)
    for down in (True, False):
        event = Quartz.CGEventCreateKeyboardEvent(None, key, down)
        Quartz.CGEventSetFlags(event, mask)
        Quartz.CGEventPost(Quartz.kCGHIDEventTap, event)
        time.sleep(0.02)
    for code in reversed(modifiers):
        _post(code, False)
        time.sleep(0.01)
    return True


def post_wispr_handsfree():
    """Wispr's own `fn ⌃ Space`, posted from here — for when the relay is down."""
    return post_chord(HANDSFREE_KEYS)


def post_wispr_dismiss(keys=None):
    """Post Wispr's own **⌃Escape** — *discard this sentence*.

    **Why this is synthesised here and not asked of the relay.** The relay does
    have `postWisprCancel`, and `POST /test/cancel` looks like the way to reach
    it — but it is not, at the one instant this matters. Read
    `WisprFlowSource.cancel()`: with the microphone already closed and a capture
    standing (`!isRecording, !speculative, capturing` — exactly the state at
    `formatted`) it takes the first branch, abandons the relay's *own* capture
    and returns **without posting anything**. Only `isRecording || speculative`
    reaches the chord. So there is no route that dismisses Wispr after it has
    finished, and the experiment this exists for happens entirely inside that
    window.

    This is the same mechanism `PushToTalk` above already uses and that
    `teacher_label.py` runs a whole batch on: `CGEventPost`, needing Accessibility
    for *this interpreter*, which is why `accessibility_ok()` is checked first
    and the caller is told rather than left with a chord that silently went
    nowhere.

    Modifier down, key down, key up, modifier up — in that order, so the release
    of a press that was made is never left orphaned.
    """
    keys = list(keys or DISMISS_KEYS)
    if not keys:
        return False
    modifiers, key = keys[:-1], keys[-1]
    for code in modifiers:
        _post(code, True)
        time.sleep(0.01)
    _post(key, True)
    time.sleep(0.02)
    _post(key, False)
    time.sleep(0.01)
    for code in reversed(modifiers):
        _post(code, False)
        time.sleep(0.01)
    return True


#: Wispr's *Open Scratchpad* binding. Per Wispr's own documentation it has three
#: readings on one shortcut: **tap** opens and closes the window, **hold** is
#: push-to-talk dictating *into the Scratchpad*, and double-tap is hands-free
#: into it (only with the window already visible). The hold is the one that
#: matters here — it puts the sentence somewhere that is not "whatever has
#: focus", which is the whole problem.
#:
#: Read from `prefs.user.shortcuts` by **value**, not by key, because the key is
#: the chord and the chord is exactly what is being changed: it shipped as
#: `35+54+61` (⌘⌥P) and is being rebound to a single **F18** (keycode 79) so
#: that holding it touches none of Victor's own keys. A held ⌘⌥ would hijack
#: every keystroke he made for the length of a sentence, which was his objection
#: and is a fair one.
SCRATCHPAD_FALLBACK = 79


def scratchpad_keys() -> list[int]:
    """The keycodes bound to `open_scratchpad`, or `[79]` (F18)."""
    override = os.environ.get("WISPR_SCRATCHPAD_KEYS")
    if override:
        return [int(k) for k in override.split(",") if k.strip()]
    try:
        import json

        config = os.path.join(HOME, "Library/Application Support/Wispr Flow/config.json")
        with open(config, encoding="utf-8") as handle:
            shortcuts = json.load(handle).get("prefs", {}).get("user", {}).get("shortcuts", {})
        for chord, action in (shortcuts or {}).items():
            if action == "open_scratchpad":
                return [int(part) for part in str(chord).split("+") if part.strip().isdigit()]
    except Exception:
        pass
    return [SCRATCHPAD_FALLBACK]


class HeldKey:
    """Holds one key (or chord) down for the length of a `with` block.

    A context manager with a **watchdog**, and both halves are the point. The
    failure that matters is a key left down: this one is held across a
    microphone wait *and* a whole clip, so an exception anywhere in the middle
    would otherwise leave a key pressed for the rest of the session — and if it
    is a modifier, every keystroke Victor makes afterwards becomes a shortcut.

    So: released in `__exit__` on every path, released by a timer at
    `max_seconds` even if `__exit__` never runs, and the release is idempotent
    so the two can race harmlessly.
    """

    def __init__(self, keys=None, max_seconds: float = 60.0):
        self.keys = list(keys or scratchpad_keys())
        self.max_seconds = max_seconds
        self._down = False
        self._lock = __import__("threading").Lock()
        self._timer = None

    def __enter__(self):
        import threading

        with self._lock:
            for code in self.keys:
                _post(code, True)
                time.sleep(0.01)
            self._down = True
        self._timer = threading.Timer(self.max_seconds, self.release)
        self._timer.daemon = True
        self._timer.start()
        return self

    def release(self) -> bool:
        """Let go. Safe to call twice, from two threads, in either order."""
        with self._lock:
            if not self._down:
                return False
            for code in reversed(self.keys):
                _post(code, False)
                time.sleep(0.01)
            self._down = False
        return True

    def __exit__(self, *exc):
        self.release()
        if self._timer is not None:
            self._timer.cancel()
        return False


#: `z`, the harmless keystroke the wrap scenarios type mid-settle.
#:
#: **Not `x`**, and the reason is the whole value of the probe: the fixture says
#: *"Commit and push the fix."* — which already contains an `x`. Counting `x`
#: cannot tell "my keystroke reached the document" from "the delivered sentence
#: brought its own", so the answer it gives is the same whichever happened, and
#: a probe that cannot distinguish the two outcomes is not a probe. `z` appears
#: in neither the sentence nor the note, so a `z` anywhere is this rig's and
#: nobody else's.
KEY_Z = 6
PROBE_KEY = KEY_Z
PROBE_CHAR = "z"

#: **One distinct letter per probe offset**, so the map of *when* a keystroke is
#: stolen can be read off a single run instead of one run per offset. Every
#: letter here is absent from the fixture (*"Commit and push the fix."*) and from
#: anything Wispr's formatting pass is likely to add, so a letter found anywhere
#: is this rig's and its offset is known. US keycodes.
#:
#: Eleven of them, because the offsets now run on **both** sides of the stop
#: gesture — the Scratchpad is open from the hold, so the interesting window
#: starts during the recording, not after it.
PROBE_LETTERS = [("q", 12), ("z", 6), ("j", 38), ("k", 40), ("y", 16),
                 ("g", 5), ("l", 37), ("b", 11)]
#: `w`, `v` and `r` were dropped on 2026-09-14 when the short fixture became
#: *"What car do I have?"* — it carries a `w`, a `v` and an `r` of its own, and a
#: probe letter the sentence already contains cannot be attributed to a
#: keystroke. `evals/test_wispr_loop.py` asserts the disjointness, so a future
#: re-baseline that reintroduces a collision fails there rather than in a run
#: whose verdicts have quietly stopped meaning anything.


def _post_bare(keycode: int, down: bool):
    """Post a key with **no modifiers**, whatever the hardware thinks is held.

    `CGEventCreateKeyboardEvent` inherits the current HID flag state, and the
    moment this fires is the moment Wispr is holding ⌘ for its own paste.
    Measured 2026-09-13: a probe meant to type `x` went out as
    `key 7 flags 0x20100000` — ⌘X — and TextEdit dutifully *cut* instead of
    typing, so the character never appeared and the run read as "the Scratchpad
    stole the keyboard". It had not. `CGEventSetFlags(event, 0)` is the whole
    fix, and without it this probe answers a question nobody asked.
    """
    import Quartz

    event = Quartz.CGEventCreateKeyboardEvent(None, keycode, down)
    Quartz.CGEventSetFlags(event, 0)
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, event)


def tap_key(keycode: int = PROBE_KEY):
    """One key, down and up. **The question Victor cares about most.**

    A wrap that writes into Wispr's Scratchpad has to open that window, and a
    window that takes the keyboard while he is mid-sentence is worse than no
    wrap at all — he would be typing into a scratchpad he cannot see and did not
    ask for. Timings can be tuned later; a stolen keyboard cannot be lived with.
    So the scenarios type one character into the room and then ask where it
    went, which is the only way to answer that from outside.
    """
    _post_bare(keycode, True)
    time.sleep(0.02)
    _post_bare(keycode, False)
    return True


def accessibility_ok() -> bool:
    """Can this interpreter synthesise keystrokes at all?

    Worth asking up front: without the grant `CGEventPost` fails *silently*, so
    a whole overnight batch would play audio into a device nobody is recording
    and report a hundred timeouts as if Wispr had rejected the channel.
    """
    # **`AXIsProcessTrusted` is in ApplicationServices, not Quartz** — and the
    # pyobjc build on this Mac raises `AttributeError` for the Quartz spelling,
    # which the bare `except` below then reported as "not trusted". A preflight
    # that answers *no permission* when it means *wrong import* sends whoever
    # runs it into System Settings for nothing (2026-09-12).
    for module in ("ApplicationServices", "HIServices", "Quartz"):
        try:
            mod = __import__(module)
            fn = getattr(mod, "AXIsProcessTrusted", None)
            if fn is not None:
                return bool(fn())
        except Exception:
            continue
    return False


def paste_sink() -> str | None:
    """Front app that will receive the paste, or `None` if nothing does.

    Wispr types its result into the focused field. This does not *create* a sink
    — opening documents on somebody's desktop unasked is worse than stopping —
    it reports what is in front so the caller can refuse.
    """
    try:
        import subprocess

        out = subprocess.run(
            ["osascript", "-e", 'tell application "System Events" to '
             "get name of first application process whose frontmost is true"],
            capture_output=True, text=True, timeout=5)
        return (out.stdout or "").strip() or None
    except Exception:
        return None


# ── the answer ───────────────────────────────────────────────────────────────
@dataclass
class Heard:
    """One teacher label. `asr` is the one that matters.

    `formatted` has been through Wispr's LLM — punctuation, capitalisation, its
    custom dictionary. Training a speech model on it would teach the student to
    imitate a *text* model it does not have, and would score as errors every
    comma the student cannot know about. `asr_text` is what the recogniser
    actually heard, and it is the supervision.
    """

    id: str
    asr: str
    formatted: str
    seconds: float
    mic: str
    at: datetime
    #: Wispr's own reading of which language it heard (`detectedLanguage`), or "".
    #: It fills this in for about two rows in three; the caller decides what an
    #: empty one means, because "Wispr did not say" is not "Wispr said Romanian".
    language: str = ""
    #: Wispr's own timestamp on the row, verbatim. The caller needs it to ask *how
    #: long ago did this dictation start* — the one question that tells a label for
    #: the clip just played from a late-arriving label for the clip before it.
    row_ts: str = ""


def _open_wispr():
    if not os.path.exists(WISPR_DB):
        raise SystemExit("Wispr Flow database not found at %s" % WISPR_DB)
    uri = "file:%s?mode=ro" % WISPR_DB.replace("?", "%3f").replace("#", "%23")
    db = sqlite3.connect(uri, uri=True, timeout=30)
    db.row_factory = sqlite3.Row
    return db


def latest_id(db) -> str | None:
    row = db.execute(
        "SELECT transcriptEntityId FROM History ORDER BY timestamp DESC LIMIT 1"
    ).fetchone()
    return row[0] if row else None


def wait_for_new(since_id, timeout=RESULT_TIMEOUT_SEC, poll=0.5) -> Heard | None:
    """Poll for a History row that was not there before.

    Matching on "newest id changed" rather than on a timestamp window, because
    Wispr writes its timestamp in UTC with its own formatting and a clock
    comparison across that boundary is a bug waiting for a DST change. The
    connection is reopened each poll: Wispr holds the file in WAL mode and a
    long-lived read snapshot would never see the row it is waiting for.

    **A new id is not a transcript.** Wispr inserts the row when the key goes
    down and fills `asrText` in when the network round-trip comes back, so the
    id appears seconds before the words do. Returning on the id alone reads the
    placeholder and reports silence for a clip Wispr transcribed perfectly —
    measured 2026-09-19 on Wispr 1.6.897, three clips out of three. So the id
    only starts the second wait: for text in that same row.
    """
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        time.sleep(poll)
        fresh = _open_wispr()
        try:
            row = fresh.execute(
                "SELECT transcriptEntityId AS id, timestamp, duration, micDevice,"
                "       asrText, formattedText, detectedLanguage"
                "  FROM History ORDER BY timestamp DESC LIMIT 1"
            ).fetchone()
        finally:
            fresh.close()
        if row and row["id"] != since_id:
            return _wait_for_text(row["id"], deadline, poll)
    return None


def _wait_for_text(row_id, deadline, poll) -> Heard | None:
    """Wait for `asrText` to land in a row that already exists.

    Shares the caller's deadline rather than starting a fresh one: the budget is
    "how long this sample may take", and a row that never fills in has to fail
    the sample instead of extending it. An empty transcript at the deadline is
    still returned — an empty reading is a fact about the clip, and the caller
    decides what an empty label means.
    """
    last = None
    while True:
        fresh = _open_wispr()
        try:
            row = fresh.execute(
                "SELECT transcriptEntityId AS id, timestamp, duration, micDevice,"
                "       asrText, formattedText, detectedLanguage"
                "  FROM History WHERE transcriptEntityId = ?", (row_id,)
            ).fetchone()
        finally:
            fresh.close()
        if row:
            last = Heard(
                id=row["id"],
                asr=(row["asrText"] or "").strip(),
                formatted=(row["formattedText"] or "").strip(),
                seconds=float(row["duration"] or 0),
                mic=row["micDevice"] or "",
                at=datetime.now(timezone.utc),
                language=(row["detectedLanguage"] or "").strip().lower(),
                row_ts=(row["timestamp"] or ""),
            )
            if last.asr:
                return last
        if time.monotonic() >= deadline:
            return last
        time.sleep(poll)


def dictate(wav_path, device_index, keys=None, timeout=RESULT_TIMEOUT_SEC,
            abort=None, on_abort=None) -> Heard | None:
    """One sample, start to finish. Returns what Wispr heard, or `None`.

    With `abort`, a predicate polled during the playback, the clip can be given
    up halfway — `PlaybackAborted` then, and three things happen first, in this
    order and for separate reasons:

    1. **the audio stops**, so Wispr stops hearing a sentence nobody is saying;
    2. **⌃Escape**, Wispr's own *discard*, because the alternative is Wispr
       pasting half a sentence into whatever window the human just clicked
       into. Best effort: the chord is known to work while Wispr is recording
       and not to work once it has formatted, and the gap between those two is
       exactly where this lands. If it misses, the paste goes to the sink that
       was checked at the start, which is the same place it would have gone
       anyway;
    3. **the row is waited for and dropped**, briefly, because a row that
       arrives late is a row the *next* clip would be handed as its own.

    `on_abort` is called between (2) and (3) — after the keys are out and before
    the twelve seconds of waiting nobody is watching. The batch uses it to drop
    the 🔒 locks at once: they say *do not touch your own Mac* and the whole
    reason this path ran is that somebody already is.
    """
    audio, rate, _ = read_wav(wav_path)
    db = _open_wispr()
    try:
        before = latest_id(db)
    finally:
        db.close()
    with PushToTalk(keys):
        whole = play(audio, rate, device_index, abort=abort)
    if not whole:
        post_wispr_dismiss()
        if on_abort is not None:
            on_abort()
        wait_for_new(before, timeout=ABORT_ROW_TIMEOUT_SEC)
        raise PlaybackAborted(str(wav_path))
    return wait_for_new(before, timeout=timeout)


# ── the same thing again, through the relay instead of our own keystrokes ────
def transcribe(wav_path, device=None, timeout=None, verbose=False) -> dict:
    """**Feed Wispr a WAV and get back what it transcribed** — the relay's way.

    The newer half of this module, and the one a batch should move to. Beside
    `dictate()` and not instead of it, because they are not the same trade:

    | | `dictate()` | `transcribe()` |
    |---|---|---|
    | the chord | synthesised here, `CGEventPost` | posted by the **app**, `POST /test/wispr-handsfree` |
    | Accessibility | **this interpreter needs the grant** | not needed, and not asked for |
    | where the words land | whatever has focus — hence `paste_sink()` and an allow-list | the relay's own sink window, which it owns |
    | the answer | read out of `flow.sqlite` | read out of the sink, with the route named |
    | when it is done | polls for a new `History` row | the sink settling, or Wispr's own `dismissed`/`empty`/`no_audio` |

    So it needs the relay running, and in exchange it stops needing the grant,
    stops needing a harmless document to be in front, and stops reading Wispr's
    database for the words — which is the rule this repo keeps
    (`.claude/rules/dictation-source.md`, *Do not read Wispr Flow's database as
    a recogniser or a transcript fallback*). The row's **status** is still read,
    read-only, as the *is it done* signal; the words come from the sink.

    `helpers/teacher_label.py` is the caller this is for. It is **not** rewritten
    yet — `docs/loopback.md` says what the switch is.

    The implementation lives in `wispr_loop.py`, beside the `Relay`, the log
    parsing and the timing arithmetic it shares; imported lazily so this module
    stays importable with no relay and no harness on the path.
    """
    import sys as _sys

    _sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import wispr_loop

    return wispr_loop.transcribe(wav_path, device=device, timeout=timeout, verbose=verbose)


# ── a tiny CLI, for one file at a time ───────────────────────────────────────
def main(argv):
    import argparse

    ap = argparse.ArgumentParser(description="Feed one WAV to Wispr Flow.")
    ap.add_argument("wav", nargs="?", help="16-bit PCM WAV to dictate")
    ap.add_argument("--device", help="virtual output device (substring)")
    ap.add_argument("--list", action="store_true", help="show output devices and exit")
    ap.add_argument("--timeout", type=float, default=RESULT_TIMEOUT_SEC)
    args = ap.parse_args(argv)

    if args.list:
        for idx, name in output_devices():
            print("%3d  %s" % (idx, name))
        return 0
    if not args.wav:
        ap.error("a WAV is required unless --list")

    idx, name = resolve_device(args.device)
    print("device: %s (index %d)" % (name, idx))
    if not accessibility_ok():
        print(
            "Accessibility is NOT granted to this interpreter — CGEventPost will do\n"
            "nothing and Wispr will never start recording. Grant it in System\n"
            "Settings → Privacy & Security → Accessibility for the terminal running this.",
            file=sys.stderr,
        )
        return 2
    print("front app (will receive the paste): %s" % (paste_sink() or "?"))

    started = time.monotonic()
    heard = dictate(args.wav, idx, timeout=args.timeout)
    took = time.monotonic() - started
    if heard is None:
        print("no transcript after %.0fs — Wispr heard nothing" % took)
        return 1
    print("asr       : %s" % heard.asr)
    print("formatted : %s" % heard.formatted)
    print("mic       : %s   (%.1fs, took %.1fs)" % (heard.mic, heard.seconds, took))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
