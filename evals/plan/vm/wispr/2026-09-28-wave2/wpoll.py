import json, os, sys, time, urllib.request
# wpoll.py SECONDS STEP — sample wisprLive every STEP s (ghost-mic watch, lab wave 2)
n, step = float(sys.argv[1]), float(sys.argv[2]); t0 = time.time()
while time.time() - t0 < n:
    try:
        # X-Walkie-Token (2026-11-25): read at every poll, the guest's own home.
        s = json.load(urllib.request.urlopen(urllib.request.Request("http://127.0.0.1:8917/test/state",
            headers={"X-Walkie-Token": open(os.path.expanduser("~/.walkie-talkie/test-token")).read().strip()}), timeout=10))
        w = s["wisprLive"]
        print(time.strftime("%H:%M:%S", time.gmtime()), "pid", w["wisprPid"], "micOpen", w["micOpen"], "capture", w["captureOpen"],
              "row", w["newestRowId"], w["newestRowStatus"], "wispr", s["wispr"]["state"], "listening", s["listening"], "busy", s["busy"], flush=True)
    except Exception as e:
        print(time.strftime("%H:%M:%S", time.gmtime()), "ERR", e, flush=True)
    time.sleep(step)
