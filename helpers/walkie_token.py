"""The loopback's `X-Walkie-Token` (2026-11-25), for every Python caller of 8917–8919.

The app writes a fresh token to `<home>/test-token` at every launch (`LoopbackToken.swift`);
every route but `POST /reply` and `POST /ask` answers 401 without it. The home is
`$WALKIE_HOME`, else `~/.walkie-talkie` — the same override `relay-restart.sh` and
`tools/restart_gate.py` use for a `--home` instance.

**The token goes to one port only** (Fable review, 2026-11-25): `<home>/test-port` names the
port the app bound (`starting` until its listener is up). Sending the header to every port of
8917–8919 handed the live token to whatever answered there — a process squatting 8918, or one
that grabbed 8917 between a quit and a relaunch. No port file at all is an app from before it
existed: then 8917 alone gets the token, and with no token file either (an app from before the
gate) all three ports are asked without one.

Two ways in:

    import walkie_token; walkie_token.install()   # every urlopen to the app's port carries it
    urllib.request.Request(url, headers=walkie_token.headers(port, {...}))

The files are re-read at every request, so a caller that outlives a relaunch keeps working.
Runs under /usr/bin/python3 (3.9): the guest and launchd use it.
"""
from __future__ import annotations

import os
import stat
import urllib.parse
import urllib.request

HEADER = "X-Walkie-Token"
PORTS = (8917, 8918, 8919)
LEGACY_PORT = 8917
# The app listens on IPv4 loopback only; `localhost` / `::1` can never be it.
_LOCAL = {"127.0.0.1"}


def home() -> str:
    return os.path.expanduser(os.environ.get("WALKIE_HOME") or "~/.walkie-talkie")


def path(home_dir: str | None = None) -> str:
    return os.path.join(home_dir or home(), "test-token")


def port_path(home_dir: str | None = None) -> str:
    return os.path.join(home_dir or home(), "test-port")


def _read_private(file: str) -> str | None:
    """The file's text, or None when it is missing or not to be trusted: a symlink, not a
    regular file, not this user's, or open to group/other (`LoopbackToken.readPrivate`)."""
    try:
        fd = os.open(file, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except OSError:
        return None
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode) or st.st_uid != os.getuid() or st.st_mode & 0o077 \
                or st.st_size > 4096:
            return None
        return os.read(fd, 4096).decode("utf-8", "replace").strip()
    except OSError:
        return None
    finally:
        os.close(fd)


def token(home_dir: str | None = None) -> str:
    """This launch's token, or "" when the app has not written one (it then answers 401)."""
    return _read_private(path(home_dir)) or ""


def pinned(home_dir: str | None = None) -> tuple[str, int | None]:
    """`(token, port)`: the token and the one port it may be sent to, or `(token, None)` while
    the app is starting (or the port file is not his) — send it nowhere then.

    The token is read **first**: the app sets the port file to `starting` before it writes a
    new token, so a new token is never paired with the last launch's port."""
    t = token(home_dir)
    p = port_path(home_dir)
    if not os.path.lexists(p):
        return t, (LEGACY_PORT if t else None)
    raw = _read_private(p)
    try:
        port = int(raw or "")
    except ValueError:
        return t, None
    return t, (port if port in PORTS else None)


def for_port(port: int | None, home_dir: str | None = None) -> str:
    """The token if `port` is the one the app bound, else ""."""
    t, p = pinned(home_dir)
    return t if t and port is not None and port == p else ""


def targets(home_dir: str | None = None) -> list[tuple[int, dict]]:
    """Where to ask, with the headers for each: the pinned port with the token; with no token
    and no port file (an app from before the gate) all three ports, tokenless; else nothing
    (the app is starting)."""
    t, p = pinned(home_dir)
    if p is not None:
        return [(p, {HEADER: t} if t else {})]
    if not t and not os.path.lexists(port_path(home_dir)):
        return [(port, {}) for port in PORTS]
    return []


def headers(port: int | None, extra: dict | None = None, home_dir: str | None = None) -> dict:
    """`extra` plus the token — only when `port` is the app's own."""
    out = dict(extra or {})
    t = for_port(port, home_dir)
    if t:
        out[HEADER] = t
    return out


def relay_port(url: str) -> int | None:
    """The port of an `http://127.0.0.1:<8917–8919>` URL, else None."""
    u = urllib.parse.urlsplit(url)
    if u.scheme != "http" or (u.hostname or "") not in _LOCAL:
        return None
    try:
        return u.port if u.port in PORTS else None
    except ValueError:
        return None


def is_relay(url: str) -> bool:
    return relay_port(url) is not None


class _Handler(urllib.request.BaseHandler):
    handler_order = 100  # before the default handlers send anything

    def http_request(self, req):
        port = relay_port(req.full_url)
        if port is not None and not req.has_header(HEADER.capitalize()):
            t = for_port(port)
            if t:
                req.add_unredirected_header(HEADER, t)
        return req


_installed = False


def install():
    """Make every `urllib.request.urlopen` to the app's port carry the token. Idempotent.

    A proxy would receive the token too, so the relay's ports bypass it (`no_proxy`)."""
    global _installed
    if not _installed:
        np = os.environ.get("no_proxy") or os.environ.get("NO_PROXY") or ""
        if "127.0.0.1" not in np.split(","):
            os.environ["no_proxy"] = ",".join(x for x in (np, "127.0.0.1") if x)
        urllib.request.install_opener(urllib.request.build_opener(_Handler()))
        _installed = True


def curl_config(port: int | None, home_dir: str | None = None) -> str:
    """`header = "X-Walkie-Token: …"` for `curl --config -` (fed on stdin, never in argv,
    where `ps` shows it to every account); "" unless `port` is the app's own."""
    t = for_port(port, home_dir)
    return 'header = "%s: %s"\n' % (HEADER, t) if t else ""


def find_port(timeout: float = 2.0) -> int | None:
    """The port of this home's app: the pinned one, if its `GET /test/state` answers this
    home's token with 200 (a relay of another home answers 401 and is not it). An app from
    before the gate — no token, no port file — is the first port that answers 200."""
    for p, hdrs in targets():
        req = urllib.request.Request("http://127.0.0.1:%d/test/state" % p, headers=hdrs)
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                if r.status == 200:
                    return p
        except Exception:
            continue
    return None
