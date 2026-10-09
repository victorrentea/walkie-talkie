---
paths:
  - "Sources/WalkieTalkie/SpawnTerminal.swift"
  - "Sources/WalkieTalkie/SpawnFolderMenu.swift"
  - "Sources/WalkieTalkie/ActiveTerminals.swift"
  - "Sources/WalkieTalkie/ProjectList.swift"
  - "helpers/recent_projects.py"
---

# Spawn: dictating to a session that does not exist yet

Rules for the gesture that opens a new Terminal window with Claude Code in it and hands it the
sentence as its first prompt (`SpawnTerminal`), the folder menu offered while the sentence is being
spoken (`SpawnFolderMenu`, `ProjectList`, `helpers/recent_projects.py`), where the window opens and
how the dialog hands over to it.
Full history and reasoning: docs/journal.md — see the sections named after each rule below.

## The gesture and what travels

- **There are two entry points now** (2026-09-12): `launchClaude(prompt:directory:)` for the
  gesture, and `resumeClaude(session:directory:)` for a session `RebindPanel`'s search found whose
  terminal has been closed (`claude --resume <id>`, in the folder the id is scoped to). Everything
  past the staged launcher is one shared `open(_:stamp:directory:what:)` — the `do script`, the
  tiling, the front being handed back — because every trap in this file lives there and none of it
  is about which of the two started it.
  → journal: *A closed window is not a dead end: ⏎ reopens the session*
- **The prompt travels in `argv` — `claude "<prompt>"` — never through the keyboard.** The
  session starts with the prompt already submitted, so there is no window to wait for, no caret to
  land in, no shell prompt to be executed at, no race between "the process is up" and "the process
  can read". Verified end to end 2026-08-30: `claude raspunde…` visible in `ps` on the spawned tty.
  → journal: *⌘ + the wheel: the destination that does not exist yet*
- **Two files on disk instead of two levels of escaping.** AppleScript is handed nothing but a
  path this app generated, and the shell reads the words with `"$(cat …)"`. A transcript carries
  quotes, apostrophes, `$`, backticks, semicolons, and surviving AppleScript's string literals *and*
  a shell command line is exactly where a dictation turns into a command. Measured with a prompt
  containing all four: it arrives byte-identical.
  → journal: *⌘ + the wheel: the destination that does not exist yet*
- **The folder is `~/workspace` unless he clicks — nothing is inferred.** Resolving it (bound
  target, else the terminal in front, else `~/workspace`) was written first and surfaced the trust
  prompt: spawned into `~/workspace/walkie-talkie`, Claude Code stopped on *"do you trust this
  folder"* instead of working, because he has only ever started it from the parent. An answer
  right four times in five is worse than a fixed one, since the fifth is discovered after the
  sentence has been spoken. A folder he pointed at on the menu is not inferred, so the menu does not
  reopen this argument.
  → journal: *⌘ + the wheel: the destination that does not exist yet*
- **The gesture is live for as long as the app is, bound or not.** It carries its own destination.
  The price stands whichever modifier it is: the chord belongs to this app whenever it is running —
  the deliberate reading of *"cât timp e pornit walkie"*.
  → journal: *⌘ + the wheel: the destination that does not exist yet*
- **The mouse chords for a spawn are live only with *Mouse Gestures: Wheel*.** ⌘ + the wheel
  and the wheel double-click are the wheel's own vocabulary; with the tick on (the default since
  2026-09-09) the row reads `🔼 ↑` in the menu. Whatever chord opens it, the behaviour below is
  the same.
  → journal: *⌘ + the wheel: the destination that does not exist yet*
- **⌘, not ⇧.** ⌘-middle-click in a browser is redundant with a bare middle click (both open a
  link in a background tab); ⇧-middle-click is a gesture of its own (new tab *and* switch to it).
  → journal: *⌘ + the wheel: the destination that does not exist yet*
- **Ending a dictation is never a spawn.** The destination belongs to the press that opened the
  microphone: a ⌘ click while one is running just ends it, a 2 s ⌘ hold still cancels.
  `HotkeyTap.wheelSpawn` is read off the **press**, not off the flags at the release, because ⌘ is
  very often let go before the button is.
  → journal: *⌘ + the wheel: the destination that does not exist yet*

## The folder menu

- **Put it up the instant the press lands, not after the opening picture.** It sits above the end
  of `startLocalRecording` because everything below it can `return` and wait seconds for cold
  weights — and the menu was waiting with them, when its clock is his reading time.
  → journal: *The folder menu (2026-09-04)*
