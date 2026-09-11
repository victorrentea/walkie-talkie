---
paths:
  - "Sources/WalkieTalkie/RelayWindow.swift"
  - "Sources/WalkieTalkie/OverlayStates.swift"
  - "Sources/WalkieTalkie/Glyphs.swift"
  - "docs/build-overlay-states.py"
  - "docs/shoot-overlay-states.sh"
  - "docs/states/**"
---

# The overlay chip: rows, glyphs, states, placement

Rules for the chip that rides the pointer (and the panel it grows into): what each row says, how
it is drawn, which loops may relayout, and how the states catalogue is kept honest.
Full history and reasoning: docs/journal.md — see the sections named after each rule below.

## The states page is part of every change

- **No change to the overlay is finished until `docs/overlay-states.html` is rebuilt.**
  `./docs/shoot-overlay-states.sh` shoots all 40 states and regenerates the HTML. That covers a new
  row, a reworded string, a changed glyph, a different colour, a state that starts or stops
  existing. A new state means a new `Shot` in `OverlayStates.swift`; a state that goes away means
  deleting one. **Never edit `docs/overlay-states.html` by hand** — it is overwritten on the next
  run. The catalogue, order, sections and prose live in `OverlayStates.swift`; the pictures are the
  real views drawing themselves through `RelayWindow.snapshot`; `build-overlay-states.py` only
  lays them out. The script stands the installed app down (`SingleInstance`) and puts it back.
  → journal: *The overlay's states are photographed, and the page is part of the change*
- **`RELAY_SHOOT` photographs states, not transitions.** The `HQ` pop, the oblique wipe and every
  other animation are skipped under it — a transition is by definition not a state, so none of
  them needs a `Shot`. → journal: *A tag pops out when it fills (2026-09-08; it said `HQ` from 2026-09-09)*
- **`snapshot` always renders at 2×** (2026-09-09). `bitmapImageRepForCachingDisplay` answers at
  the backing scale of the display the window is on, so the catalogue came out 1× with the
  external monitors awake and 2× on the built-in panel — and every file in `docs/states/` turned up
  in the diff with nothing to explain it. `snapshot` builds the rep itself at a fixed 2×; the page
  lays each picture out at its size in **points** (`build-overlay-states.py` writes
  `width=`/`height=` from the manifest). → journal: *Size: minimal, per state*
- **Every rendered string is English**, even the dormant hint rows. Current strings:
  `Self.shotHint` + `recordText`, `engineText` (`Listening...`), `hqBadge` + `elapsedText`
  (language-neutral by luck — must stay so), `Self.pickHint` + `pickText`, `titleText`,
  `flash(_:)`/`flashTitle(_:)` call sites in `AppDelegate.swift`, and `StatusItem.swift`.
  → journal: *UI language: English only*
- **Freeze frames exist for the catalogue only.** `pinListenWarmth(_:)`, `pinTranscribeWarmth`,
  `pinListenElapsed`, `pinSelectionSettled`: the shutter fires immediately after `apply`, so
  without a chosen frame every dictating state on the page would be a photograph of its own first
  200 ms. `reset` pins the full bar; `listening-cold` and `listening-warming` pin their own;
  `transcribing` pins 0.45 (with no audio behind it `transcribeWarmth` answers a **full** bar, so
  the one picture of the wait would show nothing waiting).
  → journal: *Two implementation traps, both paid for*; *The wait fills too (2026-09-08)*

## Title states

Titles are `<emoji> <label>: <state>`, label = `folder@branch` (`SessionLabel`, re-read every 10 s,
yields to `--label`).

| state | label |
|---|---|
| idle **and unbound** | **nothing at all — no window on screen.** See *The pointer is clean when nothing is bound* |
| idle, bound | the destination app's icon + `petclinic@main` — no state word: "standing by" is what he can already infer from nothing happening |
| dictating | `🤖 ai@master`, unchanged, **plus the recording row below it** |
| bound to a terminal | the destination app's icon + `petclinic@main`; the 🤖 is *replaced*. See *What the chip says when bound* |
| bound to an app with no readable directory (a blind-paste target) | the icon + the app's own name — the one case where the icon has no subject beside it |
| the dictation was cancelled | `🗑️ Cancelled` in the row `Listening…` was in — 1.5 s, swept in and swept out again by the oblique line (*The oblique wipe*). The 🗑️ came back on 2026-09-02: it was dropped while a flash still drew the lone 🎙️ title row above it, where Apple's lid-flying-off bin read as a second glyph on a two-glyph line; that row no longer appears under a flash, so the bin is the row's only picture |
| dictating in Replace Wispr | the drawn map pin + `at caret` — the same slot a spawn takes, and for the same reason |

