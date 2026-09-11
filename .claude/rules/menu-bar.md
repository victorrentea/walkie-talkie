---
paths:
  - "Sources/WalkieTalkie/StatusItem.swift"
  - "Sources/WalkieTalkie/MenuBarMirror.swift"
  - "Sources/WalkieTalkie/MessageLog.swift"
  - "Sources/WalkieTalkie/AboutPage.swift"
---

# The menu bar item

Rules for the 🤖 in the menu bar and its menu (`StatusItem`), the mirrors on the other screens
(`MenuBarMirror`), the Prompt Log page (`MessageLog`) and the About page (`AboutPage`).
Full history and reasoning: docs/journal.md — see the sections named after each rule below.

## The header and the menu's job

- **Every string in `StatusItem` is English.** The menu is where every gesture is written down —
  `Connect Terminal` / `Disconnect` / `Start dictation to new claude` and their chords, the three
  dictation rows, `Replace WisprFlow`, the legends, `Autosend`, `About`, `Quit`, the model readout.
  → journal: *UI language: English only*
- **The header `Bound to: folder@branch` is written from `AppDelegate.showBound` only** — the
  single place the chip's line and the menu's header are set, so they cannot disagree. Only the
  bound form carries the prefix; unbound the header falls back to `🤖 <launch label>`. The chip
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
| `Paste last prompt` | 📋 | `⌘⌃P` |
| — separator — | | |
| `Start Dictation` | `mic` | `🛞` |
| `Start dictation to new claude` | ✨ | `🛞🛞` |
| `End Dictation` | `mic.slash` | `🛞` |
| `Cancel Dictation` | 🗑️ | `🛞 2s` |
| `Recover Cancelled Dictation` | `arrow.uturn.backward` | |
| `Take Screenshot` | 📷 | `⬇️` |
| `Select Screen Area` | ✂️ | `🛞 drag` |
| `Pick Element in Chrome` | ✋ | `⌘⇧ + ⬅️` |
| `Replace WisprFlow` | a `checkmark` when on, **nothing** when off | the forward side button (see *Replace Wispr*) |
| `Autosend` | the same pair — a `checkmark` when on, **nothing** when off | |
| `Prompt Log` | 📜 | |
| `Victor's Walkie Talkie (<build>)` | ℹ️ | | |
| `Quit` | `power` | | |

- **The shortcut column above is the wheel vocabulary — live only with *Use Logi Gestures*
  unticked.** Each `gestureRows` entry carries two legends, `(item, label, logi, wheel)`, and
  `restyleGestures` picks one; the Logi set (default since 2026-09-09) is `◀️ + 🔼` bind, `🔽 ↓`
  disconnect, `🔼 →` start/end, `🔼 ↑` new claude, `🔼 ←` cancel, `🔼` Replace WisprFlow, `🔽`
  screenshot, `🛞 drag` area, `⌘⇧◀️` pick. Vocabulary: an emoji for the button (`◀️`/`▶️` left
  and right, `🔼`/`🔽` the stacked forward and back side buttons, `🛞` the wheel), a thin text arrow
  for the movement, `+` only to join a held button to the wheel — no `+` in `⌘⇧◀️`, since hold-and-
  click is one gesture (2026-09-09). `restyleGestures` runs on the toggle as well as on every open,
  and the tab stop is measured against the wider of the two sets so the column cannot resize under
  the pointer.
  → journal: *Use Logi Gestures — the tick that chooses between the two sets*
- **Rebind to… sits with the destination rows** (2026-09-10) — its rules are below.
  → journal: *Rebind to: the destinations already spoken to, most recent first (2026-09-10)*
- **One shortcut column, not two** (2026-09-06). Chords are drawn via a **right tab stop in an
  attributed title**; ⌘⌃B and ⌘⌃D have no `keyEquivalent` and ⌘⌃P lives in the drawn column. None
  of them ever fired *as* a menu key equivalent — this app is never the key app — the chords belong
  to `HotkeyTap`. `StatusItem.layOutGestures` measures **one** tab position for the whole menu (the
  widest of the longest plain row and label + 28 + chord).
  → journal: *Every row has an icon, and two alphabets share the column*