- **Offered once per gesture.** A cold model used to make the start run twice for one press (at
  the press, then when the weights landed), and the second run re-offered the menu and wiped a
  folder already clicked — fixed 2026-09-04 with `resumed: true`. **Since 2026-09-26 there is no
  second run at all**: a cold local model records at once and its WAV waits for the weights, so
  `resumed` is gone. → journal: *The folder menu (2026-09-04)*, *Fixes to the test plan's findings, batch 3*
- **3.5 s solid, then 1 s of fade (`solidSeconds`, `fadeSeconds`) — unless the hand is on it.**
  Two seconds was tried and is not long enough to read a half-dozen names, decide and travel while
  a sentence is being spoken. **Hovering suspends the clock**: the pointer arriving mid-fade brings
  the menu back to solid, leaving lets the fade run. **A click still lands during the fade** —
  nothing turns hit-testing off, the panel is ordered out only once the animation has finished.
  **Past the solid period the pointer's position decides, read every 0.1 s (`watch`)** — and again
  in the fade's completion; the tracking areas are only the fast hint (2026-10-07: *"I was hovering
  the menu … that did not prevent it from fading out"*). A fade in flight is the `fading` flag,
  never `alphaValue < 1`: the alpha is still 1 in the fade's first frame, which is exactly when the
  hand crossing menu → submenu exits one and enters the other, so the un-fade did nothing.
  → journal: *The folder menu (2026-09-04)*
- **A wheel-drag crop takes it down at once** (2026-10-08, *"should hide immediately rather than
  waiting for me to hover out of it"*): `areaShot` calls `SpawnFolderMenu.hide()` as the selection
  overlay goes up — a drag is framing, not choosing, and the menu sat in the way of the box.
- **It draws a surface and does not follow the pointer** — the one departure from *Nothing beside
  the pointer draws a window*. Rows need edges to be told apart, and it stays where the sentence
  started so the hand can travel to it.
  → journal: *The folder menu (2026-09-04)*
- **Below-right of the pointer (since 2026-09-06), 10 pt on each axis, flipped and clamped.** It
  flips to the other side on either axis when the preferred one would hang off, then is clamped
  into the visible frame of the display the pointer is on.
  → journal: *The folder menu (2026-09-04)*
- **One level past `CGWindowLevelForKey(.maximumWindow)`.** The effect panels sit at
  `.maximumWindow` and are created *after* the menu (menu at the press, context shot at the
  release), so `.popUpMenu` lost to them and the ripple played over the choice being read. One level
  past the maximum wins by construction rather than by ordering. Overlapping the chip is fine: that
  is a `.statusBar` window, so the menu covers it and clicks land on the menu.
  → journal: *The folder menu (2026-09-04)*
- **Not an `NSMenu`.** `popUp` runs a nested tracking run loop that freezes the pulsing 🔴 and the
  chip's cursor-following, and offers neither a timed dismissal nor a fade. Rows are drawn
  `NSView`s: the panel never becomes key, and standard controls in a non-activating panel look
  permanently disabled and eat the first click. `acceptsFirstMouse` is what makes the first click
  count — the app never activates itself, so *every* click arrives at a background app.
  → journal: *The folder menu (2026-09-04)*
- **Hand cursor via a `.cursorUpdate` tracking area with `.activeAlways`, not `resetCursorRects`**
  (2026-09-09). Cursor rects are reset by the *key* window, so on a panel deliberately never key
  they never fire; `.activeAlways` is what makes a background app's cursor stick. Over text rows the
  arrow reads as an I-beam, the one thing this panel never offers. The area covers the star too.
  → journal: *The folder menu (2026-09-04)*
- **The choice rides the `Message`; a late pick is refused.** `send` moves `spawnFolder` onto
  `Message.directory` and clears it — the panel holds a prompt for seconds and the next dictation
  may have started. Moving a folder under words already in flight silently is worse than ignoring
  a late click.
  → journal: *The folder menu (2026-09-04)*
- **A picked folder gets a row of its own on the chip, behind the ✨** (Terminal's icon until
  2026-10-07: *"the new [✨] should be there instead of that console icon"*;
  `RelayWindow.sparkleGlyph`) — the shape a binding has (*"ca și cum aș fi fost deja bind-uit la un alt astfel de terminal … să știu dacă am
  setat ce trebuie"*, 2026-09-07). `RelayWindow.spawnCollapsed` split into `spawnMarked` (the ✨
  rides in front of `Listening...`) and `spawnCollapsed` (destination row dropped — only when no
  folder was picked). **Since 2026-10-07 the ✨ rides in front of `Listening...` only while
  collapsed** — with a picked folder it is that row's icon, said once. Passing the icon turns the row on, so the default `~/workspace` is untouched.
  `docs/overlay-states.html` has the `spawn-folder` Shot for it.
  → journal: *The folder menu (2026-09-04)*
- **A folder not on disk is dropped, never offered, by both halves.** The launcher falls back to
  `$HOME` on a failed `cd`, the one destination nobody meant.
  → journal: *The folder menu (2026-09-04)*

## Active Terminals — the first row (2026-09-23)

Victor: *"when I open a new terminal, I want the first option to be a menu that says 'Recent', or
'Active Terminals', and then when I hover over it, a submenu opens that lets me bind this prompt
to that terminal."* It **replaces** the morning's third half (*Or send to an open terminal*, five
recently bound terminals under the folders, `RebindHistory.openTerminals` — deleted).

