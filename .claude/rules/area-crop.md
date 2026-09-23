---
paths:
  - "Sources/WalkieTalkie/HotkeyTap.swift"
  - "Sources/WalkieTalkie/ScreenCapture.swift"
  - "Sources/WalkieTalkie/DesktopEffects.swift"
  - "Package.swift"
---
# Area crop: the wheel, dragged

The middle button held and dragged during a dictation selects a rectangle of the screen that joins the pictures (2026-09-10); the selection UI is Victor Addons' crop, shared through `victor-mac-kit`. Full history and reasoning: docs/journal.md — see the sections named after each rule below.

## The gesture

- **The crop suspends Victor Addons' desktop effects for the length of the drag** (2026-09-22). Victor: *"atunci când fac poză la ecran cu wheel apăsat, oprește temporar, suspendă toate efectele de ecran."* This is the **only** capture in the app that needs it: every other one is over in a millisecond, while a crop is framed over seconds *while he is still talking*, and the room keeps tapping ☕ reactions at him the whole time — they rain into the box between the press and the release. `DesktopEffects.suspendForCrop()` at the press, `DesktopEffects.resume()` in the selection callback (**above** the nil branch, because a cancel and a rectangle are both ends of the drag).
  - **`GET /effect/suspend/<seconds>` and `/effect/resume` on 55123**, Victor Addons' port — not the effects app's 55124. Addons proxies `/effect/*` verbatim, so this side never needs to know there are two apps over there or which of them is up.
  - **Fire-and-forget, 1 s timeout, no retry.** A crop must never wait on a socket, and the effects app missing, stopped or mid-redeploy is a normal Tuesday — the shot is still worth taking. Failures go to the log, never to the overlay.
  - **The far side's hold is a deadline, not a flag** (`EffectsSuspension`), which is what makes a fire-and-forget resume safe: this app killed mid-drag, a redeploy, a crash — the hold expires by itself. That is why nothing here retries, and why the suspend asks for 20 s rather than for "until I say so".

- **A wheel drag while a dictation is running — bound, unbound, or headed for the caret — selects a region, in both gesture modes.** Dimming, box, ⌘ to move it whole, ⌥ to draw it from its middle, Esc to call it off: literally the same code as Victor Addons' crop. It rides `syncBorrowedGestures`' `dictating` like the other borrowed gestures, so it cannot outlive a sentence; unlike them it takes nothing until the hand has moved, and a middle **click** is handed back untouched. → journal: *The wheel, dragged: a region instead of the display (2026-09-10)*
- **`areaDragThreshold` is 12 pt, measured off the event, not off `NSEvent.mouseLocation`.** Victor's rule: *"ar trebui să ignori click/dublu-click de wheel — doar drag ne interesează."* It was 6 for a day — the right floor for *is this box worth capturing* (the overlay refuses to call a smaller one a selection), too fine for *did he mean to drag at all*; a click is never perfectly still. Nothing is lost by waiting, because the corner was recorded at the press. An event carries the position it was *made* at; the pointer answers where it is by the time the tap asks — they differ by one event, which is everything to a burst of posted events: the arm was silently skipped for a drag delivered faster than the pointer could be read, which is the shape every test of this gesture has. → journal: *The release matches the press, and in Logi mode both go through*
- **The plain click survives in Logi mode.** Verified with a listen-only tap tail-appended behind this one: a middle click during a dictation reaches the app underneath as a `DOWN` and an `UP`, nothing logged here — the whole promise of *Use Logi Gestures*. → journal: *The release matches the press, and in Logi mode both go through*

## The shared module (`Package.swift`)

