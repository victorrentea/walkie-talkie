#!/usr/bin/env python3
"""Everything that must be true before a WAV is played at Wispr Flow.

`tools/wispr-test.sh` and `tools/wispr-loop.sh` both drive a **real** dictation
through a virtual microphone, and both fail the same six ways. A preflight that
lives in one of them is a preflight the other one drifts away from, so it lives
here and each script asks for the rows it needs.

Every check answers in **words** and never silently. The failure this exists to
prevent is the quiet one: a WAV played into a device nobody is recording, Wispr
hearing the room instead, and a run that reports "no transcript" when the truth
is "one setting in an app we do not control is on the wrong value". Each row
says which of those it is, and a fatal row says what Victor has to do about it.

    python3 helpers/wispr_preflight.py                 # the rows, as text
    python3 helpers/wispr_preflight.py --json          # the same, machine-readable
    python3 helpers/wispr_preflight.py --require-routes /test/state,/test/sink

Exit code 0 when nothing fatal failed, 2 when something did.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import urllib.error
import urllib.request

HOME = os.path.expanduser("~")
WISPR_CONFIG = os.path.join(HOME, "Library/Application Support/Wispr Flow/config.json")
PORTS = (8917, 8918, 8919)
INSTALLED = "/Applications/Walkie Talkie.app"


# ── the relay's HTTP surface ─────────────────────────────────────────────────
def relay_port(timeout: float = 2.0) -> int | None:
    """First of 8917–8919 that answers. `ElementPicker` takes the first free one."""
    for port in PORTS:
        try:
            urllib.request.urlopen("http://127.0.0.1:%d/target" % port, timeout=timeout).read()
            return port
        except Exception:
            continue
    return None


def get(port: int, path: str, timeout: float = 5.0):
    """GET a route. Returns the decoded body, or `None` when the route is not there.

    A missing route is not an error here: half the point of the loop runner is
    to wait for routes another agent is still adding, and a 404 is how it finds
    out they have not landed yet.
    """
    try:
        with urllib.request.urlopen("http://127.0.0.1:%d%s" % (port, path), timeout=timeout) as r:
            return json.loads(r.read().decode("utf-8") or "{}")
    except urllib.error.HTTPError:
        return None
    except Exception:
        return None


def post(port: int, path: str, body=None, timeout: float = 10.0):
    """POST JSON to a route. Same contract as `get` — `None` means it is not there."""
    data = json.dumps(body if body is not None else {}).encode("utf-8")
    req = urllib.request.Request(
        "http://127.0.0.1:%d%s" % (port, path), data=data,
        headers={"content-type": "application/json"}, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.loads(r.read().decode("utf-8") or "{}")
    except urllib.error.HTTPError:
        return None
    except Exception:
        return None


def route_exists(port: int, path: str, timeout: float = 3.0) -> bool:
    """Is this route served at all?

    Two questions, because one answer does not cover both kinds of route.

    A GET that comes back anything other than **404** proves the handler is
    there — that settles `/test/state` and `/test/sink`. But `ElementPicker`
    dispatches on method *and* path and answers a GET to a POST-only route with
    `404 {"ok":false}`, exactly as it answers a route that does not exist
    (measured 2026-09-13: `/bind`, `/test/cancel` and `/test/wispr-handsfree`
    all do). **Probing those with a POST is out of the question** — a POST to
    `/test/gesture` *is* the gesture, and a preflight that fires a chord to find
    out whether it can fire a chord is not a preflight.

    So the second question is asked of the binary: does the running executable
    contain the route's path as a literal. Coarse and one-directional — a hit
    proves the string is compiled in, a miss proves nothing, since Swift is free
    to fold a literal into something `strings` cannot see. Used only as the
    *fallback* for the 404, which is the case where the alternative is guessing.
    """
    try:
        urllib.request.urlopen("http://127.0.0.1:%d%s" % (port, path), timeout=timeout).read()
        return True
    except urllib.error.HTTPError as e:
        if e.code != 404:
            return True
    except Exception:
        return False
    return path in _binary_strings()


_STRINGS_CACHE: str | None = None


def _binary_strings() -> str:
    """`strings` over the running relay's executable, read once."""
    global _STRINGS_CACHE
    if _STRINGS_CACHE is not None:
        return _STRINGS_CACHE
    _STRINGS_CACHE = ""
    # `comm=` and not the command line: the executable's path has a space in it
    # ("/Applications/Walkie Talkie.app/…"), so splitting the command line on a
    # space hands back "/Applications/Walkie" and the scan silently reads
    # nothing — which reads as "the route is not there".
    binary = ""
    try:
        out = subprocess.run(["/bin/ps", "-Ao", "comm="], capture_output=True,
                             text=True, timeout=10).stdout
        for line in out.splitlines():
            if "WalkieTalkie" in line or "Walkie Talkie.app" in line:
                binary = line.strip()
                break
    except Exception:
        binary = ""
    if binary and os.path.exists(binary):
        try:
            # `errors="replace"`: `strings` emits whatever bytes it found, and a
            # strict decode raises UnicodeDecodeError — which the `except` below
            # would then report as "the route is not there".
            _STRINGS_CACHE = subprocess.run(
                ["/usr/bin/strings", "-", binary], capture_output=True, timeout=60,
                encoding="utf-8", errors="replace").stdout or ""
        except Exception:
            _STRINGS_CACHE = ""
    return _STRINGS_CACHE


