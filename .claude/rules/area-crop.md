---
paths:
  - "Sources/WalkieTalkie/HotkeyTap.swift"
  - "Sources/WalkieTalkie/ScreenCapture.swift"
  - "Package.swift"
---
# Area crop: the wheel, dragged

The middle button held and dragged during a dictation selects a rectangle of the screen that joins the pictures (2026-09-10); the selection UI is Victor Addons' crop, shared through `victor-mac-kit`. Full history and reasoning: docs/journal.md — see the sections named after each rule below.

## The gesture

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
- **With *Use Logi Gestures* off the drag claims the press** (`claimWheelPress`, the same claim the release and the 2 s hold race for) and cancels the cancel timer; the release then finds `tapped` false and fires nothing. **That branch also clears `wheelArmed` / `wheelDown` itself**, because the release never reaches the branch that normally clears them: left standing, they would swallow the release of the *next* middle press — one this file passed through — the orphan bug written a third time. → journal: *The release matches the press, and in Logi mode both go through*
- **The overlay's `buttonState` poll is useless here, in both directions at once.** A swallowed release never reaches that state (first run: finger up, box stopped, dimming stayed with `buttonState` still *down*, only Esc out — and a diagnostic `swift` one-liner hung two minutes behind the phantom drag). A swallowed press never puts it *down* (tick off: the first tick would end a selection that had not started — hidden for a day behind state already stuck true from a Logi-mode drag four minutes earlier). So a drag handed in through `begin(from:)` is `driven`: the button is the caller's to report, `onAreaEnd` → `CropSelectionOverlay.endDrag()` is the report, Esc and the right button stay as the ways out that do not depend on the caller being alive. → journal: *A tap with an opinion about the button makes the overlay's poll useless*
- **A release landing before the panels are on screen is kept for `begin` for half a second** — long enough for the hop, short enough that a stale one cannot end the next selection; a flick beats the overlay onto the screen. → journal: *A tap with an opinion about the button makes the overlay's poll useless*

## The box and the readout

- **Push the position, never poll it.** `CropSelectionOverlay.dragMoved(toCG:)` on every swallowed drag event, drawing on arrival; the timer keeps only what it alone can see (Esc, right button, ⌘/⌥), with the pointer read as fallback for a tick with nothing pushed yet. A `driven` drag has every motion event swallowed before any window sees it, so a 60 Hz `Timer` polling `NSEvent.mouseLocation` starved: the box stopped following while held and caught up at release (*"nu văd live chenarul selectat în timp ce țin jos wheel-ul"*). Measured at 72 fps, worst gap 20 ms. **Not reproducible with posted events** — the machine under a posted drag is not the machine under a real one; treat that as the tell, not a dead end. → journal: *The box follows the events, not a timer (2026-09-10)*
- **Every selection logs one line saying whether the box was drawn**: `✂️ selection over 5.0s — 362 frames (59 pushed, 303 polled), worst gap 20ms`. `CropSelectionOverlay.log` is the module's one diagnostic hook, pointed at each app's logger. → journal: *The box follows the events, not a timer (2026-09-10)*
- **The readout is always `386 × 232   ⌘ move   ⌥ centre`, the word lit in the accent while its key is held.** *"legenda «centre» și «move» să fie mereu prezentă când fac crop, dar să devină colorate cuvintele când chiar se întâmplă."* They name the **key**, not the effect. **The colours live in the attributed string, not on the label** — a `foregroundColor` set on the layer does not win against the runs (the trap `RelayWindow.applySelectionText` is written under). → journal: *The two keys are always on the readout, and light up when they act*
- **No border, no vignette, no cursor mark.** He watched himself draw it at the pixels he drew it around; a mark lit afterwards is the same news, later, on top of the thing he framed. (`ScreenCaptureFlash.flash(around:)` left Victor Addons for the same reason; the full-screen flash stays there.) → journal: *No border, and no vignette either*

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
- **The menu carries a legend row `Select Screen Area — 🛞 drag`**, permanently disabled like `Take Screenshot` and `Pick Element in Chrome` — the one row that puts `🛞` back in the Logi column, because a drag is not a click. → journal: *`area-00:38(1200x800px).jpg`, and one sentence in the clause*

## The stale-⌘ bug in `tap(key:command:)`

- **Release the modifier with a `flagsChanged` carrying the state the keyboard is left in.** `TerminalBinding.tap(key:command:)` — under `pressPaste`, so every Replace Wispr dictation, every ⌘⌃P and every blind-paste delivery — stamped ⌘ onto the V's key events and never released it; `CGEventSource` reports whatever the last event's flags said, so a ⌘V ending in a key-up *with ⌘ on it* left the session believing ⌘ was held: `0x00100000` after a single paste, and it stayed. It self-heals on the next real key, which is why it was never reported. Two readers were wrong until then: `postWisprHandsFree` spun its full 200 ms allowance after every paste, and **every gesture gated on `bare` refused** — a wheel drag silently declining to select straight after a caret dictation had pasted is how it was found; the same stale ⌘ would refuse the mouse-4 shutter. Verified: `0x20100000` before, `0x20000000` after, and a crop straight after a paste now arms. → journal: *It cost a real bug in the paste path, found by this gesture refusing to fire*

## Verified end to end (re-run these when touching the gesture)

- An 800×500-point drag came back as `1600x1000px`, cross-checked against an independent whole-display `screencapture` cut at the same pixels: **correlation 0.997** — what settles the Cocoa→image y flip and the retina scale.
- Two crops in one dictation came out in order, stamped by offset, named by what was in front of him, the `area-` sentence appended once.
- The plain click survives — `DOWN`/`UP` seen downstream, nothing logged here.
- Both gesture modes, each from a clean button state and each leaving one: `left/right/center` all `false` before and after, in Logi mode and with the flag off; with the flag off both halves swallowed and neither the 2 s cancel nor the release's *end the dictation* fired.
- A flick past the threshold released in the same millisecond ends as a cancelled selection, not a stuck panel; Esc mid-drag cancels with no file written and no panel left.
→ journal: *Verified end to end*