- **`CropGeometry`, `CropSelectionOverlay`, `CropCapture` live in `../victor-mac-kit`, as a path dependency.** Both apps declare `.package(path: "../victor-mac-kit")`, so a fresh clone of either needs the sibling checked out beside it. That is the trade for editing the shared gesture and rebuilding in one step — no push, no version bump, no resolve — and both apps are only ever built on this Mac, from local. → journal: *The shared module, and why it is a path dependency*
- **`CropCapture` captures the whole display and crops at its real pixel scale.** `screencapture -R` answers *"could not create image from display with rect"* on macOS 15.7 for every rectangle it is given. → journal: *The shared module, and why it is a path dependency*
- **The two apps differ in exactly two things, both parameters.** `CropSelectionStyle` — English here (*UI language: English only*; it goes on a projector), Romanian in Addons. `begin(button:from:)` — Addons draws with the left button after letting go of ⌃P; here the drag is **already under way**, so the corner is handed in and the box is live on the first frame. → journal: *The shared module, and why it is a path dependency*
- **`CropPanel` refuses `constrainFrameRect`**, so the selection can reach the top 25 points of a screen instead of being pushed below the menu bar — the trap `BindFlight` and `CaretHalo` are already written under. → journal: *The shared module, and why it is a path dependency*
- **The selection panels must NOT be `sharingType = .none`.** Everything else this app draws near the pointer is invisible to capture; this is the one surface a person **aims** with. With the flag on the selection could not be reviewed by a screenshot or a remote pair of hands, which is exactly how a box that had stopped following the mouse went unnoticed. The beat between the panels coming down and the shutter is what keeps the dimming out of the picture, and always was. → journal: *The shared module, and why it is a path dependency*

## The release matches the press (`HotkeyTap`)

- **A swallowed release never brings a passed press up.** A press that went out puts the button *down* in session state, and a release this tap eats never takes it back up. Measured the hard way: a crop at 00:23 left `CGEventSource.buttonState` answering *middle: down* **seven hours later**, and what Victor had for those hours was a VS Code editor tab stuck to his cursor — as far as the window server was concerned a drag had been in progress since the night before. → journal: *The release matches the press, and in Logi mode both go through*
- **Swallow the release only if the press was ours** (`areaPressPassed`). Logi mode: press out, release out; the app underneath gets a middle-down and a middle-up with the movement removed — a click it ignores, the ends being in different places. Tick off: the wheel's own branch swallowed the press, so this swallows the release. Neither mode may leave the OS holding a button. → journal: *The release matches the press, and in Logi mode both go through*
- **With *Mouse Gestures: Wheel* the drag claims the press** (`claimWheelPress`, the same claim the release and the 2 s hold race for) and cancels the cancel timer; the release then finds `tapped` false and fires nothing. **That branch also clears `wheelArmed` / `wheelDown` itself**, because the release never reaches the branch that normally clears them: left standing, they would swallow the release of the *next* middle press — one this file passed through — the orphan bug written a third time. → journal: *The release matches the press, and in Logi mode both go through*
- **The overlay's `buttonState` poll is useless here, in both directions at once.** A swallowed release never reaches that state (first run: finger up, box stopped, dimming stayed with `buttonState` still *down*, only Esc out — and a diagnostic `swift` one-liner hung two minutes behind the phantom drag). A swallowed press never puts it *down* (tick off: the first tick would end a selection that had not started — hidden for a day behind state already stuck true from a Logi-mode drag four minutes earlier). So a drag handed in through `begin(from:)` is `driven`: the button is the caller's to report, `onAreaEnd` → `CropSelectionOverlay.endDrag()` is the report, Esc and the right button stay as the ways out that do not depend on the caller being alive. → journal: *A tap with an opinion about the button makes the overlay's poll useless*
- **A release landing before the panels are on screen is kept for `begin` for half a second** — long enough for the hop, short enough that a stale one cannot end the next selection; a flick beats the overlay onto the screen. → journal: *A tap with an opinion about the button makes the overlay's poll useless*

## The box and the readout

