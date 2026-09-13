# The loopback — one real dictation, driven and asserted

`tools/wispr-test.sh` asks *did a transcript come back*. This asks the two
questions a transcript cannot answer, and which are what the incidents of
**2026-09-13** were about:

- **did the words go where the gesture said they should**, or into whatever
  window happened to be in front;
- **did the ring come down when Wispr had finished**, or twelve seconds later.

```sh
tools/wispr-loop.sh caret-short            # one scenario
tools/wispr-loop.sh --all --json
tools/wispr-loop.sh caret-short --dry-run  # the steps, posting nothing
tools/wispr-loop.sh bound --verbose        # + every relay.log line the run produced
tools/wispr-loop.sh --all --wait-routes 600
tools/wispr-loop.sh sink-key-at-stop --repeat 3   # a race — one sample is an anecdote
```

Exit codes: **0** every assertion passed · **1** one failed · **2** a
precondition failed · **3** the running build has not got the loopback routes.

## The primitive everything stands on

```sh
tools/wispr-transcribe.sh clip.wav           # the sentence, on stdout
tools/wispr-transcribe.sh clip.wav --json    # + route and timings
```

**Feed Wispr an arbitrary WAV, print what it transcribed.** No scenario, no
assertions, nothing about destinations. The transcript goes to **stdout** and
everything else to stderr, so `$(tools/wispr-transcribe.sh f.wav)` is the
sentence and nothing else.

Exit: **0** a transcript · **1** nothing arrived · **2** a precondition failed ·
**3** Wispr itself said there would be nothing (`dismissed` / `empty` /
`no_audio`).

It differs from the scenarios in exactly one deliberate way: **the chord is
Wispr's own, not a relay gesture.** `POST /test/wispr-handsfree` makes the app
post `fn ⌃ Space`, so the relay sees a dictation *Victor* began by hand — it
draws the ring and watches, and routes the words nowhere. A relay gesture would
start a dictation *with a destination* and deliver the sentence to a terminal,
which is right for a scenario and wrong for a transcription. The run reports
`relayListening` / `relayRingUp` so a caller can see which of the two it got.

**Waiting on a condition, with two exits.** The sink is polled until its text is
non-empty **and has not changed for 300 ms** (`StableText`, `STABLE_MS`) —
because Wispr inserts some sentences in more than one event, and reading the
sink the instant the first one lands scores a half-written sentence as a bad
transcript. The other exit is Wispr's own `History` row reaching `dismissed`,
`empty`, `no_audio` or `error`: there is no transcript coming, and waiting out
the timeout for it is the twenty-second stall the `WisprHistory` work removed
from the app. The status is printed and the exit code is 3.

The scenarios call the same wait (`_settled_sink`) rather than reading the sink
once, so none of them can score a sentence Wispr is halfway through inserting.

### As a Python function, and what it means for the teacher batch

```python
import wispr_loopback as rig
heard = rig.transcribe("/path/to/clip.wav")     # -> {"ok", "text", "route", "timings", …}
```

`helpers/wispr_loopback.py` has **two** ways to put a WAV through Wispr now, and
they are not the same trade:

| | `dictate()` (2026-09-11) | `transcribe()` (2026-09-13) |
|---|---|---|
| the chord | synthesised here, `CGEventPost` | posted by the **app**, `POST /test/wispr-handsfree` |
| Accessibility | **this interpreter needs the grant** | not needed, not asked for |
| where the words land | whatever has focus — hence `paste_sink()` and an allow-list of harmless sinks | the relay's sink window, which it owns |
| the answer | read out of `flow.sqlite` | read out of the sink, with the route named |
| when it is done | polls for a new `History` row | the sink settling, or Wispr's own `dismissed`/`empty`/… |
| needs | Accessibility + a harmless front app | the relay running |

**`helpers/teacher_label.py` is the caller this was written for and is not
rewritten yet.** `docs/teacher-loopback.md` describes the batch as it stands:
play each corpus WAV into Wispr, read back what it heard, and store `asrText` as
the label. It was blocked on the microphone pin, which is now lifted. The switch,
when Victor wants it, is small:

