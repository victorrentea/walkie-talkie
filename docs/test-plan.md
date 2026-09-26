# Walkie Talkie — the test plan (ElevenLabs batch, ElevenLabs + Live, local Whisper)

Written 2026-09-26 from five adversarial read-only reviews (Opus) of the code, the journal and
`~/.walkie-talkie/relay.log`. Wispr Flow is out of scope. Nothing here has been run yet; every
"today:" line is what the reviewers read in the code, to be confirmed by the test that names it.

Sections: 1 objective · 2 state machine (2.5 input alphabet, 2.6 action × state) · 3 what is already
broken (fix or test first) · 4 races · 5 failure modes · 6 how tests are executed (routes, audio, Codex,
gaps) · 7 the suites (L lifecycle, D delivery, R regressions, LC band, G gestures) · 8 order of work.

---

## 1. Objective

Find every way a sentence is **lost, doubled, misrouted, or delivered late/silently**, and every
way the app **wedges** (frozen, dead gestures, "Transcribing…" forever), for the three recognisers
Victor uses now. Then keep those cases as regression tests that run from a desk (HTTP), with real
audio (once the injection gap is closed), or through Codex computer use for the GUI.

Two invariants every test asserts, whatever else it checks:

- `GET /test/state.lastDelivery.to` agrees with the tail of `~/.walkie-talkie/outbox.jsonl`.
- `awaitingBind == false` once `lastDelivery.to != "held"`.

## 2. The state machine

### 2.1 Variables that make a dictation (main thread unless noted)

| var | file:line | meaning |
|---|---|---|
| `listening` | AD:1070 | the relay has a sentence open |
| `settling` (+`settleGiveUp`, `settleEstimate`) | AD:513–527 | mic closed, words awaited |
| `fallingBack` | AD:558 | local model standing in for a failed cloud call |
| `pasteMode`, `caretPrompt`, `cleanSentence`, `submitAfterClean`, `spawnPending`, `spawnFolder` | AD:937, 962–964, 883, 893 | destination flags, set at the gesture |
| `latchedAtCaret`, `latchedMouse` | AD:2926–2932 | destination latched at mic close (**only caret-vs-not, never which terminal**) |
| `dictationInFlight`, `dictationStartedAt`, `pendingScreen/Shots/Selection/markerCues` | AD:779–780 (`stateLock`) | the envelope |
| `recordWhenSourceReady` | AD:3453 | gesture banked while the local model is cold |
| `recordWhenBound`, `bindInFlight`, `takeBindGrace` | AD:1038–1052 | **dead code** — never set / never called |
| `dictationCeiling` (600 s), `orphanFlush` (120 s) | AD:1081, 787 | backstops |
| `held`, `awaitingBind` (300 s), `cancelledAudio` (300 s) | AD:1086, 8452, 828 | panel hold · held for a bind · Recover staging |
| ELS `isRecording`/`phase`/`stream`/`opening`(audioQueue) | ELS:71–72, 59, 277 | ElevenLabs source |
| LWS `isRecording`/`phase`/`loading` | LWS:90 | local source |
| TR `proc`/`ready`/pipes | TR:63–86 | the mlx helper (`ready` read from main without a lock) |
| MR `isRecording`/`file`/`url`/`writtenFrames` under `lock`; `lifecycle` lock | MR:38–57 | the recorder |
| ELL `open`/`closed`/`pending`/`segments`/`partial`/`pcm`/`cutByte` | ELL | the live socket + batch corrections |
| `TerminalBinding.current` (NSLock) | TB:318, 508 | the binding |
| `quitDeferredSince`, `quitApproved`, `restartAsked` | AD:7900–7929 | QuitGate |

### 2.2 Reachable states

| name | listening | settling | src.isRecording | phase | mic open | notes |
|---|---|---|---|---|---|---|
| Idle unbound | F | F | F | idle/done | F | no overlay at all |
| Idle bound | F | F | F | idle/done | F | chip shows destination |
| Banked (local cold) | F | F | F | idle | F | `recordWhenSourceReady`; **uncancellable**, polls forever |
| Opening, deaf | T | F | T | listening | **F** | device open queued on `audioQueue`; speech here is lost |
| Recording (clean / prompting) | T | F | T | listening | T | band open under `eleven-live` |
| Closing | F | T | F | transcribing | T→F | stop queued on `audioQueue` |
| In flight | F | T | F | transcribing | F | upload / decode |
| Fallback | F | T | F | done("error") | F | `fallingBack` |
| **Orphan in flight** | F | **F** | F | **transcribing** | F | settle gave up (~32 s) while the reply is still coming |
| Cancelling | F | T | F | done("dismissed") | T→F | awaiting `.cancelled` |
| Prompt held | any | | | | | `held` ≠ nil (4–7 s; 1 s with autosend — **autosend is ON today**) |
| Held for bind | any | | | | | `awaitingBind`, 300 s of *awake* time |
| Recoverable | any | | | | | `cancelledAudio`, 300 s; **wiped by any restart** (`Outbox.prepare`) |
| Test-open | T | F | F | any | F | `/test/dictation/start` — no mic |
| Wedged | T/F | F | T/F | listening/transcribing forever | F | `audioQueue` or whisper queue blocked; `busy` forever |

### 2.3 Transitions (trigger → handler → queue)

- **start**: 🔼→/⌘⌃D (tap thread → global → main `toggleDictation` AD:3500), 🔼 click (`onPasteToggle` AD:1985), back click (`onCleanToggle` AD:2453), held right ⌘⌥ (AD:2471), menu, 🔼↑, bind-and-dictate, bind landing (AD:5152), banked poll (AD:3743). Guard `!listening && !isRecording && !speculative && !settling` (AD:3575) — **does not check `phase.isWaitingForWords`**; the side-button path does (AD:1989). `source.start()` opens the socket on main, queues the device open on `audioQueue`, then `didBegin` synchronously → `dictationBegan` (AD:2739): `abandonDictation` → book/capture → `probeRecentSelection` → `listening=true` → band → ceiling.
- **stop**: `endDictation` → `source.stop()`; `didStopListening` synchronous → `dictationStoppedListening` (AD:2866): latch, `beginSettling`; mic closes on `audioQueue`; ELS `phase=.transcribing` set before this runs (no gap). Also the 600 s ceiling.
- **words**: ELS `transcribe` (URLSession queue; retry on `global()`; result hops to main ELS:376); LWS blocking `read` on the whisper queue (TR:290–319) → main. `didTranscribe` → `deliver` (AD:3069) → `send`/prompt/commit/hold or caret paste; `didEnd(.delivered)` → `dictationEndedForGood` (AD:3306).
- **failure with audio** → `fallBackToLocal` (AD:3240): 0.5 s polls, 90 s model budget, 180 s settle.
- **cancel**: `cancelDictationInFlight` (AD:3968) from ✕, menu, 🔼←, `/test/cancel`, right ⌘⌥. While recording → `source.cancel()` → `.cancelled` → `keepCancelled`. **While in flight → only the relay's flags are cleared; the request keeps running and will deliver.**
- **engine switch**: `setEngine` (AD:447), refused only while `listening||settling||speculative||isRecording`; **not** while `phase` is transcribing after the settle gave up.
- **bind/unbind/spawn adopt/restart restore**: `showBound` with `deliberate` defaulting to **true** for `onBindTTY`, `restoreBinding`, `adoptSpawnedWindow` → they redirect a sentence in flight.
- **commit** (AD:8348): reads `terminal.target` **at commit time** (4–7 s after the mic closed).
- **sleep/wake**: only the tap canary runs at wake (AD:2349). All deadlines are `DispatchTime`/`asyncAfter` → they count awake time only; `MainStallGate` counts wall clock → false `🧊` after every sleep > 3 s.