- **Dictating has no title of its own.** The top line stays `🤖 folder@branch` through the whole
  dictation; what changes lives one row down. Liveness is the pulsing 🔴 — a frozen recording row is
  indistinguishable from a hung app. → journal: *Title states*
- **The pulse takes the microphone's place** (2026-09-07): 🎙️ → `🔴 Listening...` in place and
  `petclinic@main` slides to the second row; `⏳ Transcribing...` is the same slot at the next
  moment. **Only the chip** — the held panel keeps its title first. → journal: *The recording rows*

## Rows: order, tally, geometry

- **Row order, top to bottom: the dictation's state, the destination, the shots, the quoted
  highlight, Chrome last.** *"citatul să apară mereu deasupra Chrome-ului … Chrome trebuie să fie
  mereu ultima din listă"*. A highlight belongs to this message; the ⌘⇧ row outlives it, and a row
  that shuffles as a highlight comes and goes is one he has to find again every time.
  → journal: *The order of the rows, and Chrome is last (2026-09-09)*
- **The tally is the icon column read downwards**, each count two characters wide:

  ```
  🔴 Listening... [HQ] (2m)
  [Terminal] petclinic@main
  📸 ×3
  “  public Order placeOrder(Cart…      → ×2 after four seconds
  [chrome] ×3 ⤢
  ```

  `×N`, **nothing at zero**; bound dictation says `×1` from the first frame (`publishShotCount`);
  Replace Wispr takes no automatic frame, so the row appears at the first shutter. It shows
  through the decode too — `RelayWindow.gathering` is `listening || transcribing` — but the
  **invitation** half of the Chrome row stays on `listening` alone (⌘⇧ goes back to the browser
  the instant the microphone closes). The Chrome row collapses to `×N` four seconds after the
  newest pick, clock restarted on every pick. `⤢` after the count means one of the queue was
  dragged (`publishPicks` asks `contains { $0.move != nil }`) — typed, in the row's own font, so it
  reads as punctuation. → journal: *The tally: what this dictation is carrying, read down the icon column (2026-09-09)*
- **The shots row shows only `📸 ×N`** (2026-09-09). The drawn mouse and `+ selection` are behind
  `showsGestureHints` and *replace* the count rather than sharing the line.
  → journal: *The chip teaches nothing; the menu does*
- **The count says `×1` from the instant the row opens**, before `screencapture` has returned
  (`AppDelegate.contextShotPending`). It said `×0` for the best part of a second — a clipboard probe
  that sleeps up to 400 ms plus a subprocess — in the one moment he looks at the row. Zero only if
  the capture genuinely fails. **`captureContext` runs before `overlay.setListening(true)`** in
  `dictation.onChange`: it books the shot synchronously, and `setListening(true)` zeroes the
  count, so the other order publishes a `×1` into a row about to reset it.
  → journal: *The recording rows*
- **All glyphs share `glyphBox`, a fixed 17 pt square, each glyph fitted and centred in it** —
  images scaled proportionally, emoji at 15 pt. Measuring per glyph aligned the boxes and nothing
  else (*"iconurile nu sunt left-aliniate si au dimensiuni diferite"*): an emoji's ink sits a
  bearing in from the left, an app icon fills its box, the pin is 0.7 as wide as tall. Centring is
  what makes them *look* left-aligned. → journal: *The recording rows*
- **Both halves of a row are centred on the row's midline** (`centre(_:…)`). A 15 pt box at y=1
  clipped the 🔴 to an arc (*"bila rosie pulsanda e taiata jos"*), and a label filling the row
  drew its text high. Each half gets exactly its own font's height around the middle.
  → journal: *The recording rows*