- **Push the position, never poll it.** `CropSelectionOverlay.dragMoved(toCG:)` on every swallowed drag event, drawing on arrival; the timer keeps only what it alone can see (Esc, right button, ⌘/⌥), with the pointer read as fallback for a tick with nothing pushed yet. A `driven` drag has every motion event swallowed before any window sees it, so a 60 Hz `Timer` polling `NSEvent.mouseLocation` starved: the box stopped following while held and caught up at release (*"nu văd live chenarul selectat în timp ce țin jos wheel-ul"*). Measured at 72 fps, worst gap 20 ms. **Not reproducible with posted events** — the machine under a posted drag is not the machine under a real one; treat that as the tell, not a dead end. → journal: *The box follows the events, not a timer (2026-09-10)*
- **Every selection logs one line saying whether the box was drawn**: `✂️ selection over 5.0s — 362 frames (59 pushed, 303 polled), worst gap 20ms`. `CropSelectionOverlay.log` is the module's one diagnostic hook, pointed at each app's logger. → journal: *The box follows the events, not a timer (2026-09-10)*
- **The readout is always `386 × 232   ⌘ move   ⌥ centre`, the word lit in the accent while its key is held.** *"legenda «centre» și «move» să fie mereu prezentă când fac crop, dar să devină colorate cuvintele când chiar se întâmplă."* They name the **key**, not the effect. **The colours live in the attributed string, not on the label** — a `foregroundColor` set on the layer does not win against the runs (the trap `RelayWindow.applySelectionText` is written under). → journal: *The two keys are always on the readout, and light up when they act*
- **The cut-out flies from the box into the chip's `📸`** (2026-09-23, Victor asked for it for *"the area I cropped"* too — see `screenshots-and-selection.md`). Otherwise still **no border, no vignette, no cursor mark.** He watched himself draw it at the pixels he drew it around; a mark lit afterwards is the same news, later, on top of the thing he framed. (`ScreenCaptureFlash.flash(around:)` left Victor Addons for the same reason; the full-screen flash stays there.) → journal: *No border, and no vignette either*

## The file and the envelope (`ScreenCapture`)

- **The name is `area-00:38(1200x800px).jpg`: no pointer, size measured off the JPEG.** A full-screen shot carries the pointer because it answers *which of these thousand things*; here the box answered that, and the pointer is merely the corner he let go on. The size is the one fact not obvious from looking, and is never multiplied out of the screen's backing scale, for `tagCursor`'s reason. → journal: *`area-00:38(1200x800px).jpg`, and one sentence in the clause*
- **`ScreenCapture.isArea` reads the `area-` prefix**, not a flag beside the path — the name is also what says it to the agent, and a second copy of that fact is a second thing to keep in step. → journal: *`area-00:38(1200x800px).jpg`, and one sentence in the clause*
- **The clause says it once, only when a crop is present**, verbatim:

  ```
  Anything named `area-` is a region I dragged a box around, not the whole screen —
  its edges are mine, not the display's.
  ```
  → journal: *`area-00:38(1200x800px).jpg`, and one sentence in the clause*
- **The handover copy is unchanged**: 800 px on the long edge, so a smaller crop travels at its own size; the note says *at most* 800px wide. A crop counts in `📸 ×N` like any other picture — the chip is untouched. The one new string is the failure flash `⚠️ area capture failed` (the `listening-flash` state with different words). → journal: *`area-00:38(1200x800px).jpg`, and one sentence in the clause*
- **The crop's value is *which one*, not *which word*** (measured 2026-09-19, `evals/capture-proof/`).
  24 agent runs over four highlighted words: the word itself comes back right 24/24 from the whole
  800 px screen alone — the downscale is not the problem anyone assumed it was. Where the page
  fails is a word that appears twice in its own paragraph: handed the page an agent quotes the
  sentence, which holds both occurrences (4/6 pinned); handed the crop alone it quotes the lines it
  was given (6/6). **Handing over both was worse than the crop alone** (3/6) — the page invites the
  wider quote back. → journal: *The pictures are clean, and it is a measurement now (2026-09-19)*
