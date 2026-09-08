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
- `Self.shotHint` + `recordText` — the shots row (the drawn back button, then `+ selection`)
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
  `Connect Terminal` / `Disconnect` / `Start dictation to new claude` and their
  chords, which since 2026-09-02 ride a right-aligned column of their own, the
  three dictation rows, `Replace WisprFlow`,
  the `Take Screenshot` and `Pick Element in Chrome` legends, `Autosend`,
  `About`, `Quit`, and the model-name readout

The first two are **not on screen at the moment**: `showsGestureHints` is off, so
the rows are built and never shown. They still have to be English when the flag
goes back.

## The overlay's states are photographed, and the page is part of the change

`docs/overlay-states.html` shows **every state the chip and the panel can be in** —
36 of them — each with the moment it appears and why it looks the way it does. It
is generated: the catalogue, the order, the sections and every word of prose live
in `Sources/WalkieTalkie/OverlayStates.swift`, the pictures are the real views
drawing themselves through `RelayWindow.snapshot`, and `docs/build-overlay-states.py`
only lays them out.

**The rule: no change to the overlay is finished until that page is rebuilt.**

```sh
./docs/shoot-overlay-states.sh      # shoots all 36 states, regenerates the HTML
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

### The words, a blank line, then one clause per line (2026-09-07)

`AppDelegate.terminalLine` puts the dictation first, then a blank line, then each
bracketed clause on a line of its own. Victor's ask, and his reason: *"să fie
fiecare începând pe rând nou … să fie mai ușor de înțeles când mă uit eu pe
text"*. This envelope is read by **him** as often as by an agent — `⌘⌃P` pastes
exactly it and the Prompt Log shows it — and five bracketed clauses run together
behind the sentence is a shape you have to parse a sentence out of.

**It said *One line, always* until then, and that rule was half right.** Its
argument was that whatever carries the text ends with a Return, so an embedded
newline is an early submit that sends half the sentence. That is true of `\r`
and false of `\n`: in a TUI in raw mode `\n` *inserts* a newline, which is
exactly how Claude Code takes a multi-line prompt, and the submitting Return is
written separately by every delivery path here. It is the same distinction
measured when both IDE extensions were fixed for appending `\n` where a real
Return was meant — this rule was written from that bug and generalised one step
too far.

**Verified end to end before shipping**, because this is the path that fragments
a prompt if it is wrong. Bytes first, through a real `do script` into a
non-shell reader: `'fix the tax calculation\n'`, `'\n'`, one line per clause,
then the separate Return. Then into a **live Claude Code session**, which is the
question bytes cannot answer: it arrived as *one* prompt with the clauses on
their own lines and was answered once, not five times.

Two things it rests on, neither to be quietly undone. **The separators are `\n`,
and nothing here may send `\r`** except the Return that submits. And
**`TerminalBinding.escape` spells a newline `\n` for AppleScript**, whose string
literals cannot contain a raw one — without that the script does not compile and
the delivery disappears silently, with no error anywhere. `singleLine` still
normalises whitespace *inside* each line, so a transcript arriving with its own
breaks cannot fragment the sentence: the structure is the app's, never the
recogniser's.

The shots travel as **paths, not a `📸 ×2` count**:
the panel's preview is written for Victor, who needs only to know they landed,
while this is written for an agent, which can do nothing with a number and
everything with something to `Read`. `[selected: …]`, `[look at: …]`,
`[context: …]`, `[pointed at: …]` are the same split the outbox makes in keys,
and they are what replaces the skill, which is no longer there
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

### A terminal that was closed lets go of the binding by itself (2026-09-07)

The 10s tick that re-reads the bound window's name now also asks whether it is
**still there**, and lets the binding go the normal way when it is not —
`unbindTerminal`, the chip coming apart where it stood, exactly as the menu's
**Disconnect** and the right-held chord do. Victor's ask, and the whole of it:
*"dacă s-a închis terminalul la care ești bound, să te deconectezi de el normal,
dacă poți să afli"*.

The check already existed and ran in the one place it is too late to be useful:
`deliver` finds the target gone, drops the binding and flashes a warning — i.e.
**after** a sentence has been spoken at a window that stopped existing minutes
ago. Everything up to that point behaved as though there were somewhere for words
to go: the chip named the dead session, the wheel and mouse 4 stayed borrowed
(*Unbound is inert* is keyed on `isBound`, and the binding was still there), and
the status line kept its microphone.

- **`TerminalBinding.checkAlive()` answers three things, not two.** Unbinding is
  not free — it is the thing Victor pointed at something to get — so *I could not
  ask* must never be spelled the same way as *it is not there*. `.gone` is
  returned only on a definite answer, `.unknown` on silence, and `.unknown` does
  nothing at all.
- **A Terminal.app tab is tested on *any* process on its tty, not the foreground
  one.** That is deliberately the weaker test, and it is the difference between
  this and the delivery guard: `foregroundCommand` answers nil for a live tab
  whose processes all happen to be backgrounded, where it costs one refused
  delivery that says so out loud — here it would cost the binding, silently,
  while he is not looking. A tab that is still open has a shell in it.
- **tmux is asked about the pane, never the tty**, which is the outer Terminal
  tab and outlives a pane closed inside it.
- **An IDE target is two questions.** The editor having quit is definite and free
  (`NSRunningApplication` on the target's bundle id). The panel itself is
  `IDEBridge.alive`, and only a listener that **answered** `ok: false` may take
  the binding away — an extension host mid-reload answers nothing, which is
  `.unknown`.
- **Not while a sentence is in the air.** `listening || held != nil` skips the
  check: the delivery asks the same question a beat later and answers it with the
  words still in hand. Handing the wheel and the microphone back from under a
  dictation in progress to save ten seconds is a bad trade.
- **It lets go quietly**, without `report(.targetGone)`'s six-second warning.
  Nothing was lost here, and a panel announcing the tidy-up of a window he closed
  himself would be the app reporting his own action back to him.
- **The tty can be reused by the next tab**, so a binding can still survive its
  session by pointing at a stranger. That is unchanged and out of this check's
  reach — it is the same hole delivery has always had.

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
| `POST /test/spawn-folders` | put the folder menu up on its own — the three seconds of that gesture no fabricated transcript passes through |
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
| `plusOneShot` — mouse 4 | off |
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
| the dictation was cancelled | `🗑️ Dictation aborted` in the row `Listening…` was in — 1.5 s, swept in and swept out again by the oblique line (*The oblique wipe*). The 🗑️ came back on 2026-09-02: it was dropped while a flash still drew the lone 🎙️ title row above it, where Apple's lid-flying-off bin read as a second glyph on a two-glyph line; that row no longer appears under a flash, so the bin is the row's only picture |
| dictating in Replace Wispr | the drawn map pin + `at the caret` — the same slot a spawn takes, and for the same reason |

**Dictating no longer has a title of its own.** It used to be `🎙️ …` with dots
cycling 1→2→3→1, and there was a glass-shine sweep every 5s to go with it. All of
that has moved into the recording row: the top line now stays `🤖 folder@branch`
through the whole dictation — that is the fact that does not change — and what
does change lives one row down.

The liveness those animations provided is still load-bearing, and is now the
pulsing 🔴: a frozen recording row is indistinguishable from a hung app, and the
entire point of the state is reassurance that speech is being captured.

## The recording rows

While dictating, the state rows sit **above** the destination, one glyph column
and one text column:

```
🔴 Listening…                       ← something is listening
[Terminal] petclinic@main           ← and this is where the words go
[chrome] — ⌘⇧+click to select element
```

**The pulse takes the microphone's place, since 2026-09-07.** At rest the top
row is a lone 🎙️ — the chip *being* a microphone is the whole sentence
(`collapsed`). Starting to talk used to leave that slot to the destination and
push the pulse underneath, so the one row that *changes* arrived below the one
that does not, and the top line went from a microphone to a folder name at the
exact moment the microphone became true. Now it goes 🎙️ → `🔴 Listening…` in
place and `petclinic@main` slides to the second row. Victor: *"aș vrea ca
listening cu bila roșie să înlocuiască microfonul — să fie primul rând, iar
terminalul conectat să fie al doilea"*.

The waits go with it — `⏳ Transcribing... 4s` is the same slot at the next moment
(*"la fel în toate"*). The spawn is unaffected: `spawnCollapsed` already drops
the destination row and rides ✨ in front of `Listening…`, which is this order
with the second row taken out. **Only the chip.** The held panel keeps its title
first: it is parked in a corner and read whole, and *where these words are about
to go* is what a panel with a Cancel button on it opens with.

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

### `Listening...` is a progress bar, and it fills on speech (2026-09-07)

The word beside the pulse is drawn one character at a time: dim characters ahead,
lit characters behind, full when the last dot lights. Twelve steps —
`RelayWindow.listeningWord`, and **three full stops rather than `…`** so the tail
is three of them rather than one glyph taking a quarter of the bar in one step.

It is a **forecast about the transcript**, not a measurement of this recording:
it knows how much speech has arrived, not what is in it.

#### It was a fade first, and the fade was the wrong instrument

For one afternoon the whole row dissolved from dark grey to full over six
seconds. Victor: *"nu e suficient de vizibilă … așa fade, nu înțeleg când e
aprins complet"*. He is right, and the reason generalises: **brightness is judged
against what is beside it**, and this row spends its life over a terminal, an
editor, a photograph — so *is it fully lit yet?* was a question about a grey with
nothing to compare it to, asked mid-sentence in peripheral vision. Twelve
characters filling one after another turn the same number into a **count**: it is
done when there are no dim letters left, which is a fact about the row itself.

Binary per character, not a per-character gradient — a gradient would be the same
complaint again, in twelve places.

#### It counts voiced seconds, not elapsed ones

*"Uneori eu pur și simplu tac. Dacă tac pe microfon și nu vine semnal, nu știu
cât de valoroasă e întârzierea asta."* — and the corpus is emphatic: the median
dictation is only **38% voiced** (p10 14%). Six seconds of wall clock is 2.3
seconds of speech on an ordinary sentence and 0.8 on a thoughtful one, so a
clock-driven bar filled while he was thinking and told him the one thing it
exists not to.

`MicRecorder.voicedSeconds` is the source. Re-bucketing by it turns a slope into
a cliff — these are the **local model's own** language picks, from re-decoding
803 clips (`evals/short-clip-lid.md`):

| voiced | decoded into a language Victor does not speak |
|---|---|
| 0–1s | **42%** |
| 1–2s | **15%** |
| 2–3s | **1%** |
| 3–4s | 2% |
| 4s+ | **0%** |

against 50% / 28% / 19% / 2% / 0% at one, two, three, four and five seconds of
*wall clock* — the same failures, sorted by the thing that actually causes them.

⚠️ **The first version of this table was wrong, and the way it was wrong is worth
keeping.** It read the language off `detectedLanguage` in `corpus.jsonl`, which
is **Wispr Flow's** pick, not this model's — `corpus_harvest.py` copies Wispr's
row wholesale (`asr` is `r["asrText"]`, and its own docstring says *"No model
runs here and none is called"*). So a column that looked like evidence about the
local recogniser was evidence about a different one, and it understated every
figure by about three times. The **shape** survived — short clips fail
catastrophically, the cliff is real, the threshold below is right — but nothing
in that manifest describes what this model does, and `asr` is not a second
opinion to score against: it disagrees with `text` at median WER 0.008 because
they are two fields of the same Wispr row.

The cause is `language=None` in `whisper_helper.py`: the model picks a language
off its 30-second window before it decodes a word, and with a second of speech in
that window the pick is a guess. A wrong pick is not a wrong word — it is
`Teşekkür ederim.`, `É bom ir o outro dia? Ai, que acessou tudo?`, `안녕하세요.`,
`Thank you.`, all on Romanian or English speech. **That lever has since been
pulled** — see *The recogniser* — so the bar now forecasts a failure the
recogniser no longer has, which is the right time to say what it is still for:
everything else that is worse when there is less to hear.

**Full at three voiced seconds** (`RelayWindow.enoughSpeech`): the first bucket
where both failure modes are at their floor. About fifteen words at his measured
5.1 words per voiced second, and about eight seconds of ordinary talking — which
is where he put the boundary by feel, *"dacă vorbesc peste 5–7 secunde,
transcripția e mult mai calitativă"*, five to seven seconds of his speech being 2
to 2.7 voiced seconds.

#### The meter

`MicRecorder.meter` runs on the converted 16 kHz mono buffer — the same audio the
model and the corpus see, which is what makes its constants transferable from the
corpus replay that set them (`evals/voiced-seconds.py`). Per 1024 frames (64ms):
RMS against an adaptive noise floor, **9 dB** over it to count as speech, with an
absolute floor of 180 underneath.

- **Adaptive, because a fixed threshold cannot work here** — and `InputDevice`
  already wrote down why: measured in the same room, the DJI receiver peaks at
  16552 where the built-in microphone manages 855. One number would call the
  built-in silent all day or the receiver's room tone speech.
- **Instant attack down, 2% release up**, the standard cheap noise tracker: it
  settles into the gaps between his words rather than into his words.
- **The absolute floor is for the case the adaptive one cannot see**: a recording
  that is *entirely* room tone has a noise floor equal to its own content, and
  every buffer would clear a purely relative bar.
- **Reset per recording**, both of them: a floor carried over is a floor for a
  room, a microphone and a distance that may all have changed.

#### Two implementation traps, both paid for

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
  at once.

`pinListenWarmth(_:)` freezes a frame for `OverlayStates` alone — the shutter
fires immediately after `apply`, so without a chosen frame every dictating state
on the page would be a photograph of its own first 200ms. `reset` pins the full
bar; `listening-cold` and `listening-warming` pin their own.

#### The wait fills too (2026-09-08)

`Transcribing... 4s` is drawn the same way, on Victor's ask — *"la fel vrea să
colorezi transcribing, să-l colorezi de la întunecat la mai aprins, ca pe post de
progress bar"*. Same instrument, pointed at the one wait that has a **deadline**:
`DecodeRate` has already promised a number of seconds, so unlike the dictation
there is a real fraction to draw, and the row was already counting it down in
digits. The bar is that countdown said in the way the eye reads without stopping.

- **The word is the bar; the seconds are a readout beside it** and stay lit
  throughout. Their character count *shrinks* as the number falls, so a ramp over
  them would run backwards at every digit boundary.
- **`Transcribing...`, three full stops**, for `Listening...`'s reason: an
  ellipsis is one glyph and would light in one step.
- **Fifteen ticks a second, and only the digits are worth a relayout.** They
  change the row's width, so they go through `layoutContent`, at most once a
  second; the ink changes no geometry, so it is written straight onto the label —
  `startWarmth`'s bargain, and this loop must never re-measure every row on the
  chip sixty times a decode.
- **The ✨ goes in as a picture here too.** This row was still putting a raw emoji
  into an attributed string on a label carrying a halo, which is the failure
  written down two sections up — so a *spawn* dictation's wait was one mark and no
  word at all. Fixed with the same `inline(Glyphs.emoji(…))` the listening row
  uses.

**The lever named here has been pulled.** Restricting language ID to `{ro, en}`
took the wrong-language mode to 0% in every bucket, measured on the same 803
clips — see *The recogniser*. The bar stays: it forecasts short-clip quality in
general (a two-word clip is still a clip with no context in it), and the language
pin only removed the most spectacular of its symptoms.

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

## The wait is icon-sized, and it was the colour that mattered

`transcribing…` (the model chewing) is the only state left in which Victor is
**waiting on this app**. `preparing` (the model coming up) was the other one, and
since 2026-09-06 it does not exist on the chip at all — see *The model loads at
launch*. For two days the pair of them bought their hourglass 30pt — `hintInk`,
nearly twice the size of every other glyph on the chip.

They were icon-sized, in `secondaryLabelColor`, on a bare chip: half-transparent
dark grey with no halo, over the dark terminals and editors the chip spends its
life on. **Exactly the bug the selection row had** — the row was there and could
not be seen — and the question being asked is *is it still doing something?*,
asked from wherever he has already looked away to.

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
render the 16pt `send` / `transcribing…` states at 22.

The `send` row, the shot-hint row (`.back`) and the ⌘⇧-pick hint (`.left`) use the
same drawings at icon size: those rows say what they mean in words, so the picture
only has to identify the device.

## The shutter and the ⌘⇧ pick are two gestures, and they cannot collide

They are borrowed from the same dictation and they arrive in the same message,
so it is worth writing down that nothing routes one into the other. The shutter
(mouse 4 while dictating) takes a **picture plus whatever is highlighted at that moment**;
⌘⇧-click in Chrome takes a **path to a DOM element** and no picture. Neither is a
fallback for the other, and Victor asked for them to stay that way.

**The ⌘C probe cannot poison an armed pick**, which is the one interaction the
two could have had since the shutter started paying for the clipboard fallback.
`inspect.js` treats any keydown during a ⌘⇧ hold as proof the chord is a
shortcut and abandons the arm — but **both shutter routes require no modifiers
at all**: mouse 4 asks for `bare` (`HotkeyTap`). With ⌘⇧ held, it never fires,
so there is no press that could post a ⌘C into a hold. Do not relax that gate
without re-reading this. (F3 was the shutter's keyboard route until 2026-09-04,
when it went unused one year too many.)

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
overlay is that he is *away from the keyboard*. F3, the keyboard route this
button replaced, was removed on 2026-09-04 — never pressed in a year of use.

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

**Tap order does not decide this any more, and that is deliberate.** Both apps
use `.cgSessionEventTap` at `.headInsertEventTap`, where the most recently
installed tap sees events first, so whoever restarted last is ahead. That used to
be the relay, because LinearMouse started at login and the relay started per
session. It stopped being true on **2026-09-07**, when LinearMouse was
uninstalled and **Victor Addons** took the mapping over natively
(`BackButtonEnter.swift`): that app is rebuilt and restarted after every change to
it, which is often, so it is routinely the newer tap. On 2026-09-08 it was —
relay up since 22:14, addons since 22:37 — and every press became a Return before
this tap saw a mouse button. The shot silently stopped, and the Enter landed in
whatever was in front (in Chrome, it scrolled the page).

The branch that catches the Return was already there; what it could not do was
tell *that* Return apart. It matched the source pid's process name against
`LinearMouse`, and a name cannot work for Victor Addons, which posts Returns for
its own reasons too (`KeySimulator`) and those genuinely mean Enter. So the one
Return that is a button in disguise now carries a stamp in
`eventSourceUserData` — `backButtonStamp`, `0x7774_4241_434B_0000` — set by
`BackButtonEnter.post` and read here. **The literal is duplicated across the two
repos and must not drift.** Restart order is now irrelevant: whichever tap is
first, the shot is taken exactly once.

## The shot's name is *when in the sentence* and *where the mouse was*

`shot-01:23(mouse-at-1034x1466px).jpg` — taken 1m23s into the dictation, pointer
at x=1034, y=1466 in **the pixels of that image**, top-left origin like the image
(`ScreenCapture.stem` + `tagCursor`).

Both halves answer a question the sentence alone cannot. He points at things
while he talks — "this button", "that line" — and he takes several pictures
across a three-minute dictation, where `📸 ×4` is four indistinguishable files
and `0:00 · 0:38 · 1:52` is a table of contents. The prompt panel already lists
them by offset (`AppDelegate.shotStamps`, written across each thumbnail); the
name is that same reading put where
the agent meets it. They ride in the **name** rather than in new outbox fields
because the name is already in front of the agent: the path travels in `paths`,
so both facts arrive with the picture and nothing downstream learns a new key.

**`00:00` is the automatic context shot**, by definition — he took it by starting
to talk. A shot with no dictation around it keeps a timestamp instead:
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

Mouse 4 while dictating records **what is highlighted at that moment**, stamped with the
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

**The chip says `“ selecting <his own words>` for 2.5s** and then settles to
`“ ×N …`.

**The mark is the panel's, shrunk** (since 2026-09-02, Victor's ask). The row led
with `↪`, an arrow — *this came from somewhere*, where what has to be said is
*these are somebody else's words*. It is the same fact the panel sets as a
quotation one state later, so the two now look like each other: 26pt bold at
`-6`, against the panel's 30 at `-7`, and the row is 28 tall rather than 22 to
hold it. **19pt was tried first and read as a superscript**, which is the whole
change failing quietly. It is the row's *glyph*, not a second size of text, which
is what keeps it inside the one-face-one-size rule.

**And it is built, never assigned.** An attributed string outranks `textColor`,
so `refreshChrome`'s white-with-a-halo switch would do nothing to it —
`applySelectionText` reads the ink off the label and both callers come through
it. That is the same failure this row already had once, written down two
paragraphs below. **The receipt is not behind the novelty test, the filing is**: two of
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
was, for ~2s — on the automatic capture that opens a dictation and on every
back-button shot alike, since both go through `announce(cursor:)`. **`CursorMarker` no longer
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
retaken on the spot.

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
- **Loaded at launch, released when the session ends** (since 2026-09-06, on
  Victor's ask). It used to wait for one of the two gestures that mean a
  dictation is coming — ⌘⌃B binding a terminal, or a wheel hold on a model that
  is not up — on the argument that the weights are 1.5 GB resident
  (**measured: the relay alone is 56 MB, the helper 2.5 GB once a transcription
  has run**) and the ordinary case is a relay sitting in the menu bar all day
  with nothing bound. That traded the wrong resource: the relay is a **login
  item**, up before Victor is, so the ten seconds are free at launch and were
  instead being charged, every day, to the first sentence he said.
  `applicationDidFinishLaunching` calls `startWhisper` now. **The two gesture
  call sites stay** — `startWhisper` is idempotent, and they are what retries a
  launch load that failed (no `mlx_whisper`, most likely) instead of leaving the
  relay deaf until it is restarted. `RELAY_SHOOT` is excluded: that run draws
  the state pages and quits.
- **A wheel hold that has to wait for the model opens the microphone itself.** On
  a cold model that intention was costing ten seconds of waiting followed by a
  gesture he had to remember to repeat. `recordWhenModelReady` is set only when
  the **hold** asked for the load: a load started by a bind is Victor pointing the
  relay at a terminal, a different sentence, and must not open the microphone.
- **The wait says how long, not only that it is waiting** (since 2026-09-02).
  `Transcribing... 4s` counts down from the audio's own length × a factor, and the
  rounding up is deliberate: over is a pleasant surprise, under is a number that
  is wrong every second it is on screen.

  **The estimate is a line fitted to the last fifty decodes**
  (`DecodeRate.swift`). Every decode files the audio it was handed, the seconds
  it took and the machine's load at the time, and the next prediction is
  `intercept + slope × audio` off that window.

  **It was a mean ratio until 2026-09-07, and the filter around it was throwing
  away the truth.** Reported as *"secundele estimate … sunt mereu grav
  supraestimate, 14 secunde și s-a terminat în 3"*, and the cause is written in
  `relay.log` by the old code as it discarded the evidence:
  `ignoring 0.033× (45.5s audio, 1.5s decode) — outside 0.04…0.60`. **Nineteen
  such pairs**, 22s to 207s of audio, every one of them warm, every one rejected
  for being *too fast* — the floor was 0.04× and this Mac decodes at 0.033×.
  What survived in the window were short clips and the odd cold decode (ratios
  0.05…0.48), so the mean sat near 0.15 and a two-minute dictation was promised
  twenty seconds for four seconds of work. A guard written to keep nonsense out
  was keeping every representative sample out and nothing else in.

  **A line rather than a ratio**, because a decode is a fixed round trip (JSON
  out, ffmpeg, the answer back) *plus* a cost per second of audio, and one ratio
  can fit one of those or the other. Least squares over those nineteen pairs is
  `0.0355 × audio − 0.10`, worst residual **0.39s across the whole range** —
  exact, once the line is allowed an intercept. Predictions now: 45s→2s (1.5s
  actual), 90s→3s (3.3s), 207s→7s (7.5s).

  **The load is recorded and deliberately not in the model.** Victor asked for it
  by name — *"loghează … câtă încărcare are mașina și cât a durat efectiv"* — and
  that is its job: it sits in the file so a better rule can be *derived* later
  instead of guessed at now. The fit does not use it because the recent decodes
  already are the machine's load, measured end to end on the resource that
  matters.
  - **The file is `~/.walkie-talkie/decode-rate.jsonl`, appended forever**, one
    object per decode: `{at, audio, decode, load, cold}`. Beside the outbox and
    not in Caches, for the outbox's reason. The estimate reads only the tail.
    It supersedes `decode-rate.json`, which held bare ratios with **no audio
    beside them** — which is exactly why this fault could only be diagnosed from
    `relay.log`, and only from the lines about the samples that were *dropped*.
    The file was seeded from those log lines when the fix landed, so the fit was
    right on the first dictation after it.
  - **The first decode after the helper starts is recorded but not fitted.** The
    helper warms up on a second of silence, but the first real decode still pays
    for weights the allocator has not touched — 2.8s against 1.3s warm, and
    visible in the log as a 4.3s clip that took 7.3s. `LocalWhisper.stop()`
    resets the counter, so the next helper's first is cold again.
  - **Ratios outside 0.005…1.0 are not fitted to** (they are still written down).
    Wide on purpose, after the old 0.04…0.60 excluded reality: what is left out
    is only a reply that came back in no time at all, and one that took longer
    than the sentence did to say.
  - **A fit needs spread, not only points.** Below eight samples, or with less
    than 15s between the shortest and longest of them, the window is used as a
    **median** ratio through the origin instead — least squares asked about
    clustered points answers with a line through noise, and a median is what
    survives one cold decode where a mean does not. With nothing at all the
    fallback is `0.3s + 0.045×`, which is the measured line rounded up on both
    terms.
  - Filed on the **success path only**: a decode that returned nothing says
    nothing about how long a decode takes. At zero the seconds stop
  being shown rather than sitting at `0s` or counting up, which would be the app
  insisting on a promise it has already broken.
- **⏳ in the menu bar only, and nothing beside the cursor.** The load has had
  three narrations on the chip over its life: a flash, then an hourglass on the
  folder name, then a `Preparing…` row of its own — and for a while two of them
  at once, which is what Victor actually saw the day the right-held chord let him
  load the model unbound: *"2 mesaje de preparing, unul mare unul mai mic"*. All
  of them are gone as of 2026-09-06, and the reason is not layout: the load runs
  at **launch** now, so there is nobody waiting on it to tell. What is left is
  `⏳🤖` in the menu bar and `<model> — loading…` in its menu — free space, the
  half that survives him typing (macOS hides the pointer, and the chip goes with
  it), and the only way to see the load is still running if he goes looking.
  `AppDelegate.setEngineLoading` is now a one-liner into `StatusItem`.
  `StatusItem.refreshGlyph` still arbitrates the glyph, though ⏳ is the only
  badge that ever claims it — ⏸️ shared the slot until pause was removed.
- **An empty result says `No words detected`, and nothing else** (2026-09-08,
  Victor's ask). It read `⚠️ the model returned nothing — that dictation is
  lost`: three sentences where one is a fact. What the recogniser did with the
  audio is the app's business, and *that dictation is lost* names a loss he can
  do nothing about — while *nothing was heard* is the one thing he acts on, and
  it already says what to do about it.
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

### The language is pinned to {ro, en}, and the prompt carries his vocabulary (2026-09-07)

Two decode settings, both measured on **803 of his own clips, 3212 decodes, four
configs** — `evals/short-clip-lid.md`, and read it before touching either.

**A** = `language=None` (what shipped until now). **B** = argmax over `{ro, en}`
of the model's own LID. **C** = B plus a 65-token vocabulary prompt. **D** = A
plus that prompt, so the two halves could be attributed separately. **C is what
ships.**

#### B — the language pin removes an entire failure mode, for free

Wrong-language decodes: **3.2% of all clips, 19.3% under 5s, 50% under 2s → 0% in
every bucket.** These are not near misses — a whole sentence of Turkish or Korean
made out of Romanian speech, which is the one failure an agent cannot defend
against, because nothing about the text looks wrong.

It costs **−22 ms**, i.e. it is faster. `transcribe(language=None)` already runs
that exact encoder pass internally to pick a language; pinning only *relocates*
it, and `detect_language` hands back the full distribution over all 99 codes, so
restricting the argmax needs no second pass and no tokenizer surgery:

```python
model = ModelHolder.get_model(MODEL, mx.float16)   # the cache transcribe() uses
mel   = A.log_mel_spectrogram(samples[:A.N_SAMPLES], n_mels=model.dims.n_mels, padding=A.N_SAMPLES)
mel   = A.pad_or_trim(mel, A.N_FRAMES, axis=-2).astype(mx.float16)
_, probs = model.detect_language(mel)
language = max(("ro", "en"), key=lambda c: probs[c])   # ← the whole change
```

`pick_language` returns **None** on anything unexpected, which falls back to
Whisper's own unrestricted pick. A helper whose job is to answer must not stop
answering because a library moved a symbol.

#### C — the vocabulary prompt is the bigger win, and it is not free

Recall on the prompted identifiers, over their 490 occurrences in the reference
transcripts: **0.67 → 0.88**. `Claude` 0.33 → 0.85 (without it the model writes
`cloud`, `claw`, and turns `CLAUDE.md` into `CloudMD`), `frontend` 0.10 → 0.70,
`petclinic` 0.00 → 0.60, `backend` 0.44 → 0.92, `IntelliJ` 0.59 → 0.88. Median
WER under five seconds 0.300 → 0.222. **This is the metric that matters** — a
mangled identifier costs the agent everything, a wrong verb ending costs it
nothing.

**Every term is attested in his own transcripts.** `Devoxx`, `repo` and `VS Code`
were guessed at, checked (0, 1 and 2 occurrences) and thrown out. A prompt is
capped at 224 tokens and attention weights its tail hardest, so it is a short
list of things that actually break — not a glossary.

**The cost is real and it cuts both ways.** Against A: 7.0% of clips improved by
more than 0.1 WER, **4.7% got worse**. The prompt biases *toward* its own words,
so `clone` and `cloud` both come out `Claude` on a clip that says neither —
visible in the very first smoke test after it landed. The trade is net positive
and it is a trade, not a free win.

**Nothing changes past 12s** — median WER 0.167 and rare-word recall 72% in all
four configs — because `condition_on_previous_text=False` makes `transcribe` drop
the prompt after the first window. Both settings are short-clip medicine.

#### The loop gate is the price of C, and it was already in the file

`Transcriber.Result.compressionRatio` has been parsed since the helper was
written and read by nothing. It is read now, at **2.4** (`loopCeiling`), because
the prompt costs repetition loops — `af af af af…` four hundred times, which
gzips at 39 where prose sits near 1.5.

Of the 38 clips C made worse, the **12 catastrophic ones are caught by this, all
twelve**; the 26 it misses are worst-case +0.44 WER. It fires on **none** of the
802 clips whose transcript was fine — zero false alarms, which is the only reason
it can be shown to Victor at all.

**`avg_logprob` cannot do this job**: it caught 2 of the 14 loops, and the reason
is structural rather than a threshold that needs moving — **a loop is
*confidently* wrong.** The decoder is not hesitating between `af` and something
else, it is certain, over and over, which is what a high average log-probability
describes. Two numbers, two failure modes, neither a substitute for the other.

**It warns; it does not swallow.** Same rule the confidence floor already
follows, for the same reason: there is one reading of this audio and silence is
the one outcome Victor cannot notice and correct.

#### Where the worst of it actually lives

Every one of the top regressions is a clip with **almost no speech in it** —
`you` (1.3s), `VoxxedDays.` (0.6s), `5 minutes.` (1.7s). Whisper is being asked
to transcribe something that is mostly padding, and A's answer there was a
harmless `Thank you.` where C's is four hundred `af`. The literature's standard
answer to this is not a better prompt, it is **not calling the model at all** —
VAD-gate the clip and return empty. `MicRecorder.voicedSeconds` is already that
VAD; nothing gates on it yet, and that is the obvious next move rather than a
done one.

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
relay drives `MicRecorder` from the **wheel**. **A 0.6s hold on it means a new
session, since 2026-09-04** — see below; a plain click is still nobody's, and is
handed back.

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
| bound, any state | **right button down, then click the wheel** | **disconnect** — same call as the menu's Disconnect |
| anywhere, any state | **right button down, then the wheel held 1s** | dictate at a terminal that does not exist yet — ⌘ + the wheel, without the keyboard |
| bound, not dictating | **click twice** | the dictation the first click started **becomes** a spawn — new session, folder menu on the second click |
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

### Double-clicking the wheel turns the dictation into a spawn (2026-09-05)

The side-button holds are dead, and the evidence killed them. The forward
button first: measured on presses Victor was deliberately holding, it reaches
the tap as an ~18ms down-and-up pair however long the finger stays on it — and
`CGEventSourceButtonState`, asked directly, *agrees*: `physical=true` at the
down, `physical=false` 20ms later, finger still down. Something between the
mouse and this tap — the Bolt receiver, Logi's agent, or Wispr Flow's
push-to-talk, which lives on that button — throws the duration away at the
hardware's own layer. The back button got the hold for an afternoon on the
hypothesis that it might be the one button not intercepted; Victor gave up on
the whole circuit before the experiment finished: *"let's give up on that,
remove that circuit, and instead let's go for keeping the wheel held down."*

**The wheel hold that replaced it lasted exactly one day and never fired once.**
*"holding wheel does not seem to work"* — and unlike the side buttons, this one
was ours, not the hardware's. `relay.log` has no `🎙️✨ wheel held` in it at all;
what it has, every time, is `🗑️ wheel held while dictating — cancelling it`.
The button had two holds on it and they were not separable in the hand:

- **The two holds were the same length** — `cancelHoldSeconds` and
  `spawnHoldSeconds` were both 2s — and told apart only by *the state at the
  press*. A wheel he pressed, held, and went on holding past the moment the
  dictation came up read as the cancel on the very next press, which is what a
  finger that has just been told "hold it longer" naturally does.
- **The spawn timer additionally guarded on `dictating`**, a flag the tap only
  learns from `syncBorrowedGestures` once the recording is up — which on a cold
  model is ten seconds after the press. The one path where the hold mattered
  most was the one where the guard was still false when the timer fired.

A second duration on a button that already has one, arbitrated by a flag that
arrives late, is not a gesture. **A second click is.**

**The bare wheel now carries the spawn as a double click**, and still as a
conversion rather than a gesture of its own. The first click starts a dictation
at the bound terminal, exactly as it always has — the microphone opens at the
press, so the chip appears under his finger. Click again inside
`spawnDoubleSeconds` (0.6s) and the dictation *in flight* turns into a spawn:
`spawnPending` flips, the chip grows the ✨ mark, and the folder menu opens on
the second click. Same words, same recording — only the destination changes,
which is exactly the rule *A bind mid-sentence changes the recipient* already
runs on. Since 2026-09-06 it is the **only** gesture for a spawn — ➡️ + 🛞 held a
second is gone — with the menu's **Start dictation to new claude** as the
discoverable route beside it.

- **The double click is judged before `dictating` is consulted** — deliberately,
  because consulting it first is what killed the hold. The test is
  `wheelDictateAt`, a stamp only *the bare wheel opening a dictation* sets, so
  no chord and no cancel can be doubled into a spawn, and a cold model converts
  as readily as a warm one.
- **A cold model converts too**, therefore — rarer since the weights load at
  launch, but still reachable in the first seconds after login, or when the
  launch load failed and a gesture is retrying it. The first click banked the gesture
  in `recordWhenModelReady` and is waiting on the weights; the second lands
  half a second later, sets `spawnPending`, and the resumed start reads it —
  which is why the handler accepts `localRecording || recordWhenModelReady`.
  The folder menu opened by the second click survives, because a resumed start
  is `resumed: true` and skips its own offer (see *the modal must not be
  offered twice*).
- **The second press is swallowed and left unclaimable.** It sets `wheelArmed`
  (so the app underneath never sees a middle-up without its middle-down) and
  clears `wheelDown`, which makes `tapped` false at the release — otherwise the
  click that re-aimed the dictation would immediately end it.
- **The context shot still waits for the release** — Victor's refinement from
  the day before: *"you could take the screenshot when I release the mouse."*
  The bare wheel starts the recording without `captureContext`
  (`deferContext`), and the first release takes it, so the picture is of the
  screen his finger left rather than the one it landed on. The audio's zero
  stays the press, so shots are named by their real offset. Every other route
  in (⌘⌃D, the menu, the chords) still captures at the press.

**It also works with nothing bound at all — added 2026-09-06**, the same day
Victor reported the gesture doing *nothing* at rest. Two things were in the way,
and only the first was in this repo's control:

- **The ChatGPT bar was eating it.** `victor-macos-addons` had its own
  double-wheel-click detector, which synthesized ⌃⌥Space — the ChatGPT desktop
  app's `toggleLauncher` shortcut. Two event taps cannot share one gesture, and
  that one fired visibly. It was removed there (`caa3ffe`), taking
  `KeySimulator.simulateCtrlOptSpace` and `otherMouseUp` off that tap with it.
- **This tap wasn't claiming the button either.** The conversion branch is gated
  on `localCapture || dictating`, and `localCapture` is `isBound` — *"with no
  destination there is nowhere for a transcript to go"* (`syncLocalCapture`).
  That premise is **false for a double click**: it brings its own destination, a
  session that does not exist yet. So a second branch handles the unbound case
  and calls `startLocalRecording(spawn: true)`, which is already built to walk
  through that gate — it sets `spawnPending` *before* `hasDestination` is read.

The unbound half is deliberately **not** symmetrical with the bound one: the
**first click is passed through, not swallowed**. Unbound, this app has no claim
on the middle button — the argument that took ⌘ + wheel away on 2026-09-03 —
and holding every middle click on the machine on the chance a second follows
would cost every middle-click-to-open-a-tab in Chrome. A lone click therefore
leaves nothing but a timestamp (`idleWheelClickAt`); only the second one inside
`spawnDoubleSeconds` is taken. The price is exact: a *deliberate* double middle
click on a link opens one background tab. The second press is swallowed the same
way as in the bound case (`wheelArmed` set, `wheelDown` cleared), and carries
`wheelHeldFromPress` so its release still takes the context shot — the first
click having gone to the app underneath.

Verified end-to-end on a cold model with synthesized middle clicks (log,
2026-09-06): `🎙️✨ wheel double-clicked at rest` → `wheel clicked with the model
down — bringing it up now` → 7s of weights → `model up after a press that had to
wait — opening the microphone` → `context screen captured`. A single click in
the same state logs nothing, which is the pass-through working.

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

### The right chord means one thing again (2026-09-06)

**Right held, then the wheel held, used to open a session instead of closing
one** — from 2026-09-01, when ⌘ + the wheel was still the other way in and the
argument was that ⌘ is a *key*, which is what Victor does not have to hand across
the room from the laptop. Victor took the second reading out on 2026-09-06.

What it cost is what the two readings always cost: the chord had to be told apart
from itself. **Disconnect could not fire until the finger came up** (a press that
unbound and then spawned a second later would do both — an unbind burst over a
binding the spawn was about to replace), and a tap made in a hurry was one timer
away from opening a session nobody asked for. The spawn meanwhile kept two routes
that need no chord at all — the bare wheel **clicked twice**, and the menu row —
so the hold was buying a third way in at the price of the mirror gesture's
directness.

**So the disconnect is judged at the press again**, like the left chord: one
reading, no timer, and the unbind burst goes off under the finger that ordered
it. `wheelRightChord` went with the hold — there is nothing left for the release
to disambiguate. The press is still swallowed either way (`wheelArmed` claims the
release with it), so a right-held wheel click never falls through to the bare
wheel below; with nothing bound the chord is simply inert.

**Right held, then the wheel, lets the binding go** — also since 2026-09-01. It is
deliberately the *mirror* of the rebind chord: one button held as a modifier, the
wheel clicked on top, judged at the press. Left points the relay at something;
right takes it back. Nothing has to be learned twice.

### The right chord has no hold to wait out (2026-09-04)

It was judged against `chordHoldSeconds` like the left one, and that threshold was
a bug rather than a symmetry. Right-press then wheel are two halves of one quick
motion, and they land inside 0.3s often enough that the press fell through every
chord branch to the bare-wheel one at the bottom of `HotkeyTap` — opening a
dictation **at the terminal already bound**, which is the one destination the
gesture exists to get away from. Doing it again more slowly "worked", which is
exactly how a timing threshold feels from the outside. Reported 2026-09-04:
*"the tool thinks I want to dictate to the existing bound terminal … if I repeat
it a bunch of times, I make it work eventually"*.

The threshold was borrowed reasoning. It earns its keep on the **left** chord,
where a click-drag with the wheel pressed on top is a real thing to rule out.
Nothing is like that on the right: there is no right-drag anyone finishes with a
middle click, so the button being down at all is already the entire signal.

**And `rightIsHeld` now asks the window server too**, not only this tap's own
bookkeeping (`rightDownAt > 0 || CGEventSource.buttonState(.combinedSessionState,
button: .right)`). A press the tap never saw — re-enabled after a timeout
mid-gesture, or a context menu's tracking loop in the way, which is what Victor
guessed was happening — leaves `rightDownAt` at zero while the finger is very much
down. The reverse staleness is handled by `reconcileButtons()`, run before any
chord is judged: a *release* the tap never saw would otherwise leave a button held
for good and read every bare wheel click as a chord.

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
**Connect Terminal** row greys itself out with it.

**A toggle, not a push-to-talk.** A button held down for the length of the
sentence is right for a sentence; a dictation aimed at an agent runs to a minute
or more, and a mouse button held for a minute is a hand that cannot take the
screenshots (mouse 4) the same minute exists for.

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

**The folder is `~/workspace` unless he says otherwise, and nothing is
inferred.** Victor's call, and three reasons line up behind it: it is where he
starts every session by hand, so it is the one folder Claude Code already trusts;
every repo he has is a folder inside it, so the agent can still be told which
one; and a destination that never changes is one he does not have to check before
he starts talking.

Resolving it — bound target, else the terminal in front, else `~/workspace` — was
written first and is what surfaced the trust prompt: spawned into
`~/workspace/walkie-talkie`, Claude Code stopped on *"do you trust this folder"*
instead of working, because he has only ever started it from the parent. An
answer that is right four times in five is worse here than a fixed one, since the
fifth is only discovered after the sentence has been spoken.

**Saying otherwise is a click, and only ever a click** — see *The folder menu*
below. That does not reopen the argument above, which is about *guessing*: what
beat the fixed answer was inference, and a folder he pointed at is not inferred.

### The folder menu (2026-09-04)

**Three seconds after a spawn dictation opens, a small menu sits where the mouse
was when he started talking, naming the repos he starts sessions in.** A
click on one is where that session opens; not clicking is `~/workspace`, exactly
as before. `SpawnFolderMenu.swift`, put up by `AppDelegate.offerSpawnFolders`.

Victor's ask: *"vreau să-mi arăt un modal în care să pot să aleg în ce folder
pornesc dictarea"*. The fixed destination costs the first sentence of every new
session — said out loud, to name the repo, so the agent can `cd` into it — and
that sentence is the same five words every time.

- **The list is not hardcoded any more** — see *Two halves, and a line between
  them* below. It was, for four days: six names in Swift, chosen because they
  were the projects he was working on the afternoon it was written. `~/workspace`
  holds ~150 directories, nearly all of them course material, so a *listing* is
  still not a menu; what replaced the constant is a measurement, not a `ls`. A
  folder that is not on disk is dropped rather than offered by both halves, since
  the launcher falls back to `$HOME` on a failed `cd` and that is the one
  destination nobody meant.
- **Three and a half seconds solid, then a second of fade — unless the hand is
  on it.** His numbers, and the first of them was two for half an hour: two is
  not long enough to read a half-dozen names, decide and travel to one while a sentence
  is already being spoken. The fade is not only a way out: something that
  vanishes on its own was never asking to be answered, and a dictation is
  already running behind it. **Hovering suspends the clock** (his ask, later
  the same day) — the pointer arriving mid-fade brings the menu back to solid,
  and leaving it lets the fade run; a target that dims as the hand reaches it
  is being taken away at the exact moment it is aimed at. **A click still lands
  during the fade**, so the window to answer is four and a half seconds plus
  hover — nothing turns hit-testing off, and the panel is ordered out only once
  the animation has finished.
- **It draws a surface, which is the one place it departs from *Nothing beside
  the pointer draws a window*.** That rule is about the chip and the flashes,
  which are read and never touched. This one has to be *aimed at*: rows need
  edges to be told apart, and a target needs a ground to sit on. It is also the
  only thing this app puts near the cursor that does **not** follow it — it stays
  where the sentence started, so the hand can travel to it.
- **Below and to the left of the pointer** — measured at 10pt on each axis. The
  chip hangs below-*right* (`RelayWindow.anchorGap`), and a menu underneath a chip
  chasing the same cursor cannot be clicked. It flips to the other side of the
  pointer on either axis when the preferred one would hang off, and is then
  clamped into the visible frame of the display the pointer is on: a menu that
  opens near an edge opens there precisely when the hand is far from the middle.
- **The instant the press lands**, not after the opening picture — *"be shown as
  soon as possible"*. It moved up out of the end of `startLocalRecording` for a
  reason that only shows on a cold model: everything below it can `return` and
  wait seconds for the weights, and the menu was waiting with them, when its clock
  is his reading time. The capture marker still blooms out of the pointer for
  half a second, and the menu sits **below-right** of it (2026-09-06, moved from
  below-left) and **above** it: the effect panels sit at
  `CGWindowLevelForKey(.maximumWindow)` and are created *after* the menu — it
  opens at the press, the context shot fires at the release — so `.popUpMenu`
  lost to them and the ripple played over the top of the choice being read. The
  menu is now one level past that maximum, which is the only way it wins by
  construction rather than by ordering. Overlapping the chip is fine for the
  same reason: that is a `.statusBar` window, so the menu covers it and the
  clicks land on the menu.
- **Offered once per gesture** (fixed 2026-09-04). A cold model makes
  `startLocalRecording` run twice for one press — once at the press, once when
  the weights land — and the second run re-did the whole opening: the menu
  re-appeared ten seconds in under the hovering hand with its clock restarted,
  and a folder he had *already clicked* was wiped by the `spawnFolder` reset and
  the menu popped back up over it. The continuation passes `resumed: true`,
  which keeps the choice and skips the offer.
- **Not an `NSMenu`.** `popUp` runs a nested tracking run loop, which would
  freeze the pulsing 🔴 and the chip's own cursor-following for as long as it is
  up, and it offers neither a timed dismissal nor a fade. The rows are drawn
  `NSView`s for the reason `PillButton` and the ✕ are: this panel never becomes
  key, and standard controls in a non-activating panel look permanently disabled
  and eat the first click. `acceptsFirstMouse` is what makes that first click
  count — the app is `.accessory` and never active, so *every* click is one.
- **The choice rides the `Message`**, like `spawn` itself and for its reason: the
  panel holds a prompt for seconds and the next dictation may have started by
  then. `send` moves `spawnFolder` onto `Message.directory` and clears it, and a
  pick arriving after that is refused — the words are already in flight, and
  moving a folder under them silently is worse than ignoring a late click.
- **The chip gives the picked folder a row of its own**, behind Terminal's icon
  — the shape a binding has. Victor, 2026-09-07: *"numele folderului trebuie să
  fie arătat cu iconul de terminal în față, ca și cum aș fi fost deja bind-uit la
  un alt astfel de terminal … să știu dacă am setat ce trebuie"*. The argument
  that removed this row is *the folder is always `~/workspace`, so it says
  nothing he does not know* — and that holds exactly until he picks one off
  the menu, at which point the only place the choice could be checked was the ✨'s
  own label, three seconds after the menu had gone.

  `RelayWindow.spawnCollapsed` therefore split into two questions:
  `spawnMarked` (the ✨ rides in front of `Listening...`, unchanged) and
  `spawnCollapsed` (the destination row is dropped — now only when no folder was
  picked). The ✨ **stays where it is**: it is the one fact this destination does
  not share with a binding, namely that the session does not exist yet. Passing
  the icon is what turns the row on, so the default `~/workspace` is untouched.
  New state, so `docs/overlay-states.html` has a new `Shot` (`spawn-folder`).

### Two halves, and a line between them (2026-09-08)

**The menu names the projects he pinned, then a separator, then the five repos
he has actually been working in most over the last fortnight.**

```
  Start Claude in…
  human-review              ★
  petclinic                 ★
  training-assistant        ★     ← PinnedProjects — his decision
  victor-macos-addons       ★
  victor-vsc                ★
  walkie-talkie             ★
  ─────────────────────────
  petclinic-main            ☆
  petclinic-pr              ☆     ← RecentProjects — measured
  victor-phone-addons       ☆
  victor-skills             ☆
  victor-skills-private     ☆