- **Row heights: title 21, every other row 22, `rowGap` 2, `pad` 12 all round.** Idle chip is 40
  tall (bound the same, the folder is in the title row); dictating is 40 + 3 × 23, plus 21 more with
  a selection. The selection row's `“` mark sits in the **icon column** (2026-09-02, not a 28 pt
  row with a 26 pt mark 6 below the baseline) — *"rândurile trebuie să aibă distanță egală între
  ele în tooltip"*. → journal: *Size: minimal, per state*
- **`layoutContent()` hugs the current state, not the widest.** No room reserved for the longest
  title, the hidden legend, or a ✕ the chip does not have. Resizing on a state change is expected,
  and so is the hair of width the recording row gains at `×10`. → journal: *Size: minimal, per state*

## `Listening...` and `Transcribing...`

- **`Listening...` is a progress bar drawn one character at a time** — twelve steps
  (`RelayWindow.listeningWord`), **three full stops rather than `…`** so the tail is three steps,
  not one glyph taking a quarter of the bar. Binary per character, not a gradient — a gradient
  would be *"nu înțeleg când e aprins complet"* in twelve places. It is a forecast about the
  transcript, not a measurement of the recording.
  → journal: *`Listening...` is a progress bar, and it fills on speech (2026-09-07)*
- **It counts `MicRecorder.voicedSeconds`, not wall clock.** The median dictation is only 38 %
  voiced (p10 14 %); a clock-driven bar filled while he was thinking. The local model's own
  language picks, re-decoding 803 clips (`evals/short-clip-lid.md`):

  | voiced | decoded into a language Victor does not speak |
  |---|---|
  | 0–1s | **42%** |
  | 1–2s | **15%** |
  | 2–3s | **1%** |
  | 3–4s | 2% |
  | 4s+ | **0%** |

  The first version of this table read `detectedLanguage` from `corpus.jsonl`, which is **Wispr
  Flow's** pick (`corpus_harvest.py` copies Wispr's row wholesale) and understated every figure
  about three times; `asr` is not a second opinion to score against. The `{ro, en}` pin has since
  taken the wrong-language mode to 0 % in every bucket; the bar stays because a two-word clip is
  still a clip with no context in it. → journal: *It counts voiced seconds, not elapsed ones*
- **Full at three voiced seconds** (`RelayWindow.enoughSpeech`) — the first bucket where both
  failure modes are at their floor; ~15 words at 5.1 words per voiced second, ~8 s of ordinary
  talking (*"dacă vorbesc peste 5–7 secunde, transcripția e mult mai calitativă"*).
  → journal: *And then the minutes, in brackets (2026-09-09)*
- **The `HQ` tag: blue, drawn (`Glyphs.tag`), `0.8 ×` the icon column, an `NSImageView`, popped
  once on the edge, measured into the width.** Never ⭐, never ✨ (the sparkles are the spawn's
  mark and sit on this very row — checked in `docs/states/spawn.png`). Drawn because a raw glyph in
  an attributed string on a halo label turns every other character transparent
  (`applyTitleText`). `0.8 ×` because the capsule fills its box corner to corner. An `NSImageView`
  because a text attachment has no layer to animate and re-rasterising per frame would put a
  relayout in the one loop that must not have one. Pop 0.15 → 1.45 → 0.85 → 1.08 → 1.0 over
  0.42 s with a quarter turn *to* zero (`placeListenExtras`) — not `CursorMarker`'s bloom, whose
  job is to get out of the way. **Edge-triggered**: the tag is a function of the bar being full,
  the pop only the edge; `applyEngineText` runs on every relayout and `refreshChrome`, so a replayed
  pop would flash at the corner of his eye for the rest of the sentence. `listenExtrasWidth` makes
  its arrival **the one tick in a sentence allowed a relayout**.
  → journal: *A tag pops out when it fills (2026-09-08; it said `HQ` from 2026-09-09)*
