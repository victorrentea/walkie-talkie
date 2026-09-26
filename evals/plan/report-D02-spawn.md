# Test plan run — 2026-09-26 13:37

Verdicts: **PASS** = the app does what the plan expects · **BUG** = the plan's prediction of a defect was confirmed · **FAIL** = neither the expectation nor the prediction · **SKIP** / **ERROR**.

BUG 2 · SKIP 1

| case | verdict | s | expectation | observed |
|---|---|---|---|---|
| TR22 | **SKIP** | 0 | a spawn that fails re-offers the sentence; no spawn: receipt before the window exists | no route or fault switch fails a spawn (SpawnTerminal has no test hook) — needs a new gap |
| TD25 | **BUG** | 5 | busy stays true from the spawn's first busy until the new window is bound (spawn is a restart blocker) | busy false before the spawned window was bound — 114 samples; first busy +0.036s ('prompt on screen',); bound ttys015 at +3.09s; idle-while-unbound samples=59 from +1.038s to +3.055s |
| TR22 | **BUG** | 0 | no `spawn:` receipt before the new window exists (and a failed spawn re-offers the sentence) | receipt written before the window existed — spawn rows=['spawn:/Users/victorrentea/workspace']; first outbox row at +1.04s; bound ttys015 at +3.09s; failure/re-offer not injectable |
