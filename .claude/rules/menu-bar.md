---
paths:
  - "Sources/WalkieTalkie/StatusItem.swift"
  - "Sources/WalkieTalkie/MenuBarMirror.swift"
  - "Sources/WalkieTalkie/MessageLog.swift"
  - "Sources/WalkieTalkie/AboutPage.swift"
---

# The menu bar item

Rules for the 🤖 in the menu bar and its menu (`StatusItem`), the mirrors on the other screens
(`MenuBarMirror`), the Prompt Log page (`MessageLog`) and the About panel (`AboutWindow`).
Full history and reasoning: docs/journal.md — see the sections named after each rule below.

## The header and the menu's job

- **Every string in `StatusItem` is English.** The menu is where every gesture is written down —
  `Connect Terminal` / `Disconnect` / `Start dictation to new claude` and their chords, the three
  dictation rows, `Engine: …`, the legends, `Autosend`, `About`, `Quit`, the model name.
  → journal: *UI language: English only*
- **The header `Bound to: folder@branch` is written from `AppDelegate.showBound` only** — the
  single place the chip's line and the menu's header are set, so they cannot disagree. Only the
  bound form carries the prefix; unbound the header is the drawn map pin (`Glyphs.mapPin`) plus
  **`Unbound`** (2026-09-14) — it was `🤖 <launch label>`, and a login item's launch label is `/`,
  so the row named the directory `launchd` started the app in as though it were a destination. The chip
  shows the same line without `Bound to:` — beside the cursor a folder name has nothing else to
  name; above a stack of commands a bare name reads as a section title.
  → journal: *The menu bar item*
- **The label is read in `menuWillOpen`, not pushed on a timer.** With two overlays up, two
  identical 🤖 say nothing about which session a click is about to end; the only moment the answer
  has to be right is the moment he is looking at it.
  → journal: *The menu bar item*
- **The menu is the only legend, so it has to be complete: every action is an always-visible row
  naming the mouse or key that performs it, greyed when it cannot act *this second* — never
  hidden** (*"indiferent de starea în care sunt acum"*). `Take Screenshot`, `Select Screen Area` and
  `Pick Element in Chrome` are permanently disabled legend rows: *this is something you do, not
  something you pick*, under a separator of their own below the rows that end a dictation.
  → journal: *The chip teaches nothing; the menu does*
- **`Start dictation to new claude` is `startLocalRecording(spawn: true)`; `Take Screenshot` is
  `plusOneShot` after a 0.35 s beat** — AppKit dismisses the menu and the screen redraws a frame or
  two later, so a capture fired on the click photographs the menu that ordered it.
  → journal: *The chip teaches nothing; the menu does*
- **The separator groups by what a row is *for*.** Above it, everything about a destination
  (point at one, let it go, paste the last sentence); below it, everything done with a dictation
  open plus the two rows that open one — `Start Dictation` and, directly under it, `Start dictation
  to new claude`, the same verb with the two destinations there are.
  → journal: *Every row has an icon, and two alphabets share the column*

## Every row has an icon

| row | icon | shortcut column |
|---|---|---|
| `Connect Terminal` | `mappin`, in Google Maps red | `⬅️ + 🛞` |
| `Disconnect` | `mappin.slash` | `➡️ + 🛞` |
| `Paste last prompt` | 📋 | `⌘⇧P` — **enabled off the log, not off this run's memory** (2026-09-22) |
| — separator — | | |
| `Start Dictation` | `mic` | `🛞` |
| `Dictate to New Claude` (`Start dictation to new claude` until 2026-09-22) | ✨ | `🛞🛞` |
| `End Dictation` | `mic.slash` | `🛞` |
| `Cancel Dictation` | 🗑️ | `🛞 2s` |
| `Recover Dictation` (`Recover Cancelled Dictation` until 2026-09-22) | `arrow.up.trash` — out of the bin | |
| `Take Screenshot` | 📷 | `⬇️` |
| `Select Screen Area` | ✂️ | `🛞 drag` |
| `Pick Element in Chrome` | ✋ | `⌘⇧ + ⬅️` |
| `Engine: <what is listening>` | `waveform` | `>` — a two-row submenu |
| `Mic: <glyph> <device>` (`Microphone` until 2026-09-22, shortened for width) | `mic` | `>` — automatic + the six devices; the same six rows Victor Addons shows, and the same shared preference file |
| `Mouse Gestures: Logi` / `: Wheel` | `computermouse` | `>` — a two-row submenu |
| `Halo fx[: <effect>]` | `sparkles` | `>` — the lightning ring, a line, the ported effects, the presets (greyed `— engine not bundled` until `butterchurn.min.js` is in `assets/milkdrop/`), then a row per destination with the same list, then `Engine: projectM｜Web` and `Pre-process: <chain>` (`Fx engine` / `Fx voice` until 2026-09-22 — *"doar «projectM», că deja știu cine e"*, and the parentheses shortened so the open list fits at the right edge of the screen) |
| `Autosend` | the same pair — a `checkmark` when on, **nothing** when off | |
| `Prompt Log` | 📜 | |
| `Victor's Walkie Talkie (<build>)` | ℹ️ | | |
| `Quit` | `power` | | |

