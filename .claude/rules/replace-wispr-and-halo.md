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

A mode (since 2026-09-02) that turns the relay into a dictation tool for the machine: the
**forward side button** opens and closes the microphone and the words are **pasted at the caret** —
no outbox line, no terminal, no prompt panel, no countdown.

**It has no menu row since 2026-09-14.** `Replace WisprFlow` was replaced in the menu by the
`Engine` picker, on Victor's reading that a checkbox named after another app says *that app: yes or
no* rather than *which recogniser*. Nothing about the mode changed: the flag, the preference key
and the forward button are where they were, the flag simply moved from `StatusItem` to
`AppDelegate.replaceWisprKey`. What it costs is that the mode can now only be turned over through
`POST /test/replace-wispr`, and that the chip's `⌨️ at the caret` is the only place it can be read.
The mouse-5 legend went with the row. → `.claude/rules/menu-bar.md`, *The Engine row*

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
- **The transcript goes on the clipboard as well** (`pasteText`, shared with ⌘⇧P) and sets
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
| `screenshots during dictation are in: …` (was `[the shots I took: …]` until 2026-09-13), `[elements I picked in Chrome: …]` | ✓ | ✓ — identical wording |
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
  `loud` 0.27 (**+20 % on 2026-09-16**, was 0.225 — only the bright end moved, so what got louder is
  the difference a syllable makes) × `artworkGain` 1.98 → **0.148 / 0.535** window alpha; the swell is a scale of 0.2
  off the same sample (*"chiar 20%"*) — from the voice, never a timer. Measured: 94.5 pt at rest vs
  113.5 pt at full voice, ratio 1.201. → journal: *It is the beacon now, and it breathes on his voice (2026-09-11)*
- **Every ring grows out of the pointer** (2026-09-12 for a bound sentence, **all of them since 2026-09-14**): `setActive(opening:)` holds the stage at `collapseEnd` and blooms it to full size over `expand` — 0.5 s, the collapse reversed, which is the *"durată comparabilă cu cea de închidere"* he asked for and the reason nothing about the animation itself changed. `CaretHalo.Opening` has three cases and the only difference between the two blooming ones is what they wait for: **`.afterFlash`** waits for `grow()`, called beside `CaptureFlash.announce`, so a bound or spawn ring comes out of the mark the yellow bubble has just made (`growGrace`, 1.5 s, grows it anyway if no bubble comes; `growOnShow` remembers a `grow()` that landed before the ring was up, because `dictationBegan` takes the picture a line before it raises the ring); **`.fromPointer`** blooms one main-queue hop after `orderFrontRegardless` — for every dictation that announces nothing, where the bloom *is* the arrival and `growGrace` would be a second and a half of a four-point dot. `.whole` is left for the state shots. `grow()` on a ring not held small is a no-op, so there is never a second bloom. Victor: *"să apară din cursor și să se mărească inelul dictării"* (09-12), then *"să apară din mouse, să se mărească în momentul în care începe să asculte … se mărește din centru spre exterior"* (09-14). → journal: *The ring grows out of the pointer (2026-09-12)*, *Every ring grows out of the pointer now (2026-09-14)*
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

## The ring covers them again, in every engine (2026-09-18)

The half of the 09-11 rule above **was lost on 09-12** and nobody noticed for six days: when Wispr
Flow became the *source*, `wisprDictating` came out of the halo's gate on the reading that
`listening` now covered every Wispr dictation. It does not. `listening` is **the relay's own
sentence**, so the ring went dark for exactly the dictations the 09-11 section exists for — the
ones he starts himself. Victor, 2026-09-18: *"când pornesc Wispr Flow cu gestul de mouse back sau
când activez eu Wispr Flow cu tastele … să apară același cerc cu fulger în jurul cursorului …
fulgerul să arate că cineva ascultă"*.

- **Halo active is `listening || speculative || wisprHearing`.** The third is
  `AppDelegate.wisprHearing`, fed by `WisprFlowSource.hearingChanged` — every edge of
  `WisprState.listening`, wired **at launch** beside the music pause rather than in
  `wireDictationSource`. That is what makes it work in every engine: with the Engine on the local
  model or on ElevenLabs the Wispr source is not wired at all, so none of the five
  `DictationSource` events fire, and 🔽 → posts Wispr's chord raw in **all** of them.
- **Not `WisprWatch`, though it is the witness the 09-11 rule names.** Measured 2026-09-13 it is
  0–6 s late and produced **no edge at all** in five of five runs, and with the Engine elsewhere
  this source's `watch` is never started. `WisprState` joins it with Wispr's `History` row, written
  at the gesture — 182 ms, measured 2026-09-18. Same reason `hearingChanged` and not a second
  CoreAudio reader.
- **The ring, and nothing else, for a microphone that is not ours** — `foreignMic`, i.e.
  `wisprHearing && !listening && !speculative`, forces `atCaret` to false. This **reverses** the
  09-11 line two sections up (*"`atCaret` is `pasteMode || (wisprDictating && !listening)`"*), for
  two reasons: the heads promise *the words are landing here, do not move the mouse* about a
  delivery this app is not making, and their schedule is silence read off `source.meter`, which for
  a foreign dictation is a recorder that is not running — a **stale** reading, not a quiet one.
  Victor asked for the lightning and explicitly for nothing else: *"fără tooltip neapărat"*.