### 2.4 Timers

| timer | value | armed / cancelled |
|---|---|---|
| settle give-up | 8 s steps; ~32 s while transcribing; 180 s while falling back (from mic close) | `beginSettling` / `endSettling` |
| dictation ceiling | 600 s | `dictationBegan` / `dictationStoppedListening` only |
| orphan flush | 120 s | booked at start and at every shot / `send`, `abandonDictation` — **not by stop, not by `listening`** |
| ElevenLabs request | 20 s **idle** per attempt, no overall limit; one retry after 0.8 s on transport/429/5xx, never after a timeout | |
| helper hello / decode | 180 s / 300 s — **not enforced** (checked only between blocking reads) | |
| fallback model-up poll | 0.5 s × 90 s | |
| banked-gesture poll | 0.5 s, **no limit** | |
| prompt hold | 4–7 s; 1 s under autosend | |
| held-for-bind · Recover staging | 300 s awake each | |
| F10 stop dwell | 2.0 s (HotkeyTap:1505) | |
| min recording | 0.35 s | |
| live socket: VAD commit | 1.5 s silence; batch correction after 3.0 s with nothing new | |
| restart gate | `busy` false + 10 s quiet; escapes: unreachable 60 s, stale `listening` 30 s; script waits ≤ 1800 s; QuitGate ≤ 600 s | |

### 2.5 The input alphabet (Logi mode, the default; keyDown swallowed, keyUp always passes)

| input | gate | handler | notes |
|---|---|---|---|
| ⏎ / ⎋ bare | `promptHeld` | send / cancel the held panel | ~~⏎ does not check the stamp; autorepeat after the first ⏎ passes through~~ — batch 4: stamped keys pass, the answering key's repeats are eaten |
| **bare F7 / F9** | always | halo style ±1 | swallowed system-wide, undocumented |
| ⌘⌃B | H2920 | bind toggle (global queue) | no mutual exclusion; two quick presses race |
| ⌘⌃D | H2941 | `toggleDictation` | no dwell/re-fire guard (F10 has one) |
| ⌘⇧P | H2960 | paste last | ⇧ released first → ⌘P repeats leak (Print) |
| ⌃⌥P | H3319 | +1 shot | **no autorepeat guard**; stale ⌘ makes it pass |
| right ⌘ + right ⌥ (`flagsChanged`) | H2611 | clean hold / Wispr PTT | tap-thread state, no stamp check → the app's own `flagsChanged` posts count as a release |
| unstamped key while the pair is held | H2644 | `.shortcut` quiet cancel | also fires on Options+ F-keys (unstamped) → **two handlers** |
| 🔼→ F10 | 0.6 s window, `openSentenceAge < 2 s` refused, ◀️ held → bind+dictate | `toggleDictation` | the one guarded gesture |
| 🔼← F11 · 🔼↑ F8 · 🔼↓ F9 | 0.6 s window (batch 4) | cancel (the held panel first, Q6) · spawn/convert · kamikaze toggle (the held panel too) | ~~no re-fire guard~~ |
| 🔼 F7 | ◀️ held ≥ 0.3 s → bind | caret prompt / stop | |
| 🔽 F6 | arm, `ownDictation`, `ownCleanSentence`, 0.8 s settle, `backUsesOwnEngine` | shutter / clean toggle / Wispr chord | |
| 🔽→ F5 | 0.6 s window; `ownDictation && ownCleanSentence` | stop + Return / Return | plain Return mid relay-prompt |
| 🔽← F3 · 🔽↑ F4 · 🔽↓ F12 | 0.6 s window (batch 4) | Wispr cancel or relay cancel · film · unbind | ~~no re-fire guard~~ |
| middle button (Logi) | `dictating && bare && !promptHeld && !left && !right`, 12 pt | crop drag | press **passes** to the app underneath (dial: a Chrome tab closes) |

Flags the tap decides on arrive from main through `syncBorrowedGestures` (`dictating`, `ownDictation`,
`ownCleanSentence`, `promptHeld`, `haloUp`, `bound`); only the Wispr arm is set synchronously on the tap
thread. Every handler hops `global.async` → `main.async` (a concurrent queue: microsecond-spaced inputs
can swap). `tapDisabledByTimeout` re-enables silently and reconciles nothing (`areaCropping`, PTT
flags, `leftDownAt`). Fail-open (`MainStallGate`) opens 3 s after the last heartbeat and stays open
while any button 0–4 is down in the session state. (Batch 4, 2026-09-26: uptime clock, 0.1 s beat,
a 10 Hz watchdog, the real stall length at the close, the app's own chords dropped while open, every
swallow traced.)

### 2.6 Action × state (the cells that are wrong or undefined; full matrix in the gesture review)

| gesture | S2 relay prompt | S3 clean (own engine) | S3w adopted Wispr | S4 settle | S5 panel | S8 cold bank |
|---|---|---|---|---|---|---|
| 🔼 F7 / 🔼→ F10 | stop | stop / "↪️ to X" flash but words go to caret | Engine≠Wispr: `stop()` no-op | silent no-op / "nothing to start" | new sentence, panel keeps counting | re-bank, overwrites spawn/paste/clean |
| 🔼← F11 / 🔽← F3 | cancel | cancel | relay-side only, Wispr keeps recording | **"Cancelled" then delivered** | nothing, panel **sends** | nothing, bank survives |
| 🔼↑ F8 | bound: convert; caret/spawn: silent | silent | | silent | new spawn | convert |
| 🔼↓ F9 | toggle (re-fire untoggles) | row lights then dropped | | toggle | ignored though uncommitted | ignored |
| 🔽 F6 | shutter | stop | **shutter** | misleading banner | new clean | re-bank, `clean` dropped |
| 🔽→ F5 | **live Return mid-dictation** | stop + Return (stray Return inside the sync gap) | **plain Return while Wispr listens** | Return before the words (Wispr) | **sends the panel** (stamped Return → ⏎ branch) | Return |
| 🔽↑ F4 · wheel drag | film / crop | allowed then dropped at `cleanLine` | | stop only / refused | flash / refused | flash |
| 🔽↓ F12 | bound → caret at close | nothing | | → `awaitingBind` | commit → `awaitingBind` | caret |
| ⌘⌃B / ◀️+F7 | bind, redirect | chip lies (caret forced) | | recipient changes | recipient changes | bank continues |

Other states: S6 held-for-bind is released by any bind; S9 crop can outlive the sentence (ceiling, ⌘⌃D);
S10 rebind panel: 🔽→ activates the selected row; S11 quit pending: gestures still start sentences; S12
fail-open: ⌘⌃D → dictionary, ⌘⇧P → VS Code palette, F-keys → escape sequences in the Claude prompt.


## 3. Already broken by reading (fix, and keep the test)

Ranked by how a sentence is lost. Each has a test in §7.

