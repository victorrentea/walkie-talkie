# Test plan run — 2026-09-26 15:46

Verdicts: **PASS** = the app does what the plan expects · **BUG** = the plan's prediction of a defect was confirmed · **FAIL** = neither the expectation nor the prediction · **SKIP** / **ERROR**.

FAIL 1 · PASS 6 · SKIP 1

| case | verdict | s | expectation | observed |
|---|---|---|---|---|
| TR20 | **PASS** | 9 | terminal closed mid-sentence → the sentence is pasted at the caret (Victor's Q4, 2026-09-26), no 'delivered' row for the dead tty | B=ttys013 closed while listening; to=caret; rows=[]; gone logged=True; bound after=None; awaitingBind=False; pasted into the sink=True |
| TG8 | **PASS** | 13 | 🔼← F11 in the settle throws the sentence away. Predicted defect (§3.2, R2): `🗑️ Cancelled`, then the words are delivered anyway (`📦 delivery` after the cancel line) | cancel line=True, lastDelivery={'to': 'caret', 'at': '2026-09-26T12:46:06.252Z', 'kind': 'route', 'via': 'test'}, witness got 0 chars · sent forward-right@3.530s forward-right@10.927s forward-left@11.043s |
| TG9 | **PASS** | 10 | F11 in the settle of a spawn sentence throws it away. Predicted defect: delivered anyway, and to the bound terminal / caret, not `spawn:` (the cancel cleared the spawn flag only) | cancel line=True, delivered after it=False, to='caret' · sent forward-up@2.231s forward-right@8.538s forward-left@8.648s |
| TL10 | **PASS** | 25 | R2: cancel during the upload → no delivery, WAV in cancelled/ (today: delivered after 'Cancelled') | phase at cancel 'uploading'; after cancel: delivery False, 'audio kept' True, recoverable True; witness 0 chars |
| TL11 | **SKIP** | 2 | R2 local (through the fallback, engine unchanged): helper SIGSTOP, stop, cancel, SIGCONT → today delivered after 'Cancelled' | local helper not up ({'pid': None, 'loading': False, 'ready': False, 'alive': False}) |
| TL16 | **FAIL** | 22 | 3 s of silence → 'returned no words', the WAV kept for Recover (fixed 2026-09-26, §3.8: an empty answer is `.failed` with the audio, so the local model tries it first; the BUG branch is the old loss) | no-words line True, ↪️ True, audio kept False, recoverable False, delivered True |
| TR10 | **PASS** | 20 | fallback with a cold model (helper SIGKILLed first) → delivered before fallbackCeiling (180 s) | delivered 10.6 s after stop via local-fallback, 'did not come up' False, helper now alive True pid 338 |
| TR13 | **PASS** | 31 | empty Scribe answer on 20 s of speech → nothing lost: the local model transcribes it (via local-fallback, the §3.8 fix routes an empty answer through `.failed`), or the WAV is staged and Recover returns it | 'returned no words' True; the local model stood in — via local-fallback to terminal:ttys013 |
