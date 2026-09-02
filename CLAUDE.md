# Walkie Talkie — working notes

See `README.md` for what this is and how it works. This file is for rules that
must survive across sessions.

## UI language: English only

**Every string the app renders on screen is in English** — the title, the hint
legend, flash messages, error banners. No Romanian in the UI, ever, even though
Victor dictates in Romanian and these notes discuss it in Romanian.

Why: the overlay is on screen during workshops, in front of an international
audience and often mirrored to a projector. A Romanian label is noise to the room
at best and a distraction at worst.

This applies only to what is *rendered*. Log lines, comments and commit messages
are unaffected, and the dictation content itself is obviously whatever language
he spoke.

Current strings live in `RelayWindow.swift`:
- `Self.shotHint` + `recordText` — the shots row (`📸 2 — mouse/F3 for more shots`)
  and `engineText` beside the pulsing 🔴 (`Listening…` — the model id it used to
  carry now lives only in the menu's engine row, see `applyWhisperTitle`)
- `Self.pickHint` + `pickText` — the ⌘⇧-picked row (`⌘⇧`, then
  `×2 div#cart > span.price`, both behind Chrome's icon); the label beside the outline in
  `chrome-extension/inspect.js` counts too, and so do its one error string
  (`⚠ no relay session took it`) and the toolbar title in `relay.js`
- `titleText` — `🤖 <label>`
- `flash(_:)` / `flashTitle(_:)` call sites in `AppDelegate.swift`
- `StatusItem.swift` — **now the longest of these**, since the menu is where
  every gesture is written down (*The chip teaches nothing; the menu does*):
  `Connect Window — hold ⬅️ + 🛞`, `Disconnect — hold ➡️ + 🛞`, the three
  dictation rows, `New Claude Code in ~/workspace — ⌘ + 🛞, or hold ➡️ + 🛞 1s`,
  `Replace Wispr — forward button dictates, pasted at the caret`,
  `One More Screenshot`, the `Pick an Element in Chrome` legend, `Autosend`,
  `Quit`, and the `Local Whisper` readout

The first two are **not on screen at the moment**: `showsGestureHints` is off, so
the rows are built and never shown. They still have to be English when the flag
goes back.

## The overlay's states are photographed, and the page is part of the change

`docs/overlay-states.html` shows **every state the chip and the panel can be in** —
33 of them — each with the moment it appears and why it looks the way it does. It
is generated: the catalogue, the order, the sections and every word of prose live
in `Sources/WalkieTalkie/OverlayStates.swift`, the pictures are the real views
drawing themselves through `RelayWindow.snapshot`, and `docs/build-overlay-states.py`
only lays them out.

**The rule: no change to the overlay is finished until that page is rebuilt.**

```sh
./docs/shoot-overlay-states.sh      # shoots all 33 states, regenerates the HTML
```

That covers a new row, a reworded string, a changed glyph, a different colour, a
state that starts or stops existing — anything Victor could see. A new state also
means a new `Shot` in `OverlayStates.swift`; a state that goes away means deleting
one. **Never edit `docs/overlay-states.html` by hand** — it is overwritten on the
next run, and a hand-edit is a lie that survives exactly until then.

Why it is worth the machinery: this window is invisible to every screen capture,
half its states last two seconds, and several of them (`⚠️ Whisper unavailable`, a
transcript the confidence gate flagged, the refused shell prompt) cannot be
reached on demand at all. Before this, reviewing a layout change meant standing
behind Victor, or `kill -USR1` at the right instant. A page that regenerates in
twenty seconds is what makes "look at all of it" a thing anyone can actually do.

The script stands the installed app down (`SingleInstance`) and puts it back when
it is finished.

## Bound to a terminal: the second destination

Since 2026-08-15 the relay can be **pointed at a terminal**, and every dictation
from then on is typed into that session and submitted — no `/relay`, no skill, no
`Monitor` armed on the outbox, no label filter to get right. `⌘⌃B` (this app's own key since 2026-08-26, see below) binds whatever
terminal is in front.

**The outbox is still written whenever a message goes out.** A binding is a
second destination, not a replacement: `AppDelegate.commit` writes the JSONL line
and *then* delivers, so the log survives, an agent watching the queue the old way
keeps working, and `session_end` — which is addressed to a watcher and means
nothing to a terminal — is the one kind that is not delivered.

**But a binding is now also the on switch** — see *Unbound is inert*. There is no
longer such a thing as a relay that writes the outbox with nothing bound.

### IDE terminals go through the editor's own extension

`⌘⌃B` on VS Code or IntelliJ no longer pastes. The relay finds a loopback
listener published by Victor's own extensions — `victor-vsc`'s
`relay-terminal.js` and the `live-coding` plugin's `RelayTerminalService` — under
`~/.walkie-talkie/ide/`, asks it which terminal is selected, and hands it every
later line (`IDEBridge.swift`). The extension calls `sendText` /
`sendCommandToExecute` on **that** widget.

**Why, measured.** The old `.keystroke` path addressed the *application* and
delivered with clipboard → activate → ⌘V → Return, and ⌘V goes wherever the
caret is. Four deliveries on a bound IntelliJ, one variable:

| caret at delivery | where it landed |
|---|---|
| the bound terminal | correct |
| another app entirely | correct — the app is activated, the caret never moved |
| the **editor** | **into the source file**, plus a Return |
| a second terminal tab | the wrong terminal |

and the relay logged `delivered` for all four, because "⌘V was sent" is all it
could observe. On 2026-08-15 that put a dictation into
`OwnerRestController.java`; the backend hot-compiled it and the endpoint
answered 500 until somebody read the file. All four now land in the bound tab,
re-verified on both editors with `Editor.java` byte-identical afterwards.

**This is the Chrome extension's argument run again** — from outside a window
you cannot address what is inside it; from inside, the API is right there — with
the direction reversed. Chrome *reports* picks, so the relay listens; here the
relay *pushes*, so the editor listens.

- **The focused window is what disambiguates.** Two VS Code windows are two
  extension hosts and two listeners. `/ping` answers `focused`, and the relay
  takes the one that says yes; with a single candidate it is believed without
  the flag, since ⌘⌃B can land a beat before the answer settles. Matching on the
  process tree was the alternative and is worse: it identifies the
  *application*, which is exactly the granularity that was never the problem.
- **A per-run secret gates it**, unlike the Chrome endpoint. That one hands over
  a CSS selector; this one types a line into a shell and presses Return.
- **VS Code targets are now guarded.** `/bind` returns the shell's pid, the
  relay resolves a tty from it and runs the same `foregroundIsShell` test it
  runs on a Terminal.app tab — verified refusing `rm -rf build` with zsh at the
  prompt. **IntelliJ's are not yet**: the reworked terminal does not hand back a
  process through `ttyConnector`, so `shellPID` comes back nil there.
- **No pid means unguarded, not refused.** Fail-closed is right for a tty target;
  here it would trade an announced weakness for a feature that does nothing,
  since every IDE target was unguarded before this existed. `isGuarded` is false
  and the bind flash says `— no shell guard`.
- **`.keystroke` survives as the fallback** for a known editor with no extension
  answering, and is logged as such.
- **VS Code's window is found through the window server, not Accessibility.**
  Electron builds its AX tree lazily, so `kAXFocusedWindow` answers
  `cannotComplete` (-25204, measured) for every VS Code window while IntelliJ
  answers it fine — and the visible consequence was that binding a VS Code
  terminal skipped the **bind flight**: no source rectangle, so the one gesture
  that says *that window is now this chip* silently did not happen there.
  `CGWindowListCopyWindowInfo` answers it instead. The documented alternative,
  setting `AXManualAccessibility` on the app, is deliberately not used: VS Code
  answers it by switching the editor into screen-reader mode.
- **The Return is `\r`, written separately, and both halves matter.** Both
  extensions used to let the editor's own API append the newline —
  `sendText(line, true)`, `sendCommandToExecute(line)` — and both append `\n` on
  macOS. In a TUI in raw mode `\n` is not Enter: it is *insert a newline*, the
  convention Claude Code uses for a multi-line prompt. So the dictation landed in
  the prompt and sat there until Victor pressed Return himself (reported
  2026-08-26, in VS Code). The tty paths never had this — tmux's `send-keys
  Enter` and Terminal.app's `do script` press a real Return. Each extension now
  writes the text, then writes `\r` 120ms later, the second half being the same
  reason tmux has always been two calls: a TUI that reads `text\r` in one chunk
  takes the whole thing for a paste and keeps the Return as text.
- **The IDE branch also used to send `text` where every other branch sends
  `line`**, i.e. the unflattened message — so the one path that could not survive
  an embedded newline was the one path that did not strip them.

### Only terminals get bound

`bind` used to send **every** non-Terminal app down the paste path — there was
no whitelist at all — so ⌘⌃B pressed while looking at Chrome bound Chrome and
typed the next dictation into whatever field held the caret. Proven, with the
screen locked, by binding `loginwindow`. Anything that is neither Terminal.app
nor an editor `IDEBridge` recognises is now refused outright.

### The handle is never a window

`TerminalBinding.Handle` has three cases and all three are things the terminal
can be asked to re-resolve, because a window reference is stale by the second
dictation (tabs get dragged between windows, Spaces move, order changes):

| case | address | how it delivers | guarded? |
|---|---|---|---|
| `.terminalApp` | the **tty** | `do script … in <tab with that tty>` | yes |
| `.tmux` | the **`%pane`** | `send-keys -l` then `Enter` | yes |
| `.keystroke` | the **pid** | clipboard → activate → ⌘V → Return → focus back | **no** |

The first two **do not touch focus at all** — verified against a raw-mode reader,
which is the shape a TUI actually has, with the target window behind others. Only
`.keystroke` has to bring the app forward, for ~200ms, and it puts the focus and
the clipboard back afterwards. It exists because VS Code and IntelliJ host their
terminal inside a window nothing outside the app can address.

### The shell guard is the load-bearing part

Before **every** delivery, not once at bind: if the foreground process group on
the target is a shell, nothing is sent. Victor hits Escape or the agent exits and
the tab goes back to being a prompt with the binding still pointing at it — and
at a prompt a dictation is not typed at an agent, it is **run**. "Șterge tot ce e
în folderul de build" said out loud is a real `rm`.

It is a **shell** test, not an "is this Claude Code" test, deliberately. What
makes a delivery dangerous is precisely and only that a shell is reading the
line; `claude`, `node`, an editor, a REPL all merely receive text on stdin, which
is the intended behaviour. Naming the agent would also mean guessing how it
appears in `ps`, and guessing again every release. It fails **closed**: a target
that cannot be interrogated counts as a shell.

`.keystroke` targets cannot be guarded at all — nothing outside VS Code or
IntelliJ can say which pane owns the caret, let alone what runs in it. The chip
does not distinguish them (every bound target is 📍); the bind flash says
`— no shell guard` and `GET /target` carries `guarded`, which is where the fact
can still change what Victor does about it.

### tmux: `display-message -c` does not refuse

Handed a tty attached to nothing, `tmux display-message -c <tty>` silently falls
back to tmux's own current client and answers with **that** pane. So a plain
Terminal tab bound to whichever pane a detached background session happened to
have focused — which is exactly what happened the first time this ran on a Mac
with `claude-rc` alive. `tmuxPane` therefore checks `list-clients` first. A wrong
pane is the worst failure available here: indistinguishable from a correct bind
until a sentence lands in somebody else's window.

### One line, always

Whatever carries the text ends with a Return, so an embedded newline is not
formatting — it is an early submit that sends half the sentence and leaves the
rest to arrive as a prompt of its own. `AppDelegate.terminalLine` flattens
everything into one line and the shots travel as **paths, not a `📸 ×2` count**:
the panel's preview is written for Victor, who needs only to know they landed,
while this is written for an agent, which can do nothing with a number and
everything with something to `Read`. `[selected: …]`, `[look at: …]`,
`[context: …]`, `[pointed at: …]` are the same split the outbox makes in keys,
said in one line — and they are what replaces the skill, which is no longer there
to explain what a field called `screen` is for.

**And `[this text was dictated in RO or EN]`, which is the one clause that
changes how the rest is read rather than adding something to read.** A transcript arrives
looking exactly like something Victor typed, so a mis-heard word reads as a word
he chose. Measured on his own corpus, the recogniser turned `Wispr Relay` —
what this app was called then — into
`risparerile ei`; an agent that does not know the input came through a
microphone has no reason to sound that out, and one that does resolves it at
once.
`dictation` only — inviting phonetic guessing at a screenshot's caption or a
typed message would be inviting it to misread them.

**The languages are named because they are half the answer**, and they are
named as a **fixed pair** rather than as the one the recogniser detected. Victor
dictates in Romanian and in English, and the phonetics that recover a mis-heard
word are the phonetics of the language it was said in — so *which two* to sound
a word out in is worth saying, and `RO` also explains a Romanian sentence
carrying English technical terms verbatim, which is how he actually speaks.

For one commit the clause carried the detected code (MLX Whisper reports it in
its JSON). It was taken out because the code is not reliable enough to assert: a
sentence of Victor's plain Romanian came back labelled `en` in the very recording
used to test it. A clause naming the wrong language
is worse than one naming neither — it aims the phonetics at a language the words
were never said in. Both, always, is true on every dictation.

**The advice that used to follow it is gone**, on Victor's instruction — *"skip
the rest of details - are obvious"*. It read `[dictated aloud — if a word makes
no sense, it was mis-heard: try what it sounds like]`, and a reader capable of
acting on that does not need it spelled out on every single dictation.

### The bind flight

Binding takes a **picture of the window it just captured**, lays it exactly over
that window, then shrinks it and flies it to the cursor over 1s, arriving under
it at the chip's size and fading out (`BindFlight.swift`).

⌘⌃B is pressed while looking at a terminal and answered by a chip that lives next
to the *cursor* — two places, with nothing connecting them. A blink over the
window would confirm the capture and leave the chip unexplained; a blink at the
cursor would confirm the chip and never say which window. **The travel is the
sentence**: that window is now this chip.

- **It carries the window's pixels, not a chenar round them** — since
  2026-08-28. An outline says "something here"; the picture says *which*, and two
  terminals side by side are the case where that is the whole question. It also
  makes the sentence literal: what lands under the cursor is the window, so the
  chip left sitting there is visibly what the window became. Grabbed with
  `CGWindowListCreateImage` on the **screen rectangle**, not on a window id:
  what has to be recognisable is what he was looking at when he pressed,
  overlapping windows included, and the binding does not keep a window id anyway.
  Not `screencapture`, which everything else here uses — a subprocess waited on
  is ~200ms, a fifth of the flight, spent before the first frame. Falls back to
  the old hollow rectangle if the grab returns nothing.
- **White, not blue, and not a signal colour.** Victor Addons flashes yellow for
  "I captured this", `CaptureFlash` flashes red for "it went to the agent" —
  both *announce an event*. This one **moves a thing**, and the thing now carries
  its own colours; white frames it without claiming a third meaning, and it is
  the colour of the chip it flies into.
- **Solid first, half on arrival.** Opacity falls 100% → 50% as it shrinks, and
  the first number is the one that matters: at full opacity, lying exactly over
  the window it was copied from, the picture is **invisible** — pixel for pixel
  what is already there — so the flight starts as the window itself coming loose
  rather than as a copy fading up on top of it. It briefly ran the other way
  (20% → 50%, on the old reasoning that anything solid over a terminal hides it
  mid-workshop); that reasoning does not survive the picture, because a picture of
  the window hides nothing of the window, and what it bought was a washed-out
  start at the one moment the seam has to be invisible. It ends at half because by
  then it is a small rectangle on unrelated desktop, where arriving opaque reads
  as a real window sitting there rather than as a token going into the chip. The
  white border is the one thing visible at the start, and carries "this window"
  on its own.
- **1s, halved from 2s** on 2026-08-28. Two seconds is how long a flight has to
  be to be *studied*, and this one is not studied twice — after the gesture is
  learned it is a receipt glanced at, and a receipt that outstays the glance is
  in the way.
- **The first eighth is spent standing still**, at full size. Without it the
  rectangle is already shrinking by the time the eye arrives, and the question it
  exists to answer is asked of a shape that has stopped covering the answer.
- **The cursor is re-read every frame**, not sampled once, so it chases a hand
  that keeps moving instead of arriving where the hand used to be.
- **One panel per screen, and that is the only thing that works.** It was written
  as a single panel spanning the union of every display — the obvious shape for
  something that must cross them — and it played on exactly one screen. Two
  rounds of diagnosis went past the real cause. `constrainFrameRect` genuinely
  *was* clamping the frame (AppKit pulls windows back onto a display and below
  the menu bar; `RelayPanel` overrides that away and the plain `NSPanel` here had
  never inherited the fix) — and with that fixed the geometry was provably right,
  the panel measuring `-1920,0 5568×2197` and the layer landing exactly on the
  source window, and it *still* drew on one screen.

  The cause is `com.apple.spaces spans-displays`, unset on Victor's Mac and unset
  by default on macOS: **each display has its own Space, so the window server
  gives a window to one display and no window spans two.** `canJoinAllSpaces`
  does not buy it back — that is Spaces *on* a display, not spanning displays.
  Hence one panel per screen, each drawing the same global rectangle in its own
  coordinates, which is the shape `CaptureFlash` already had for the same reason.

  Verified by burst-capturing a non-primary display through a whole flight:
  strong-blue pixels went 178 → 3070 the frame the rectangle arrived — measured
  when the shape was blue, and the multi-screen wiring it proved is unchanged.
- **The rectangle hands over to the chip.** The label appears beside the cursor
  the instant the rectangle gets there (`BindFlight.fly(from:landed:)`), so the
  two are one gesture rather than two announcements: the shape that lands
  *becomes* the thing now sitting under his hand. The bind flash is sized to
  `BindFlight.duration` for the same reason — a flash is a *panel*, and a panel
  is not the chip, so an overlay still showing one in the corner has nowhere to
  put a label beside the pointer. Ending them together is what leaves the cursor
  free at the exact moment of arrival.

  `landed` never fires on cancel, which is what a replacing bind does: the old
  answer must not land on top of the new one.

**The source frame is the one piece of geometry here that can be silently
wrong.** AppleScript's `bounds` and the Accessibility API both measure y
**downward from the top of the primary display**; Cocoa measures it upward from
that display's bottom (`cocoaRect`). They agree only on the primary screen, so a
mistake stays invisible until a second monitor is plugged in. Verified against a
Terminal window set to a known `{200, 150, 1000, 700}` on a multi-monitor desk:
`200,417 800×550` with a primary 1117 tall.

### What the chip says when bound: one row, and the destination app's own icon

```
[VSCode icon] petclinic@test-pr          ← which app, and which session inside it
```

`🤖 folder@branch` becomes that. It was two rows until 2026-08-26 — a drawn pin
plus the agent's own title (`✳ extracting the tax calculation`), and a drawn
folder plus `petclinic@test-pr` under it — and the collapse to one line was
Victor's call, made in three steps in a single sitting: three rows, then two,
then this.

**The icon is the half that carries the most and costs the least.** The pin only
ever said *bound*, which the presence of a folder name says by itself; which of
Terminal, Visual Code and IntelliJ is receiving the words is the fact that
actually differs between two bindings, and it is the difference between a
delivery that can be refused at a shell prompt and one pasted blind. Drawn as the
application's real icon (`AppDelegate.appIcon`, asked of the bundle on disk
rather than of the running app, whose `icon` is lazily loaded and often nil), it
takes exactly the space the pin was taking and is read without being read.

**The agent's self-title is what was given up for it.** It moved while the
session worked, which made it the one part of the chip that proved the session
was alive — but it is also the part with no length anybody controls, and this
line rides beside the cursor over whatever Victor is reading. The liveness it
provided is still there in the pulsing 🔴 one row down.

**The folder is the folder name and nothing else** — no parents, and never
truncated with an ellipsis. `label(forDirectory:)` takes `lastPathComponent` and
appends `@branch` when the directory is a repo. It is also now **re-read on the
poll** (`refreshBinding`), not read once at bind: as the only line, it has to be
the current answer, and Victor `cd`s between repos inside one session all day.

**The IDE path used to show a raw path here**, which is how the row came to read
`/` for a shell sitting at the root — it was the one target whose folder skipped
`label(forDirectory:)`. Fixed at the same time.

Four further decisions behind where that folder comes from:

- **The label is the bound session's, not the launch directory's — and those are
  two different things.** Claude Code keeps a *session* directory that moves when
  Victor moves, and a *process* directory that never leaves where it was
  launched. `lsof -d cwd` gives the second: measured on a live session working in
  `walkie-talkie`, it still answered `~/workspace`, which is also why the branch was
  missing (`~/workspace` is not a repo).

  So the session directory is **published rather than inferred**. Victor's status
  line already receives it from Claude Code and writes it to
  `~/.claude/cwd/<ttysNNN>`; `publishedDirectory(forTTY:)` reads it, and the
  process directory stays as the fallback for a terminal running something else.

  **The tty is the key because it is the only handle both sides hold.**
  `TERM_SESSION_ID` was the obvious cheaper choice and is unusable: macOS shows a
  process's environment only to its own descendants, so the relay — launched
  separately by ⌘⌃B — reads nothing back (measured: 2926 bytes of environment for
  a process in the caller's ancestry, 4 for an unrelated terminal's). The status
  line publishes under its **parent's** tty, since Claude Code spawns it with no
  controlling terminal of its own but keeps one itself.

  A stale entry is harmless: tty numbers are reused by the next tab, so the read
  checks the directory still exists before believing it.
- **The working directory gets a row of its own.** It rode on the title after a
  `·` for an afternoon, which put two different kinds of answer on one line and
  made the chip as wide as both together — beside the cursor, over Victor's work.
  Split, each row is short and the eye takes the one it came for. The row is
  **absent** for targets with no tty to read a directory from (VS Code,
  IntelliJ), rather than showing an app's name beside a folder icon;
  `Target.folder` is nil there and `folderText` returns nothing.
- **The title row carries what the agent calls itself** — Terminal.app's
  `custom title` (where the OSC escape lands) or tmux's `#{pane_title}`, and for
  IDE targets the AX window title, which is the closest thing to a working
  directory those have (both IDEs put the project first; guessing at the app's
  child shells would put a confidently wrong repo on the chip). It rides the
  existing 10s branch timer — same question, two sources — and is truncated from
  the **head** (`fitHead`), the opposite of a selector, because a title puts its
  subject first. With no title, the row falls back to the address: `ttys004`
  distinguishes two sessions where a repeated folder name would not.
- **The glyphs are drawn, not typed** (`Glyphs.swift`), and both replace an
  emoji Victor rejected by name. 📍 is `ROUND PUSHPIN` — Apple draws a pin stuck
  in at an angle, not the teardrop marker everyone means by a pin on a map — and
  📁 is whatever the installed font feels like. They are traced from references
  he supplied, by proportion: the pin's head is tangent to the top with radius
  `0.348 × height` and its sides are the **tangents** from the tip (a triangle
  merely touching a circle shows its corners), its hole punched with `.clear` so
  the chip's backdrop shows through rather than a white disc appearing on a dark
  terminal; the folder is `1.25 ×` as wide as it is tall with the tab's diagonal
  at `0.44 × width`.

  **They are images in boxes of their own**, and the title joins the
  row-with-a-glyph pattern the ⌘-pick row already uses. Both images are rasterised
  **once** (`pinGlyph`, `folderGlyphImage`): the chip relayouts as it follows the
  cursor, and redrawing a shape sixty times a second for a picture that never
  changes is work for nothing.

  **The old note here said an inline drawn glyph was impossible. It is not** —
  measured 2026-08-29, by putting an `NSTextAttachment` into a fresh
  `NSTextField(labelWithString:)` and reading the pixels back: the drawing and the
  text beside it both render. The "everything but the emoji comes out transparent"
  failure is the **title** label's, which carries a shadow/halo (`refreshChrome`),
  and `applyTitleText` is where that warning belongs — it is not a property of
  these labels in general. `shotHintText` had been mixing emoji and text in one of
  them the whole time. `RelayWindow.inline(_:font:)` is the helper; the rows that
  need a glyph *between* words use it, and the rows whose glyph is what the row is
  *about* still put it in the icon column.

**🤖 is still what unbound looks like** in the menu bar, and the glyph replaces
it rather than decorating it: 🤖 used to mean "this overlay is writing an outbox
somebody is watching", and bound that is no longer what happens. Since *Unbound
is inert* it means less than that — the app is running, and that is all.

The flashes carry **no pin at all** — `→ petclinic@main · ttys004` at bind,
`unbound — nothing is relayed now` at release. They are text rows, so the only pin
available to them is the pushpin emoji the drawn one exists to avoid.

### ⌘⌃B again on the same target lets go of it — the chord does not

The key had no off. Starting the relay is a keystroke and stopping it was a trip
to the menu bar — and the menu bar is a moving target precisely when the reason
to stop is that Victor is already somewhere else. So a bind that resolves to the
target **already bound** releases it instead of re-pointing at it, which also
makes the off switch reachable without aiming: whatever app is in front, two
quick presses bind it and then let it go.

- **Compared by handle, not by app.** Two tabs of Terminal are two ttys, so
  pressing in a different tab re-points rather than stops. What is bound is a
  session, not an application.
- **The left-plus-wheel chord is exempt**, since 2026-09-01 — see *The wheel is
  the relay's* for why. `bindFrontmostTerminal(toggle:)` carries the difference;
  ⌘⌃B and `POST /bind` keep the toggle, the chord does not.
- **It unbinds; it does not quit** — since 2026-08-28. It quit until then, and
  the argument was that ⌘⌃B is what *starts* the relay, so an off switch leaving
  the process running would not be the opposite of the gesture that made one.
  That argument died with the two changes underneath it: the app **starts at
  login** now and is up all day regardless (*⌘⌃D is this app's own key*), and
  *unbound is inert* made an idle relay free — it touches no dictation at all. So
  quitting stopped undoing a launch and started undoing a binding **plus a login
  item**, and the second half had to be put back by hand before the key worked
  again. It now calls the same `unbindTerminal` that `POST /unbind` and the
  menu's **Disconnect** call, so all three routes out of a binding land in one
  state.
- **No `session_end` goes out on this any more**, precisely because it is the
  Disconnect route and not the Quit route. An agent watching the outbox is left
  waiting rather than told to stop — which is the correct reading now: the relay
  is still there and a second ⌘⌃B can point it back at that terminal, whereas a
  `session_end` says the overlay is gone. Quitting (✕, menu **Quit**) still
  announces itself.
- **Autorepeat is swallowed** in this app's tap (`HotkeyTap`). With two presses meaning
  "stop", a key held a moment too long would otherwise bind and immediately end
  the session it had just started — the one input mistake this gesture cannot
  afford.

Verified across all three cases: bind, re-point to a second tab (the first tab is
let go), press again on that tab (nothing bound, app still running).

### The loopback control surface

`ElementPicker` is no longer only Chrome's mailbox — it is the relay's loopback
control surface, on the same 8917–8919. A second listener would need a second
port scheme for a caller to guess between, and buys nothing.

| route | what it does |
|---|---|
| `POST /bind` | bind the frontmost terminal; 409 if there is nothing bindable. Called on the terminal already bound it **unbinds** instead, answering `{"unbound": true}` |
| `POST /unbind` | stop — the relay goes inert (see *Unbound is inert*) |
| `GET /target` | the current binding, read-only |
| `POST /test/dictation` | `{"text": "…"}` — a fabricated transcript, entering exactly where a real one does |
| `POST /test/spawn` | the same for ⌘ + the wheel — opens the window and starts the session |
| `POST /test/replace-wispr` | `{"on": true}` — the mode behind the forward button, otherwise reachable only from the menu |
| `POST /test/dictation/start` | open a dictation without talking, so shot offsets have a zero to count from |
| `GET /engine` | which model is loaded, and whether it is ready |

`/bind`, `/unbind` and `/target` are **not gated on `dictating`**, unlike `/ping`
and `/pick`: pointing the relay at a terminal is something Victor does at rest,
and a bind that only worked mid-sentence would be one he could never make.

`/test/dictation` exists because everything downstream of the microphone — the held
prompt, the countdown, the outbox line, the delivery — was otherwise reachable
only by talking into a microphone, which made the one part of this app that types
into a live session the one part nobody could test at a desk.

### ⌘⌃B binds, ⌘⌃D dictates (since 2026-09-01)

The two global keys this app owns, on the letters they spell:

| key | call | note |
|---|---|---|
| **⌘⌃B** | `onBindHotkey` → `bindFrontmostTerminal` | was ⌘⌃D until 2026-09-01 |
| **⌘⌃D** | `onLocalToggle` → `toggleLocalRecording` | new — the wheel's click, from the keyboard |

⌘⌃D was the bind key from the day Addons handed it over (see the section below,
which is about that handover and still says D throughout — it was true then).
Moving bind to **B** freed the letter that actually spells *dictate*, and
dictation had until then no keyboard route at all: it was the mouse wheel or
nothing, on one specific mouse.

Both are swallowed unconditionally, autorepeat included — a held ⌘⌃D would open
the microphone and shut it again on the next repeat, the same mistake the bind
branch has always guarded against. ⌘⌃D is **ungated**: `startLocalRecording`
already refuses without `hasDestination`, so a press with nothing bound costs
nothing, and a key that sometimes falls through to macOS's "look up in
dictionary" would be worse than one that never does. ⌘⌃⌥D is still Victor
Addons' dark-mode toggle, told apart by ⌥ alone.

Both ride the menu as real key equivalents (`StatusItem`): ⌘⌃B on **Connect
Window**, ⌘⌃D on **Start Dictation** *and* **End Dictation** — only one of the
two rows is ever enabled, so the shared key reads as the toggle it is.

### ⌘⌃D is this app's own key (since 2026-08-26)

`HotkeyTap.onBindHotkey` → `AppDelegate.bindFrontmostTerminal`, the same call the
loopback `POST /bind` makes.

It lived in **Victor Addons** (`WalkieTalkieBinder.swift`) until then, and the
reason was real at the time: the relay was started per session and was down most
of the time, while Addons is a login item, so a cold press had to *launch* the
relay (`open -g`) before it could ask it to bind. That whole apparatus is gone
now that this app **starts at login itself** (`AppDelegate.startAtLogin`,
`SMAppService.mainApp`) — an app that is already running does not need another
app to launch it, and a key served by the process it acts on cannot go stale
against it.

Nothing about ⌘⌃D remains in Addons: no binder, no banner, no hotkey branch. The
cheat sheet still lists the key, display-only — the sheet answers "what does this
combination do on **this Mac**", which a key owned by another app still answers.

It is still the **only** owner: two taps claiming ⌘⌃D would both fire on one
press. Autorepeat is swallowed here now (a held key would bind and then
immediately stop the session it started). NB it shadows the system-wide ⌘⌃D
"look up in dictionary".

Binding takes the **first port that answers**, not all of them the way the Chrome
extension does: pointing every relay on the machine at one terminal would mean
every dictation arriving there two or three times.

## The rename, and the two places the old name survives

The app was `wispr-relay` until 2026-08-26 — folder, repo, Swift target, `.app`
and home folder all say `walkie-talkie` now. The dictation app it was named after
is gone from the code entirely since 2026-08-29 (see *The recogniser*): no
database read, no recording watch, no fallback, no swallowed paste.

Two strings deliberately still say the old name:

- **The bundle id, `ro.victorrentea.wispr-relay`** — and with it the Caches path
  and the dispatch-queue labels, which follow it. macOS keys Accessibility,
  Screen Recording and the microphone to that string plus the signing identity;
  changing it costs three grants re-ticked by hand in System Settings, on an app
  whose whole job is to be running before Victor starts talking. It is invisible
  everywhere he looks. `build-app.sh` says so beside the line, because it is
  exactly the kind of inconsistency a later reader would tidy up.
- **One quoted mis-transcription** in the notes above `dictatedHint`, where the
  recogniser turned `Wispr Relay` into `risparerile ei`. That is evidence about
  what a recogniser did to a word, not a name to keep current.

**`~/.wispr-relay` is merged into `~/.walkie-talkie` on the first launch**
(`Outbox.adoptLegacyHome`), because it holds the voice corpus — 300 MB of
Victor's own speech paired with transcripts, and the one thing here that cannot
be regenerated at any price.

It is a **merge, not a rename**, and that was not a hypothetical: the VS Code
extension publishes its listener into `~/.walkie-talkie/ide/` and creates the
folder doing so, and the skill's `install.sh` does the same with `mkdir -p` —
both before the first renamed relay ever runs. A rename-if-absent would have
skipped itself forever and left the corpus under a name nothing reads. So each
entry moves only when the destination has none of that name, directories present
on both sides are merged one level down, and nothing is overwritten. A `--home`
override skips the whole thing, checked rather than assumed: without that guard a
test instance would drag the real corpus into a scratch directory.

`IDEBridge` reads **both** registries for the same transitional reason — an
extension host keeps running the code loaded when its window opened, and a window
not yet reloaded would otherwise fall back to a blind paste.

## Scope: dictation helper only

There is **no text entry** and **no selection shortcut**. Both existed and were
deliberately removed — everything except "one more shot" now happens by itself
when a dictation opens, and that one is reachable without the keyboard at
all (see *Mouse 4 is the shutter*). Do not reintroduce a typing affordance:
the panel's `canBecomeKey` is false precisely so the overlay can never steal the
caret from the app Victor is working in.

**The terminal binding does not contradict this**, though it looks like it might.
This rule is about the overlay's own surface — there is nothing to type *into*,
and the panel never takes the caret. Delivering a dictation into a bound terminal
is the opposite gesture: it puts words somewhere else without the overlay ever
becoming key. `.keystroke` targets are the one place focus moves at all, and it
moves to the target and straight back.

## Unbound is inert

**With no terminal bound, the app does nothing at all.** No dictation can be
started, no picture is taken, no mouse button is borrowed, no line is written.
Since 2026-08-27, `AppDelegate.isBound` (`terminal.target != nil`) gates every
path that could deliver, plus `syncLocalCapture`, which is what lets the wheel open
the microphone.

**One gesture is outside it, since 2026-08-30**: ⌘ + the wheel starts a dictation
whose destination is a terminal that does not exist yet (*⌘ + the wheel: the
destination that does not exist yet*). The four gates below now ask
`hasDestination` — `isBound || spawnPending || pasteMode` (the third since
2026-09-02, see *Replace Wispr*) — because the reason for the rule is
that there is nowhere for these words to go, and a spawn is a yes to that
question, just not yet. `syncLocalCapture` is deliberately **not** widened: the
bare wheel's claim on the microphone still needs a binding, and the shifted press
bypasses that flag in the tap rather than pretending to set it.

| gate | unbound |
|---|---|
| `captureContext` — flash, selection probe, screen capture | off |
| `plusOneShot` — F3 / mouse 4 | off |
| `send` — the outbox line and the delivery | off |
| `syncBorrowedGestures` — mouse 4, ⌘⇧-click in Chrome | off |
| `syncLocalCapture` — the wheel's claim on the microphone | off |
| `corpus.captureLocal` | **on** |

**It is the only such gate now.** Pause used to bail out of the same four places
and is gone (*Pause is gone*, below).

Why it had to change. The relay used to be started per session by `/relay` and
live only as long as Victor was dictating at an agent, so "running" and "aimed at
something" were the same fact and none of this could misfire. Since 2026-08-26 it
is a **login item** and sits there all day — so every sentence he spoke into a
browser, a chat or a commit message was getting a screenshot taken of it and was
losing him mouse 4 and ⌘⇧-click, with nowhere for the words to go. Pause existed
to stop exactly that, and he was having to press it against an app that had no
destination anyway — which is why, once this rule was in, pause had nothing left
to do and went (*Pause is gone*).

**The outbox goes quiet too, and that is a deliberate loss.** The `/relay` skill's
original mode was an unbound relay appending to a queue with an agent watching
it; that mode is gone. Victor was asked directly on 2026-08-27 and chose the
whole switch over half of it — an outbox filled all day for a watcher that is
usually not there is not a feature, it is a log of his private dictation. A
`/relay` session gets its destination the way everything else does now, by
binding.

**The corpus is the one thing that keeps running**: it is a file on Victor's own
disk, the samples are what the local model is being judged on, and one dropped
because he happened to be dictating into a browser cannot be taken again.

**`showBound` is where the switch is thrown**, since it is the one place every
route into and out of a binding passes through — ⌘⌃B, `POST /unbind`, and a
target discovered gone at delivery time (`report(.targetGone)`). That last one is
why it lives there and not in the two callers: a relay whose terminal was closed
under it must hand the wheel and the microphone back at that moment, not at the
next deliberate gesture.

**`/test/dictation` is gated too**, which makes it useless at a desk with nothing
bound — and is why the spawn needed a route of its own, for the one gesture
defined by not needing a binding. That is the right reading of a route whose
whole claim is that it enters exactly where a real transcript does — bind something first, which is what the
path under test needs anyway.

## Pause is gone

**Since 2026-09-01 there is no pause.** Not the menu row, not the chip click that
toggled it, not the ⏸️ badge on the menu bar item or in front of the chip's
folder, not the 0.30 opacity state, and not the `paused` flag any of them were
about. Victor's call, in one line: *"nu mai vreau să am conceptul de pauză"*.

It was written when the relay was aimed at nothing in particular and running all
day, and *Unbound is inert* took its job away — an unbound relay already touches
no dictation, borrows no button and writes no line, which is everything pause
did. What was left was a second switch for a state the app reaches on its own,
and two ways to say "stop relaying" is one question the menu should not have been
asking. Disconnect is the answer when there is a binding to let go of; nothing is
the answer when there is not.

**Do not reintroduce it.** If a "hand the mouse back for a minute" gesture is ever
wanted again, it is Disconnect — which already exists, is reachable from the
right-held chord and the menu, and says *which* terminal it let go of.

A click on the chip is therefore no longer a control: at rest it does nothing.
That was the only thing pause could be toggled with beside the menu, and a
control that rides the pointer and moves away as you reach for it was never one —
the same argument that has always kept the ✕ off the chip.

## Title states

Titles are `<emoji> <label>: <state>`, where the label is `folder@branch` of the
directory the overlay was launched in — the same thing Claude Code's status line
shows, e.g. `ai@master`. It said "Agent" until two overlays could exist at once;
with two sessions on screen, identical titles hide the only fact that matters,
which is *which repo* is about to receive what he says. `SessionLabel` derives it
from the working directory (inherited from the session, since `/relay` launches
`start.sh` inside it), re-reads the branch every 10s, and yields to `--label`.

| state | label |
|---|---|
| idle **and unbound** | **nothing at all — no window on screen.** See *The pointer is clean when nothing is bound* |
| idle, bound | the destination app's icon + `petclinic@main` — no state word: "standing by" is what he can already infer from nothing happening |
| dictating | `🤖 ai@master`, unchanged, **plus the recording row below it** |
| bound to a terminal | the destination app's icon + `petclinic@main`; the 🤖 is *replaced*. See *What the chip says when bound* |
| bound to an app with no readable directory (a blind-paste target) | the icon + the app's own name — the one case where the icon has no subject beside it |
| the dictation was cancelled | `dictation cancelled` in the row `Listening…` was in, **bare and glyphless** — 1.5 s, then half a second of dissolve back to the chip at rest |
| dictating in Replace Wispr | the destination app's icon + `⌨️ at the caret` — the same slot a spawn takes, and for the same reason |

**Dictating no longer has a title of its own.** It used to be `🎙️ …` with dots
cycling 1→2→3→1, and there was a glass-shine sweep every 5s to go with it. All of
that has moved into the recording row: the top line now stays `🤖 folder@branch`
through the whole dictation — that is the fact that does not change — and what
does change lives one row down.

The liveness those animations provided is still load-bearing, and is now the
pulsing 🔴: a frozen recording row is indistinguishable from a hung app, and the
entire point of the state is reassurance that speech is being captured.

## The recording rows

While dictating, three rows sit directly under the title, one glyph column and
one text column:

```
🤖 ai@master
🔴 whisper-large-v3-turbo           ← something is listening, and this is what
📸 2 — mouse/F3 for more shots      ← what the message is carrying
[chrome] — ⌘⇧+click to select element
```

It was one row (`🔴 📸 ×2 🖱️/F3`) until 2026-08-26, packed as tight as it would
go on the argument that every character costs width over the work underneath.
Two things made it three rows. The 🔴 acquired a second meaning the moment the
relay grew a microphone of its own — *recording* was no longer the whole story,
because **which recogniser** is now a live question — and a pulse cannot carry a
name. And once one row spelled something out, the abbreviations beside it read as
a different kind of thing rather than as a list.

**The glyphs share one column** (`glyphBox`, a fixed 17pt square) so the text
starts at the same x on every row. Measured per row — an emoji, a second emoji
and a bitmap are three different widths — they lined up with nothing, which is
what makes three rows read as three unrelated lines instead of one thing being
assembled.

**Fixed, and centred in it, since 2026-08-26.** The column used to be the widest
of the four glyphs, each measured its own way: the emoji asked of the font, the
icons asked of the image. That aligns the boxes and nothing else — an emoji's
ink is narrower than its advance and sits a bearing in from the left, an app
icon fills its box corner to corner, and the map pin is 0.7 as wide as it is
tall. Victor read the result exactly as it was: *"iconurile nu sunt
left-aliniate si au dimensiuni diferite"*. Every glyph is now fitted into the
same square — images scaled proportionally, both emoji at 15pt — and centred in
it. Centring is what makes them *look* left-aligned: with equal boxes and
unequal ink, flush-left puts the narrow glyph's ink where the wide one's bearing
is.

**Both halves of a row are centred on the row's midline** (`centre(_:…)`), which
fixed two things at once. The glyph box was 15pt tall at y=1, and an emoji at
14pt needs nearly 17pt of line box — so the 🔴 was drawn as a clipped arc, the
pulse of all things ("bila rosie pulsanda e taiata jos"). And the label filled
the row, where a single-line `NSTextField` draws its text high, so the words sat
above the glyph beside them. Each now gets exactly the height its own font asks
for, placed around the middle; neither half has to know anything about the
other's font.

Rows two and three are still Victor's list, not a designer's: **how many pictures
this message is carrying, and the two ways to add another.** The count includes the automatic context capture — he took
that one by starting to talk, and a count that skipped it would disagree with
what the agent receives. It goes up live, so taking a shot needs no other receipt.

**The count says `×1` from the instant the row opens**, before `screencapture`
has returned (`AppDelegate.contextShotPending`). It used to say `×0` for the best
part of a second — a clipboard probe that sleeps up to 400ms plus a subprocess —
and then flick to `×1`; but a picture *is* being taken in that second, so zero
was simply wrong, and wrong in the one moment he looks at the row. It falls back
to zero only if the capture genuinely fails, which is the only case where zero is
the truth. `captureContext` therefore runs **before** `overlay.setListening(true)`
in `dictation.onChange`: it books the shot synchronously, and `setListening(true)`
zeroes the count, so the other order publishes a `×1` into a row about to reset it.

The inputs sit inside this row rather than in a legend of its own. They are the
only things that do anything while he talks, and they belong beside the number
they change. The mouse is named first because it is the half that needs saying:
F3 has always been there, while the back button is borrowed only for the length
of the dictation.

**The mouse is drawn here too** — the row leads with `Glyphs.mouse(pressed:
.back)` inline, its rear thumb button red, then `+ selection`. It has been through
three forms: `🖱️/F3`, then the words `— mouse/F3 for more shots`, then 🖱️ with a
🔽 kerned underneath. The last was a rebus — it needed a legend, and the legend was
the thing the row was supposed to be. A drawing of the actual button does not.

## One face, one size, one weight — everywhere on the chip

**Victor's rule, 2026-09-01:** *"toate textele care apar în tooltipul de lângă
maus trebuie să aibă aceeași mărime de font și font face"*. Every word on the
chip is `hintFont` — system 17, regular. Three rows were not, and all three are
now: the **title** (was semibold), the **selection** row (was 14, the one row
still set from the old ×1.3 table's bottom rung — its box goes 19 → 22 to match),
and the two **waits** (were a semibold 20, given to them a build earlier to make
them visible).

The chip is one card an inch from the pointer, read at a glance and never
studied. Type hierarchy is for a page with a structure to explain; here it only
made a five-row chip look like five different things.

**Emphasis on the chip is the glyph column's job.** That is what the waits keep —
see below — and it is the better half anyway: a picture is recognised rather than
read, so it costs the prose nothing.

The panel is outside the rule (`promptFont`, the quote mark, the front line): it
parks in a corner and is read whole.

## The two waits are icon-sized, and it was the colour that mattered

`preparing` (the model coming up) and `transcribing…` (the model chewing) are the
only two states in which Victor is **waiting on this app**. For two days that
bought their hourglass 30pt — `hintInk`, nearly twice the size of every other
glyph on the chip.

They were icon-sized, in `secondaryLabelColor`, on a bare chip: half-transparent
dark grey with no halo, over the dark terminals and editors the chip spends its
life on. **Exactly the bug the selection row had** — the row was there and could
not be seen — and this time it was two states where the question being asked is
*is it still doing something?*, asked from wherever he has already looked away to.

**The fix that mattered was the colour**, and it was made in the same commit:
these rows joined `refreshChrome`'s white-plus-halo list, which is the one place a
row becomes legible on a bare chip. That list is the third place a row has been
left off it.

So the height was buying nothing, and on 2026-09-02 it went back to `iconInk` on
Victor's ask — *"clepsidra este prea mare comparativ cu restul de icoane din
tooltip"* — which is half of what it was and exactly what the 🔴, the 📸 and the
destination's own icon are. `hintInk` survives for the two rows it was written
for: the drawn mice that teach the rebind chord, where the picture *is* the
sentence.

## The mouse is drawn, and the buttons the gesture presses are red

**Rule, from Victor, 2026-08-29: wherever the UI has to show the mouse, draw his
mouse — never an emoji.** `Glyphs.mouse(height:pressed:)` takes a `Buttons` option
set (`.left`, `.right`, `.wheel`, `.back`, `.forward`) and fills those regions in
`.systemRed`.

The old vocabulary was 🖱️ for the device with a second emoji kerned beside it for
which part of it to press, and it ran out the day rebinding became a **chord**: an
emoji pair cannot say *this button while that one is held*, and two red regions on
one drawing can. It was also a rebus at every size, dependent on whatever Apple
Color Emoji ships this year, and it was not his mouse.

**The silhouette is traced, not drawn by eye.** Victor supplied a wireframe
(`~/Downloads/image.png`, a line drawing of the **Logitech Signature M650 L** on
his desk — `~/.config/linearmouse/linearmouse.json` names the device). A one-off
program read the outer dark run per row off that PNG and emitted 33 normalised
`(v, left, right)` samples, which are the `mouseOutline` table; the aspect ratio
0.568 is that trace's bounding box. Two corrections, both because a min-x scan
reads *ink* and not *body*: the thumb buttons protrude past the left edge in the
drawing and came back as a notch at v 0.34…0.47, interpolated across, and the
whole column is 3-tap smoothed so the flanks are not faceted at 150pt.

The interior landmarks come off the same trace: the central island the wheel sits
in spans u 0.382…0.620, the wheel 0.456…0.548. **That island is what makes the
picture work at 16pt** — the two buttons are not halves of a blob split down the
middle, they are the areas either side of the island, so filling one red is a
shape the eye already sees the boundary of.

Two things learned by rendering it to a PNG and looking, which is the only way any
of these numbers were settled:

- **A pressed part is outlined in its own colour, not the body's.** The wheel and
  the thumb buttons are small enough that a stroke is a large fraction of the
  mark, and a grey ring round a red wheel renders at 16pt as a grey wheel.
- **The thumb buttons are drawn only when one of them is the button being named.**
  Two extra marks on every mouse in the card is texture, not information.

The wireframe is line art; the glyph is not. A 0.16-alpha wash fills the
silhouette, because the chip floats over a terminal, an editor, a photograph, and
an unfilled outline is a few grey strokes with somebody's code showing through.

**Where they appear.** Bound and idle, the chip is now **three rows** — the
folder, then one row per gesture (`statusLines`, two of `hintRows`):

```
🤖 workspace
🖱️(left) 🖱️(wheel)  ReBind
🖱️(wheel)  dictate
```

The first picture of each row rides in the icon column, under the destination's
own icon; only the second is inline. The mouse is repeated for the second press
rather than the wheel appearing on its own, because it is a button *on the same
mouse* and a bare wheel beside a mouse reads as a different object. Rebind is
first: the card is read at the moment the relay is pointed somewhere, and
dictating is the half his hand already knows.

**There is no arrow between the two.** One rode there for a build to say *then*;
at 30pt the drawings say it on their own — left-to-right already reads as an
order — and the arrow was a third object competing with the two that carry the
meaning.

**These two rows draw the mouse at 30pt, not 16** (`hintInk`), so they are 34 tall
where every other row is 22. Everywhere else a glyph is a label for a row that
says its own thing in words; here the picture *is* the sentence — which button, on
which mouse, in which order — and at icon size that sentence was a smudge with a
red pixel in it. The drawing is still narrower than the icon column (30 × 0.568 ≈
17 against a box of 20), so only the height changes and the column the
destination's icon starts in is kept. `statusLines` carries each row's ink size and
`hintRowHeight` turns it into a height, which is what lets the same two views also
render the 16pt `send` / `transcribing…` / `preparing` states at 22.

The `send` row, the shot-hint row (`.back`) and the ⌘⇧-pick hint (`.left`) use the
same drawings at icon size: those rows say what they mean in words, so the picture
only has to identify the device.

## The shutter and the ⌘⇧ pick are two gestures, and they cannot collide

They are borrowed from the same dictation and they arrive in the same message,
so it is worth writing down that nothing routes one into the other. The shutter
(mouse 4, or F3) takes a **picture plus whatever is highlighted at that moment**;
⌘⇧-click in Chrome takes a **path to a DOM element** and no picture. Neither is a
fallback for the other, and Victor asked for them to stay that way.

**The ⌘C probe cannot poison an armed pick**, which is the one interaction the
two could have had since the shutter started paying for the clipboard fallback.
`inspect.js` treats any keydown during a ⌘⇧ hold as proof the chord is a
shortcut and abandons the arm — but **both shutter routes require no modifiers
at all**: mouse 4 asks for `bare` and F3 for `!ctrl && !opt && !cmd && !shift`
(`HotkeyTap`). With ⌘⇧ held, neither fires, so there is no press that could post
a ⌘C into a hold. Do not relax either gate without re-reading this.

## Two gestures are borrowed, and only while dictating

Mouse 4 and ⌘⇧-click in Chrome both belong to other software the rest of the time,
and `syncBorrowedGestures()` is the single switch that takes them and gives them
back. The two sections below are one argument applied twice.

Since 2026-08-28 the same switch also **pauses Chrome's music** (`MusicBridge`,
below). It is not a gesture, but it is the same window and the same argument: for
the length of a sentence, something that belongs to the rest of the machine is
borrowed and then handed straight back. Since 2026-09-02 it also raises the
**corner beacon** — same switch, same window, and the reason it is that switch
and not a fourth place `listening` is written down.

**Neither gesture is borrowed in Replace Wispr** (`live && !pasteMode`). Both are
taken in order to *add to a message* — a picture, an element in a page — and that
mode has no message: there is one string and it goes where the caret is. Leaving
mouse 4 alone is also the whole of "the back button gives Enter".

## The music pauses for the length of a dictation

`MusicBridge` pushes `{type:"dictation", active, seq}` over a WebSocket on
**127.0.0.1:8920** and `chrome-extension/relay.js` pauses every audible tab,
resuming exactly those. Ported from Victor Addons' `DictationBridge` + its
`chrome-extension/`, which does the same for its own dictations — read
`victor-macos-addons/docs/audio-sounds.md` for the CoreAudio half of the story.

**Why Chrome decides which tab.** CoreAudio funnels every tab through one Chrome
audio helper process, so from outside the browser "Chrome is making sound" is the
finest grain obtainable — the tab cannot be named, let alone stopped.
`chrome.tabs.query({audible: true})` is the per-tab answer and only exists inside
the extension. Same shape as the picker's argument about the DOM.

**Why a push and not the HTTP server already there.** The extension polls
`ElementPicker` only while ⌘⇧ is held. A poll fast enough to catch the front edge
of a sentence would have to run all day for something that happens a few times an
hour; a socket the app writes to costs nothing idle and lands in the same
millisecond as the recording row. It pings every 20 s because an MV3 service
worker is torn down after ~30 s idle and socket traffic resets that timer, and it
replays the state on connect, so a worker that *was* torn down mid-dictation
comes back knowing it still owes a resume.

**8920, not 8766.** Victor Addons holds 8766 for its own bridge. Both may be
installed and both may pause, which is harmless — each extension marks what it
stopped (`data-wt-dictation-paused` here, `data-va-dictation-paused` there) and
resumes only its own marks, and an element the other already stopped is skipped
as "not playing". They cannot share a listener, so this sits just past
`ElementPicker`'s 8917–8919.

**The socket is gated on a probe, and never blindly retried.** A refused
WebSocket is a runtime error Chrome files on the extension's *Errors* page, one
entry per attempt — and with the relay started and killed per agent session,
"nothing on 8920" is the ordinary state of the world, so a plain reconnect loop
turns that page into a wall of `ERR_CONNECTION_REFUSED`. A refused `fetch` is
caught in `ask()` and stays silent, and `AppDelegate` opens the picker's HTTP
port in the same breath as the bridge (`picker.start(); music.start()`), so a
probe that answers is proof 8920 is there to connect to. The retry is a
`chrome.alarms` period of 30 s (Chrome's floor, and also the worst case between
the app coming up and the music being pausable again) rather than a
`setTimeout` chain — with no socket open nothing keeps the worker alive, and a
timer scheduled by a worker that is then torn down never fires. A ⌘⇧ hold that
finds the picker alive reconnects immediately, for free. This is why the
extension also asks for the **`alarms`** permission.

**A dead socket resumes**, which is a deliberate departure from Victor Addons.
That app runs from login and is rarely killed; the relay is started and killed
*per agent session*, so a relay that goes away mid-sentence would otherwise leave
the music off with nothing alive to turn it back on. A blip that is only a blip
costs a stutter — the reconnect replays `active:true` and pauses again.
`applicationWillTerminate` also calls `music.stop()`, so the ordinary quit says
so rather than relying on the net.

**Gated on `live`, not on `listening`.** A dictation nobody is relaying (unbound,
or unbound) is Victor talking into some other app, and silencing his
music for that would be the relay reaching outside its own session.

**The extension needs `tabs`, `scripting`, `storage` and `<all_urls>`** — new
permissions on an extension that had only `http://127.0.0.1/*`, so a **Reload** in
`chrome://extensions` is required after pulling this; the pause silently does
nothing until then.

## Mouse 4 is the shutter, but only while dictating

The back side button (`MOUSE_BUTTON_4` = 3) takes a shot, and the relay
**swallows it** so nothing else acts on it — while a dictation is running and
forwarding is on, and at no other time.

That button is Victor's Return key: LinearMouse
(`~/.config/linearmouse/linearmouse.json`) maps it to a `keyPress: ["enter"]`,
which is what he submits with all day. Borrowing it is only defensible because
of how narrow the window is — during a dictation an Enter lands in whatever
happens to have focus, which is never what he meant, and the point of the whole
overlay is that he is *away from the keyboard*. Asking him to reach for F3 to
attach a picture put the one thing he does mid-sentence back on the keyboard.

Three rules keep the theft honest:

- **Gated on `listening`**, pushed to the tap by
  `AppDelegate.syncBorrowedGestures()` from both edges that can change the answer
  (a dictation starting, a dictation ending). At rest the button
  is untouched and still types Return. That one method sets **both** borrowed
  gestures — this button and ⌘⇧-click in Chrome — from a single expression, so the
  recording row can never advertise one of them in a state where it is dead.
- **Only the bare press.** LinearMouse maps ⌘+button separately to ⌘Return, so
  any modifier passes straight through: one gesture must not quietly become two
  different things.
- **Both halves are swallowed** (`otherMouseDown` *and* `otherMouseUp`, which is
  why the tap mask grew). LinearMouse sits downstream of this tap and would
  otherwise still see an orphan release to act on.

**Tap order is what makes this work, and it is not guaranteed.** Both apps use
`.cgSessionEventTap` at `.headInsertEventTap`, where the most recently installed
tap sees events first. LinearMouse starts at login and the relay starts per
session, i.e. always later — so the relay wins. If LinearMouse is ever restarted
*after* a relay, it will convert the button to Return before this tap sees it and
the shot silently stops working; restarting the relay fixes it.

## The shot's name is *when in the sentence* and *where the mouse was*

`shot-01:23(mouse-at-1034x1466px).jpg` — taken 1m23s into the dictation, pointer
at x=1034, y=1466 in **the pixels of that image**, top-left origin like the image
(`ScreenCapture.stem` + `tagCursor`).

Both halves answer a question the sentence alone cannot. He points at things
while he talks — "this button", "that line" — and he takes several pictures
across a three-minute dictation, where `📸 ×4` is four indistinguishable files
and `0:00 · 0:38 · 1:52` is a table of contents. The prompt panel already lists
them by offset (`AppDelegate.shotLine`); the name is that same reading put where
the agent meets it. They ride in the **name** rather than in new outbox fields
because the name is already in front of the agent: the path travels in `paths`,
so both facts arrive with the picture and nothing downstream learns a new key.

**`00:00` is the automatic context shot**, by definition — he took it by starting
to talk. A shot with no dictation around it (bare F3) keeps a timestamp instead:
"elapsed since the start" of nothing is not a fact.

**The colon is legal and the Finder lies about it.** POSIX filenames on APFS take
`:` fine, and everything that handles these paths is POSIX — but the Finder
renders it as `/` (`shot-00/00(…)`), the old HFS separator swap. So a folder
Victor opens by hand reads slightly differently from what the agent sees.

**Pixels, without a denominator.** It was a percentage pair
(`-cursor-34.2x71.8pct`) because the agent reads these through a tool that
downsamples them, so a pixel stops pointing at the right thing once the picture
is resized; then briefly `-cursor-at-1034x1466-of-3024x1890`, carrying its own
denominator to answer that. Victor dropped the denominator: the name is read by
him as often as by an agent, and raw pixels are what he can check against a
screen. **The consequence is real and accepted** — a downsampled frame needs its
own dimensions read back before these numbers mean anything, which anything
looking at the image already has. Do not reintroduce the denominator without
asking.

**Measured against the file, never computed from the screen.** The size comes out
of the JPEG header after `screencapture` returns (`pixelSize(of:)`, no decode),
because multiplying the screen's frame by its backing scale is a guess: mirrored
displays, HiDPI modes and a sleeping external monitor all break it. That is why
the shot is **named provisionally and renamed afterwards** — the file has to
exist before it can be measured. A failed rename leaves the provisional name: a
shot with no pointer in its name is still a shot.

**Victor Addons is not the same reading, despite the similar words.** Its
`2026-08-14_00-34-42_at1200x500.jpg` is in **global CG points** — y down from the
primary display's top, negatives normal on a screen to its left — because it
answers "where on the desk was the pointer". This one is in **pixels of that
image**, because it answers "where in this picture do I look". Do not port either
convention onto the other.

## The agent gets an 800px copy, Victor keeps the retina frame

Every capture writes two files: `shot-00:38(mouse-at-1034x1466px).jpg` as
`screencapture` produced it, and `…-small.jpg` beside it at 800px wide. The
**small one is what travels** (`ScreenCapture.handover`, used by
`AppDelegate.shotsClause`); the original is what he opens himself.

An image costs `width × height / 750` tokens once the reading tool has fitted it
to 2000px on the long edge, so a 3456×2234 desktop always lands at ~3450 tokens
**whatever the JPEG weighs** — compressing harder buys exactly nothing. At
1000px the same desktop is ~860, and at 800px ~550.

**That this is free was measured, not assumed** (`evals/`, 39 runs of a real
agent over two real dictations replayed off the outbox). Pooled over the
seven-frame Gmail dictation where every frame has to be opened: accuracy 0.95
either way, 29,349 tokens against 48,350, cost $0.38 against $0.56. On the
"what was I pointing at" fixture the small frames produced **byte-identical
answers**, quoting `⇒in browser/sql LIMIT OFFSET` off a code editor.

**1000 was the first width tried, not the measured floor**, and it stayed for
three weeks because it came out free against retina. `evals/text-vs-pixels.md`
walked the ladder down on 2026-08-22: 33 runs, both fixtures, **6/6 clean at
800, 6/6 at 700, and no legibility failure even at 500px** — where a 3456×2234
desktop is 215 tokens and still yields all seven senders. The two cells under
1.00 failed at the shots' *sequence* and at a fixture key too narrow to accept a
correct answer, neither of them at reading.

**800 is therefore one rung above what the evidence allows**, deliberately. 700
is where the measurement points (−51% a frame instead of −36%); three repeats a
cell is thin, both fixtures now score 1.00 at every width they used to
discriminate, and Victor reads these frames too. Do not take the rest of the
saving without a harder fixture — the missing rung is the one that would find a
cliff in production instead of in `evals/`.

**The width is said in one place.** `ScreenCapture.handoverWidth` is not private
and `AppDelegate.shotsClause` interpolates it, because the shipped line tells the
agent how wide the frames are and a second literal is how that sentence comes to
disagree with the pixels.

Written through ImageIO's thumbnail path, which scales during the JPEG decode —
this sits in the capture path, and the burned-in cursor mark was removed from
there partly for costing ~100ms of exactly the decode-and-re-encode this avoids.
`prune()` counts **frames, not files**, and drops the sibling with its frame;
counting both would silently halve a cap expressed in pictures.

**One thing that was measured and deliberately not built** is the line under the
pointer: OCR at the recorded cursor, quoted in the shots clause. It held accuracy
at 1.00 and cut the agent's turns from 12 to 5 and its thinking from 3,109 output
tokens to 1,323, with one run in three answering without opening a picture at
all. It is not here because the shutter path is short and Victor chose to keep it
that way. `docs/pointer-line.md` has the numbers, the build order and the traps —
read it before either building it or re-deriving it.

### Three things that sound like improvements and are not

- **Compacting the line saves nothing.** Factoring the directory out of seven
  paths (~90 characters a frame) measured *inside the noise* — 50,320 tokens
  against 48,350, i.e. slightly worse. The compact form was kept anyway for what
  it **says**, not what it saves: that the list is chronological and that the
  context frame may be skipped. Do not go looking for tokens in the wording
  again; they are in the pixels.
- **Dropping the automatic context frame costs accuracy** (0.93 against 0.95).
  It is not a spare. He starts talking about what is *already on his screen*, so
  it is routinely **picture one of the enumeration** — in the Gmail dictation it
  is the first of the seven senders. It is offered cheaply with a hint that it
  can be skipped, never withheld.
- **A native-resolution crop at the pointer, offered beside the small frame,
  scored 0.87** — worse than the small frame alone. Not because the crop is
  unreadable: because two pictures per shot make the **sequence** harder to
  hold, and one run came back with the first two shots swapped. Sequence is what
  these messages are made of.

**Order, not timestamps.** Nothing needed wall-clock times. The name carries
where in the sentence the shot was taken and where the pointer was; the line
says the list is oldest first. That was enough for 7-item alignment at 0.95.

## Every frame says which window it came from

`WindowContext.describe()` reads the **frontmost app and its focused window
title** at the instant of each capture, and the delivered line names it beside
the file:

```
[in <dir>/ — the shots I took, oldest first, each named by what was in front of me:
 shot-00:18(…)-small.jpg = IntelliJ IDEA — OwnerController.java;
 shot-00:31(…)-small.jpg = Google Chrome — Gmail – Inbox (24,277)]
```

A screenshot arrives as a rectangle of pixels with **no provenance**: that this
is a browser, that the browser is on Gmail, that the editor behind it has
`OwnerController.java` open — all of it has to be re-derived by looking, and all
of it is already written down by the app itself. One Accessibility call replaces
several hundred tokens of looking, and answers the question the pixels answer
worst: two frames of the same IDE at the same zoom are near-identical to the eye
and are two different files.

**The three cases are one mechanism**, which is why there is only one: Chrome
puts the page title in its window title, both IDEs put the project and the open
file in theirs, and a terminal puts whatever the shell or the agent last set —
the same `custom title` the chip already reads when bound.

- **Sampled at the gesture**, never inside the capture. Same rule as the cursor
  and the offset, same reason: `screencapture` is a subprocess we wait on, and a
  title read after it returns names the window he *ended up* in front of while
  still talking about the one he photographed.
- **It goes in the line and in the outbox, not in the file name** — which is
  where the offset and the pointer live, and deliberately not where this lives.
  Those two are short machine-generated readings that survive being made into a
  filename. A window title is arbitrary text carrying `/`, quotes, colons and
  eighty characters of headline: sanitising it into a name strips exactly the
  characters that identify the page, and leaves Victor — who reads these names
  himself — with something he cannot read. The evals settled the cost side: the
  addressing is a rounding error beside the pixels, so the line has room.
- **Truncated from the head** at 80 characters (`fitHead`'s reasoning, applied
  again): a title puts its subject first.
- In the outbox it is `sources`, keyed by **base name** rather than full path —
  the folder is already in `paths` and `screen`, and repeating it as a JSON key
  would double the longest string in the line to say nothing new.
- `AXUIElementCreateApplication` + `kAXFocusedWindowAttribute` is the same read
  `TerminalBinding.focusedWindow` makes. **Duplicated on purpose**: that one is
  about binding — it resolves a target and answers with a frame to fly a
  rectangle from — and folding a screenshot's provenance into it would tie two
  unrelated features to one signature.

`NSWorkspace.frontmostApplication` is a main-thread question and every caller is
an event tap, a CoreAudio callback or an HTTP listener, so the hop is a
`main.sync` — guarded by `Thread.isMainThread`, because a deadlock in the
shutter path is not a bug anyone would enjoy finding later.

## The shutter also takes the selection

F3, or mouse 4 while dictating, records **what is highlighted at that moment**, stamped with the
offset it was taken at, beside the picture (`stashExtraSelection`). A screenshot
shows a line of code; the selection *is* the line of code, in characters
something can grep for, and until now only the first one of a dictation survived.

`pendingSelection` is **unchanged** and still means what it always meant — the
subject, frozen at the first non-empty read, never overwritten. The extras
accumulate beside it in `pendingExtraSelections`, and three cases are skipped
because each would be noise: nothing highlighted; the same text the frozen slot
already holds (he never let go of it — the common case); the same text as the
previous extra. The one exception is a dictation that opened with **nothing**
highlighted: the first thing he highlights mid-sentence fills the frozen slot
instead, because that is the subject arriving late.

**It reads the selection the same way the opening one is read** —
`SelectionCapture.read()`: Accessibility, then a synthetic ⌘C with the clipboard
snapshotted and restored. It was AX-only (`readQuiet`) until 2026-08-31, on the
reasoning that a keystroke posted into whatever app is under his hand, several
times a sentence, is a side effect the gesture never promised. The reasoning was
sound and the result was that the feature did not work **where he actually uses
it**: a highlight in a Chrome *page* is exactly the case AX cannot see, so every
shot Victor took over one filed nothing at all, silently. A shutter press is a
deliberate act with a deliberate subject; the ⌘C is a price he asked to pay, and
with nothing selected the probe is a no-op nothing notices. `readQuiet` is gone —
it had no other caller.

**The chip says `↪ selecting <his own words>` for 2.5s** and then settles to
`↪ ×N …`. **The receipt is not behind the novelty test, the filing is**: two of
the three skipped cases are presses that *did* catch a highlight — the frozen one
he never let go of, the same one shot twice — and a shutter that says nothing
there reads as one that missed, which is the failure the row exists to rule out.
The message still carries each highlight exactly once. The row was already going to carry the highlight for the rest of the
sentence, which answers *is it still there* but not the question he has at the
instant he presses — *did this catch the thing I meant?* A picture is taken
silently and a selection is read silently, so without the verb the only
confirmation the shutter grabbed the right paragraph arrived in the terminal, a
sentence too late to reselect.

**It is deliberately not a `flash(_:)`.** A flash *replaces* the chip for a
second and a half, and the receipt has to sit beside the text it is about for the
rest of the sentence — so the row that was going to carry the highlight anyway is
where it goes. (When this was written a flash was also a *panel*, thrown across
the work being photographed; that half of the argument is gone since 2026-09-02,
and the other half is enough.)

**And that row was invisible.** `refreshChrome` turns every row white with a halo
for the bare chip and `selectionLabel` was the one it never listed, so it kept
`secondaryLabelColor` — half-transparent dark grey, on a chip that spends its life
over dark terminals and editors. The highlight *was* being carried and *was* on
the row; it looked exactly like a shutter that had failed to read it. Fixed at the
same time, and it is why "the selection does not show up" and "the selection is
not captured in Chrome" were one report.

**The row is measured into the chip's width now**, clamped to 34 characters from
the **head** (`fitHead` — a highlight reads forwards, unlike a selector, whose tail
is the part that identifies it). Left out of the width it truncated to whatever
the other rows happened to make the chip, which beside a short folder name came
out as `selecting public O…`. Left unclamped it would be as wide as a file. Same
bargain the ⌘-pick row above it already strikes.

It rides the outbox as **`selections`** — `[{at: "0:31", text: …}]` — while
`selection` keeps carrying the first one, so nothing reading the queue has to
learn a key to keep working. In the terminal line they are stamped
(`[selected 0:31: …]`), because a second bare `[selected: …]` beside the first
is two highlights with no way to tell which came from where in the sentence.
The chip shows the newest with `↪ ×N`, the same idiom as `📸 ×N` and `🎯 ×N`.

## Shots live in Caches, one folder per relay session

`~/Library/Caches/ro.victorrentea.wispr-relay/shots/<session-stamp>/`, and
**`--home` does not move them** (it still moves the outbox).

They are a staging area, never an archive: each retina JPG is a megabyte or two,
Victor dictates all day, and what any one of them is *for* is over within the
turn that reads it. Caches is the one folder that emptying the Trash, Storage
Management and every cleaner tool actually reach, and macOS may purge it under
disk pressure — all welcome. `/tmp` was the other candidate and is worse for the
stated requirement: it clears on reboot and on a 3-day sweep, neither of which is
"when the disk is full". Same call `ScreenshotManager` makes in Victor Addons.

**The outbox stays put**, in `~/.walkie-talkie`. It is the log of what Victor said,
the record that outlives the session, and a log the system may delete under
pressure is not a log.

**The pre-Caches pile is retired to the Trash on launch** (`Outbox.retireLegacyShots`).
Moving shots to Caches left `~/.walkie-talkie/shots` behind with nothing that would
ever clean it: `prune()` walks `cacheRoot` and only `cacheRoot`, so the cap of
300 never applied there, and no cleaner tool reaches a dotfolder in `$HOME`.
Measured when this was written: **382 MB in 209 retina JPGs**, going back to the
first day the relay ran. It goes to the **Trash and not to `rm`** — old outbox
lines still name those files, and the Trash is literally the answer to "somewhere
I can clean easily": they go when he empties it. One-shot by nature, since
nothing recreates the folder.

**The per-session folder is what makes the names safe.** Shots are named by their
offset, so every session produces `shot-00:00(…)` again; without a folder between
them a new run would overwrite the last one's pictures, including ones an outbox
line still points at. Within a session the pointer position separates two shots
at the same offset in almost every real case — and `unique()` appends `-2` for
the rest, because "dictate twice without moving the mouse" is not exotic.

`prune()` counts the newest 300 **across all session folders**, not within the
current one: a session can be five minutes long, so a per-folder cap would keep
300 per restart and bound nothing. Emptied session folders are removed; the
current one never is, since it is empty for the whole time before the first
dictation.

The position is sampled **at the gesture** and carried down into
`ScreenCapture.grab(cursor:)`, never read inside it — by the time the capture
runs, a clipboard probe and a subprocess later, the hand has moved on.

### The cursor mark is on the screen, never in the picture

`CaptureFlash.markCursor` drops the red target on the desktop where the pointer
was, for ~2s — on the automatic capture that opens a dictation and on every F3
alike, since both go through `announce(cursor:)`. **`CursorMarker` no longer
touches the file.**

It used to be burned into the saved JPEG, on the argument that the file name
carried the reading for the agent while Victor — who opens these shots himself —
cannot resolve a coordinate pair by eye. Two things were wrong with that. A mark
painted into a frame **covers the thing it is pointing at**, which is precisely
the thing being asked about; and an agent reading the image has no way to know
the red circle is not part of the UI it is being asked to look at. A frame handed
to an agent should be what was on the screen.

The screen flash answers the same need at a better moment. The vignette says
*what* was captured, this says *where he was pointing while he said it* — and
unlike a mark in a file, which is something you find afterwards, it lands while
the sentence is still being spoken, so a shot aimed at the wrong thing can be
retaken with F3 on the spot.

Dropping the burn-in also dropped a second JPEG pass over a frame `screencapture`
had already encoded: ~100ms, and at quality 1.0 the file came back *larger*.

The animation **blooms** since 2026-08-29: it arrives at 0.5×, spreads to 3.6×
and fades from 0.5 to nothing, all inside **half a second**. It was Victor
Addons' `markCursor` verbatim — landing at 1.3×, settling to 0.9× over 0.35s,
then holding for the rest of 1.2s. The holding is what was wrong: the mark sits
over the very line or button he is describing, and a shape that stays there for a
second is something to wait out. Blooming uncovers those pixels by the same
motion that makes it noticeable, and the question it answers — "did that catch
where I was pointing?" — is answered by the first frame. The panel is sized to
the mark at its **largest**, or the bloom is clipped by its own window a third of
the way out.

**It also turns a quarter as it blooms**, since 2026-08-31, on Victor's request.
90° is the only angle available: the mark is a ring, four arms and a dot, i.e.
four-fold symmetric, so a quarter turn lands exactly on its own drawing and
leaves nothing tilted behind — the spin is read as motion while it happens and
says nothing once it is over. Growing straight out of the pointer is the one kind
of movement that is easiest to miss on a screen already repainting; a rotation is
not, and it costs no extra pixels and no extra time. The scale and the rotation
travel as **one animation on `transform`**, not as `transform.scale` beside
`transform.rotation.z` — those are two animations each rebuilding the whole matrix
from the model value, so they overwrite rather than compose. Core Animation
interpolates a `CATransform3D` by decomposition, so the pair never shears. It
runs from −90° to 0, which keeps the resting transform the plain scale it has
always been.

`sharingType = .none`, like the vignette — the relay photographs the screen
milliseconds later and the confirmation must never be inside the capture it
confirms. **Which also means it cannot be verified with a screenshot**; the only
checks available are the drawing itself and Victor's eyes. That the *file* is
clean is checkable, and was: zero `systemRed` pixels in a 312×312 box around the
recorded position, against 949 in the same crop of a shot from before the change.

The 🔴 pulses 1.0 → 0.25 and back, 1.1s each way — slow on purpose. Anything
brisker is something blinking next to the cursor while he is trying to think.
Only the dot animates; the count must stay readable at every instant.

**At rest there is no second row at all**, and flashes still get one: any
`flash(_:)` message summons it in any state, because the Accessibility warning
fires at launch, long before a dictation.

## The DJI receiver is the microphone whenever it is plugged in

`InputDevice.swift`, called from `MicRecorder.start` once per dictation. If a
device whose name or manufacturer says DJI is present, the recording goes through
it; otherwise through the system's default input.

- **Why not just follow the system default.** macOS points the default input at
  whatever arrived last, and this Mac has four virtual input devices on it
  (Loopback's `🎙️TO Zoom`, Wave Link, Iriun, Teams) plus every headset that ever
  pairs. Any of them can quietly become the default between two dictations, and a
  relay that followed it would record a sentence through a silent loopback and
  hand back an empty transcript. Measured side by side on the same room: peak
  amplitude 16552 through the receiver against 855 through the built-in
  microphone — the built-in is across a desk, in a room with a projector fan and
  an audience, which is exactly the audio Whisper is worst at.
- **The receiver does not say "DJI"** — its USB product name is `Wireless Mic Rx`.
  The brand is in the *manufacturer* string (`DJI Technology Co., Ltd.`), so the
  match is over name **and** manufacturer, which is also what keeps it working
  across the Mic 2 / Mic Mini line.
- **Chosen per recording, never cached.** The `AudioDeviceID` is reassigned every
  time the receiver is plugged back in, so nothing is remembered between
  dictations — which is also what makes unplugging it mid-workshop fall back to
  the built-in microphone instead of failing.
- **A device is always set, even when it is the default one.** The input audio
  unit keeps whatever device it was last told about, so a recording made after the
  receiver was unplugged would otherwise still be aimed at a device that is gone.
- **The tap's format comes from `inputFormat(forBus: 0)`, never
  `outputFormat`** — and getting this wrong aborts the app rather than failing to
  record. `outputFormat` is the node's own cached idea of what it hands
  downstream and it does **not** refresh when
  `kAudioOutputUnitProperty_CurrentDevice` is set under it; `inputFormat` is the
  hardware talking. Measured with the receiver plugged in: after selecting it,
  `outputFormat` still said **1ch 44100** (the built-in it had come from) while
  `inputFormat` said **2ch 48000** (the receiver). `installTap` compares what it
  is given against the hardware and throws
  `Input HW format and tap format not matching` — an **NSException**, which Swift
  cannot catch, so the process aborted the instant a dictation started
  (`SIGABRT`, three crash reports, 2026-09-01 18:28). Only reachable when the
  chosen device's format differs from the previous one's, which is why it arrived
  with the receiver and not with the commit before it.
- **Nothing about this is on screen.** The chip has no room for a device name and
  the choice is not a state Victor acts on; the log line
  (`mic: recording through Wireless Mic Rx — 48000Hz × 1ch`) is where it is
  answered, and it is also the only evidence if the switch ever fails.

## The voice corpus: audio kept beside the transcript, forever

**`~/.walkie-talkie/voice-corpus/`** — `VoiceCorpus.swift`. Every dictation the
relay records leaves three things behind:

```
voice-corpus/2026-08-17/14-30-22-local123.wav   ← what Victor said
voice-corpus/2026-08-17/14-30-22-local123.txt   ← what the model made of it
voice-corpus/corpus.jsonl                        ← one line per sample
```

It exists so a recogniser can be judged on **Victor's own voice** later — the
words he actually says to an agent, at the speed and in the accent he says them.
That is the one thing no public benchmark contains and the one thing that cannot
be collected retroactively.

- **It is not in Caches, and that is the opposite of the shots' argument.** A
  screenshot's purpose expires within the turn that reads it, so a folder the
  system may purge is right for it. A corpus is worthless unless it accumulates.
  It sits beside the outbox, for the outbox's reason, and `--home` moves it the
  way it moves the outbox and unlike the shots.
- **Day folders**, because he dictates 40–90 times a day and a flat folder stops
  being listable inside a week. Budget from the same measurement: ~35 MB/day of
  WAV, so **~1 GB a month**. It is meant to grow and nothing prunes it. If that
  ever bites, `afconvert` to FLAC halves it losslessly and is already on the Mac
  — but do not compress lossily, which would put a second codec between Victor's
  voice and the model being judged.
- **The `.txt` is the transcript and nothing else**, ending in a newline: it is
  meant to be diffed against another model's output over the same WAVs, and
  metadata mixed in would have to be stripped by everything that reads it.
  Duration, detected language, the app that was in front and
  `engine: "whisper-local"` are in the manifest, which is the thing built to
  carry them.
- **The line beside a recording is not ground truth.** It is what the model that
  produced it heard, so scoring *that* model against it measures nothing. Real
  ground truth means transcripts corrected by hand, which this corpus makes
  possible and does not itself contain. A field that merely *looks* like a
  correction is not one either: the relay once had access to a "what the user
  edited afterwards" column and it turned out to record where the text had been
  pasted, not what the recogniser got wrong.
- **Everything the microphone hears, whatever the relay then does with it.**
  Filing the recording is not *acting* on a dictation — nothing is sent anywhere,
  the file is on his own disk either way — so `captureLocal` is called from
  `stopLocalRecording` beside `send`, never through it. That is what kept it
  running through pause while pause existed, and it is what keeps it running for
  a delivery that is refused at a shell prompt.
- **The bytes are read on the caller's thread**, before the queue hop: the staged
  WAV is deleted as soon as `captureLocal` returns, and a copy queued for later
  would race it.
- **The clock is the key**, `HH-mm-ss` plus the millisecond. There is one
  microphone and one hand on the wheel, so two samples cannot share a second —
  and the millisecond keeps a retry from overwriting one.

## The recogniser

`Transcriber.swift` (`LocalWhisper`) plus `helpers/whisper_helper.py`. There is
**one** recogniser and no setting to change it: the relay records through
`MicRecorder` and transcribes locally. It needs `mlx_whisper`
(`pip install mlx-whisper`) and `ffmpeg`, which `mlx_whisper` shells out to for
decoding; the model is `mlx-community/whisper-large-v3-turbo`, overridable with
`RELAY_WHISPER_MODEL`.

**It used to read another app's database.** Until 2026-08-29 the relay watched
Wispr Flow's `flow.sqlite` for finished transcripts, transcribed the WAV blob it
found there, swallowed Wispr's own paste on the way past, and fell back to
Wispr's text whenever the local model could not answer — with a menu row to pick
between the two. All of that is gone, on Victor's instruction, and it went whole:
`WisprWatcher.swift`, `FlowDB.swift`, `DictationMonitor.swift`, the
`TranscriptionEngine` setting, `HotkeyTap.blockInjection`, and the
`POST /engine`, `POST /test/corpus` and `POST /test/transcript` routes. **Do not
reintroduce any of it.** If a fallback recogniser is ever wanted, it is a second
*local* model, not another app's database.

- **A daemon, not a subprocess per dictation, and that is measured.** Importing
  `mlx_whisper` costs 7.4s and the first transcription another 2.8s for the
  weights, against 1.3s once warm. Shelling out each time would put ten seconds
  between the end of a sentence and the agent seeing it. `helpers/whisper_helper.py`
  starts once, warms up on a second of silence, and answers one JSON line per
  request at ~0.1× the audio's duration.
- **Started only when a dictation is coming, released when the session ends.**
  The weights are 1.5 GB resident — **measured: the relay alone is 56 MB, the
  helper 2.5 GB once a transcription has run** — and the ordinary case is a relay
  sitting in the menu bar all day with nothing bound. Two gestures bring it up,
  and they are the two that mean he is about to talk: ⌘⌃B binding a terminal, and
  a wheel hold on a model that is not up yet (`AppDelegate.startWhisper`).
- **A wheel hold that has to wait for the model opens the microphone itself.** On
  a cold model that intention was costing ten seconds of waiting followed by a
  gesture he had to remember to repeat. `recordWhenModelReady` is set only when
  the **hold** asked for the load: a load started by a bind is Victor pointing the
  relay at a terminal, a different sentence, and must not open the microphone.
- **⏳ in two places while it loads.** The chip beside the cursor shows
  `⏳ folder@branch`, taking the slot ⏸️ uses and outranking it for those seconds;
  the menu bar shows `⏳🤖`, which is the half that survives him typing, since
  macOS hides the pointer then and the chip goes with it.
  `AppDelegate.setEngineLoading` drives both from one call so they cannot
  disagree. **The row is the only place the word appears**: `startWhisper` used to
  also flash `⏳ preparing` when nothing was bound, on the reading that the row is
  only shown bound — which `statusLines` never did, since it answers
  `engineLoading` above its `boundLabel == nil` check. So the two appeared
  together the moment the right-held chord made it possible to load the model
  unbound: *"2 mesaje de preparing, unul mare unul mai mic"*. The flash is gone. `StatusItem.refreshGlyph` still arbitrates the glyph, though ⏳ is now
  the only badge that ever claims it — ⏸️ shared the slot until pause was removed.
- **A failure has to be loud**, because there is nothing else to transcribe with:
  no `mlx_whisper`, most likely, and then `⚠️ Whisper unavailable — …` sits on
  screen for twelve seconds and the log says why.
- **The confidence floor is −0.6 and is measured, not chosen.** Over 442 real
  dictations, a gate on the worst segment's `avg_logprob` at −0.6 caught 7 of
  the 11 semantically broken outputs and falsely rejected **0 of 40** good ones;
  `no_speech_prob` caught none of them. Those 11 are not mildly wrong, they are
  fluent inventions — `Nu uitați să vă abonați la revedere!` for a sentence
  about an invoice — which is the one failure an agent cannot defend against,
  because nothing about the text looks wrong. Nearly all are clips under 5s.
- **A low score does not swallow the dictation.** There is one reading and
  nothing to fall back on, so it goes out with a warning on the panel: silence is
  the one outcome Victor cannot notice and correct. The message an agent receives
  says so too, in `dictatedHint`.
- `GET /engine` reports which model is loaded and whether it is ready — enough
  for a test to wait out a ten-second load. `POST /test/dictation` enters *below*
  the recogniser with a fabricated string, so it says nothing about it.

### What the local model is actually worth, measured

442 dictations, 163 minutes, `mlx-community/whisper-large-v3-turbo`, scored
against the transcripts the relay was receiving at the time as the reference — a
**disagreement** rate, not an error rate, since there is no ground truth here.

| | all | ro | en |
|---|---|---|---|
| semantic similarity | 0.918 | 0.908 | 0.948 |
| rare-word recall | 87.1% | 84.2% | 94.9% |
| WER | 19.4% | 21.1% | 12.8% |

86.0% of transcripts land semantically equivalent to the reference (>0.85),
11.5% degraded, 2.5% broken. **The broken ones are almost all short**: 13.6% of clips under 5s
against ~1% of everything longer. Median speed 0.105× realtime.

Two things that sound true and are not: the Romanian errors are **not** mostly
morphology — content-WER with words stemmed to five characters and stopwords
dropped is 21.8%, i.e. unchanged, so they are wrong words rather than wrong
endings. And plain WER badly understates the model, because the transcript is
going to an agent and not into a document: casing, punctuation and verb endings
cost WER and cost the agent nothing, while a mangled identifier costs the agent
everything and is what rare-word recall is there to measure.

### The menu says what the model costs

While the helper is up, the `Local Whisper` row reads `Local Whisper — 1.6 GB RAM`,
read when the menu opens (like the header) rather than pushed on a timer. The row
is **disabled**: it is a readout, not a switch — there is one recogniser and
nothing to pick between.

The number is `ri_phys_footprint` from `proc_pid_rusage` — Activity Monitor's
"Memory", not `ps`'s RSS, because MLX puts its weights in unified memory and the
two disagree on the same process. The question being answered is "what am I
paying for this?", which is Activity Monitor's question.

**It is shown because the weights are the whole argument** for starting the
helper only when a dictation is coming and letting it go at the end of the
session — and until this row existed that cost was a number in a comment, which
is exactly where a fact nobody can check belongs. It doubles as proof the helper
is alive: a dead one has no footprint and the row goes back to its bare name.

### The wheel is the relay's; mouse 5 is nobody's (except in Replace Wispr)

Until 2026-08-29 the relay took **mouse 5** — the same button the dictation app
it then depended on used for push-to-talk — so every dictation began with the
question of which of the two was armed. Victor's call: mouse 5 goes back
untouched (only a *double* click still means anything to this app: bind), and the
relay drives `MicRecorder` from the **wheel**.

**Replace Wispr takes it back, and only while the mode is ticked** — see that
section. The forward button is then the microphone for a dictation that goes to
the caret, which is the one job the wheel's vocabulary has nothing to say about.

**The wheel says three things — and only one of them is about how long it is
held. The third is a chord with the left button.**

| state | press | verdict |
|---|---|---|
| bound, not dictating | **click** | start a dictation |
| dictating | **click** | end it — transcribe and send |
| dictating | hold **2s** | **cancel** it — throw the audio away |
| **any state, bound or not** | **⌘ + click** | start a dictation **at a session that does not exist yet** — see *⌘ + the wheel* |
| anywhere, any state | **left button held ≥0.3s, then click the wheel** | **bind** — same call as ⌘⌃B, **without the toggle** |
| anywhere, any state | **left button held ≥0.3s, then the wheel held 1s** | bind **and** start the dictation at it |
| bound, any state | **right button held ≥0.3s, then click the wheel** | **disconnect** — same call as the menu's Disconnect |
| anywhere, any state | **right button held ≥0.3s, then the wheel held 1s** | dictate at a terminal that does not exist yet — ⌘ + the wheel, without the keyboard |
| nothing bound, no chord | click | passed straight through |

**The chord does not toggle, since 2026-09-01.** ⌘⌃B on the target already bound
lets go of it (below) and the chord used to do the same, because both go through
`bindFrontmostTerminal` — so the gesture Victor makes *while pointing at the
terminal he means* answered a second press by unbinding it. The ordinary reason
to make it twice is not being sure the first one landed, and the answer he wants
there is the flight again. `bindFrontmostTerminal(toggle:)` is the switch; only
the chord passes `false`. His argument, and it is the whole of it: letting go
already has two routes that mean nothing else — the right-held chord, and the
menu's Disconnect. A toggle earns its keep on a key with no off switch; it is a
trap on a gesture that has two.

**Keeping the wheel down turns the same chord into a dictation**, since the same
day. Press and let go binds; hold the wheel a further second
(`chordDictateSeconds`) and the microphone opens at the terminal that was just
bound. *Point at that terminal and start talking to it* was two gestures made a
second apart at the same window, and the second one was pure tax on the first.

The **bind still fires at the press**, so the flight plays the instant the signal
arrives rather than a second later once the verdict on the hold is in — nothing
about it is conditional on how long he goes on holding, which is what makes the
two readings of one press one gesture instead of two. A second rather than
`cancelHoldSeconds`: this is a deliberate wait, not a confirmation — nothing it
leads to is destructive.

**Rebinding moved off the wheel and onto the chord on 2026-08-29**, and the two
halves of that are one decision. Starting a dictation used to cost a **1s hold**,
bought so that a bare click could still be handed back to whatever was underneath
— which is what kept middle-click working in Chrome while a terminal was bound.
Victor gave that trade up: the gesture he makes dozens of times a day should not
be the one with a wait in it. Once a click means *dictate*, there is nothing left
for a click to also mean, and the old rebind rules — a tap over a bindable window
binds, a hold with nothing bound binds — are exactly the ones it collides with.

So rebinding is now **hold the left button, then click the wheel**. That is not a
compromise: it is unmistakable, it needs no timer to disambiguate, and the hand
that rebinds is already on the mouse already pointing at the terminal it means.
`chordHoldSeconds` (0.3s) is only there to separate *holding the left button and
reaching for the wheel* from *the wheel going down inside a click* — a drag, a
click-through, a slip. Nobody holds the left button a third of a second by
accident while pressing something else.

**The price, stated:** while something is bound — which is hours — the wheel is
the relay's, full stop. Middle-click in a browser does not open links in new tabs
or close them until the session ends. That was Victor's explicit call and it
reverses the bargain the previous build was written to protect; if it grates, the
cheap fix is to hand the click back when the frontmost app is a browser, not to
put the hold back.

**Right held, then the wheel held, opens a session instead of closing one** —
since 2026-09-01, the same day the left chord grew its own hold. ⌘ + the wheel
already spawns, and ⌘ is a *key*, which is exactly what Victor does not have to
hand when he is across the room from the laptop with only the mouse on it. So the
right chord carries both readings the way the left one does: **tap to disconnect,
hold a second to start a dictation at a terminal that does not exist yet.**

The pairing is not arbitrary. Left is *point at something that exists*; right is
now *let this one go* / *make a new one* — the two things to do when the session
in front of you is not the one you want.

**The disconnect therefore moved to the release.** It fired at the press, and
firing at the press then spawning a second later would do both — an unbind burst
going off over a binding the spawn is about to replace anyway, which is one
gesture read out loud as two. `wheelRightChord` is what
the release reads to know which branch swallowed the press; the spawn half is
**not** gated on `bound`, since the one moment a new session is most wanted is
when there is no session at all.

**Right held, then the wheel, lets the binding go** — also since 2026-09-01. It is
deliberately the *mirror* of the rebind chord: one button held as a modifier, the
wheel clicked on top, judged at the press, with the same `chordHoldSeconds`
telling a chord from two buttons that overlapped. Left points the relay at
something; right takes it back. Nothing has to be learned twice.

Disconnecting was in the menu and nowhere else, and the menu bar is the one place
the hand on the mouse is not — every other thing the wheel does (bind, dictate,
cancel, spawn) is reachable without leaving the pointer, and the gesture that
*ends* a binding was the exception. It calls the same `unbindTerminal` the menu's
**Disconnect** row calls, so both routes land in one state and the chip comes
apart where it stood (`UnbindPop`), which is the only thing on screen that says
it happened.

**It outranks every other meaning the wheel has**, including a held prompt and a
running dictation, and it is the first middle-button branch in `handle` for that
reason. It is the answer to *stop, this is going to the wrong place*, and it
would be a poor one if it first needed the sentence to be over. A press it takes
mid-dictation cancels the pending 2s hold timer, so the cancel cannot land on
whatever comes next.

**Gated on `HotkeyTap.bound`, which is deliberately not `localCapture`**: the two
say the same thing today, and the flag that means *there is a binding to let go
of* must not be the one that means *the wheel may open the microphone*. With
nothing bound the branch is skipped entirely and the click stays available to
whatever is underneath.

**The right button is watched and never taken**, on exactly the terms the left
one is — a swallowed right click is a context menu that never opened.

**The left button is watched and never taken.** `HotkeyTap` adds `.leftMouseDown`
/ `.leftMouseUp` to the tap only to record *when* the button went down, and both
are returned untouched at the top of `handle`. Nothing in that file may ever
swallow one.

**Cancelling still costs a 2s hold**, because it is the one verdict that cannot
be taken back: it throws away a sentence already spoken and there is nothing to
undo it with — the long press is the confirmation dialog this gesture does not
have. The state at the press picks the timer and the state at the fire has to
still agree, so a dictation that ended under his finger cannot have its cancel
land on the next one. It is the same verdict as the menu's `Cancel Dictation` and
as pressing Cancel on the panel a moment later, without waiting for the model to
transcribe something already known to be unwanted.

**A press with a hold on it is *claimed*, not tested.** Every gesture whose press
means one thing tapped and another held has two claimants racing for it: the
timer, which runs on the main queue, and the release, which arrives on the tap
thread. They both read `wheelDown` and then acted, so a button let go in the same
millisecond the timer fired ran **both** halves — a disconnect *and* a spawn, or
a dictation opened twice, which is `mic.start` called twice.
`HotkeyTap.claimWheelPress()` takes it under `stateLock` and whoever loses finds
it already taken; it sets `wheelArmed` **before** clearing `wheelDown`, because
the release's own swallow test reads `wheelArmed || wheelDown` and a window in
which neither is true is an orphan middle-up. `AppDelegate.startLocalRecording`
refuses re-entry as the second net.

**Nothing is replayed any more.** `replayMiddleClick` and its `wheelReplayUntil`
window are gone: the wheel is now either the relay's (and always acts) or nobody
touched it (and it was passed through at the press). What replaced them is a
single rule at the release — **any release whose press we swallowed is ours**,
whatever the state has become in between. The left button may have come up, the
binding may have been dropped; the app underneath must still never be handed a
middle-up it never saw a middle-down for. That is the orphan-event bug this file
guards against twice already, written a third time.

`HotkeyTap.frontIsBindable` survives the change but the wheel no longer consults
it: the chord acts wherever it is made and lets `bindFrontmostTerminal` refuse.
It is still pushed from `AppDelegate` on every app activation, because the menu's
**Connect Window** row greys itself out with it.

**A toggle, not a push-to-talk.** A button held down for the length of the
sentence is right for a sentence; a dictation aimed at an agent runs to a minute
or more, and a mouse button held for a minute is a hand that cannot take the
screenshots (mouse 4, F3) the same minute exists for.

`MicRecorder` opens the input device at its native rate and converts to 16 kHz
mono 16-bit through `AVAudioConverter` — the format Whisper resamples to anyway
and the format every existing corpus sample is in. Anything under 0.35s is
dropped as a misfire. The microphone is asked for **while the model loads**, not
at the first press: the grant dialog is modal and a refusal costs a trip through
System Settings, and mid-sentence with an agent waiting is the wrong moment to
find out.

**A recording is sent even below the confidence floor.** There is one reading of
the audio and no second opinion to fall back on, so the alternative to a shaky
transcript is silence — and silence is the one outcome Victor cannot notice and
correct. The banner says the score instead, and the panel holds it long enough to
fix or cancel.

**The menu can start, end and cancel one.** `Start Dictation` / `End Dictation` /
`Cancel Dictation` sit under Disconnect and
calls the same `stopLocalRecording()` a wheel tap does — the transcript is made
and sent exactly as if the wheel had ended it. It exists because the wheel is one
button on one specific mouse, and a dictation started at the desk has to be
closable from the trackpad or after that mouse's battery has gone; recording is
the one state where not reaching the button costs the dictation *and* leaves the
microphone open.

The rows are always visible and merely disabled while nothing is being recorded —
the way Disconnect is while nothing is bound — since they are then the only lines
in the menu that say whether the microphone is open at all. The answers are read
when the menu opens (`StatusItem.isRecording`), like the footprint above, because
the flag flips on every dictation.

Every dictation is filed in the corpus (`VoiceCorpus.captureLocal`), stamped
`engine: "whisper-local"` and with **no second reference transcript**: there is
one reading and no second opinion, and a manifest that duplicated the text into
two fields would read as a comparison that never happened.

### ⌘ + the wheel: the destination that does not exist yet

**Since 2026-08-30 a dictation can be aimed at a session that has not been
started.** ⌘ + the wheel opens the microphone exactly as a bare click does; when
the sentence ends, a new Terminal window appears in `~/workspace` with an
interactive Claude Code in it and the words as its first prompt, and the relay
binds it.

**Why it had to exist.** Every other destination in this app has to be *pointed
at* — ⌘⌃B, the mouse-5 double click, the left-plus-wheel chord all say "that
terminal, the one already on screen". None of them can express the way most
sessions actually begin: Victor has a thought and there is no window for it yet.
Opening a terminal, `cd`-ing somewhere, typing `claude` and waiting for it to
come up are four steps in front of a sentence he already has in his head, and by
the fourth the sentence has changed.

**It is the one gesture *Unbound is inert* does not reach.** That rule gates
everything on `isBound`, and the argument under it is that a dictation with
nowhere to go is a room taped for nobody. This one *carries* its destination, so
the argument does not apply and the gesture is live for as long as the app is —
which is exactly what Victor asked for: the moment it is most useful is the
moment there is no session yet. In the code that is `hasDestination`
(`isBound || spawnPending || pasteMode`), and it is what the four gates ask now.

**The prompt travels in `argv`, not through the keyboard.** `claude "<prompt>"`
starts the interactive session with that prompt already submitted, and that
removes the entire class of bug this file guards against twice over: there is no
window to wait for, no caret to land in, no shell prompt to be executed at, and
no race between "the process is up" and "the process can read". The words are in
the process's arguments before it has drawn a frame — verified end to end on
2026-08-30, `claude raspunde…` visible in `ps` on the spawned tty and the answer
on screen.

**Two files on disk instead of two levels of escaping.** The transcript is Victor
speaking freely — quotes, apostrophes, `$`, backticks, semicolons — and it would
otherwise have to survive AppleScript's string literals *and* a shell command
line, which is the exact place a dictation turns into a command. So AppleScript
is handed nothing but a path this app generated, and the shell reads the words
from a file with `"$(cat …)"`. Measured with a prompt containing all four: it
arrives byte-identical.

**The folder is always `~/workspace`, and nothing is inferred.** Victor's call,
and three reasons line up behind it: it is where he starts every session by hand,
so it is the one folder Claude Code already trusts; every repo he has is a folder
inside it, so the agent can still be told which one; and a destination that never
changes is one he does not have to check before he starts talking.

Resolving it — bound target, else the terminal in front, else `~/workspace` — was
written first and is what surfaced the trust prompt: spawned into
`~/workspace/walkie-talkie`, Claude Code stopped on *"do you trust this folder"*
instead of working, because he has only ever started it from the parent. An
answer that is right four times in five is worse here than a fixed one, since the
fifth is only discovered after the sentence has been spoken.

**The window flies into the chip, 2.5s after it opens** — the same `BindFlight`
every bind plays (`AppDelegate.flySpawnedWindow`). A spawn is the one destination
Victor never pointed at: the window appears on its own, somewhere he was not
looking, while his hand is still on the mouse. Every other way a session becomes
a destination answers itself with a picture of that window travelling to the
chip; this one answered with nothing, and the sentence went somewhere he had to
go and find.

**And the flight is now a real bind flight** — see the paragraph below. It used
to be played for the reason the flight exists (*which window did that go to?*)
without the claim that comes with it; the claim is true since 2026-09-01. 2.5s because `do script`
returns as soon as Terminal has a window: the shell is still starting, `claude`
has not drawn a frame, and a picture taken then is a picture of an empty prompt.
The frame comes from `TerminalBinding.terminalWindowFrame(tty:)` — not private
since this, because a spawn knows its window only by the tty `do script` handed
back.

**The binding moves to the new window (since 2026-09-01).** For its first two
days it did not: a spawn was a one-shot destination, on Victor's explicit
instruction, because the wheel is a gesture he makes dozens of times a day at the
session he is working in and a spawn that silently re-pointed it would put the
next ordinary dictation into a session four seconds old.

What killed that rule is the commonest path through the gesture, not an edge of
it: the app starts unbound, the right chord opens a session, the words land — and
the relay is still pointing at nothing, so the wheel is inert (*Unbound is
inert*) and the second sentence of the conversation he has just started has
nowhere to go. He has to bind the window by hand, which is the pointing this
gesture exists to remove. Reported 2026-09-01: *"nu s-a autolegat de acel
terminal … a rămas idle"*, with the log showing the manual `left + wheel` bind a
minute later.

**Always, not only when nothing was bound** — his call, asked and answered the
same day. A spawn is him saying the session he wants does not exist yet, which is
the same sentence as *the one I am pointed at is not it* — literally what the
right chord means (*let this one go / make a new one*). Two spawns in a row each
still get their own window; the relay ends up on the second, which is the one he
is talking to.

`AppDelegate.adoptSpawnedWindow` is where it happens, on the same 2.5s beat as
the flight and for a second reason of its own: the chip's label is read off the
process on that tty, and at `do script`'s return there is not one yet. It binds
by tty (`TerminalBinding.bind(tty:)`) rather than by "the tab in front" — the
window was never pointed at, the device is already in hand, and by then Victor's
focus may have moved on. Nothing is flashed on success: the window is in front
with the session running in it, and the chip now names it, which is the whole
message.

**The chip says the destination that does not exist yet**, and it outranks the
bound one for the length of that sentence (`RelayWindow.spawnLabel`): the words
are not going where the chip has been saying they go, and this line's whole job
is to get that right. Unbound it is also what puts the overlay on screen at all.

**Ending a dictation is never a spawn.** The destination belongs to the press
that opened the microphone, so a ⌘ click while one is running just ends it, and a
2s ⌘ hold still cancels. `HotkeyTap.wheelSpawn` is read off the **press** rather
than off the flags at the release, because ⌘ is very often let go before the
button is.

**⌘ and not ⇧, from 2026-08-30** — it was ⇧ for one build. ⌘-middle-click in a
browser is redundant with a bare middle click (both open a link in a background
tab), where ⇧-middle-click is a gesture of its own: new tab *and* switch to it.
⇧ was also already spoken for on this very wheel — `linearmouse.json` maps ⇧ +
vertical scroll to horizontal scroll, so holding it to press the button put a
sideways scroll one twitch away.

**The price** stands whichever modifier it is: it belongs to this app whenever it
is running, not merely while something is bound. That is the deliberate reading
of *"cât timp e pornit walkie"*, and it is a strictly larger claim than the bare
wheel's.

`POST /test/spawn` is the route that exercises all of it from a desk, and it
needs one of its own because `/test/dictation` is gated on a binding — the one
condition this gesture is defined by not needing.

## Replace Wispr: the relay as a way to type

**Since 2026-09-02, one menu tick turns this app into a dictation tool for the
machine rather than for an agent.** Ticked, the **forward side button** opens the
microphone and closes it, and what was said is **pasted at the caret**: no outbox
line, no terminal, no screenshots, no picked elements, no prompt panel, no
countdown. The **back button is handed back**, so LinearMouse goes on typing
Return with it.

It is named after the app it replaces. Victor dictates into chats, commit
messages and forms all day through Wispr Flow, and this app already had the two
expensive halves of that job — a warm local Whisper and a mouse button — pointed
only at agents. *"Ăsta ar fi un mod nou de lucru în care nu injectează decât
textul transcris… în fapt, cum face Wispr Flow acum."*

| | bound dictation | Replace Wispr |
|---|---|---|
| gesture | 🛞 | the forward side button |
| destination | the bound terminal | wherever the caret is |
| what travels | words, shots, selections, picks | the words |
| review | the held prompt, 3–5 s | none — it is pasted |
| back button | the shutter | untouched: Return |

- **The forward button, and not the wheel.** The wheel is the relay's whole
  vocabulary — dictate, cancel, bind, disconnect, spawn — and every one of those
  meanings is about a *terminal*. A mode that types into whatever is in front has
  no business colliding with them, and the hand can hold this one without
  learning a chord. It **outranks the mouse-5 double click** that binds a window,
  which is the one thing this mode is not about, and cannot be told from it at
  the press anyway: waiting out the double-click interval before opening the
  microphone is exactly the wait Victor had removed from the wheel.
- **The back button is not synthesised.** *"Pe butonul de Back să dea Enter"* —
  which it already does, from LinearMouse, every other minute of the day. The
  relay simply stops borrowing it (`hotkeys.dictating` is false in this mode), the
  event passes through untouched, and LinearMouse — downstream of this tap —
  produces the Return. Posting one here as well would be two Returns for one
  press.
- **It carries its own destination**, so *Unbound is inert* does not reach it, the
  same exemption ⌘ + the wheel has. `hasDestination` is `isBound || spawnPending ||
  pasteMode`, and the tap's branch consults the mode flag and nothing else.
- **Decided at the press, consumed at the stop.** `pasteMode` is read and cleared
  in `stopLocalRecording`, so a transcript landing a second later goes where the
  press said it would even if the tick has been clicked since — the rule
  `Message.spawn` already follows.
- **No context shot, and that is not only a saving.** The automatic frame exists
  to be read by an agent beside the words; here there is no agent and no message.
  The real reason is the selection probe that comes with it: it posts a ⌘C into
  whatever field he is about to dictate into, and this is the one mode where that
  field is the whole subject.
- **The chip says `⌨️ at the caret`**, in the slot a spawn uses and for the
  spawn's reason: the bound terminal is still there, and for the length of this
  sentence the words are not going to it.
- **Off at every launch, deliberately not persisted** — the call `Autosend`
  makes. It changes where every sentence lands, and a tick that survived a restart
  would put a dictation meant for a bound agent into whatever field had the caret,
  weeks after he had forgotten it was on.
- **The transcript is on the clipboard as well as at the caret**
  (`pasteText`, which ⌘⌃P now shares), so a paste that landed somewhere unhelpful
  is one ⌘V of his own away from being fixed. `lastDictation` is set too: a
  Replace Wispr sentence is exactly the kind wanted twice, in a second field.
- **`POST /test/replace-wispr {"on": true}`** exists because the mode is otherwise
  reachable only by clicking a menu row — the one input nothing at a desk can
  produce. The route and the row both go through `setReplaceWispr`, so the tick,
  the tap's flag and the flash cannot say three different things.

**The corpus keeps everything**, as it does for a delivery refused at a shell
prompt: `captureLocal` runs before the branch. These are Victor's own words in his
own voice, and which destination they were headed for says nothing about their
worth as a sample.

## A bind mid-sentence changes the recipient

The left-plus-wheel chord works **while a dictation is running**, and it
redirects the sentence being spoken. The tap sees the chord before it sees the
wheel's own meaning (`leftIsHeld` is checked above the dictation branch), the
press is swallowed and the release fires nothing, so the recording is not
touched — only where it is going.

For a bound → bound rebind this was always true and by accident of a good
design: `deliverToTerminal` asks `terminal.target` when the panel resolves, not
when the microphone opened. **A spawn was the exception**, and since 2026-08-31
is not: ⌘ + the wheel sets `spawnPending` at the press, and `showBound` now takes
it back when a bind lands mid-recording (`spawnPending && localRecording`). Before
that, ⌘ + the wheel followed by the chord opened a new session in `~/workspace`
anyway and left the terminal he had just pointed at with nothing.

The chip stops saying `✨ workspace` at the same moment, because `clearSpawn`
does both — a destination line that is no longer true is worse than none.

**The window is the recording, not the panel.** Once the transcript is on screen
the destination is already on the `Message` (that is what `Message.spawn` is
for), and a bind during the hold changes nothing about the sentence in front of
him. The seconds are few and the rule is the simpler one to hold: *the recipient
is whoever the relay is pointed at when the microphone closes.*

## ⌘⌃P pastes the last dictation

The last dictation that **went out** — its words, not the line the terminal got —
onto the clipboard and pasted at the caret, from `⌘⌃P` or the menu row. `📸 ×2
0:38`, the quoted selection and the picked selectors stay behind: that envelope is
addressed to an agent, and this is for the commit message, the chat or the form
where the same sentence is wanted a minute later. Saying it twice is worse than
saying it once — the second take is never the same sentence, and it costs another
model run.

Both halves are the feature: the clipboard keeps it so it can be pasted again,
the ⌘V is so he does not have to think about the clipboard when the caret is
already where the words go. **The clipboard is not restored** afterwards, unlike
`TerminalBinding`'s blind paste — there the relay borrows it behind his back,
here he asked for it.

Recorded at `commit`, so a cancelled prompt does not overwrite the last thing
that did go out, and after an edit is folded in. Silent on success; the one thing
it says out loud is `⚠️ nothing dictated yet`. From the menu the ⌘V waits a beat,
because AppKit gives the caret back a frame or two after the row is clicked.

## The chip teaches nothing; the menu does

**A setting is not an event.** The same argument that took the gesture hints off
the chip took the model id off it on 2026-08-30: the engine row read `Listening
with mlx-community/whisper-large-v3-turbo`, which is the right fact — the id is
what a comparison between recognisers is written down against — in the wrong
place. A comparison is written down at leisure; that row is read mid-sentence,
beside the cursor, and it stretched the panel to the width of its longest
possible value in order to restate something that does not change from one
dictation to the next. It now says `Listening…` and nothing else, and the id
appears in the menu's engine row beside the RAM the model is holding
(`StatusItem.applyWhisperTitle`), which is where the rest of the engine's facts
already were.


**Since 2026-08-30 the overlay advertises no gesture at all** — with one
condition-gated exception below. Every row whose job was to name an input is off:
`ReBind` and `dictate` at rest, `send` while editing the transcript, the shutter
beside the pulse. What is left on the chip is everything that reports *state*:
the pulse, `Listening…`, `transcribing…`, `preparing`, the picks he has
actually made, the destination.

**The exception is `⌘⇧`, shown while dictating *and* with Chrome in front.**
Victor asked for that one back the same day, and the two conditions are what earn
it the pixels. The hints that were removed were paid for at every moment of every
day in order to be read once; this one is on screen only when it is actionable —
a dictation is open and he is looking at the page he would be pointing into — so
it costs nothing in the hours it is not true. It also has the strongest claim of
any of them to being said out loud, because the relay **takes the gesture away
from Chrome** while it is up: ⌘⇧-click normally opens a link in a new tab and
jumps to it, and a browser that silently stopped doing that reads as broken.

Once he has actually picked something the row belongs to the picks and stays
whatever app he switches to — they are travelling with this dictation, which is a
fact about the message rather than about the front window. `chromeFront` is
pushed from `AppDelegate`'s existing front-app watcher, the one that already
answers `frontIsBindable`: `NSWorkspace` is a main-thread question and this is
read from `layoutContent`, which runs while the chip follows the cursor.

It is the same argument that took the `bind` row off the unbound chip a build
earlier — *"mă încurcă, mă enervează"* — carried to its end. The chip rides over
Victor's real work all day; a legend is read once and paid for forever, and the
inputs it was teaching are ones he makes dozens of times a day and now knows.
He asked to learn the remaining ones *"ușor-ușor"*, from the menu.

**`RelayWindow.showsGestureHints` is one word, and the rows are still built.**
Nothing was deleted: `shotHintText`, `pickHint`, `rebindText` and their glyphs
are all still there and still measured, so this is reversible by flipping the
flag. Victor said *temporar*, and a change described as temporary that deletes
its own way back is not one.

**The menu bar becomes the only legend, and therefore has to be complete.**
Every action the app has is a row, **always visible**, naming the mouse or key
that performs it — `New Claude Code in ~/workspace — ⌘ + 🛞, or hold ➡️ + 🛞 1s`,
`Cancel Dictation — hold 🛞 2s`, `One More Screenshot — F3, or the back
button while dictating`. A row greys out when it cannot act *this second*; it
never disappears, because a menu that hid what he cannot do right now would be
useless for learning what he can do at all. That is what *"indiferent de starea
în care sunt acum"* asks for.

One row exists because of this rule rather than despite it:
**`Pick an Element in Chrome — ⌘⇧ + 🖱️`** is a legend, permanently
disabled — the gesture happens inside a page this app cannot reach from a menu,
but the relay takes the input over, so with the chip silent there is nowhere else
it could be written. A disabled row is the honest rendering of *this is something
you do, not something you pick*.

The two new commands are the same calls their gestures make, not quieter
variants: `New Claude Code` is `startLocalRecording(spawn: true)`, and
`One More Screenshot` is `plusOneShot` — the latter **after a 0.35s beat**,
because AppKit dismisses the menu and the screen redraws a frame or two later,
so a capture fired on the click would photograph the menu that ordered it.

## Size: minimal, per state

`layoutContent()` hugs the **current** state's content — not the widest state
there is. Standing by is what the overlay does for hours, so it must be no bigger
than `🤖 ai@master` needs — not even the 26px normally kept clear for the ✕, since
the chip has none. It used to reserve room for the longest title and for the
hidden shortcut legend, which bought an overlay that never twitched at the cost of
empty space the whole time.

Resizing on a state change is therefore expected and fine, and so is the hair of
width the recording row gains at `×10`.

Row heights, for checking a layout change without seeing it: title 16, engine row
17, shots row 17, ⌘⇧-picked row 17, selection 15, `rowGap` 6 between them, `pad`
12 all round. So the idle chip is 40 tall — bound is the same, since the folder
moved *into* the title row — and dictating is 40 + 3 × 23 for the three rows and
their gaps, plus 21 more with a selection.

**No screen capture can contain this window**, and `RELAY_CAPTURABLE=1` no
longer buys it back on macOS 15 (verified 2026-07-31: transparent image, both
whole-display and `screencapture -l <windowid>`). Two ways to see a change
anyway:

- `./docs/shoot-overlay-states.sh` → all 33 states at once, and the page that
  shows them. This is the one to reach for; the rule that comes with it is at the
  top of this file. A panel's blur is missing from the shot (the window server
  draws it, not the view) and so is the window's alpha, which the page reapplies
  in CSS; the chip comes out exactly as he sees it.
- `kill -USR1 <pid>` → `<home>/snapshot.png`, the same drawing, for one state that
  is already on screen. Still the fastest way to look at something mid-session,
  and how `docs/idle.png` and friends were made before the harness existed.
- `CGWindowListCopyWindowInfo` for geometry: the bounds say which rows are up,
  and comparing the origin to the cursor says whether it is still anchored.

## Two shapes: the chip and the panel

The overlay has two forms, and `anchored` in `RelayWindow` is the switch.

**Anchored (at rest *and while dictating*)** — bare text, `🤖 folder@branch` plus
the recording row when there is one, no blur, no rounded rect, no window shadow,
alpha 0.80, trailing the cursor. Parked in a corner it was either invisible or
pointless; riding along with the pointer it answers the one question worth
answering at rest — *which agent is this?* — where he is already looking. There
is **no ✕ on the chip**: an end-session button on something that moves away as
you reach for it means nothing. (The menu bar item is the ✕ that stays put.)

**Panel (the message, and only the message)** — what the overlay has always been,
top-left of the current screen, with the blur, the ✕ on hover, and full opacity.
Entered by a prompt, and **by nothing else since 2026-09-02**: a flash used to
borrow the blur without leaving the pointer, and now borrows nothing. See *Nothing
beside the pointer draws a window*.

**There is never a ✕ beside the pointer, in any state.** The rule was
`bare || !hovering`, which meant a flash — anchored, riding the cursor like
everything else — put one there for the length of its message. There is nothing
to press: the thing moves with the hand reaching for it, which is the argument
that has always kept a ✕ off the idle chip. It is now `anchored || !hovering`, so
only the panel parked in a corner has one. Victor, reporting it: *"n-am cum să
apăs pe el din moment ce acel tooltip se plimbă cu mouse-ul"*.

**Dictating is not a panel state.** It was, and that put a half-screen window
over his work for the entire time he talked, to report a state he had just
entered on purpose. The panel is now for the one thing he must actually read:
what the model heard, while Cancel can still stop it. That is also why the F3
receipt is a number in the recording row and not a `flash(_:)`: a flash takes the
chip over for a second and a half, and the count has to keep climbing while he
talks.

Tracking has two modes, and the second is what keeps the chip catchable:
*engaged* pins it to the cursor every frame at 60 Hz (anything lazier reads as
lag, because it is lag), and after ~0.25s of stillness it *settles* and stays put
until the cursor travels 70px. Growing into the panel is animated (0.22s ease
out); everything else resizes instantly.

## The pointer is clean when nothing is bound

**Unbound and idle, there is no overlay window on screen at all** — not a faded
one, not an empty one. `RelayWindow.refreshPresence` orders the panel out.

**Tried and reverted the same hour, 2026-08-29.** A single row, `🛞 bind`, went
in so the state would have a visible way out; Victor had it out again within the
hour — *"mă încurcă, mă enervează"*. The lesson is the one this section already
carried and is worth stating in its stronger form: the pointer is where he
works, an unbound relay is inert, and **nothing** is the correct amount to say
about a state in which the app does nothing. A gesture he already knows does not
buy a label that rides beside the cursor for hours.

What survives from the attempt is structural and worth keeping: `layoutContent`
omits the **title row** entirely when there is no destination (it used to render
`🤖 /` and lean on `refreshPresence` to hide it), and `refreshPresence` counts any
row at all as a reason to be on screen rather than `rowCount > 1`, which only
made sense while the title row was unconditional and therefore free.

The chip's one job at rest is to say *where the words go*. Bound, that is a real
answer: the destination app's icon and `petclinic@main`. Unbound it was `🤖 `
plus whatever directory the app was launched from — and since Walkie Talkie
became a login item (`SMAppService`, started by macOS from nowhere in
particular) that directory is `/`. A robot and a slash, riding beside the
pointer every waking hour, naming nothing. Victor: *"acum langa mouse-ul meu e
permanent un emoji cu un robot si un '/'. cand walkie nu e legat la nici un
terminal, mouse-ul tre sa fie curat"*.

**`orderOut`, not `alphaValue = 0`.** An invisible panel is still a panel: it
sits 10pt right and 22pt below the cursor and it takes mouse events, so one
following him around all day would swallow clicks on whatever it happened to be
over. The `typing` state may fade to zero — it lasts as long as a keystroke —
but this state lasts hours.

**The rows decide, not a list of states.** Everything the overlay has to say is
a row: the dictation in progress, a held prompt, a flash, a ⌘-picked element, a
frozen selection. So a layout that produced *only* the title row is by
construction an overlay with nothing to say, and `layoutContent` hands its row
count straight to `refreshPresence`. The three states that change the *title*
instead of adding a row have to be named there explicitly: bound, and
the model coming up. A row added later keeps the chip on screen without anyone
remembering to come back and edit that condition.

Coming back, it is `reposition`ed first: it may have been away for hours, so it
lands where the pointer is now rather than reappearing wherever it was last
parked.

## The menu bar item

`StatusItem.swift` puts a 🤖 in the menu bar for the whole life of the process,
with **where the words go** as a disabled header — the destination app's icon
beside `Bound to: folder@branch` of the bound session — then every command the
app has (*The chip teaches nothing; the menu does*), the **Autosend** checkbox,
the engine readout and **Quit**.

The chip shows the same line **without** the `Bound to:` prefix, and that is not
a drift between them. Beside the cursor a folder name has nothing else it could
be naming; in the menu it sits above `Connect Window` / `Disconnect` /
`End Dictation`,
where a bare name between an icon and a stack of commands reads as a section
title — as what the commands are *for* — rather than as a destination. Only the
bound form is prefixed: unbound the row falls back to the launch label, and
`Bound to:` in front of that would be false in the state the row is most often
read in.

`AppDelegate.showBound` is the single place both are written, so the chip and the
menu cannot disagree about the destination. Unbound, the header falls back to
`🤖 <launch label>`, which is what an unbound relay is: an outbox in a directory
with some agent watching it.

It exists because neither shape is a dependable place to find the app. The chip
belongs to the pointer and hides while he types; the panel comes and goes with
what is happening; and the ✕ lives only on the panel, which at rest is not on
screen at all. The menu bar is the one place that is always in the same pixels.

The label is read in `menuWillOpen`, not pushed on a timer — with two overlays up,
two identical 🤖 say nothing about which session a click is about to end, and the
only moment the answer has to be right is the moment he is looking at it.

### Every row has an icon, and two alphabets share the column

Since 2026-09-01 each command carries a picture in the menu's icon column.

| row | icon | gesture in the title |
|---|---|---|
| `Connect Window` | `mappin`, in Google Maps red | `hold ⬅️ + 🛞` (⌘⌃B rides the shortcut column) |
| `Disconnect` | `mappin.slash` | `hold ➡️ + 🛞` |
| `Start Dictation` | `mic` | `🛞` (⌘⌃D in the shortcut column) |
| `End Dictation` | `mic.slash` | `🛞` |
| `Cancel Dictation` | 🗑️ | `hold 🛞 2s` |
| `New Claude Code in ~/workspace` | ✨ | `⌘ + 🛞, or hold ➡️ + 🛞 1s` |
| `Paste the Last Dictation` | 📋 | ⌘⌃P |
| `One More Screenshot` | 📷 | `F3, or the back button while dictating` |
| `Pick an Element in Chrome` | ✋ | `⌘⇧ + 🖱️, while dictating` |
| `Replace Wispr` | ⌨️ | the forward side button (see *Replace Wispr*) |

**Two sources, and the split is forced rather than aesthetic.** Emoji are what
Victor asked for and they carry their own colour — but Unicode has no crossed-out
map pin and no crossed-out microphone, and both of those rows are the *off* half
of a pair. A pair whose halves come from two different alphabets reads as two
unrelated rows, so **Connect/Disconnect and Start/End are SF Symbols on both
sides**, where the slash is drawn by the same hand as the thing it crosses.
Everything with no off state is an emoji, rendered into an image of the same size
(`StatusItem.emojiIcon`) so the column lines up.

📍 is not the pin. It is `ROUND PUSHPIN` — a thumbtack stuck in at an angle, not
the teardrop marker everybody means by a pin on a map; `mappin` is the marker.
Same objection `Glyphs.pin` was drawn to answer, one column over, and Victor
raised it again by name here.

**The gestures are drawn, not spelled.** `— or hold left, click the wheel` is six
words describing two objects, read in a menu open for a second; `— hold ⬅️ + 🛞`
is the same sentence in the shape of the mouse it is about. Right-aligning them
into the shortcut column was the first ask and `NSMenuItem` does not offer it —
that column belongs to `keyEquivalent`, and a wheel is not a key — so they stay in
the title, after the em dash, where the words they replace already were.

### Autosend

A checkbox, **off at every launch and deliberately not persisted**. Ticked, the
pre-send panel opens for one second (`AppDelegate.autosendHold`) **with no Send
and no Cancel on it**, and then the message goes.

- **The panel still opens.** It is the receipt, and a dictation that vanished into
  a terminal with nothing shown is the one state where a delivery cannot be told
  from a drop.
- **The buttons' row goes with them**, not just their labels: two buttons up for
  one second are two buttons nobody can reach — an invitation to press something
  that will not be there when the hand arrives.
- **Not remembered across launches**, and that is the point. The panel is what
  catches a transcript the model got fluently wrong; a checkbox that survived a
  restart would quietly take that away weeks later, in a session where he had
  forgotten it was ticked.
- The state lives on the menu item (`StatusItem.autosend.state`) and is pushed to
  `AppDelegate.autosend` through `onToggleAutosend`, so the tick and the behaviour
  cannot disagree.

Quit goes through the same `endSession(reason:)` as the ✕, so the outbox still
gets its `session_end` before the process dies. There is no ⌘Q key equivalent:
the app is `.accessory` and never becomes key, so the hint would advertise a
shortcut that does nothing outside the open menu.

### The 🤖 on the other screens

`NSStatusItem` appears in exactly one menu bar: the display that currently has
the keyboard focus. Victor works across three, and the state that glyph carries —
the model loading — is precisely what he needs while looking at one of the
other two, since the chip is hidden the moment he starts typing.

`MenuBarMirror` draws the rest: one borderless, click-through panel per screen at
`.statusBar` level (above `.mainMenu`), carrying the same string `refreshGlyph`
puts in the real item, on every space including full-screen ones. It is an
indicator only — no menu — because opening one is a focus change away, and a
click here means crossing to another display anyway.

**Centred in the strip, not at either end**: the right end is the clock and
Control Center, the left is the frontmost app's menus, and the middle is the only
part of an inactive menu bar that is reliably empty. `NSScreen.main` is polled
every 500ms rather than observed — it moves with the focus and posts nothing —
and the panel on the active screen is hidden, since the real status item is
already there.

## The corner beacon: a microphone on every screen while it listens

**Top-right of every display, a 30pt strip, a 🎙️ pulsing 1.0 → 0.15 and back over
1.2 s each way** (`RecordingBeacon.swift`), for exactly as long as the microphone
is open.

The chip already says this — the pulsing 🔴 and `Listening…` — and it says it
*beside the cursor*, which is the one place Victor is not looking while he talks:
he dictates while reading something on another display, with a full-screen window
up, and macOS hides the pointer the moment he touches the keyboard, taking the
chip with it. The state that must never be in doubt — *is it still hearing me?* —
had the least dependable receipt in the app. This is Wispr Flow's own answer to
the same problem, which is what he asked for by name.

- **The pulse is the point, and it is slow on purpose.** 1.2 s each way is the
  🔴's tempo and is chosen for the 🔴's reason: anything brisker is something
  flashing in the corner of the eye of a man trying to think, and this one is up
  for the whole minute a dictation to an agent lasts. A frozen microphone is
  indistinguishable from a hung app, which is the failure it is here to rule out.
- **One panel per screen**, the shape `MenuBarMirror` has and for its reason: with
  `com.apple.spaces spans-displays` off — the default — no window spans two
  displays, and the display he is *not* typing on is the one this is for.
  `.statusBar` level and `fullScreenAuxiliary`, so a full-screen window does not
  bury it.
- **Never in a screenshot** (`sharingType = .none`). The relay photographs the
  screen during the very dictation this marks — the automatic frame and every F3 —
  and a confirmation inside the thing it confirms is a fixture the agent has to
  learn to ignore. Same rule `CaptureFlash` and `MenuBarMirror` follow. **It is
  therefore not checkable with a screenshot**; what is checkable is the geometry,
  through `CGWindowListCopyWindowInfo`, which is how the four panels were verified
  sitting at the right edge of each screen under the menu bar.
- **Just under the menu bar, not in it.** The bar's right end is the clock and
  Control Center. `visibleFrame.maxY` is what places it, so the notch's taller bar
  needs no number written down here.
- **`syncBorrowedGestures` is the switch**, on `listening` rather than on `live`:
  it answers *is it hearing me?*, and the microphone is either open or it is not —
  where the words then go is the chip's question, not this one. Riding the one
  method every edge of a dictation already passes through is what keeps it from
  drifting out of step with the row on the chip.

## The prompt is held, not sent

The prompt shown after a dictation is **not yet in the outbox**. It sits in
`AppDelegate.held` for 3–5s (`minHold`/`maxHold`, scaled by word count) behind a
**Cancel** button in the bottom-right, and only `commit()` — on the countdown
running out, on a click on the overlay body, or on quit — ever writes it.

That delay is the whole point: the agent polls the outbox every couple of
seconds, so a line already written may already be a tool call in flight. Cancel
can only mean something while nothing has been written. Escape in the terminal
remains the tool for work already under way.

**The last line of the prompt is the pictures, with their times:**

```
↪ public Order placeOrder(Cart cart) {
extract the tax calculation out of this method
📸 ×2 0:38
```

`AppDelegate.shotLine` builds it, and the stamps are **m:ss from the moment the
dictation opened**, not wall-clock. The count on its own answers "did my shots
land"; it does not answer the question he has a few seconds later, which is
*which* moments he caught. In a three-minute dictation `📸 ×4` is four
indistinguishable files, while `0:38 · 1:52 · 2:41` is a table of
contents — and this panel, with the Cancel clock running, is the last instant at
which noticing a missing one is free. Wall-clock would say nothing here: the
shots exist only as parts of this message, and `15:22:07` does not locate a
moment *inside* it.

**The context screen is counted but not stamped.** It is always at zero — he
took it by starting to talk — so its `0:00` is the one stamp that carries no
information, and printing it only pushed the stamps that do mean something a
column to the right. What is listed are the moments he chose; a dictation whose
only picture is the automatic one therefore reads `📸 ×1`, with nothing after it.

The count is built from `pendingScreen`
plus `pendingShotOffsets`, **not** from `attached` — the screen travels in its
own outbox field, so counting `attached` would print a total one lower than the
`📸 ×N` he just watched climb in the recording row. The `🎙️ sent + N 📸` flash
counts the same way, for the same reason.

Offsets are sampled **at the gesture** (`plusOneShot`'s `takenAt`), like the
cursor and for the same reason: `screencapture` returns a subprocess later, and a
second of drift is a whole sentence.

Ordering is preserved: a second dictation arriving mid-countdown releases the
first one before displaying itself.

### ⏎ sends it, and clicking the words edits them

Since 2026-08-28 the panel is not only a thing to read.

- **⏎ sends now.** The Send button has read `⏎ Send 3s` since it was written and
  the key did nothing, because the overlay never takes the keyboard. It is caught
  in `HotkeyTap` instead (`promptHeld`, `onPromptEnter`) and **swallowed**, so the
  Return does not also land in whatever is behind the panel. Bare only — ⌘⏎ and
  ⇧⏎ belong to other people — and only during the 3–5s a prompt is actually up,
  which is what makes taking a key as ordinary as Return affordable: outside that
  window it is untouched, and inside it Victor is reading a panel, not typing.
- **A click on the transcript turns it into a text field**, because a local
  Whisper line is occasionally *fluent nonsense* and the only two answers the
  panel offered were send it or lose the sentence and say it again. One wrong word
  in forty is not worth saying again, and is exactly what the model gets wrong.
- **Only the words are editable.** The preview also carries `📸 ×2 0:38` and the
  `↪` lines, which are the app describing what it is carrying — `showSentPrompt`
  now takes the raw `words:` alongside the assembled preview and keeps the seam
  (`promptWords` / `promptExtras`), so the box he types in holds his sentence and
  nothing else. If the two do not agree the text is simply not editable, which is
  the honest failure.
- **The clock stops while he is in the field, and restarts whole when he leaves.**
  A dictation going out from under his hands mid-word is the one failure worse
  than the mis-transcription. Clicking away means "that's right now" — and the
  new text deserves the same read-through the old one got, so it is a restart and
  not a resume.
- **Clicking outside the panel counts as clicking away** (a global mouse monitor,
  armed only while editing). Global monitors see only events going to other apps,
  so it can never fire for a click inside the field.
- **The panel takes the keyboard for exactly that long.** `RelayPanel.wantsKey`
  gates `canBecomeKey`, and `.nonactivatingPanel` is what makes it affordable: the
  panel becomes key **without the app activating**, so the terminal stays
  frontmost and gets the keyboard straight back. Handing it back is
  `orderOut` + `orderFrontRegardless` — there is no API for "give it to whoever
  had it", and the window server does exactly that once the panel stops being key.
- **One view, not a label swapped for a field** (`PromptField`). The panel's
  height is measured from its rows, so a swap would be a row vanishing and another
  appearing at the moment the panel should be doing nothing but growing a caret.
  Its `mouseDown` override is load-bearing: a label *does* swallow the click that
  lands on it, so before this, clicking the words reached nothing at all and the
  panel's "click to send" only ever fired on the empty space around them.

## Dark mode

The overlay must look right in **both** appearances, and it follows the system
automatically — nothing pins an appearance. That holds only as long as every
colour is either a dynamic system colour (`labelColor`, `secondaryLabelColor`,
`textBackgroundColor`, `systemRed`) or a translucent white/black overlay that
works on any backdrop. The blur is `NSVisualEffectView(.hudWindow)`, which
adapts on its own.

**Do not hardcode a literal colour for anything that sits on a variable
backdrop.** The ✕ was drawn with a hardcoded white cross: fine on light mode's
dark disc, nearly invisible against dark mode's light one. Custom-drawn views
resolve dynamic colours against `effectiveAppearance` inside `draw(_:)`, so
using them is enough — no appearance observers needed.

## Opacity states

| state | alpha |
|---|---|
| idle chip | 0.80 |
| every panel state | 1.00 |

The chip is translucent because it now rides over his actual work and has to read
as an overlay; the panels are opaque because each of them exists to be read. The
0.30 that used to belong to paused went with it.

## Nothing beside the pointer draws a window

**Victor's rule, 2026-09-02:** *"toate tooltip-urile din jurul mouse-ului …
niciunul nu mai trebuie să aibă border în jur"*. `refreshChrome` asks one
question now — `let bare = anchored` — so the blur, the rounded rect, the shadow
and the ✕ belong to the panel parked in a corner and to nothing else.

A flash used to summon all four for the length of its message, on the argument
that a sentence read once over a busy screen earns a surface. What that actually
did was open and close a window an inch from his hand, dozens of times a day,
over the thing he was reading — for `⚠️`, for `🎙️ sent + 2 📸`, for every bind
receipt. The cancelled dictation got the exemption first (*"fără border…
înlocuiești Listening cu dictation cancelled"*, 2026-09-01) and nothing in that
argument was ever about *which* message it was.

What paid for the surface was legibility, and that bill is settled by `bare`
itself: white text with a halo, which is what makes a row readable over a dark
terminal and over a white page with nothing drawn behind it.

**`flash(_:duration:bare:)` lost its parameter with this.** One caller passed
`true`; now everyone gets it, and a parameter whose only value is the default is
a question nobody is being asked.

**A flash replaces the collapsed chip rather than sitting under it.** Bound with
nothing in flight, the title row is a lone 🎙️ with no words beside it (`collapsed`
— the chip *being* a microphone is the whole sentence). Under a message that row
is noise, and twice it was worse than noise: `dictation cancelled` read as a
microphone with a caption — Apple draws the wastebasket with its lid flying off
above the bin, so the 🗑️ the message used to lead with was a second one — and
`🎙️ sent + 2 📸` came out as two microphones stacked, one of them punctuation.
Victor: *"să nu se arate și microfonul acela mic, ci doar dictation cancelled"*.
So `layoutContent` drops the title row while a flash is up **and** the chip is
collapsed. Only then: with a folder name in the row the glyph is that line's icon,
and the line is still the honest answer to *where do the words go*.

## Placement

**Chip**: below-right of the cursor (`anchorGap`), flipped at the screen edges so
it is never half off-screen, never under the pointer.

**Panel**: top-left of **whichever screen the cursor is on**. An overlay stranded on
the other monitor is an overlay he cannot see; where it sits *on* that screen is
left alone, so one he dragged out of the way stays out of the way. It anchors its
top edge so it grows downward, and never teleports while a mouse button is down.

## Capture order: flash first

The red vignette fires **before** the selection probe and before `screencapture`
— `CaptureFlash.announce()` at the top of `captureContext` / `plusOneShot`, with
the slow work pushed onto a background queue. It used to fire from inside
`ScreenCapture.grab`, i.e. after a clipboard probe that sleeps up to 400ms and a
subprocess we wait on, so the confirmation landed visibly late — after the window
had already widened and the selection was long taken. A receipt that arrives that
far behind the gesture no longer says *now*.

`CaptureFlash`'s panel is `sharingType = .none`, so firing it first cannot put it
in the shot it is confirming.

## Picking elements in Chrome

Hold ⌘⇧ over a page **while dictating**, the cursor becomes a `grab` hand, the
element under it is outlined and named; ⌘⇧-click and its selector joins that dictation. It resolves the demonstratives — "make
*this* button blue" is not actionable, and a CSS path is the same sentence with
the pronoun filled in.

**It is a Chrome extension (`chrome-extension/`), and the relay is only a
mailbox.** CDP is the obvious design and it is the wrong one twice over:

- Since Chrome 136 `--remote-debugging-port` is refused on the default profile,
  and `--load-extension` is ignored outright as of 151 (verified 2026-08-15:
  the flag loads nothing, and `--disable-extensions-except` alongside it disables
  everything). Driving Victor's *actual* browser over CDP would mean relaunching
  it against a throwaway `--user-data-dir` — a browser without his tabs or his
  logins, i.e. not the thing he is looking at.
- From outside, pointing at a DOM node means mapping a screen point through the
  window origin, the height of the browser chrome, page zoom and device pixel
  ratio, then mapping the element's box back out to draw a rectangle round it.
  Inside the page there is no mapping at all — `elementFromPoint` and
  `getBoundingClientRect` are already in the coordinate system the outline is
  drawn in, and stay right after a zoom.

So `ElementPicker.swift` is an HTTP listener on loopback and nothing else. The
inspector — outline, label, ⌘⇧ gate, swallowed click, selector — is `inspect.js`.
Ports are 8917–8919, first free one per relay; the extension posts to **all** of
them, which is the same shape as the outbox, where one dictation reaches whoever
is listening.

Installing it is a manual step, once: `chrome://extensions` → Developer mode →
Load unpacked. There is no scriptable route left in Chrome 151 (`Extensions.
loadUnpacked` over CDP works, but only for a browser started with
`--enable-unsafe-extension-debugging`, which his is not).

### It lives only while the recording row does

`ElementPicker.dictating` is set from the same `listening` as mouse 4,
by the same `syncBorrowedGestures()`. Outside that window `/ping` answers 503 and
the extension reads a refusal exactly like no relay at all, so ⌘⇧ in Chrome goes
straight back to opening links in new tabs.

It was armed around the clock for about an hour, and that is the wrong shape:
⌘⇧-click is how a link opens in a new tab, so an inspector that can take it at any
moment is a browser that intermittently stops opening links with nothing on
screen to explain why. Tied to the dictation, the theft is narrow *and visible* —
the row saying the gesture is live and the gesture itself appear and disappear
together, which is the same bargain mouse 4 already made.

The extension caches its probe for only 1s (`PROBE_TTL_MS`) because the answer
now flips every time he starts and stops talking, rather than once a session.

### The hint is the row, and the row is beside the cursor

While dictating and before he has picked anything, the row is Chrome's icon and
`⌘⇧`, nothing else. After the first pick it gives way to `×2 div#cart >
span.price`, because the question changes: before, the only thing worth saying is
*that this is possible*; after, he knows the gesture, and what he cannot check
without a name is whether the click caught the button or the div wrapped around
it.

It has been stripped twice, both times on the same argument. It read `hold ⌘⇧🖱️`
and then `select element ⌘⇧🖱️`: the words went because the row is not read by
somebody discovering the feature, it is glanced at by somebody who knows it —
what he needs is the *keys*, which are the half borrowed from Chrome. **And the
mouse went on 2026-08-31**, at Victor's request: a hand already holding two
modifiers down over a page is not in any doubt about which button clicks, so the
drawn left button was the one glyph on the row he could not act on, drawn at a
size and baseline of its own, taking a third of the width to restate the obvious.
It is also the only thing that ever made this row need `glyphRowWidth`.

**The glyph is Chrome's own icon**, `NSWorkspace.icon(forFile:)` on whatever
`com.google.Chrome` resolves to — looked up, never shipped, so no version of the
logo is frozen into the repo and a restyle arrives on its own. `pickGlyph` is
therefore an `NSImageView` and not a label, and `pickGlyphWidth` is the constant
`pickGlyphSize` rather than a font measurement: an image has no metrics to ask.
It replaced a 🎯, which said "aim at something" — which is what the words beside
it already say — where the browser the gesture only works in was said nowhere.

### The cursor is a hand, not a crosshair

`inspect.js` puts `cursor: grab !important` on the page's own elements while the
outline is up (it cannot live in the shadow root, so it goes up and comes down
with it). It was `crosshair` until 2026-09-01, and Victor was right about it: a
crosshair is the cursor for choosing a **point** — a colour picker, a region
dragged out — and this gesture picks up the thing under it whole. `grab` is what
every browser already uses for *this is something you can take*, so it says what
the outline is showing, in the one place the eye is guaranteed to be.

### ⌘⇧ has to be *held*

400ms, alone, with any other keypress abandoning the hold (`HOLD_MS`,
`poisoned`). ⌘⇧-click opens a link in a new tab and jumps to it; a quick one still
does, and only a deliberate hold arms the outline — the two gestures are told
apart by the one thing that actually differs, which is time. Every ⌘⇧ shortcut is
typed faster than the gate as well, so ⌘⇧T/⌘⇧N/⌘⇧R never arm it.

**The chord, not the ⌘.** It was bare ⌘ for an hour, which was wrong: ⌘-click is
how a link opens in a new tab, which Victor does all day, and one modifier is far
easier to hit by accident than two. Releasing *either* half ends the gesture, and
`poisoned` survives until the chord breaks — so ⌘C followed by reaching for ⇧
without letting go of ⌘ stays a shortcut rather than turning into a hold
halfway through.

Two more gates on top: with **no relay session running** the extension never arms
(it probes `/ping` first, so the gesture in a browser with no agent behind it
means exactly what Chrome says it means), and the same refusal covers **not
currently dictating**, which is now the common case.

Verified 2026-08-15, driving a test Chrome over CDP: plain click → page sees it;
chord-click under the gate → page sees it; chord held past the gate → swallowed
and picked; ⌘C first then held → page sees it; chord released → page sees it. And
against the relay directly: at rest `/ping` and `/pick` both answer 503 and
nothing is recorded; with the dictation flag set, both answer 200 and the pick
lands.

### The pick queue still survives a dictation opening

Unlike shots and the selection, `pendingPicks` survives `captureContext` — not
because picks can predate a dictation (they cannot any more; the gesture is dead
outside one) but because **Cancel puts them back**. A cancelled prompt leaves its
elements in the queue for the retry, and those legitimately predate the dictation
they end up riding, which is why the stamps can still come out **negative**:
`🎯 −0:08 …` means he pointed at it eight seconds before he started saying it
again. In the ordinary case every stamp is positive.

They go stale after 10 minutes (`pickTTL`) — a queue left behind by a cancelled
prompt he never retried is litter, not context. Nothing else clears it, so a
dictation whose transcript never arrives keeps its picks rather than stranding
them: `flushOrphaned` releases the *shots* on their own because a picture is
worth looking at unaccompanied, while a bare selector is nothing to act on.

**Cancel puts them back.** `releaseHeld(send: false)` returns the elements to the
queue — cancelling means the sentence was wrong, not that he pointed at the wrong
things, and re-taking a pick means finding the element in the page again, which
is the expensive half of the gesture. Shots are not restored: another one can be
taken blind, and the screen has moved on anyway.

### What a pick carries: the page, and what the thing said

Each entry of the outbox's `elements` is `{path, tag, text, label, href, url,
title, frame}` — built in `describe()` (`inspect.js`), re-read and clamped by
`ElementPick(json:)`, emitted by `ElementPick.json`. Nothing in that chain may
rename or drop a key: the `relay` skill documents them by name, and an agent
reading an old key it no longer gets is worse than an agent with fewer keys.

Two of them do the work Victor asked them to do, and both were wrong in a case
that is easy to hit:

- **`url` is the page, not the frame.** It was `location.href`, which inside an
  iframe is the iframe's address — and `frame` already carried that, so the page
  he was actually on appeared nowhere. `pageURL()` reads `window.top.location.href`
  and falls back to `location.href` when the top document is cross-origin and
  unreadable, which is the best true answer available there.
- **`text` falls back to `value`.** `innerText` is empty for `<input>`,
  `<textarea>` and `<select>`, which is exactly the case where a pick arrives as a
  bare selector with nothing in it to recognise. `elementText()` takes the
  rendered text when there is any, the selected option's label for a `<select>`,
  and the control's `value` otherwise.

### Why the row names the newest pick

`ElementPick.short` is the **tail** of the selector, for the same reason the tail
is what identifies it: the head is the page he is already looking at. The green
flash in the page is gone the moment he lets go of the chord, so this row remains
of the receipt for the rest of the sentence.

Built as a row with a separate glyph label, like the recording row. Not for an
animation (nothing pulses here) but because `measure()` is a font metric and both
🎯 and `×` fall back to faces the monospaced metrics know nothing about: inline,
the underestimate was ~2 characters, and AppKit ellipsized the count away.
`glyphRowWidth` asks the label via `sizeToFit` instead of asking the font. The
rows above tolerate the same error only because they never truncate.

## The selection is frozen for the whole dictation

The first non-empty read wins, and nothing overwrites it until the message is
sent or flushed (`stashSelection` bails when `pendingSelection` is already set;
`captureContext` clears it only when a *new* dictation opens). He talks for a
minute, another window jumps in front, he switches apps to look something up —
none of that changes what he is talking about. Later probes exist only to fill a
blank the first one left.

## A stale bundle in /Applications is three bugs at once

On 2026-08-28 all three of these were reported as separate faults:

- `⌘⌃D` no longer bound a terminal — macOS's "look up in dictionary" took it;
- Local Whisper refused to start with `cannot import mlx_whisper`;
- the menu bar showed an old glyph instead of the walkie talkie.

One cause: `/Applications/Walkie Talkie.app` predated three commits
(`e635128` its own ⌘⌃D, `584ecd2` the python probe, and the icon assets) while
the working tree was clean and at HEAD. Nothing on screen says which build is
installed, so each symptom looked like its own regression, and the ⌘⌃D one looks
exactly like an OS shortcut winning a fight — it isn't; **nobody was claiming the
key**, because Victor Addons had already given it up (see *⌘⌃D is this app's own
key*) and the installed relay had not yet taken it.

**Read the bundle, not the repo, when a fix "did not take".**
`find "/Applications/Walkie Talkie.app" -type f` is the whole diagnostic: a
Resources folder without `walkie-idle.png` dates the build older than the icons.
Source mtimes lie here — `build-app.sh` copies with `cp`, so every file in the
bundle carries the *install* time whatever its contents.

This is why the Quit row now carries a build stamp (below): the question "am I
running what I just built?" had no answer anywhere in the app.

## The app icon and the build stamp

- **The Finder/Spotlight icon is generated at build time** from
  `assets/walkie-bound.png` — the device inside its **orange ring**. It was the
  idle picture for two days, on the argument that the ring means "bound to a
  terminal right now" and an app icon is the same picture whether the relay is
  running or not. Victor reversed that on 2026-08-28 (*"iconul app sa fie cu
  cercul portocaliu in jur, ca originalul"*), and the argument does not survive
  the reversal: the ring reads as a *state* only in the menu bar, where the two
  pictures alternate in the same pixels. Nothing ever shows the app icon beside
  its own alternative — there it is the app's identity, and the ring is what
  makes it findable at 32px in a folder of a hundred icons. `build-app.sh` scales the ten iconset sizes with
  `sips` and calls `iconutil`, rather than committing an `.icns`, so the PNG stays
  the single source of truth and the app icon follows it on the next build. The
  bundle is `touch`ed afterwards or Finder and the Dock keep serving the cached
  old picture. (The app is `LSUIElement`, so this icon never appears in the Dock —
  Finder, Spotlight and Get Info are where it shows.)
- **`Quit — built Aug 28, 17:48`**, one row, the way Victor Addons does it: read
  once a session, and read while reaching for Quit anyway, since the answer to
  "no, that's the old build" is to quit and relaunch. The date is the
  **executable's own mtime**, not a constant stamped into the source: Addons seds
  a `BUILD_TIME` literal into a tracked Swift file on every build, which dirties
  the working tree and lands in commits as noise, while the file date says the
  same thing for free, cannot go stale, and works unchanged for a plain
  `swift build` run from the terminal.