1. **The settle gives up at ~32 s while the recogniser still works** (AD:3407) and a new start is then allowed (AD:3575 checks `settling`, not `phase`). The late reply consumes the new sentence's flags, shots and destination, sets the new sentence's `listening=false` while its mic is open. → T-L8, T-L15.
2. **Cancel during upload/decode/fallback cancels nothing** — no URLSession handle, `deliver` never checks. "🗑️ Cancelled", then the words land. → T-L10, T-L11.
3. **Unbound real sentence pastes at the caret** (`latchedAtCaret` AD:2884 → caret branch) while the chip says `bind to send`; `holdForBind` is reached only through `/test/dictation`, so desk tests hide it. → T-D3, T-D31.
4. **`bind(tty:)` never fails** (TB:345–368 always returns a Target): dead ttys are bound, restore/pick failure paths are dead code, a sentence released into a dead tty ends `targetGone` with the outbox row already written. → T-D1, T-D28.
5. **Restores, spawn adoption and `onBindTTY` count as deliberate binds** → redirect a sentence in flight, take back `pasteMode`/`spawnPending`. → T-D4..7.
6. **The 120 s orphan flush fires mid-sentence** (no `listening` check, AD:4461): context, selection, markers, `dictationStartedAt` gone; shots go out alone. → T-L1, T-D8.
7. **Dead mlx helper**: `ready` stays true (TR:292); next write → SIGPIPE, and nothing ignores SIGPIPE → the app probably dies. Hung helper: phase `transcribing` forever, `busy` forever, restart blocked 30 min. → T-L5..7, T-L31.
8. **Audio deleted on two paths**: empty Scribe answer (ELS:382–390) and nil helper answer → `.silent`, `removeItem(wav)`; no fallback, no Recover. 60 s of speech gone on 09-19 and 09-20. → T-L16, T-R13/14.
9. **Recover always uses the local model and never loads it** (AD:4148) → "No words detected" with Engine = ElevenLabs. → T-L17.
10. **Engine switch after the settle expired drops the transcript** (callbacks nil-ed, WAV left in Caches forever). → T-L9.
11. **Outbox gives false receipts**: row written at commit, before delivery; dead terminal, shell guard, failed spawn all keep "delivered" rows (three real cases 09-23/09-25). → T-D13, T-R20..22.
12. **Held sentence survives sleep** (uptime clock) and **a second held sentence deletes the first** (also from ⌘⇧P). → T-D2, T-D23, T-L28.
13. **Shell guard is a local snapshot**: `ssh`, `sudo -s`, `script`, `docker exec`, pagers pass; `less` + a `q` in the sentence executes the rest in zsh; Claude Code modals are not detected. → T-D15..17.
14. **Live socket after a drop**: one error line per buffer (~11/s) for the rest of the sentence; `pending` unbounded before `session_started`; band open with no key. → T-L29, T-L30.
15. **`MainStallGate` uses wall clock** → `🧊 195 s` on 09-25 was a lid-closed sleep; fail-open for ~0.5 s after every wake. → T-R5.
16. **`SessionLabel.gitBranch` runs `/usr/bin/git` synchronously on main every 10 s with no timeout** (seen in the 09-25 hang sample). → T-R29.
17. **projectM SIGSEGV (4 crashes 09-21 19:43) has no recorded fix**; `haloEngine` is `native` again. → T-R16.
18. **Gestures (tap):** cancel in the settle delivers anyway (same as 2, from every cancel path); **a cold local engine cannot be aborted** (`recordWhenSourceReady` ignored by cancel and by the start guard → re-bank overwrites spawn/paste/clean; the resumed start drops `clean`, so a back-click sentence becomes a caret prompt with a context shot); **adopted hand-started Wispr sentences disable every tap branch meant for them** (🔽 = shutter, 🔽→ = bare Return while Wispr listens); **🔽 then 🔽→ inside the main-sync gap types a stray Return** on your own engine (the Wispr arm is synchronous, the engine flags are not); **the panel's ⏎ branch ignores `backButtonStamp`** so the app's own Return sends a held panel; **bare F7/F9 are swallowed system-wide** (IntelliJ Step Into / Resume); **⌃⌥P has no autorepeat guard**; the key trace cannot see the app's own swallows (`return nil`, not `swallow()`); Wheel-mode `onMouse5Double` calls `endDictation` off main. → T-G.
19. Smaller: `pendingPromptWarning` leaks onto the next sentence; key hot-add reloads only `elevenSource`, not `elevenLiveSource`; `ElevenLabsSource.config` static dictionary raced between main and the retry queue; `mic-<epoch>.wav` names collide after a #10 orphan; `start()` guard returns silently (no log line) on a sticky flag.

## 4. Race conditions (merged, ranked)

| id | interleaving | symptom | repro |
|---|---|---|---|
| R1 | slow upload/decode > 32 s → settle gives up → new start → old reply lands | wrong pictures, wrong destination, new mic open with `listening=false` | throttle (T-L8) or `kill -STOP` helper (T-L11) |
| R2 | cancel while in flight | delivered after "Cancelled" | T-L10/11 |
| R3 | engine switch after R1 step 1 | transcript silently lost, restart allowed mid-upload | T-L9 |
| R4 | slow/failed mic open, stop arrives first | `.silent("")`, "under 0.35 s" lie | T-L20/21 |
| R5 | wedged `audioQueue` / helper | phase stuck, gestures refuse, `busy` forever | T-L31 |
| R6 | 120 s orphan timer in a long sentence | envelope wiped mid-sentence | T-L1 |
| R7 | banked local gesture + engine switch | ElevenLabs mic opens with no gesture; "Wispr Flow is not running" flash | T-L22/23 |
| R8 | device removed / format change mid-recording (no `AVAudioEngineConfigurationChange` observer) | silent truncation, wrong duration | T-L19 |
| R9 | sleep mid-dictation / mid-upload; uptime timers | ceiling/hold/recover stretched; socket dies; false 🧊 | T-L28, T-R5/7/8 |
| R10 | main stall coalesces start+stop | sub-0.35 s recording, no banner | T-L21 |
| R11 | bind/unbind/adopt/restore during settle or hold | recipient changes 4–7 s after mic close | T-D4..7, T-D29 |
| R12 | tab closed + tty reused within 10 s | binding silently moves to a stranger | T-D21 |
| R13 | destination app errors after typing (caret) | words pasted **twice** (AD:6287) | T-D-R3 |
| R14 | `deliver`→`endSettling`, `send` deferred one main turn | `busy` false for one turn; QuitGate/Dock restart (0.5 s polls, no quiet window) can kill in it | T-D24/25 |
| R15 | restart restores `bound-tty` read before a deferred quit; tmux client tty → active pane; IDE pty → "no Terminal.app tab" | wrong/dead binding after restart | T-D12..14 |
| R16 | two transcripts close together: fallback finishing after a new sentence opened; Recover during a settle; held + new | flags stolen, first held sentence gone | T-D26/27, T-D2 |
| R17 | `⌘⇧P` during the panel hold; clipboard restore 0.4 s later | previous sentence pasted; clipboard clobbered | T-D30 |
| R18 | `do script` + `\r` vs Claude Code input: review read-back fixed 0.35 s; the echo of the dictation itself matches "press Enter to send"; text half-typed by hand merges; modals; alternate screen; control chars not stripped | stray Return, unsent, executed | T-D18..20, T-D17 |
| R19 | live socket delivering after stop | guarded (`closed`, `stream === opened`) — safe | T-L29 as control |
| R21 | main-pushed flags vs tap decisions (only the Wispr arm is synchronous) | 🔽→ stray Return; second F10 inside the blind dwell; `openSentenceAge` measures the main edge | T-G6/7 |
| R22 | two-hop dispatch on a concurrent queue; `bindFrontmostTerminal` unguarded; `unbindTerminal` off main | 🔼+🔼→ reorder; ⌘⌃B×2 both bind; ⌘⌃B then F12 ends **bound** | T-G37 |
| R23 | blocking work on the tap thread (`Relaunch.stashBackStop` disk I/O, `Log`, CoreAudio reads, `proc_name`) → `tapDisabledByTimeout`, silent re-enable | missed press → ◀️+F7 becomes a caret dictation; crop overlay stuck | T-G25..28 |
| R24 | fail-open held open by a stuck session button; `/test/stall` holds no lock so it cannot reproduce a lock-holding stall | tap transparent for hours (the 7 h middle-button case) | T-G27 |
| R20 | batch correction (new, 2026-09-26) finishing after `stop()` or after segments changed | must be dropped (`closed` guard); `upTo <= segments.count` guard | T-LC-B3 |