- **`attributedTitle` rewrites `title` — store labels in `gestureRows`, never read them back off
  the item.** `restyleGestures` once built its string from `row.item.title`, so the second pass
  concatenated the chord onto a title already carrying one: every gesture row printed its chord
  twice, on two lines, right on first open and wrong every open after.
  → journal: *Every row has an icon, and two alphabets share the column*
- **An attributed title stops AppKit dimming a disabled row.** A disabled `End Dictation` came
  out as black as a live one. `restyleGestures` picks the ink off `isEnabled` and runs from
  `menuWillOpen`, the one moment every flag is current — the same reason the header and the
  footprint are read there.
  → journal: *Every row has an icon, and two alphabets share the column*
- **On/off pairs are SF Symbols on both sides; everything with no off state is an emoji rendered
  through `StatusItem.emojiIcon` at the column's size.** Unicode has no crossed-out map pin or
  microphone, and a pair drawn by two alphabets reads as two unrelated rows.
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

## Switches: Autosend, Replace WisprFlow, Use Logi Gestures

- **Switch state lives in the icon column — a `checkmark` when on, a blank image of the column's
  exact width when off — never `NSMenuItem.state`.** A ticked row makes AppKit reserve the state
  column for the **whole** menu, shoving every other row sideways the moment one is switched on.
  Blank, not ⏸️ or ⏩: a picture in the column claims the row is *doing* something, and these two
  are the menu's only switches, so the one fact to carry is on or off (*"autosend să aibă bifă în
  față, nu ⏩ când e activ"*, 2026-09-07).
  → journal: *Autosend*
- **Autosend and Replace WisprFlow persist across launches** (both since 2026-09-07). Ticked,
  the pre-send panel still opens for `AppDelegate.autosendHold` = 1 s — the receipt, without
  which a delivery cannot be told from a drop — **with no Send and no Cancel and no buttons' row**:
  two buttons up for one second are two buttons nobody can reach. State lives on the item and is
  pushed through `onToggleAutosend`, so tick and behaviour cannot disagree.
  → journal: *Autosend*
- **Use Logi Gestures defaults to on, and the default has to be written out:**
  `object(forKey:) as? Bool ?? true`. `UserDefaults.bool(forKey:)` answers `false` for a key never
  written, which would have shipped the wheel gestures to the Mac already configured for the new
  ones.
  → journal: *Use Logi Gestures — the tick that chooses between the two sets*

## Rebind to…, Recover, Quit and readouts

- **`Rebind to…` is a dispatched pop-up, not a submenu** (2026-09-10). AppKit reserves the
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
- **The engine row reads `<model> — 1.6 GB RAM` (bare model name, org prefix stripped), disabled,
  read when the menu opens.** A readout, not a switch. The number is `ri_phys_footprint` from
  `proc_pid_rusage` — Activity Monitor's "Memory", not `ps`'s RSS, because MLX puts weights in
  unified memory and the two disagree. It doubles as liveness: a dead helper has no footprint and
  the row goes back to its bare name.
  → journal: *The menu says what the model costs*
- **The build stamp on the About row (`Victor's Walkie Talkie (<build>)`, formerly `Quit — built
  Aug 28, 17:48`) is the executable's own mtime**, never a sed'ed constant.
  → journal: *The menu bar item*
- **No ⌘Q key equivalent in the status menu.** ⌘Q is in the main menu `main.swift` installs; a key
  equivalent here would advertise a shortcut that does nothing outside the open menu. Quit goes
  through the same `endSession(reason:)` as the ✕, so the outbox gets its `session_end`.
  → journal: *Autosend*

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
- **Copy copies the exact `line` from the outbox — byte for byte what ⌘⌃P would paste.** `commit`
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
- Do not put `Rebind to…` back as a submenu, and do not `popUp` it inline from the click.
- Do not set `NSMenuItem.state` on any row, and do not read a label back off an item that has an
  `attributedTitle`.
- Do not give `Quit` a ⌘Q key equivalent in the status menu.
- Do not fetch anything over the network from the Prompt Log page, and do not write it into
  `shots`.
