#!/usr/bin/env python3
"""A dry run of the combined feature in the `wt-lab` guest (2026-09-30): markers spliced into the
bridge at his next pause, the bridge catching up after each, `ShotMarker.resolveStrict` placing them.

    python3 dryrun.py <clip.wav> <press_s>[,<press_s>…] [late_s]     (guest, via tart exec)

`late_s`: Wispr opens its input that much after the gesture — the start chord is muted and posted
late (`/test/wispr-chord`, the catch-up eval's trick), so the bridge starts behind and markers pile
on top of that lag.

The real app end to end: relay gesture (`forward-right`, direct) → the clip into BlackHole 2ch (the
relay's "microphone", `/test/mic`) → the bridge into From Walkie (Wispr's) → a shutter press at each
`press_s` via `/test/area` (reserves the picture, speaks the marker) → the stop gesture → the
envelope in the bound tab (`cat >> /tmp/dry-out.txt`). Prints one JSON line: the envelope, Wispr's
row (asr and formatted), and the relay's 📣 / 🔀 lines for this run. Not an eval — a few runs to see
the idea hold before Victor tries it live.
"""
from __future__ import annotations

import json
import os
import sys
import threading
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "helpers"))
import walkie_token  # noqa: E402 — X-Walkie-Token on every call to the relay (2026-11-25)
walkie_token.install()
import wispr_loopback as wl  # noqa: E402

LOG = os.path.expanduser("~/.walkie-talkie/relay.log")
OUT = "/tmp/dry-out.txt"


def api(path, body=None, timeout=15):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request("http://127.0.0.1:8917/" + path, data=data,
                                 method="POST" if data is not None else "GET")
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read())


def main(argv):
    clip, presses = argv[1], [float(x) for x in argv[2].split(",") if x]
    late = float(argv[3]) if len(argv) > 3 else 0.0
    st = api("test/state")
    if st.get("listening"):
        api("test/cancel", {})
        time.sleep(1)
    api("test/bridge", {"on": True})
    api("test/mic", {"device": "BlackHole 2ch"})
    before = wl.latest_id(wl._open_wispr())
    log_at = os.path.getsize(LOG)
    out_at = os.path.getsize(OUT) if os.path.exists(OUT) else 0
    audio, rate, _ = wl.read_wav(clip)
    idx, _ = wl.resolve_device("BlackHole 2ch")
    if late:
        api("test/wispr-chord", {"mute": True, "seconds": late + 60})
    t0 = time.monotonic()
    api("test/gesture", {"name": "forward-right", "direct": True})
    if late:
        threading.Timer(late, lambda: api("test/wispr-chord", {"mute": False, "post": "on"})).start()
    time.sleep(0.2)
    pressed = []

    def press(at):
        time.sleep(max(0, at - (time.monotonic() - t0)))
        r = api("test/area", {"x": 200, "y": 200, "w": 400, "h": 300})
        pressed.append({"at": round(time.monotonic() - t0, 2), "frame": os.path.basename(r.get("frame", ""))})

    threads = [threading.Thread(target=press, args=(p,)) for p in presses]
    for t in threads:
        t.start()
    wl.LEAD_SEC = 0.0
    wl.play(audio, rate, idx)
    for t in threads:
        t.join()
    time.sleep(0.4)
    api("test/gesture", {"name": "forward-right", "direct": True})
    t_stop = time.monotonic() - t0
    h = wl.wait_for_new(before, timeout=60)
    end = time.monotonic() + 40
    while time.monotonic() < end and api("test/state").get("busy"):
        time.sleep(0.5)
    time.sleep(1.5)
    with open(LOG, "rb") as f:
        f.seek(log_at)
        lines = [l for l in f.read().decode(errors="replace").splitlines()
                 if any(k in l for k in ("📣", "🔀", "✂️ marker", "markers", "wispr history"))]
    envelope = ""
    if os.path.exists(OUT):
        with open(OUT, "rb") as f:
            f.seek(out_at)
            envelope = f.read().decode(errors="replace")
    print(json.dumps({"clip": os.path.basename(clip), "presses": pressed, "stop_at": round(t_stop, 2), "late": late,
                      "asr": h.asr if h else "", "formatted": h.formatted if h else "",
                      "mic": h.mic if h else "", "envelope": envelope, "log": lines[-30:]},
                     ensure_ascii=False))


if __name__ == "__main__":
    main(sys.argv)
