#!/usr/bin/env python3
"""One marker clip into the `wt-lab` guest's Wispr Flow; prints one JSON line.

    python3 guest.py <clip.wav> [device]     device: what Wispr records from (default BlackHole 2ch)

The clip goes straight into Wispr's microphone device with its push-to-talk held (`wispr_loopback.
dictate`: 1.3 s lead, 0.5 s tail, peak 0.5), and the new `History` row is read back. Runs under the
guest's /usr/bin/python3 (3.9) via `tart exec` — the only chain there with a microphone grant.
The relay's bridge is switched off first when a relay answers: it would be a second writer on the
device (the lab's Finding A). Driven from the host by `run.py drive`.
"""
from __future__ import annotations

import json
import os
import sys
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "helpers"))
import wispr_loopback as wl  # noqa: E402
import walkie_token  # noqa: E402 — X-Walkie-Token on every call to the relay (2026-11-25)
walkie_token.install()


def bridge_off():
    for port in (8917, 8918, 8919):
        try:
            req = urllib.request.Request("http://127.0.0.1:%d/test/bridge" % port,
                                         data=json.dumps({"on": False}).encode(), method="POST")
            urllib.request.urlopen(req, timeout=3).read()
            return True
        except OSError:
            continue
    return False


def main(argv):
    path = argv[1]
    dev = argv[2] if len(argv) > 2 else os.environ.get("WISPR_DEV", "BlackHole 2ch")
    relay = bridge_off()
    idx, name = wl.resolve_device(dev)
    t0 = time.monotonic()
    h = wl.dictate(path, idx, timeout=60)
    db = wl._open_wispr()
    try:
        extra = db.execute("SELECT asrText, formattedText, pastedText, status, numDictionaryReplacements "
                           "FROM History WHERE transcriptEntityId = ?", (h.id,)).fetchone() if h else None
    finally:
        db.close()
    print(json.dumps({
        "row": h.id if h else None, "asr": h.asr if h else "", "text": (h.formatted or h.asr) if h else "",
        "pasted": (extra["pastedText"] if extra else None), "status": (extra["status"] if extra else None),
        "dict_repl": (extra["numDictionaryReplacements"] if extra else None),
        "seconds": h.seconds if h else 0.0, "mic": h.mic if h else "", "lang_det": h.language if h else "",
        "device": name, "relay": relay, "wall": round(time.monotonic() - t0, 2)}, ensure_ascii=False))


if __name__ == "__main__":
    main(sys.argv)
