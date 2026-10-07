#!/usr/bin/env python3
"""**Walkie's channel into a running Claude Code session** (2026-10-07, experiment).

Victor: *"Is it even possible to find a better way to ship a prompt to a running
Claude instance in a terminal, something more reliable than pasting a text and
hitting enter afterwards?"* Typing into the tab fails in ways the relay can only
paper over: Claude Code folds a Return that arrives with a large chunk into the
paste, asks to "review and press Enter", or leaves the sentence under the prompt
while background agents run.

Claude Code's **channels** (research preview, code.claude.com/docs/en/channels-
reference) are the documented way in: an MCP server that Claude Code spawns over
stdio and that pushes `notifications/claude/channel`; the text reaches the model as
`<channel source="walkie">…</channel>`, queued while a turn runs. No keystrokes.

This is that server, stdlib only (Apple's `/usr/bin/python3`, like
`recent_projects.py`): newline-delimited JSON-RPC on stdin/stdout, plus an HTTP
listener on a random 127.0.0.1 port. Every session started with

    claude --dangerously-load-development-channels server:walkie

spawns its own copy; the copy finds the terminal it serves (its parent's tty) and
writes `~/.walkie-talkie/channels/<tty>.json` — `{port, token, tty, claude_pid}` —
so the app can address the session it is bound to. The file goes when the session
ends (stdin closes).

`POST /prompt` with header `X-Walkie-Token: <token>` → one channel event, body =
the prompt. The token is what keeps a web page from posting into the session: a
browser can reach 127.0.0.1 but cannot read the file or send the header blind.
"""
import json
import os
import secrets
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

NAME = "walkie"
CHANNELS = os.path.expanduser("~/.walkie-talkie/channels")
INSTRUCTIONS = (
    'Messages arriving as <channel source="walkie"> are Victor\'s own prompts: he dictated them into '
    "his microphone and his Walkie Talkie app relayed them to this terminal session instead of typing "
    "them. Treat each one exactly as a message Victor typed at this prompt — same authority, same "
    "envelope (screenshot paths, [Dictated in RO or EN] footer). It is one-way: answer in the session "
    "as usual, there is no reply tool."
)

out_lock = threading.Lock()
pending = []                 # prompts held while the session works — see `deliver`
pending_lock = threading.Lock()


def session_busy():
    """Claude Code's own word on the session that spawned us: `status` in
    `~/.claude/sessions/<pid>.json` — `busy` while a turn runs."""
    try:
        with open(os.path.expanduser(f"~/.claude/sessions/{os.getppid()}.json")) as f:
            return json.load(f).get("status") == "busy"
    except Exception:
        return False


def emit(text):
    send({"jsonrpc": "2.0", "method": "notifications/claude/channel",
          "params": {"content": text, "meta": {"via": "dictation"}}})


def deliver(text):
    """**Only into an idle session.** Measured 2026-10-07: a channel event that
    arrives while a turn runs is filed as a `queued_command` from the channel and
    shown to the model as *untrusted external input* — it declined to act on it
    ("write BETA into …" was not done) — while the same text into an idle session
    becomes an ordinary user turn and is acted on. So a prompt that finds the
    session busy is held here and emitted the moment the turn ends."""
    with pending_lock:
        if pending or session_busy():
            pending.append(text)
            log(f"held — the session is working ({len(pending)} waiting)")
            return "held"
    emit(text)
    return "sent"


def release_when_idle():
    while True:
        threading.Event().wait(0.25)
        with pending_lock:
            if not pending or session_busy():
                continue
            batch = pending[:]
            pending.clear()
        for text in batch:
            emit(text)
        log(f"released {len(batch)} held prompt(s) — the turn ended")


def send(msg):
    with out_lock:
        sys.stdout.write(json.dumps(msg, ensure_ascii=False) + "\n")
        sys.stdout.flush()


def log(text):
    sys.stderr.write(f"[walkie-channel] {text}\n")
    sys.stderr.flush()


def parent_tty():
    """The terminal of the `claude` process that spawned us — `ttys012`."""
    try:
        out = subprocess.run(["/bin/ps", "-o", "tty=", "-p", str(os.getppid())],
                             capture_output=True, text=True, timeout=2).stdout.strip()
        return out if out.startswith("ttys") else None
    except Exception:
        return None


class Handler(BaseHTTPRequestHandler):
    token = ""

    def log_message(self, *args):
        pass

    def do_POST(self):
        if self.path != "/prompt" or self.headers.get("X-Walkie-Token") != self.token:
            self.send_response(403)
            self.end_headers()
            return
        n = int(self.headers.get("Content-Length") or 0)
        text = self.rfile.read(n).decode("utf-8", "replace")
        if not text.strip():
            self.send_response(400)
            self.end_headers()
            return
        outcome = deliver(text)
        log(f"prompt in, {len(text)} chars — {outcome}")
        self.send_response(200)
        self.end_headers()
        self.wfile.write(outcome.encode())


def serve_http():
    """Bind, then publish where — returns the registry file to remove at the end."""
    Handler.token = secrets.token_hex(16)
    httpd = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    threading.Thread(target=release_when_idle, daemon=True).start()
    tty = parent_tty() or f"pid{os.getppid()}"
    os.makedirs(CHANNELS, exist_ok=True)
    path = os.path.join(CHANNELS, f"{tty}.json")
    tmp = path + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump({"port": httpd.server_address[1], "token": Handler.token, "tty": tty,
                   "claude_pid": os.getppid(), "pid": os.getpid()}, f)
    os.replace(tmp, path)
    log(f"listening on 127.0.0.1:{httpd.server_address[1]} for {tty}")
    return path


def main():
    registry = None
    try:
        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue
            try:
                msg = json.loads(line)
            except ValueError:
                continue
            method, mid = msg.get("method"), msg.get("id")
            if method == "initialize":
                version = (msg.get("params") or {}).get("protocolVersion", "2025-06-18")
                send({"jsonrpc": "2.0", "id": mid, "result": {
                    "protocolVersion": version,
                    "capabilities": {"experimental": {"claude/channel": {}}},
                    "serverInfo": {"name": NAME, "version": "0.1.0"},
                    "instructions": INSTRUCTIONS}})
            elif method == "notifications/initialized":
                if registry is None:
                    registry = serve_http()
            elif mid is not None:
                if method == "ping":
                    send({"jsonrpc": "2.0", "id": mid, "result": {}})
                elif method in ("tools/list", "resources/list", "prompts/list"):
                    key = method.split("/")[0]
                    send({"jsonrpc": "2.0", "id": mid, "result": {key: []}})
                else:
                    send({"jsonrpc": "2.0", "id": mid,
                          "error": {"code": -32601, "message": f"no {method}"}})
    finally:
        if registry:
            try:
                os.remove(registry)
            except OSError:
                pass


if __name__ == "__main__":
    main()