- **The minutes `(2m)`: wall clock, nothing under a minute, a label of its own, relayout at most
  once a minute.** Wall clock because this answers *how long have I been at this*; `(0m)` is a
  readout saying only that a clock exists. Its own label because a run in `engineInfo` would land
  *before* the tag. `startElapsed` ticks once a second and does nothing on 59 ticks in 60 — the
  ramp's timer cannot carry it, it stops at three voiced seconds. `pinListenElapsed` freezes it for
  `OverlayStates`. → journal: *And then the minutes, in brackets (2026-09-09)*
- **`Transcribing...` fills from `DecodeRate`'s deadline and carries no digits** (2026-09-08).
  `transcribeDeadline`, `transcribeSpan` and the fitted line are what the bar is drawn from; the
  `4s` countdown went the same day (*"e doar stresant. Lasă să se sugereze progressbar-ul prin
  culoarea textului"*). Three full stops, for `Listening...`'s reason. Fifteen ticks a second and
  **nothing relayouts at all** — the row is a fixed string whose ink changes; taking the number
  off *removed* a relayout. → journal: *The wait fills too (2026-09-08)*
- **The meter constants come from the corpus replay and are transferable only because
  `MicRecorder.meter` runs on the converted 16 kHz mono buffer** (`evals/voiced-seconds.py`). Per
  1024 frames (64 ms): RMS against an adaptive noise floor, 9 dB over it to count as speech,
  absolute floor 180 underneath; instant attack down, 2 % release up; both reset per recording.
  Adaptive because the DJI receiver peaks at 16552 where the built-in microphone manages 855.
  → journal: *The meter*

### Two implementation traps, both paid for

- **A timer, not a layer animation, twice over.** `textColor` is not animatable —
  an `NSTextField` draws its string through the view, not a `CATextLayer`, so
  Core Animation has nothing to interpolate and `NSAnimationContext` silently
  does nothing. And there is nothing to interpolate *toward*: the bar is driven
  by audio that has not arrived, so its length is polled, never scheduled. 15
  ticks a second on `.common` (the wheel chord is a held mouse button, i.e. a
  tracking loop), each reading one `Double` under a lock and **doing nothing at
  all unless the count of lit characters changed** — twelve steps against fifteen
  ticks a second means the overwhelming majority are a no-op. It must never reach
  `layoutContent`, which would re-measure every row of the chip on every frame.
- **The ✨ goes in as a picture, not as a character** (`Glyphs.emoji` through
  `inline`). A raw emoji inside an attributed string on a label carrying a halo
  is the failure `applyTitleText` has warned about for weeks: the emoji draws and
  **every other glyph comes out fully transparent**. It cost the spawn row its
  entire word for one build — the chip read `🔴 ✨` and nothing else — and it is
  close to invisible in review, because the *other* spawn state (a picked folder,
  wider chip) drew correctly and looked like proof the row was fine. Caught by
  `docs/overlay-states.html`, which is the whole argument for that page: a
  regression in a state that lasts two seconds, found by looking at all of them
  at once. The `Transcribing...` row had the same bug — a *spawn* dictation's wait was one mark
  and no word — fixed with the same `inline(Glyphs.emoji(…))`.
  → journal: *Two implementation traps, both paid for*; *The wait fills too (2026-09-08)*

## Type, ink, and drawn glyphs

- **One face, one size, one weight: every word on the chip is `hintFont` — system 17, regular.**
  *"toate textele care apar în tooltipul de lângă maus trebuie să aibă aceeași mărime de font și
  font face"* (2026-09-01). The title was semibold, the selection row 14, the waits semibold 20 —
  all three are 17 regular now. Emphasis is the glyph column's job. The **panel is exempt**
  (`promptFont`, the quote mark, the front line). → journal: *One face, one size, one weight — everywhere on the chip*
- **The waits are `iconInk`, white-plus-halo.** The hourglass was 30 pt `hintInk` for two days and
  went back to icon size on 2026-09-02 (*"clepsidra este prea mare"*); the fix that mattered was
  joining `refreshChrome`'s white-plus-halo list, the one place a row becomes legible on a bare
  chip. **Three rows have now been left off that list** (the selection row, then the waits) —
  check it for any new row. `hintInk` survives only for the two dormant hint rows that draw the
  mouse at 30 pt. → journal: *The wait is icon-sized, and it was the colour that mattered*
- **Wherever the UI has to show the mouse, draw his mouse — never an emoji** (2026-08-29).
  `Glyphs.mouse(height:pressed:)` takes a `Buttons` option set (`.left`, `.right`, `.wheel`,
  `.back`, `.forward`) and fills those regions in `.systemRed`. The silhouette is traced from the
  Logitech Signature M650 L wireframe (33 `(v, left, right)` samples in `mouseOutline`, aspect
  0.568, notch at v 0.34…0.47 interpolated, 3-tap smoothed); the wheel island spans u 0.382…0.620,
  the wheel 0.456…0.548. Learned by rendering to PNG: **a pressed part is outlined in its own
  colour, not the body's** (a grey ring round a red wheel renders at 16 pt as a grey wheel); **thumb
  buttons are drawn only when one of them is the button being named**; a 0.16-alpha wash fills the
  silhouette because an unfilled outline over a terminal is a few grey strokes with code showing
  through. The two dormant hint rows (`statusLines`, `hintRows`) draw it at 30 pt (`hintInk`),
  34 tall, no arrow between the two presses; `hintRowHeight` turns ink size into height so the same
  views also render 16 pt rows at 22. → journal: *The mouse is drawn, and the buttons the gesture presses are red*
- **`Glyphs.pin` and the folder are drawn by proportion, rasterised once.** Pin head tangent to the
  top with radius `0.348 × height`, sides are the **tangents** from the tip, hole punched `.clear`
  so the backdrop shows through; folder `1.25 ×` as wide as tall, tab diagonal at `0.44 × width`.
  `pinGlyph`/`folderGlyphImage` are rasterised once because the chip relayouts as it follows the
  cursor. **An inline drawn glyph IS possible** (measured 2026-08-29 with an `NSTextAttachment` in
  a fresh `NSTextField(labelWithString:)`): the "everything but the emoji comes out transparent"
  failure is the **title** label's, which carries a halo (`refreshChrome`) — `applyTitleText` is
  where that warning belongs. `RelayWindow.inline(_:font:)` is the helper; rows needing a glyph
  *between* words use it, rows whose glyph is what the row is *about* put it in the icon column.
  → journal: *What the chip says when bound: one row, and the destination app's own icon*

## The chip teaches nothing

- **`showsGestureHints` is off (2026-08-30) and the rows are still built and measured.**
  `shotHintText`, `pickHint`, `rebindText` and their glyphs exist; flipping the flag is the way
  back, and they must stay English. What is on the chip is *state*: the pulse, `Listening...`,
  `Transcribing...`, the destination, the tally. The model id lives in the menu's engine row
  (`StatusItem.applyWhisperTitle`), not on the chip. → journal: *The chip teaches nothing; the menu does*
- **The one exception is the `⌘⇧` row, shown while dictating *and* with Chrome in front.**
  It is on screen only when actionable, and the relay **takes ⌘⇧-click away from Chrome** while it
  is up. Once something is picked the row belongs to the picks whatever app is in front.
  `chromeFront` is pushed from `AppDelegate`'s front-app watcher (the one answering
  `frontIsBindable`): `NSWorkspace` is a main-thread question and this is read from
  `layoutContent`, which runs while the chip follows the cursor.
  → journal: *The chip teaches nothing; the menu does*

