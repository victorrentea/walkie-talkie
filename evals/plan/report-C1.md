# Test plan run — 2026-09-26 13:26

Verdicts: **PASS** = the app does what the plan expects · **BUG** = the plan's prediction of a defect was confirmed · **FAIL** = neither the expectation nor the prediction · **SKIP** / **ERROR**.

BUG 2 · PASS 5 · SKIP 6

| case | verdict | s | expectation | observed |
|---|---|---|---|---|
| TD3 | **SKIP** | 0 | unbound real sentence is held for a bind, not pasted at the caret | needs real audio: /test/dictation skips latchedAtCaret (see TD31); run with cases_audio |
| TD24 | **SKIP** | 0 | busy never flickers false between the first busy and the panel (R14) | needs a real spoken sentence (deliver → endSettling → send one turn later) — [AUDIO] |
| TD26 | **SKIP** | 0 | a fallback finishing after a caret sentence opened does not steal its flags | needs a real sentence in the settle with no key — [AUDIO] |
| TD27 | **SKIP** | 0 | Recover does not pick up the area/spawn of the sentence opened after it | needs a cancelled real recording to recover — [AUDIO] |
| TG12 | **SKIP** | 0 | clean-submit Return eaten by another panel → words in the sink, no 36; panel A sent early | needs sentence A's panel held while a clean sentence B settles with its queued Return; two overlapping sentences cannot be staged deterministically from one Loopback — run by hand |
| TL10 | **BUG** | 28 | R2: cancel during the upload → no delivery, WAV in cancelled/ (today: delivered after 'Cancelled') | phase at cancel 'uploading'; after cancel: delivery True, 'audio kept' False, recoverable True; witness 81 chars |
| TL11 | **BUG** | 26 | R2 local (through the fallback, engine unchanged): helper SIGSTOP, stop, cancel, SIGCONT → today delivered after 'Cancelled' | after cancel + SIGCONT: delivery True, 'audio kept' False, recoverable True |
| TL12 | **PASS** | 21 | 401 → 'HTTP 401', '↪️ … on this Mac instead', via local-fallback (no retry); next sentence back on ElevenLabs | 401 True, ↪️ True, retries 0, via local-fallback in 1.8 s; next sentence via elevenlabs-scribe; the stale-warning half needs G5 (prompt state) |
| TL13 | **PASS** | 12 | transport error retried once: 'attempt 1 failed … retrying', failure ≤ 2 s after stop, fallback delivers | retries 1, failure → fallback 0.81 s after stop, via local-fallback |
| TL14 | **PASS** | 32 | blackhole (fake timeout after 20 s): failure at 20±1 s, no retry, 'still uploading — 8 s in', fallback delivers | failure 20.0 s after stop, retries 0, 'still uploading — 8 s in' True, via local-fallback (the fake's delay, not URLSession's own timeout — G13 for that) |
| TL16 | **PASS** | 8 | 3 s of silence → 'returned no words', no ↪️, nothing kept in cancelled/ (documents the loss, §3.8) | no-words line True, ↪️ False, audio kept False, recoverable True, delivered False |
| TL32 | **PASS** | 8 | normal cancel keeps the audio: 'N s of audio kept', one cancelled-*.wav | 'audio kept' 5.7 s, recoverable cancelled-13-28-32.wav exists True, delivered False |
| TR25 | **SKIP** | 0 | device switch refused → system input: the chip shows the device really recording; a silent device is flagged, not uploaded as silence | needs a refused CoreAudio switch (G11 failNextOpen or hardware); /test/eleven cannot inject it |
