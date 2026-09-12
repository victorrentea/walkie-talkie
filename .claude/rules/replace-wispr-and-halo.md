---
paths:
  - "Sources/WalkieTalkie/CaretHalo.swift"
  - "Sources/WalkieTalkie/DropArrow.swift"
  - "Sources/WalkieTalkie/WisprWatch.swift"
  - "assets/caret-halo-5x5.png"
---

# Replace Wispr, the halo and the drop arrow

Rules for the caret-paste mode (Replace Wispr), the film halo that rides every dictation
(`CaretHalo`), and the arrow that asks for a place to paste (`DropArrow`).
Full history and reasoning: docs/journal.md — see the sections named after each rule below.

## Replace Wispr: the relay as a way to type

One menu tick (since 2026-09-02) turns the relay into a dictation tool for the machine: the
**forward side button** opens and closes the microphone and the words are **pasted at the caret** —
no outbox line, no terminal, no prompt panel, no countdown.

| | bound dictation | Replace Wispr |
|---|---|---|
| gesture | 🛞 | the forward side button |
| destination | the bound terminal | wherever the caret is |
| what travels | words, shots, selections, picks | the words, plus any shot or pick he took |
| review | the held prompt (`minHold`–`maxHold`, 4–7 s in code) | none — it is pasted |
| back button | the shutter | the shutter (was Return until 2026-09-08) |

- **The forward button, not the wheel.** Every wheel meaning is about a *terminal*; a mode that
  types into whatever is in front must not collide with them. It outranks the mouse-5 double click
  that binds a window — waiting out the double-click interval is exactly the wait Victor removed
  from the wheel. → journal: *Replace Wispr: the relay as a way to type*
- **`pasteMode` is decided at the press and consumed in `stopLocalRecording`** — read and cleared
  there, so a transcript landing a second later goes where the press said even if the tick was
  clicked since (the rule `Message.spawn` already follows). → journal: *Replace Wispr: the relay as a way to type*
- **A deliberate bind mid-sentence overrules it** (2026-09-09): left+wheel or ⌘⌃B during a caret
  dictation sends the words to that terminal, the chip stops saying `at caret`, and the 5 s bind
  grace applies. The mode itself is untouched. → journal: *Replace Wispr: the relay as a way to type*
- **No automatic context shot — and that survives the shutter being live.** The selection probe
  that comes with the frame posts a ⌘C into the field he is about to dictate into, which in this
  mode is the whole subject (*"nu trebuie să facă poză originală"*). The shutter, the ⌘⇧ pick and
  the selection watcher are live; nothing *automatic* is. → journal: *Replace Wispr: the relay as a way to type*
- **The chip says `at caret` behind the drawn map pin** (`RelayWindow.pinGlyph`, `Glyphs.mapPin`,
  not 📍), in the slot a spawn uses. **It stays up through the decode** and comes down where the
  words land and on every path that gives up on them (`clearSpawn`); a dictation that is neither a
  spawn nor a paste takes the row down as it opens, so a stale caret cannot ride the next sentence.
  `at caret`, not `at the caret` (2026-09-09). → journal: *Replace Wispr: the relay as a way to type*
- **Persisted across launches since 2026-09-07.** `AppDelegate` seeds the flag and the tap from
  `StatusItem.isReplaceWispr` **without** going through `setReplaceWispr`: that call flashes the
  overlay, and a restored mode is not an event to announce. → journal: *Replace Wispr: the relay as a way to type*
- **The transcript goes on the clipboard as well** (`pasteText`, shared with ⌘⌃P) and sets
  `lastDictation`, so a paste that landed somewhere unhelpful is one ⌘V away. → journal: *Replace Wispr: the relay as a way to type*
- **The menu row's icon is its state** — `checkmark` on, an empty box of the same size off — never
  `NSMenuItem.state`: a ticked row makes AppKit reserve the state column for the whole menu and
  shoves every other row sideways. → journal: *Replace Wispr: the relay as a way to type*
- **`POST /test/replace-wispr {"on": true}`** goes through `setReplaceWispr` like the row, so the
  tick, the tap's flag and the flash cannot say three different things. → journal: *Replace Wispr: the relay as a way to type*