- **First row, always drawn.** `Active Terminals ›`, a line, then `Start Claude in…` and the
  folders. With nothing running it reads `Active Terminals — none`, dimmed, no chevron — never
  hidden, so the folders do not move between openings. `build` is bottom-up, so *first* means
  *added last*; `evals/test_active_terminals.py` holds that, and that it is unconditional.
- **Found by looking** (`TerminalBinding.activeAgentSessions`): every Terminal.app tab whose tty
  has a process owning a fresh `~/.claude/cwd/.last-<pid>` (`publishedDirectory(ownedBy:)`).
  `liveTitles()` + one `ps -ax` + a `stat` per pid — never one `osascript` per tab. Off the main
  thread, **after** the menu is up (`fillActive`); the row is measured for its longer label so the
  answer restyles it in place and the clock is not restarted.
- **The rows are a pure function** (`ActiveTerminals.items`, `swift test`): folder alone when
  unique; shared folder → the task from the tab title, else the tty, plus the tty when two tasks
  match; alphabetical; the bound tty ticked `✓` (either spelling of the tty).
- **A pick binds and the ordinary delivery sends** (`AppDelegate.redirectSpawn`), **without raising
  the terminal** (2026-10-08, Victor: *"it should not come in front by default … I usually don't care
  where it is"*). The spawn is
  cleared **at the click** — `showBound` only drops a spawn while `listening`, and the menu still
  answers during the settle. While the bind (`osascript`) is in flight `commit` **holds** the
  sentence (`spawnPickInFlight`, no flash) and the pick's `showBound` releases it; the caret is
  not latched for a pick in flight. **A pick that cannot bind puts the spawn back**
  (`spawnAfterFailedPick`), never a hold the 10 s poll would release into the old binding. A pick
  after `send` is refused (`spawnPending` guard), as a late folder is.
- **The submenu is a second non-activating panel**, not an `NSMenu`, same level and
  `sharingType = .none`; right of the menu, its first row level with *Active Terminals*, flipped
  left and clamped at the screen edge. Hovering it suspends the fade like the menu
  (`hoveredMain || hoveredSub`); another row entered closes it after `submenuGrace` = 0.3 s unless
  the hand reaches it. It fades and hides with the menu.
- **`WT_SHOOT_MENU` draws it open** with the real sessions; `WT_SHOOT_BOUND=ttysNNN` ticks one.

## Sessions under their folders (2026-10-07)

Victor: *"to have the active session grouped under [the projects] … only if you've never sent
Kamikaze to that session yet … Clicking the parent, not just hovering, but clicking should start a
new one, even if it has children … the remaining terminals … should stay in the first"*, then *"an
emoji with the three yellow stars just in front of [each] project … [children] should have in front
of them an icon of the terminal"*, and *"a hourglass in front of them if you detect that Claude
session to be active right now"*.

- **A folder's sessions are lines under it, not a submenu** (2026-10-09, Victor: *"there are
  submenus right now which take time and look awkward when they paint … display the terminal which
  is already working in that project below the entry for that project … a bit indented to the
  right. So there are no more sub menus … leave Active Terminals … this extra space in front allows
  you also space to put the checkbox"*) — supersedes the chevron-and-submenu below. Each session is
  a `FolderRow` with `indent` (`sessionIndent` 8 pt), `sessionFont` 15 pt, `sessionHeight` 24 pt,
  under its folder: the ✓ in the indent, Terminal's icon, ⏳ when busy, the name; no star. A click
  binds it (`redirectSpawn`), exactly as an *Active Terminals* pick. The folder row's click still
  opens a new session. **Only *Active Terminals* keeps a submenu.**
- **Drawn from the first frame: the last opening's sessions** (`lastSessions`), then `fillActive`'s
  fresh look relays the menu out (top-left kept, clock not restarted) only when `children` changed —
  so lines appear under the hand only on the opening after a session started or ended.
- ~~**A folder row with live sessions grows a chevron (between name and star) and a submenu on
  hover; its click still opens a new session**~~ (2026-10-07 → 2026-10-09).
- **`ActiveTerminals.grouped`**: a session belongs to the deepest row whose path is its directory
  or contains it; what no row claims stays under *Active Terminals* (`— none` when nothing is left).
  `regroup()` runs when the sessions land and after a star. Folder submenus name the task from the
  tab title, else the subfolder, else the folder, `· tty` on a tie (`folderItems`).
- **Folder rows wear ✨ in front of the name (*opens a new session*); session rows wear Terminal's
  icon (*a running session*) after the ✓ column, and ⏳ when busy.**
- **Busy and kamikaze come from Claude Code's own `~/.claude/sessions/<pid>.json`** (`status`,
  `sessionId`, `cwd`; `TerminalBinding.agentState`) — the pid is the one owning `.last-<pid>`.
  **A session any of whose user prompts has `kamikaze` on a line of its own is offered nowhere**
  (`ActiveTerminals.isKamikaze`; the transcript is byte-scanned, only user lines with the word are
  parsed, tool results ignored). A missing file answers *idle, not kamikazed*.
