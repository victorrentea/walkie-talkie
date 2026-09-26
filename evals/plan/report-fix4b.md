# Test plan run — 2026-09-26 17:21

Verdicts: **PASS** = the app does what the plan expects · **BUG** = the plan's prediction of a defect was confirmed · **FAIL** = neither the expectation nor the prediction · **SKIP** / **ERROR**.

BUG 1

| case | verdict | s | expectation | observed |
|---|---|---|---|---|
| TD20 | **BUG** | 7 | 5000 chars with quotes/$(date)/backticks/^C/ESC[201~ arrive intact: 2-3 CR, control bytes stripped, no expansion | control bytes reached the tty raw — sent 4826 chars via autosend; to=terminal:ttys024; arrived 4851 bytes in 6 reads (1022, 1022, 1022, 1022, 762, 1); CR=2; ^C raw=True; ESC[201~ raw=True; literals intact=True; begin+end=True |
