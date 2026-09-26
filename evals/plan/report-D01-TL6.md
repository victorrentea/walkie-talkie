# Test plan run — 2026-09-26 13:36

Verdicts: **PASS** = the app does what the plan expects · **BUG** = the plan's prediction of a defect was confirmed · **FAIL** = neither the expectation nor the prediction · **SKIP** / **ERROR**.

PASS 1

| case | verdict | s | expectation | observed |
|---|---|---|---|---|
| TL6 | **PASS** | 4 | dead helper (SIGKILL) → /test/local-fallback {ok:false} fast + 'it died', app pid unchanged (probable before G4: app dies of SIGPIPE); restart brings it back | route 0.05 s → {'error': 'no words', 'ok': False}; app pid 11073→11073; 'it died' line: yes; ready after=False; restart up in 3.1 s (helper pid 28708→46116) |