- **The corpus keeps everything**: `captureLocal` runs before the branch. → journal: *Replace Wispr: the relay as a way to type*

## What a caret dictation carries (2026-09-08)

`AppDelegate.caretLine` is `terminalLine` with everything **automatic** taken out and everything
**deliberate** kept, in identical wording:

| clause | terminal | caret |
|---|---|---|
| the words | ✓ | ✓ |
| `[the shots I took: …]`, `[elements I picked in Chrome: …]` | ✓ | ✓ — identical wording |
| `[selected: …]` | ✓ | ✓ — identical wording, since 2026-09-09 |
| the context frame, `[Focused window: …]` | ✓ | — none is taken |
| `[this text was dictated in RO or EN…]` | ✓ | — |

- **Paths stay, the language hint goes.** A path or selector is noise he asked for by pressing a
  shutter; the hint is unconditional ceremony, and a stray sentence about mis-hearing pasted into a
  Slack message is the mode failing at its one job. → journal: *What a caret dictation carries (2026-09-08)*
- **Selection is filed here too** (2026-09-09): `plusOneShot` calls `stashExtraSelection` (the only
  route that sees a highlight in a Chrome page) and `syncSelectionWatch` gets a bare `live`. Mind
  what the caret sits in — a selection made *in the target field* to be replaced by the dictation is
  one this will file; it has to settle two seconds first and the chip says `“ selecting …`. → journal: *What a caret dictation carries (2026-09-08)*
- **Open the bookkeeping by hand.** `captureContext` is never called in this mode, so
  `dictationInFlight` (makes `plusOneShot` attach rather than send alone) and `dictationStartedAt`
  (the zero every shot is named from) must be set explicitly, or a shot is named by wall-clock and
  dropped for want of a destination. → journal: *What a caret dictation carries (2026-09-08)*
- **`caretLine` clears `pendingScreen` even though it can never be set** — `shotsClause(screen:
  nil)` regardless, so a frame that did arrive cannot survive to the next sentence. → journal: *What a caret dictation carries (2026-09-08)*
- **Both `/test` routes honour the mode**: `/test/dictation/start` opens a caret dictation when
  Replace Wispr is on, `/test/dictation` pastes `caretLine` instead of calling `send`. → journal: *What a caret dictation carries (2026-09-08)*
- **Every AppKit call in an `ElementPicker` callback needs its own main hop.** The first start route
  called `overlay.setSpawnDestination` on the picker's listener thread; `layoutContent` set a window
  frame and the app died with `SIGTRAP` inside `NSWMWindowCoordinator`. → journal: *What a caret dictation carries (2026-09-08)*

## The halo: up for every dictation, breathing on the voice (2026-09-11)

- **`CaretHalo` is up for every dictation, not only a caret one; it is the beacon now.** Its
  alpha and its scale both ride `MicRecorder.level`: envelope `floor + (ceiling − floor) × level`
  sampled at 20 Hz, with the three-second linear fall living in `MicRecorder`. `rest` 0.075 /
  `loud` 0.225 × `artworkGain` 1.98 → **0.148 / 0.445** window alpha; the swell is a scale of 0.2
  off the same sample (*"chiar 20%"*) — from the voice, never a timer. Measured: 94.5 pt at rest vs
  113.5 pt at full voice, ratio 1.201. → journal: *It is the beacon now, and it breathes on his voice (2026-09-11)*
- **The panel `side` grew by the same 20 %.** It was measured to hold exactly the falloff at rest,
  so at full voice the outer glow was cut off square by its own window — found on the contact sheet,
  not on screen. → journal: *It is the beacon now, and it breathes on his voice (2026-09-11)*
- **Silence no longer brightens the ring.** It answers *is the microphone open*; `patience` and
  `swell` (2 s each) are `DropArrow`'s schedule now. → journal: *It is the beacon now, and it breathes on his voice (2026-09-11)*
- **`RelayPanel`, not `NSPanel`.** `constrainFrameRect` would shove the ring off the cursor at the
  top of the screen. Same trap as `BindFlight` and `UnbindPop`. → journal: *The ring round the pointer, when the destination is not a place (2026-09-09)*
- **Global *and* local mouse monitors** — the chip rides the same cursor and is not click-through,
  so without the local half the ring stops dead when the pointer crosses it. → journal: *The ring round the pointer, when the destination is not a place (2026-09-09)*
