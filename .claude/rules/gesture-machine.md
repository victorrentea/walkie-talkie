---
paths:
  - "Sources/WalkieTalkie/GestureDiagram.swift"
  - "Sources/WalkieTalkie/GestureMachine.swift"
  - "Sources/WalkieTalkie/GestureActions.swift"
  - "Sources/WalkieTalkie/GestureSimulation.swift"
  - "docs/gestures.puml"
  - "docs/build-gestures.sh"
---
# The gesture machine: the diagram is the program

What a mouse gesture means lives in **`docs/gestures.puml`** and nowhere else.
`GestureDiagram` parses it at launch, `GestureMachine` executes it, `GestureActions`
turns its names into Swift. Full reasoning: `docs/journal.md` — *The diagram is the
program (2026-09-14)*.

## Edit the diagram, not the Swift

- **There is no second copy of the transition table.** No codegen, no baked-in
  fallback table, no `switch` over gesture names anywhere in `Sources/`. The file on
  disk is what runs. That is the whole of the anti-drift argument and everything
  below only protects it.
- **`./docs/build-gestures.sh` after every change**, exactly as
  `./docs/shoot-overlay-states.sh` is run after every overlay change. **Never
  hand-edit `docs/gestures.svg`** — `evals/test_gesture_diagram.py` re-renders into a
  temp directory and fails on a byte diff.
- **The grammar is in the diagram's own header**, so a person editing the file reads
  the rules in the file they are editing.

## The rules the parser enforces, and what each one cost

- **`A --> A` is a parse error.** A UML self-transition re-runs `exit` and `entry`, so
  a loop arrow on `Listening` would resume the music and drop the ring for a gesture
  meant to change nothing. Refusing the syntax is what makes Victor's rule —
  *"dacă nu e nimic bindat, dictarea nu se termină, ci așteaptă să se înțeleagă unde
  se trimite. De aia apare warning. Nu la început."* — **unwriteable wrong**: it has
  to be an internal transition, and an internal transition cannot run `exit`.
- **The unguarded transition for a `(state, trigger)` must be written last**, and the
  parser says so with both line numbers. Written first, it shadows every guarded one
  behind it. It caught this the first time the diagram was run: the unguarded
  `Listening : 🔼 forward-right / warnNothingBound` sat inside the state block, above
  the guarded `forward-right [bound]` arrow, and would have refused every delivery.
- **Reserved words are refused as triggers.** `exit  / resumeMusic` — aligned under
  `entry /`, which is how a person writes it — did not match `exit /` and was accepted
  as a *transition whose trigger was the word `exit`*. It raised nothing and cost
  `resumeMusic`: the music stayed paused after every sentence. Whitespace is collapsed
  before the keyword tests now, and `entry` / `exit` / `chip` / `mic` / `note` are
  refused as trigger names, because silence is the failure this grammar can least
  afford.
- **A composite may not be entered directly** — point the arrow at the substate.
  Entering `Listening` would have to pick one of its three silently.
- **One level of nesting.** A hand-written statechart stops being readable at depth
  two, and readability is the entire justification for the file.

## What belongs in the diagram, and what may not

