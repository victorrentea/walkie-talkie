#!/usr/bin/env python3
"""One Wispr catch-up run inside the `wt-lab` guest; prints one JSON line.

    python3 guest.py b <clip.wav>              baseline: clip straight into From Walkie (Wispr's mic), ptt held
    python3 guest.py p <clip.wav> <lag_s>      pacing alone: what BridgePacer would hand over after <lag_s>,
                                               rendered offline, played as in b
    python3 guest.py r <clip.wav> <rate>       Wispr's tolerance: the whole clip at <rate> (time-pitch, no pause
                                               cut) straight into Wispr's mic — no relay needed ($WT_EVAL_WISPR_DEV,
                                               default BlackHole 2ch, the guest's own Wispr microphone)
    python3 guest.py l <clip.wav> warm|lateN   the real app: relay gesture, clip into BlackHole 2ch (the
                                               relay's mic), the bridge into From Walkie (Wispr's); lateN =
                                               the start chord held back N s, so Wispr listens N s late

Runs under the guest's /usr/bin/python3 (3.9) via `tart exec` — the only way to hear audio there.
Driven from the host by `run.py`. Python 3.9: no `X | Y` annotations outside strings.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request
import wave

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "helpers"))
import wispr_loopback as wl  # noqa: E402

LOG = os.path.expanduser("~/.walkie-talkie/relay.log")
WISPR_DEV = "From Walkie"   # what Wispr listens to, as on his Mac (Auto-detect ranks it first)
RELAY_MIC = "BlackHole 2ch"   # the relay's "microphone": a 16-channel device reads as zeros in the relay
ROW_TIMEOUT = 60.0


# ── the relay's loopback port ────────────────────────────────────────────────
def _token_headers():
    """X-Walkie-Token (2026-11-25). Inline, not `helpers/walkie_token.py`: this file is
    copied into the guest alone. Read at every call — a relaunch writes a new one."""
    try:
        with open(os.path.expanduser(os.environ.get("WALKIE_HOME") or "~/.walkie-talkie") + "/test-token") as f:
            return {"X-Walkie-Token": f.read().strip()}
    except OSError:
        return {}


def api(path, body=None, timeout=10):
    for port in (8917, 8918, 8919):
        try:
            data = None if body is None else json.dumps(body).encode()
            req = urllib.request.Request("http://127.0.0.1:%d/%s" % (port, path), data=data,
                                         method="POST" if data is not None else "GET",
                                         headers=_token_headers())
            with urllib.request.urlopen(req, timeout=timeout) as r:
                raw = r.read()
            try:
                return json.loads(raw)
            except ValueError:
                return {"raw": raw.decode(errors="replace")}
        except OSError:
            continue
    raise RuntimeError("relay not answering on 8917-8919")


def wait(pred, timeout, step=0.05):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        v = pred()
        if v:
            return v
        time.sleep(step)
    return None


def wispr_pid():
    out = subprocess.run(["pgrep", "-x", "Wispr Flow"], capture_output=True, text=True).stdout.split()
    return int(out[0]) if out else None


def heard_dict(h):
    if h is None:
        return {"row": None, "asr": "", "text": "", "seconds": 0.0, "mic": ""}
    return {"row": h.id, "asr": h.asr, "text": h.formatted or h.asr, "seconds": h.seconds, "mic": h.mic}


def latest():
    db = wl._open_wispr()
    try:
        return wl.latest_id(db)
    finally:
        db.close()


def settle():
    """No dictation left open from a run before (the gesture is a toggle: one lost stop inverts
    every run after it — seen 2026-09-30 after a crash, a 237 s take whose bridge wrote into
    From Walkie under the baselines)."""
    st = api("test/state")
    if st.get("listening") or st.get("dictationStartedAt"):
        api("test/cancel", {})
    wait(lambda: not api("test/state").get("listening"), 10, 0.2)
    wait(lambda: not api("test/state").get("busy"), 20, 0.5)


# ── b and p: straight into Wispr's device ─────────────────────────────────────
def straight(path):
    settle()
    # the bridge off: its engine is a second writer on From Walkie, and BlackHole's shared statics
    # let one writer wipe the other's ring (the lab's Finding A) — the baseline came back "So"
    api("test/bridge", {"on": False})
    idx, name = wl.resolve_device(WISPR_DEV)
    t0 = time.monotonic()
    h = wl.dictate(path, idx, timeout=ROW_TIMEOUT)
    return dict(heard_dict(h), device=name, wall=round(time.monotonic() - t0, 2))


def pace(path, lag, rate=1.1, synced=0.2, lead_pad=0.3, kept_gap=0.25, chunk=0.085):
    """BridgePacer, offline: trimStart, then admit/rate chunk by chunk until caught up."""
    audio, sr, _ = wl.read_wav(path)
    x = audio if audio.ndim == 1 else audio.mean(axis=1)
    n = int(sr * chunk)
    chunks = [x[i:i + n] for i in range(0, len(x), n)]
    # the meter's idea of voiced, near enough: 9 dB over a 10th-percentile floor, absolute floor underneath
    rms = np.array([np.sqrt(np.mean(c.astype(np.float64) ** 2)) if len(c) else 0 for c in chunks])
    floor = max(np.percentile(rms, 10), 1e-4)
    voiced = rms > max(floor * 2.8, 180 / 32768.0)
    # trimStart
    first = int(np.argmax(voiced)) if voiced.any() else len(chunks)
    start, kept = first, 0.0
    while start > 0 and kept < lead_pad:
        start -= 1
        kept += len(chunks[start]) / sr
    cut_lead = sum(len(c) for c in chunks[:start]) / sr
    lag = max(0.0, lag - cut_lead)
    fast, slow, silent_run, dropped = [], [], 0.0, 0.0
    for c, v in zip(chunks[start:], voiced[start:]):
        s = len(c) / sr
        if lag > synced:
            if v:
                silent_run = 0.0
            else:
                silent_run += s
                if silent_run > kept_gap:
                    dropped += s
                    lag -= s
                    continue
            fast.append(c)
            lag -= s * (1 - 1 / rate)
        else:
            slow.append(c)
    fast_a = np.concatenate(fast) if fast else np.zeros(0)
    slow_a = np.concatenate(slow) if slow else np.zeros(0)
    if len(fast_a):
        fast_a = atempo(fast_a, sr, rate)
    out = np.concatenate([fast_a, slow_a]).astype(np.float32)
    fd, tmp = tempfile.mkstemp(suffix=".wav")
    os.close(fd)
    write_wav(tmp, out, sr)
    return tmp, {"cut_lead": round(cut_lead, 2), "dropped": round(dropped, 2),
                 "fast_s": round(sum(len(c) for c in fast) / sr, 2),
                 "caught_up": lag <= synced, "out_s": round(len(out) / sr, 2)}


def write_wav(path, a, sr):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes((np.clip(a, -1, 1) * 32767).astype(np.int16).tobytes())


def atempo(a, sr, rate):
    fd, src = tempfile.mkstemp(suffix=".wav")
    os.close(fd)
    dst = src.replace(".wav", "-f.wav")
    write_wav(src, a, sr)
    subprocess.run(["/opt/homebrew/bin/ffmpeg", "-loglevel", "error", "-y", "-i", src,
                    "-filter:a", "atempo=%s" % rate, dst], check=True)
    b, _, _ = wl.read_wav(dst)
    os.unlink(src)
    os.unlink(dst)
    return b if b.ndim == 1 else b.mean(axis=1)


# ── l: through the relay and its bridge ───────────────────────────────────────
def log_tail(offset):
    with open(LOG, "rb") as f:
        f.seek(offset)
        return f.read().decode(errors="replace")


def relay_run(path, mode):
    settle()
    api("test/bridge", {"on": True})
    api("test/mic", {"device": RELAY_MIC})
    # warm: Wispr as it is (~0.3 s late). lateN: its start chord N s after the gesture. (A Wispr that is not running is not a late start: the relay
    # takes that sentence to the local model at once, by design.)
    if not wispr_pid():
        subprocess.run(["open", "-g", "-b", "com.electron.wispr-flow"])
        wait(wispr_pid, 20)
        time.sleep(15)  # younger than 12 s reads as still starting
    late = float(mode[4:]) if mode.startswith("late") else 0.0
    if late:
        # the gesture's start chord is swallowed; the same chord goes out `late` s later, so Wispr
        # opens its input that much after he started talking. (SIGSTOP on Wispr was tried first: a
        # frozen CoreAudio client stalled the guest's audio, a 10 s clip took 16 s to play.)
        api("test/wispr-chord", {"mute": True, "seconds": late + 30})
    before = latest()
    offset = os.path.getsize(LOG)
    audio, rate, _ = wl.read_wav(path)
    idx, _ = wl.resolve_device(RELAY_MIC)
    t0 = time.monotonic()
    api("test/gesture", {"name": "forward-right", "direct": True})
    if late:
        chord = threading.Timer(late, lambda: api("test/wispr-chord", {"mute": False, "post": "on"}))
        chord.start()
    # he talks 0.2 s after the gesture. Not polled: `/test/state` answers in seconds while Wispr is
    # frozen, and `isRecording` waits for Wispr — both put the clip behind the lag being tested.
    time.sleep(0.2)
    opened = True
    t_open = time.monotonic() - t0
    wl.LEAD_SEC = 0.0  # the helper's 1.3 s lead-in would be silence the pacer cuts, hiding the lag
    wl.play(audio, rate, idx)
    t_played = time.monotonic() - t0
    time.sleep(0.4)
    at_stop = api("test/state")
    api("test/gesture", {"name": "forward-right", "direct": True})
    t_stop = time.monotonic() - t0
    if not wait(lambda: not api("test/state").get("listening"), 5, 0.2):
        api("test/cancel", {})  # the stop did not take; say so in the row rather than poison the next run
        stop_missed = True
    else:
        stop_missed = False
    h = wl.wait_for_new(before, timeout=ROW_TIMEOUT)
    wait(lambda: not api("test/state").get("busy"), 30, 0.5)
    after = api("test/state")
    lines = [l for l in log_tail(offset).splitlines()
             if any(k in l for k in ("🔀", "📮", "wispr history", "🎙️ Wispr", "bridge", "local", "DEAF"))]
    wlive = at_stop.get("wisprLive") or {}
    return dict(heard_dict(h), opened=bool(opened), t_open=round(t_open, 2), t_played=round(t_played, 2),
                t_stop=round(t_stop, 2), bridge_at_stop=wlive.get("bridge"),
                delivery=(after.get("lastDelivery") or {}).get("via"), stop_missed=stop_missed, log=lines[-25:])


def main(argv):
    mode, path = argv[1], argv[2]
    if mode == "b":
        res = straight(path)
    elif mode == "p":
        lag = float(argv[3])
        tmp, info = pace(path, lag)
        try:
            res = dict(straight(tmp), pace=info, lag=lag)
        finally:
            os.unlink(tmp)
    elif mode == "r":
        rate = float(argv[3])
        audio, sr, _ = wl.read_wav(path)
        fast = atempo(audio, sr, rate) if rate != 1.0 else audio
        fd, tmp = tempfile.mkstemp(suffix=".wav")
        os.close(fd)
        write_wav(tmp, fast, sr)
        try:
            idx, name = wl.resolve_device(os.environ.get("WT_EVAL_WISPR_DEV", "BlackHole 2ch"))
            t0 = time.monotonic()
            h = wl.dictate(tmp, idx, timeout=ROW_TIMEOUT)
            res = dict(heard_dict(h), device=name, rate=rate, out_s=round(len(fast) / sr, 2),
                       wall=round(time.monotonic() - t0, 2))
        finally:
            os.unlink(tmp)
    elif mode == "l":
        res = relay_run(path, argv[3])
    else:
        raise SystemExit(__doc__)
    print(json.dumps(res, ensure_ascii=False))


if __name__ == "__main__":
    main(sys.argv)