```

Victor's ask: *"analizând conversațiile pe care le-am avut cu Claude-ul, cu un
script … să determin care sunt proiectele în care am lucrat … să le adaugi sub o
linie separatoare"*.

**A hardcoded list is wrong the week after, and wrong silently.** The six names
were right the day they were written and are the wrong six by the time anything
reminds him — and the cost of a project missing from the menu is exactly the cost
the menu was built to remove: the first sentence of every session started in it,
spoken out loud to tell the agent where it is.

#### Where the bottom half comes from

`helpers/recent_projects.py` reads **Claude Code's own transcripts**
(`~/.claude/projects/*/*.jsonl`) and ranks the git repos he has burned tokens in.
Where he has been working is a fact already written on this disk, next to the
`usage` block that says what it cost.

- **Token burn, and the metric turned out not to matter.** *"am promptat mult,
  sau am ars mult stoc, nu știu exact cum"* — so it was measured three ways over
  his real 14-day window: weighted cost (output ×5, cache-creation ×1.25, input
  ×1, cache-read ×0.1), raw output tokens, and number of prompts. **All three
  name the same top five**, with only 4th and 5th swapping. There is nothing here
  to tune, and a later reader should not spend an afternoon believing there is.
- **`cwd` is read per record, not per session**, so a session that `cd`s between
  repos attributes honestly to both. **Everything under `~/workspace/<x>/` rolls
  up to `<x>`**, which is the only non-obvious line in the script: sessions run in
  `petclinic/petclinic-backend/.codecity-tool` and in
  `agentic-how/.claude-worktrees/…`, and left alone the first of those ranked
  *seventh in its own right*, splitting the work of the project that ranked first.
  The rollup also makes worktrees and nested tool checkouts free rather than a
  case to handle. Outside `~/workspace` the git root stands alone; outside `$HOME`
  there is nothing — those are `/private/tmp` scratchpads, a session's litter.
- **It is cheap, which is half the ask** (*"nu vreau să mănânci token ca să
  evaluezi unde s-au petrecut mulți token … dar nici să execuți asta la fiecare
  click"*). Nothing calls a model. ~1 GB across ~800 transcripts scans in **1.9
  seconds**, because a line reaches the JSON parser only after a raw byte scan
  finds `"assistant"` in it — a small minority of them. That is cheap enough that
  **there is no cache and no incremental read offset**, which is two classes of
  bug not written.
- **Apple's `/usr/bin/python3`, deliberately** — the script is pure stdlib, so
  `Transcriber.pythonPath`'s probe for an interpreter carrying `mlx_whisper`
  would cost several process launches to answer a question this does not ask.
- **Run at most once a day, in the background, and never waited on.**
  `RecentProjects.refreshIfStale` is a single `stat`; on the one day in a hundred
  it says the file is stale it launches a detached process. It is asked at
  **launch and at the gesture**, because neither covers how this app is used
  alone: it is a login item that can stay up a week (launch is not often enough)
  and it can be restarted five times in an afternoon (launch alone would rescan
  five times — the age check is what prevents that). The menu that triggers a
  scan shows yesterday's answer; today's lands for the next one, and nothing
  about a fortnight's ranking is urgent enough to justify a menu that appears two
  seconds after the sentence started.
- **The file holds every qualifying project, not the top five.** The menu takes
  its five *after* removing the pinned ones, and a pin comes off at any moment —
  a file of five would mean an unpinned project vanishing until tomorrow's scan,
  which is precisely the case he named.

#### The star

**Clicking it moves a row across the line, and does not close the menu.** A star
is a change to what the menu *is*, not an answer to what it asks — and the reason
to pin something is so that it is there next time, so a star that dismissed the
menu would make him reopen it to use what he had just arranged. The clock
restarts on a toggle, because a hand that has just arranged the list is a hand
about to use it.

- **Unpinning is not a delete.** The row falls into the recent half if it
  qualifies and disappears if it does not — *"acel proiect să apară în lista de
  proiecte recente, doar dacă am deschis recent în acel folder vreo muncă"*. That
  needs no code: it is `RecentProjects.offered` with the pin removed, and the
  qualification is already what the bottom half means.
- **Chosen by rank, shown alphabetically**, both halves alphabetical — his
  instruction, corrected mid-sentence (*"în ordine descrescătoare după… nu,
  alfabetic"*). The measurement decides *which five*; the eye gets a list it can
  find a name in without reading all of it. A leaderboard that reorders itself
  between two openings puts the row he reached for last time somewhere else.
- **On the right**, where a favourite toggle lives in everything that has one.
  It also keeps the folder names in one flush-left column — the names are what he
  aims at, and a glyph in front would push each one in by the width of something
  he is not reading.
- **SF Symbols `star` / `star.fill`**, the call `StatusItem` already made for
  `mappin` / `mappin.slash`: this is an on/off *pair*, and a pair whose halves are
  drawn by two different hands reads as two unrelated marks.
- **The hollow star is dim but always drawn**, never revealed on hover: it is the
  only thing on this menu that has to be *discovered*, and a control that appears
  when the pointer is already on it is one he finds by accident first.
- **A subview, not a region tested inside the row's `mouseUp`.** The two clicks
  mean opposite things — one opens a session and dismisses the menu, the other
  rearranges it and keeps it up — and a hit test off by two points would start a
  session he did not ask for. A subview cannot get the boundary wrong.
- **A rebuild keeps the panel's top-left corner** (`anchor`), since the menu
  hangs *below* the pointer: anchoring the bottom would slide every row out from
  under the hand that just clicked one.
- **The pins are seeded from the six that were hardcoded.** A fresh install shows
  him the menu he already knows, with a star beside each row explaining how it got
  that way. `~/.walkie-talkie/pinned-projects.json`; a pinned folder that is
  missing is dropped from the menu but **kept in the file** — an external disk or
  a checkout he will make again should not cost him the pin. Only a click removes
  one.

#### `WT_SHOOT_MENU` — because this panel cannot be photographed either

`WT_SHOOT_MENU=/tmp/menu.png ./.build/debug/WalkieTalkie` draws the menu into a
PNG and quits (`SpawnFolderMenu.shoot`). It is `sharingType = .none` like
everything else near the pointer, so the only way to review a layout change was
to make a spawn dictation and look with your own eyes, within three and a half
seconds, at something that then faded. Same problem `docs/overlay-states.html`
solves for the chip and the same answer — the real views drawing themselves —
minus the catalogue, since this panel has one layout rather than 36 states.

It paid for itself on the first run: the stars came out as **five solid
squares**. Drawing a template `NSImage` and then `fill(using: .sourceAtop)` over
the same rectangle paints the whole box, because what it composites against is
the row and the blur behind it, both opaque. The tint has to happen inside an
`NSImage(size:flipped:)` of its own, whose backing is transparent. That is
invisible in review and obvious in a picture.

**The clock did not grow with the list, and that is a live question.** Eleven
rows is nearly twice what 3.5 seconds was timed against. Hovering suspends the
fade and a click lands during it, so it is answerable; if it starts to feel
rushed, the number to change is `solidSeconds`.

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
it: the app starts unbound, a double click opens a session, the words land — and
the relay is still pointing at nothing, so the wheel is inert (*Unbound is
inert*) and the second sentence of the conversation he has just started has
nowhere to go. He has to bind the window by hand, which is the pointing this
gesture exists to remove. Reported 2026-09-01: *"nu s-a autolegat de acel
terminal … a rămas idle"*, with the log showing the manual `left + wheel` bind a
minute later.

**Always, not only when nothing was bound** — his call, asked and answered the
same day. A spawn is him saying the session he wants does not exist yet, which is
the same sentence as *the one I am pointed at is not it* — the thing the right
chord says by letting the binding go. Two spawns in a row each
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

**It is one mark on the recording row, not a row of its own** (since 2026-09-02).
It was a title row — Terminal's icon, ✨, `workspace` — and Victor took it off:
the folder is *always* `~/workspace`, which is the whole point of the gesture, and
the icon names an app he is not looking at yet, so the row spent a line beside his
cursor saying one thing he already knew. *"Pune doar steluțe în fața butonului de
listening și nu mai afișa primul rând."* The ✨ now rides in front of `Listening…`
(and `Transcribing… 4s`), and `RelayWindow.spawnCollapsed` is the switch.

- **The 🔴 keeps the glyph column.** A frozen recording row is indistinguishable
  from a hung app, which is the one thing the pulse is here to rule out, and it
  cannot be given up for a mark that never moves.
- **The held panel keeps its title row.** It is parked in a corner, read whole,
  and *where these words are about to go* is exactly what a panel with a Cancel
  button on it has to say out loud.
- **Only the spawn.** Replace Wispr's `at the caret` names a destination that
  genuinely varies, so it keeps its row — which is why the mark is passed in
  (`setSpawnDestination(_:mark:)`) rather than sliced off the label.

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
condition this gesture is defined by not needing. `POST /test/spawn-folders`
is the second half of that: `/test/spawn` enters *below* the microphone with a
finished transcript, and the folder menu belongs to the three seconds after a
dictation opens — a stretch no fabricated transcript passes through, so without
its own route the menu's geometry, its fade and the fact that a row can be
clicked at all are unverifiable at a desk.

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
- **The chip says `at the caret` behind the drawn map pin**, in the slot a spawn
  uses and for the spawn's reason: the bound terminal is still there, and for the
  length of this sentence the words are not going to it.

  **The pin replaced a ⌨️ on 2026-09-08**, on Victor's ask. The keyboard named
  the *input* — which is the one thing a dictation does not use — where the row's
  whole job is to say **where the words land**, and it named it inside the words
  instead of in the icon column every other destination's picture rides in. It is
  `RelayWindow.pinGlyph`, the same drawn `Glyphs.mapPin` a binding falls back to
  — the oval drawn down to a point with a hole through it, and deliberately not
  📍, which Apple draws as a thumbtack stuck in at an angle.

  **And it stays up through the decode** (2026-09-08, his ask: *"când fac
  transcribing … dar sunt în modul de insert la caret, îmi trebuie să rămână tot
  jos același lucru scris"*). `stopLocalRecording` used to clear it at the
  microphone's close, which put the **bound terminal** back on the chip for the
  whole wait — the one destination those words are certainly not going to, named
  in the seconds he is watching the row to find out where they went. It comes
  down where they land, and on every path that gives up on them (`clearSpawn`).
  A dictation that is neither a spawn nor a paste takes the row down as it opens,
  so a caret left by a decode that never came back cannot ride the next
  sentence.
- **Restored from the last launch** (since 2026-09-07) — the call `Autosend`
  makes. It was deliberately *not* persisted until then, and the argument was the
  stronger one of the pair: autosend changes *how long the panel waits*, this
  changes **where every sentence lands**, so a tick that survived a restart would
  put a dictation meant for a bound agent into whatever field had the caret,
  weeks after he had forgotten it was on. What overrules it is that the mode is
  not a setting he drifts into — it is how he dictates for a whole stretch of
  work, and re-ticking it every launch is a tax charged on the one gesture that
  exists to save typing. The tick is one click away and the chip says
  `at the caret` on every sentence it takes, so a mode left on is visible
  before a word is spoken. `AppDelegate` seeds the flag and the tap from
  `StatusItem.isReplaceWispr` at launch **without** going through
  `setReplaceWispr`: that call flashes the overlay, and a restored mode is not an
  event to announce.
- **The transcript is on the clipboard as well as at the caret**
  (`pasteText`, which ⌘⌃P now shares), so a paste that landed somewhere unhelpful
  is one ⌘V of his own away from being fixed. `lastDictation` is set too: a
  Replace Wispr sentence is exactly the kind wanted twice, in a second field.
- **The menu row's icon *is* its state**: a `checkmark` in front of the words
  when the mode is on, and an empty box the same size when it is off (Victor,
  2026-09-07 — asked for as an ✕ or nothing, *"sau mai bine chiar … nimic"*). It
  had `⌨️` in that column and its state in `NSMenuItem.state`, which is the
  arrangement `Autosend` gave up one row below and for the same reason: a ticked
  row makes AppKit reserve the state column for the **whole** menu, so switching
  this one mode on shoved every other row sideways.
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

**Only a deliberate bind may do this** (fixed 2026-09-02). `showBound` is not
only the bind route: `refreshBoundTitle` rides the overlay's 10s branch tick and
calls it with the binding **already** in place, to pick up a window an agent has
renamed. So the take-back fired on a *poll* — a spawn dictation started while some
terminal was still bound lost its destination a couple of seconds in, with no
button pressed, the chip going from `✨ workspace` back to the terminal bound
before it and the sentence going there with it. Victor: *"după 2-3 sec de vorbit,
fără să apăs niciun buton, tooltipul a arătat că s-a reconectat la unul dintre
terminale"*. It reads as random because the timer's phase has nothing to do with
the gesture, and the shutter presses it happens to land near make it look like the
shot did it. `showBound(_:deliberate:)` carries the difference; the poll is the
one caller that passes `false`.

**The window is the recording, not the panel.** Once the transcript is on screen
the destination is already on the `Message` (that is what `Message.spawn` is
for), and a bind during the hold changes nothing about the sentence in front of
him. The seconds are few and the rule is the simpler one to hold: *the recipient
is whoever the relay is pointed at when the microphone closes.*

## ⌘⌃P pastes the last dictation

The last dictation that **went out**, onto the clipboard and pasted at the caret,
from `⌘⌃P` or the menu row. Saying it twice is worse than saying it once — the
second take is never the same sentence, and it costs another model run.

**It is the whole line the terminal got, since 2026-09-04** — `📸 ×2 0:38`, the
quoted selection, the picked selectors and the paths of the frames included.
Victor: *"paste the whole text with all the image references and everything"*.

It was the words alone until then, on the argument that the envelope is addressed
to an agent and is noise in a commit message. The argument was about the wrong
caret: where this lands is overwhelmingly **another agent** — a second session, a
web chat, an editor's assistant — and there the screenshots and the highlight are
the half that cannot be retyped, while a stray `📸 ×2` in a commit message is a
word to delete. `commit` records `terminalLine(m)`, the same call
`deliverToTerminal` and `spawnClaude` make, so what he pastes is byte for byte
what the session received.

**Replace Wispr still pastes the words**, and that is the rule rather than an
exception to it: that mode builds no envelope, so the words *are* the whole
message.

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
the pulse, `Listening...`, `Transcribing... 4s`, the picks he has
actually made, the destination. (`Preparing…` was on that list until 2026-09-06,
when the model started loading at launch and the state stopped being one he could
be waiting on.)

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
that performs it — `Start dictation to new claude — 🛞🛞`,
`Cancel Dictation — 🛞 2s`, `Take Screenshot — ⬇️`. A row greys out when it cannot act *this second*; it
never disappears, because a menu that hid what he cannot do right now would be
useless for learning what he can do at all. That is what *"indiferent de starea
în care sunt acum"* asks for.

One row exists because of this rule rather than despite it:
**`Pick Element in Chrome — ⌘⇧ + ⬅️`** is a legend, permanently
disabled — the gesture happens inside a page this app cannot reach from a menu,
but the relay takes the input over, so with the chip silent there is nowhere else
it could be written. A disabled row is the honest rendering of *this is something
you do, not something you pick*.

The two new commands are the same calls their gestures make, not quieter
variants: `Start dictation to new claude` is `startLocalRecording(spawn: true)`, and
`Take Screenshot` is `plusOneShot` — the latter **after a 0.35s beat**,
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

Row heights, for checking a layout change without seeing it: title 21, and every
other row on the chip — engine, shots, ⌘⇧-picked and the selection — 22, with
`rowGap` 2 between them. **The chip's rows are all the same height on purpose**:
the selection row stood at 28 until 2026-09-02, to hold a 26pt quotation mark
sitting 6 below the baseline inside its text label, and those six points read as
deliberate air in a shape meant to be a flat stack of one-line facts (*"rândurile
trebuie să aibă distanță egală între ele în tooltip"*). The mark is in the **icon
column** now, like every other row's glyph — which also puts the selection's words
in the same text column as the rest, where they never were. 16 more under the
**panel's** quote row, which is the seam between what he highlighted and what he
said; it was 8 and could not be seen, because the mark's own baseline offset
lengthens that row's line box downward and spent most of them inside the row.
`pad` 12 all round. So the idle chip is 40 tall — bound is the same, since the folder
moved *into* the title row — and dictating is 40 + 3 × 23 for the three rows and
their gaps, plus 21 more with a selection.

**No screen capture can contain this window**, and `RELAY_CAPTURABLE=1` no
longer buys it back on macOS 15 (verified 2026-07-31: transparent image, both
whole-display and `screencapture -l <windowid>`). Two ways to see a change
anyway:

- `./docs/shoot-overlay-states.sh` → all 36 states at once, and the page that
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

The chip is pinned to the pointer on **every** mouse event, and there is no
second mode. Growing into the panel is animated (0.22s ease out); everything
else resizes instantly.

**The leash is gone, 2026-09-07.** There was a *settled* state: 0.25s of
stillness parked the chip, and it then stayed where it stopped until the pointer
had travelled 70px. It was bought to keep the ✕ **catchable** — a chip that
re-engages on the first pixel of movement can never be walked over to and
clicked — and that argument died twice over without anyone coming back for the
leash: the ✕ is the panel's alone (*There is never a ✕ beside the pointer*), and
pause, the one thing a click on the chip ever toggled, is gone (*Pause is gone*).
Nothing on the chip has been clickable for months.

It was still being paid at every stop-and-start of the hand, and paid visibly.
Victor: *"nu e lipit de mouse, ci ceva care se trage lângă mouse … a trecut în
cursor de resize și după aia are vreo jumătate de secundă lag până când reprinde
mouse-ul"*. That is the leash exactly, and the resize cursor is the tell rather
than the cause: pausing over a window edge long enough for the pointer to change
shape is 0.25s of stillness, which settles the chip, and the 70px that follow —
half a second at reading speed — are spent with it standing still. **Do not
reintroduce a leash, a smoothing filter or a spring**: every one of them is lag
by construction, and the thing they were meant to make reachable is not there.

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
count straight to `refreshPresence`. The one state that changes the *title*
instead of adding a row has to be named there explicitly: bound. A row added
later keeps the chip on screen without anyone remembering to come back and edit
that condition.

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
be naming; in the menu it sits above `Connect Terminal` / `Disconnect` /
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
| `Take Screenshot` | 📷 | `⬇️` |
| `Pick Element in Chrome` | ✋ | `⌘⇧ + ⬅️` |
| `Replace WisprFlow` | a `checkmark` when on, **nothing** when off | the forward side button (see *Replace Wispr*) |
| `Autosend` | the same pair — a `checkmark` when on, **nothing** when off | |
| `Prompt Log` | 📜 | |
| `Victor's Walkie Talkie (<build>)` | ℹ️ | | |
| `Quit` | `power` | | |

**One shortcut column, not two** (Victor, 2026-09-06). Until then the mouse
chords were drawn into a tab-stopped column of their own and AppKit laid its
`keyEquivalent` column out to the right of it, so `Connect Terminal` and the two
dictation rows were the only ones with something in both, and every other row had
a gap where the second column ran past it. ⌘⌃B and ⌘⌃D lost their key equivalents
outright and ⌘⌃P moved into the drawn column beside the wheel chords. **Nothing
about the keyboard changed**: none of the three ever fired *as* a menu key
equivalent — this app is never the key app, so they only worked with the menu
already open — the chords themselves belong to the event tap (`HotkeyTap`), which
is untouched.

**The line groups by what a row is *for*.** Above it, everything about a
**destination** — point at one, let it go, paste the last sentence somewhere by
hand. Below it, everything done **with a dictation open**, plus the two rows that
open one: `Start Dictation` and, directly under it since 2026-09-06,
`Start dictation to new claude`. They are the same verb with the two destinations
there are — the terminal that is bound, and the session that is not open yet — so
they are read as a pair, and the row that used to sit up with Bind and Disconnect
on the argument that a new session is a destination now sits with the verb it
actually performs. They were interleaved before, in the order each was
written, with the two gestures that are only live mid-sentence sitting three rows
below the block they belong to. A menu that is the app's only legend has to group
by the question its reader is asking.

**The legend chords are bare — no `while dictating` qualifier at all.** It was
those two words for minutes and the marker `@🎙️` for two days before them;
Victor took both out (2026-09-04). The condition is said by the section the two
rows sit in — legends, under their own separator, below the dictation commands —
not by words or emoji riding on the row.

**The word `hold` is gone from every chord**, on Victor's ask. Where a hold has a
*duration* the duration says so (`🛞 2s`); where it does not, the
chord is unambiguous without it — there is no tap-⬅️-then-🛞 meaning something
else for it to be told apart from. It was four characters in front of the two
rows read most often.

**Take Screenshot is a legend, not a command** — permanently disabled since
2026-09-04, the same rendering the ⌘⇧-pick row already used for "this is
something you do, not something you pick". F3, its keyboard route, was never
pressed and went the same day — the key equivalent, the global branch in
`HotkeyTap`, all of it. The two legend rows sit under a separator of their own,
below the three rows that end a dictation and actually do something when
clicked.

**The back button is drawn `⬇️`**, joining ⬅️ and ➡️ rather than being spelled out
as *the back button*. The arrows in this menu are already mouse buttons; the
thumb button is the one that had no mark and so had to be four words.

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
words describing two objects, read in a menu open for a second; `hold ⬅️ + 🛞` is
the same sentence in the shape of the mouse it is about.

**And since 2026-09-02 they have a column, beside the key equivalents.** The note
here used to say `NSMenuItem` does not offer it — true only of the shortcut column
itself, which belongs to `keyEquivalent` and cannot hold a wheel. A **right tab
stop in an attributed title** is that same right edge drawn by hand, and AppKit
lays its own ⌘⌃ column out to the right of the text, so the two end up neighbours.
`StatusItem.layOutGestures` measures one tab position for the whole menu — the
widest of (longest plain row) and (label + 28 + chord) — so the chords line up
with each other instead of each floating at the end of its own label.

**`attributedTitle` also rewrites `title`, and that shipped as a bug.**
`restyleGestures` built its string from `row.item.title`, so the second pass
concatenated the chord onto a title that already carried one — every gesture row
printed its chord twice, on two lines. It runs from `menuWillOpen`, so the menu
looked right the first time it was opened and wrong every time after. The label
is stored in `gestureRows` now and never read back off the item.

**The cost is that an attributed title stops AppKit dimming a disabled row.** A
menu greys a title only while it is drawing it itself; handed a string, the
colours in that string are the last word, and a disabled `End Dictation` came out
as black as a live one. `restyleGestures` picks the ink off `isEnabled` and runs
from `menuWillOpen`, which is the one moment every flag in the file is current —
the same reason the header and the footprint are read there.

### Autosend

A checkbox, **restored from the last launch** since 2026-09-07. Ticked, the
pre-send panel opens for one second (`AppDelegate.autosendHold`) **with no Send
and no Cancel on it**, and then the message goes.

**It deliberately did not persist for two weeks, and the argument was a real
one**: the panel is what catches a transcript the model got fluently wrong, and a
tick that came back on its own would quietly take that away weeks later, in a
session where he had forgotten it was set. Victor overruled it after enough
restarts to settle the question — the reading it was protecting against is one he
makes deliberately, and re-making the same choice every launch is the worse tax.
**`Replace WisprFlow` persists too**, since 2026-09-07 — it was the second of the
pair to give the argument up, and it was the stronger bet: autosend changes *how
long the panel waits*, that one changes **where the words go**. See its own
section for what overruled it.

- **The panel still opens.** It is the receipt, and a dictation that vanished into
  a terminal with nothing shown is the one state where a delivery cannot be told
  from a drop.
- **The buttons' row goes with them**, not just their labels: two buttons up for
  one second are two buttons nobody can reach — an invitation to press something
  that will not be there when the hand arrives.
- The state lives on the menu item and is pushed to `AppDelegate.autosend`
  through `onToggleAutosend`, so the tick and the behaviour cannot disagree.
- **The icon column is the state: a `checkmark` when it sends straight through,
  and nothing at all when it does not** (Victor, 2026-09-07). It rides the icon
  column rather than `NSMenuItem.state` for the reason `Replace WisprFlow` does
  one row up: a ticked row makes AppKit reserve the state column for the
  **whole** menu, shoving every other row sideways the moment this one is
  switched on.

  Both halves of that pair were settled the same day, in two steps. Off was `⏸️`
  first, which is the same mistake an ✕ would have been on the row above — a
  picture in the column claims the row is *doing* something, and the panel
  holding for its three seconds is the app's ordinary behaviour, not a mode. On
  was then `⏩` for an afternoon, and Victor replaced it with the tick the row
  above already carried: *"autosend să aibă bifă în față, nu ⏩ când e activ"*.
  The icon column is where a row draws *what it is*, which is right for a row
  like `Take Screenshot` whose picture never changes — these two are the menu's
  only **switches**, so the one fact their column has to carry is on or off. A
  glyph illustrating the behaviour makes the reader decode a picture to answer a
  yes/no question, and makes the two switches look like unrelated rows when they
  are the same kind of thing. Blank is still an image of the column's exact
  width, so the title does not step sideways when the mode comes on.

Quit goes through the same `endSession(reason:)` as the ✕, so the outbox still
gets its `session_end` before the process dies. There is no ⌘Q key equivalent:
the app is `.accessory` and never becomes key, so the hint would advertise a
shortcut that does nothing outside the open menu.

### Prompt Log: the outbox read back as a page

`outbox.jsonl` is the record of everything Victor has ever dictated, and until
2026-09-03 the only way to read it was to `tail` a file of one-line JSON blobs
with UTC stamps and absolute paths to retina JPGs in them — a format written for
the agent watching the queue, not for the person who filled it. **Prompt Log**
(`MessageLog.swift`, 📜, under the two switches) renders the **last 48 hours** of
that same file into one self-contained HTML file and opens it in the default
browser.

**Generated on the click, never maintained.** The page is a view of a file
appended to all day; an HTML mirror kept in step with every send would be a
second writer on the send path for something read a few times a week. Building it
on demand also makes "the last two days" mean two days back from *now* rather
than from whenever a mirror was last rewritten.

**It lands in Caches** —
`~/Library/Caches/ro.victorrentea.wispr-relay/message-log.html`, beside the
`shots` folder rather than inside it, since `ScreenCapture.prune` walks that
directory and counts what it finds and a page is not a shot. Derived, regenerable
in a click, and nothing is lost when the system purges it. The outbox itself
stays in `~/.walkie-talkie`: *that* one is the log (see `Outbox.cacheRoot`).

**Local time, grouped by day.** `ts` is UTC, which is right for the queue and
useless for the only question ever asked of this page — *when did I say that?*
Three hours off in summer is enough to make yesterday evening look like today.

**Newest first, all the way down.** The page is opened for the sentence just
said, so the day at the top is today and the row at the top of it is the last
thing dictated. It costs the ability to read a session forwards, which is not
what a log gets opened for.

**The pictures are `stat`ed at generation time**, and a missing one becomes a
dashed row saying the frame is no longer on disk. Shots live in Caches precisely
so that macOS and every cleaner tool may take them, so a page built from lines
two days old will routinely name frames that are gone — and a broken-image box
says nothing about why.

**No CDN, both palettes, and one inline script.** The page is opened off
`file://`, where a remote stylesheet is a request that may not answer and a
failed one leaves the log unreadable; nothing here is fetched. Colours are tokens
on `:root` with a `prefers-color-scheme: dark` override, because Victor works in
dark all day.

**Every card has a Copy button, since 2026-09-04** — *"there should be a copy
icon, visible, that would allow to copy the whole text for easy pasting"*. The
page is read in order to *find* a sentence, and what happens next is that it gets
pasted; until then that meant a drag-select across a card that also holds a
timestamp, an app name and a block quote.

- **It copies the exact prompt ⌘⌃P would paste**, byte for byte — Victor's ask
  the day after the button landed: the same words, the dictated-aloud hint,
  every quoted selection, the focused window, the frames' paths and the picked
  elements. Since then the outbox carries the delivered envelope itself:
  `commit` writes `line` (the `terminalLine` the delivery used) into the JSON,
  and Copy reads it back. Lines from before that day have no `line`, so
  `MessageLog.payload` re-assembles those from the parts — close, not identical.
- **The payload rides in a hidden `<pre>`**, not in a `data-` attribute: an
  attribute would need its quotes escaped too, and a dictation is arbitrary text.
- **The script is the one bend in "no script", and the rule survives it.** That
  rule is about the *network*; this is a dozen lines inline, delegated from
  `document` rather than bound per card, and with JavaScript off the page still
  shows every message minus a button.
- **`document.execCommand` is the fallback and is not vestigial**: the Clipboard
  API needs a secure context, `file://` is one in Chrome and is not guaranteed to
  be everywhere, and the old select-and-copy trick has no such requirement.
- **The clipboard glyph is drawn as an SVG**, not 📋 — it has to sit on a 12px
  line beside a word and take the button's own ink in both palettes, which an
  emoji does at whatever size and colour the font feels like.

**A bad line is skipped, never thrown.** The file is appended to by a live
process while the page reads it, and it has survived every schema this app has
had: one truncated tail line is not a reason to refuse to show the other five
hundred. Lines with neither words nor pictures (`session_start` / `session_end`)
are dropped too — a page of empty rows is what made the raw file unreadable in
the first place. A missing outbox gives an empty page with a sentence saying so.

**The row carries no callback**, unlike every other command in the menu. The
others hand their click to `AppDelegate` because they need state only the
delegate has; this one needs nothing but the file on disk, and a hop through the
delegate would exist only to be consistent with rows that had a reason.

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

## The bound tty is published, so the status line can wear a microphone

`~/.walkie-talkie/bound-tty` holds the tty of the bound session while there is
one, and does not exist otherwise (`Outbox.publishBound`). Victor's status line
reads it and puts a 🎙️ badge in front of the model name when it matches its own
tty — **yellow bound, red while the microphone is open**.

The line carries both facts: `ttys006`, or `ttys006 listening`. A second word
rather than a second file, because the reader is a shell loop doing one builtin
`read` and two files would be two of them plus a state that can be half-written.
It is written from **both** switches that own the two facts — `showBound` for the
binding, `syncBorrowedGestures` for the microphone — since neither can answer the
other's question.

Yellow is the state that lasts hours and red the one that lasts a minute, which
is the same split the chip draws with a folder name against a pulsing 🔴.

**Same problem the corner beacon solves, at the other end of the sentence.** The
beacon answers *is it hearing me?*; this answers *which of these twenty
terminals is it aimed at?* — and the chip, which is the only thing that has ever
answered it, rides the pointer and is hidden the moment he types.

- **A file, not the `GET /target` route that already answers this.** The bar
  re-renders every second in every open session; an HTTP call on that beat is a
  per-second cost across every terminal on the machine. Nothing bound is a file
  that is not there, i.e. one failed builtin `read` and no subprocess at all.
- **The tty is the only handle both sides hold** — the same argument
  `~/.claude/cwd/<ttysNNN>` already makes in the other direction, and the reason
  that publisher exists. `Handle.tty` answers for a Terminal tab directly and for
  an IDE target through `tty(ofPID:)` on the shell pid — as bare `ttysNNN`,
  **never `/dev/ttysNNN`**. Both spellings live in `TerminalBinding`: the handle
  keeps the device path because that is what AppleScript compares a tab's `tty`
  against, `address` keeps the short form because that is what a human reads.
  Publishing the path shipped once and matched nothing, silently — which is the
  failure mode a marker like this has by construction: no error, only a badge
  that never appears. A tmux pane answers with
  the **client's** tty, which is the outer Terminal tab and not the pty the agent
  is on, so it fails to match rather than matching the wrong session;
  `.keystroke` has no tty at all, which is the case that could not be guarded
  either.
- **Written from `showBound` and nowhere else**, which is the one method every
  route into and out of a binding passes through — so the file cannot drift from
  the chip.
- **Removed, never emptied, and cleared at launch as well as at quit.** A marker
  outliving the process would claim a binding that went with it, and a microphone
  on a row with nothing behind it is worse than none: the badge is only worth
  anything if it can be trusted.
- **A profile or a background tint on the bound tab was considered and dropped.**
  `~/.claude/hooks/session-color.sh` already owns `background color of <tab>`,
  keyed by the same tty, hashed on the folder, re-applied on every `CwdChanged`
  and by a per-session watcher when macOS flips appearance. Two writers on one
  property, and the hook has the last word — a bind colour would vanish at the
  next `cd`. `cursor color` is the one per-tab property nothing else claims, and
  is where that idea would have to go if the status line ever proves not enough.

## The beacon: a microphone in Wispr Flow's own badge slot (2026-09-07)

**On the screen the pointer is on, 19pt, in the menu bar where Wispr Flow puts
its own badge, pulsing 🎙️ for exactly as long as the microphone is open**
(`RecordingBeacon.swift`) — and it flies there out of the pointer.

The chip already says this — the pulsing 🔴 and the `Listening...` bar — and it
says it *beside the cursor*, which is the one place Victor is not looking while
he talks: he dictates while reading something on another display, with a
full-screen window up, and macOS hides the pointer the moment he touches the
keyboard, taking the chip with it. The state that must never be in doubt — *is it
still hearing me?* — had the least dependable receipt in the app.

### It moved from a 150pt corner, and the reason is not aesthetics

It spent a week as a **150pt microphone in the top-right corner of every
display**, on two arguments that are both true: a corner is the one part of a
screen nothing is ever laid out against, and big is what makes an indicator
readable across a room. Victor replaced it anyway: *"emoji-ul acela de microfon
vreau să îl pui în locul badge-ului lui Wispr Flow, în aceeași poziție, că mă uit
mereu la el acolo … un pic mai mic"*.

**The eye does not go to the best place, it goes to the practised one.** A year
of dictating through Wispr Flow is a year of glancing at one specific spot in the
menu bar to find out whether the microphone is open. An indicator that is
objectively more visible somewhere else is still one he has to remember to look
for; one in the slot his eyes already travel to costs nothing to read. That beats
size, and it is why this went from 150pt to 19.

- **The slot is measured, not written down.** `anchor(on:)` asks
  `CGWindowListCopyWindowInfo` where Wispr Flow's badge actually is on that
  screen — owner name plus `layer > 0` plus a size cap, because the name alone
  also matches its 512 × 586 `Status` panel. Hardcoding the x would be hardcoding
  *how many status items happen to sit to its right*, and that failure would be
  silent and would look exactly like the feature not working. Measured on all
  four of his displays: 21 × 24 each (37 tall on the built-in), one per screen.
- **The flip is the load-bearing line.** `CGWindowList` speaks CG global
  coordinates — y downwards from the top-left of the *primary* display — and
  everything else here is Cocoa's. They agree only on the primary screen, which
  is the trap `TerminalBinding.cocoaRect` is already written under and which
  stays invisible until a second monitor is plugged in. Verified on all four:
  the badge lands inside the menu bar's own y range on each.
- **The fallback is 513pt from the right edge**, which is where his Wispr badge
  sits on three of his four bars (532 on the built-in). It is only reached if
  Wispr Flow is not running, and being a few points off there is the correct
  amount of wrong.
- **19pt box, 16pt glyph** — *"un pic mai mic"* than the 21 × 24 it stands beside,
  so it reads as one badge rather than two competing.
- **Bounds need no Screen Recording permission**; only pixels do, and nothing
  here reads pixels.

### One screen, the pointer's — and it gets out of the way

It was every display at once, which is right for a corner nobody clicks and wrong
for a badge in the menu bar: four copies means three sitting on top of three real
menu bars he is not looking at. The pointer is the best available guess at where
he is looking — the same assumption the chip is built on — and unlike the chip
this one survives him typing, because it is not anchored to a pointer macOS hides.

**And the pointer arriving inside it takes it off screen** until it leaves:
*"dacă mouse-ul merge peste el, dispare ca să pot să dau click sub el"*. The panel
has always been `ignoresMouseEvents`, so the click was already getting through;
what it did not do is let him *see* what he was aiming at — and what is under it
is, by construction, Wispr Flow's own badge. There is `clearance` of 8pt around
the box, because a bare containment test flickers it on and off while he works
along the bar.

**A global monitor, not a poll.** `MenuBarMirror` polls `NSScreen.main` every
500ms because the focused screen posts nothing; the pointer does post, and half a
second of lag on *get out of the way so I can click* is half a second of clicking
at something still covered. A global monitor sees only events going to other
applications, which is every event there is here — the app is `.accessory`, never
key, and the panel ignores the mouse. It is armed for the length of a dictation
and taken down with it.

### What did not change

- **It flies out of the pointer**, 0.55s after the microphone opens
  (`CaptureFlash.markerDuration` plus a beat, so the red cursor target is not
  blooming out of the same pixels at the same instant). The slot is the right
  place for it to *live* and the wrong place for it to *appear*: a microphone
  materialising in a menu bar he is not looking at is a thing he finds later, if
  at all. It **shrinks** now where it used to grow — 34pt to 19 — which is
  `BindFlight`'s own direction and reads the same way.
- **A dictation that ends inside that beat never puts anything up at all**, which
  is the correct ceremony for a gesture that did not happen.
- **The pulse**: 1.0 → 0.15 and back over 1.2s each way, the 🔴's tempo for the
  🔴's reason. At 19pt it is doing more work than it used to, since size is no
  longer carrying any of it.
- **One panel per screen** even though only one is up: a window belongs to a
  single display and a panel built for one keeps that display's scale and Space
  behaviour. `.statusBar` level and `fullScreenAuxiliary`, so a full-screen
  window does not bury it and it draws *over* the bar rather than under it.
- **Never in a screenshot** (`sharingType = .none`) — the relay photographs the
  screen during the very dictation this marks. So it cannot be checked with a
  screenshot; what is checkable is the geometry, which is how both this and the
  slot it aims at were verified.
- **`syncBorrowedGestures` is still the switch**, on `listening` rather than
  `live`: it answers *is it hearing me?*, and where the words go is the chip's
  question.

## The prompt is held, not sent

The prompt shown after a dictation is **not yet in the outbox**. It sits in
`AppDelegate.held` for 3–5s (`minHold`/`maxHold`, scaled by word count) behind a
**Cancel** button in the bottom-right, and only `commit()` — on the countdown
running out, on a click on the overlay body, or on quit — ever writes it.

That delay is the whole point: the agent polls the outbox every couple of
seconds, so a line already written may already be a tool call in flight. Cancel
can only mean something while nothing has been written. Escape in the terminal
remains the tool for work already under way.

**The times are written on the frames themselves** (since 2026-09-02) — a dark
pill low in each thumbnail's left corner, `0:38`, `1:52`, in the strip under the
words. `AppDelegate.shotStamps` formats them and `RelayWindow.layoutShots` drops
them in; the stamps are **m:ss from the moment the dictation opened**, not
wall-clock.

The count on its own answers "did my shots land"; it does not answer the question
he has a few seconds later, which is *which* moments he caught. In a three-minute
dictation `📸 ×4` is four indistinguishable files, while `0:38 · 1:52 · 2:41` is a
table of contents — and this panel, with the Cancel clock running, is the last
instant at which noticing a missing one is free. Wall-clock would say nothing
here: the shots exist only as parts of this message, and `15:22:07` does not
locate a moment *inside* it.

**They were a line of text above the strip until then**, which is a caption only
if you count columns to match a stamp to a frame — and the count was off by one,
since the unstamped context shot is *in* the strip and was not in the line. On the
picture there is nothing to match: the frame says when it was taken. Victor's ask:
*"pune timpul acela desenat, scris peste thumbnail-ul pozei"*. It also gave the
transcript row back the line the stamps were taking, an inch from his cursor.

**The context screen is counted but not stamped**, and that survives the move: it
is always at zero — he took it by starting to talk — so its `0:00` is the one
stamp that carries no information. The first frame in the strip is therefore bare,
and `shotStamps` says so with an empty string rather than with a missing entry, so
the stamps stay index-aligned with the frames the panel is handed.

**A pill, not bare text over the picture.** What is behind it is a screenshot — a
terminal, a white page, a Figma canvas — so no ink colour is legible against all
of them; text on its own ground is, and at 10pt semibold with monospaced digits
the ground costs about thirty pixels of the frame. The label sits in a container
rather than being the pill itself, because `NSTextField` puts a single line where
its cell decides and not on the box's midline.

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

### The send flight (2026-09-04)

**When a held prompt is released — the countdown running out, ⏎, a click, the
Send button, or autosend's one-second beat — the panel flies to the terminal the
words were sent to.** Victor's ask: *"once the timer expires or it sends to the
terminal I would love it to pan and increase the size until it reaches that
terminal"*. A picture of the panel leaves its corner and grows until it fills
the bound window's frame, then dissolves. The receipt for *it went there*, in
the bind flight's own language and through the same `BindFlight` machinery —
which is what guarantees the two can never drift.

- **An outline, and only an outline** (`outlined:`, since 2026-09-07). It flew
  the panel's own drawing of itself — the overlay is invisible to screen capture
  (`sharingType = .none`), so its view's `panelImage()` was the only picture of
  it in existence, handed in through a `carrying:` parameter that existed for
  this one caller. Victor took it out the same day the spawn flight lost its
  picture, and for the same reason: *"când dialogul se duce spre terminal, vreau
  să se ducă spre un border doar … nu mai știu mental ce era în acel terminal,
  doar să înțeleg că se duce într-un terminal, undeva"*. A bind ends **small, at
  the cursor**, so pixels are what say which window became the chip; this ends
  **on a window, at full size**, over what he is reading — where a picture covers
  the very destination it is pointing at. `carrying:` and `panelImage()` went
  with it, having no other caller. It fades across the arrival (`tail:`) like the
  spawn's, rather than blinking off a terminal.
- **The destination is re-resolved, not remembered.** `Target.sourceFrame` went
  stale the moment Victor dragged anything after binding; the flight asks
  Terminal for the window showing the bound tty *now* — the same
  `terminalWindowFrame(tty:)` the spawn flight uses. tmux bindings aim at the
  client's window by the same call.
- **IDE and keystroke targets get no flight.** Nothing outside those apps can
  name their window's frame honestly, and a flight toward a guessed rectangle
  is worse than none.
- **The dialog is held for it, and fades only once the outline has left**
  (Victor, 2026-09-07: *"când pleacă mesajul din dialog către terminal existent,
  la fel … abia atunci începe să facă fade dialogul"*). It vanished the instant
  the prompt resolved, so the outline set off from a dialog that was already
  gone — which is the same thing that made the spawn's flight unreadable, one
  section down. `resolvePrompt` now holds the panel on **every** send,
  `sendFlight` starts the flight and schedules the fade `spawnPanelFadeDelay`
  later, and **every path with no flight to make releases it at once** — an IDE
  or keystroke target, a window that could not be found, a send with no panel
  behind it. That last part is the one to keep right: a dialog waiting for a
  flight that never comes is a dialog that never closes. The spawn learned this
  first only because its window does not exist yet; the argument was never about
  spawning.
- **A cancel has its own grammar already** — the 🗑️ row — so it does not fly,
  and Replace Wispr holds no prompt at all, so there is nothing to fly. **A spawn
  makes this very call, since 2026-09-07**, from its held dialog to the window
  that has just opened (*The spawn's flight leaves the dialog*): it is late by
  however long the terminal takes to appear, and it is the one flight whose
  source has to be kept alive on screen until then.

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

## The oblique wipe: a message replaces a message

**Since 2026-09-07 a message does not appear beside the pointer and it does not
disappear — a line at 60° crosses the chip, brightens the words it passes over,
and leaves the next ones behind it** (`ChipWipe.swift`).

Victor's ask, in his own words: *"an oblique line that wipes out the message of
dictating when I cancel by holding the wheel down… an effect that wipes the text
that was there and replaces it with 'cancelled'… imagine an oblique line, like 60
degrees from the horizontal, which makes the text a bit brighter where it passes
through and then it wipes the text out, or replaces it with another text"*.

**It exists because the chip's whole vocabulary is one row being swapped for
another**, and a swap made in a single frame is indistinguishable from a redraw.
Cancelling is the case that makes it obvious: `🔴 Listening…` is gone and
`🗑️ Dictation aborted` is there, with nothing on screen saying the second
*replaced* the first — which is exactly the fact a cancel has to carry, since the
thing that went away is the sentence he had just spoken. What was there before
was a half-second alpha dissolve on the message **leaving** and nothing at all on
the message **arriving**: an asymmetric fade for a symmetric event, and the fade
is gone with this.

**A line rather than a fade, because a fade cannot say *replaced*.** A fade says
*this is ending*; a wipe says *this became that*, since at every instant of it
both are on screen with a boundary between them. The chip is a flat stack of
one-line facts and there is nothing else a transition here could add: what a line
travelling through it adds is direction, with no surface, no window and no second
meaning attached.

**60° is his number and is also the only one that works.** The chip is wide and
short — 200 points by 40 to 100 — so a vertical edge crosses every row at the
same instant, one column of text after another, which reads as a curtain; a
horizontal one takes the rows off one at a time, which reads as three separate
events. A steep oblique crosses the whole stack at once and still reaches the
bottom row a beat after the top, so the shape is one gesture with a grain to it.
Steeper than 45° deliberately: at 45° the travel is dominated by the chip's
height and the sweep looks like it is going *down* rather than across.

**0.32 s, and the floor is the brightening, not the wipe.** The argument that
halved the bind flight from 2 s to 1 s applies harder here — a bind is answered
once per binding, this runs on every flash the app raises, dozens of times a day,
an inch from what he is reading. But below about a quarter of a second the band
crosses a 200pt chip faster than the eye resolves it and the whole thing collapses
into a flicker, which is worse than the instant swap it replaced. 0.32 leaves the
band roughly four frames over any given word and is over well before the message
it announces has been read.

**Both halves of the swap are pictures, and the live rows are muted for the
length of it.** The obvious build — one picture of the old content erased over
the live new content — is wrong in a way that only shows on a message longer than
the one it replaces: the chip's background is transparent, so wherever the old
picture has no ink the new row is already showing through it, `Dictation aborted`
sticking its tail out past `Listening…` from the first frame, on the side the
line has not reached yet. Two masked pictures over an `alphaValue`-muted view
tree is the only arrangement in which the region ahead of the line is honestly
*only* the old chip. Muted by alpha and not by `isHidden`, because
`layoutContent` owns `isHidden` on every one of those rows and would fight for
it; `ChipWipe.cancel` is the single place it is given back, so an interrupted
sweep cannot leave the chip blank.

**The light is masked by the words — and by luminance, not by alpha.** A white
band laid straight over the chip would be a translucent stripe dragged across
whatever is behind it, and behind it is his screen (*Nothing beside the pointer
draws a window*). So the band is stencilled by the text's own pixels. Taking that
stencil from the **alpha** channel does not work, and it is the halo that breaks
it: every row is white ink carrying a dark halo so it reads over a terminal, the
halo has alpha too, and a stencil cut from alpha is therefore a blurred blob
around each glyph rather than the glyph — lit up, the row becomes a white slab
with the letters lost inside it. The brightest **channel** of a premultiplied
pixel is the white ink's own coverage and reads a black halo as zero, which is
the whole difference. Measured against a rendered sheet of the sweep before it
shipped: alpha-stencilled the seam is an unreadable smear, luminance-stencilled it
is the words, brighter.

**And the fattening is what makes "brighter" mean anything.** The ink is already
white, so white light on it changes nothing; what changes is the *edge* — the
stencil is grown a point, so under the band the halo is filled and the stroke
gains a rim, and the word reads as momentarily bolder and hotter. That is
Victor's "a bit brighter" on ink that was white to begin with.

**The band leads the edge and rides inside each picture.** It sits a quarter of
its own width ahead of the erasing line, so the order is the order he described —
brighter first, gone second — while still straddling the seam enough to catch the
incoming words on the way past. Each picture carries its **own** copy of the band,
clipped by its own ink and its own side of the line, because a single glow over
the union of both lit the outgoing and the incoming words *at once* wherever it
crossed the seam: on two different strings that is two words superimposed, and it
reads as a smear rather than as a line.

**The picture it sweeps away is taken at the top of `layoutContent`, not at the
flash**, and that is the one piece of this that is not about drawing. Cancelling
is four calls in one call stack — `setListening(false)`, `clearSelection()`, then
`flash("🗑️ Dictation aborted")` — and the first two each relayout the chip.
Nothing is *rendered* in between, since Core Animation commits once at the end of
the turn, so what Victor sees leave is `🔴 Listening…`; but a capture taken at the
flash draws the views as they are *by then*, which is the collapsed `🎙️` nobody
ever saw. The sweep would have started from a picture that was never on screen,
and the row it exists to replace would have vanished in a jump one frame earlier.
So `rememberChip` takes it at the first relayout of a turn, while the views still
hold what the last frame showed, and releases it on the next hop through the main
queue — which drains after the call stack unwinds and before the frame is
committed, i.e. exactly at the boundary that matters.

**What it does not apply to.** The **panel** is out: parked in a corner and read
whole — a transcript, a quotation, a strip of frames, two buttons — a line
travelling across all of that is a page being turned, which is a far bigger claim
than the one row changing that this narrates. `anchored` is the test, the same one
`refreshChrome` asks. A flash raised while **nothing is on screen** is out too:
there is nothing to wipe *from*, and a stripe of light over blank desktop
announces nothing. `showSentPrompt` clears its flash **without** the sweep, since
what comes next is not another chip but the panel unfolding out from under it.
And it is off entirely under `RELAY_SHOOT`: `docs/overlay-states.html` photographs
*states*, and a transition is by definition not one — which is also why nothing
here needed a new `Shot`.

**It is drawn in the chip's own layer rather than in a panel of its own**, unlike
`UnbindPop` and `BindFlight`. Those open a window over the screen because what
they draw leaves the chip — a burst spreading past its edges, a rectangle
travelling from a terminal. This never leaves the chip: it is the chip's own
content being exchanged, and the chip is riding the pointer while it happens, so a
separate window would have to chase the cursor for a third of a second to stay
registered with the thing it is drawing on, and would composite at its own opacity
instead of at the chip's 0.80. The one price is that `RelayWindow.snapshot` has to
stand a sweep down before it photographs anything, or a `kill -USR1` landing
inside those 0.32 s would write out an empty chip.

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

**The glyph is Chrome's own icon**, **at 0.8 of what the system hands out**
(2026-09-02, Victor's ask: the system gives these at 32 against a 20pt box, and an
app icon fills its box corner to corner where an emoji sits a bearing in from the
edge — so at the same nominal size it was the largest thing in the column).
`NSWorkspace.icon(forFile:)` on whatever `com.google.Chrome` resolves to — looked up, never shipped, so no version of the
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

### …but it must not outlive it (2026-09-04)

*"Once I have a selected text it sometimes remains into the tooltip even if there
is no current dictation."* Two independent leaks, both fixed:

1. **Cancel never put the row down.** `cancelLocalRecording` clears
   `pendingSelection` under the lock, but the row showing it is the overlay's own
   copy and nothing else there touches it — `setListening(false)` does not, and
   the `🗑️ Dictation aborted` flash draws *over* the chip rather than resetting
   it. Every other exit already called `overlay.clearSelection()` (`commit` before
   the panel opens, `flushOrphaned` for the ones that died); cancel was the one
   route that did not, so the last highlight sat beside the cursor with no
   dictation behind it until the next sentence overwrote it.
2. **The probe can outlive its dictation.** `SelectionCapture.read` falls back to
   a ⌘C that polls the pasteboard for up to 400ms, and the wheel held down through
   those 400ms is a cancel. The probe then wrote everything the cancel had just
   cleared straight back — a `pendingSelection` that would ride the *next*
   sentence, and a row on a chip at rest. Both `stashSelection` and
   `stashExtraSelection` now capture `dictationStartedAt` before probing and drop
   the result if it no longer matches: nil means the sentence ended, a different
   instant means a new one has begun.

### Where a spawned window opens (2026-09-04)

A spawn is by definition the one window Victor never pointed at: it appears on its
own while his eyes are somewhere else. It used to `activate` and land wherever
Terminal felt like, which in practice is on top of whatever he is reading on the
built-in Retina display. `SpawnTerminal.board()` and `slot(for:on:avoiding:)`
decide instead:

- **an external display attached** → the window is **tiled** across every
  non-Retina screen, left to right, and Terminal is brought forward — on screens
  he is not working on, that costs him nothing. *"tile them somehow so that they
  don't overlap with others… use all the monitors you have around"*.
- **nothing but the Retina display** → there is nowhere to move it to, so it opens
  **behind** instead. Nothing activates Terminal; if `do script` launched it from
  cold and it took the front anyway, the app that *was* frontmost is put back a
  quarter second later. The window still exists and `adoptSpawnedWindow` still
  binds it a beat later — delivery goes through `do script … in <tab>`, which does
  not need the window in front.

**The tiling is a grid of the window's own size, scored rather than filtered.**
Each display is cut into cells as big as the window Terminal just made — two
columns of a 905pt terminal on a 1920pt monitor — with the grid centred in
whatever the cells did not use, so a single-column screen does not park the
window against its left edge. Every cell on every display is scored by how many
square points of *other* Terminal windows it would sit on, and the first cell
with the lowest score wins. Scoring rather than filtering is what makes it
degrade instead of fail: with every slot taken — six terminals across three
monitors — the answer is the least-covered cell rather than no answer, and
reading left to right is what lands a second spawn beside the first instead of
on it.

**Only Terminal's own windows are avoided**, and they arrive in the same
`osascript` round trip that opened the window: the slot is chosen by what is
already there, and a second launch of the interpreter to ask for a list the
first one was holding is a launch for nothing. Asking the window server about
every app's windows would price a browser off the monitors that are there to
hold browsers.

"Retina" is `backingScaleFactor >= 2` — the same test the `come-back-when-done`
skill uses, and deliberately not a size or a name. Everything below `board()`
speaks **AppleScript's** coordinates (origin top-left of the primary screen, y
downwards), because the only thing any of it is for is `set bounds of window`.

### The spawn's flight leaves the dialog, and the dialog waits for it

*"dialogul dispare … înainte ca terminalul pornit să apară, dacă îl deschid unul
nou. În cazul în care a deschis terminalul nou, așteaptă ca terminalul să
pornească și abia apoi începe animarea care duce fereastra către terminal"*, and
then: *"imediat când chenarul din jurul dialogului pleacă către terminalul nou
pornit, atunci să înceapă și fade-out-ul pe jumătate de secundă, în timp ce
chenarul călătorește către terminal"* — Victor, 2026-09-07.

**The panel is not relayouted when a spawn is sent** (`RelayWindow.spawnPanelHeld`).
Every other resolved prompt collapses back to the chip in the frame it is
released, and for a delivery that is right — the words went to a session that is
already open, so the panel has nothing left to say. A spawn is the one case where
the destination **does not exist yet**: the terminal takes a few hundred
milliseconds to appear, and collapsing on the way there left a hole in the middle
of the gesture — the dialog gone, nothing arrived, and then an outline setting off
from a chip beside the pointer with no visible connection to what had just been
read.

The state behind the panel is cleared exactly as it always was (the delegate may
raise the next prompt from inside that same call); what stays on screen is the
last frame the views were laid out in, which is what he was reading. Two
consequences fall out of holding a *live* panel rather than a picture of one, and
both are guarded: it must not follow the pointer (`followCursor` returns early —
the outline is aimed at that exact rectangle), and nothing else may touch its
alpha (`refreshOpacity` returns early — a keystroke arriving mid-dissolve would
otherwise animate it back up). Any **relayout** ends the hold (`endSpawnHold`, at
the top of `layoutContent`): a new dictation or a flash is newer state than this
picture, and newer state wins the chip.

**The outline then leaves the dialog** — `BindFlight.fly(from: promptFarewell,
to: { window })`, which is *the same call the send flight makes*, so the two
panel→terminal flights are one animation with two callers. It flies the moment
`adoptSpawnedWindow` finds the window, and **the dialog holds still for a quarter
of a second before it starts to fade** (`spawnPanelFadeDelay`, then
`releaseSpawnPanel` over `spawnPanelFade` = 0.5s).

**The delay is the whole thing working.** The two ran on the same instant for a
day, on the reasoning that the rectangle leaving the dialog is what the dialog
*becomes*, so the panel emptying out behind it is the other half of one sentence.
That reasoning is right and the timing defeated it: at t=0 the outline lies pixel
for pixel on the panel's own rectangle, so a panel already dissolving underneath
it never reads as *a thing leaving a dialog* — it reads as both of them fading at
once, which is a dismissal rather than a journey. Victor, 2026-09-07: *"dialogul
trebuie abia atunci să înceapă să facă fade-out timp de jumătate de secundă, dar
doar după ce conturul lui pleacă în călătorie către terminalul nou deschis …
vreau să văd vizual că ideea dialogului se duce spre terminal"*.

A quarter second is a third of the flight — by then the rectangle has
unmistakably cleared the panel it came from — and it lands the end of the
half-second fade within a hair of the outline's arrival, so the dialog finishes
emptying out just as the window receives it. The whole gesture is a held dialog,
an outline leaving it, a fade and an arrival, with nothing hanging at either end.

**The terminal is open before any of this starts**, which is the precondition the
sequence rests on and the reason `adoptSpawnedWindow` polls for up to
`spawnWindowWait` (4s): a flight needs a real rectangle to aim at, so the window
has to exist and have coordinates first. That is also why the panel is *held*
rather than dismissed when the prompt resolves — it is being kept alive for a
moment that has not happened yet.

**The old backwards flight is still there, as the fallback**, for a spawn that
never showed a panel — there is then nothing but the chip to leave from. What
follows is why it was built that way, and it is still the argument for that case.

*"the animation should be backwards, from the mouse going to the terminal, and
should start as soon as the terminal window is displayed. Faster a bit."* —
Victor, 2026-09-04.

Backwards is the honest direction for a spawn. A bind says *that window is now
this chip*, so the picture travels window → cursor. A spawn says the opposite —
*what you just said is now that window over there* — about a window he has not
looked at yet and does not know the position of, so the picture leaves the chip
under his hand and arrives **on** the window, growing instead of shrinking and
going from half opacity to full.

It is **one flipped `t`** and not a second animation (`BindFlight.fly`'s
`reversed:`), so the two can never drift: the hold that opens a bind — standing
still over the window — becomes the beat a spawn *ends* on, resting on the window
it has just filled, and the fade that ends a bind becomes the spawn's fade **in**
out of the pointer. `source` is still the window and `destination` still the chip
in both directions; only which of them it starts at changes.

**And it starts when the window is on screen**, not on a fixed 2.5s beat.
`seconds:` is the other half: `AppDelegate.spawnFlightSeconds` is 0.7 against the
bind's second, because this flight is a hand-off rather than an answer to a press
and it plays while the eye is still travelling to a window that has just
appeared somewhere else.

**It carries no picture — an outline, and only an outline** (`outlined:`, since
2026-09-07). Everything the bind flight argues for carrying pixels is an argument
*against* them in this direction. A bind's picture is invisible at the start
because it lies pixel for pixel on the window it was copied from; a spawn's
starts at the cursor and ends **on** a window that, with one monitor, has just
opened *behind* whatever Victor is reading — so the same trick renders as a copy
of a terminal pasted on top of his work. *"Să nu ia poza terminalului … doar un
chenar către chenarul terminalului, oriunde ar fi el."* A frame arriving on a
frame says *there* without covering anything, which is all this direction ever
had to say. The white fill the picture-less bind flight falls back to is off for
the same reason.

**And it fades across the arrival rather than at it** (`tail:`,
`AppDelegate.spawnFlightRest` = 0.5s). The fade starts with the last sixth of the
travel still to go (`BindFlight.tailFadeFraction`), runs through the landing, and
reaches nothing half a second after the rectangle has come to rest on the window.
A bind ends by sliding under the chip, which is somewhere for it to *go*; this
one ends on a window that stays exactly where it is, so without the tail its last
frame is a white rectangle blinking off a terminal. Landing and dissolving is the
same sentence with an ending. Victor: *"când mai are 10%, 20% din distanță,
începe să facă fade-out … mai stând acolo încă jumate de secundă, până când
dispare complet."*

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

## Never launch the installed app by its executable path

`open "/Applications/Walkie Talkie.app"` — never
`"/Applications/Walkie Talkie.app/Contents/MacOS/Walkie Talkie"`, however much
easier the second one makes reading the log on stdout.

**macOS keys a privacy grant to a bundle identifier only for a process it
launched itself.** A process started by its own path is attributed to the
**path** instead, i.e. filed as a second, unrelated application that happens to
share a name. Found 2026-09-08, with two of them already on this Mac:

```
kTCCServiceScreenCapture | ro.victorrentea.wispr-relay                              | 0 | 2026-08-15
kTCCServiceScreenCapture | /Applications/Walkie Talkie.app/Contents/MacOS/Walkie…   | 1 | 2026-09-08
kTCCServiceAppleEvents   | ro.victorrentea.wispr-relay            → com.apple.Terminal | 0 | 2026-08-15
kTCCServiceAppleEvents   | /Applications/Walkie Talkie.app/Contents/MacOS/Walkie…  → com.apple.Terminal | 1 | 2026-08-28
```

`client_type` is the whole story: `0` is a bundle id, `1` is a path. Victor saw
the consequence in System Settings — **two rows both called "Walkie Talkie"**,
one carrying the app's own icon and one the generic `exec` icon macOS gives an
unbundled Mach-O, each holding Screen Recording of its own. *"Elimină Walkie
Talkie-ul care arată ca terminalul … să apară doar aplicația asta odată."*

- **The rows are indistinguishable in the UI**, which is what makes this worth a
  section: same name, and nothing in the pane says which is the bundle. The
  query above is the diagnostic —
  `/Library/Application Support/com.apple.TCC/TCC.db` for Screen Recording and
  Accessibility, `~/Library/Application Support/com.apple.TCC/TCC.db` for
  Automation and the microphone. Both are readable with a `sqlite3` select from
  a terminal that has Full Disk Access; **neither is writable** without root, and
  `tccutil reset` takes a bundle identifier, so it cannot name a path row at all.
  **Removing one is a click in System Settings** — select the row, press `−` —
  and that is the only route there is.
- **A duplicate is not merely untidy.** Each row is a grant that can be revoked
  independently of the one the app actually uses, so the app can lose Screen
  Recording while a checkbox next to its name is still ticked. That is the same
  class of confusion as *A stale bundle in /Applications is three bugs at once*
  above, and it presents the same way: a feature stops working with nothing
  visible to explain it.
- **`main.swift` now makes it structurally impossible.**
  `relaunchThroughLaunchServicesIfNeeded()` runs before `NSApplication.shared` is
  so much as touched: if the parent is not launchd (pid 1) **and** the executable
  sits inside a `.app`, it re-execs the bundle through `open -n -a … --args` and
  exits, having asked macOS for nothing. `WT_ALLOW_DIRECT=1` overrides it.
- **Development runs are untouched**, and that is the point of testing the
  bundle rather than the parent alone: `swift build` puts the binary in
  `.build`, which is not a `.app` and has no bundle identity to be mistaken for.
  `RELAY_SHOOT` and `docs/shoot-overlay-states.sh` run exactly as before.

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
  makes it findable at 32px in a folder of a hundred icons. `build-app.sh` renders the ten iconset sizes
  (`assets/make-appicon.swift`) and calls `iconutil`, rather than committing an
  `.icns`, so the PNG stays the single source of truth and the app icon follows
  it on the next build. The bundle is `touch`ed afterwards or Finder and the Dock
  keep serving the cached old picture.

  **And touching the bundle is not enough for the Dock.** Measured the day the
  grid inset landed: the installed `.icns` was the new one and
  `NSWorkspace.iconForFile:` served the new one, while the Dock went on painting
  the old picture across a `killall Dock` — the tile it draws comes from
  `com.apple.dock.iconcache` in the darwin user cache dir, and **that file
  survives a Dock restart**. Deleting it and restarting is what repaints the
  tile. `build-app.sh` now does exactly that, and only when the `.icns` checksum
  actually changed (a Dock restart is a visible flicker, and the script runs on
  every build). Verified by capturing the Dock and measuring: 72px against a
  neighbour's 76 — the circle slot — where before it was the full tile.

  **The tiles are inset to Apple's icon grid, and until 2026-09-07 they were
  not.** `sips -Z` scales artwork to *fill* the tile, and `walkie-bound.png`
  fills its own canvas corner to corner — so the ring was drawn at the full width
  of the Dock slot while every neighbour sits inside the grid, and it read as
  visibly fatter than the icons either side of it. Victor spotted it in the Dock
  and in ⌘-Tab. Measured on this Mac rather than taken from the HIG: on a 1024
  canvas Finder's and Chrome's bodies are **824** across to the pixel (80.5% —
  the 83.6% an alpha bounding box reports is their drop shadow bleeding), and a
  **circle** gets the smaller slot, **790** (77.1%), because at equal width a
  disc reads as the larger object. Victor Addons, circular like this one, sits at
  77.0–78.1%. This icon is now 790/1024, verified in the built `.icns`.

  **The padding cannot live in the artwork**, which is the whole reason there is
  a script: `walkie-bound.png` is *also* the menu bar's icon, drawn into a 19pt
  box that has no grid and must not be inset. One source of truth, two framings.
  Swift rather than a `sips` loop because `sips` cannot pad with transparency
  (`--padColor` takes an opaque RGB triple), and not Python because CoreGraphics
  there needs PyObjC, which `/usr/bin/python3` does not have — while the Swift
  toolchain is already a hard dependency of `build-app.sh`. (It shows in Finder, Spotlight, Get Info — and, since 2026-09-07,
  in the Dock: see *The Dock tile is the escape hatch* below.)
- **`Quit — built Aug 28, 17:48`**, one row, the way Victor Addons does it: read
  once a session, and read while reaching for Quit anyway, since the answer to
  "no, that's the old build" is to quit and relaunch. The date is the
  **executable's own mtime**, not a constant stamped into the source: Addons seds
  a `BUILD_TIME` literal into a tracked Swift file on every build, which dirties
  the working tree and lands in commits as noise, while the file date says the
  same thing for free, cannot go stale, and works unchanged for a plain
  `swift build` run from the terminal.

## The Dock tile is the escape hatch

The app is a **`.regular`** app since 2026-09-07 — `setActivationPolicy(.regular)`
in `main.swift`, and no `LSUIElement` in the plist `build-app.sh` writes. So there
is a Dock tile, with the running dot under it.

It was `.accessory` from the start, on an argument that is still true: an overlay
is not an app you switch to, and a Dock tile for something with no window is
clutter. What that argument never covered is **the day the app hangs**. Victor's
Dock is on the right of the screen, and ⌥-click on a tile → **Force Quit** is the
gesture his hands already know. An `.accessory` app has no tile, so the only ways
out of a frozen relay were Activity Monitor or a `pkill` in a terminal — and the
terminal may be the very thing the relay was in the middle of typing into. That
happened on 2026-09-07 (see the deadlock below), and the tile went in the same
afternoon.

**It costs nothing the rest of the time.** Nothing in the app activates itself:
the overlay is a `.nonactivatingPanel` (see *Nothing beside the pointer draws a
window*), the About row and the message log open pages in the browser rather than
modals, and no code calls `NSApp.activate`. The one thing that changes is that a
click on the tile now *does* make the app frontmost — which is why `main.swift`
installs a minimal main menu (About, Hide, Quit ⌘Q). A `.regular` app with no
`mainMenu` shows an empty menu bar, and an empty menu bar on the one occasion
Victor looks at the app directly reads as a broken app.

**The comments that say "never becomes key" are still right in spirit.** They are
in `RecordingBeacon`, `SpawnFolderMenu`, `RelayWindow` and `AboutPage`, and each
is about a mouse monitor or a click-through: the app is never frontmost *by its
own doing*, so every click still arrives at a background app and still counts as a
first click. Clicking the Dock tile is the exception, and it is a deliberate act
that ends in Force Quit or in ⌘Q.

## The mic's own lock is not recursive, and `start` already holds it

`MicRecorder.lock` is an `NSLock`. `start(to:)` takes it on its first line and
holds it to the `return`. On 2026-09-07 the commit that added the voiced-seconds
meter reset the meter's two fields halfway down that method and wrapped the pair
in `lock.lock()` / `lock.unlock()` — the reflex every other write to `voiced` and
`noiseFloor` correctly follows, because they are written from CoreAudio's thread.

`NSLock` is not recursive. That second acquire deadlocked the thread that called
`start`, which is the **main thread** — `onPasteToggle` and every other dictation
gesture hop to main before opening the microphone — so the whole app froze on the
first dictation of the build, with the window server still delivering events to
the tap on its own thread and the log still filling up with mouse edges that led
nowhere.

**The log is what dated it, and the shape is worth remembering**: the last line
before the freeze was `🎙️ forward button — Replace Wispr` and the next line that
should have existed, `🎙️ local recording started`, never did. Everything between
those two lines is `mic.start`. Victor reported it as *"cum apas forward pe mouse
se blochează"* and the forward button was innocent — the wheel and ⌘⌃D would have
frozen it just the same; the forward button was simply what he was testing that
afternoon, having just turned Replace Wispr on.

The fix is to **not** take the lock: inside `start` the state is already private.
The rule for this file is that `lock` is taken exactly once per public entry
point, and never again inside one.

