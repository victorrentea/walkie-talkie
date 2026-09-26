# Test plan run — 2026-09-26 16:39

Verdicts: **PASS** = the app does what the plan expects · **BUG** = the plan's prediction of a defect was confirmed · **FAIL** = neither the expectation nor the prediction · **SKIP** / **ERROR**.

PASS 4

| case | verdict | s | expectation | observed |
|---|---|---|---|---|
| TL1 | **PASS** | 125 | orphan flush 121 s after /test/area mid-sentence: dictationStartedAt stays non-null (today: null + 'releasing 1 shot(s)' while listening) | bound ttys020; area at t=0, flush seen at — s; at 121 s listening=True dictationStartedAt=2026-09-26T13:39:09.786Z released=no witness got 0 chars; invariants ok |
| TL5 | **PASS** | 370 | helper hang (SIGSTOP): the 300 s decode budget is enforced ('timed out after 300s', the helper killed and replaced), the control surface answers while /test/local-fallback waits, the next decode is in sync. Before: only the route's 180 s semaphore answered, /up was blocked behind it, no timeout ever | route answered after 180.01 s (False); control surface at +5 s: 0.00 s; 'timed out after' by 305 s: yes; after SIGCONT stale answer consumed: no; next decode 0.76 s ok=True in sync |
| TL7 | **PASS** | 5 | a dead helper must not read ready:true in /engine (plan: today still ready:true until a request fails) | after SIGKILL (alive=False): ready=False; after one request (4.11 s, ok=True): ready=True |
| TD8 | **PASS** | 140 | a sentence open > 120 s with a wheel shot keeps its envelope; no bare screenshot message goes to A | /test/area 200; flush line=none in 135 s; listening=True; dictationStartedAt 2026-09-26T13:47:28.652Z → 2026-09-26T13:47:28.652Z; screenshot rows=0 to=[]; witness bytes=0 |
