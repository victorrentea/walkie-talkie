# Test plan run — 2026-09-26 13:11

Verdicts: **PASS** = the app does what the plan expects · **BUG** = the plan's prediction of a defect was confirmed · **FAIL** = neither the expectation nor the prediction · **SKIP** / **ERROR**.

BUG 5 · FAIL 1 · PASS 2

| case | verdict | s | expectation | observed |
|---|---|---|---|---|
| TL15 | **BUG** | 46 | during an orphan upload (settle gave up, phase transcribing) forward-click and forward-right agree; today: forward-click refuses ('still in flight'), forward-right starts | eleven-live: orphan window at 32.2 s after stop; forward-click refused, forward-right started; late reply landed, lastDelivery.to=terminal:ttys007 — the two start gates disagree; invariants ok |
| TL17 | **PASS** | 13 | Recover with the model down transcribes (brings it up); today: 'produced no transcript', file still present | staged 0.6 s at cancelled-13-12-13.wav; model before Recover ready=True alive=True; after: loading=False ready=True; outcome=recovered; file still present=False; witness 81 chars |
| TL18 | **BUG** | 8 | the restart gate blocks while audio is staged for Recover; today: --dry-run opens (busy:false) and a restart would wipe cancelled/ | staged 5.9 s; busy=False busyWhy=[]; dry-run exit 0 after 0.2 s (🧪 dry run: the gate is open — would quit pid 11073, relaunch, and re-bind nothing); recoverable still set=True — the gate opened over staged audio |
| TL21 | **BUG** | 10 | start+stop coalesced inside a 6 s main stall → 'under 0.35s' or a dwell refusal, and a banner; today: no banner | mic opened=True; 'discarded — under 0.35s'=True; dwell refusal=False; after the stall listening=False isRecording=False; banner rows=none — the stall coalesced start+stop into a silent sub-0.35 s discard |
| TL22 | **BUG** | 5 | a gesture banked on a cold local model is cancellable and dies with an engine switch; today: /test/cancel has nothing to cancel, and POST /engine eleven opens the ElevenLabs mic within 0.6 s with no gesture (no key: 'Wispr Flow is not running') | banked on whisper; /test/cancel had nothing to cancel; switched to eleven (key ready=True); ElevenLabs mic opened 0.22 s after the switch — the bank outlived the cancel and the engine |
| TR4 | **FAIL** | 14 | fail-open proves itself (/test/stall 6 + input) → 🧊 within 3.5 s, one hangs/ file, no button left down | nudge posted=True; silent line=3.7 s; back line=none; new hangs files=1; sessionFlags=[]; buttons down=[] |
| TR18 | **BUG** | 56 | sticky `listening` is loud and short-lived: a log line naming the refusing flag, cleared well under 10 min (today: silent, lasts to the ceiling) | log after the gesture: silent about it (2 line(s)); listening still up 45 s later |
| TR19 | **PASS** | 16 | MicrophoneAfterACancel: after a cancel, a start 0.2 s later opens the microphone — EL and local | eleven-live: ok→ok 0.22s, ok→ok 0.22s, ok→ok 0.21s; whisper: ok→ok 0.21s, ok→ok 0.21s, ok→ok 0.22s |
