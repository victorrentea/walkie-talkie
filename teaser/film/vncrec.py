#!/usr/bin/env python3
"""Record the lab VM's display from the HOST side, through Virtualization.framework's VNC server
(`tart run --vnc-experimental`), without any window on the host.

Why not record inside the guest: most of Walkie's overlay windows are `sharingType = .none`, so no
in-guest screen capture sees them. The hypervisor's framebuffer shows what a person at the screen sees.

    vncrec.py out.mp4 [--seconds N] [--url vnc://:pass@127.0.0.1:port] [--png still.png]

Stops at --seconds, or on SIGINT/SIGTERM (the file is finalised). 30 fps constant, 1920x1080 H.264.
"""
import argparse, os, re, signal, socket, struct, subprocess, sys, threading, time
import numpy as np
from cryptography.hazmat.primitives.ciphers import Cipher, modes
try:
    from cryptography.hazmat.decrepit.ciphers.algorithms import TripleDES
except ImportError:
    from cryptography.hazmat.primitives.ciphers.algorithms import TripleDES


def recvn(s, n):
    buf = bytearray(n); view = memoryview(buf); got = 0
    while got < n:
        r = s.recv_into(view[got:], n - got)
        if not r: raise EOFError("vnc closed")
        got += r
    return buf


def vnc_des(password, challenge):
    key = (password.encode("latin-1") + b"\0" * 8)[:8]
    key = bytes(int(f"{b:08b}"[::-1], 2) for b in key)          # VNC mirrors every key byte
    enc = Cipher(TripleDES(key * 3), modes.ECB()).encryptor()
    return enc.update(bytes(challenge)) + enc.finalize()


def connect(url):
    m = re.match(r"vnc://:?([^@]*)@([^:]+):(\d+)", url)
    pw, host, port = m.group(1), m.group(2), int(m.group(3))
    s = socket.create_connection((host, port)); s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 8 << 20)
    recvn(s, 12); s.sendall(b"RFB 003.008\n")
    n = recvn(s, 1)[0]; types = list(recvn(s, n))
    if 1 in types: s.sendall(b"\x01")
    elif 2 in types:
        s.sendall(b"\x02"); s.sendall(vnc_des(pw, recvn(s, 16)))
    else: raise SystemExit(f"no usable security type in {types}")
    if struct.unpack(">I", recvn(s, 4))[0] != 0: raise SystemExit("vnc auth failed")
    s.sendall(b"\x01")                                           # shared
    w, h = struct.unpack(">HH", recvn(s, 4)); recvn(s, 16)
    recvn(s, struct.unpack(">I", recvn(s, 4))[0])
    # 32 bpp, little endian, true colour, B in the low byte → BGRX in memory
    s.sendall(struct.pack(">BxxxBBBBHHHBBBxxx", 0, 32, 24, 0, 1, 255, 255, 255, 16, 8, 0))
    encs = [0, -223]                                             # raw, DesktopSize
    s.sendall(struct.pack(">BxH", 2, len(encs)) + b"".join(struct.pack(">i", e) for e in encs))
    return s, w, h


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out"); ap.add_argument("--seconds", type=float, default=0)
    ap.add_argument("--url"); ap.add_argument("--png"); ap.add_argument("--fps", type=int, default=30)
    a = ap.parse_args()
    url = a.url
    if not url:
        log = os.path.expanduser(os.environ.get("TART_HOME", "~/tart") + "/wt-lab.log")
        url = re.findall(r"vnc://\S+", open(log).read())[-1]
    s, w, h = connect(url)
    fb = np.zeros((h, w, 4), np.uint8); lock = threading.Lock(); stop = threading.Event()
    stats = {"updates": 0, "first": threading.Event()}

    def reader():
        try:
            s.sendall(struct.pack(">BBHHHH", 3, 0, 0, 0, w, h))
            while not stop.is_set():
                t = recvn(s, 1)[0]
                if t == 0:
                    recvn(s, 1); n = struct.unpack(">H", recvn(s, 2))[0]
                    for _ in range(n):
                        x, y, rw, rh, enc = struct.unpack(">HHHHi", recvn(s, 12))
                        if enc == 0:
                            data = np.frombuffer(recvn(s, rw * rh * 4), np.uint8).reshape(rh, rw, 4)
                            with lock: fb[y:y + rh, x:x + rw] = data
                        elif enc == -223: raise SystemExit("guest display resized mid-recording")
                        else: raise SystemExit(f"unexpected encoding {enc}")
                    stats["updates"] += 1; stats["first"].set()
                    s.sendall(struct.pack(">BBHHHH", 3, 1, 0, 0, w, h))
                elif t == 2: pass                                # bell
                elif t == 3: recvn(s, 3); recvn(s, struct.unpack(">I", recvn(s, 4))[0])
                elif t == 1: recvn(s, 1); recvn(s, 2); recvn(s, 6 * struct.unpack(">H", recvn(s, 2))[0])
                else: raise SystemExit(f"unexpected message {t}")
        except (EOFError, OSError) as e:
            if not stop.is_set(): print("reader:", e, file=sys.stderr)
        finally: stop.set()

    threading.Thread(target=reader, daemon=True).start()
    if not stats["first"].wait(15): raise SystemExit("no first frame")
    if a.png:
        with lock: frame = fb.copy()
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-f", "rawvideo", "-pix_fmt", "bgr0", "-s", f"{w}x{h}",
                        "-i", "-", "-frames:v", "1", a.png], input=frame.tobytes(), check=True)
        if a.out == "-": return
    ff = subprocess.Popen(["nice", "-n", "5", "ffmpeg", "-loglevel", "error", "-y", "-f", "rawvideo", "-pix_fmt", "bgr0",
                           "-s", f"{w}x{h}", "-r", str(a.fps), "-i", "-",
                           "-vf", "scale=1920:1080:flags=lanczos,format=yuv420p", "-c:v", "h264_videotoolbox",
                           "-b:v", "14M", "-r", str(a.fps), "-movflags", "+faststart", a.out], stdin=subprocess.PIPE)
    for sig in (signal.SIGINT, signal.SIGTERM): signal.signal(sig, lambda *_: stop.set())
    t0 = time.monotonic(); n = 0
    print(f"recording {w}x{h} → {a.out}", flush=True)
    while not stop.is_set() and (not a.seconds or n < a.seconds * a.fps):
        due = t0 + n / a.fps; now = time.monotonic()
        if due > now: time.sleep(due - now)
        with lock: frame = fb.tobytes()
        ff.stdin.write(frame); n += 1
    stop.set(); ff.stdin.close(); ff.wait()
    print(f"{n} frames, {n / a.fps:.1f} s, {stats['updates']} vnc updates ({stats['updates'] / max(1, n / a.fps):.0f}/s)")


if __name__ == "__main__":
    main()