- **It will not breathe, and that is honest.** The ring pulses on `source.meter.level`; nothing
  opens the relay's microphone for a sentence it is not running. It sits at rest alpha, which is
  the whole of what is known — *a microphone is open*.
- **The edge goes through `syncBorrowedGestures`, not `syncMusic`.** The halo hangs off that one
  switch and the music is synced from inside it; everything else it recomputes is unchanged by a
  foreign microphone, so the rest is a no-op by construction.
- **The 600 s ceiling takes the ring down with the music.** `wisprHearingCap` calls
  `wisprIsHearing(false)` rather than undoing the flag by hand — a ceiling that undoes two of three
  things leaves a ring at the pointer for ever, which is the 09-15 failure the idle sweep exists
  for.
- **`GET /test/state.wisprHearing`** is why the ring is up when `listening`, `speculative` and
  `settling` are all false. Nothing that rides the pointer can be screenshot, so without it that
  ring is unexplainable from a desk.

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

## The heads stay up while the words travel to the caret (2026-09-15)

Victor: *"dacă dictez la caret, după ce dictarea se oprește, fulgerul dispare, doar că rămân
săgețile care curg până când efectiv se inseră textul la caret … să-mi atragă atenția că dictarea
încă se procesează și curge spre cursor și să nu plec cu cursorul de acolo."*

- **`CaretHalo.setDelivering(settling && settlingAtCaret)`**, driven from `syncBorrowedGestures`
  **before** `setActive` — the collapse reads the flag to decide whether the arrow goes down with
  the ring. `arrow.armed = (on && atCaret) || delivering`.
- **Only the caret case, and only the heads.** A bound sentence is addressed to a terminal and the
  mouse may go where it likes; the ring stays *microphone open* and still goes down at the stop,
  because a ring standing over a sentence already pasted into Word is the 09-13 lie this must not
  bring back. The heads were never about the microphone, which is why they are the half that can
  stay.
- **`DropArrow.hold(at:)` outranks the meter.** `refresh(quiet:)` ramps with the silence, which is a
  question about whether he has stopped talking; past the close the answer is yes, and a meter still
  answering must not dim the heads. `holding` is idempotent (it is called from every `follow`), fades
  in over `recall` rather than the swell's 2 s — the wait has already begun — and is cleared only by
  `hide()`.
- **They go in a cut, at the ⌘V.** `endSettling` for this mode *is* the paste (`pasting at the
  caret`, a line before `pasteText`), and what replaces them is the words appearing. A fade there is
  a hint still asking him to stay put after the sentence has landed.
- **The pointer monitors outlive the ring now** — `releaseMonitorsIfIdle()` (`!live && !closing &&
  !delivering`), and `follow()` runs on `live || closing || delivering`. `follow` is what moves the
  heads; a teardown that asked only about the ring would leave them standing where the pointer used
  to be, which is the opposite of what they are up to say.
- **`GET /test/state.arrowsUp`** is the only way to assert this — nothing that rides the pointer can
  be screenshot.

## The ring is up before anything is opened (2026-09-12)

Victor, 2026-09-12: the ⚡ ring has to be on screen **when Wispr Flow starts recording** — not
when the first level sample arrives, not when the first word is transcribed.

- **`syncBorrowedGestures()` runs first on the edge, `startMetering()` second.** It was the other
  way round, and the other way round put a synchronous device open in front of the beacon. Measured
  on a build with no microphone grant: `-[AVAudioEngine inputNode]` **never returned**, so the old
  order was a Wispr dictation with no ring at all rather than one with a ring that does not
  breathe. The ring needs no level to be drawn — `show()` puts it at `rest` and the 20 Hz timer
  picks the swell up on its next tick. → journal: *The ring is up before anything is opened (2026-09-12)*
- **The Wispr meter is opened and closed on `wisprMeterQueue`, never on main.** Serial, and both
  edges go through it, so a `stop` cannot overtake the `start` it undoes. → journal: *The ring is up before anything is opened (2026-09-12)*
- **`MicRecorder.level` and `.quietSeconds` use `lock.try()` and return the last value when
  contended.** They are read from the halo's 20 Hz timer on the main thread, and `start(to:)` holds
  the same lock across the device open — so a blocking read freezes the app, ring included, for as
  long as opening a microphone takes. A 20 Hz readout has nothing to gain from being exactly current
  and everything to lose from being late. → journal: *The ring is up before anything is opened (2026-09-12)*
- **`CaretHalo.prewarm()` builds the panel at launch.** `makePanel` decodes the 236×236 ×25 sheet
  and integrates its alpha twice (centroid + flux for `artworkGain`); measured **419–438 ms**, and
  it was being spent on the main thread inside the first `show()`. Same trade the Whisper weights
  already make: the relay is a login item that is up before he is. The log line says how long it
  took, and `◯ caret halo film` appearing *after* `◯ caret halo on` in a log is the symptom of this
  regressing. → journal: *The ring is up before anything is opened (2026-09-12)*
