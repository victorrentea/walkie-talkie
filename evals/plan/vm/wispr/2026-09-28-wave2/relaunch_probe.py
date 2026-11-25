"""Lab wave 2 probe (2026-09-28): does a Wispr (re)launch silence BlackHole 2ch for a few seconds?
A recorder opened BEFORE the relaunch records 10 s of BlackHole input; a clip is played into
BlackHole from a separate process starting at +1.5 s; Wispr is relaunched through the app's
/test/wispr-proc at +1.0 s (or not, for the control). Prints the voiced share per 0.5 s window
and whether the player process raised."""
import json, os, subprocess, sys, time, urllib.request, numpy as np, sounddevice as sd
relaunch = sys.argv[1] == "relaunch"
CLIP = sys.argv[2]
idx = [i for i, d in enumerate(sd.query_devices()) if "blackhole" in d["name"].lower()][0]
rec = sd.rec(int(48000 * 10), 48000, channels=2, device=idx, dtype="float32")
t0 = time.time()
time.sleep(1.0)
if relaunch:
    r = urllib.request.Request("http://127.0.0.1:8917/test/wispr-proc", data=b'{"relaunch": true}', method="POST",
                               headers={"X-Walkie-Token": open(os.path.expanduser("~/.walkie-talkie/test-token")).read().strip()})  # 2026-11-25
    print("relaunch:", urllib.request.urlopen(r, timeout=30).read()[:120], "at +%.2f s" % (time.time() - t0))
time.sleep(max(0, 1.5 - (time.time() - t0)))
player = subprocess.run([sys.executable, "-c", """
import sys, wave, numpy as np, sounddevice as sd
from scipy.signal import resample_poly
idx=[i for i,d in enumerate(sd.query_devices()) if 'blackhole' in d['name'].lower()][0]
w=wave.open(sys.argv[1]); a=np.frombuffer(w.readframes(w.getnframes()),np.int16).astype(np.float32)/32768
a=resample_poly(a,48000,w.getframerate())[:48000*6]; a=a/max(1e-6,abs(a).max())*0.5
sd.play(np.repeat(a[:,None],2,1),48000,device=idx,blocking=True); print('played',len(a)/48000)
""", CLIP], capture_output=True, text=True, timeout=60)
print("player rc", player.returncode, player.stdout.strip(), player.stderr.strip()[-200:], "started at +1.5 s")
sd.wait()
x = np.abs(rec[:, 0])
win = [float((x[i:i + 24000] > 0.01).mean()) for i in range(0, len(x), 24000)]
print("voiced share per 0.5 s:", " ".join("%.2f" % v for v in win))
print("total voiced s ≈ %.1f" % (sum(v * 0.5 for v in win)))