- **`sharingType = .none`, verified twice**: `screencapture -l <window id>` answers *could not
  create image from window*, and a whole-screen shot with the halo up shows no gold annulus (mean
  R−B in the core band −19.03 vs −17.20 outside, where 5 % would have added +11). It therefore
  cannot be reviewed with a screenshot either — that is what `WT_SHOOT_HALO` is for. → journal: *The ring round the pointer, when the destination is not a place (2026-09-09)*
- **`NSColor.systemYellow` is never used** — dynamic, shifts with appearance; this is drawn over
  whatever is on screen. → journal: *The ring round the pointer, when the destination is not a place (2026-09-09)*
- **Both edges are logged** (`◯ caret halo on/off`): nothing behind them is visible on screen. → journal: *The ring round the pointer, when the destination is not a place (2026-09-09)*

## The film asset (`assets/caret-halo-5x5.png`)

- **25 frames of his GIF (`neon-electric-ring.gif`, 236 px, 20 fps), keyed off black with
  `a = max(r,g,b)`, packed five across.** A glow on black is its own premultiplied form, so the key
  is exact — the difference from the September reference that came out olive mud. → journal: *What ships now: his picture, and it runs as a film (2026-09-10)*
- **The grid comes out of the file name** (`-<cols>x<rows>`, absent = one frame); a still and a
  film are the same code path. → journal: *What ships now: his picture, and it runs as a film (2026-09-10)*
- **Measure the film once, not per frame.** The mean ring radius over all 25 (86 px) is mapped onto
  `core` (105 pt) with one transform; per-frame measurement lets the ring breathe a pixel or two,
  which reads as pulsing out of true. → journal: *What ships now: his picture, and it runs as a film (2026-09-10)*
- **The envelope is a `CAGradientLayer` mask, not a pixel pass** — 25× the launch cost otherwise. → journal: *What ships now: his picture, and it runs as a film (2026-09-10)*
- **Discrete keyframes on `contents`, `isRemovedOnCompletion = false`.** Lightning does not tween;
  and the panel is ordered out between dictations rather than rebuilt, so a self-tidying animation
  leaves a still ring the second time. → journal: *What ships now: his picture, and it runs as a film (2026-09-10)*
- **A third of the GIF's rate, 6.7 fps** (*"mai lentă animația 3×"*): 25 frames come round in
  3.75 s. Faster is a flicker at the edge of vision. → journal: *What ships now: his picture, and it runs as a film (2026-09-10)*
- **Light is matched on the panel, not in the bitmap.** The film carries 0.51× the band's flux, so
  `artworkGain` is 1.98; any gain in the pixels flattens the filaments into a solid annulus. → journal: *What ships now: his picture, and it runs as a film (2026-09-10)*

## The plateau envelope

- **Full alpha across the central fifth of the ring's thickness, ramps to zero at both rims,
  `rampGamma` 2.2, `core` 105.** Two fades compose: this spatial one, fixed, and the temporal one on
  the whole panel. Gamma puts the ramp mid-point at 19 % (inner ramp mid 20 % → 6 % of band ink,
  outer 21 % → 9 %). → journal: *What ships: `codex3`, and the envelope became a plateau (2026-09-10)*
- **`plateauInner` / `plateauOuter` are named because two things read them** — the envelope and
  any texture that spreads across the plateau — and must not drift apart. → journal: *What ships: `codex3`, and the envelope became a plateau (2026-09-10)*
- **The flux-gain clamp belongs on the ink, envelope applied after.** `min(1, coverage × gain ×
  envelope)` saturated every pixel with envelope > 0.4 at gain 2.5 and cut both ramps to a hard
  edge. → journal: *What ships: `codex3`, and the envelope became a plateau (2026-09-10)*
- **Spread texture by `sqrt` of the lane, not evenly in radius** — an annulus at r has 2πr to fill;
  a constant count per radius was 40 % down by the outer circle inside the "uniform" plateau. → journal: *What ships: `codex3`, and the envelope became a plateau (2026-09-10)*

## Spin, collapse, layers

