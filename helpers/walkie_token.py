"""The loopback's `X-Walkie-Token` (2026-11-25), for every Python caller of 8917–8919.

The app writes a fresh token to `<home>/test-token` at every launch (`LoopbackToken.swift`);
every route but `GET /engine`, `GET /target`, `POST /reply` and `POST /ask` answers 401
without it. The home is `$WALKIE_HOME`, else `~/.walkie-talkie` — the same override
`relay-restart.sh` and `tools/restart_gate.py` use for a `--home` instance.

Two ways in:

    import walkie_token; walkie_token.install()   # every urlopen to 127.0.0.1:8917-8919 carries it
    urllib.request.Request(url, headers=walkie_token.headers({...}))

The file is re-read at every request, so a caller that outlives a relaunch keeps working.
"""
import os
import urllib.parse
import urllib.request

HEADER = "X-Walkie-Token"
PORTS = (8917, 8918, 8919)
_LOCAL = {"127.0.0.1", "localhost", "::1"}


def home() -> str:
    return os.path.expanduser(os.environ.get("WALKIE_HOME") or "~/.walkie-talkie")


def path(home_dir: str | None = None) -> str:
    return os.path.join(home_dir or home(), "test-token")


def token(home_dir: str | None = None) -> str:
    """This launch's token, or "" when the app has not written one (it then answers 401)."""
    try:
        with open(path(home_dir), encoding="utf-8") as f:
            return f.read().strip()
    except OSError:
        return ""


def headers(extra: dict | None = None, home_dir: str | None = None) -> dict:
    out = dict(extra or {})
    t = token(home_dir)
    if t:
        out[HEADER] = t
    return out


def is_relay(url: str) -> bool:
    u = urllib.parse.urlsplit(url)
    return (u.hostname or "") in _LOCAL and u.port in PORTS


class _Handler(urllib.request.BaseHandler):
    handler_order = 100  # before the default handlers send anything

    def http_request(self, req):
        if is_relay(req.full_url) and not req.has_header(HEADER.capitalize()):
            t = token()
            if t:
                req.add_unredirected_header(HEADER, t)
        return req


_installed = False


def install():
    """Make every `urllib.request.urlopen` to the relay's ports carry the token. Idempotent."""
    global _installed
    if not _installed:
        urllib.request.install_opener(urllib.request.build_opener(_Handler()))
        _installed = True


def curl_args(home_dir: str | None = None) -> list[str]:
    """`["-H", "X-Walkie-Token: …"]` for a `curl` this process runs, [] without a token."""
    t = token(home_dir)
    return ["-H", "%s: %s" % (HEADER, t)] if t else []


def find_port(timeout: float = 2.0) -> int | None:
    """First of 8917–8919 whose `GET /test/state` answers this home's token with 200.

    Asking a gated route is the point: a relay of another home (the installed app on
    8917 beside a `--home` test instance on 8918) answers 401 and is skipped.
    """
    for p in PORTS:
        req = urllib.request.Request("http://127.0.0.1:%d/test/state" % p, headers=headers())
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                if r.status == 200:
                    return p
        except Exception:
            continue
    return None