# ── the things that are true of the Mac, not of the relay ────────────────────
#: **The executable, anchored, and never the bare name** (2026-09-13). Wispr
#: ships a *nested* Accessibility helper at
#: `…/Contents/Resources/swift-helper-app-dist/Wispr Flow.app`, bundle id
#: `com.electron.wispr-flow.accessibility-mac-app`, whose executable is **also**
#: called `Wispr Flow`. `pgrep -x "Wispr Flow"` matches it, `pgrep -f "Wispr
#: Flow.app"` matches it, and — worse — `open -a "Wispr Flow"` *launches* it:
#: LaunchServices resolves the name to the nested bundle, which then quits
#: itself in about 100 ms for want of a parent. That cost an afternoon reading
#: as "Wispr Flow will not stay running", with no crash report and nothing in
#: the unified log, because nothing was crashing — the wrong app was starting
#: and correctly leaving. `osascript -e 'POSIX path of (path to application
#: "Wispr Flow")'` is the one-line proof: it answers the nested path.
WISPR_EXECUTABLE = "/Applications/Wispr Flow.app/Contents/MacOS/Wispr Flow"
#: How to start it, when it is genuinely not running. **Never `open -a`.**
WISPR_LAUNCH = 'open "/Applications/Wispr Flow.app"   (or: open -b com.electron.wispr-flow)'


def wispr_running() -> bool:
    """Is Wispr *proper* running — not its nested Accessibility helper."""
    return _pgrep("^" + WISPR_EXECUTABLE)


def relay_process() -> tuple[bool, str]:
    """(is it the installed bundle, the path we found).

    A `.build/debug` binary has no Accessibility grant, so `CGEventPost` fails
    **silently** — every gesture this harness posts would go nowhere and the run
    would report the app ignoring it. Worth one `ps`.
    """
    try:
        out = subprocess.run(["/bin/ps", "-Ao", "pid=,command="], capture_output=True,
                             text=True, timeout=10).stdout
    except Exception:
        return (False, "?")
    for line in out.splitlines():
        if "WalkieTalkie" in line or "Walkie Talkie.app" in line:
            if "grep" in line:
                continue
            command = line.strip().split(" ", 1)[-1]
            return (INSTALLED in command, command.strip())
    return (False, "(not running)")


def wispr_microphone() -> tuple[str, str]:
    """(`auto` | `fixed` | `unknown`, the device's name).

    Wispr's microphone lives in `prefs.user.overrideAudioDeviceId` as a Chromium
    `MediaDeviceInfo.deviceId` — a per-origin salted hash that cannot be computed
    from a device name, in a file Wispr's own process rewrites. **Nothing here
    ever writes it.** `rankedAudioDevices` carries
    `{"deviceId": "default", "name": "Auto-detect (…)"}`, and with Auto-detect
    picked Wispr follows the system default input, which *is* scriptable.
    """
    if not os.path.exists(WISPR_CONFIG):
        return ("unknown", "(config not found)")
    try:
        with open(WISPR_CONFIG, encoding="utf-8") as handle:
            user = json.load(handle).get("prefs", {}).get("user", {})
    except Exception as e:
        return ("unknown", "(unreadable: %s)" % e)
    device = user.get("overrideAudioDeviceId")
    names = {d.get("deviceId"): d.get("name") for d in (user.get("rankedAudioDevices") or [])}
    if device == "default":
        return ("auto", names.get("default", "Auto-detect"))
    return ("fixed", str(names.get(device, device)))