- **16 s clockwise per revolution** (41 pt/s at the rim, `CursorMarker`'s direction). → journal: *It turns while it is up, and it collapses into the pointer when it goes (2026-09-10)*
- **Close is a 0.5 s collapse to 2 %, not `orderOut`.** Scale and ink are sampled against one eased
  progress (smoothstep, 24 steps) and the fade keyed off the last fifth of the *travel*. 2 %, not
  zero: a layer scaled to nothing has no defined last frame. → journal: *It turns while it is up, and it collapses into the pointer when it goes (2026-09-10)*
- **It keeps chasing the pointer while collapsing**: mouse monitors outlive `hide` by 0.5 s, so
  `show` installs them only when none exist — a dictation opening inside the collapse would leak a
  pair. → journal: *It turns while it is up, and it collapses into the pointer when it goes (2026-09-10)*
- **Three layers — `stage` (collapse), `pulse` (swell), film (spin) — because two animations on one
  `transform` overwrite rather than compose.** The stage is ours, not the view's backing layer,
  which AppKit resets on any layout. → journal: *It is the beacon now, and it breathes on his voice (2026-09-11)*
- **Neither animation writes a model value.** The spin is `isRemovedOnCompletion = false`; the
  collapse fills forwards and is removed on the beat the panel is ordered out, so the layer snaps
  back unseen — or the next ring comes up at 2 %. → journal: *It turns while it is up, and it collapses into the pointer when it goes (2026-09-10)*
- **A `show` mid-collapse takes it back whole**: animations removed, a generation counter
  invalidating the delayed `orderOut` — otherwise the old tidy-up puts the new ring away half a
  second after it came up. → journal: *It turns while it is up, and it collapses into the pointer when it goes (2026-09-10)*

## The ring covers Wispr Flow's dictations too (2026-09-11)

- **`WisprWatch` lights the ring while Wispr Flow holds the microphone, with no gate.** Replace
  Wispr is down most days and with it down Wispr Flow is what he dictates into everywhere — *"în
  orice context în care dictez … că este la cursor, peste tot"*. Halo active is `listening ||
  wisprDictating`. → journal: *The ring covers Wispr Flow's dictations too (2026-09-11)*
- **The signal is `kAudioProcessPropertyIsRunningInput` on every audio process object whose bundle
  id has the prefix `com.electron.wispr-flow`** — prefix and OR, because Electron spreads over
  `.helper` and `.accessibility-mac-app` and which one holds the device changes between versions.
  → journal: *The ring covers Wispr Flow's dictations too (2026-09-11)*
- **Never use the device's `DeviceIsRunningSomewhere`** — measured 2026-09-11 with nothing being
  dictated, `ai.krisp.krispMac` and `com.rogueamoeba.audiohijack` sit at `runningInput = 1` all
  day. A flag that is always true is not a signal. → journal: *The ring covers Wispr Flow's dictations too (2026-09-11)*
- **Never draw it from `HotkeyTap.postWisprHandsFree` instead.** That chord is a *toggle this app
  sends*, so the state drifts the moment Wispr misses one or he stops from Wispr's own window, and
  it is blind to a dictation started from the keyboard. → journal: *The ring covers Wispr Flow's dictations too (2026-09-11)*
- **Listen on the process list as well as on each process.** An Electron helper is only filed as an
  audio object once it first touches audio, so the one that will hold the microphone this afternoon
  may not exist at launch. → journal: *The ring covers Wispr Flow's dictations too (2026-09-11)*
- **The ring breathes because the relay opens its own microphone alongside Wispr's**
  (`MicRecorder.startMetering`, a second `MicRecorder`) — a boolean cannot drive a ring that moves
  on syllables, and a timer is the substitution the beacon died for. Nothing is written; see the
  whisper rule. `AppDelegate.voiceMeter` picks the relay's own session when it is running. → journal: *The ring covers Wispr Flow's dictations too (2026-09-11)*
- **`atCaret` is `pasteMode || (wisprDictating && !listening)`** — Wispr pastes at the caret, so the
  arrow belongs there too (*"Da, ca la at-caret"*); the relay's own live dictation outranks it on
  that half only, because the chip is naming a destination. → journal: *The ring covers Wispr Flow's dictations too (2026-09-11)*

## `DropArrow` — six heads closing in (2026-09-12)

- **Armed on `pasteMode`, re-read on every `setActive`**, so a ⌘⌃B mid-sentence gives the words a
  terminal and the heads stop asking; the ring stays up. → journal: *`DropArrow`: three dashes and a head, pointing down at the cursor (2026-09-11)*
- **`CaretHalo.patience` 2 s of quiet, then `swell` 2 s up to 0.75.** Two seconds because gaps
  inside a sentence are ordinary. Measured 0.164 → 0.333 → 0.483 → 0.633 → 0.750. → journal: *`DropArrow`: three dashes and a head, pointing down at the cursor (2026-09-11)*
- **Three heads above pointing down, three below pointing up, symmetric about the hot spot** —
  `gap` 18, `step` 13, so 18…44 pt out, inside the halo's hole and the faint inner ramp. The old
  single dotted arrow is gone: an arrow hanging above the pointer is a thing to *read*, it costs a
  fixation, and it is off-centre by construction. → journal: *Six heads closing in, instead of one arrow hanging above (2026-09-12)*
- **The flash runs outside → inside**, phased with **`timeOffset`, never `beginTime`**: the panel is
  built once and shown again on every silence for the rest of the day, so an absolute timeline point
  would phase them against whenever it happened to be built. → journal: *Six heads closing in, instead of one arrow hanging above (2026-09-12)*
- **Both heads of a ring share one layer**, so the pair cannot drift a frame apart and read as two
  hints. **Open Vs, never filled triangles** — a stroke is a direction, a fill is an object in the
  way. **Linear**, the dashes' old rule: a hint that eases is a hint being admired. → journal: *Six heads closing in, instead of one arrow hanging above (2026-09-12)*
- **`dim` 0.40, measured off the white half of the sheet** — at 0.28 the unlit heads vanished on
  paper (0.28 × `ceiling` = 0.21 of amber on white). Amber with a shadow outline, so it is neither
  part of the blue-and-magenta ring nor lost on a page. → journal: *Six heads closing in, instead of one arrow hanging above (2026-09-12)*
- **Leaving is a 0.18 s fade (`recall`), not a cut** (*"ele fac fade-out repede"*), and it needs the
  `fading` flag: every 20 Hz tick would otherwise start another, and an overruled fade's completion
  handler would order out a panel that is visible again. `hide()` stays a hard cut. → journal: *Six heads closing in, instead of one arrow hanging above (2026-09-12)*
- **Its own window, never a layer in the halo's panel.** The halo's window alpha *is* the voice and
  these appear when the voice has stopped: as layers they were drawn through the ring's floor,
  0.75 × 0.148, a stain no layer opacity recovers. `CaretHalo.follow` places both off one
  `origin()` in one call, so they cannot be a frame apart. → journal: *`DropArrow`: three dashes and a head, pointing down at the cursor (2026-09-11)*
- **`DropArrow.picture()` is posed, not animated** (`ChipWipe.shoot`'s rule) — the middle ring lit,
  the only frame that shows what the sweep is doing. → journal: *Six heads closing in, instead of one arrow hanging above (2026-09-12)*

## Tooling

- **`WT_HALO_DEMO=25` is the only thing that sets `CaretHalo.capturable`** (`.readOnly`); the
  demo has no dictation, transcript or chip in frame. It drives a fabricated voice (six seconds of
  syllables at 3 Hz, six of silence) and ends with the collapse. Measured off the window server:
  alpha rides 0.148 → 0.445 and sits flat at the floor through silence; six `screencapture` crops
  show a different filament pattern in each (mean abs diff 1.0–1.6) — the film, which no still can
  show. → journal: *`WT_HALO_DEMO` — the answer to *does it actually move**
- **The sheet cannot catch an animation bug — `WT_HALO_DEMO` is the regression check.**
  `DropArrow.picture()` is *posed*, so it never builds the flash at all; a static render of the six
  heads looked perfect on the build that crashed the app 7 s into the first dictation that raised
  them. `WT_HALO_DEMO=11` arms the arrow and crosses `patience` at t=8: measured 2026-09-12, exit
  **133** (SIGTRAP) with the bug and **0** with it fixed. Run it after touching anything animated
  here. → journal: *Six heads closing in, instead of one arrow hanging above (2026-09-12)*
- **`WT_SHOOT_HALO=/tmp/halo.png` draws the sheet and quits** — two grounds (dark, light), state
  columns carrying each row's own `opacity(_:for:)` with gain, and a full-strength column with no
  gain, to judge the falloff. It also writes `/tmp/halo-arrow.png` (`CaretHalo.shootArrow`), the
  only way to see the arrow at all; the arrow is drawn at its own opacity in its own host so the
  sheet cannot reproduce the stain bug. → journal: *`WT_SHOOT_HALO` — because a falloff cannot be judged from code*
- **When a sheet is downscaled for review, say by how much.** The first review measured 2–3 px
  strokes off a 4× downscaled sheet; they were 8 px. → journal: *Spokes: the halo stylised with lines (2026-09-10, in progress)*
- **`/test/dictation/start` opens no microphone**, so `level` and `quietSeconds` stay at zero and
  the halo sits at rest for ever there — it reads exactly like a broken swell and is not one. → journal: *What ships: `codex3`, and the envelope became a plateau (2026-09-10)*

## Measured findings that still bind the design

- **Peripheral vision is a low-pass filter; hairlines have no low frequencies.** Through a mild blur
  six stroke designs lost 86–94 % of contrast where the smooth band lost 14 %. This mark is only
  ever seen out of the corner of an eye. → journal: *Spokes: the halo stylised with lines (2026-09-10, in progress)*
- **Strokes cannot reach the band's visibility — the brief as stated is unsatisfiable.** The band
  covers 20.4 % of its disc at peak; strokes top out at 9–15 % before they stop being strokes, and
  no opacity setting recovers a fill factor. Mass out of geometry, never out of alpha. → journal: *Spokes: the halo stylised with lines (2026-09-10, in progress)*
- **Spinners, compasses and marquees are all wrong readings**: arcs/spirals say *wait*, cardinal
  axes give direction, two dotted circles are marching ants. → journal: *Spokes: the halo stylised with lines (2026-09-10, in progress)*

## The beacon is gone (2026-09-11)

- **`RecordingBeacon.swift` is deleted; do not bring back a microphone on the bottom edge.** The
  halo is drawn round the thing his hand is on, which is the spot the beacon moved twice failing to
  find. `CaretHalo.refresh` is `RecordingBeacon.watchLevel` with a scale spent alongside the alpha. → journal: *The beacon is gone — the halo took its job (2026-09-11)*
- **Pointer-avoidance and one-panel-per-display are deliberately gone.** A mark centred on the
  cursor cannot be in its way and is on the pointer's screen by construction. → journal: *The beacon is gone — the halo took its job (2026-09-11)*

## Do not

- **Do not re-key the September reference image.** Keyed off its flat `(246,246,246)` white it is
  the better picture at 100 % and nothing at all at 15 %; if the halo is ever wanted with texture,
  the opacities have to go up with it. → journal: *The ring round the pointer, when the destination is not a place (2026-09-09)*
- **Do not gate the ring on `pasteMode` or `isBound`** — it is the microphone's beacon now, and
  since 2026-09-11 that includes a microphone another app opened. → journal: *It is the beacon now, and it breathes on his voice (2026-09-11)*
- **Do not write `.map(NSNumber.init)` for `keyTimes` or `values`.** That bare function reference
  compiles and resolves to an **`NSValue`** initialiser, so the array fills with `NSConcreteValue`,
  which has no `floatValue`; QuartzCore's `copyFloatVector` then throws an unrecognised-selector
  **NSException inside the `CATransaction` flush**, which Swift cannot catch — the app dies with
  `SIGTRAP` in `-[NSApplication _crashOnException:]` and nothing in the relay log says why. Bare
  literals under a `[NSNumber]?` contextual type bridge correctly (`__NSCFNumber`), and that is what
  every other keyframe in this app uses. → journal: *Six heads closing in, instead of one arrow hanging above (2026-09-12)*
- **Do not breathe the ring on a timer.** A ring breathing on a clock proves a clock is running,
  the substitution that took the beacon's own free-running blink out. → journal: *It is the beacon now, and it breathes on his voice (2026-09-11)*
- **Do not post a context shot or a ⌘C probe in Replace Wispr.** → journal: *Replace Wispr: the relay as a way to type*
