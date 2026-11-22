#!/usr/bin/python3
"""Synthetic pointer + keys INSIDE the lab guest (never on the host). Runs with the guest's /usr/bin/python3 (pyobjc).

    mouse.py '[["move",640,360,0.6],["down","middle"],["drag",900,500,0.8,"middle"],["up","middle"]]'

Ops (global points, origin top-left): move x y [seconds] · drag x y [seconds] [button] · down/up/click [button]
· key <keycode> [flag…] · keydown/keyup <keycode> [flag…] · flags [flag…] (bare modifier state) · sleep s · type "text" · pbimage <file>
Buttons: left right middle. Flags: shift cmd ctrl alt.
"""
import json, sys, time
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


def glide(x, y, seconds, kind, button):
    x0, y0 = pos(); n = max(1, int(seconds * 60))
    for i in range(1, n + 1):
        t = i / n; t = t * t * (3 - 2 * t)                       # ease in and out
        post(kind, x0 + (x - x0) * t, y0 + (y - y0) * t, button)
        time.sleep(seconds / n)


def mask(names): 
    m = 0
    for n in names: m |= FLAG[n]
    return m


def key(code, names, down):
    e = Q.CGEventCreateKeyboardEvent(src, code, down)
    Q.CGEventSetFlags(e, mask(names) | held)
    Q.CGEventPost(Q.kCGHIDEventTap, e)


for op in json.loads(sys.argv[1] if len(sys.argv) > 1 else sys.stdin.read()):
    name, a = op[0], op[1:]
    if name == "move": glide(a[0], a[1], a[2] if len(a) > 2 else 0, Q.kCGEventMouseMoved, Q.kCGMouseButtonLeft)
    elif name == "drag":
        b = BTN[a[3] if len(a) > 3 else "left"]; glide(a[0], a[1], a[2] if len(a) > 2 else 0.5, b[3], b[0])
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
    else: raise SystemExit("unknown op " + name)
