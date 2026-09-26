# Test plan run — 2026-09-26 13:21

Verdicts: **PASS** = the app does what the plan expects · **BUG** = the plan's prediction of a defect was confirmed · **FAIL** = neither the expectation nor the prediction · **SKIP** / **ERROR**.

BUG 1 · PASS 1 · SKIP 3

| case | verdict | s | expectation | observed |
|---|---|---|---|---|
| TG3 | **SKIP** | 6 | 🔼← F11 aborts a start banked on a cold local model. Predicted defect: no cancel line, and the microphone opens ~10 s later anyway (`recordWhenSourceReady` ignored by cancel) | SIGKILL did not clear whisper.ready |
| TG4 | **SKIP** | 6 | 🔽 click on a cold local model stays a clean dictation once the model is up (context shot skipped) and a second 🔽 click stops it. Predicted defect: the resumed start drops `clean` — a caret prompt with a context shot, and the second click is the shutter | SIGKILL did not clear whisper.ready |
| TG28 | **BUG** | 7 | every gesture's keyDown is in the key trace with its verdict (`↓ key N … SWALLOWED by …`). Predicted defect: blindness for all ten — zero `↓`, one `↑ (ours) passed` each | all ten blind — forward-click F7 ↓0/0sw ↑1, forward-right F10 ↓0/0sw ↑1, forward-left F11 ↓0/0sw ↑1, forward-up F8 ↓0/0sw ↑1, forward-down F9 ↓0/0sw ↑1, back-click F6 ↓0/0sw ↑1, back-down F12 ↓0/0sw ↑1, back-right F5 ↓0/0sw ↑1, back-left F3 ↓0/0sw ↑1, back-up F4 ↓0/0sw ↑1 · sent back-right@0.000s forward-left@0.716s back-down@1.432s forward-down@2.150s forward-click@2.868s forward-right@3.201s forward-up@3.720s back-up@4.528s back-click@5.347s back-left@6.160s |
| TG29 | **PASS** | 13 | `sessionFlags == []` within 300 ms after every gesture and after the app's own posters (`postReturn` via 🔽→ at idle; `postWisprHandsFree` / `postWisprCancel` when Wispr runs) | 13 steps, every one bare within 300 ms · postWisprHandsFree exercised; postWisprCancel not reached (🔽← took the relay-cancel branch); Wispr closed=True · sent back-right@0.000s forward-left@0.716s back-down@1.436s forward-down@2.156s forward-click@2.874s forward-right@3.206s forward-up@3.722s back-up@4.534s back-click@5.353s back-left@6.165s postWisprHandsFree (start)@6.540s back-left@7.015s postWisprHandsFree (stop)@12.002s |
| TG41 | **SKIP** | 6 | an engine switch while a gesture is banked on the cold local model is refused, or drops the bank. Predicted defect (R7): accepted, and the dictation opens on the new engine when the 0.5 s poll fires (or `Wispr Flow is not running` flashes) | SIGKILL did not clear whisper.ready |
