# Test plan run — 2026-09-26 14:42

Verdicts: **PASS** = the app does what the plan expects · **BUG** = the plan's prediction of a defect was confirmed · **FAIL** = neither the expectation nor the prediction · **SKIP** / **ERROR**.

BUG 1

| case | verdict | s | expectation | observed |
|---|---|---|---|---|
| TR11 | **BUG** | 53 | slow failure (transport after 19 s, twice) passes the 30 s settle ceiling → expected to fail today: the settle times out before the fallback | settle timed out at 32.1 s, ↪️ at 39.1 s, end at 40.9 s, via local-fallback, to terminal:ttys007 |
