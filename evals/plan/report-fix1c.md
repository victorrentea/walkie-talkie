# Test plan run — 2026-09-26 15:51

Verdicts: **PASS** = the app does what the plan expects · **BUG** = the plan's prediction of a defect was confirmed · **FAIL** = neither the expectation nor the prediction · **SKIP** / **ERROR**.

PASS 3

| case | verdict | s | expectation | observed |
|---|---|---|---|---|
| TL11 | **PASS** | 28 | R2 local (through the fallback, engine unchanged): helper SIGSTOP, stop, cancel, SIGCONT → today delivered after 'Cancelled' | after cancel + SIGCONT: delivery False, 'audio kept' True, recoverable True |
| TL16 | **PASS** | 9 | 3 s of silence → 'returned no words', the WAV kept for Recover, nothing delivered (fixed 2026-09-26, §3.8: an empty answer is `.failed(heardNothing)` with the audio, no local fallback; the BUG branch is the old loss) | no-words line True, ↪️ False, audio kept True, recoverable True, delivered False |
| TR13 | **PASS** | 29 | empty Scribe answer on 20 s of speech → WAV staged, Recover returns it (fails today: 'returned no words', audio deleted) | 'returned no words' True, staged cancelled-15-52-05.wav (22.81055200099945 s), Recover via test |