- `rig.dictate(wav, idx)` → `rig.transcribe(wav)`; the returned dict's `text` is
  the label and `timings` replaces the hand-rolled stopwatch.
- `rig.accessibility_ok()` and the `rig.paste_sink()` allow-list **go away** —
  neither is a question any more once the app posts the chord and the relay owns
  the window the words land in. Hazards 1 and 2 of
  `docs/teacher-loopback.md` are answered by construction rather than by
  refusing to start.
- the 🔒 locks stay, and `tools/wispr-act.sh` is where that lives now.
- **one thing does not survive the switch:** the batch stores Wispr's **`asrText`**,
  the recogniser's raw reading, and deliberately *not* `formattedText`. The sink
  receives what Wispr **inserts**, which is the formatted text. So a batch that
  moves to `transcribe()` is training on a different column, and that is a
  decision about the corpus, not a refactor — see *What gets written* in
  `docs/teacher-loopback.md`. Until it is made, `dictate()` stays.

## How the loop works

```
   evals/fixtures/wispr-loop.json
            │ (a WAV of Victor's own voice + Wispr's own reading of it)
            ▼
   helpers/wispr_loopback.py · sd.play()
            │
            ▼
   ┌──────────────────────┐        ┌────────────┐
   │ Loopback virtual dev │──mic──▶│ Wispr Flow │
   │  out side → in side  │        └─────┬──────┘
   └──────────▲───────────┘              │ ⌘V, or an insertion no tap sees
              │                          ▼
   system default input          ┌──────────────────┐
   POST /test/input {"name"}     │  Walkie Talkie   │  ← tap swallows, routes
   (restored on EVERY exit)      └───┬────┬─────┬───┘
                                     │    │     │
                  /test/sink window ─┘    │     └─ spawn: a new Terminal
                     bound tty ───────────┘
            ▲                                         ▲
            │                                         │
   POST /test/gesture {"name": "forward-click"} ───────┘
   (the APP posts the real ⌃⌥⌘F-key chord — this script synthesises nothing)
```

Four things make it work, and each of them is load-bearing:

1. **Wispr on Auto-detect.** Its microphone is `prefs.user.overrideAudioDeviceId`
   — a salted Chromium hash, in a file Wispr's own process rewrites, which
   **nothing here may ever edit**. On *Auto-detect* it follows the **system
   default input**, and that is scriptable: `POST /test/input {"name": …}`.
   That one setting is the whole reason any of this is possible.
2. **A Loopback device whose output side feeds its input side.** `resolve_device`
   prefers `🎓 TO Wispr`, then `TO Wispr`, then the devices that already exist on
   this Mac. As of 2026-09-13 no `TO Wispr` device has been made, so it lands on
   `🎙️TO Zoom`, which is the same pass-through and works.
3. **The relay posts its own chords.** The app holds the Accessibility grant;
   this harness holds none and needs none. `POST /test/gesture` is the only way
   in, and a `.build/debug` relay is refused by the preflight because
   `CGEventPost` fails *silently* there.
4. **The sink.** `POST /test/sink {"on": true}` makes a relay-owned window key,
   so "whatever app is in front" is a window this harness can read and attribute
   to a route (`paste` · `ax` · `typed` · `keyDown`) instead of being Victor's
   editor.

Everything the run measures comes out of numbers the **relay already prints**.
`relay.log` timestamps have second resolution; the milliseconds live inside the
sentences (`⌘V from Wispr Flow — 294 ms after the microphone closed`), so every
interval is arithmetic over those offsets against one anchor — the microphone's
close — and never over the wall clock. When an offset is missing the table says
`— (not measured)` rather than printing a smooth lie.

## Preconditions, all of them named

`helpers/wispr_preflight.py` is the single list, shared with `wispr-test.sh` so
the two cannot drift. Nothing fails silently; a fatal row says what to do.