def audio_stack() -> tuple[bool, str]:
    try:
        import numpy  # noqa: F401
        import sounddevice  # noqa: F401
        return (True, "sounddevice + numpy")
    except Exception as e:
        return (False, str(e))


def hands_off_path() -> str | None:
    path = os.path.join(HOME, "bin/hands-off")
    return path if os.access(path, os.X_OK) else None


def _pgrep(pattern: str) -> bool:
    try:
        return subprocess.run(["/usr/bin/pgrep", "-f", pattern],
                              capture_output=True, timeout=10).returncode == 0
    except Exception:
        return False


# ── the rows ─────────────────────────────────────────────────────────────────
class Row:
    """One preflight answer. `ok` is None for a note that is neither."""

    def __init__(self, ok, text, fatal=False, remedy=None, key=None):
        self.ok, self.text, self.fatal, self.remedy, self.key = ok, text, fatal, remedy, key

    def render(self) -> str:
        mark = "✓" if self.ok else ("✗" if self.ok is False else "•")
        out = "%s %s" % (mark, self.text)
        if self.ok is False and self.remedy:
            out += "\n" + "\n".join("  " + line for line in self.remedy.splitlines())
        return out

    def as_dict(self):
        return {"key": self.key, "ok": self.ok, "text": self.text,
                "fatal": self.fatal, "remedy": self.remedy}


def checks(device_name: str | None = None, speaker: bool = False,
           require_routes: list[str] | None = None, need_idle: bool = True) -> list[Row]:
    """Every precondition, in the order in which one failing makes the next moot."""
    rows: list[Row] = []

    port = relay_port()
    if port is None:
        rows.append(Row(False, "the relay is not listening on 8917–8919", fatal=True,
                        remedy="Is Walkie Talkie running? `open \"/Applications/Walkie Talkie.app\"`.",
                        key="relay"))
        return rows
    rows.append(Row(True, "relay on port %d" % port, key="relay"))

    installed, path = relay_process()
    rows.append(Row(installed, "installed build" if installed else "the running relay is not the installed bundle: %s" % path,
                    fatal=True, key="installed",
                    remedy="`.build/debug` has no Accessibility grant — every gesture this harness\n"
                           "posts would fail silently. Run ./build-app.sh and relay-restart.sh."))

    running = wispr_running()
    rows.append(Row(running, "Wispr Flow is running" if running else "Wispr Flow is not running",
                    fatal=True, key="wispr",
                    remedy="Launch it and let its pill appear:\n  %s\n"
                           "NOT `open -a \"Wispr Flow\"` — that resolves to the nested Accessibility\n"
                           "helper of the same name, which quits itself in ~100 ms." % WISPR_LAUNCH))

    mic, mic_name = wispr_microphone()
    if mic == "auto":
        rows.append(Row(True, "Wispr microphone: Auto-detect — it follows the system default", key="mic"))
    elif speaker:
        rows.append(Row(None, "Wispr microphone is pinned (%s) — playing out loud instead" % mic_name, key="mic"))
    else:
        rows.append(Row(False, "Wispr microphone is pinned to a device (%s)" % mic_name,
                        fatal=True, key="mic",
                        remedy="Victor: Wispr → Settings → Microphone → 'Auto-detect (MacBook Pro)'.\n"
                               "Nothing here may edit Wispr's config.json — the id is a salted hash and\n"
                               "Wispr's own process rewrites the file. Without it Wispr hears the room."))

    target = get(port, "/target") or {}
    if target.get("bound"):
        rows.append(Row(None, "bound to %s — the transcript should reach that session"
                        % (target.get("address") or "?"), key="target"))
    else:
        rows.append(Row(None, "unbound — the transcript should land at the caret", key="target"))

    ok, detail = audio_stack()
    rows.append(Row(ok, "python audio: %s" % detail, fatal=not speaker, key="audio",
                    remedy="pip install sounddevice numpy for %s" % sys.executable))

    if speaker:
        rows.append(Row(None, "playing out loud — Wispr hears it through whatever microphone it is on", key="device"))
    elif ok:
        try:
            sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
            import wispr_loopback as wl
            idx, name = wl.resolve_device(device_name)
            note = "playing into: %s (index %d)" % (name, idx)
            if "wispr" not in name.lower():
                note += " — no '🎓 TO Wispr' device exists; this Loopback pass-through does the same job"
            rows.append(Row(True, note, key="device"))
        except SystemExit as e:
            rows.append(Row(False, "no usable virtual output device", fatal=True, key="device",
                            remedy=str(e)))
        except Exception as e:
            rows.append(Row(False, "virtual output device: %s" % e, fatal=True, key="device"))

    hands_off = hands_off_path()
    rows.append(Row(hands_off is not None,
                    "🔒 hands-off at ~/bin/hands-off" if hands_off else "~/bin/hands-off is missing",
                    fatal=True, key="hands-off",
                    remedy="The run posts keystrokes and steals focus. Without the locks Victor cannot\n"
                           "see that his Mac is busy. `victor-macos-addons/hands-off.sh` → ~/bin/hands-off."))

    for route in (require_routes or []):
        present = route_exists(port, route)
        rows.append(Row(present, "route %s" % route if present else "route %s is not on this build yet" % route,
                        fatal=True, key="route:%s" % route,
                        remedy="Wait for the build that adds it, then run again (--wait-routes polls)."))

    if need_idle:
        up = get(port, "/up") or {}
        idle = not (up.get("listening") or up.get("dictating"))
        rows.append(Row(idle, "no dictation in flight" if idle else "a dictation is already listening — Victor may be talking",
                        fatal=True, key="idle",
                        remedy="Refusing to post gestures into somebody else's sentence. Wait and run again."))

    return rows