- **The diagram names events; code owns clocks.** `settleTimeout` (8 s, Wispr's p99),
  `settleCeiling` (30 s), `speculativeGrace` (12 s) and `captureTimeout` (30 s) stay
  Swift constants with their measurements beside them. A duration in a `.puml` is a
  duration nobody can attach the evidence to, and the evidence is the only reason
  that number is 8 and not 20.
- **Physics stays in the tap.** `leftIsHeld` asks the window server and reconciles
  stale bookkeeping synchronously, before the swallow verdict. A guard containing
  that could not be simulated, which destroys the one property the simulate route
  exists for. So `HotkeyTap` turns physics into a **word** — `forward-bind` against
  `forward-click` — and the diagram turns the word into behaviour.
- **The machine does not deliver.** `AppDelegate.deliver` → `commit` is a four-way
  fork over a dead tty, a blind-paste target and a spawn that failed to open. None of
  it is decided by the mouse; firing `deliver` from a transition as well sends the
  sentence twice. The machine is told `@delivered` / `@held` afterwards and follows.
- **The ring, the borrowed gestures and the chip are functions of the state**, not
  effects fired at an instant, so they are re-derived by `reconcile` after every
  transition and appear on no arrow. **The music pause is the exception and is a real
  edge** — `MusicBridge` is told once when the microphone opens and once when it
  shuts — so it is `Listening`'s `entry` / `exit`. That distinction is the file's, and
  it is worth keeping: an effect that is a function of the state and an effect that
  fires at an instant are two different things.
- **Nothing here may name a recogniser.** `GestureActions.swift` speaks
  `DictationSource` only; `evals/test_gesture_no_second_brain.py` asserts no
  **concrete recogniser type** appears in it — `WisprFlowSource`,
  `LocalWhisperSource`, `WisprHistory`, `Transcriber` and the rest.
  `postWisprHandsFree` is the one deliberate exception and is not a leak: the
  action posts Wispr Flow's own *keyboard chord*, which is a key to post, not a
  recogniser to drive. Victor's scope, 2026-09-14: *"doar partea de
  interacțiune cu mouse-ul, nu motorul de hackuire al lui Wispr Flow, care trebuie cu
  grijă decuplat oricum și pus sub un strat."*

## When it will not load

Three layers, and the middle one is the one to understand:

1. **Build time.** `build-app.sh` validates before it touches `/Applications`, so a
   broken diagram never reaches the installed app.
2. **Launch, with a last-known-good.** Every diagram that loads is copied to
   `~/.walkie-talkie/gestures.last-good.puml`. A parse error or an unresolved name
   refuses the file **whole** and retries with that copy, saying so on the overlay and
   in `GET /test/state.gestureMachine.diagram.origin`. It is not a second source of
   truth — it is never hand-edited and never wins silently.
   **A simulation refuses to run on it.** A test that quietly asserts against
   yesterday's diagram is worse than one that fails; it cost twenty minutes the day
   this was written, when a duplicated line made the checked-in file unparseable and
   the answer complained about five action names that had already been deleted.
3. **Both fail → Safe Mode.** No machine; the chords are still swallowed and do
   nothing. **⌘⌃B, ⌘⌃D and ⌘⌃P stay outside the machine** and are the way back from a
   bad edit. Deliberately **not** a fall-back to the old imperative path — a second
   brain that wakes only when the first is ill is exactly the drift this removes.

## Testing

- **`./.build/debug/WalkieTalkie --simulate-gestures`** reads a script as JSON on
  stdin and prints the transitions, the chip at each moment, the actions, the
  warnings and anything **refused**. It exits before AppKit, before any permission is
  asked for and before `SingleInstance` can stand the running relay down — so the
  whole vocabulary is assertable with the installed app still bound to a terminal and
  hearing him. That is the property `POST /test/wispr-state/simulate` does not have.
- `POST /test/gesture-machine/simulate` is the same thing over the loopback.
- `POST /test/gesture {"name": …}` still posts the real chord; `GET
  /test/state.gestureMachine.state` now says which state it landed in, so a
  ten-gesture smoke test is one shell loop. The F7 **bind** sub-case needs a real held
  left button and is still not fakeable through that route — but `forward-bind` is
  fireable in the **simulator**, which is new.
- **`refused`** answers *why did nothing happen*, which before this machine had no
  answer anywhere in the app.

## Two behaviour changes worth knowing

- **🔽 click during the settle takes a picture, it does not post Return.** On
  master `dictating` was false once the microphone shut, so F6 typed Return. Here
  `Settling` answers it with `captureScreenshot`, which is right — `dictationInFlight`
  is cleared in `send`, so a frame taken after the microphone closes still attaches
  to the sentence. It does mean the key he submits with is a shutter for the length
  of a settle; if that grates, the fix is one line on `Settling`.
- **⌘⌃D is outside the machine** (with ⌘⌃B and ⌘⌃P) and reaches `toggleDictation`
  directly. It was inside for one build, which made a liar of every place that
  calls it the way back from a bad diagram — in Safe Mode the chord was swallowed
  and answered by nothing. The machine hears about a dictation it starts through
  `@micOpened` / `@idle`, like any other the world opens without asking it.

## Do not

- **Do not add a `switch` over gesture names anywhere in `Sources/`.**
- **Do not hand-edit `docs/gestures.svg`.**
- **Do not put a duration, a keycode or an expression in the diagram.**
- **Do not let a name in `GestureActions` go unreferenced** — there is no exemption
  list, because the diagram is the only caller.
- **Do not fall back to the old imperative path.** Safe Mode does nothing, loudly.
