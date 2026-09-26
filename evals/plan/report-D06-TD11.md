# Test plan run — 2026-09-26 13:54

Verdicts: **PASS** = the app does what the plan expects · **BUG** = the plan's prediction of a defect was confirmed · **FAIL** = neither the expectation nor the prediction · **SKIP** / **ERROR**.

PASS 1

| case | verdict | s | expectation | observed |
|---|---|---|---|---|
| TD11 | **PASS** | 43 | gate escapes a stale `listening` (no mic, no recogniser) after ~30 s + 10 quiet s → exit 0, 'stuck flag' | busyWhy before=['dictating']; exit 0 after 40s; output: ` is still up with no microphone and no recogniser behind it — a stuck flag, not a sentence<br>⏳ waiting for 10 quiet seconds after the last delivery (1 s so far)<br>✅ idle, and quiet for 10 s — safe to restart (waited 39 s)<br>🧪 dry run: the gate is open — would quit pid 75172, relaunch, and re-bind nothing |