- **Leaving *Active Terminals* for another row closes its submenu after `submenuGrace`** unless the
  hand reaches it (`entered`) — the diagonal into it crosses other rows.
- `WT_SHOOT_MENU` draws the session lines in place and *Active Terminals*' submenu open when it has
  any (`WT_SHOOT_SUB` is gone with the folder submenus).

## Pinned + recent (`ProjectList`, `helpers/recent_projects.py`)

- **The list is pinned projects, a separator, then the five most-worked repos of the last
  fortnight — never a hardcoded list.** Six names in Swift were right the day they were written
  and silently wrong the week after; the cost of a missing project is the first sentence of every
  session, spoken to tell the agent where it is. `~/workspace` holds ~150 directories, nearly all
  course material, so a listing is not a menu either.
  → journal: *Two halves, and a line between them (2026-09-08)*
- **`PinnedProjects` is seeded from the six that were hardcoded**, persisted in
  `~/.walkie-talkie/pinned-projects.json`. A pinned folder that is missing is dropped from the menu
  but **kept in the file** — an external disk or a checkout he will make again should not cost the
  pin. Only a click removes one.
  → journal: *The star*
- **`RecentProjects` comes from `helpers/recent_projects.py`, which reads
  `~/.claude/projects/*/*.jsonl`.** Three metrics were measured on his real 14-day window —
  weighted cost (output ×5, cache-creation ×1.25, input ×1, cache-read ×0.1), raw output tokens,
  prompt count — and **all three name the same top five** (4th and 5th swap). There is nothing to
  tune; do not spend an afternoon believing there is.
  → journal: *Where the bottom half comes from*
- **`cwd` is read per record, not per session; everything under `~/workspace/<x>/` rolls up to
  `<x>`.** Left alone, `petclinic/petclinic-backend/.codecity-tool` ranked *seventh in its own
  right*, splitting the project that ranked first; the rollup also makes worktrees
  (`agentic-how/.claude-worktrees/…`) free. Outside `~/workspace` the git root stands alone;
  outside `$HOME` nothing counts (`/private/tmp` scratchpads).
  → journal: *Where the bottom half comes from*
- **Cheap, no cache, no incremental offset, no model.** ~1 GB across ~800 transcripts scans in
  **1.9 s** because a line reaches the JSON parser only after a raw byte scan finds `"assistant"`.
  That is cheap enough to make a cache and a read offset two classes of bug not written.
  → journal: *Where the bottom half comes from*