- **`Paste last prompt` asks the same question `⌘⇧P` does** — `AppDelegate.pastableDictation`:
  this run's `lastDictation`, else the newest line in the outbox. Victor, 2026-09-22: *"în prompt
  history apar elemente, dar «paste last prompt» e dezabilitat. Nu prea are sens asta, nu?"* — and
  it did not: `lastDictation` is born nil, so every relaunch greyed the row out above a
  *Prompt history* submenu listing twelve sentences the key would have pasted. The two rows were
  reading different stores and only one of them survives a restart. **Read lazily, at most once a
  run** — `MessageLog.recent()` parses the whole outbox (two megabytes, and it grows forever) and
  this is asked at every menu open, so it is only ever consulted while `lastDictation` is still
  nil. A caret sentence writes no outbox line and so cannot be seen here, which is honest: what is
  restored is the last sentence that was *sent somewhere*, the same set the submenu lists.
- **The shortcut column above is the wheel vocabulary — live only with *Mouse Gestures: Wheel*.** Each `gestureRows` entry carries two legends, `(item, label, logi, wheel)`, and
  `restyleGestures` picks one; the Logi set (default since 2026-09-09) is `◀️ + 🔼` bind, `🔽 ↓`
  disconnect, `🔼 →` start/end, `🔼 ↑` new claude, `🔼 ←` cancel, `🔽`
  screenshot, `🛞 drag` area, `⌘⇧◀️` pick. Vocabulary: an emoji for the button (`◀️`/`▶️` left
  and right, `🔼`/`🔽` the stacked forward and back side buttons, `🛞` the wheel), a thin text arrow
  for the movement, `+` only to join a held button to the wheel — no `+` in `⌘⇧◀️`, since hold-and-
  click is one gesture (2026-09-09). `restyleGestures` runs on the toggle as well as on every open,
  and the tab stop is measured against the wider of the two sets so the column cannot resize under
  the pointer.
  → journal: *Use Logi Gestures — the tick that chooses between the two sets*
- **Rebind to… sits with the destination rows** (2026-09-10) — its rules are below.
  → journal: *Rebind to: the destinations already spoken to, most recent first (2026-09-10)*
- **The whole chord is one glyph, in AppKit's own shortcut column** (2026-09-22, after three asks
  and two rejected arrangements). The item's **`keyEquivalent`** carries it, so it is drawn flush
  with the `>` of the submenu rows and with `⌘Q` — which is what Victor asked for three times
  (*"chiar nu avem nici o opțiune să trecem shortcuturile să fie pe aceeași coloană cu >"*).
  **The style of the arrow is the button and its direction is the movement**: dotted `⇢ ⇠ ⇡` is the
  front side button, doubled `⇑ ⇓` the back one. Where the gesture has no direction the glyph is a
  mark instead — `●` a press, `⤢` the wheel drag, `⟳` a 2 s hold, `◐`/`◑` a button held while
  another is pressed, `◎` the wheel, `⦿` twice.
- **Why it cannot be two glyphs, measured.** AppKit reserves the disclosure-arrow gutter **after**
  every row's content — **31 pt**, or **47** once any row carries a key equivalent — so anything
  written into a title pushes the gutter right along with it and the gap never closes. A right tab
  stop, a negative kern to under-report the measured width, and a trailing pad were all built and
  all three moved the column and the arrow together. `keyEquivalent` is the only thing drawn
  *inside* that gutter, and it holds **one glyph** plus `⌃⌥⇧⌘`: `"▲→"` draws `▲`, `"ABC"` draws
  `⇧A`.
