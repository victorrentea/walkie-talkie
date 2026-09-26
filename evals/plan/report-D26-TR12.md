# Test plan run — 2026-09-26 14:44

Verdicts: **PASS** = the app does what the plan expects · **BUG** = the plan's prediction of a defect was confirmed · **FAIL** = neither the expectation nor the prediction · **SKIP** / **ERROR**.

PASS 1

| case | verdict | s | expectation | observed |
|---|---|---|---|---|
| TR12 | **PASS** | 43 | 4xx not retried, 5xx/429 retried once: 'attempt 1 failed' 0/0/1/1 for 401/422/500/429, all end in the fallback | 401: 0 retries, via local-fallback; 422: 0 retries, via local-fallback; 500x2: 1 retry, via local-fallback; 429x2: 1 retry, via local-fallback |
