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

    **`auto` is not good enough, and that is measured** (2026-09-13). The whole
    harness was built on the journal's hypothesis that *with Auto-detect picked
    Wispr follows the system default input, which is scriptable*. It does not.
    Five runs with the system default pointed at `🎙️TO Zoom` came back with
    Wispr's own `micDevice` column reading **`Built-in mic (recommended)`** every
    single time — Wispr resolves *Auto-detect* to the built-in microphone, not to
    the system default. The WAV was never heard: what Wispr recorded was a quiet
    room (RMS 37-109 against the clip's 297, 1% of frames over the speech
    threshold against 11%), which is why row after row sat at `raw_transcript`
    and `no_audio` with no text.

    So Wispr's microphone has to be **pinned to the Loopback device in Wispr's
    own UI** — which is what `docs/teacher-loopback.md` said from the start. Only
    Victor can do it, and nothing here may write that file.

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
    name = names.get(device)
    # **A hash with no name is not a failure.** `rankedAudioDevices` is Wispr's
    # cache of the devices it has *enumerated*, and it lags: the moment after a
    # new device is picked in Wispr's UI, `overrideAudioDeviceId` is a hash that
    # is in no entry (seen 2026-09-13 the minute `🎓 TO Wispr` was pinned). The
    # id is a per-origin salted hash and cannot be computed from a name, so this
    # is genuinely unanswerable from the file — which is the whole reason the
    # run checks Wispr's `micDevice` column afterwards.
    if name is None or name == device:
        return ("unnamed", str(device)[:12] + "…")
    return ("fixed", str(name))


def _loopback_name(device_name: str | None) -> str:
    """The device this run would play into, by name, or "" if none resolves."""
    try:
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        import wispr_loopback as wl
        return wl.resolve_device(device_name)[1]
    except Exception:
        return ""


def _same_device(a: str, b: str) -> bool:
    """CoreAudio names carry emoji and spacing Wispr does not always echo back."""
    strip = lambda x: "".join(c for c in (x or "").lower() if c.isalnum())  # noqa: E731
    return bool(a and b) and (strip(b) in strip(a) or strip(a) in strip(b))


def wispr_settings_open() -> str:
    """Wispr's own window, if one is in front. `""` when only its pill is up.

    **Wispr's Settings → Microphone page holds the microphone open** for its
    level meter. A run made while it is up is poisoned three ways, all observed
    2026-09-13 22:13: `WisprWatch` sees no *transition* to recording, so the
    relay reports `no microphone within 12 s of the hotkey — Wispr ignored the
    chord` for a dictation Wispr was recording perfectly well; the row never
    leaves `processing`; and `micDevice` is never written, so the one column
    that is ground truth about the microphone stays blank.

    Read with `osascript`, which activates nothing.
    """
    try:
        out = subprocess.run(
            ["/usr/bin/osascript", "-e",
             'tell application "System Events" to tell process "Wispr Flow" to '
             "name of windows"],
            capture_output=True, text=True, timeout=10).stdout
    except Exception:
        return ""
    # "Status" is the pill and is always there; anything else is a real window.
    windows = [w.strip() for w in (out or "").split(",") if w.strip() and w.strip() != "Status"]
    return ", ".join(windows)


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
    wanted = _loopback_name(device_name)
    if speaker:
        rows.append(Row(None, "Wispr microphone is %s — playing out loud instead" % mic_name, key="mic"))
    elif wanted and _same_device(mic_name, wanted):
        rows.append(Row(True, "Wispr microphone: %s — the device this plays into" % mic_name, key="mic"))
    elif mic == "unnamed":
        rows.append(Row(None, "Wispr microphone is a device id Wispr has not named yet (%s) — most "
                        "likely the one just pinned. Going ahead; the run reports which microphone "
                        "Wispr actually used." % mic_name, key="mic"))
    elif mic == "auto":
        # **Auto-detect is a hard failure, and it is measured.** It resolves to
        # the built-in microphone, not to the system default input: six runs,
        # six times `micDevice = Built-in mic (recommended)`, and the audio to
        # match — the clip goes out at RMS 1714 and Wispr's own stored blob comes
        # back at RMS 59, 0% of frames voiced. A 29× drop is not something a
        # digital pass-through can do; that is a room.
        rows.append(Row(False, "Wispr microphone is Auto-detect, which means the built-in mic",
                        fatal=True, key="mic",
                        remedy="Victor: Wispr → Settings → Microphone → 🎓 TO Wispr.\n"
                               "Auto-detect does NOT follow the system default input — measured\n"
                               "2026-09-13, six runs out of six: RMS 1714 played, 59 stored, 0%\n"
                               "voiced. The WAV is never heard."))
    else:
        rows.append(Row(False, "Wispr microphone is %r, not %s" % (mic_name, wanted or "the Loopback device"),
                        fatal=True, key="mic",
                        remedy="Victor: Wispr → Settings → Microphone → 🎓 TO Wispr.\n"
                               "That device's sources are the physical MacBook Pro Microphone AND\n"
                               "Pass-Thru, so his own dictation is unaffected and the rig plays into the\n"
                               "same device. Nothing here may edit Wispr's config.json — the id is a\n"
                               "salted hash in a file Wispr's own process rewrites."))

    target = get(port, "/target") or {}
    if target.get("bound"):
        rows.append(Row(None, "bound to %s — the transcript should reach that session"
                        % (target.get("address") or "?"), key="target"))
    else:
        rows.append(Row(None, "unbound — the transcript should land at the caret", key="target"))

    settings = wispr_settings_open()
    if settings:
        rows.append(Row(False, "a Wispr Flow window is open (%s)" % settings, fatal=True, key="wispr-ui",
                        remedy="Close it. Wispr's Settings → Microphone page holds the microphone\n"
                               "open for its level meter, and a run made while it is up gets no\n"
                               "microphone *transition* for WisprWatch to see: the relay reports\n"
                               "'Wispr ignored the chord' for a dictation Wispr is recording fine,\n"
                               "the row never leaves 'processing', and micDevice is never written."))

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
            if wl.is_pinned_device(name):
                note += " — Wispr is pinned to it, so the system default input is left alone"
            else:
                note += (" — a fallback device; Wispr is not pinned to it, so this needs "
                         "--switch-input and steers the system default")
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