## 5. Failure modes (taxonomy)

| id | trigger | mechanism | silent? | mitigation today | residual |
|---|---|---|---|---|---|
| F1 main-thread wedge | CoreAudio busy, lock order | device open / `removeTap` under lock on main; ABBA (09-24 32 min) | was; now `🧊` + sample | `audioQueue`, lifecycle lock, `lock.try()`, `MainStallGate` fail-open | git on main; `WindowContext` `main.sync` |
| F2 crash mid-dictation | projectM, NSNumber, UI off main | SIGSEGV/SIGTRAP | yes (only `.ips`) | partial | projectM unfixed; in-flight WAV not recovered at relaunch |
| F3 relaunch mid-sentence | redeploy, Dock, crash | process ends with recorder/settle open (71 relaunches with a dictation open since 09-01) | yes | restart gate + QuitGate | SIGKILL/crash; caret sentences have no outbox row |
| F4 recogniser returns nothing | helper dead/desynced, empty Scribe, silent device | `.silent` + `removeItem` | semi | none | **audio destroyed** |
| F5 cloud unreachable | offline, hotel Wi-Fi, 5xx/429, bad key | retry once, then fallback (never run live) | no | `c04aa2b` | non-timeout failure ~19 s + retry passes the 30 s settle before `fallingBack` |
| F6 destination fails after the receipt | terminal closed, agent at shell, spawn fails | outbox written then flash only | effectively | shell guard, ⌘⇧P | sentence not held; `checkAlive` skipped while busy |
| F7 sticky state → dead gesture | harness leftovers, cancel with nothing | `startDictation` guard returns silently (21 minutes on 09-20) | yes | ceiling 10 min | no log line |
| F8 tap inert/open | re-signed build, wake, stall, TCC loss | canary; fail-open | flash | canary + `bundle=` | wake false alarms |
| F9 mic surprise | unplug, 96 kHz XLR, `'nope'`, BT HFP | falls to system input (maybe virtual → silence) | until F4 | ladder, `neverRecord` | device read once at start |
| F10 TCC identity loss | concurrent builds (no Info.plist), path launch | grants keyed to path | flash | verify in `build-app.sh` | two builds not prevented |
| F11 destination races | bind/spawn/pick during settle | wrong-moment latch | yes | (dead) grace code | see R11 |
| F12 sleep/wake | lid closed mid-anything | uptime vs wall clock | mixed | wake canary only | no wake handler |
| F13 live caption | socket drop, no key, Turkish | caption only, never the delivery | log | pinned `ro`+`en`, keyterms | error storm; band open with no key |

## 6. Execution layer

### 6.1 Control surface

`http://127.0.0.1:8917` (first of 8917–8919 whose `/up` answers). Full route table with JSON is in
`.claude/rules/desk-testing.md`; routes it does not list: `/up`, `/chrome/reload`, `POST /engine`,
`/test/halo`, `/test/local-fallback`, `/test/live-caption {"text","partial"?,"gentle"?,"on"?}`,
`/test/bridge`, `/test/key-guard`, `/test/ax-insert`, `/test/about`. `GET /test/state` carries
`liveCaption {open, words, committed, dropped, anchor, lineWidth, shownWidth, velocity, bandWidth,
reflowing, corrections, correcting[], ghosts[], opacity[], eraseFront}`.

Prelude for every scripted run (save as `$W/wt.sh`; the witness tab runs `cat`, a non-shell
foreground, so the guard lets deliveries through and the text lands in a file):

```bash
W=${W:-$TMPDIR/wt-plan}; mkdir -p "$W"
PORT=$(for p in 8917 8918 8919; do curl -s -m2 http://127.0.0.1:$p/up | grep -q '"ok":true' && { echo $p; break; }; done)
B=http://127.0.0.1:$PORT; LOG=~/.walkie-talkie/relay.log
get(){ curl -s -m 5 "$B$1"; }
post(){ local b="${2:-}"; [ -n "$b" ] || b='{}'; curl -s -m 20 -X POST "$B$1" -H 'content-type: application/json' -d "$b"; }
js(){ get /test/state | python3 -c 'import json,sys; d=json.load(sys.stdin); print(eval(sys.argv[1]))' "$1"; }
[ "$(js 'd["busy"]')" = False ] || { echo "relay busy: $(js 'd["busyWhy"]')"; exit 2; }
TTY=$(~/bin/hands-off run "deschid un tab de Terminal-martor în care relay-ul va scrie propozițiile de test; fără click-uri" -- \
  osascript -e "tell application \"Terminal\" to set t to do script \"printf '\\\\e]0;wt-witness\\\\a'; stty -echo; exec cat >> $W/witness.txt\"" \
            -e 'tell application "Terminal" to get tty of t')
post /bind "{\"tty\":\"${TTY#/dev/}\"}"; post /engine '{"id":"eleven-live"}'
MIC0=$(get /engine | python3 -c 'import json,sys;print(json.load(sys.stdin)["mic"]["chosen"])')
# cleanup: /test/cancel only if listening||isRecording · /test/mic {"id":$MIC0} · /unbind · close the witness window · never leave awaitingBind
```

Every `/test/gesture` synthesises input → the whole scenario runs under `~/bin/hands-off run "<what and why, for Victor>" -- …` and `caffeinate -disu -t 900`.

### 6.2 Real audio

**Fact that decides everything:** `InputDevice.resolve()` walks xlr ▸ rx ▸ stage ▸ bose ▸ mac and
only falls back to the system default when none is present; the built-in mic is always present, so
**the relay's recorder cannot be pointed at a virtual device today**. `POST /test/input` moves only
the *system* default (Wispr follows it, the relay does not). `/test/dictation/start` opens no mic.

- **Today, acoustic only:** `afplay` into the room → built-in mic. Needs the speaker unmuted
  (it is muted on purpose), Victor away, and Victor's OK — **never at night** (refused 02:20).
- **G1 (small, unblocks everything):** `POST /test/mic {"device":"<CoreAudio substring>"|null}` —
  a process-local override checked first in `resolve()`, not written to `mic/choice`, cleared on
  restart, shown as `/engine.mic.override`. Pair with a Loopback device **"🧪 WT Inject"**
  (Pass-Thru only, no ladder needle in its name). Test pass-thru with the 440 Hz check before each
  run (Loopback pass-thru dies silently; toggle the device by hand to revive).