- **Do not split the gesture across the title and the column.** Both halves were tried in one
  night — the button as `▲`/`▼` at the end of the title with the movement in the column, then the
  two swapped (*"nu in titlu, ci in key shortcut tre sa fie arrowheadul"*) — and both were rejected
  on sight: a gesture in two columns is read as two marks. *"revino la 2 tipuri de sageti: punctata
  pt forward si inca una pt back."* The first attempt at the convention was rejected too
  (*"punctat = but din fata e neintuitiv"*) and came back anyway, because the alternative costs a
  reading of **every** row; the convention costs one reading of the About window, which draws it on
  a picture of his own mouse.
- **Plain `→ ← ↑ ↓` are normalised by AppKit into `▶ ◀ ▲ ▼`**, the arrow-*key* glyphs — the second
  reason the two families are the dotted and the doubled ones: those it draws as given.
- **None of these fire as key equivalents**: this app is never the key app, so the menu matches
  them only while it is open, and `⇢` is not a key any keyboard produces. ⌘⌃B and ⌘⌃D are not
  written on rows at all; ⌘⇧P and ⌘⇧◀ are drawn by AppKit from the mask and belong to `HotkeyTap`.
- **The emoji legend moved to the About window** (`AboutWindow`, `Glyphs.mouse`): a menu row holds
  one glyph, a drawing of his own mouse holds the vocabulary.
  → journal: *Every row has an icon, and two alphabets share the column*
- **`attributedTitle` rewrites `title` — store labels in `gestureRows`, never read them back off
  the item.** `restyleGestures` once built its string from `row.item.title`, so the second pass
  concatenated the chord onto a title already carrying one: every gesture row printed its chord
  twice, on two lines, right on first open and wrong every open after.
  → journal: *Every row has an icon, and two alphabets share the column*
- **An attributed title stopped AppKit dimming a disabled row**, and no gesture row has one any
  more: with the chord in the shortcut column the titles are plain again, AppKit dims the row
  *and* its glyph, and `restyleGestures`'s re-inking from `menuWillOpen` went with it. `Chord.head`
  is still wired through `applyGestureColumn` for the day something has to ride beside the glyph —
  and the ink rule is kept there, because that is the moment it would be needed again.
  → journal: *Every row has an icon, and two alphabets share the column*