## Two shapes, and the pointer is clean

- **`anchored` is the switch: chip (rest and dictating) vs panel (the message, and only the
  message).** Anchored = bare text, no blur, no rounded rect, no shadow, alpha 0.80, trailing the
  cursor. Panel = top-left of the current screen, blur, ✕ on hover, full opacity, entered by a
  prompt and **by nothing else since 2026-09-02**. → journal: *Two shapes: the chip and the panel*
- **There is never a ✕ beside the pointer, in any state**: `anchored || !hovering`, not
  `bare || !hovering` — the old test put a ✕ on a flash riding the cursor (*"n-am cum să apăs pe
  el din moment ce acel tooltip se plimbă cu mouse-ul"*). The menu bar item is the ✕ that stays
  put. → journal: *Two shapes: the chip and the panel*
- **Dictating is not a panel state.** The panel is for what the model heard while Cancel can still
  stop it; the shot receipt is a number in the recording row, not a `flash(_:)`, because a flash
  takes the chip over for 1.5 s and the count has to keep climbing.
  → journal: *Two shapes: the chip and the panel*
- **Pinned to the pointer on every mouse event; growth into the panel animated 0.22 s ease out,
  everything else instant.** → journal: *Two shapes: the chip and the panel*
- **Unbound and idle, there is no overlay window at all.** `layoutContent` omits the title row when
  there is no destination, and `refreshPresence` counts any row as a reason to be on screen (not
  `rowCount > 1`). The `🛞 bind` row was tried and reverted within the hour (*"mă încurcă, mă
  enervează"*); as a login item the launch directory is `/`, so the old chip read `🤖 /` beside the
  pointer every waking hour. → journal: *The pointer is clean when nothing is bound*
- **`orderOut`, not `alphaValue = 0`.** An invisible panel still sits 10 pt right and 22 pt below
  the cursor and takes mouse events; one following him all day would swallow clicks. `typing` may
  fade to zero — it lasts a keystroke. → journal: *The pointer is clean when nothing is bound*
- **The rows decide presence, not a list of states.** `layoutContent` hands its row count straight
  to `refreshPresence`; the one state that changes the *title* instead of adding a row — bound — is
  named there explicitly. Coming back, the chip is `reposition`ed first so it lands where the
  pointer is now. → journal: *The pointer is clean when nothing is bound*

## Chrome, colour, placement

- **`let bare = anchored`: no border, blur, shadow or ✕ beside the pointer** (2026-09-02, *"toate
  tooltip-urile din jurul mouse-ului … niciunul nu mai trebuie să aibă border în jur"*). Legibility
  is paid by `bare` itself — white text with a halo. `flash(_:duration:bare:)` lost its parameter.
  → journal: *Nothing beside the pointer draws a window*
- **A flash replaces the collapsed chip rather than sitting under it.** `layoutContent` drops the
  title row while a flash is up **and** the chip is collapsed (the lone 🎙️): under a message it
  read as a microphone with a caption, and `🎙️ sent + 2 📸` came out as two microphones stacked.
  Only then — with a folder name in the row, the glyph is that line's icon.
  → journal: *Nothing beside the pointer draws a window*
- **Never hardcode a literal colour on a variable backdrop.** Dynamic system colours
  (`labelColor`, `secondaryLabelColor`, `textBackgroundColor`, `systemRed`) or translucent
  white/black only; custom views resolve them against `effectiveAppearance` inside `draw(_:)`, no
  observers. The ✕ was a hardcoded white cross — nearly invisible on dark mode's light disc.
  → journal: *Dark mode*
- **Opacity:**

  | state | alpha |
  |---|---|
  | idle chip | 0.80 |
  | every panel state | 1.00 |

  → journal: *Opacity states*
- **Chip: below-right of the cursor (`anchorGap`), flipped at screen edges — never half off-screen,
  never under the pointer. Panel: top-left of whichever screen the cursor is on**, position on
  that screen left alone, top edge anchored so it grows downward, and **never teleports while a
  mouse button is down**. → journal: *Placement*

## Do not

- **Do not reintroduce a leash, a smoothing filter or a spring**: every one of them is lag by
  construction, and the thing they were meant to make reachable is not there. The 0.25 s settle /
  70 px leash was *"nu e lipit de mouse, ci ceva care se trage lângă mouse … vreo jumătate de
  secundă lag"* (gone 2026-09-07). → journal: *Two shapes: the chip and the panel*
- **Never edit `docs/overlay-states.html` by hand.** → journal: *The overlay's states are photographed, and the page is part of the change*
- **The ramp timer and the transcribe timer must never reach `layoutContent`.** The only relayouts
  a dictation is allowed are the `HQ` tag's arrival and the once-a-minute `(Nm)` tick.
  → journal: *Two implementation traps, both paid for*
- **Never put a raw emoji into an attributed string on a label that carries a halo** — go through
  `inline(Glyphs.emoji(…))`. → journal: *Two implementation traps, both paid for*
- **The reward mark is the blue `HQ` tag, never ⭐ or ✨.** → journal: *A tag pops out when it fills (2026-09-08; it said `HQ` from 2026-09-09)*