- **What ships is the whole display with the rectangle in the *name*, not a crop** (2026-09-14, `grabArea`) — the two bullets above quote the pre-2026-09-14 clause and the later date wins. The drag became a **pointing** gesture: *"nu doar decupez o bucată, ci arăt: în zona aia vreau să dispară, să apară ceva"*.
- **With nothing selected, that costs a quarter of the answers** (measured 2026-09-19, `evals/pointing-proof/`, 96 runs). Asked *which sentence am I pointing at* with no highlight anywhere: the shipped envelope gets it **21/28**, and six of the seven misses land in **another paragraph**; the region alone gets it 28/28 (p = 0.006). The cause is that `tagArea` measures the rectangle off the **full-resolution** JPEG while the file handed over is the 800 px copy, so the reader rescales by 4.3× by eye — and **spelling the scale out in the clause does not fix it** (7/12, no better than saying nothing). What fixes it is pixels: the screen **plus** the framed region as a second file scores 15/16 and keeps the pointing semantics. → journal: *A box round it, with nothing selected (2026-09-19)*
- **So a drag writes three files, and the third is not scaled** (2026-09-19, Victor: *"trimite atât ecranul original + 800px ca până acum, dar și selecția originală decupată (nescalată)"*). `<name>.jpg` (the display, his), `<name>-small.jpg` (800 px, the agent's), `<name>-zoom.jpg` — the rectangle **cut out of that same frame** at its own pixels. `ScreenCapture.writeRegionCopy`, and it cuts the frame rather than capturing again: a second `screencapture -R` is 200 ms later and of a screen that has moved, where this is the same instant by construction. It costs a decode and re-encode, which is affordable only because `fileArea` is already off the main thread with the panels down.
- **The cut-out has no `-small` of its own, deliberately.** It is the unscaled copy or it is nothing; `handover(for:)` falls back to the file itself when no small sibling exists. The reading tool fits any image to 2000 px before charging for it, so the worst a zoom can cost is what a retina desktop costs (~3450 tokens) and a band of text is 400–900.
- **One drag is still one picture.** `-zoom` is a sibling found by name (`ScreenCapture.zoom(for:)`), like `-small`: it is not in `paths`, not in the chip's `📸 ×N`, and `prune()` counts neither sibling as a frame and deletes both with it. In the clause it is an **indented** row under its frame, because a flat list of two rows is two shots to an agent and puts the `[shot N]` enumeration out by one.
- **The clause had to change in two places, not one.** The area sentence now reads *in the pixels of the full-resolution frame* (it said *that picture's own pixels*, which is false for the 800 px copy the reader is holding — the `sized` condition above proves saying it better does not help, but saying it wrong is still wrong), and the width note gains *a `-zoom` is the exception: it is not scaled at all*, or the one file whose point is that it was not shrunk is covered by a sentence claiming everything is ≤800 px.
- **`POST /test/area` is how any of this is asserted** — `evals/test_envelope.py::AreaFrame`, five cases: the frame keeps the box in its name, the cut-out is an indented row under it, the note carries both new sentences, the file on disk matches the rectangle in the name and is wider than the handover, and the outbox still lists one picture. The gesture needs a held middle button and a moving hand, so without the route the three files were only checkable by making it.
- **A rectangle over wrapped text selects a band of lines, never a sentence.** The runs that located scene 2's box exactly then quoted the whole paragraph, because that is what the box contains. For a sentence inside a paragraph the highlight is the instrument, not the drag. → journal: same
- **The menu carries a legend row `Select Screen Area — 🛞 drag`**, permanently disabled like `Take Screenshot` and `Pick Element in Chrome` — the one row that puts `🛞` back in the Logi column, because a drag is not a click. → journal: *`area-00:38(1200x800px).jpg`, and one sentence in the clause*

## The stale-⌘ bug, and the test that guards it

**The rule, once:** *a function that posts a key event with a modifier flag on it must also post a
`flagsChanged` carrying the state the keyboard is left in — or address its events to a process with
`postToPid`, which never touches session state at all.* `CGEventSource.flagsState` reports whatever
the **last event's flags said**, so a key-up that carries ⌘ leaves the whole session believing ⌘ is
held until Victor's next real keystroke heals it.

**Four occurrences, and each time the symptom was something else failing:**

| when | poster | what it broke |
|---|---|---|
| 2026-09-10 | `TerminalBinding.tap(key:command:)` | every Replace Wispr dictation, ⌘⌃P and blind paste left `0x00100000` behind; found because a wheel drag silently refused to select an area after a caret paste |
| 2026-09-13 | `HotkeyTap.postGesture` | `POST /test/gesture` posted ⌃⌥⌘F-key down and up and nothing else, so every *wait for a bare wire* loop ran to its 200 ms ceiling — and Wispr's Scratchpad chord went out as `⌃⌥⌘F18`, which it does not have bound |
| 2026-09-13 | `HotkeyTap.postScratchpad` | posted immediately rather than onto a bare wire — the same bug from the other end |
| 2026-09-14 | `KeySimulator.simulateKeyPress` (the ⌘C selection probe) | the session believed ⌘ was held after every probe; **the window server merges live modifier state back into a posted key**, so letters arriving afterwards were delivered as ⌘ + letter — against TextEdit, `q z j k w y v` are *quit*, *close the document*, *undo* and four edits |

It self-heals on the next real key, which is why it has never been reported and why it has had to
be rediscovered four times. So it is a test now:

- **`evals/test_stale_modifier.py`** parses `Sources/` and fails any function that posts a key with
  non-empty flags and neither posts a `flagsChanged` nor uses `postToPid`. `--list` prints every
  poster it found (12 at the time of writing); `--self-test` reads `SelectionCapture.swift` as it
  stood before `fc74df6` and asserts the scan **rejects** it, because a guard nobody has watched
  fail is a guard nobody knows the shape of. Exit 2 when it finds no posters at all — a parser that
  has stopped matching must not read as a clean tree.
- **It detects the assignment, not the literal.** The fourth occurrence took its flags as a
  *parameter* (`simulateKeyPress(keyCode:flags:)`) and named no modifier, so a scanner looking for
  `.maskCommand` would have missed the very bug it was written for.
- **`GET /test/state.sessionFlags`** answers what the window server believes is held right now, by
  name, so a standing *flags are clear* check reads the state instead of inferring it from the
  damage.

## The stale-⌘ bug in `tap(key:command:)`

- **Release the modifier with a `flagsChanged` carrying the state the keyboard is left in.** `TerminalBinding.tap(key:command:)` — under `pressPaste`, so every Replace Wispr dictation, every ⌘⌃P and every blind-paste delivery — stamped ⌘ onto the V's key events and never released it; `CGEventSource` reports whatever the last event's flags said, so a ⌘V ending in a key-up *with ⌘ on it* left the session believing ⌘ was held: `0x00100000` after a single paste, and it stayed. It self-heals on the next real key, which is why it was never reported. Two readers were wrong until then: `postWisprHandsFree` spun its full 200 ms allowance after every paste, and **every gesture gated on `bare` refused** — a wheel drag silently declining to select straight after a caret dictation had pasted is how it was found; the same stale ⌘ would refuse the mouse-4 shutter. Verified: `0x20100000` before, `0x20000000` after, and a crop straight after a paste now arms. → journal: *It cost a real bug in the paste path, found by this gesture refusing to fire*

## Verified end to end (re-run these when touching the gesture)

- An 800×500-point drag came back as `1600x1000px`, cross-checked against an independent whole-display `screencapture` cut at the same pixels: **correlation 0.997** — what settles the Cocoa→image y flip and the retina scale.
- Two crops in one dictation came out in order, stamped by offset, named by what was in front of him, the `area-` sentence appended once.
- The plain click survives — `DOWN`/`UP` seen downstream, nothing logged here.
- Both gesture modes, each from a clean button state and each leaving one: `left/right/center` all `false` before and after, in Logi mode and with the flag off; with the flag off both halves swallowed and neither the 2 s cancel nor the release's *end the dictation* fired.
- A flick past the threshold released in the same millisecond ends as a cancelled selection, not a stuck panel; Esc mid-drag cancels with no file written and no panel left.
→ journal: *Verified end to end*