def main(argv):
    import argparse

    ap = argparse.ArgumentParser(description="Preconditions for a real Wispr dictation.")
    ap.add_argument("--device", help="virtual output device (substring)")
    ap.add_argument("--speaker", action="store_true", help="out loud instead of the virtual device")
    ap.add_argument("--require-routes", default="", help="comma-separated routes that must exist")
    ap.add_argument("--routes-only", action="store_true",
                    help="check nothing but the routes — 'is this build new enough' is a "
                         "different question from 'is this Mac set up', and the two get "
                         "different exit paths")
    ap.add_argument("--no-idle-check", action="store_true", help="do not refuse a dictation in flight")
    ap.add_argument("--advisory", action="store_true",
                    help="print the rows but never fail — for a dry run, which posts nothing "
                         "and so cannot be harmed by a setting being wrong")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--print", dest="print_", choices=("port", "device"),
                    help="print one value and exit — for a shell script that needs the "
                         "port or the resolved device name and should not parse the rows")
    args = ap.parse_args(argv)

    if args.print_ == "port":
        port = relay_port()
        print(port if port else "")
        return 0 if port else 2
    if args.print_ == "device":
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        import wispr_loopback as wl
        try:
            print(wl.resolve_device(args.device)[1])
        except SystemExit as e:
            print(e, file=sys.stderr)
            return 2
        return 0

    routes = [r.strip() for r in args.require_routes.split(",") if r.strip()]
    if args.routes_only:
        port = relay_port()
        if port is None:
            rows = [Row(False, "the relay is not listening on 8917-8919", fatal=True, key="relay")]
        else:
            rows = [Row(route_exists(port, r), "route %s" % r, fatal=True, key="route:%s" % r)
                    for r in routes]
    else:
        rows = checks(args.device, args.speaker, routes, need_idle=not args.no_idle_check)
    failed = [] if args.advisory else [r for r in rows if r.ok is False and r.fatal]

    if args.json:
        print(json.dumps({"ok": not failed, "rows": [r.as_dict() for r in rows]}, ensure_ascii=False))
    else:
        for row in rows:
            print(row.render())
    return 2 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
