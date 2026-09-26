# Test plan run — 2026-09-26 13:29

Verdicts: **PASS** = the app does what the plan expects · **BUG** = the plan's prediction of a defect was confirmed · **FAIL** = neither the expectation nor the prediction · **SKIP** / **ERROR**.

BUG 5 · FAIL 1 · PASS 3

| case | verdict | s | expectation | observed |
|---|---|---|---|---|
| TL16 | **BUG** | 10 | 3 s of silence → 'returned no words', no ↪️, nothing kept in cancelled/ (documents the loss, §3.8) | no-words line True, ↪️ False, audio kept False, recoverable False, delivered False — the audio is gone |
| TL29 | **BUG** | 16 | live socket drop mid-sentence (fault live:drop) → ≤ 1 'send failed' line (today ~11/s); batch still delivers | drop injected True, 72 'send failed' lines (~9.0/s over ~8 s), batch via elevenlabs-scribe |
| TL30 | **BUG** | 13 | live socket that never opens (live:never-open stands in for no key) → today: band open and empty the whole sentence, `pending` grows unbounded (§3.14, F13) | band open 27/27 samples, max words 0, socket {'connecting'}, pending [0] → [70], batch via elevenlabs-scribe |
| TR9 | **PASS** | 13 | offline (transport ×2 + live drop) → ↪️, via local-fallback, no 'abandoned' | ↪️ True, abandoned False, via local-fallback, witness 229 chars |
| TR13 | **BUG** | 25 | empty Scribe answer on 20 s of speech → WAV staged, Recover returns it (fails today: 'returned no words', audio deleted) | 'returned no words' True, nothing recoverable |
| TR23 | **PASS** | 20 | three more chords during the settle (within 0.5 s) → no new dictation, one delivery | new microphones after the stop 0, deliveries 1, recording at the end False |
| TR24 | **BUG** | 18 | bind B during the settle → the words go where the latch said at the stop (A); R11 predicts they follow the bind | A (ttys011) 0 chars, B (ttys013) 229 chars, delivery to terminal:ttys013 |
| LC13 | **PASS** | 12 | live integration: band words > 0 while isRecording; the band closes when listening goes false | max band words while recording 9; after stop: listening false at 0.072 s, band closed at 0.072 s |
| B1 | **FAIL** | 12 | first live partial ≤ 2 s after speech starts (plan: ≤ 1.5 s) | first band word 5.31 s after the WAV started; socket open, chunks 62, segments 0, caught up 39 chunk(s) at session open |
