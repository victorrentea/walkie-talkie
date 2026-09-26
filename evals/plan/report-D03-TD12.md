# Test plan run — 2026-09-26 13:38

Verdicts: **PASS** = the app does what the plan expects · **BUG** = the plan's prediction of a defect was confirmed · **FAIL** = neither the expectation nor the prediction · **SKIP** / **ERROR**.

BUG 1

| case | verdict | s | expectation | observed |
|---|---|---|---|---|
| TD12 | **BUG** | 16 | a bind made while a quit is deferred survives the relaunch (restore binds B, not the A read before SIGTERM) | the relaunch restored the stale A — A=ttys016 B=ttys017; bound-tty read before SIGTERM=ttys016; quit deferred=True; restore /bind 200; bound after=ttys016 |