- **Every icon in the column is a template SF Symbol** (Victor, 2026-09-21: *"să fie toate
  monocrome"*). The column used to have two alphabets — SF Symbols wherever a row had an *off*
  half (Unicode has no crossed-out map pin or microphone, and a pair drawn by two alphabets reads
  as two unrelated rows), emoji everywhere else — and by the end only two emoji were left, 🆕 and
  ✨, which read as two rows that are *special* rather than two rows that are *different*. They
  are `mic.badge.plus` (pairing with `mic` / `mic.slash` above and below) and `sparkles` (✨'s own
  symbol). `StatusItem.emojiIcon` is gone; `symbolIcon(_:tint:)` keeps its `tint`, unused, and a
  tint costs the image its template flag and with it the highlight and dark mode.
  → journal: *Every row has an icon, and two alphabets share the column*
- **`mappin`, not 📍.** 📍 is `ROUND PUSHPIN`, a thumbtack at an angle; `mappin` is the teardrop
  marker everybody means. Victor raised it by name.
  → journal: *Every row has an icon, and two alphabets share the column*
- **The word `hold` is gone from every chord.** Where a hold has a duration the duration says so
  (`🛞 2s`); elsewhere the chord is unambiguous without it. Legend chords carry no `while
  dictating` qualifier and no `@🎙️` marker (removed 2026-09-04) — the section says the condition.
  → journal: *Every row has an icon, and two alphabets share the column*
- **The back button is drawn, not spelled** (`⬇️` in the journal's table, `🔽` in the Logi
  legends). The arrows in this menu are already mouse buttons.
  → journal: *Every row has an icon, and two alphabets share the column*

## The Engine row: which recogniser is listening (2026-09-14)

- **It replaced `Replace WisprFlow`, and that row is gone from the menu.** A checkbox named after
  another app reads as *that app: yes or no* (*"nu mai trebuie să fie un checkbox «Wispr» sau nu,
  ci un submeniu din care să aleg modelul de utilizat"*). A tick can only name one of the two
  engines; the unnamed one is exactly what he is asked about in a room — *"așa se vede și numele
  modelului, dacă mă întreabă cineva ce folosesc"*. The caret-paste mode itself is untouched and
  still lives on the forward side button; what it has lost is its row, its tick and its legend.
  → journal: *The engine is a choice with two names on it (2026-09-14)*
- **Wispr Flow is the third row again since the evening of 2026-09-22**, behind the firewall
  (`HotkeyTap` drops its ⌘V, the relay reads its `History` row) — the exact condition the
  paragraph below asked for. Its title says so: *its own app, the relay reads its History row*.
- **Wispr Flow left the list on the morning of 2026-09-22, and the list was two rows** — `Local` and
  `ElevenLabs`. Victor: *"scoate wisprflow ca sursă de dictare din lista de Engine — n-am reușit
  niciodată să-l integrăm ca lumea în fluxul nostru să-i preluăm ce text injectează."* It is a
  capability and not a ranking: the other two hand the app a transcript, Wispr pastes into
  whatever has focus and the wrap never made that dependable. **`WisprFlowSource` is not deleted**
  — 🔽 → still posts its chord raw, `hearingChanged` still feeds the ⚡ ring, and the wrap is left
  standing for the day the injection can be blocked outright. What went is the row, the
  `engine(named:)` case and the `(W)` mark.
  → journal: *Wispr Flow leaves the Engine list (2026-09-22)*
- **The row is a readout of `AppDelegate.source` first and a control second.** Its title is
  `Engine: ElevenLabs` or `Engine: Local (2.6 GB)`, so the answer is readable without opening
  anything. No `…` on it — the arrow already says there is more.
- **It is an ordinary submenu with the arrow** — *"tre submeniu obișnuit cu >, nu un modal"*
  (Victor, 2026-09-14, after seeing the alternative). It was a dispatched `popUp` for one build, on
  `Rebind to…`'s gutter argument carried over rather than re-tested; a detached list of two reads
  as a modal instead of as a branch of the menu. `Rebind to…` keeps its pop-up — its list is long,
  live and searched. **The submenu's rows are rebuilt in `applyEngineRow`**, which `menuWillOpen`
  already calls, not by a delegate of the submenu's own.
- **The tick in the list is drawn from what is running, never from the click.** `StatusItem` holds
  `engineId` only as a mirror; `AppDelegate.setEngine` is what decides and calls `setEngine` back —
  including when it **refuses**, which it does with a sentence in flight (`listening`, `settling`,
  `speculative`, `source.isRecording`). A source swapped between `didStopListening` and
  `didTranscribe` leaves the old one holding a transcript with nobody wired to receive it.
- **Picking the local model brings the weights up on the spot.** `LocalWhisperSource.prepare()` is
  deliberately a no-op, but a deliberate pick *is* the gesture that asks for it — a first dictation
  answered with `the local model is still loading` reads as the switch having failed.
- **`GET /engine` answers `engine` (`whisper` / `eleven`) beside `source`**, so a test asserts the
  pick without matching a display name. A stored `dictationSource=wispr` from before 2026-09-22
  falls through `engine(named:)`'s default and comes back as `eleven` — the migration is the
  fallback, deliberately, because an engine that can run but cannot be picked is the one state
  where the chip and the menu disagree.

## The Microphone row (2026-09-19)

Victor: *"Listening(E)... turns to Listening(🎙️⇒E)... (XLR) or Listening(💻⇒E)... (Mac's
microphone) or Listening(🎤⇒E)... (for the RX portable bt mic) or Listening(🎧⇒E)... (for BOSE mic),
and source should be selectable via menu too. those unavailable disabled"* — and, the same evening,
*"instead of `⇒`, use `/`"*, so the mark ships as `Listening(🎙️/E)...`.

- **Directly under `Engine`, because it is the same question one level down.** That row answers
  *what is listening to me*, this one *through what*; together they are the two halves of the mark
  the chip wears, and a man who read one off the chip should not hunt for the other.
  → journal: *The chip says which microphone, and the menu picks it (2026-09-19)*
- **The list is the four he named, never the whole of CoreAudio.** This Mac answers with fifteen
  inputs, eleven of them virtual (Loopback ×3, Wave Link ×2, Zoom, Teams, Webex, Iriun…). A menu
  offering all of them would be a device chooser, which System Settings already is; what it would
  not be is readable at a glance while he is teaching. → journal: same
- **`Automatic` is first, ticked by default, and never disabled** — and it says what it does:
  `Automatic — 🎙️ ▸ 🎤 ▸ 🎧 ▸ 💻`, the first of the four that is plugged in. **The rows below are
  in that same order**, because `InputDevice.known` is the one list that is both the menu and the
  ladder; a menu ordered differently from the automatic pick would teach the wrong preference every
  time he opened it. → journal: same
- **An absent device is disabled *and says why*** — `🎤 DJI Wireless Mic Rx — not connected`. A
  grey row with no explanation is indistinguishable from a broken one, and the explanation is the
  only thing he can act on: it is a cable. → journal: same
- **Two names per device, `Engine`'s rule applied here** — the top row gets `short`
  (`Microphone: 🎙️ XLR`), the list under the arrow gets `label` (`🎙️ Elgato Wave XLR`). The row
  above it learnt this by stretching the whole menu to the width of a model id.
- **`micSubmenu.autoenablesItems = false`, and it is load-bearing.** AppKit re-enables any item
  with a valid target and action unless the *menu* says otherwise, and that flag is per `NSMenu` —
  the one set on the top-level menu buys this list nothing. Without it the `— not connected` rows
  are fully clickable and the greying is decoration. It is the same trap that made `Disconnect`
  clickable with nothing bound.
- **The top row says what would record; the tick says what he asked for.** They differ exactly when
  a picked device has been unplugged (`InputDevice.resolve` falls back to automatic), and that
  difference is the sentence he needs — *you asked for the receiver, you are on the built-in*.
  → journal: same
- **Rebuilt in `applyMicRow` from `menuWillOpen`**, like `applyEngineRow`, and for a sharper reason:
  a receiver is plugged in *while* the menu is up at least as often as before it, so the list is
  asked of CoreAudio at every open and never cached.
- **A pick is never refused mid-sentence, unlike `Engine`.** Switching engines rewires five
  callbacks under a dictation in flight; `InputDevice.select` is read once, at `MicRecorder.start`,
  so a pick takes effect on the next sentence and cannot disturb this one — which is also the
  honest behaviour, because the words already spoken did come through the old device. The chip is
  re-marked at once even so, and the flash says `— from the next sentence` while he is talking.
- **`GET /engine` answers a `mic` block and `POST /test/mic {"id": …}` makes the pick**, so the
  fallback and the chip's mark are assertable without photographing a menu.

## Autosend, and the Mouse Gestures row

- **Switch state lives in the icon column — a `checkmark` when on, a blank image of the column's
  exact width when off — never `NSMenuItem.state`.** A ticked row makes AppKit reserve the state
  column for the **whole** menu, shoving every other row sideways the moment one is switched on.
  Blank, not ⏸️ or ⏩: a picture in the column claims the row is *doing* something, and these two
  is the menu's only switch left, so the one fact to carry is on or off (*"autosend să aibă bifă în
  față, nu ⏩ când e activ"*, 2026-09-07). The same `checkmark`-or-blank pair draws the tick inside
  the `Engine` and `Mouse Gestures` submenus, where the chosen row wears it.
  → journal: *Autosend*
- **Autosend persists across launches** (since 2026-09-07; so does the caret-paste mode, whose
  preference moved to `AppDelegate.replaceWisprKey` when its row went). Ticked,
  the pre-send panel still opens for `AppDelegate.autosendHold` = 1 s — the receipt, without
  which a delivery cannot be told from a drop — **with no Send and no Cancel and no buttons' row**:
  two buttons up for one second are two buttons nobody can reach. State lives on the item and is
  pushed through `onToggleAutosend`, so tick and behaviour cannot disagree.
  → journal: *Autosend*
- **The two mouse wirings are a submenu, not a tick** (2026-09-14, Victor: *"cu submeniu din care
  aleg cele 2 variante (ca la Engine)"*). The row reads `Mouse Gestures: Logi` or `: Wheel` and
  opens `Logi — side buttons from Options+` / `Wheel — the wheel carries the dictation`; it was the
  checkbox `Use Logi Gestures`, which could say that Logi was off but had no word for what was on
  instead. `applyLogiGesturesRow` rebuilds both rows, `gesturesPicked` ignores a click on the row
  already ticked, and `setLogiGestures` is still the one writer of the preference and of
  `restyleGestures`.
  → journal: *Use Logi Gestures — the tick that chooses between the two sets*
- **It defaults to Logi, and the default has to be written out:**
  `object(forKey:) as? Bool ?? true`. `UserDefaults.bool(forKey:)` answers `false` for a key never
  written, which would have shipped the wheel gestures to the Mac already configured for the new
  ones.
  → journal: *Use Logi Gestures — the tick that chooses between the two sets*

## The Halo row (2026-09-20, three destinations since 2026-09-21)

- **`Halo fx`, the shape `Engine` and `Mouse Gestures` have** — a readout with the
  list under the arrow, the tick drawn as an icon on the chosen row. The first row is today's
  film and the default; under a separator, the nine effects ported from the `voice-halo` page at
  tag `swift-port-01`, in the order Victor ranked them. `applyHaloRow` runs on every open and reads
  the preferences, so the tick is whatever is running — including a choice made with the wheel
  dial mid-dictation (`.claude/rules/mouse-gestures.md`).
- **There are three picks, one per destination** (`HaloDestination`: caret, bound, spawn), so the
  submenu has two shapes at once: the **full list at the top sets all three** and is ticked only
  while all three agree — with three different picks **nothing is ticked and the row drops its
  readout** (`Halo fx`, no colon), because naming one of three is the one claim that is false —
  and **a row per destination under it** (`At the caret: Tunnel`, `Bound terminal: Tendrils`,
  `New claude: Sparks`), each carrying the same list under its own arrow. `Fx engine` stays last.
  Victor: *"să nu apară niciunul selectat … dacă îl selectez precis, atunci toate trei sunt puse pe
  același … mi-ar plăcea să pot alege separat cele trei efecte"*.
- **`onPickHalo` carries the destination** (`nil` = the top-level list = all three) →
  `CaretHalo.setStyle(_:for:)` / `setStyleEverywhere`, which write the preference and rebuild the
  ring on the spot if what changed is the dress being worn.
  → journal: *The ring says where the sentence is going (2026-09-21)*

## Rebind to…, Recover, Quit and readouts

- **`Rebind to…` puts up `RebindPanel`, a window with a search field** (2026-09-12) — the rows and the search over the session journals are in `.claude/rules/terminal-binding.md`. What stayed from the pop-up: dispatched out of the click, built when asked for, the app's own icon per row, a row that cannot be acted on greyed rather than hidden.
  → journal: *The list takes typing, and searches the session journals (2026-09-12)*
- **It was a dispatched pop-up before that, and never a submenu** (2026-09-10). AppKit reserves the
  disclosure-arrow gutter on every row as soon as one item has a submenu, and one arrow moved the
  whole gesture column (*"a fugit toată coloana de meniuri din cauza >"*). The row builds an
  `NSMenu` on click and `popUp`s it at the pointer; **dispatched**, not inline — the click is still
  closing the menu it came from, and a menu put up inside that closing lands underneath it and
  takes no clicks.
  → journal: *Rebind to: the destinations already spoken to, most recent first (2026-09-10)*
- **Plain titles in the pop-up, deliberately.** An attributed title stops the dimming, and the
  rows that cannot be clicked — already bound, a closed window, an IDE panel with no Terminal.app
  tab — are exactly the ones that must read as disabled. Titles come from one
  `TerminalBinding.liveTitles()` AppleScript (~30 ms for the machine, about one `title(forTTY:)`);
  a tty the history remembers and the map does not is greyed, not deleted.
  → journal: *Rebind to: the destinations already spoken to, most recent first (2026-09-10)*
- **`Recover Cancelled Dictation` exists** (2026-09-10), `arrow.uturn.backward`, in the dictation
  block.
  → journal: *Every row has an icon, and two alphabets share the column*
- **⏳ lives only in the menu bar (`StatusItem.refreshGlyph`), never beside the cursor.** The
  model loads at launch (2026-09-06), so nobody waits on it; what remains is `⏳🤖` and
  `<model> — loading…` in the menu. `AppDelegate.setEngineLoading` is a one-liner into
  `StatusItem`; ⏳ is the only badge that claims the glyph.
  → journal: *The recogniser*
- **The local model's name reads `mlx-community/whisper-large-v3-turbo — 2.6 GB RAM`, in full,
  read when the menu opens — in the *submenu*.** It was a disabled row of its own at the bottom of
  the menu until 2026-09-14, then the Engine row's own title; since the same day the top-level row
  says only `Engine: Local (2.6 GB)` (`engineShortTitle`) and the full id stays one hover away, in
  the list under the arrow. A model id on the top-level row stretched the whole menu to the width
  of a string nobody reads with the menu open over their work; the size stays on both because it is
  the half that changes. The org
  prefix stays — *"trece numele modelului: mlx…"* is how Victor says it, and a name he has to
  reassemble to repeat is not the name. **It is never `Local Whisper`**: that category was the
  fallback while the helper was down, i.e. most of the time the row is read;
  `LocalWhisperSource.configuredModel` answers the id that *would* load instead, and must be kept
  in step with `helpers/whisper_helper.py`'s `MODEL`. The number is `ri_phys_footprint` from
  `proc_pid_rusage` — Activity Monitor's "Memory", not `ps`'s RSS, because MLX puts weights in
  unified memory and the two disagree. It doubles as liveness: a dead helper has no footprint and
  the row goes back to its bare name.
  → journal: *The menu says what the model costs*
- **The build stamp is a `Version: <build>` row one above Quit (2026-09-13)** — formerly the
  clickable About row `Victor's Walkie Talkie (<build>)`, before that `Quit — built Aug 28,
  17:48`. Same plain readout in Victor Addons and Victor Effects. The stamp **is the executable's
  own mtime**, never a sed'ed constant.
  → journal: *The menu bar item*, *Version row and ⌘Q (2026-09-13)*
- **It is clickable again since 2026-09-22 and opens `AboutWindow`** — a native
  `.nonactivatingPanel`, not the HTML page in a browser it was for a day (*"să fie nu webpage ci
  pagina swift de about"*). It stopped being the only dead row in the menu; the title stays the
  plain version readout, and what makes it worth clicking is what the panel holds — the mouse
  drawn with every button named, which is the legend the gesture rows gave up when their chords
  moved into AppKit's shortcut column. Still reachable from the Dock tile's main menu too.
- **The panel is adjusted to the live gesture vocabulary** (*"ajustat după alegerea actuală de
  gestures"*): it names `Logi` or `Wheel` in its headings, shows **only** that set's column, and
  derives each button's action list from the table `StatusItem` publishes rather than from a
  hand-written one — so a chord that moves, or a vocabulary switched, changes the panel with
  nobody editing it. A button idle in the live set says so by name.
  → journal: *The About page becomes a window (2026-09-22)*
- **Quit carries ⌘Q as a key equivalent (2026-09-13)**, matching the other two apps; it fires only
  while the menu is open (the app never becomes key), the real ⌘Q is in the main menu `main.swift`
  installs. Quit goes through the same `endSession(reason:)` as the ✕, so the outbox gets its
  `session_end`.
  → journal: *Autosend*, *Version row and ⌘Q (2026-09-13)*

## Prompt Log (`MessageLog`)

- **Generated on the click, never maintained.** A mirror kept in step with every send is a second
  writer on the send path; on demand, "the last 48 hours" (`MessageLog.window`) means back from
  *now*.
  → journal: *Prompt Log: the outbox read back as a page*
- **It lands in Caches — `~/Library/Caches/ro.victorrentea.wispr-relay/message-log.html` —
  beside the `shots` folder, not inside it.** `ScreenCapture.prune` walks that directory and counts
  what it finds, and a page is not a shot. The outbox itself stays in `~/.walkie-talkie`.
  → journal: *Prompt Log: the outbox read back as a page*
- **Local time grouped by day, newest first all the way down.** `ts` is UTC; three hours off in
  summer makes yesterday evening look like today. The page is opened for the sentence just said.
  → journal: *Prompt Log: the outbox read back as a page*
- **Pictures are `stat`ed at generation time**; a missing one is a dashed row saying the frame is
  gone. Shots live in Caches so the system may take them, and a broken-image box says nothing.
  → journal: *Prompt Log: the outbox read back as a page*
- **No CDN, both palettes, one inline script.** Opened off `file://`, where a remote stylesheet
  may not answer. Tokens on `:root` with a `prefers-color-scheme: dark` override. The script is
  the one bend in "no script": a dozen lines, delegated from `document`, and with JS off the page
  still shows every message minus a button.
  → journal: *Prompt Log: the outbox read back as a page*
- **Copy copies the exact `line` from the outbox — byte for byte what ⌘⇧P would paste.** `commit`
  writes `line` (the `terminalLine` the delivery used) into the JSON; older lines have none and
  `MessageLog.payload` re-assembles them — close, not identical. The payload rides in a **hidden
  `<pre>`**, not a `data-` attribute (a dictation is arbitrary text). `document.execCommand` is the
  fallback and not vestigial: the Clipboard API needs a secure context and `file://` is not one
  everywhere. The glyph is an SVG, not 📋, so it takes the button's ink at 12 px in both palettes.
  → journal: *Prompt Log: the outbox read back as a page*
- **A bad line is skipped, never thrown.** The file is appended to by a live process while the page
  reads it; one truncated tail line is not a reason to refuse the other five hundred. Lines with
  neither words nor pictures (`session_start` / `session_end`) are dropped; a missing outbox gives
  an empty page with a sentence saying so.
  → journal: *Prompt Log: the outbox read back as a page*
- **The row carries no callback into `AppDelegate`.** It needs nothing but the file on disk.
  → journal: *Prompt Log: the outbox read back as a page*

## `MenuBarMirror`

- **One borderless click-through panel per screen at `.statusBar` (above `.mainMenu`), carrying
  the same string `refreshGlyph` puts in the real item, on every space including full-screen.**
  Indicator only, no menu — opening one is a focus change away.
  → journal: *The 🤖 on the other screens*
- **Centred in the strip; `NSScreen.main` polled every 500 ms; hidden on the active screen.** The
  right end is the clock and Control Center, the left the front app's menus, the middle the only
  part of an inactive menu bar reliably empty. `NSScreen.main` moves with the focus and posts
  nothing.
  → journal: *The 🤖 on the other screens*

## Do not

- Do not hide a row the app cannot act on right now — grey it.
- Do not put `Rebind to…` back as a submenu, and do not put its panel up inline from the click.
- Do not turn the `Engine` submenu back into a pop-up, and do not let it tick a row the app has
  not switched to.
- Do not put `Replace WisprFlow` back as a row without asking — it was removed deliberately.
- Do not take **Wispr Flow** out of the `Engine` submenu again without asking — it went on the
  morning of 2026-09-22 and came back that evening once the firewall made its words as sure as
  the other engines'. Removing the row would not remove the firewall.
- Do not set `NSMenuItem.state` on any row, and do not read a label back off an item that has an
  `attributedTitle`.
- Do not give `Quit` a ⌘Q key equivalent in the status menu.
- Do not fetch anything over the network from the Prompt Log page, and do not write it into
  `shots`.

## Renames of 2026-09-22 (evening)

Victor, from the projector: `Recover Dictation` (icon `arrow.up.trash`, *"un coș de gunoi cu capacul
ridicat"*), `Dictate to New Claude`, `Mic`, `Record Screen` / `Stop Recording Screen`, and in
`Halo fx`: `Engine: projectM｜Web` (rows `projectM (native)` / `Web (butterchurn)`) and
`Pre-process: …` with its parentheses cut to two words each. In `Engine` the Wispr row is
`Wispr Flow ☁️` — a cloud after it like ElevenLabs', nothing else. The `Halo fx` rows are what
`HaloDestination.title` and `HaloStyle.title` say; the picks he confirmed that evening are
Tendrils at the caret, Tunnel bound, Sparks into a new claude, **Mosaic for Wispr's microphone —
whoever routes the words** (`AppDelegate.wisprMicSentence`; behind the firewall `foreignMic`
alone read a 🔽 → sentence as bound).
