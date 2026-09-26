# Test plan run — 2026-09-26 14:24

Verdicts: **PASS** = the app does what the plan expects · **BUG** = the plan's prediction of a defect was confirmed · **FAIL** = neither the expectation nor the prediction · **SKIP** / **ERROR**.

BUG 1

| case | verdict | s | expectation | observed |
|---|---|---|---|---|
| TL5 | **BUG** | 311 | helper hang (SIGSTOP): /test/local-fallback answers only at the route's 180 s semaphore, no 'timed out after 300s' ever; after SIGCONT the stale answer is consumed | route answered after 180.0 s (False); control surface at +5 s: blocked (TimeoutError); 'timed out after' by 305 s: no; after SIGCONT stale answer consumed: yes; next decode 0.74 s ok=True in sync — the helper's 300 s budget is not enforced; only the route's semaphore answered |
