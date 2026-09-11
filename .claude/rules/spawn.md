---
paths:
  - "Sources/WalkieTalkie/SpawnTerminal.swift"
  - "Sources/WalkieTalkie/SpawnFolderMenu.swift"
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
- **The mouse chords for a spawn are live only with *Use Logi Gestures* unticked.** ⌘ + the wheel
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
- **Offered once per gesture.** A cold model makes `startLocalRecording` run twice for one press
  (at the press, then when the weights land); the second run re-did the opening — the menu
  re-appeared ten seconds in under the hovering hand with its clock restarted, and a folder he had
  *already clicked* was wiped by the `spawnFolder` reset. The continuation passes `resumed: true`,
  which keeps the choice and skips the offer (fixed 2026-09-04).
  → journal: *The folder menu (2026-09-04)*
- **3.5 s solid, then 1 s of fade (`solidSeconds`, `fadeSeconds`) — unless the hand is on it.**
  Two seconds was tried and is not long enough to read a half-dozen names, decide and travel while
  a sentence is being spoken. **Hovering suspends the clock**: the pointer arriving mid-fade brings
  the menu back to solid, leaving lets the fade run. **A click still lands during the fade** —
  nothing turns hit-testing off, the panel is ordered out only once the animation has finished.
  → journal: *The folder menu (2026-09-04)*
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
- **A picked folder gets a row of its own on the chip, behind Terminal's icon** — the shape a
  binding has (*"ca și cum aș fi fost deja bind-uit la un alt astfel de terminal … să știu dacă am
  setat ce trebuie"*, 2026-09-07). `RelayWindow.spawnCollapsed` split into `spawnMarked` (the ✨
  rides in front of `Listening...`) and `spawnCollapsed` (destination row dropped — only when no
  folder was picked). Passing the icon turns the row on, so the default `~/workspace` is untouched.
  `docs/overlay-states.html` has the `spawn-folder` Shot for it.
  → journal: *The folder menu (2026-09-04)*
- **A folder not on disk is dropped, never offered, by both halves.** The launcher falls back to
  `$HOME` on a failed `cd`, the one destination nobody meant.
  → journal: *The folder menu (2026-09-04)*

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
- **A grid of the window's own size, scored not filtered.** Cells as big as the window Terminal
  just made (two columns of a 905 pt terminal on a 1920 pt monitor), grid centred; every cell
  scored by square points of *other* Terminal windows it would cover, first lowest wins. With every
  slot taken — six terminals across three monitors — the answer is the least-covered cell, and
  left-to-right lands a second spawn beside the first.
  → journal: *Where a spawned window opens (2026-09-04)*
- **Only Terminal's own windows are avoided, listed in the same `osascript` round trip that
  opened the window.** A second interpreter launch is a launch for nothing; asking the window
  server about every app would price a browser off the monitors that are there to hold browsers.
  → journal: *Where a spawned window opens (2026-09-04)*
- **Everything below `board()` speaks AppleScript coordinates** (origin top-left of the primary,
  y downwards) — the only consumer is `set bounds of window`.
  → journal: *Where a spawned window opens (2026-09-04)*

## The spawn flight and the held dialog

- **A spawn sends the window, not an outline: the little terminal grows out of the dialog
  carrying the destination's pixels, forwards, 1 s** (2026-09-09). `BindFlight.fly(from:
  spawnSeed(under: promptFarewell, like: window), to: { window }, picturing: window)`; the seed
  (`AppDelegate.spawnSeed`) is 96 pt tall with **the window's own aspect ratio**, 12 pt under the
  anchor, clamped into that screen. `spawnGrowSeconds` = 1.0 against `sendFlightSeconds` = 0.7:
  this is the only thing on screen saying *which monitor* the session went to. **Only the spawn
  changes** — `sendFlight` to an existing terminal is untouched (outline only, 0.7 s).
  → journal: *The little terminal grows out of the dialog (2026-09-09)*
- **`picturing:` is the one case where the pixels come from the far end.** The grab is from the
  *destination* rectangle, so it lands pixel for pixel on what is there and only the white border
  dissolves, over `spawnFlightRest` = 0.5 s (`tail:` — the fade starts with the last sixth of the
  travel to go, `BindFlight.tailFadeFraction`, and reaches nothing half a second after rest).
  → journal: *The little terminal grows out of the dialog (2026-09-09)*
- **No `reversed:` anywhere in a spawn.** Both branches run forwards from a seed to the window;
  the panel-less fallback anchors the same flight under the chip instead of under the dialog.
  → journal: *The little terminal grows out of the dialog (2026-09-09)*
- **The grab photographs whatever is on top.** `CGWindowListCreateImage` on a screen rectangle
  returns that patch of screen; on this path the window was just tiled into a free cell, so
  nothing covers it.
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
