# Test plan run — 2026-09-26 14:35

Verdicts: **PASS** = the app does what the plan expects · **BUG** = the plan's prediction of a defect was confirmed · **FAIL** = neither the expectation nor the prediction · **SKIP** / **ERROR**.

BUG 1

| case | verdict | s | expectation | observed |
|---|---|---|---|---|
| TL8 | **BUG** | 174 | R1: upload > settle ceiling, S2 starts, S1's late reply lands → today: 'dictation abandoned (a new dictation started)', S1's outbox has S2's screen, listening false with isRecording true | settle ended 32.2 s after stop (phaseStatus 'uploading', busy True); abandoned line True; listening:false+isRecording:true at [36.2, 36.4, 36.7]; S1 lines 1 S2 lines 0, same screen dir False; ring down after S2 stop 0 |
