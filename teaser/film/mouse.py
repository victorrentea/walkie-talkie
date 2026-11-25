#!/usr/bin/python3
"""Synthetic pointer + keys INSIDE the lab guest (never on the host). Runs with the guest's /usr/bin/python3 (pyobjc).

    mouse.py '[["move",640,360,0.6],["down","middle"],["drag",900,500,0.8,"middle"],["up","middle"]]'

Ops (global points, origin top-left): move x y [seconds] [bow] · drag x y [seconds] [button] [bow] · down/up/click [button]
· at <s> (wait until T0 + s; T0 = argv[2], a wall-clock epoch — a whole take's choreography in ONE process, no per-step
launch lag) · waitstate <expr on d> [timeout] (poll GET /test/state) · mark <name> (appends "<name> <epoch>" to /tmp/film-marks) · api <path> [json] (POST to Walkie's control port)
· key <keycode> [flag…] · keydown/keyup <keycode> [flag…] · flags [flag…] (bare modifier state) · sleep s · type "text" · pbimage <file>
Buttons: left right middle. Flags: shift cmd ctrl alt.
"""
import json, math, random, sys, time
import Quartz as Q

BTN = {"left": (Q.kCGMouseButtonLeft, Q.kCGEventLeftMouseDown, Q.kCGEventLeftMouseUp, Q.kCGEventLeftMouseDragged),
       "right": (Q.kCGMouseButtonRight, Q.kCGEventRightMouseDown, Q.kCGEventRightMouseUp, Q.kCGEventRightMouseDragged),
       "middle": (Q.kCGMouseButtonCenter, Q.kCGEventOtherMouseDown, Q.kCGEventOtherMouseUp, Q.kCGEventOtherMouseDragged)}
FLAG = {"shift": Q.kCGEventFlagMaskShift, "cmd": Q.kCGEventFlagMaskCommand, "ctrl": Q.kCGEventFlagMaskControl,
        "alt": Q.kCGEventFlagMaskAlternate}
MODKEY = {"shift": 56, "cmd": 55, "ctrl": 59, "alt": 58}
src = Q.CGEventSourceCreate(Q.kCGEventSourceStateHIDSystemState)
held = 0


def pos():
    p = Q.CGEventGetLocation(Q.CGEventCreate(None)); return p.x, p.y


def post(kind, x, y, button):
    e = Q.CGEventCreateMouseEvent(src, kind, (x, y), button)
    Q.CGEventSetFlags(e, held)
    Q.CGEventPost(Q.kCGHIDEventTap, e)


def profile(n):
    """Where along the path the hand is at each of n steps: a reach, not a ramp — it leaves fast (speed peaks a
    fifth of the way in) and spends the second half slowing into the target."""
    v = [((i + 0.5) / n) ** 0.55 * (1 - (i + 0.5) / n) ** 2.3 for i in range(n)]
    total = sum(v); out, acc = [], 0.0
    for x in v: acc += x; out.append(acc / total)
    return out


def glide(x, y, seconds, kind, button, bow=None):
    """A human path to (x, y): a slightly bowed curve (the arc of a wrist, always the same side for a direction),
    two slow wobbles that die out before the target, ease-out timing. `bow` = the arc's height as a share of the
    distance (default 0.07–0.11; 0 for a ruler-straight drag, e.g. along a line of text)."""
    x0, y0 = pos(); dx, dy = x - x0, y - y0; dist = math.hypot(dx, dy)
    if seconds <= 0 or dist < 1.5: post(kind, x, y, button); return
    n = max(3, int(seconds * 90))
    px, py = -dy / dist, dx / dist                               # the normal
    side = -1 if dx >= 0 else 1                                  # concave: the arc bulges up on the way right, down on the way back
    h = min(dist * (random.uniform(0.07, 0.11) if bow is None else bow), 46) * side
    cx, cy = x0 + dx * 0.42 + px * h * 2, y0 + dy * 0.42 + py * h * 2
    amp = 0 if bow == 0 else min(2.2, dist * 0.012)
    a1, a2 = random.uniform(-1, 1) * amp, random.uniform(-1, 1) * amp * 0.6
    f1, f2, p1, p2 = random.uniform(1.1, 1.9), random.uniform(2.6, 4.2), random.uniform(0, 6.28), random.uniform(0, 6.28)
    start = time.time()
    for i, t in enumerate(profile(n)):
        bx = (1 - t) ** 2 * x0 + 2 * (1 - t) * t * cx + t * t * x
        by = (1 - t) ** 2 * y0 + 2 * (1 - t) * t * cy + t * t * y
        w = (a1 * math.sin(6.283 * f1 * t + p1) + a2 * math.sin(6.283 * f2 * t + p2)) * math.sin(math.pi * t) * (1 - t) ** 0.5
        post(kind, bx + px * w, by + py * w, button)
        lag = start + (i + 1) * seconds / n - time.time()
        if lag > 0: time.sleep(lag)
    post(kind, x, y, button)


