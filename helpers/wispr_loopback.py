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
# Preferred virtual input devices, most specific first. The `🎓` one does not
# exist yet — it is what the setup above creates — and naming it here is how the
# rig picks it up the moment it does.
DEVICE_PREFERENCE = ["🎓 TO Wispr", "TO Wispr", "🎙️TO Zoom", "🔊OS Output"]

SAMPLE_RATE = 16000
# Silence played after the file, so Wispr's endpointing sees an ending rather
# than a key release in the middle of a word.
TAIL_SEC = float(os.environ.get("WISPR_TAIL_SECONDS", "0.5"))
# Silence played *before* it, for the opposite reason: Wispr drops the first
# fraction of a second while its recorder spins up, and the corpus WAVs start on
# a word.
LEAD_SEC = float(os.environ.get("WISPR_LEAD_SECONDS", "0.6"))
# How long to wait for a transcript after the key comes up. Wispr is a network
# round-trip plus an LLM formatting pass; measured at 1.5–4 s, and a long clip
# is slower.
RESULT_TIMEOUT_SEC = float(os.environ.get("WISPR_RESULT_TIMEOUT", "45"))


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


def play(audio, rate, device_index, gain=1.0):
    """Play through to the end, blocking. Real time, by construction."""
    import sounddevice as sd

    lead = np.zeros(int(rate * LEAD_SEC), dtype=np.float32)
    tail = np.zeros(int(rate * TAIL_SEC), dtype=np.float32)
    signal = np.clip(np.concatenate([lead, audio * gain, tail]), -1.0, 1.0)
    sd.play(signal, samplerate=rate, device=device_index, blocking=True)


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


def accessibility_ok() -> bool:
    """Can this interpreter synthesise keystrokes at all?

    Worth asking up front: without the grant `CGEventPost` fails *silently*, so
    a whole overnight batch would play audio into a device nobody is recording
    and report a hundred timeouts as if Wispr had rejected the channel.
    """
    try:
        import Quartz

        return bool(Quartz.AXIsProcessTrusted())
    except Exception:
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
    """
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        time.sleep(poll)
        fresh = _open_wispr()
        try:
            row = fresh.execute(
                "SELECT transcriptEntityId AS id, timestamp, duration, micDevice,"
                "       asrText, formattedText"
                "  FROM History ORDER BY timestamp DESC LIMIT 1"
            ).fetchone()
        finally:
            fresh.close()
        if row and row["id"] != since_id:
            return Heard(
                id=row["id"],
                asr=(row["asrText"] or "").strip(),
                formatted=(row["formattedText"] or "").strip(),
                seconds=float(row["duration"] or 0),
                mic=row["micDevice"] or "",
                at=datetime.now(timezone.utc),
            )
    return None


def dictate(wav_path, device_index, keys=None, timeout=RESULT_TIMEOUT_SEC) -> Heard | None:
    """One sample, start to finish. Returns what Wispr heard, or `None`."""
    audio, rate, _ = read_wav(wav_path)
    db = _open_wispr()
    try:
        before = latest_id(db)
    finally:
        db.close()
    with PushToTalk(keys):
        play(audio, rate, device_index)
    return wait_for_new(before, timeout=timeout)


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