- **`⚡ ring up <n> ms after Wispr Flow opened the microphone` is written on every real edge**, off
  `WisprWatch.edgeAt` (stamped on the watcher's queue just before the hop to main). It is suppressed
  for `POST /test/wispr`, which enters below the watcher and would print the age of the last real
  dictation. → journal: *The ring is up before anything is opened (2026-09-12)*
- **The chevrons are not gated on a binding and never were.** `atCaret` is `pasteMode ||
  (wisprDictating && !listening)` and `syncBorrowedGestures` reads no `hasDestination` for the halo,
  so an unbound Wispr dictation arms `DropArrow` exactly like a bound one. When they appeared to be
  missing unbound it was the `.map(NSNumber.init)` crash below: the heads are built at
  `patience`, so *every* Wispr dictation with a two-second pause took the app down at the instant
  they were due. → journal: *The ring is up before anything is opened (2026-09-12)*

## The ring is up on Wispr's keystroke, not its microphone (2026-09-12, second pass)

Moving the ring ahead of `startMetering` was not enough — Victor still saw it arrive late. The
CoreAudio edge is the *truth* but not the *first* moment: Electron has to wake, raise its overlay
and open a device before `IsRunningInput` flips.

- **`HotkeyTap.onWisprMaybeStarting` fires on Wispr Flow's own start gestures, read out of its own
  config** — `~/Library/Application Support/Wispr Flow/config.json`, `prefs.user.shortcuts`, keyed
  by keycodes joined with `+`: **`49+59+63` = `popo`** (fn ⌃ Space, the hands-free toggle
  `postWisprHandsFree` already posts) and **`54+61` = `ptt`** (right ⌘ + right ⌥ held,
  push-to-talk). Watched, never taken. → journal: *The ring is up on Wispr's keystroke (2026-09-12)*
- **Push-to-talk is two modifiers and produces no `keyDown`** — it is a `flagsChanged`, and the
  test has to be on the **device-dependent** bits (`NX_DEVICERCMDKEYMASK` 0x10,
  `NX_DEVICERALTKEYMASK` 0x40). `.maskCommand`/`.maskAlternate` would raise the ring on every ⌘⌥ in
  the day. → journal: *The ring is up on Wispr's keystroke (2026-09-12)*
- **A speculative ring must be able to be taken back.** `wisprSpeculativeGrace` 1.5 s: if no
  microphone follows the keystroke, the ring goes down and says so. A beacon that lies is worse
  than one that is late — that is the whole reason the CoreAudio edge stayed the confirmation.
  → journal: *The ring is up on Wispr's keystroke (2026-09-12)*
- **Both numbers are logged**: `⚡ ring up <n> ms after <gesture> (speculative …)` and
  `⚡ mic edge confirms the ring <n> ms after the hotkey`. Measured through the test route, the
  first is **0.6–0.7 ms**. → journal: *The ring is up on Wispr's keystroke (2026-09-12)*
- **The meter comes up with the guess**, not with the confirmation, so the ring breathes from the
  first syllable. `start(to:)` is a no-op on a session already open, so the confirming edge costs
  nothing. → journal: *The ring is up on Wispr's keystroke (2026-09-12)*

## The ring goes down when the words land (2026-09-12)

Victor: the ⚡ ring and the chevrons go away when the text is **inserted**, not when the microphone
closes. Between the two is the whole transcription — the stretch in which he is waiting.

- **`settling` is a fourth reason for the ring to be up**, beside `listening`, `wisprDictating` and
  `wisprSpeculative`, and it carries `settlingAtCaret` so the chevrons do not disarm underneath it.
  → journal: *The ring goes down when the words land (2026-09-12)*
- **A Wispr paste is another app's ⌘V; the pasteboard's `changeCount` is the only thing there is to
  observe.** Polled at 20 Hz *only while settling*. Wispr writes the transcript there and presses
  ⌘V, exactly as `pasteText` does. → journal: *The ring goes down when the words land (2026-09-12)*
- **The relay's own caret dictation ends its settle from `pasteText`**, at the ⌘V and not at the
  transcript: the words are on screen when the key goes out. `watchClipboard: false` there — it
  *is* the paste and needs no guessing. → journal: *The ring goes down when the words land (2026-09-12)*
- **A bound dictation is deliberately not settled.** Its words go through the held prompt, up to
  seven seconds of countdown with a panel already saying so; a ring over that is a second indicator
  for a state that has one, and it would outlive `settleTimeout` besides. → journal: *The ring goes down when the words land (2026-09-12)*
- **`settleTimeout` 6 s, and the log says which ended it** — `⚡ ring down: <reason> — <n> ms after
  the recording ended`, one of *pasted at the caret* / *Wispr pasted at the caret* / *timed out
  waiting for the text* / *nothing was recorded*. That line is what makes "the ring went away too
  early" answerable from the file. → journal: *The ring goes down when the words land (2026-09-12)*
- **A cancel never settles.** There are no words to wait for, so the ring goes at once
  (`wisprCancelling` tells the closing edge that follows Wispr's Escape not to start one).
  → journal: *The ring goes down when the words land (2026-09-12)*

## The ✕ cancels the dictation (2026-09-12)

- **The ✕ on the overlay cancels the dictation in flight, and only ends the session when there is
  none.** It is hidden until the pointer is over the overlay and the overlay is a panel he can reach
  *during* a dictation — so at the one moment it is reachable it must mean *stop this sentence*, not
  *quit the app that drew the ring*. `AppDelegate.cancelDictationInFlight` returns whether there was
  anything to cancel; the ✕ falls through to `endSession` when there was not. → journal: *The ✕ cancels the dictation (2026-09-12)*
- **⬅️ cancels a Wispr dictation too** (2026-09-12): `hotkeys.onLocalCancel` — the forward button
  held and the mouse flicked left (`VK_F11` under ⌃⌥⌘), and the wheel held with Logi gestures off —
  goes through `cancelDictationInFlight` like the ✕ and the menu row. The gesture that abandons a
  sentence must not depend on which app is hearing it; local behaviour is untouched because
  `localRecording` is tried first. → journal: *The ✕ cancels the dictation (2026-09-12)*
- **A Wispr Flow dictation is cancelled with `HotkeyTap.postWisprCancel()` — ⌃Escape on the wire.**
  **Not a bare Escape.** Wispr's own config files `53+59` as `dismiss` — Escape plus Control — in
  the same `prefs.user.shortcuts` map as the hands-free chord. A bare Escape is whatever the app
  under the caret does with Escape.
  Built out of `postWisprHandsFree` and sharing everything that makes it correct: the Options+
  settle, the wait for Victor's own modifiers to come off (a held ⌘ would make this ⌘Escape), the
  `hidSystemState` source and `backButtonStamp` so this app's own tap lets the keystroke through.
  Nothing of Wispr's is read — the database rule is untouched. → journal: *The ✕ cancels the dictation (2026-09-12)*
- **The ring comes down on Wispr's own closing edge, not on the cancel.** Nothing guesses at the
  state, so a cancel Wispr ignores leaves the beacon truthfully lit. → journal: *The ✕ cancels the dictation (2026-09-12)*
- **The menu bar's *Cancel Dictation* row reads `isDictationCancellable`, not `isRecording`.**
  `isRecording` still gates *Start Dictation*, *New Session* and *Recover*, which are all about the
  relay's own microphone and must go on being. → journal: *The ✕ cancels the dictation (2026-09-12)*

## Tooling

- **Every demo, sweep or shoot that puts a window on his screen or captures it runs under
  `hands-off run "<what>" -- <command>`, for the WHOLE run** (2026-09-20, late — paid for: a
  15-style sweep ran on his screen while he was working, with the locks up only for the pointer
  parking, and the parked pointer read as *"why is it stealing my focus?!"*). The demo path sets
  `.accessory` and every panel is `.nonactivatingPanel`; nothing in it activates — the thing he
  feels is his pointer being moved. Batch captures into one locked run; never one per style
  with the locks dropping in between. A `.build/debug` demo does **not** displace the installed
  app: `WT_HALO_DEMO` / `WT_SHOOT_*` return before `AppDelegate` exists, so `SingleInstance.enforce`
  never runs in them (the installed app kept its pid through fifty demo runs that evening).

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
- **`POST /test/wispr {"hotkey": true}` fakes Wispr's *start gesture*, one step earlier than its
  microphone.** The real path is `HotkeyTap`'s event tap, which needs an Accessibility grant a
  `.build/debug` binary does not have — so without this the speculative ring is unreachable at a
  desk. The sequence that exercises the whole life of the ring: `{"hotkey": true}` →
  `{"on": true}` → `{"on": false}` → write something to the pasteboard. → journal: *The ring is up on Wispr's keystroke (2026-09-12)*
- **`POST /test/wispr {"on": true|false}` fakes Wispr Flow's microphone.** `WisprWatch` reads a
  CoreAudio boolean about *another app's* process, so before this the ⚡ ring, the chevrons and the
  ✕'s cancel could only be exercised by actually dictating into Wispr Flow — which is how a crash in
  the chevrons survived a day of testing. It enters at the watcher's own edge
  (`wisprDictationChanged(_:measured:)`), opens the relay's meter like the real thing, and is the
  regression check for *unbound* too: `POST /unbind` first, then this, then wait past `patience`.
  → journal: *The ring is up before anything is opened (2026-09-12)*
- **`POST /test/cancel` is the ✕'s cancel from a desk.** In a build with no Accessibility grant the
  Escape it posts is dropped by the window server, so the route is verified from the log line
  (`🗑️ Wispr Flow dictation cancelled via … — posting Escape`) rather than from Wispr reacting.
  → journal: *The ✕ cancels the dictation (2026-09-12)*
- **A debug binary run out of `.build` has no microphone grant and `AVAudioEngine.inputNode` hangs
  in it for ever.** That is not a product bug, but every main-thread wait behind it is: it is how
  both main-thread hazards above were found. If a test build stops logging after `◯ caret halo on`,
  `sample <pid>` before suspecting the feature. → journal: *The ring is up before anything is opened (2026-09-12)*

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

## Other halos: the `voice-halo` page and the MilkDrop engine, in web views (2026-09-20, evening)

- **`HaloStyle` picks what is drawn round the pointer; `.lightning` is the film, the default,
  native, and never waits on a web view.** The eight hand-written effects of the `voice-halo` page
  are run **by the page itself** in a transparent, click-through `WKWebView` (`HaloPage`) on a
  panel the size of the pointer's screen; the six MilkDrop presets by the real engine in its own
  page (`MilkDropHalo`, `assets/milkdrop/halo.html`), a square of side `max(w, h)` × the preset's
  scale that follows the pointer as a window. The panel, the pointer-following, the collapse (a
  fade of the panel's alpha for a web view), the arrow and the idle sweep are unchanged. The
  CoreGraphics ports of nine effects (`HaloEffects.swift`, tags `swift-port-01/02`) went:
  measured on this Mac, a full-screen CoreGraphics trail pass is 48–86 ms a frame and the page's
  ring with its shadow blur 58 ms, so the page's geometry at the screen's resolution was never
  going to run on the CPU, and the hand ports were small, coarse and — for the water — missing the
  scene. **The hand-drawn water (`Lagoon`) is gone for good** (Victor: *"drop those hand-drawn
  meteors — go back to the MilkDrop variant"*); `Water Dream` (MilkDrop 103) is the water.
- **The names are Victor's** (the page's `name` field): Pulse, Amethyst, Crown, Prism, Eclipse,
  Atom, Gemini, Beads; ⚡ • Tunnel, ⚡ Cauldron, ⚡ • Tendrils, ⚡ Snowflake, ⚡ ★ Sparks, ⚡ ★ Water
  Dream. **He does not always use them back**: the Wispr dress came back as *"efectul de mozaic"*
  and Snowflake as *"efectul de stars"* — a dictated ask names what he saw, so read it against the
  destination it is about (`picks` in `POST /test/halo`) rather than against this list.
  **A size ask is a factor on what is drawn today**, not on the page's `FORMULAS` number: *"mai mic
  cu treizeci la sută"* twice over is 0.75 → 0.525 → 0.3675, and the page's entry still says 0.75.
  Sparks then went ×3 the same evening (*"should be three times larger than it is right now"*) —
  0.3675 → 1.1025, a 1905 pt canvas, wider than the built-in screen: the two shrinks were
  asked of it while the destinations were still moving, the ×3 of it wearing the one it keeps.
  **And ×0.5 an hour later**, watching that one run (*"efectul de stars e prea mare. Micșorează-l
  cu cincizeci la sută"*): 1.1025 → 0.55125, a 953 pt canvas — inside the screen again, and
  still ~1.5× the 635 pt it wore before the ×3, which is the part that earned the ×3 in the first
  place. **Then ×1.3 twice** (*"fa stars mai mare cu 30%"*, the same sentence minutes apart) —
  0.55125 → 0.716625 → **0.9316125**, 1610 pt. Six factors on one preset in two days, the last
  three of them him homing in by eye on a thing that only exists while it is running; the chain
  lives in full in `HaloStyle.swift` beside the preset. Apply the next ask to the number the app
  draws at **now**, never to the page's 0.75 and never to an earlier link in the chain.
  **Those pt figures are what the square really occupies only since the fix below**: until
  2026-09-21 evening the web route drew `max(w, h) × scale²`, so every one of those asks landed
  **squared** — the ×3 was ×9 on screen, the ×0.5 was ×0.25 — which is most of why it took five
  of them to find the size. Sparks grew 1500 → 1610 pt when the second scale went, and `scale` is
  linear from here.
  **"Not centred on the tip of my mouse" was a size complaint**, measured that evening:
  `docs/projectm/captures/sparks-on-pointer-2026-09-21.png` — the demo on his own screen with the
  pointer in frame, differenced against a baseline capture — puts the cloud's centre of light
  within ~10 pt of the tip at 0.3675, over four frames. A ~160 pt knot in a 635 pt canvas leaves
  the pointer at its edge, and a knot that wanders frame to frame reads as off-centre. Reach for
  `scale` before `centerAt`/`offset`; a static shift on a composition that is already centred is
  what made Tunnel *"no longer centred"* the other way. `Eclipse` and `Water Dream` are his own words. A `−` on the page (Petals, Silk, Nova,
  Royal, **Mosaic** — *"the bricks look lame"*) is not implemented.
- **One menu, `Halo fx`** (his spelling; *"there must be ONE menu, not 2: and the MilkDrop ones
  should have a lightning bolt in the name"*): the film first and apart, the hand-written effects,
  a line, the presets with their ⚡ (`HaloStyle.menuTitle`). The menu bar runs Microphone, Engine,
  Mouse Gestures, `Halo fx`. `WT_HALO_STYLE=<case>` overrides for one run; a saved style that no
  longer exists reads as that destination's default.
- **One effect per destination, not one per app** (2026-09-21). `HaloDestination` — `caret`,
  `bound`, `spawn`, `wispr` — has a preference each (`UserDefaults` `haloStyle.<case>`; the single
  old `haloStyle` key is no longer read) and a default each. **Victor named all four in one breath
  on 2026-09-21** (*"când am Wispr Flow, dictare să apară mozaic. Când am dictare în terminal nou,
  să apară stars. Când am dictare legată, să apară Cauldron. Și când am dictare nelegată la
  carrot, îmi apare tunnel"*), and that reading is the current one: **Tunnel** at the caret,
  **Cauldron** bound, **Sparks** into a new claude (*"la dictarea in terminal nou, sa redai
  efectul stars, nu snowflake"* — the correction of that same day), **Mosaic** for Wispr's own. One effect lost
  a destination that morning and stays on the list a tick away — **Tendrils** (bound until
  Cauldron took it). **Snowflake** held the new claude for a few hours of that same morning, on a
  reading of *stars* as a title (Zylot's *Star Ornament* is the only star in the catalogue) rather
  than as a picture, and went back off the offered list when Sparks was given it back: a
  destination's dress is named by what it **looks like**, so look in `docs/projectm/captures/`
  before matching a dictated word to a menu row. `AppDelegate.syncBorrowedGestures`
  pushes the destination into `CaretHalo.setDestination` **only while the ring is up**, on every
  sync, from the same facts `atCaret` is read from, `foreignMic` tested first.
- **A foreign Wispr dictation is its own destination** (2026-09-21, later the same day). It wore
  the caret's dress first, on the reading that Wispr types at the caret so the two are one thing;
  Victor split them: *"Wispr-ul este o dictare … la fel de dictare. Folosește un efect MilkDrop
  rămas pentru el"*. Cauldron is the *rămas* — the only offered preset none of the other three had
  claimed (Snowflake was off the menu that morning and is back on it since the afternoon; Water
  Dream is built but off). It stays deliberately out of
  `atCaret` either way, because that flag arms `DropArrow` and the heads must not promise a
  delivery this app is not making.
- **Every open Wispr microphone gets a halo, however it was opened** (Victor, 2026-09-21: *"ori
  de câte ori Wispr Flow interceptează vocea, trebuie să fie o animație pe ecran … că pornesc cu
  apăsat taste, că pornesc din gesturi de mouse"*). Three witnesses, all unconditional now:
  `HotkeyTap`'s two chords — `54+61` (right ⌘ + right ⌥ held, `ptt`, tested on the **device-right**
  flag bits) and `49+59+63` (fn ⌃ Space, `popo`); `onWisprRawChord` for the chords this app posts
  itself (🔽 →, the back-button stop), which the tap filters out by design; and
  `WisprFlowSource.watch`, the CoreAudio edge.
- **The watch is started by `watchMicrophone()`, not by `prepare()`** — that was the bug. `prepare()`
  is called on the **selected** source only, so with `dictationSource` on `eleven` or `whisper` the
  CoreAudio witness never ran, and a dictation started any way other than the two chords (the F18
  Scratchpad hold, a rebound shortcut, Wispr's own window) had no witness at all: no `gestureSeen`,
  no `hearingChanged`, `ringUp` false, nothing on screen. `AppDelegate` now calls `watchMicrophone()`
  beside `wisprMic.start()`, always; `WisprWatch.start()` is idempotent so `prepare()` may still call
  it. **Only the watch** — the Scratchpad sweep and the front-restore stay in `prepare()`, because
  the relay wraps nothing it did not start. Cost of the CoreAudio route: it is 0–6 s late, so a
  chord-started dictation is still the one that lights instantly.
- **`use` draws, `setStyle` writes.** `CaretHalo.use(_:)` changes the dress without touching a
  preference; `setStyle(_:for:)` writes one destination's, `setStyleEverywhere` all three. **F7/F9
  (`cycleStyle`) only draw** — they are how he browses the list outside a dictation, and browsing
  must not rewrite a pick (*"F7, F9 rămân doar de preview așa"*). **The wheel dial (`dialStyle`)
  writes**, to the destination being worn: it turns only while the ring is up, so the turn is a
  decision about that kind of dictation, and the flash names it (`✨ Tendrils · Bound terminal`).
- **`POST /test/halo` previews by default**: `{"style": …}` draws without saving, `"for":
  "<destination>"` makes it a write (or, alone, wears that destination's dress). The answer carries
  `destination` and `picks`.
  → journal: *The ring says where the sentence is going (2026-09-21)*
- **Vendored, pinned, never fetched.** `tools/vendor-voice-halo.sh` copies `index.html` +
  `water.js` from `~/workspace/voice-halo` at the commit/tag it pins into `assets/voice-halo/`
  (+ `VERSION`); `build-app.sh` runs it (a no-op without the sibling) and copies the folder into
  `Resources/voice-halo` beside `Resources/milkdrop` (the engine's page, the engine and the preset
  packs; `butterchurn.min.js` is still dropped in by hand — without it the preset rows are greyed
  `— engine not bundled`). A change on the page reaches the app by bumping the pin and rebuilding;
  `WT_HALO_PAGE_DIR` points a run at the working checkout, `WT_MILKDROP_DIR` at another engine folder.
- **`?embed=1` is the page's own mode for this host** (in `victorrentea/voice-halo`, not injected):
  transparent `html`/`body`, no chips, buttons, bars, version line or drawn cursor; the drawing
  origin on the real pointer through the page's walk offset (`halo.center(x, y)` on every move);
  `halo.pick(i)` by `FORMULAS` index (`HaloStyle.pageIndex` — the page never reorders that list,
  and the name it answers with is logged); `halo.probe()` says what the page sees
  (`WT_HALO_PAGE_PROBE=1` logs it 5 s in). **Audio is pushed, and the analyser is emulated**:
  `halo.audio(<base64 Float32>)`, the last 1024 samples at 16 kHz, 30 Hz; the page upsamples the
  last 683 to a 2048-point 48 kHz window, Blackman + FFT, `2|X|/N`, time smoothing 0.72² per call,
  −100…−30 dB to bytes. No `getUserMedia`, no running `AudioContext`, no output device.
  `halo.start()` clears the trail and starts the frame loop; `halo.stop()` halts it.
- **Why the presets are not in that page** (measured, not found): the same engine, fed the same
  bytes with the same preset, renders **dark** inside the page in a `WKWebView` — engine buffer
  mean 2/255 against 67 in `halo.html`, with every JS-side variable identical (levels, `cx/cy`,
  viewport, texture size, shader link status, no console errors, context not lost), and the
  canvas shows the composition when put on screen directly. The old page through the new host is
  bright; the cause was not found in the time there was. `halo.html` stays, with what Victor asked
  of Tunnel that evening: `halo.preset(name, fade, {fadeRadius, fadeFloor, gain, rot})` — Tunnel at
  the full canvas, fading to **nothing** at half the screen's width from the pointer, at **2×
  intensity** (`gain`, before the key) and **2× rotation** (our copy of the preset: `a.rot*=2`
  appended to its compiled frame equations, the vendored pack untouched).
- **Composited over the live screen, always.** Nothing captures the desktop: a web view is a
  window layer over whatever is there, verified by two captures 1.5 s apart over an animated
  window under every style (all changed) and a near-black census over a bright window (none above
  the baseline the window's own text sets). Additive effects are faint over pure white, as on the
  page over its own light — that is the design, not a bug. The engine's black is keyed to alpha
  (`a = max(r, g, b)`), so a dark preset region is translucent, never a black box.
- **Failure has a floor, and it is the film.** Page or engine missing → film, said in the log. A
  page that fails to load, a WebContent process that dies, a preset that will not pin, or no
  `ready` 2 s after the ring is asked for → `onFailure` → `CaretHalo.fallBack`: the panel is
  rebuilt as the film **in the same call**, mid-dictation if need be, and `pageBroken` stops the
  retry until the style changes. `drawn` is what the panel shows; `style` stays the preference.
  Proven the hard way: a JavaScript error in the page put the film up two seconds later, as designed.
- **What it costs, measured** (`top`, 1 s samples, ring up, demo voice, 3456×2234): the film
  0.3 % CPU / 46 MB; a hand-written page effect 4–6 % in the app + 4–7 % WebContent + **20–95 %
  of a core in the WebKit GPU process** (canvas 2D is drawn there), 50–110 MB + ~40–55 MB; a
  MilkDrop preset 4 % + ~30 % + ~67 %, **~280–330 MB WebContent + ~240–290 MB GPU process**.
  Route B (projectM 4.1.7, native, spiked 2026-09-20) renders the presets in 2–3 ms a frame at
  ~40 MB but needs a from-source build, a 2-line fork (it hard-binds FBO 0), three of the seven
  presets that exist only as butterchurn JSON, and a texture pack; route C (an engine in
  Swift/Metal) is 5–8 k lines and 10–15 days for a first render that would still not match
  butterchurn. The web views are the route until the cost is felt.
- **The host multiplies `scale` into the view; the page must NOT do it again** (2026-09-21,
  *"oare la stelute poti mari rezolutia? apar un pic blurate punctele. animatia din pagina web e
  mai 'precisa', 'neblurata'"*). `halo.html` used to lay its canvas out at the host view's full
  side and then `transform: scale(var(--k))` it by the preset's `scale` — on a view whose side
  `CaretHalo.panelFrame` had **already** multiplied by that same `scale`. Two faults in one line:
  - **the blur.** It asked the compositor to resample a 3220 px canvas into 3000 device px every
    frame. Measured with a 1-device-pixel grid pushed through the real panel and read off a
    `screencapture`: before, a hairline arrives as `39 40 104 176 · 39 39 167 112 · 39 39 230 49`
    — split across two pixels with a phase that drifts along the line; after, `255 38 38 38 · 255
    38 38 38`. Modulation depth **121 → 150 of 255** on the same alpha. Nothing was gained for it:
    the extra 220 px were thrown away in the resample.
  - **the square.** The halo was `max(w, h) × scale²` while `ProjectMHalo`, on the same number,
    drew `max(w, h) × scale` — the two engines disagreed about the size of the same preset, and
    a size ask on the web route landed squared.
  Both are one deleted CSS transform. The canvas is the view, at the backing scale, 1:1 with the
  screen; `k` is still in the `halo.size` signature and is ignored. The page reports the geometry
  it settled on — `MilkDrop 87: ok · 1610pt canvas, 3220px` — because *what size is it actually
  drawing at* was a question only a patched page could answer until that evening.
  **The ruler is how to ask it again**: a copy of `assets/milkdrop/` whose `preset()` draws a
  4-px white grid into `src` and returns, `WT_MILKDROP_DIR` at it, one `screencapture`, and read
  a column. A 1:1 path gives `255 38 38 38`; anything else is resampling something.
- **Resolution is a feature-size dial for a MilkDrop preset, not a quality dial** (2026-09-21,
  the same evening, after the fix above did not settle it — *"parcă tot puncte cețoase văd"*).
  A preset's features are **not** a constant fraction of its canvas: measured on the same 10 % of
  the canvas at the same second of the same clip, a chain-breaker spark is **~5 canvas px at 1610,
  ~20 at 3220, ~56 at 6440** — it grows faster than the canvas does, so more pixels means bigger,
  softer, more crowded sparks that merge into a wash, and fewer pixels means small separate stars.
  On his screen at 1:1 the 3220 canvas is a milky veil with the text under it unreadable and the
  1610 one is stars over a readable desktop (`docs/projectm/captures/sparks-resolution-2026-09-21/`).
  So **a big halo with small sparks is only possible by rendering the canvas coarser than the
  screen** — `HaloStyle.Preset.renderScale`, canvas pixels per point, nil = the backing scale,
  **1 for Sparks alone**; `WT_MD_SCALE` overrides, `ProjectMHalo`'s `WT_PM_SCALE` twin. Keep the
  ratio an **exact integer** (1 pt = 2 device px), because a fractional one is the blur of the
  bullet above. Reach for it only for a preset Victor calls foggy — everything else wants 1:1.
- **Review**: `WT_HALO_STYLE=<case> WT_HALO_DEMO=11 WT_HALO_DEMO_AUDIO=1` puts one effect on the
  real pointer, capturable; `WT_HALO_CYCLE=1.5` dials through all of them on the live ring. The
  log says `halo page ready: 20 effects, webgl true` and which page entry a style picked, or
  `MilkDrop <n>: ok`.

## Where the halo work stopped (2026-09-20, 23:00) — for the next session

- **Deployed = `50a9b52`**, the newest commit at close; nothing committed but undeployed. Page
  vendored at `dc91aa7`. Deploy is `./build-app.sh && ./relay-restart.sh`, only with no ring up
  (`GET /test/state`), under `hands-off run`.
- **Decided, not omitted**: a style change rebuilds the web view, **~115 ms** to the first
  frame of a hand-written effect (measured `+117 ms page ready`). Victor does not feel it and
  chose the simpler rebuild-per-change over keeping a page alive — do not "fix" it.
- **Not done, known**: (2) a preset's lag after F9 is the **1.5 s warm-up**
  (`MilkDropHalo.warmup`) + ~0.3 s load — the previous panel stays up meanwhile, so nothing
  blinks, but the preset itself cannot come sooner without a shorter warm-up (0.5 s = a flash
  of bare waveform); (3) Atom's dots scale with its `scale` since the last commit (`dotK`, reference 0.0696),
  so the outline tracks the size both ways; (4) **presets render dark inside the whole
  voice-halo page in a WKWebView** (engine buffer 2/255 vs 67 in `halo.html`, every JS variable
  identical) — unexplained; the presets live in `halo.html` because of it, and the page's
  `Comets`/Water Dream hybrid is Mac-only for the same reason.
- **`Comets` is out** (Victor, 23:05), marked `−` on the page like the other dropped ones;
  `comets.js` and the Water Dream hybrid stay committed — built twice already (Lagoon, then
  the hybrid's top layer), he may want it again. No `HaloStyle` case; nothing offers it.
- **Reading a preset's equations**: on the loaded page, `mdPresets[name].frame_eqs_str` is the
  compiled JS as text — easier than the minified packs. Tunnel and Cauldron drift `cx/cy` (±0.11
  of sines); `pinCenter` appends `a.cx=a.cy=0.5`. Sparks and Snowflake do not drift.

## The idle sweep (2026-09-15)

- **Nothing of the halo's may stand at the pointer with no dictation in flight, and once it did.**
  Victor: *"the mouse was having a caret, although there was no dictation currently open"* — after a
  sentence that began at the caret, was redirected to the bound terminal a second later and took a
  highlight, a shot, an area crop and a picked element on the way. The log said `◯ caret halo off`,
  every flag in `/test/state` read clean, four desk replays of that shape left the window list empty,
  and an `orderOut` landing mid-fade in a standalone panel was clean too. **Not reproduced.**
- **So `CaretHalo.startIdleSweep` runs from launch**: every 0.5 s, while `live`, `closing` and
  `delivering` are all false, both panels are asked `isVisible`; two consecutive yeses take the window
  down (`orderOut`, `arrow.hide`, monitors released) and log `◯ a halo window stood at the pointer
  with no dictation in flight — …` with the panel named and every flag it claimed. That line is the
  evidence the next look at this starts from; `GET /test/state.halo` is the same reading from a desk.
- **`isVisible` is the gate, not the window server's list.** AppKit answers false the instant
  `orderOut` is called; `CGWindowListCopyWindowInfo` still lists the window for a frame or two
  afterwards (measured), which is why the sweep wants two ticks and the harness's window list is the
  slower witness.

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
