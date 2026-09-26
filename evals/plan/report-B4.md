# Test plan run — 2026-09-26 13:25

Verdicts: **PASS** = the app does what the plan expects · **BUG** = the plan's prediction of a defect was confirmed · **FAIL** = neither the expectation nor the prediction · **SKIP** / **ERROR**.

BUG 4

| case | verdict | s | expectation | observed |
|---|---|---|---|---|
| TG10 | **BUG** | 5 | 🔼← F11 while the prompt panel is held cancels it (`✕ cancelled`, no outbox row). Predicted defect: nothing — the panel sends at the end of its hold | panel up 18 ms after /test/dictation, F11 at +0.018 s; outbox +1, ✕ cancelled=False, autosend=True · sent forward-left@0.018s |
| TG11 | **BUG** | 3 | 🔽→ while the panel is held is not the panel's ⏎ (its Return is stamped ours). Predicted defect: the ⏎ branch ignores the stamp — trace `SWALLOWED by the prompt panel's ⏎` on key 36 (ours), panel sent | panel up 7 ms after /test/dictation; outbox row 126 ms after the 🔽→; trace: swallowed by the panel=True, passed=False; sink Returns=0; autosend=True · sent back-right@0.007s |
| TG16 | **BUG** | 4 | 🔼↓ F9 while the panel is held (words not yet committed) marks that prompt kamikaze. Predicted defect: `☠️ kamikaze gesture with no sentence in flight — ignored` | panel up 8 ms; ignored line=True; sent prompt carries kamikaze=False · sent forward-down@0.008s |
| TG36 | **BUG** | 3 | undefined in the plan: 🔽→ with the *Rebind to…* panel up. Predicted: its Return activates the selected row (the witness is re-bound) | the gesture's Return activated the panel's row — bound after 🔽→ = ttys009 (witness ttys009); `🔽 → — Return` line=True · sent back-right@1.771s |