| checked | why it matters |
|---|---|
| relay answering on 8917–8919 | `ElementPicker` takes the first free port |
| the **installed** bundle, not `.build/debug` | debug has no Accessibility grant; `CGEventPost` fails silently |
| Wispr Flow running | the relay drives it, it never launches it |
| **Wispr microphone on Auto-detect** | the one setting only Victor can change; the preflight prints the instruction and exits 2 |
| a Loopback device resolves | otherwise the WAV is played at nobody |
| `sounddevice` + `numpy` | the playback |
| `~/bin/hands-off` | the locks are mandatory, not a nicety |
| `/test/state`, `/test/sink`, and `/test/gesture` (scenarios) or `/test/wispr-handsfree` (the primitive) | a build older than the harness exits **3**, not 1 |
| `/up` says nothing is listening | Victor may be dictating; the run refuses |

**Route detection has a wrinkle worth knowing.** `ElementPicker` dispatches on
method *and* path, and answers a GET to a POST-only route with the same
`404 {"ok":false}` it gives a route that does not exist. Probing `/test/gesture`
with a POST is out of the question — a POST to it *is* the gesture. So a 404
falls back to `strings` over the running executable: a hit proves the literal is
compiled in, a miss proves nothing, and it is only ever the fallback.

All three of these — the preflight, the system input and the locks — live in
**`tools/wispr-act.sh`**, sourced by both scripts. One implementation of the
restore trap, not two.

**The locks and the restore.** The act phase runs under
`hands-off run "wispr-loop <scenario>" -- …`, which releases on exit, on Ctrl-C
and on a crash. The system default input is switched by the shell and restored
by a `trap … EXIT INT TERM`, deliberately **not** from the Python: leaving
Victor's Mac recording from a Loopback device would make his next real dictation
silence, with nothing on screen to say why, and a shell trap is the thing that
survives the runner being killed.

There is **no `--speaker`** here. That is `wispr-test.sh`'s way round a pinned
microphone; it plays Victor's own voice out loud in his room, which an
unattended harness must never do.

## The scenarios

Each is **setup → act → wait on a condition → assert → teardown**. Never a fixed
sleep: every wait is `wait_for(predicate, timeout)` and a timeout is reported as
a failed assertion, not papered over.

| scenario | gestures | what it asserts |
|---|---|---|
| **`caret-short`** | `forward-click` · play · `forward-click` | the 2.2 s clip lands at the caret, and the ring is down ≤ 2000 ms after Wispr finished |
| **`caret-long`** | the same, 19.4 s clip | the control — green today |
| **`spawn-click-in-settle`** | `forward-up` · play · `forward-click` · *(settling)* · `forward-click` | **nothing** in the sink; an outbox line whose `delivery.to` starts `spawn:` and whose text matches |
| **`bound`** | bind a scratch tty · `forward-right` · play · `forward-right` | the words are typed into `bound-sink.txt`, nothing in the sink |
| **`cancel`** | `forward-click` · play · `forward-left` | no words anywhere, no outbox line, ring down ≤ 1000 ms after the gesture, reason says *cancel* |
| **`sink-key-at-start`** | sink key · `forward-click` · play · `forward-click` | the control for the pair below: the words are in the sink, the victim document is empty |
| **`sink-key-at-stop`** | `forward-click` · play · `forward-click` · **sink key** | the same, with the keyboard taken ~100 ms *after* the stop chord — see below |