- **Apple's `/usr/bin/python3`, deliberately.** Pure stdlib; `Transcriber.pythonPath`'s probe for
  an interpreter carrying `mlx_whisper` would cost several process launches for a question this
  does not ask.
  → journal: *Where the bottom half comes from*
- **`RecentProjects.refreshIfStale` runs at most once a day, detached, never waited on — asked at
  launch and at the gesture.** A single `stat`; a login item can stay up a week (launch is not
  often enough) and be restarted five times in an afternoon (the age check stops five rescans).
  The menu that triggers a scan shows yesterday's answer.
  → journal: *Where the bottom half comes from*
- **The file holds every qualifying project, not the top five.** The menu takes its five *after*
  removing the pinned ones, and a pin comes off at any moment — a file of five would make an
  unpinned project vanish until tomorrow's scan.
  → journal: *Where the bottom half comes from*

## The star

- **Clicking the star moves a row across the line and does not close the menu; the clock
  restarts.** A star changes what the menu *is*, not what it asks; a hand that has just arranged the
  list is about to use it.
  → journal: *The star*
- **Unpinning is not a delete.** The row falls into the recent half if it qualifies and disappears
  if it does not — `RecentProjects.offered` with the pin removed, no extra code.
  → journal: *The star*
- **Chosen by rank, shown alphabetically — both halves** (*"în ordine descrescătoare după… nu,
  alfabetic"*). A leaderboard that reorders itself between two openings moves the row he reached
  for last time.
  → journal: *The star*
- **On the right; SF Symbols `star` / `star.fill`; the hollow star is dim but always drawn.** An
  on/off pair drawn by two hands reads as two unrelated marks; a control revealed on hover is one
  found by accident first. The right side keeps folder names in one flush-left column.
  → journal: *The star*
- **A subview, not a hit region tested inside the row's `mouseUp`.** The two clicks mean opposite
  things (open a session and dismiss / rearrange and keep up); a hit test off by two points would
  start a session he did not ask for.
  → journal: *The star*
- **A rebuild keeps the panel's top-left corner (`anchor`).** The menu hangs *below* the pointer;
  anchoring the bottom would slide every row out from under the hand that just clicked one.
  → journal: *The star*

## `WT_SHOOT_MENU`

- **Review layout changes with `WT_SHOOT_MENU=/tmp/menu.png ./.build/debug/WalkieTalkie`**
  (`SpawnFolderMenu.shoot`), never by eye during a 3.5 s dictation. The panel is
  `sharingType = .none` like everything near the pointer, so this is the only picture of it.
  → journal: *`WT_SHOOT_MENU` — because this panel cannot be photographed either*
- **Template tint must happen inside an `NSImage(size:flipped:)` of its own.** Drawing a template
  `NSImage` and then `fill(using: .sourceAtop)` over the same rectangle paints the whole box — it
  composites against the opaque row and blur — and the stars came out as **five solid squares**.
  Invisible in review, obvious in a picture.
  → journal: *`WT_SHOOT_MENU` — because this panel cannot be photographed either*
- **If eleven rows feel rushed, the number to change is `solidSeconds`.** The clock did not grow
  with the list; hover-suspend and click-during-fade make it answerable.
  → journal: *`WT_SHOOT_MENU` — because this panel cannot be photographed either*

## Binding, chip and test routes

- **The binding moves to the new window — always, not only when nothing was bound** (since
  2026-09-01). Reported that day: *"nu s-a autolegat de acel terminal … a rămas idle"* — the
  second sentence of a conversation just started had nowhere to go and he bound by hand a minute
  later. A spawn says *the session I want does not exist yet*, the same sentence as letting a
  binding go. Two spawns in a row each get their own window; the relay ends up on the second.
  → journal: *`WT_SHOOT_MENU` — because this panel cannot be photographed either*
- **`AppDelegate.adoptSpawnedWindow` binds by tty (`TerminalBinding.bind(tty:)`), not by "the
  tab in front", and flashes nothing on success.** The window was never pointed at and Victor's
  focus may have moved on; the chip naming it is the whole message. It polls for the window (up to
  `spawnWindowWait` = 4 s) rather than firing on a fixed beat, because `do script` returns as soon
  as Terminal has a window — the shell is still starting and the chip's label is read off the
  process on that tty, which does not exist yet. The frame comes from
  `TerminalBinding.terminalWindowFrame(tty:)`.
  → journal: *`WT_SHOOT_MENU` — because this panel cannot be photographed either*
- **The chip says the destination that does not exist yet (`RelayWindow.spawnLabel`) as one ✨
  mark in front of `Listening...` / `Transcribing...`, not a row of its own** (since 2026-09-02;
  *"Pune doar steluțe în fața butonului de listening și nu mai afișa primul rând."*). The 🔴 keeps
  the glyph column — a frozen recording row is indistinguishable from a hung app. The held panel
  keeps its title row. Only the spawn collapses: Replace Wispr's `at caret` keeps its row, which is
  why the mark is passed in (`setSpawnDestination(_:mark:)`) rather than sliced off the label.
  → journal: *`WT_SHOOT_MENU` — because this panel cannot be photographed either*
- **`POST /test/spawn` exercises the spawn from a desk; `POST /test/spawn-folders` the menu.**
  `/test/dictation` is gated on a binding, the one condition a spawn is defined by not needing;
  `/test/spawn` enters *below* the microphone with a finished transcript, so without its own route
  the menu's geometry, fade and clickability are unverifiable.
  → journal: *⌘ + the wheel: the destination that does not exist yet*

## Where the window opens (`SpawnTerminal.board()` / `slot(for:on:avoiding:)`)

- **Tile across every non-Retina screen *lateral* to the primary, left to right; with nothing but
  the Retina display, open behind.** "Retina" is `backingScaleFactor >= 2` — deliberately not a
  size or a name.
  → journal: *Where a spawned window opens (2026-09-04)*
- **"Lateral" is measured: a screen is *stacked* when it shares more than half of its own width
  with the primary's horizontal span, and stacked screens are dropped** (2026-09-09, *"start the
  terminals on the lateral screens, not on the screen above"*). At home a Dell at `(-89, 1117)`
  stacked above the laptop took a third of the spawns. The primary is never stacked, so a desk of
  only external monitors still tiles; a sliver of overlap is *beside*. Verified on the four real
  displays: two side Dells kept, the one above dropped, the Retina one dropped.
  → journal: *Where a spawned window opens (2026-09-04)*
- **Neither case activates Terminal (2026-09-08).** `activate` is an *application*-level raise: it
  lifts every Terminal window on every display (*"toate terminalele sar în față, inclusiv cele de
  pe retina"*). Measured with Finder frontmost and Terminal running: `do script` creates the window
  and **does not** take the front. The quarter-second focus restore stays, in both branches, for
  the one case that still steals it — a Terminal launched from cold by `do script`. It gives back
  focus only; raised windows stay raised, which is why `activate` had to go rather than be undone.
  → journal: *Where a spawned window opens (2026-09-04)*
- **Victor Addons' four quadrants, scored not filtered** (2026-10-04, *"să le așezi în modul de
  tile pe care îl pune default Mac OS addons. Nu rulat tile efectiv, dar … în colțuri"*). Each
  screen's visible frame is cut like `TerminalTileLayout.quadrants` (halves, `quadrantMargin` 2 pt
  at the outer edges only) and the window **takes the quadrant's size**; the other windows are not
  moved (⌘⌃A remains the tile). Every quadrant scored by square points of *other* Terminal windows
  it would cover, first lowest wins, TL → TR → BL → BR, screens left to right. Until that day the
  cells were the window's own default size, centred — two terminals side by side mid-screen.
  → journal: *Where a spawned window opens (2026-09-04)*
- **Only Terminal's own windows are avoided, listed in the same `osascript` round trip that
  opened the window.** A second interpreter launch is a launch for nothing; asking the window
  server about every app would price a browser off the monitors that are there to hold browsers.
  → journal: *Where a spawned window opens (2026-09-04)*
- **Everything below `board()` speaks AppleScript coordinates** (origin top-left of the primary,
  y downwards) — the only consumer is `set bounds of window`.
  → journal: *Where a spawned window opens (2026-09-04)*

## The spawn flight and the held dialog

- **A spawn's flight is a white outline growing out of the dialog onto the new window, 1 s**
  (`outlined: true`, no `picturing:` — `destinations-and-outbox.md`, *The send flight*). The seed
  (`AppDelegate.spawnSeed`) is 96 pt tall with **the window's own aspect ratio**, 12 pt under the
  anchor, clamped into that screen. `spawnGrowSeconds` = 1.0 against `sendFlightSeconds` = 0.55:
  this is the only thing on screen saying *which monitor* the session went to. The border
  dissolves over `spawnFlightRest` = 0.5 s (`tail:` — the fade starts with the last sixth of the
  travel to go, `BindFlight.tailFadeFraction`).
  → journal: *The little terminal grows out of the dialog (2026-09-09)*
- **No `reversed:` anywhere in a spawn.** Both branches run forwards from a seed to the window;
  the panel-less fallback anchors the same flight under the chip instead of under the dialog.
  → journal: *The little terminal grows out of the dialog (2026-09-09)*
- **The panel is not relayouted when a spawn is sent (`RelayWindow.spawnPanelHeld`).** The
  destination does not exist yet; collapsing left a hole — dialog gone, nothing arrived, an outline
  setting off from a chip with no connection to what was read. State behind the panel is cleared as
  always; what stays is the last laid-out frame. Two guards: `followCursor` returns early (the
  flight is aimed at that rectangle) and `refreshOpacity` returns early (a keystroke mid-dissolve
  would animate it back up). **Any relayout ends the hold** (`endSpawnHold` at the top of
  `layoutContent`) — newer state wins the chip.
  → journal: *The spawn's flight leaves the dialog, and the dialog waits for it*
- **The dialog holds still `spawnPanelFadeDelay` = 0.25 s after the flight leaves, then fades over
  `spawnPanelFade` = 0.5 s (`releaseSpawnPanel`).** On the same instant, the two read as both
  fading at once — a dismissal, not a journey (*"vreau să văd vizual că ideea dialogului se duce
  spre terminal"*, 2026-09-07). A quarter second is a third of the flight, and the half-second fade
  then ends within a hair of the arrival.
  → journal: *The spawn's flight leaves the dialog, and the dialog waits for it*
- **Then the dialog waits, inactive, for the session to take the prompt** (2026-10-04, Victor:
  *"să rămână dialogul acela sus inactiv … până când terminalul efectiv primește și începe să
  lucreze"*). After the flight leaves, `releaseWhenSessionStarts` polls (¼ s, off main) for a `.jsonl`
  in `~/.claude/projects/<folder>/` created since the launch with a `"type":"user"` line, then fades
  it; `spawnStartWait` = 90 s is the cap. While held the panel `ignoresMouseEvents` (no hover, no ✕,
  no click) and **only a dictation, a wait, a flash or a new prompt end the hold** — the spawn's own
  bind and the 10 s title tick no longer relayout over it (`layoutContent`'s early return;
  `reposition` is guarded too). A resumed session (`resumeClaude`) keeps the old release.
- **The pointer on it keeps it past the release** (2026-10-05, Victor: *"dacă țin mouse-ul pe
  căsuța aceea … chiar dacă textul a plecat deja în terminal … să rămână pe ecran, să pot să citesc
  mai atent"*). `releaseSpawnPanel` defers while `NSEvent.mouseLocation` is inside `panel.frame`
  (polled at 10 Hz — the panel still ignores mouse events, so no tracking area), and fades as soon
  as the pointer leaves. A pointer that has not moved > 2 pt since the hold began is resting, not
  reading, and does not keep it. Log `✨ the spawn's dialog stays — the pointer is on it` /
  `✨ the pointer left the spawn's dialog — it goes`. A dictation or a flash still ends it.
- **The terminal is open before any of this starts.** A flight needs a real rectangle, which is
  why `adoptSpawnedWindow` polls up to `spawnWindowWait` = 4 s and why the panel is *held* rather
  than dismissed when the prompt resolves.
  → journal: *The spawn's flight leaves the dialog, and the dialog waits for it*

## Do not

- Do not infer the spawn folder from the bound target or the front terminal — `~/workspace` or a
  click, nothing else.
- Do not turn the folder menu into an `NSMenu`, put the hand cursor in `resetCursorRects`, or
  accept a folder pick after `send` has moved it onto the `Message`.
- Do not read `wheelSpawn` off the release flags, and do not make a ⌘ click during a dictation
  spawn.
- Do not reintroduce `activate` in `SpawnTerminal`, `reversed:` in a spawn flight, or a picture on
  the send flight to an existing terminal.
- Do not cache or offset-read in `recent_projects.py`, and do not trim its output file to five.
- Do not hide *Active Terminals* when nothing is running, move it off the first row, or let a
  pick's words out before its bind lands.
- Do not make a folder row's click do anything but start a new session, and do not put the folder submenus back.
- Do not offer a session that was sent `kamikaze`.
