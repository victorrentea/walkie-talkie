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
  and `engineText` beside the pulsing 🔴 (`Listening with Wispr Flow` / `Listening with <model id>`)
- `Self.pickHint` + `pickText` — the ⌘⇧-picked row (`select element ⌘⇧🖱️`, then
  `×2 div#cart > span.price`, both behind Chrome's icon); the label beside the outline in
  `chrome-extension/inspect.js` counts too, and so do its one error string
  (`⚠ no relay session took it`) and the toolbar title in `relay.js`
- `titleText` — `🤖 <label>` / `⏸️ 🤖 <label>`
- `flash(_:)` / `flashTitle(_:)` call sites in `AppDelegate.swift`
- `StatusItem.swift` — the menu bar item's `Pause` / `Resume` / `Disconnect` /
  `Stop Recording` / `Quit`, plus the two transcription-engine rows
  (`Wispr Flow` / `Local Whisper`), flat in the main menu

## Bound to a terminal: the second destination

Since 2026-08-15 the relay can be **pointed at a terminal**, and every dictation
from then on is typed into that session and submitted — no `/relay`, no skill, no
`Monitor` armed on the outbox, no label filter to get right. `⌘⌃D` (this app's own key since 2026-08-26, see below) binds whatever
terminal is in front.

**The outbox is still written whenever a message goes out.** A binding is a
second destination, not a replacement: `AppDelegate.commit` writes the JSONL line
and *then* delivers, so the log survives, an agent watching the queue the old way
keeps working, and `session_end` — which is addressed to a watcher and means
nothing to a terminal — is the one kind that is not delivered.

**But a binding is now also the on switch** — see *Unbound is inert*. There is no
longer such a thing as a relay that writes the outbox with nothing bound.

### IDE terminals go through the editor's own extension

`⌘⌃D` on VS Code or IntelliJ no longer pastes. The relay finds a loopback
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
  the flag, since ⌘⌃D can land a beat before the answer settles. Matching on the
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
no whitelist at all — so ⌘⌃D pressed while looking at Chrome bound Chrome and
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
he chose. Measured on his own corpus, a local recogniser turned `Wispr Relay` —
what this app was called then — into
`risparerile ei`; an agent that does not know the input came through a
microphone has no reason to sound that out, and one that does resolves it at
once. The same failure exists with Wispr — rarer, not absent.
`dictation` only — inviting phonetic guessing at a screenshot's caption or a
typed message would be inviting it to misread them.

**The languages are named because they are half the answer**, and they are
named as a **fixed pair** rather than as the one the recogniser detected. Victor
dictates in Romanian and in English, and the phonetics that recover a mis-heard
word are the phonetics of the language it was said in — so *which two* to sound
a word out in is worth saying, and `RO` also explains a Romanian sentence
carrying English technical terms verbatim, which is how he actually speaks.

For one commit the clause carried the detected code (MLX Whisper reports it in
its JSON; Wispr keeps it in `History.detectedLanguage`, while `language` there is
the *setting* and is empty on auto). It was taken out because the code is not
reliable enough to assert: Wispr had labelled a sentence of Victor's plain
Romanian `en` in the very row used to test it. A clause naming the wrong language
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

⌘⌃D is pressed while looking at a terminal and answered by a chip that lives next
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
  separately by ⌘⌃D — reads nothing back (measured: 2926 bytes of environment for
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

  **They are images in boxes of their own, and that is not a style choice.**
  These labels are `NSTextField(labelWithString:)`, where `attributedStringValue`
  renders the image and turns **every other glyph fully transparent** — the bug
  that once left the chip showing a robot head and no session name. So an inline
  drawn glyph is impossible here, and the title joins the row-with-a-glyph
  pattern the ⌘-pick row already uses. Both images are rasterised **once**
  (`pinGlyph`, `folderGlyphImage`): the chip relayouts as it follows the cursor,
  and redrawing a shape sixty times a second for a picture that never changes is
  work for nothing.

**🤖 is still what unbound looks like** in the menu bar, and the glyph replaces
it rather than decorating it: 🤖 used to mean "this overlay is writing an outbox
somebody is watching", and bound that is no longer what happens. Since *Unbound
is inert* it means less than that — the app is running, and that is all.

The flashes carry **no pin at all** — `→ petclinic@main · ttys004` at bind,
`unbound — nothing is relayed now` at release. They are text rows, so the only pin
available to them is the pushpin emoji the drawn one exists to avoid.

### ⌘⌃D again on the same target lets go of it

The key had no off. Starting the relay is a keystroke and stopping it was a trip
to the menu bar — and the menu bar is a moving target precisely when the reason
to stop is that Victor is already somewhere else. So a bind that resolves to the
target **already bound** releases it instead of re-pointing at it, which also
makes the off switch reachable without aiming: whatever app is in front, two
quick presses bind it and then let it go.

- **Compared by handle, not by app.** Two tabs of Terminal are two ttys, so
  pressing in a different tab re-points rather than stops. What is bound is a
  session, not an application.
- **It unbinds; it does not quit** — since 2026-08-28. It quit until then, and
  the argument was that ⌘⌃D is what *starts* the relay, so an off switch leaving
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
  is still there and a second ⌘⌃D can point it back at that terminal, whereas a
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

`/bind`, `/unbind` and `/target` are **not gated on `dictating`**, unlike `/ping`
and `/pick`: pointing the relay at a terminal is something Victor does at rest,
and a bind that only worked mid-sentence would be one he could never make.

`/test/dictation` exists because everything downstream of Wispr — the held
prompt, the countdown, the outbox line, the delivery — was otherwise reachable
only by talking into a microphone, which made the one part of this app that types
into a live session the one part nobody could test at a desk.

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
cheat sheet still lists the key, display-only, exactly the way it lists Wispr
Flow's ⌘⌃W — the sheet answers "what does this combination do on **this Mac**",
which a key owned by another app still answers.

It is still the **only** owner: two taps claiming ⌘⌃D would both fire on one
press. Autorepeat is swallowed here now (a held key would bind and then
immediately stop the session it started). NB it shadows the system-wide ⌘⌃D
"look up in dictionary".

Binding takes the **first port that answers**, not all of them the way the Chrome
extension does: pointing every relay on the machine at one terminal would mean
every dictation arriving there two or three times.

## The rename, and the two places the old name survives

The app was `wispr-relay` until 2026-08-26 — folder, repo, Swift target, `.app`
and home folder all say `walkie-talkie` now. **Wispr Flow keeps its own name**
wherever it appears: it is a different program, and this app still reads its
database, watches its recording state and falls back to its transcripts.

Two strings deliberately still say the old name:

- **The bundle id, `ro.victorrentea.wispr-relay`** — and with it the Caches path
  and the dispatch-queue labels, which follow it. macOS keys Accessibility,
  Screen Recording and the microphone to that string plus the signing identity;
  changing it costs three grants re-ticked by hand in System Settings, on an app
  whose whole job is to be running before Victor starts talking. It is invisible
  everywhere he looks. `build-app.sh` says so beside the line, because it is
  exactly the kind of inconsistency a later reader would tidy up.
- **One quoted mis-transcription** in the notes above `dictatedHint`, where a local
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
when Wispr starts listening, and that one is reachable without the keyboard at
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

**With no terminal bound, the app does nothing to a dictation at all.** Not a
picture, not a borrowed mouse button, not an outbox line — and Wispr Flow's own
paste goes through untouched. Since 2026-08-27, `AppDelegate.isBound`
(`terminal.target != nil`) gates every path that pause gates, plus one pause
never did: `syncLocalCapture`, which is where `HotkeyTap.blockInjection` lives.

| gate | unbound | paused |
|---|---|---|
| `captureContext` — flash, selection probe, screen capture | off | off |
| `plusOneShot` — F3 / mouse 4 | off | off |
| `send` — the outbox line and the delivery | off | off |
| `syncBorrowedGestures` — mouse 4, ⌘⇧-click in Chrome | off | off |
| `syncLocalCapture` — **Wispr's injection**, mouse 5 on Whisper | **off** | off |
| `dictation.onChange` — the recording row | off (the *stop* edge still runs) | on |
| `corpus.capture` | **on** | on |

Why it had to change. The relay used to be started per session by `/relay` and
live only as long as Victor was dictating at an agent, so "running" and "aimed at
something" were the same fact and none of this could misfire. Since 2026-08-26 it
is a **login item** and sits there all day — so every sentence he spoke into a
browser, a chat or a commit message was getting a screenshot taken of it, was
losing him mouse 4 and ⌘⇧-click, and, worst of the three, was having Wispr's
paste swallowed by a relay with nowhere to put the words instead. Pause existed
to stop exactly that, and he was having to press it against an app that had no
destination anyway.

**The outbox goes quiet too, and that is a deliberate loss.** The `/relay` skill's
original mode was an unbound relay appending to a queue with an agent watching
it; that mode is gone. Victor was asked directly on 2026-08-27 and chose the
whole switch over half of it — an outbox filled all day for a watcher that is
usually not there is not a feature, it is a log of his private dictation. A
`/relay` session gets its destination the way everything else does now, by
binding.

**The corpus is the one thing that keeps running**, on the argument it was always
kept running through pause: it is a file on Victor's own disk, the samples are
what the local model is being judged on, and one dropped because he happened to
be dictating into a browser cannot be taken again.

**`showBound` is where the switch is thrown**, since it is the one place every
route into and out of a binding passes through — ⌘⌃D, `POST /unbind`, and a
target discovered gone at delivery time (`report(.targetGone)`). That last one is
why it lives there and not in the two callers: a relay whose terminal was closed
under it must stop swallowing Wispr's paste at that moment, not at the next
deliberate gesture.

**The stop edge of `dictation.onChange` is never gated**, only the start edge. A
relay unbound in the middle of a sentence would otherwise leave the recording row
on screen with nothing left running to take it down.

**`/test/dictation` is gated too**, which makes it useless at a desk with nothing
bound. That is the right reading of a route whose whole claim is that it enters
exactly where a real transcript does — bind something first, which is what the
path under test needs anyway.

## What pause is (and is not)

Pause **does not touch Wispr Flow**. That is the whole purpose of it: Victor
pauses so he can dictate into a browser, a chat, a commit message *normally*,
without those words also landing in the agent's queue. Nothing in this app may
try to stop, mute or intercept the transcription — it only stops acting on it.

Concretely, `paused` bails out of four places and nowhere else — the same four
`isBound` gates, plus the injection block it does not touch (see *Unbound is
inert*): `captureContext`
(no flash, no selection probe, no screen capture), `plusOneShot` (F3 does
nothing), `send` (nothing reaches the outbox), and `syncBorrowedGestures` — which
hands mouse 4 back to LinearMouse *and* ⌘⇧-click back to Chrome. That last one is
load-bearing rather than tidy: dictating into a browser is the reason he paused,
and an inspector still eating his ⌘⇧-clicks would be the one thing pause was
supposed to stop. Wispr keeps reporting that it
is listening, which is why `recordText` also hides the recording row while
paused — advertising F3 in a state where it does nothing would be a lie.

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
| Wispr recording | `🤖 ai@master`, unchanged, **plus the recording row below it** |
| paused (chip click, or the menu bar) | `⏸️ 🤖 ai@master` — the ⏸️ goes **in front of** the robot, never instead of it |
| bound to a terminal | the destination app's icon + `petclinic@main`; the 🤖 is *replaced*. See *What the chip says when bound* |
| bound to an app with no readable directory (a blind-paste target) | the icon + the app's own name — the one case where the icon has no subject beside it |
| bound **and** paused | `⏸️` still prefixes the identity |

Paused prefixes rather than replaces, and carries no state word. The chip's job
is still to say *which agent this is*; pause is a modifier on that, not a
different thing — and it is the same order as the menu bar item (`⏸️🤖`), which
is the other place the state shows. The old form was `⏹️ ai@master: Paused`, from
when paused was a panel in the corner with room for a word.

**Dictating no longer has a title of its own.** It used to be `🎙️ …` with dots
cycling 1→2→3→1, and there was a glass-shine sweep every 5s to go with it. All of
that has moved into the recording row: the top line now stays `🤖 folder@branch`
through the whole dictation — that is the fact that does not change — and what
does change lives one row down.

The liveness those animations provided is still load-bearing, and is now the
pulsing 🔴: a frozen recording row is indistinguishable from a hung app, and the
entire point of the state is reassurance that speech is being captured.

Paused wears ⏹️ because it is the one state that has to be readable from across a
room. Opacity separates it further (1.00 vs 0.30).

## The recording rows

While dictating and not paused, three rows sit directly under the title, one
glyph column and one text column:

```
🤖 ai@master
🔴 Wispr Flow                       ← something is listening, and this is what
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

**The mouse is named in words now** — `— mouse/F3 for more shots`, where it was
`🖱️/F3`. The glyph-only form was right while the row was one line of shorthand
sitting under a title; beside a row that says `Wispr Flow` in full it reads as a
different register. Which button is still unsaid, and still does not need saying:
the hand knows by the second dictation.

## Two gestures are borrowed, and only while dictating

Mouse 4 and ⌘⇧-click in Chrome both belong to other software the rest of the time,
and `syncBorrowedGestures()` is the single switch that takes them and gives them
back. The two sections below are one argument applied twice.

Since 2026-08-28 the same switch also **pauses Chrome's music** (`MusicBridge`,
below). It is not a gesture, but it is the same window and the same argument: for
the length of a sentence, something that belongs to the rest of the machine is
borrowed and then handed straight back.

## The music pauses for the length of a dictation

`MusicBridge` pushes `{type:"dictation", active, seq}` over a WebSocket on
**127.0.0.1:8920** and `chrome-extension/relay.js` pauses every audible tab,
resuming exactly those. Ported from Victor Addons' `DictationBridge` + its
`chrome-extension/`, which does the same for Wispr's own dictations — read
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

**A dead socket resumes**, which is a deliberate departure from Victor Addons.
That app runs from login and is rarely killed; the relay is started and killed
*per agent session*, so a relay that goes away mid-sentence would otherwise leave
the music off with nothing alive to turn it back on. A blip that is only a blip
costs a stutter — the reconnect replays `active:true` and pauses again.
`applicationWillTerminate` also calls `music.stop()`, so the ordinary quit says
so rather than relying on the net.

**Gated on `live`, not on `listening`.** A dictation nobody is relaying (unbound,
or forwarding paused) is Victor talking into some other app, and silencing his
music for that would be the relay reaching outside its own session.

**The extension needs `tabs`, `scripting`, `storage` and `<all_urls>`** — new
permissions on an extension that had only `http://127.0.0.1/*`, so a **Reload** in
`chrome://extensions` is required after pulling this; the pause silently does
nothing until then.

## Mouse 4 is the shutter, but only while dictating

The back side button (`MOUSE_BUTTON_4` = 3) takes a shot, and the relay
**swallows it** so nothing else acts on it — while Wispr is recording and
forwarding is on, and at no other time.

That button is Victor's Return key: LinearMouse
(`~/.config/linearmouse/linearmouse.json`) maps it to a `keyPress: ["enter"]`,
which is what he submits with all day. Borrowing it is only defensible because
of how narrow the window is — during a dictation an Enter lands in whatever
happens to have focus, which is never what he meant, and the point of the whole
overlay is that he is *away from the keyboard*. Asking him to reach for F3 to
attach a picture put the one thing he does mid-sentence back on the keyboard.

Three rules keep the theft honest:

- **Gated on `listening && !paused`**, pushed to the tap by
  `AppDelegate.syncBorrowedGestures()` from both edges that can change the answer
  (Wispr starting/stopping, pause toggling). At rest and while paused the button
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

**Accessibility only** (`SelectionCapture.readQuiet`), never the clipboard
fallback. `read()` posts a synthetic ⌘C and polls the pasteboard for up to
400ms; paying that once per dictation is a bargain, paying it on every shutter
press into whatever app is under his hand is a side effect the gesture never
promised. No AX selection reads as "he did not highlight anything new", which is
true far more often than not.

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

The animation is Victor Addons' `ScreenCaptureFlash.markCursor` verbatim: lands
at 1.3× and settles to 0.9× over 0.35s (a scope brought down onto a spot, not a
badge appearing beside one), 80% opaque from the first frame, fading only in its
last quarter.

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

## The voice corpus: audio kept beside the transcript, forever

**`~/.walkie-talkie/voice-corpus/`** — `VoiceCorpus.swift`. Every dictation the
watcher sees while the relay is up leaves three things behind:

```
voice-corpus/2026-08-17/14-30-22-a1b2c3d4.wav   ← what Victor said
voice-corpus/2026-08-17/14-30-22-a1b2c3d4.txt   ← what Wispr made of it
voice-corpus/corpus.jsonl                        ← one line per sample
```

It exists to make one future decision measurable: **replacing Wispr Flow with a
local model.** The relay transcribes nothing today and is not being taught to.
What it cannot do later is go back and collect the samples — Wispr keeps the
audio for a while and then drops it (measured 2026-08-17: **495 rows still had
audio out of 11,999**, roughly the last fortnight; the rest are text forever).
Every day the relay runs without this is a day of paired data that is gone.

- **The audio is Wispr's own bytes, not a second recording.** `History.audio` is
  a complete `.wav` — RIFF header and all, 16 kHz mono 16-bit PCM. Verified by
  writing a blob straight out and reading it back: `afinfo` says
  `1 ch, 16000 Hz, Int16`, 23.384s against the row's `duration` of 23.4, and the
  written file is byte-identical to the blob. Beyond being free, it is the only
  way the eventual comparison is *like-for-like*: a parallel recording made by
  this app would be a different signal from the one Wispr scored — other device,
  other gain, other start and end — and a benchmark where the two models heard
  different audio measures nothing. **Do not add a microphone to this app.**
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
- **The `.txt` is the formatted text and the manifest carries `asr` beside it**,
  and that split is the point of having a manifest. `formattedText` has been
  through Wispr's LLM post-processing — punctuation, casing, the user dictionary
  — so scoring a local Whisper against it charges the model for work an ASR does
  not do. `asr` is the apples-to-apples reference; the formatted text is the bar
  the *product* has to clear. The two already differ on the first sample
  collected (a trailing full stop). The `.txt` holds the transcript **and
  nothing else**, ending in a newline: it is meant to be diffed against another
  model's output, and metadata mixed in would have to be stripped by everything
  that reads it.
- **Everything the watcher sees, paused included.** Pause is documented as
  bailing out of exactly four places and this is deliberately not a fifth: it
  stops the relay *acting* on a dictation, and collecting the recording is not
  acting on it — nothing is sent anywhere, the file is on his own disk either
  way. Narrowing it to unpaused would throw away the minutes he spends dictating
  into a browser, which are some of his longest and least technical, i.e.
  precisely the coverage a corpus of agent prompts otherwise lacks. `capture` is
  therefore called from `wispr.onTranscript` beside `send`, never through it.
- **Keyed by Wispr's own `transcriptEntityId`**, which is what makes two relays
  safe. Both watch the same DB and both are handed the same id; the second finds
  the `.wav` already there and stops, so the sample is written once. The id also
  survives into the file name (first 8 chars) and the manifest, so a sample can
  always be traced back to the row it came from.
- **The blob is fetched off the poll path.** `WisprWatcher.onTranscript` carries
  the id and not the audio: the blob is megabytes, and the poll is how the words
  reach the agent. `VoiceCorpus` re-reads the row on its own utility queue, and
  **retries at 0/1.5/4s** because Wispr writes the text and the audio in its own
  order and the watcher can win that race. A row that still has no audio after
  that is logged and skipped — a corpus entry with no recording is not a sample.
- **`POST /test/corpus {"id": "…", "origin": "…"}`** collects a sample for a row
  that already exists. `/test/dictation` cannot reach this code, because a
  fabricated transcript has no recording behind it — and this is the same
  argument that route was added for.

  **It is also how the corpus was back-filled**, on 2026-08-17, the day it was
  written: 478 rows still had their audio, so driving every id through this
  route filled the corpus with **2.75 h over 3–15 August** (305 MB, 339 ro /
  132 en) instead of waiting a fortnight for it. Driving the route rather than
  writing the files from a script is the point — the app stays the only writer
  of that format, so a back-fill cannot drift from what live capture produces.

  `origin` is what makes that honest. It replaces the manifest's `session`,
  which for live capture is the relay session that heard the dictation and is
  the truth. A back-filled row was dictated days ago from a session long gone;
  stamping it with whatever session happens to be running now would not be a
  useless field but a **wrong** one, and this corpus is meant to be read months
  from now. Back-filled samples say `"session": "backfill"`.

### `editedText` is not ground truth — do not use it as one

It looks like exactly what an evaluation wants: 105 rows have both audio and an
`editedText`, which reads like "the transcript after Victor corrected it". It is
not. Wispr fills it by **observing the target app after the paste**
(`contentObservationEndReason` is the giveaway), so it records what happened to
the text downstream, not what was wrong with the recognition.

Measured before believing it: of 104 such rows, **56 are identical** to
`formattedText` once whitespace is normalised, and the 48 that differ are
overwhelmingly of this shape:

```
formatted: Arată-mi ce viziți ai, șters!
edited   : arată-mi ce viziți ai, șters
formatted: It is degrading for the human being to prove manually…
edited   : "it is degrading for the human being to prove manually…"
```

A lowercased initial because it was pasted mid-sentence, a stripped full stop,
added quotation marks. Scoring a recogniser against that measures where Victor
pasted, not what the microphone heard.

**There is no ground truth in this DB.** Every number the corpus can produce
today is a *disagreement rate* between two recognisers, not an error rate — and
when they disagree, either one may be the correct side. Real ground truth needs
transcripts corrected by hand, which is what the corpus makes possible and does
not itself contain.
- `FlowDB.swift` now holds the read-only opener both readers share. The URI form
  with `mode=ro` is load-bearing (see `WisprWatcher`) and was not worth
  remembering correctly in two places.

## Choosing the recogniser: Wispr Flow or a local Whisper

The menu bar's two engine rows — **Wispr Flow** and **Local Whisper**, flat in the
main menu below a separator — switch which recogniser's words reach
the agent, and the choice is kept in `UserDefaults` so it survives a relay
restart and a logout. `Transcriber.swift` holds both the setting and the engine;
`POST /engine {"engine": …}` and `GET /engine` are the same switch on the
loopback surface.

**Wispr recorded in both modes until 2026-08-26, and that was deliberate**: the
local engine transcribed `History.audio` — the complete 16 kHz WAV Wispr already
stored, the same bytes Wispr's own recogniser scored — so there was no microphone
code, no new TCC grant, no second capture that could drift from the first, and a
genuinely like-for-like comparison in live use. That was the step that answered
whether owning the microphone was worth the work. It was.

**Local Whisper now records for itself, and Wispr is out of the loop entirely.**
See *Mouse 5 is the relay's on Local Whisper* below. The Wispr-recorded path is
still there and still the one that runs on the Wispr engine, and it is still what
a `POST /test/transcript` replays.

- **A daemon, not a subprocess per dictation, and that is measured.** Importing
  `mlx_whisper` costs 7.4s and the first transcription another 2.8s for the
  weights, against 1.3s once warm. Shelling out each time would put ten seconds
  between the end of a sentence and the agent seeing it. `helpers/whisper_helper.py`
  starts once, warms up on a second of silence, and answers one JSON line per
  request at ~0.1× the audio's duration.
- **A bind that has to wait for the model opens the microphone itself.** ⌘⌃D
  means "I am about to talk to this agent", and on a cold model that intention was
  costing ten seconds of waiting followed by a mouse 5 he had to remember to
  press — with the ready-flash saying "go ahead" to a relay that was not
  listening. `recordWhenModelReady` is set only when the **bind** asked for the
  load: a load started from the menu is Victor choosing an engine, a different
  sentence, and must not open the microphone.
- **⏳ in two places while it loads, and that is the whole point of the setting
  being visible.** The model takes ten seconds, and a dictation started inside
  that window is silently handed to Wispr by the fallback — so what has to be
  said is "not yet". The chip beside the cursor shows `⏳ folder@branch`, taking
  the slot ⏸️ uses and outranking it for those seconds; the menu bar shows
  `⏳🤖`, which is the half that survives him typing, since macOS hides the
  pointer then and the chip goes with it. `AppDelegate.setEngineLoading` drives
  both from one call so they cannot disagree, and `StatusItem.refreshGlyph`
  arbitrates the glyph because pause and loading are set from different places
  and both own it. Loading ends with **`🎙️ local Whisper ready — go ahead`** —
  worded as permission, because the question he has been holding for ten seconds
  is whether he may talk yet. The reverse direction is instant and says so
  anyway (`🎙️ Wispr Flow — ready`): "did that take?" is the same question both
  ways and only one of them answers itself.
- **Started only when selected, and stopped when deselected.** The weights are
  1.5 GB resident and the ordinary case is a relay running all day on Wispr — **measured: the relay alone is 56 MB, the
  helper 2.5 GB once a transcription has run**, and it is 0 on Wispr because
  nothing is started. A A
  relay that starts up *already* set to Whisper loads the model at launch rather
  than on the first dictation — otherwise the choice would silently cost ten
  seconds mid-sentence and the fallback would hand that dictation to Wispr,
  which is the one confusion this feature must not create.
- **The tick follows the engine actually in use.** Choosing Local Whisper starts
  something that takes ten seconds and can fail outright (no `mlx_whisper`, most
  likely), so the setting is written only once the model has answered; a failure
  leaves Victor on Wispr with a banner saying why. This is why `AppDelegate`
  calls `setEngine` back rather than the click handler moving the tick itself,
  and why `POST /engine` answers **202** rather than 200.
- **A dictation is never dropped for the sake of a setting.** Model not up,
  helper dead, no audio on the row, low confidence — every one of those falls
  back to Wispr's own text, because Victor said something and an agent is
  waiting. Each fallback is logged *and* flashed: an engine silently not being
  used would corrupt the very evaluation this exists for.
- **The confidence floor is −0.6 and is measured, not chosen.** Over 442 real
  dictations, a gate on the worst segment's `avg_logprob` at −0.6 caught 7 of
  the 11 semantically broken outputs and falsely rejected **0 of 40** good ones;
  `no_speech_prob` caught none of them. Those 11 are not mildly wrong, they are
  fluent inventions — `Nu uitați să vă abonați la revedere!` for a sentence
  about an invoice — which is the one failure an agent cannot defend against,
  because nothing about the text looks wrong. Nearly all are clips under 5s.
- **The corpus is collected under both engines**, deliberately: it is Wispr's
  audio either way, so samples keep accumulating while the local model is on
  trial and switching back and forth does not punch holes in the record.
- `POST /test/transcript {"id": …}` replays a real Wispr row through this whole
  path. `/test/dictation` enters *below* it with a fabricated string and no
  recording behind it, so it can say nothing about which recogniser is in use.

### What the local model is actually worth, measured

442 dictations, 163 minutes, `mlx-community/whisper-large-v3-turbo`, scored
against Wispr as the reference — a **disagreement** rate, not an error rate,
since there is no ground truth here (see the `editedText` note above).

| | all | ro | en |
|---|---|---|---|
| semantic similarity | 0.918 | 0.908 | 0.948 |
| rare-word recall | 87.1% | 84.2% | 94.9% |
| WER | 19.4% | 21.1% | 12.8% |

86.0% of transcripts land semantically equivalent (>0.85), 11.5% degraded, 2.5%
broken. **The broken ones are almost all short**: 13.6% of clips under 5s
against ~1% of everything longer. Median speed 0.105× realtime.

Two things that sound true and are not: the Romanian errors are **not** mostly
morphology — content-WER with words stemmed to five characters and stopwords
dropped is 21.8%, i.e. unchanged, so they are wrong words rather than wrong
endings. And plain WER badly understates the model, because the transcript is
going to an agent and not into a document: casing, punctuation and verb endings
cost WER and cost the agent nothing, while a mangled identifier costs the agent
everything and is what rare-word recall is there to measure.

### The menu says what the model costs

While the helper is up, the Local Whisper row reads `Local Whisper — 1.6 GB`,
read when the menu opens (like the header) rather than pushed on a timer.

The number is `ri_phys_footprint` from `proc_pid_rusage` — Activity Monitor's
"Memory", not `ps`'s RSS, because MLX puts its weights in unified memory and the
two disagree on the same process. The question being answered is "what am I
paying for this?", which is Activity Monitor's question.

**It is shown where the choice is made.** The weights being 1.5 GB resident is
the whole argument for starting the helper only when the engine is selected and
killing it the moment it is not — and until now that cost was a number in a
comment, which is exactly where a fact nobody can check belongs. Beside the row
that turns it on, it is also proof the helper is alive: a dead one has no
footprint and the row goes back to its bare name.

### The wheel is the relay's; mouse 5 is Wispr's, whole

Until 2026-08-29 the relay took **mouse 5** on Local Whisper — the same button
Wispr Flow uses for push-to-talk — so every dictation began with the question of
which of the two was armed. Victor's call: mouse 5 goes back to Wispr alone (the
tap only *observes* it, `onDictationStarted`), and the relay drives `MicRecorder`
from the **wheel**.

**The wheel says three things, and the length of the press separates them:**

| state | press | verdict |
|---|---|---|
| idle | hold 400ms | start a dictation |
| dictating | tap | end it — transcribe and send |
| dictating | hold 400ms | **cancel** it — throw the audio away |

Holding is the deliberate half in both states, and in both it is the half that
cannot be taken back: starting a recording of a room, or discarding a sentence
already spoken. A tap is the ordinary outcome and costs nothing to repeat. The
hold reads the state **when it fires**, not when the button went down — a
dictation can begin or end inside those 400ms, and what the hold means is decided
by the state it lands in.

Cancelling from the wheel is the same verdict as the menu's `Cancel Dictation`,
and the same one as pressing Cancel on the panel a moment later — without waiting
for the model to transcribe something already known to be unwanted.

**A tap while nothing is recording is given back.** It means nothing to this app
in that state, so the click is **replayed** as a synthetic middle click and
Chrome goes on opening links and closing tabs. That is what makes the wheel
affordable at all: it was swallowed outright for as long as a terminal was
bound — hours — for a gesture Victor uses in a browser all day.

Every press is swallowed first and judged on release, because the decision cannot
be made when the button goes down — which is also why ending a dictation now
waits for the finger to lift, the price of the same button being able to cancel
one. The alternative — pass the press through and
swallow only the release — leaves whatever is underneath holding a button that
never came up, which is the orphan-event bug this file guards against twice
already, pointing the other way. The replay is let past the tap by a 0.3s time
window (`wheelReplayUntil`) rather than by a tag on the event: a tag that failed
to survive posting would be an infinite loop, where a window that fails is one
click let through.

**A toggle, not a push-to-talk.** Wispr's button is held down for the length of
the sentence, which is right for a sentence; a dictation aimed at an agent runs
to a minute or more, and a mouse button held for a minute is a hand that cannot
take the screenshots (mouse 4, F3) the same minute exists for.

`MicRecorder` opens the input device at its native rate and converts to 16 kHz
mono 16-bit through `AVAudioConverter` — the format Whisper resamples to anyway
and the format every existing corpus sample is in. Anything under 0.35s is
dropped as a misfire. The microphone is asked for **when the engine is picked**,
not at the first press: the grant dialog is modal and a refusal costs a trip
through System Settings, and mid-sentence with an agent waiting is the wrong
moment to find out.

**A local recording is sent even below the confidence floor**, unlike the
Wispr-recorded path, and the difference is not an oversight. There, a low
`avg_logprob` meant falling back to Wispr's own reading of the same audio; here
Wispr never heard the sentence, so the alternative to a shaky transcript is
silence — and silence is the one outcome Victor cannot notice and correct. The
banner says the score instead.

**The menu can start, end and cancel one.** `Start Dictation` / `End Dictation` /
`Cancel Dictation` sit under Disconnect and
calls the same `stopLocalRecording()` a second mouse 5 does — the transcript is
made and sent exactly as if the button had ended it. It exists because mouse 5 is
a thumb button on one specific mouse, and a dictation started at the desk has to
be closable from the trackpad or after that mouse's battery has gone; recording
is the one state where not reaching the button costs the dictation *and* leaves
the microphone open.

The row is **hidden outright on the Wispr engine**, not greyed: there the
recording is Wispr's, started and ended on Wispr's own button, so a row claiming
to stop it would be a promise the app cannot keep. On Local Whisper it is always
visible and merely disabled while nothing is being recorded — the way Disconnect
is while nothing is bound — since it is then the only line in the menu that says
whether the microphone is open at all. Both answers are read when the menu opens
(`StatusItem.isRecording`), like the footprint above, because the flag flips on
every dictation.

The corpus keeps growing in this mode (`VoiceCorpus.captureLocal`), stamped
`engine: "whisper-local"` and with **no `asr` field**: there is one reading and no
second opinion, and a manifest that duplicated the text into both fields would
read as a comparison that never happened.

### Wispr's paste is swallowed

Wispr drops its transcript wherever the caret is. The relay has always taken the
words from Wispr's database instead, which made that injection pure damage: a
sentence about a page he is reading, typed into the document, the search field,
the terminal.

`HotkeyTap.blockInjection` drops every keyboard event **posted by Wispr Flow's
own process** — matched by source pid, the same discriminator that tells a
LinearMouse Return from a typed one, and cached per pid because it runs on the
tap for every key of a transcript. All three keyboard event types are covered:
half a synthetic ⌘V is worse than all of it, since the target app would be left
holding a ⌘ that was never released.

**Off while paused**, and that is what pause has always meant: pausing is what
Victor does *in order to* dictate into an app, so the app getting the text is
then exactly the point.

Each burst logs one line (`🛑 swallowed Wispr injection — …`) with the first
event's keycode, flags and unicode payload, then a tally. That line is also the
measurement: if Wispr ever stops going through posted events — if it starts
writing the text through the Accessibility API — nothing will be logged, because
no event tap can see that, and this block will silently stop working.

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

- `kill -USR1 <pid>` → `<home>/snapshot.png`, the view drawing itself. This is
  how `docs/*.png` are made: `RELAY_DEMO=1` for the content, USR1 at each state,
  composite onto a dark backdrop. A panel's blur is missing from the shot (the
  window server draws it, not the view); the chip comes out exactly as he sees it.
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
Entered by a prompt and by a flash. **Nothing else.**

**Paused is not a panel state.** It was, on the argument that pausing was the
only route to a ✕ at rest. The menu bar now carries Pause/Resume *and* Quit, so
that argument is gone — and what was left was a half-screen panel parked over his
work for the whole time he dictates into other apps, which is minutes, saying
something he entered on purpose. It stays a chip: `⏸️ 🤖 folder@branch`, at 0.30.

**Dictating is not a panel state.** It was, and that put a half-screen window
over his work for the entire time he talked, to report a state he had just
entered on purpose. The panel is now for the one thing he must actually read:
what Wispr heard, while Cancel can still stop it. That is also why the F3 receipt
is a number in the recording row and not a `flash(_:)` — a flash is a panel, and
taking a picture mid-dictation must not throw one across the screen.

Tracking has two modes, and the second is what keeps the chip catchable:
*engaged* pins it to the cursor every frame at 60 Hz (anything lazier reads as
lag, because it is lag), and after ~0.25s of stillness it *settles* and stays put
until the cursor travels 70px. Growing into the panel is animated (0.22s ease
out); everything else resizes instantly.

## The pointer is clean when nothing is bound

**Unbound and idle, there is no overlay window on screen at all** — not a faded
one, not an empty one. `RelayWindow.refreshPresence` orders the panel out.

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
instead of adding a row have to be named there explicitly: bound, paused, and
the model coming up. A row added later keeps the chip on screen without anyone
remembering to come back and edit that condition.

Coming back, it is `reposition`ed first: it may have been away for hours, so it
lands where the pointer is now rather than reappearing wherever it was last
parked.

## The menu bar item

`StatusItem.swift` puts a 🤖 in the menu bar for the whole life of the process,
with **where the words go** as a disabled header — the destination app's icon
beside `Bound to: folder@branch` of the bound session — and two commands:
**Pause/Resume** and **Quit**, plus the two engine rows.

The chip shows the same line **without** the `Bound to:` prefix, and that is not
a drift between them. Beside the cursor a folder name has nothing else it could
be naming; in the menu it sits above `Pause` / `Disconnect` / `Stop Recording`,
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
what is happening; and the ✕ lives only on the panel, so ending a session at rest
meant pausing first just to make a panel to close. The menu bar is the one place
that is always in the same pixels.

The label is read in `menuWillOpen`, not pushed on a timer — with two overlays up,
two identical 🤖 say nothing about which session a click is about to end, and the
only moment the answer has to be right is the moment he is looking at it.

**Pause is here and not only on the chip** because the chip is a moving target —
it rides the cursor and vanishes while he types — and pausing is something he
does *on his way into another app*, i.e. precisely when he has no patience to
chase a label around. The item is worded as the verb it performs (`Pause` while
running, `Resume` while paused), not as a checkbox of the current state, and the
menu bar glyph becomes `⏸️🤖` — the same order as the chip. That glyph matters:
while he is typing the chip is hidden, so the menu bar is then the only thing on
screen saying forwarding is off. `AppDelegate.togglePause(reason:)` is the single
switch behind both routes, so the two can never disagree.

Quit goes through the same `endSession(reason:)` as the ✕, so the outbox still
gets its `session_end` before the process dies. There is no ⌘Q key equivalent:
the app is `.accessory` and never becomes key, so the hint would advertise a
shortcut that does nothing outside the open menu.

### The 🤖 on the other screens

`NSStatusItem` appears in exactly one menu bar: the display that currently has
the keyboard focus. Victor works across three, and the state that glyph carries —
paused, model loading — is precisely what he needs while looking at one of the
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
| paused | 0.30 |
| idle chip | 0.80 |
| every panel state | 1.00 |

The chip is translucent because it now rides over his actual work and has to read
as an overlay; the panels are opaque because each of them exists to be read.

Paused keeps 0.30, because there the fade *is* the message: forwarding is off,
and the overlay should look switched off.

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

Hold ⌘⇧ over a page **while dictating**, the element under the cursor is outlined
and named; ⌘⇧-click and its selector joins that dictation. It resolves the demonstratives — "make
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

`ElementPicker.dictating` is set from the same `listening && !paused` as mouse 4,
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

While dictating and before he has picked anything, the row reads `select element
⌘⇧🖱️`. After the first pick it gives way to `×2 div#cart > span.price`, because
the question changes: before, the only thing worth saying is *that this is
possible*; after, he knows the gesture, and what he cannot check without a name is
whether the click caught the button or the div wrapped around it.

**The row leads with the outcome, not the mechanic.** It read `hold ⌘⇧🖱️` for a
while, on the argument that the gesture arms only after 400ms and a bare `⌘⇧🖱️`
would describe a click that does nothing. But a hint whose first word is *hold*
spends the only words it has on how to press the keys and never says what
pressing them is for; `select element` says the thing that is not guessable, and
the delay stays discoverable by trying it once.

**The glyph is Chrome's own icon**, `NSWorkspace.icon(forFile:)` on whatever
`com.google.Chrome` resolves to — looked up, never shipped, so no version of the
logo is frozen into the repo and a restyle arrives on its own. `pickGlyph` is
therefore an `NSImageView` and not a label, and `pickGlyphWidth` is the constant
`pickGlyphSize` rather than a font measurement: an image has no metrics to ask.
It replaced a 🎯, which said "aim at something" — which is what the words beside
it already say — where the browser the gesture only works in was said nowhere.

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
means exactly what Chrome says it means), and the same refusal covers **paused**
and **not currently dictating**, which is now the common case.

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