The gesture names are the mouse's, not the keyboard's. `HotkeyTap` reads them as
⌃⌥⌘ **F7** (click — `onPasteToggle`), **F8** (↑, spawn), **F10** (→, bound —
`onLocalToggle`), **F11** (←, cancel), **F5** (🔽 →, Wispr's raw chord).

**The click and the right-move are toggles** (`onPasteToggle` and
`onLocalToggle` → `toggleDictation`, the same call ⌘⌃D makes), so the gesture
that opens a dictation is the gesture that ends it. **The spawn is not**, which
is why `spawn-click-in-settle` stops with a click and not with a second ↑.

### The two that are expected red

**`caret-short` reproduces incident 1** (2026-09-13 18:18:04). A sentence that is
over before Wispr's microphone ever opens leaves the relay inside
`speculativeGrace` — 12 s — with the lightning on screen the whole time, and
`⚡ ring down: no microphone within 12 s of the hotkey — Wispr ignored the chord`
is the line it ends on. The runner is built to **print that red with the measured
gap**, not to crash on it: the ring-down line has no `ms after the recording
ended` in it, so the interval falls back to the wall clock and says so.

**`spawn-click-in-settle` reproduces incident 2**: the second click Victor made
while the sentence was still settling sent the words to the caret — into the
window in front — and wrote no outbox line at all, so a sentence meant to open a
session simply vanished.

A real spawn **opens a Terminal window with `claude` in it**. That is a side
effect on Victor's desktop; the runner reports the spawned destination in its
notes so the window can be closed.

### The pair that answers a question rather than guarding a behaviour

Victor decided on 2026-09-13 that **the sink becomes the wrap mechanism**:
Walkie's own key text field receives whatever Wispr inserts, and Walkie routes it
onward. That design rests entirely on one fact nobody has measured —

> **does Wispr pick its insertion target at the START (the chord) or at the END
> (whatever is focused when the transcript is ready)?**

If it latches the front app at the chord, making the sink key after the
microphone closes is too late and the words go to whatever Victor was looking
at. `sink-key-at-start` and `sink-key-at-stop` are the two halves of that
experiment:

- both put a **real TextEdit document** in front — the *victim* — because "the
  sink got it" proves nothing unless something else could have got it instead.
  It is opened from a scratch file and addressed **by its file name**, never
  `document 1` by position: TextEdit may already be holding something of
  Victor's, and a harness that clears the front document is a harness that eats
  his notes. It is read with `osascript` (a read, no focus stolen) and closed
  `saving no`.
- `sink-key-at-start` makes the sink key **before** the chord. Whichever way
  Wispr decides, the sink should win. If it does not, something more basic is
  broken and the other run means nothing.
- `sink-key-at-stop` leaves the victim front for the whole dictation and takes
  the keyboard in the ~100 ms after the **stop** chord — the gap is measured and
  printed.

The verdict is a sentence under **`➤`** in each run and gathered under *where
Wispr put the words* in the summary:

| where the words landed | what it means |
|---|---|
| the sink | Wispr chose at the **END** — the wrap design works |
| the victim | Wispr chose at the **START** — the sink must be key before the chord |
| both | Wispr inserted twice, or the sink echoed the victim |
| neither | inconclusive — read the ring-down reason first |

Wispr's own `History` row carries an **`app`** column, which is *its* record of
where it put the sentence; it is reported beside the observation as a third
opinion.

**Run these with `--repeat 3`.** Wispr's round trip is 0.7–13 s and
`sink-key-at-stop` is a race; one sample of a race is an anecdote, and a
disagreement between repetitions is itself the finding.

```sh
tools/wispr-loop.sh sink-key-at-start --repeat 3
tools/wispr-loop.sh sink-key-at-stop  --repeat 3 --verbose
```

Teardown puts the previous app back (`POST /test/sink {"restore": true}`) and
closes the victim without saving, on every path.

## Reading the timing table

```
  timings
  gesture → mic open            412 ms
  mic close → Wispr done        294 ms  ⌘V from Wispr Flow
  Wispr done → ring down          9 ms
  Wispr done → delivery           5 ms  Wispr's ⌘V
  ring down reason              pasting at the caret
```

- **gesture → mic open** — `⚡ mic edge confirms the ring N ms after the gesture`.
  324–674 ms warm, **5–6 s cold** (measured 2026-09-12). A cold figure here is
  not a fault; it is the number `speculativeGrace` exists for.
- **mic close → Wispr done** — when Wispr says it is finished. Two sources, and
  the row names which: `formatted (Wispr's History row)` when Wispr inserted by
  a route no tap can see, `⌘V from Wispr Flow` when it pasted. Wispr's own
  `e2eLatency` over 30 days: p50 2.2 s, p90 3.5 s, p99 7.1 s.
- **Wispr done → ring down** — *the* number. Budget 2000 ms
  (`RING_DOWN_BUDGET_MS`). `(wall clock)` beside it means there was no
  measurement in the log and the interval came off second-resolution
  timestamps — which is itself the symptom of incident 1.
- **Wispr done → delivery** — `🗣️ wispr transcript via … N ms after the
  microphone closed`, and the route it came by.

`probes:` lists the synthetic keys the tap saw (`key 9 flags 0x20100000 from
Wispr Flow` is the ⌘V). The day Wispr stops delivering with a ⌘V, that line is
where it shows.

## Fixtures

`evals/fixtures/wispr-loop.json` holds **absolute paths** into
`~/.walkie-talkie/voice-corpus/` and nothing else. **The WAVs are Victor's own
voice and stay out of the repo**, which may be public; the corpus is never
pruned, so the paths keep.

| key | clip | length | transcript |
|---|---|---|---|
| `default` | `2026-09-04/13-25-48-fab7e654.wav` | 2.2 s | *"Commit and push the fix."* |
| `caret-long` | `2026-09-12/22-31-12-wispr243.wav` | 19.4 s | *"Let's run a bunch of experiments…"* |

Both are English, 16 kHz mono 16-bit PCM. The corpus is mostly Romanian; these
were picked for being **clean and unambiguous**, not for being typical, and
English gives the fuzzy match the least to argue about. The long one is labelled
`engine: wispr-flow` — its transcript came back through Wispr's own formatting
pass **on this very audio**, which is the closest thing to a known answer the
corpus has.

`transcript` is Wispr's own reading and is **not ground truth**
(`.claude/rules/whisper-and-corpus.md`, *The line beside a recording is not
ground truth*). That is the point: the run compares Wispr to Wispr over the same
audio, so any difference is the loopback.

Matching is `difflib.SequenceMatcher` over lowercased, punctuation-stripped,
whitespace-collapsed text, floor **0.80** (`SIMILARITY_FLOOR`). An exact match
would fail on a channel that is working perfectly, because the formatting pass
re-punctuates between two readings.

`--wav` and `--transcript` override any of it. **`--wav` on its own drops the
fixture's transcript**, so a new clip is never scored against the old clip's
words.

## Adding a scenario

1. Write `scenario_<name>(ctx) -> Result` in `helpers/wispr_loop.py`. `ctx`
   carries the `Relay`, the `Result`, a `LogMark` and an `OutboxMark` (both
   already at this run's high-water mark), the fixture, the device and a scratch
   directory.
2. Assert with `result.check(ok, label, measured)` — **one line per assertion,
   and always with the measured value on it**, because a `✗` with no number
   beside it is a bug report nobody can act on.
3. Wait with `wait_for(predicate, timeout, dry=ctx.relay.dry_run)`. Never
   `time.sleep` for a condition.
4. Register it in `SCENARIOS`: `name → (func, one-line blurb, expected_red)`.
   `expected_red=True` says the scenario reproduces a live bug, so the summary
   marks its failure `FAIL*` instead of pretending it is a surprise.
5. If it needs a clip of its own, add a key to `evals/fixtures/wispr-loop.json`
   under the scenario's exact name; otherwise it gets `default`.
6. Add the case to `evals/test_wispr_loop.py` if it adds any parsing or
   arithmetic. The pure half is unit-tested precisely because it can be wrong
   quietly:

   ```sh
   python3 evals/test_wispr_loop.py
   ```

A scenario must leave the Mac as it found it: close the sink, unbind, close any
window it opened. `--dry-run` prints every step it would take and asserts
nothing, which is also the cheapest way to review a new one.
