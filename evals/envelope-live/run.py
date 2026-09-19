#!/usr/bin/env python3
"""A whole dictation, spoken out loud, with the gestures made while it speaks —
and the envelope it really produced.

Victor, 2026-09-19: *"încearcă să sintetizezi tu niște text-to-voice audio și
să-l suprapui pe niște gesturi. Preferabil să le faci cât mai realist."*

So this is the real path end to end, nothing faked below the recogniser: macOS's
Romanian voice speaks the sentence **through the speakers**, the relay's own
microphone hears it, ElevenLabs Scribe transcribes it and returns word timings,
and the gestures are posted at chosen seconds *while the sentence is being
spoken*. What comes back is the envelope as an agent would receive it, with the
tokens standing where the press fell.

    ./run.py                 # every scenario
    ./run.py area            # one
    ./run.py --keep          # leave the clips in /tmp for a listen

**It makes noise and it posts chords**, so it runs under `hands-off` and it
takes the relay for the length of a sentence. It binds `ttys999` — a tty nothing
is listening on — exactly as `evals/test_envelope.py` does: the outbox line is
written at delivery and delivery to a dead tty reaches no window, which is the
only way to get a real envelope out of a relay that must not type into anything.

ElevenLabs' own text-to-speech would be the more realistic voice and is **not
reachable**: the key on this Mac is scoped to speech-to-text
(`missing_permissions: text_to_speech`), so `say -v Ioana` it is. It is robotic
and it is Romanian, which is what the recogniser needs.
"""
import argparse, json, pathlib, subprocess, sys, time, urllib.request

BASE = "http://127.0.0.1:8917"
NOWHERE = "ttys999"
OUTBOX = pathlib.Path.home() / ".walkie-talkie" / "outbox.jsonl"
VOICE = "Ioana"
# Loud enough for the built-in microphone across a desk, quiet enough not to
# startle a room. Restored to whatever it was at the end.
VOLUME = 45


def post(path, obj=None):
    body = json.dumps(obj or {}).encode()
    req = urllib.request.Request(BASE + path, data=body, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return json.loads(r.read() or b"{}")
    except Exception as e:
        return {"error": str(e)}


def last_line():
    lines = OUTBOX.read_text().splitlines()
    return json.loads(lines[-1]) if lines else {}


def volume(level=None):
    if level is None:
        out = subprocess.run(["osascript", "-e", "get volume settings"],
                             capture_output=True, text=True).stdout
        return int(out.split("output volume:")[1].split(",")[0])
    subprocess.run(["osascript", "-e", f"set volume output volume {level}"])


def clip(text, path):
    """macOS's Romanian voice, with `[[slnc N]]` where the gestures go."""
    subprocess.run(["say", "-v", VOICE, "-o", str(path), text], check=True)
    out = subprocess.run(["afinfo", str(path)], capture_output=True, text=True).stdout
    for line in out.splitlines():
        if "estimated duration" in line:
            return float(line.split(":")[1].split()[0])
    return 0.0


# Each scenario: the words (with `[[slnc ms]]` pauses), and what to do at which
# second of the recording. The gestures are aimed at the pauses on purpose —
# that is where he presses, and it is where a token reads best.
SCENARIOS = {
    "area": {
        "why": "the ordinary one — he shows the screen and points at a region",
        "say": "Uite ce am pe ecran acum. [[slnc 900]] "
               "În zona asta [[slnc 1200]] vreau să apară un buton nou, "
               "[[slnc 600]] la fel ca celelalte.",
        "do": [(3.2, ("area", {"x": 380, "y": 500, "w": 700, "h": 220}))],
    },
    "shot-and-selection": {
        "why": "a picture mid-sentence and a highlight he makes while talking",
        "say": "Uite aici. [[slnc 1000]] Linia asta e problema, [[slnc 1200]] "
               "hai să o rescriem mai simplu.",
        "do": [(1.4, ("shutter", None)),
               (3.6, ("selection", {"text": "public Order placeOrder(Cart cart) {"}))],
    },
    "two-shots-and-element": {
        "why": "two frames and an element picked in Chrome",
        "say": "Butonul ăsta [[slnc 1000]] și cel de aici [[slnc 1000]] "
               "trebuie să arate la fel. [[slnc 500]] Schimbă-le pe amândouă.",
        "do": [(1.3, ("shutter", None)),
               (2.9, ("shutter", None)),
               (4.3, ("element", {"path": "div.toolbar > button.primary", "tag": "button",
                                  "text": "Salvează", "title": "Orders",
                                  "url": "https://petclinic.victorrentea.ro/orders"}))],
    },
}

ACTIONS = {
    "shutter": lambda arg: post("/test/gesture", {"name": "back-click"}),
    "area": lambda arg: post("/test/area", arg),
    "selection": lambda arg: post("/test/selection", arg),
    "element": lambda arg: post("/pick", arg),
}


def run(name, keep=False):
    scene = SCENARIOS[name]
    path = pathlib.Path(f"/tmp/wt-live-{name}.aiff")
    seconds = clip(scene["say"], path)
    before = len(OUTBOX.read_text().splitlines())

    post("/bind", {"tty": NOWHERE})
    post("/test/gesture", {"name": "forward-right"})     # a dictation at the bound tty
    time.sleep(1.2)                                       # the microphone opens
    t0 = time.monotonic()
    player = subprocess.Popen(["afplay", str(path)])
    for at, (action, arg) in scene["do"]:
        while time.monotonic() - t0 < at:
            time.sleep(0.05)
        ACTIONS[action](arg)
    player.wait()
    time.sleep(0.5)
    post("/test/gesture", {"name": "forward-click"})      # the stop
    if not keep:
        path.unlink(missing_ok=True)

    for _ in range(30):
        time.sleep(1)
        if len(OUTBOX.read_text().splitlines()) > before:
            return last_line()
        post("/bind", {"tty": NOWHERE})
    return {"error": "the dictation never reached the outbox"}


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("scenarios", nargs="*", default=list(SCENARIOS))
    ap.add_argument("--keep", action="store_true")
    a = ap.parse_args()

    was = volume()
    volume(VOLUME)
    try:
        for name in (a.scenarios or list(SCENARIOS)):
            print(f"\n═══════════ {name} — {SCENARIOS[name]['why']} ═══════════")
            entry = run(name, keep=a.keep)
            print(entry.get("line") or entry.get("error") or entry)
    finally:
        volume(was)
        post("/unbind")