- **G2 (deterministic):** `POST /test/feed {"wav","realtime":true,"gain","clip"}` → 4096-frame
  16 k buffers from the file through `MicRecorder.append`'s post-conversion path (file, meter,
  `onBuffer` → live socket).
- Below the microphone: `tools/eleven-test.sh wav scribe_v2` (recogniser alone; pass the model,
  the script does not read `elevenlabs.env`'s model), `POST /test/local-fallback {"wav"}`,
  `POST /test/dictation {"text","words"}` (delivery with real Scribe timings).
- Corpus: 3,554 rows / 24.3 h, all 16 kHz mono s16; clips: 3.5 s EN `2026-09-18/21-05-35-11l735.wav`;
  ~3 min RO `2026-09-15/00-44-22-local695.wav`, EN `2026-09-18/23-59-48-11l129.wav`; clipped
  `2026-09-21/14-06-35-11l992.wav`. Silence: `ffmpeg -f lavfi -i anullsrc=r=16000:cl=mono -t 20`.
- WER: `jiwer` is absent; the plan's Python `wer()` (edit distance on NFKC-lowercased tokens).
  Baseline = the same model with no channel (`eleven-test.sh`); report channel WER (≤ 0.10
  Loopback, ≤ 0.25 acoustic, to calibrate) and model drift vs the corpus `.txt`.
- Every test WAV becomes a **corpus row in a never-pruned corpus** → G10 (`"harness":id` stamp)
  before bulk runs; record ids in the run report.

### 6.3 GUI via Codex (`codex exec`)

Needs a GUI: menu rows (Engine, Mic, **Autosend**, Recover, Rebind to…, Disconnect), prompt
panel Send/Cancel (**invisible to screenshots**: `sharingType = .none`; compute from
`CGWindowListCopyWindowInfo`: panel at visible top-left (24, 38+24), Cancel 116×28 bottom-right,
Send 128×28 to its left, 8 pt gap, 12 pt pad), the Rebind panel (anchor CG (864, 377.5)), a real
⌘⌃B/⌘⌃D, Loopback's device toggle. Status item = window `Item-0` (read x at runtime).

Wrapper: `caffeinate -disu -t 900 & ~/bin/hands-off run "<scenario>" -- codex exec
--dangerously-bypass-approvals-and-sandbox --skip-git-repo-check -C "$REPO" -o "$W/codex-S.txt"
"$(cat $W/S.prompt)"`. Preamble in every prompt: *no exploring, no screenshots unless told; drive
only the given System Events AX paths; verify each step with the given curl; stop at the first
mismatch; print one JSON `{step, evidence}`.* Scenarios S1 (Engine pick + refusal mid-sentence),
S2 (Mic submenu, greyed rows, `mic/choice` back to `auto`), S3 (Autosend off → Cancel → Send →
on), S4 (Rebind panel ↓/⏎), S5 (real ⌘⌃B toggle, `sessionFlags == []`), S6 (Recover row) — full
prompts in the harness report (`scratchpad`, to be moved under `evals/codex/`).

### 6.4 Gaps to close so the plan is automatable

| # | route | hook |
|---|---|---|
| G1 | `POST /test/mic {"device"}` override | `InputDevice.testOverride` in `resolve()`; `picker.onTestMic` AD:1616 |
| G2 | `POST /test/feed {"wav"}` | `MicRecorder.feed(url)` beside `insert(_:)` MR:507 |
| G3 ✅ 2026-09-26 | `POST /test/eleven {"fail":…,"delayMs","scope":"final|correction|any","lang":{code,p},"live":"drop|never-open|error:<type>","once"}` / `{"clear":true}` — T-L12 passed at 11:17 (401 → local fallback delivered in 7.3 s, cold model). Lesson: the first fault was eaten by the caption's rolling correction, hence `scope` (default `final`); a failed correction now holds 5 s before retrying (the 0.5 s timer re-uploaded 0.3 s after the failure) | `ElevenLabsSource.fault`, `settle()` in `transcribe`; `ElevenLabsLive.fault` |
| G4 ✅ 2026-09-26 | `POST /test/whisper {"kill"|"stop"|"cont"|"restart"}`; `/engine.whisper.alive,pid`; `SIGPIPE` ignored, `ready` cleared on EOF/EPIPE — verified 11:18: SIGKILL → the next request fails in 0.1 s with the app alive (pid unchanged), restart brings a new helper up in 3 s | `LocalWhisper.signalHelper`, `markDead` |
| G5 ✅ 2026-09-26 (batch 4) | `POST /test/prompt {"do":"send|cancel|edit","text"}`; state `prompt{held,verb,deadline,text,buttons,editing,paused}` | `picker.onTestPrompt`, `RelayWindow.promptState` / `testEditPrompt` |
| G6 | `POST /test/autosend {"on"}`; state `autosend` | AD:1316 |
| G7 ✅ 2026-09-26 (partly) | state: `fallingBack`, `autosend`, `lastFailure`, `recoverable`, `live{…}`, `elevenFault`, `elevenCost`, `micOpened`, `whisper` — done; `lastCorpus` and `liveCaption.frame/screen` still to add | `stateSnapshot` |
| G8 | `POST /test/live-caption {"script":[{at,text,partial,gentle}]}`, `{"trace":{"seconds"}}` → per-tick `[t,anchor,velocity,dropped,lineWidth,reflowing,eraseFront]` | `LiveCaptionBand.tick` |
| G9 | `POST /test/ceiling {"seconds"}` | `armDictationCeiling` |
| G10 | `POST /test/run {"id"}` → `"harness":id` on corpus rows and outbox lines | `VoiceCorpus`, `Outbox.send` |
| G11 | `POST /test/mic {"failNextOpen":true}` | `MicRecorder.start` |
| G12 | `POST /test/dictation/start {"mic":true}` / `/test/dictation/stop` — a real-mic dictation without `CGEventPost` | `status.onStartDictation` |
| G13 | `WT_ELEVEN_URL` env → a local fault server (stall, 5xx, RST) | ELS:539 hard-coded URL |
| G14 | `POST /test/source-end {"end":"silent|failed","wav"}` | `didEnd` injection |

## 7. The suites

Tags: **[HTTP]** routes only · **[TTY]** scripted Terminal tab / tmux · **[CC]** a real Claude Code
(haiku) session · **[AUDIO]** real audio (acoustic today; G1/G2 later) · **[NET]** `pfctl`/`dnctl`
or mitmproxy (URLSession follows the system proxy) or G3/G13 · **[HW]** device / sleep ·
**[CODEX]** computer use. Run only when `busy` is false and Victor is not dictating. Cases that
kill or relaunch the app (T-L6, T-L23, T-R17) need Victor idle.

### 7.1 T-L — lifecycle (ElevenLabs batch, + Live, local)

1. [HTTP] Orphan flush mid-sentence: `/test/dictation/start`, `/test/area`, wait 121 s → expect `dictationStartedAt` non-null; today null + "releasing 1 shot(s)" while `listening`.
2. [HTTP] Cancel of a test-open sentence → within 200 ms `listening`/`settling` false, "nothing to cancel" line.
3. [HTTP] `POST /engine` refused mid-sentence; accepted after cancel (`whisper.loading:true`).
4. [HTTP] `/test/local-fallback` happy path: `via:local-fallback`, ~6 s cold / ~2 s warm.
5. [HTTP] Helper hang: `kill -STOP` helper → `/test/local-fallback` returns only at the 180 s semaphore, no "timed out after 300s" ever; after `-CONT` the stale answer is consumed.
6. [HTTP] Dead helper → SIGPIPE: `kill -9`, `/test/local-fallback` → expect `{ok:false}` + "went away"; probable today: app dies (crash report). Relaunch via `open`.
7. [HTTP] Dead helper still `ready:true` in `/engine`.
8. [AUDIO+NET] R1: throttle to 32 Kbit/s, 30 s clip, stop; at ~32 s `settling:false, phaseStatus:uploading, busy:true`; start S2 + `/test/area`; unthrottle → today: "dictation abandoned (a new dictation started)", S1's outbox has S2's `screen`, `listening:false` with `isRecording:true`, no "ring down" for S2.
9. [AUDIO+NET] R3: as 8 until `settling:false`, `POST /engine whisper` accepted, unthrottle → "elevenlabs: … chars" with no outbox line, WAV left in shots.
10. [AUDIO+NET] R2 cancel during upload → `lastDelivery.at` later than the cancel; expect no delivery + WAV in `cancelled/`.
11. [AUDIO] R2 local: `kill -STOP` helper, stop, cancel, `-CONT` → delivered after "Cancelled".
12. [NET] 401 (bogus key; re-pick engine so `prepare` reloads) → "HTTP 401", "↪️ on this Mac instead", outbox `via:local-fallback`, warning row; then a back-click sentence, then a restored-key sentence → today the stale warning shows on it. Restore the key file.
13. [NET] transport error retried once (`block return`): "attempt 1 failed … retrying", failure ≤ 2 s, fallback delivers.
14. [NET] blackhole (`block drop`): failure at 20±1 s, no retry, "still uploading — 8 s in", fallback.
15. [NET] inconsistent start gates during an orphan upload: `forward-click` refuses ("still in flight"), `forward-right` starts.
16. [AUDIO] empty transcript policy: 3 s room tone → "returned no words", no `↪️`, nothing in `cancelled/` (documents the loss).
17. [AUDIO-lite] Recover with the model down → "produced no transcript", file still present.
18. [HTTP] restart gate ignores Recover staging (`--dry-run` → `busy:false` → restart would wipe `cancelled/`).
19. [HW] unplug the mic mid-sentence → log says 10.x s, file has ~5 s, no warning.
20. [HW] open latency (Bose after 5 min idle): "recording started" → "mic: recording through" ≤ 300 ms, else speech clipped.
21. [HTTP+AUDIO] stall coalescing: `/test/stall 6`, start+stop inside → "under 0.35s" or dwell refusal; no banner today.
22. [HTTP] R7: `POST /engine whisper` then `forward-right` immediately (banks), `/test/cancel` → nothing to cancel; `POST /engine eleven` → within 0.6 s `isRecording:true` with no gesture; with no key: flash says "Wispr Flow is not running".
23. [HTTP+env] broken Python runaway: `RELAY_WHISPER_PYTHON=/nonexistent`, `POST /engine whisper`, gesture → ≤ 1 "did not come up" line per 10 s expected, ~20 today.
24. [HTTP] 10-min ceiling on a test sentence at 600±1 s.
25. [AUDIO] 10-min ceiling on real audio; record `via` (measures the 20 s idle-timeout hypothesis on long WAVs).
26. [HTTP] held sentence + expiry at 300 s ("held dictation expired").
27. [HTTP] held sentence released by `POST /bind {"tty"}` within 1 s.
28. [HW] held across sleep (`pmset sleepnow`, 6 wall-clock min) → today still `awaitingBind`.
29. [AUDIO] live socket drop (Wi-Fi off 3 s) → ≤ 1 "send failed" line expected, ~11/s today; batch still delivers.
30. [AUDIO] live with no key → band open the whole sentence, no "connecting" line.
31. [AUDIO] stuck phase blocks gestures and restart: `kill -STOP` helper, dictate, wait 35 s → `settling:false, phase:transcribing, busyWhy:[transcribing]`, `--dry-run` blocked.
32. [AUDIO] normal cancel keeps the audio: "N s of audio kept", one `cancelled-*.wav`.
33. [GUI] key hot-add under `eleven-live` → "key went away mid-sentence" + `local-fallback` until re-picked.

### 7.2 T-D — delivery, binding, restart

1. [HTTP] dead tty accepted: `POST /bind {"tty":"ttys999"}` → 200 (expect 409); then `/test/dictation` → outbox `terminal:ttys999`, "is gone", `bound=null`, `awaitingBind=false` (lost).
2. [HTTP+TTY] second held sentence replaces the first silently; a bind delivers only BRAVO.
3. [AUDIO] unbound **real** sentence goes to the caret (sink on) while the chip says `bind to send`.
4. [HTTP+TTY] bind B during the hold of a sentence latched to A → lands in B.
5. [HTTP] restore takes back the caret (`pasteMode` false + "caret dictation redirected").
6. [HTTP] restore takes back a spawn (`spawnPending` false + "spawn dropped").
7. [TTY+CC] two spawns in a row → #2's words in window #1.
8. [HTTP+TTY] orphan flush mid-sentence sends a bare screenshot message to A.
9. [HTTP] 10-min ceiling unaffected (control for 8).
10. [HTTP] gate vs held sentence: `--dry-run --max-wait 20` → exit 3 "held for a bind".
11. [HTTP] gate stale-flag escape at ~30 s with `listening:true`.
12. [HTTP+TTY] deferred quit restores the **old** tty (bind B after SIGTERM, cancel, relaunch+rebind A).
13. [TTY] tmux restore picks the active pane, not the bound one.
14. [TTY] IDE-like pty restore → "no Terminal.app tab on", `bound=null`.
15. [TTY] guard bypass: `script -q /dev/null /bin/zsh` / `ssh localhost` → `touch` executes.
16. [TTY] pager `q` escape: `less`, sentence "quick check; touch …" → zsh runs the rest.
17. [CC] permission dialog: a haiku session asked to run `touch`; dictate "2 no stop" → does the file exist, did the words become a prompt.
18. [CC] review Return positive (400 chars → "a third Return").
19. [CC] review Return false positive (40 chars containing "press Enter to send").
20. [TTY] raw bytes: 5000 chars with quotes, `$(date)`, backticks, `\u0003`, `\u001b[201~` → chunk count, `\r` count 2–3, control bytes raw.
21. [HTTP+TTY] tty reuse within 10 s → binding silently moves to B.
22. [HTTP] expiry vs bind boundary at 298.5 / 299.5 / 300.2 s → one invariant outcome, recorded.
23. [SLEEP] hold across sleep → delivered after wake (today).
24. [AUDIO] `busy` flicker: poll every 20 ms across a real sentence → at least one `false` between first busy and the panel (R14).
25. [TTY+CC] spawn not in the blockers: `busy` goes false before `bound.tty` is the new tty.
26. [AUDIO] fallback cross-contamination: no key; during `settling` `/test/replace-wispr on` + `/test/dictation/start` → sentence 1 to caret, `pasteMode` false after.
27. [AUDIO] Recover steals state: cancel, `/test/recover`, then `/test/dictation/start`+`/test/area`+`/test/spawn-folders` → recovered text carries the area/spawn.
28. [CODEX] Active Terminals pick on a closed tab → bound to a dead tty, sentence lost.
29. [HTTP+TTY] unbind during the hold → `awaitingBind`, B receives.
30. [CODEX/keys] ⌘⇧P during the panel hold pastes the previous sentence; after restart, the newest outbox line even when the last went to the caret.
31. [HTTP] test-route fidelity: `/test/dictation` unbound → `held`; real speech unbound → `caret`. **Any suite built on `/test/dictation` misses the latch.**

R3 (caret double paste): [TTY] make Terminal error after typing (quit Terminal mid-`do script`) → words pasted twice.

### 7.3 T-R — regressions from the incident catalogue (still applicable to EL/local)

1–2. ABBA on cancel (09-24, 32 min freeze): 50 cancels at random 0–300 ms offsets while buffers flow, local then EL → `/test/state` answers within 1 s each time, no `🧊`, "audio kept" each time.
3. Device open on a wedged CoreAudio (`kill -STOP coreaudiod` 10 s) → `.failed`, not a freeze.
4. Fail-open proves itself (`/test/stall 6` + gesture) → `🧊` within 3.5 s, one `hangs/` file, no button left down.
5. Sleep is not a stall: `pmset sleepnow` > 10 s → no `🧊` line (fails today: wall clock; unit test `MainStallGate` with an injected monotonic clock).
6. Wake canary vs a gesture within 5 s of wake.
7. Dictation across sleep (60 s) → exactly one outcome; ceiling at 10 min wall time fires within 1 s of wake.
8. Upload in flight across sleep → words land once, original destination.
9. Offline → local fallback end to end (journal: "not yet tested") → `↪️`, `via:local-fallback`, warning row, no "abandoned".
10. Fallback with a cold model (`pkill -f whisper_helper.py` first) → delivery before `fallbackCeiling`.
11. Slow failure passes the settle ceiling (fault server: hold 19 s then RST, twice) → expected to fail today (30 s < 19+0.8+19).
12. 4xx not retried; 5xx/429 retried once (count "attempt 1 failed" lines 0/0/1/1), all end in fallback.
13. Empty Scribe answer keeps the audio (20 s speech, server answers `""`) → WAV staged, Recover returns it (fails today).
14. Helper dies mid-decode (`kill -9` 200 ms after stop) → `.failed` with audio, helper restarts, next sentence delivers.
15. Helper desync after a cancel (3 s, cancel, 3.6 s within 3 s) ×20 → no "gave no answer" (24 occurrences since 08-28).
16. projectM crash guard: `haloEngine native`, each preset, 30 dictations at 48 k and 16 k → pid unchanged, no `.ips`.
17. Restart gate: 30 s dictation, `relay-restart.sh` at t=5 and `kill -TERM` → no relaunch until 10 s after delivery; `kill -9` as the known-unguarded case (WAV of the killed take found at relaunch — not today).
18. Sticky `listening` is loud and short-lived → a log line naming the refusing flag (silent today), cleared well under 10 min.
19. Microphone after a cancel (`MicrophoneAfterACancel`) for EL and local at 0.2 s gaps.
20. Terminal closed mid-sentence → held or pasted, no "delivered to dead tty" row.
21. Agent exited to the shell → `⛔️ refused`, no delivery row, still pastable.
22. Spawn that fails → sentence re-offered, no `spawn:` receipt before the window exists.
23. Second gesture during the settle (×3 within 0.5 s) → no new dictation, one delivery.
24. Bind during the settle → words go where the latch said (per the rule).
25. Device switch refused → system input: chip shows the device actually recording; a silent-device sentence flagged, not uploaded as silence.
26. Device unplugged mid-sentence (F9) → no SIGABRT (09-01 format trap), `.failed` with the audio so far.
27. Filename collision `mic-<epoch>.wav` ×50 cancel/restart within a second.
28. TCC identity: launch line `bundle=ro.victorrentea.wispr-relay trusted=true eventTap=true`; two concurrent `build-app.sh` runs → one fails, never a bundle without Info.plist.
29. Git-on-main stall: stalled `.git` → no `🧊` over a minute of 10 s ticks (`SessionLabel.gitBranch` off main or bounded).

### 7.4 LC — the subtitle band (`POST /test/live-caption` + `state.liveCaption`, 20 Hz sampling)

Constants (07:50 layout): band 80 pt, `marginRight` 48, `dropSlack` 40, 38 pt bold; centred layout,
`ease` 0.45 s, `vMax` 700; `swap` 1.0 s (ghost 0.5), `correctionFade` 1.6, `reflow` 0.26;
`provisionalFloor` 0.4; `fadeIn` 0.22 (opacity, since batch 5); eraser after 5.0 s idle (2.0 until 2026-09-26 14:20), 260 pt/s, edge 160, letter by letter across the edge. `centre = anchor +
(visibleStart + visibleWidth)/2` where `visibleStart` = `eraseFront + 80` when erasing, else 0, and `visibleWidth`
(batch 5) is `shownWidth` with each appended word counted by how far it has come in (`appear`) — the
*visible* text; an invisible word just appended is not on screen. Case 2's end is `anchor + visibleWidth`.

1. First word appears centred: right after `{"partial":"Hello"}`, `|centre − bandWidth/2| < 3`, `velocity == 0`, opacity rising from 0 to 0.4 (provisional) within 0.5 s. No sample with `anchor ≥ bandWidth − 5`.
2. Growth to the right at 0.4 s/word for 20 s: centre stays within ±80 of the middle until the line is wider than `bandWidth − 96`; after that `anchor + shownWidth ≤ bandWidth − 48 + 2` on every sample; |Δanchor| ≤ 700·Δt + 2; no anchor increase except by a drop width.
3. Pause: `velocity → 0` within 1.5 s of the last word; centre unchanged until the eraser starts at 5.0 s.
4. Burst of 15 words at once: anchor eases (elastic, no step > 700·Δt), every sample `velocity ≤ 700`.
5. Correction that shortens ("fix the build today" → "fix it today"): `corrections += 1`, `ghosts == ["the","build"]` within 0.3 s, `[]` after 0.6 s, `correcting` empty after 2.7 s, `reflowing` > 0 then < 0.5 within 1.6 s; the centre glides, never steps.
6. Correction that lengthens ("500" → "five hundred"): `corrections += 2`, `ghosts == ["500"]`.
7. Revision past the dropped words (new line): `dropped == 0`, `words == 3`, placed centred at once (`velocity == 0` on the first sample), `ghosts == []`. 7b: change only inside the dropped region → `corrections` unchanged, `anchor` continuous.
8. Tail punctuation flicker and mid-line case/punctuation commits → `corrections` unchanged, `ghosts == []` (LCS on case-folded stems).
9. Append-only ×30 → `corrections == 0`; every appended word's opacity starts < 0.1 and reaches its target within 0.6 s.
10. `{"on":false}` fade and reopen within 0.15 s (see the previous version: `open` flips at once, `words == 0` after 0.6 s; reopen must not be reset by the completion handler).
11. Second display (needs G7 `frame`).
12. `RELAY_SHOOT` never shows it.
13. Live integration: `words > 0` while `isRecording`; closes when `listening` goes false.
14. Empty text while open → `words == 0`, still open.
15. Provisional tail: `{"text":"a b c.","partial":"d e f"}` → `committed == 3`, opacity ≈ [1,1,1,0.8,0.6,0.4] within 0.6 s; commit all → ≈ 1 within 0.8 s, `corrections == 0`.
16. Eraser + re-centring: feed, wait 2 s → `eraseFront` increasing ≈ 260 pt/s; centre of the *visible* text stays within ±80 of the middle while `dropped` grows; a new word freezes the front (no increase; decreases by drop widths only); after `eraseFront ≥ lineWidth` the next word is a fresh centred line, `eraseFront == null`.
17. Gentle correction (`"gentle":true`): `corrections += 1`, the eraser keeps sweeping (`eraseFront` still increasing), paler tint.
18. Timing precision and the two-display case need G8's server-side script/trace and G7's `frame`.

Live-socket cases (real audio, after G1/G2): **B1** partials arrive ≤ 1.5 s after speech; **B2** every VAD
commit → "💬 live correction: … → scribe_v2" line, `state.eleven.cost` grows, a `gentle` update on
the band with `corrections` ≥ 0 and the committed text replaced; **B3** stop during a correction
in flight → no update after `closed` (log shows the result discarded, no crash); **B4** correction
failure (G3 `fail:500`) → "next pause covers the span again", cut unchanged, next pause uploads the
longer span; **B5** menu row shows `$x.xx` growing by (live s × 0.39 × 1.2 + batch s × 0.22)/3600.

### 7.5 T-G — gestures and the tap (from `POST /test/gesture` [R], a CGEvent script [S] under `hands-off`, or a device/Codex [D]). Pre/post for each: `/test/key-trace on`, `sessionFlags == []` within 300 ms after every step; `WisprSink` as the front app that records stray keys.

1. [R] F7 idle → caret prompt (`pasteMode`, chip `at caret`); key trace has no `↓ key 98` line (blindness).
2. [R] F10 re-fire train at 0/300/600/900 ms → one start, three "re-triggered … dropped"; at 1.6 s "only NNN ms old — not stopping"; at 2.3 s stops.
3. [R] F11 cannot abort a cold bank (Engine whisper cold): no cancel line, mic opens ~10 s later.
4. [R] Cold back click becomes a prompt (context shot logged); second back click = shutter.
5. [S] Cold clean hold (right ⌘⌥ 12 s) → `listening:true` after release (never ended).
6. [R] 🔽 then 🔽→ at +60 ms on ElevenLabs → "🔽 → — Return", sink keycode 36, sentence still open; at +500 ms → correct stop.
7. [R] Same pair on Engine=wispr → correct at both gaps (asymmetry).
8. [R+audio] Cancel in the settle still delivers (`lastDelivery.at` > cancel).
9. [R+audio] Same with a spawn → lands in terminal/caret, not `spawn:`.
10. [R] F11 does not cancel the panel (outbox written after the hold).
11. [R] 🔽→ sends the panel (delivery within 1 s; trace "SWALLOWED by the prompt panel's ⏎ (ours)").
12. [R+audio] Clean-submit Return eaten by another panel → words in the sink, no 36; panel A sent early.
13. [R+audio] 🔼→ over a bound clean sentence → "↪️ redirected" flash but `lastDelivery.to == caret`.
14. [R] Kamikaze re-fire at +2.5/+2.8 s → toggled back off.
15. [R] Film re-fire → start+stop, "caught no frames".
16. [R] F9 during the panel → "ignored" though uncommitted.
17. [R] F8 on a caret sentence → silent.
18. [R+audio] Bind during the upload → chip promised the terminal, `lastDelivery.to == caret`.
19. [R] Rebind during the panel → delivered to B (docs imply A).
20. [R+audio] F12 during the settle → `awaitingBind`, then bind delivers (positive control).
21–24. [R] Adopted Wispr sentence (`/test/wispr-handsfree {"hand":true}`): 🔽← → "nothing to cancel", Wispr keeps listening; 🔽 → shutter; 🔽→ → keycode 36 in the sink while `wisprHearing`; 🔼/🔼→ → nothing.
25. [R] Stall queued vs leaked: `/test/stall 8`, F10 at +1.0 s (queued) and +4.5 s (leaks, sink sees ⌃⌥⌘F10); don't GET state during the stall.
26. [R] Canary during fail-open → `alive:false` + a V keyUp in the sink (misdiagnosis).
27. [S] Fail-open held open by a middle button held to +11 s; ⌘⌃D at +8 s leaks.
28. [R] Key-trace blindness for all ten gestures (one `↑ (ours) passed`, zero `↓`) — regression guard once swallows use `swallow()`.
29. [R] Stale-flag guard for every gesture plus `postWisprHandsFree` / `postReturn` / `postWisprCancel`.
30. [R] Debug-build guard: `/test/gesture` answers 200 with no effect → assert log lines, never the 200.
31. [S/D] ⌃⌥P autorepeat 1.5 s → many 📸 lines.
32. [S] ⌘⌃D with ⌃ released first → ⌘D ×5 reach the sink.
33. [S/D] Bare F7 swallowed globally (IntelliJ does not step).
34. [S] Left-held bind at 0.4 s → bound; at 0.25 s → caret dictation.
35. [D/S] Options+ F-key under a held right ⌘⌥ → `.shortcut` quiet cancel **and** a new clean sentence; `/test/gesture` under the same hold takes the release path instead (route/device divergence).
36. [R] 🔽→ with the rebind panel up → activates the selected row (undefined).
37. [S] ⌘⌃B ×2 at 150 ms → two binds, still bound (docs: bind then unbind).
38. [S/D] Halo dial passes the middle click (Chrome tab closes).
39. [S] Crop across the sentence end (F10 mid-drag) → where do the `area-*` files attach.
40. [R+audio] F6 in the settle → misleading "finish the sentence" banner.
41. [R] Engine switch during a bank → accepted; dictation opens on the new engine when the poll fires.
42. [R] 🔽 click with Wispr quit → does ⌃Space switch the macOS input source (`AppleSelectedInputSources` before/after).

## 8. Order of work

1. ~~Close G1 + G3 + G4 + G7~~ — done 2026-09-26 morning (G7 minus two fields). Real audio goes
   through `POST /test/mic {"device":"TO Wispr"}` + a `sounddevice` player into the Loopback
   (`scratchpad/looprun.sh` is the working prototype; move it under `evals/plan/`).
2. Run **T-L 1–7, 22–24, 26–27**, **T-D 1, 2, 5, 6, 10, 11, 29, 31**, **T-G 1–4, 6–7, 10–11, 14–17, 19, 25–26, 28–30, 36, 41**, **LC 1–17** — all pure
   HTTP, today, in one script (`evals/plan/run-http.sh`, to write), each case leaving the relay as
   it found it.
3. Fix the ranked list in §3 as the tests confirm it (1, 2, 6, 7, 8 first — they lose sentences).
4. **Audio suite** through G1/G2: T-L 8–11, 16, 29–32, T-D 3, 24, 26, 27, T-R 1–2, 9–15, 23–24,
   B1–B5. Not through the speaker.
5. **Codex GUI / CGEvent scripts**: S1–S6, T-D 28, 30, T-G 5, 27, 31–35, 37–39 (under `hands-off run`, `caffeinate`).
6. **Hardware/sleep** with Victor present: T-L 19–20, 28, T-R 3, 5–8, 19, 25–26.
7. Every case that passes becomes a row in `evals/plan/` with its route script; every one that
   fails becomes a journal entry with the fix commit.