def mask(names): 
    m = 0
    for n in names: m |= FLAG[n]
    return m


def key(code, names, down):
    e = Q.CGEventCreateKeyboardEvent(src, code, down)
    Q.CGEventSetFlags(e, mask(names) | held)
    Q.CGEventPost(Q.kCGHIDEventTap, e)


T0 = float(sys.argv[2]) if len(sys.argv) > 2 else time.time()


def _token():
    """X-Walkie-Token (2026-11-25), the guest's own — this file is pushed into the guest alone."""
    import os
    try: return {"X-Walkie-Token": open(os.path.expanduser("~/.walkie-talkie/test-token")).read().strip()}
    except OSError: return {}


def api(path, body=None):
    import urllib.request
    try: urllib.request.urlopen(urllib.request.Request("http://127.0.0.1:8917/" + path, data=json.dumps(body or {}).encode(),
                                                       headers=_token()), timeout=20).read()
    except Exception as e: print("api", path, e)


for op in json.loads(sys.argv[1] if len(sys.argv) > 1 else sys.stdin.read()):
    name, a = op[0], op[1:]
    if name == "move": glide(a[0], a[1], a[2] if len(a) > 2 else 0, Q.kCGEventMouseMoved, Q.kCGMouseButtonLeft, a[3] if len(a) > 3 else None)
    elif name == "drag":
        b = BTN[a[3] if len(a) > 3 else "left"]; glide(a[0], a[1], a[2] if len(a) > 2 else 0.5, b[3], b[0], a[4] if len(a) > 4 else None)
    elif name in ("down", "up", "click"):
        b = BTN[a[0] if a else "left"]; x, y = pos()
        if name != "up": post(b[1], x, y, b[0])
        if name == "click": time.sleep(0.06)
        if name != "down": post(b[2], x, y, b[0])
    elif name == "key": key(a[0], a[1:], True); time.sleep(0.04); key(a[0], a[1:], False)
    elif name == "keydown": key(a[0], a[1:], True)
    elif name == "keyup": key(a[0], a[1:], False)
    elif name == "flags":                                        # press / release bare modifiers, as a hand would
        new = mask(a)
        for n, bit in FLAG.items():
            if (new ^ held) & bit:
                e = Q.CGEventCreateKeyboardEvent(src, MODKEY[n], bool(new & bit))
                Q.CGEventSetType(e, Q.kCGEventFlagsChanged); Q.CGEventSetFlags(e, new if new & bit else new)
                held = (held | bit) if new & bit else (held & ~bit)
                Q.CGEventSetFlags(e, held); Q.CGEventPost(Q.kCGHIDEventTap, e)
    elif name == "type":
        for ch in a[0]:
            for down in (True, False):
                e = Q.CGEventCreateKeyboardEvent(src, 0, down); Q.CGEventKeyboardSetUnicodeString(e, len(ch), ch)
                Q.CGEventPost(Q.kCGHIDEventTap, e)
            time.sleep(a[1] if len(a) > 1 else 0.03)
    elif name == "pbimage":                                      # put a picture file on the clipboard, as ⌘C on an image would
        import AppKit
        pb = AppKit.NSPasteboard.generalPasteboard(); pb.clearContents()
        pb.writeObjects_([AppKit.NSImage.alloc().initWithContentsOfFile_(a[0])])
    elif name == "sleep": time.sleep(a[0])
    elif name == "at": time.sleep(max(0, T0 + a[0] - time.time()))
    elif name == "mark": open("/tmp/film-marks", "a").write("%s %.3f\n" % (a[0], time.time()))
    elif name == "api": api(a[0], a[1] if len(a) > 1 else None)
    elif name == "waitstate":                                    # waitstate "<python expr on d = GET /test/state>" [timeout s]
        import urllib.request
        end = time.time() + (a[1] if len(a) > 1 else 20)
        while time.time() < end:
            try:
                d = json.load(urllib.request.urlopen(urllib.request.Request("http://127.0.0.1:8917/test/state",
                                                                            headers=_token()), timeout=5))
                if eval(a[0]): break
            except Exception as e: err = e
            time.sleep(0.05)
        else: print('waitstate timed out:', a[0], locals().get('err'))
    else: raise SystemExit("unknown op " + name)
