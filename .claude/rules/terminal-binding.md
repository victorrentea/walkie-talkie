---
paths:
  - "Sources/WalkieTalkie/TerminalBinding.swift"
  - "Sources/WalkieTalkie/IDEBridge.swift"
  - "Sources/WalkieTalkie/BindFlight.swift"
  - "Sources/WalkieTalkie/RebindHistory.swift"
  - "Sources/WalkieTalkie/UnbindPop.swift"
  - "relay-restart.sh"
---

# Terminal binding

Rules for pointing the relay at a terminal, delivering into it, and keeping that binding across restarts: the handle, the shell guard, the IDE bridge, the envelope, the bind flight, the chip's bound row, ⌘⌃B, Rebind to…, liveness, the loopback routes and `relay-restart.sh`. Full history and reasoning: docs/journal.md — see the sections named after each rule below.

## What can be bound, and what the handle is

- **Only Terminal.app tabs, tmux panes and editors `IDEBridge` recognises get bound; refuse everything else outright.** `bind` used to send every non-Terminal app down the paste path, so ⌘⌃B while looking at Chrome bound Chrome and typed the next dictation into whatever field held the caret — proven, with the screen locked, by binding `loginwindow`. → journal: *Only terminals get bound*
- **The handle is never a window.** A window reference is stale by the second dictation (tabs get dragged between windows, Spaces move, order changes); all three cases are things the terminal can re-resolve:

  | case | address | how it delivers | guarded? |
  |---|---|---|---|
  | `.terminalApp` | the **tty** | `do script … in <tab with that tty>` | yes |
  | `.tmux` | the **`%pane`** | `send-keys -l` then `Enter` | yes |
  | `.keystroke` | the **pid** | clipboard → activate → ⌘V → Return → focus back | **no** |

  The first two do not touch focus at all (verified against a raw-mode reader with the target window behind others). Only `.keystroke` brings the app forward, for ~200ms, and puts focus and clipboard back. → journal: *The handle is never a window*
- **`bind(tty:)` normalises through `devicePath()` — the one door a caller-supplied tty comes through.** Callers hand both spellings (`SpawnTerminal` returns `/dev/ttys014`, `POST /bind` carries the short `ttys014` that `relay-restart.sh` reads out of `bound-tty`), and every AppleScript in `TerminalBinding` compares against Terminal.app's own answer, which is the path. The short form built a `Target` that *looked* bound and could never find its tab: no title, no window frame, `→ re-bound to ttys014` from the restart script on a binding whose first delivery came back `targetGone` — that way since the restart route was written (2026-09-09). Proven by the first rebind after the fix logging `window at 765,561 945×516` where it had logged `frame unknown`. → journal: *`bind(tty:)` normalises the tty, and that fixed a silent bug*
- **Binding takes the first port that answers, not all of them** (unlike the Chrome extension): pointing every relay on the machine at one terminal would deliver every dictation there two or three times. → journal: *⌘⌃D is this app's own key (since 2026-08-26)*

## The shell guard

- **Run the guard before every delivery, never once at bind.** Victor hits Escape or the agent exits, the tab goes back to a prompt with the binding still pointing at it, and at a prompt a dictation is not typed at an agent, it is **run** — *"Șterge tot ce e în folderul de build"* said out loud is a real `rm`. → journal: *The shell guard is the load-bearing part*
- **It is a shell test, not an "is this Claude Code" test, and it fails closed.** What makes a delivery dangerous is precisely that a shell is reading the line; `claude`, `node`, an editor, a REPL merely receive stdin. Naming the agent would mean guessing how it appears in `ps` every release. A target that cannot be interrogated counts as a shell. → journal: *The shell guard is the load-bearing part*
- **Read the whole foreground job, not its first process** (2026-09-08). A prompt is a foreground group that is *only* a shell; any non-shell in the group means a program is running. Reading only the first `+` line made Copilot CLI in a VS Code terminal permanently undeliverable: Copilot Chat launches it through `…/globalStorage/github.copilot-chat/copilotCli/copilot`, a `#!/bin/sh` script that does **not** `exec`, so the job is `sh` → `Code Helper (Plugin)` → `copilot` → its MCP servers and the guard read `sh`. Measured on ttys014: every dictation refused as "would run as shell" while an agent sat waiting for one. A nested interactive `bash` — one shell alone in the group — is still refused. The reported name skips app-bundle helpers, so that job says `copilot`, not `Code Helper (Plugin)`. → journal: *The shell guard is the load-bearing part*
- **IDE targets are guarded since 2026-09-10; only `.keystroke` is unguarded.** `/bind` returns the shell's pid, the relay resolves a tty from it and runs the same `foregroundIsShell` test — verified refusing `rm -rf build` on VS Code with zsh at the prompt, and `echo THIS MUST NEVER RUN` on IntelliJ. No pid means unguarded, not refused: `isGuarded` is false and the bind flash says `— no shell guard`. The chip does not distinguish them; `GET /target` carries `guarded`. → journal: *IDE terminals go through the editor's own extension*
- **`tmuxPane` checks `list-clients` before `display-message -c`.** Handed a tty attached to nothing, `tmux display-message -c <tty>` silently falls back to tmux's own current client and answers with **that** pane — a plain Terminal tab bound to whichever pane a detached `claude-rc` session happened to have focused. A wrong pane is indistinguishable from a correct bind until a sentence lands in somebody else's window. → journal: *tmux: `display-message -c` does not refuse*

## IDE bridge (`IDEBridge.swift`)

- **Deliver into VS Code and IntelliJ through Victor's own extensions, never by pasting.** `victor-vsc`'s `relay-terminal.js` and `live-coding`'s `RelayTerminalService` publish a loopback listener under `~/.walkie-talkie/ide/`; the relay asks which terminal is selected and hands it every later line, and the extension calls `sendText` / `sendCommandToExecute` on **that** widget. The old `.keystroke` path addressed the *application*; four deliveries on a bound IntelliJ landed correct, correct, **into the source file plus a Return** (caret in the editor), and in the wrong terminal (a second tab) — all logged `delivered`. On 2026-08-15 that put a dictation into `OwnerRestController.java`; the backend hot-compiled it and the endpoint answered 500. → journal: *IDE terminals go through the editor's own extension*
- **The focused window disambiguates via `/ping`.** Two VS Code windows are two extension hosts; the relay takes the one answering `focused`, and believes a single candidate without the flag (⌘⌃B can land a beat before the answer settles). Process-tree matching identifies the *application*, which is the granularity that was never the problem. → journal: *IDE terminals go through the editor's own extension*
- **A per-run secret gates the listener** — it types a line into a shell and presses Return. → journal: *IDE terminals go through the editor's own extension*
- **Find VS Code's window with `CGWindowListCopyWindowInfo`, not Accessibility.** Electron builds its AX tree lazily: `kAXFocusedWindow` answers `cannotComplete` (-25204, measured) for every VS Code window, which silently skipped the bind flight there. Do not set `AXManualAccessibility` on the app: VS Code answers it by switching the editor into screen-reader mode. → journal: *IDE terminals go through the editor's own extension*
- **Write the text, then `\r` separately 120ms later.** Both extensions' own APIs append `\n`, which in a raw-mode TUI is *insert a newline*, so the dictation sat in the prompt until Victor pressed Return (reported 2026-08-26). The gap is the same reason tmux has always been two calls: a TUI reading `text\r` in one chunk takes it for a paste and keeps the Return as text. → journal: *IDE terminals go through the editor's own extension*
- **Send `line`, never `text`.** The IDE branch used to send the unflattened message — the one path that could not survive an embedded newline was the one path that did not strip them. → journal: *IDE terminals go through the editor's own extension*
- **The far end must JSON-parse the body.** `IDEBridge.send` serialises with `JSONSerialization`; the IntelliJ plugin's `/send` picked the string out with a regex and unescaped only `\"` and `\\`, so between 2026-09-07 and 09-10 every delivery arrived as one run-on line with a literal `\n\n` in it. VS Code calls `JSON.parse` and never had it. `RelayTerminalService.unescapeJson` now handles the whole escape set in one left-to-right pass (the old pair also turned `\\"` into a bare quote). → journal: *The words, a blank line, then one clause per line (2026-09-07)*
- **IntelliJ's connector must be unwrapped (`RelayTerminalService.unwrapProxy`).** Its connector is a `BackendTtyConnector` even for a local tab; the wrapper is a `ProxyTtyConnector` whose `getConnector()` returns the ordinary `PtyProcessTtyConnector`. `shellPid` searched the wrapper's hierarchy for `getProcess` and answered nil for three weeks; unwrapped, IntelliJ answers `shellPID: 9323`. What Victor saw was only a `⚠️` (*"No Shell Guard"*) on a bind that was working. → journal: *IDE terminals go through the editor's own extension*
- **`.keystroke` survives as the fallback** for a known editor with no extension answering, and is logged as such. → journal: *IDE terminals go through the editor's own extension*

## The envelope

- **Words first, a blank line, then one bracketed clause per line** (`AppDelegate.terminalLine`, 2026-09-07). *"One line, always"* is expired. Verified end to end: bytes through a real `do script` into a non-shell reader, then into a live Claude Code session, which received *one* prompt answered once, not five times. → journal: *The words, a blank line, then one clause per line (2026-09-07)*
- **Separators are `\n`; nothing may send `\r` except the submitting Return.** In a raw-mode TUI `\n` inserts a newline (how Claude Code takes a multi-line prompt); `\r` submits half the sentence. → journal: *The words, a blank line, then one clause per line (2026-09-07)*
- **`TerminalBinding.escape` spells a newline `\n` for AppleScript.** Its string literals cannot contain a raw one — without this the script does not compile and the delivery disappears silently, with no error anywhere. `singleLine` still normalises whitespace *inside* each line, so the structure is the app's, never the recogniser's. → journal: *The words, a blank line, then one clause per line (2026-09-07)*
- **Shots travel as paths, not a `📸 ×2` count.** An agent can do nothing with a number and everything with something to `Read`; `[selected: …]`, `[look at: …]`, `[context: …]`, `[elements I picked in Chrome: …]` mirror the outbox keys. → journal: *The words, a blank line, then one clause per line (2026-09-07)*
- **Keep `[this text was dictated in RO or EN]`, on dictation only, naming both languages always.** A transcript looks typed, so a mis-heard word reads as chosen: the recogniser turned `Wispr Relay` into `risparerile ei`. The detected code was tried for one commit and dropped — plain Romanian came back labelled `en` in the very recording used to test it, and a clause naming the wrong language aims the phonetics at a language the words were never said in. Do not add advice after it (*"skip the rest of details - are obvious"*). → journal: *The words, a blank line, then one clause per line (2026-09-07)*

## The bind flight (`BindFlight.swift`)

- **One panel per screen — nothing else works.** A single panel spanning the union of displays measured `-1920,0 5568×2197`, laid the layer exactly on the source window, and still drew on one screen: `com.apple.spaces spans-displays` is unset by default, so each display has its own Space and no window spans two; `canJoinAllSpaces` does not buy it back. `constrainFrameRect` was also genuinely clamping (plain `NSPanel` never inherited `RelayPanel`'s override) — fix both. Verified by burst-capturing a non-primary display: strong-blue pixels 178 → 3070 the frame the rectangle arrived. → journal: *The bind flight*
- **Convert the source frame with `cocoaRect`.** AppleScript `bounds` and AX measure y downward from the top of the primary display; Cocoa upward from its bottom. They agree only on the primary screen, so the mistake stays invisible until a second monitor is plugged in. Verified: `{200, 150, 1000, 700}` → `200,417 800×550` with a primary 1117 tall. → journal: *The bind flight*
- **`landed` never fires on cancel.** A replacing bind cancels the old flight; the old answer must not land on top of the new one. The chip label appears the instant the rectangle arrives (`BindFlight.fly(from:landed:)`), and the bind flash is sized to `BindFlight.duration`. → journal: *The bind flight*
- **Grab the window pixels with `CGWindowListCreateImage` on the screen rectangle, not `screencapture`.** A subprocess waited on is ~200ms, a fifth of the 1s flight; fall back to the hollow rectangle if the grab returns nothing. Opacity 100% → 50%, first eighth standing still, cursor re-read every frame. → journal: *The bind flight*

## What the chip says when bound

- **One row: the destination app's real icon + `folder@branch`.** `AppDelegate.appIcon` asks the bundle on disk, not the running app (whose `icon` is lazily loaded and often nil). The IDE path used to show a raw path (`/` for a shell at the root) because it skipped `label(forDirectory:)`. → journal: *What the chip says when bound: one row, and the destination app's own icon*
- **The folder is `lastPathComponent` + `@branch`, never truncated, re-read on the poll (`refreshBinding`).** Victor `cd`s between repos inside one session all day. → journal: *What the chip says when bound: one row, and the destination app's own icon*
- **Read the session directory from `~/.claude/cwd/<ttysNNN>` (`publishedDirectory(forTTY:)`), process cwd only as fallback.** `lsof -d cwd` gives the launch directory: a live session working in `walkie-talkie` answered `~/workspace` (and no branch, since `~/workspace` is not a repo). `TERM_SESSION_ID` is unreadable — macOS shows a process's environment only to its descendants (2926 bytes for an ancestor, 4 for an unrelated terminal). The status line publishes under its **parent's** tty; the read checks the directory still exists, since tty numbers are reused. → journal: *What the chip says when bound: one row, and the destination app's own icon*
- **The title row is Terminal.app's `custom title` / tmux's `#{pane_title}` / the IDE's AX window title, truncated from the head (`fitHead`).** A title puts its subject first. With no title, fall back to the address (`ttys004`). The folder row is absent for targets with no tty (`Target.folder` nil). → journal: *What the chip says when bound: one row, and the destination app's own icon*
- **Glyphs are drawn (`Glyphs.swift`) and rasterised once** (`pinGlyph`, `folderGlyphImage`); the chip relayouts sixty times a second. → journal: *What the chip says when bound: one row, and the destination app's own icon*

## ⌘⌃B and ⌘⌃D

| key | call | note |
|---|---|---|
| **⌘⌃B** | `onBindHotkey` → `bindFrontmostTerminal` | was ⌘⌃D until 2026-09-01 |
| **⌘⌃D** | `onLocalToggle` → `toggleLocalRecording` | new — the wheel's click, from the keyboard |

- **⌘⌃B on the already-bound target unbinds; compare by handle, not by app.** Two Terminal tabs are two ttys, so a press in another tab re-points. It calls the same `unbindTerminal` as `POST /unbind` and the menu's **Disconnect**. → journal: *⌘⌃B again on the same target lets go of it — the chord does not*
- **It unbinds, it does not quit** (since 2026-08-28) — quitting undid a binding **plus a login item**. → journal: *⌘⌃B again on the same target lets go of it — the chord does not*
- **No `session_end` goes out on unbind.** It is the Disconnect route; a second ⌘⌃B can point back. Quitting (✕, menu **Quit**) still announces itself. → journal: *⌘⌃B again on the same target lets go of it — the chord does not*
- **Swallow autorepeat on both keys** (`HotkeyTap`): a held key would bind and immediately end the session it started. The left-plus-wheel chord is exempt from the toggle (`bindFrontmostTerminal(toggle:)`, since 2026-09-01); ⌘⌃B and `POST /bind` keep it. → journal: *⌘⌃B binds, ⌘⌃D dictates (since 2026-09-01)*
- **This app is the only owner of ⌘⌃B/⌘⌃D**; nothing about the bind key remains in Victor Addons. ⌘⌃⌥D is Addons' dark-mode toggle, told apart by ⌥. → journal: *⌘⌃D is this app's own key (since 2026-08-26)*

## Rebind to… (`RebindHistory.swift`, `UnbindPop.swift`)

- **`RebindHistory` is a log of bindings, keyed by `address` (`ttys016`, `%3`, `IntelliJ IDEA`), capped at twelve, persisted to `~/.walkie-talkie/rebind-history.json`.** No LLM, no transcript search (*"strict ceva recent, fără niciun LLM"*): `claude -p` costs 13 s for sonnet and 17 s for haiku on this Mac. → journal: *Rebind to: the destinations already spoken to, most recent first (2026-09-10)*
- **Every bind goes through the single private `adopt`, which stamps the outgoing binding.** A binding ends in `unbind()`, in a `targetGone` delivery, or — the common one — by a displacing bind that passes through neither; stamping only in `unbind()` would have every row claim it was let go hours later. → journal: *Rebind to: the destinations already spoken to, most recent first (2026-09-10)*
- **✨ means this app opened the window; passed at `adoptSpawnedWindow` → `bind(tty:spawned: true)` and sticky.** `★` is `SpawnFolderMenu`'s. → journal: *Rebind to: the destinations already spoken to, most recent first (2026-09-10)*
- **One AppleScript for all titles: `TerminalBinding.liveTitles()`**, ~30 ms for the machine, about one `title(forTTY:)`. It doubles as liveness: a remembered tty missing from the map is greyed, not deleted. → journal: *Rebind to: the destinations already spoken to, most recent first (2026-09-10)*
- **A dispatched pop-up at the pointer, not a submenu.** AppKit reserves the disclosure-arrow gutter on every row once one item has a submenu, which shoved `layOutGestures`' column (*"a fugit toată coloana de meniuri din cauza >"*). Dispatch it: a menu put up inside the closing click lands underneath and takes no clicks. → journal: *Rebind to: the destinations already spoken to, most recent first (2026-09-10)*
- **Plain titles, so disabled rows dim** (the bound one, closed windows, IDE panels with no tab). → journal: *Rebind to: the destinations already spoken to, most recent first (2026-09-10)*

## Liveness (`checkAlive()`)

- **Three answers: `.gone` only on a definite answer, `.unknown` on silence, and `.unknown` does nothing.** *I could not ask* must never be spelled like *it is not there*. → journal: *A terminal that was closed lets go of the binding by itself (2026-09-07)*
- **Test a Terminal tab on *any* process on its tty — deliberately weaker than the delivery guard.** `foregroundCommand` answers nil for a live tab whose processes are all backgrounded; there it costs one refused delivery, here it would cost the binding silently. tmux is asked about the pane, never the tty. An IDE target is two questions: `NSRunningApplication` on the bundle id, and `IDEBridge.alive` — only a listener that **answered** `ok: false` may unbind. → journal: *A terminal that was closed lets go of the binding by itself (2026-09-07)*
- **Never while a sentence is in the air** (`listening || held != nil`), and let go quietly, without `report(.targetGone)`'s six-second warning. A reused tty can still point a binding at a stranger; that hole is out of this check's reach. → journal: *A terminal that was closed lets go of the binding by itself (2026-09-07)*

## Loopback routes and restart (`relay-restart.sh`)

- **`/bind`, `/unbind`, `/target` are not gated on `dictating`**; `POST /bind {"tty":…}` binds that session with no toggle, no flight, no flash. `/bind` on the bound terminal answers `{"unbound": true}`. → journal: *The loopback control surface*
- **Victor's rule, verbatim:** *"niciodată să nu mai dai restart la Walkie Talkie … în dictare — oprești și aștepți să se termine dictarea, să se livreze, abia apoi faci restart"*, then *"legat dar nu în dictare poți să-l restartezi totuși, ideal ar fi să-l re-legi la același terminal automat"*. It cost one on 2026-09-09. → journal: *Restarting keeps the binding, and never interrupts a sentence (2026-09-09)*
- **Read `~/.walkie-talkie/bound-tty` before standing the app down** (launch clears it): absent unbound, `ttysNNN` bound, `ttysNNN listening` while the microphone is open. Wait **six seconds** after the row stops saying `listening` — the decode and the held panel come after the microphone closes. → journal: *Restarting keeps the binding, and never interrupts a sentence (2026-09-09)*
- **Restore by tty, never the front window**, which at the end of a build is whatever the build was watched in. → journal: *Restarting keeps the binding, and never interrupts a sentence (2026-09-09)*
- **The retry waits ten seconds, not one.** A bind is one to two `osascript` round trips and the route answers only when finished; `curl -m 1` timed out on a bind that had succeeded, and the loop bound again: seven re-binds over 70 seconds after one restart, one stealing a binding Victor made by hand, another redirecting a caret dictation. The retry is for a port not yet open, which fails in milliseconds. → journal: *Restarting keeps the binding, and never interrupts a sentence (2026-09-09)*
- **A `.keystroke` target has no tty and cannot be restored**; the script says so. → journal: *Restarting keeps the binding, and never interrupts a sentence (2026-09-09)*

## Bind mid-sentence and the bind grace

- **A bind while recording redirects the sentence; only a deliberate bind may do this.** `deliverToTerminal` asks `terminal.target` when the panel resolves. `showBound` takes back `spawnPending` (since 2026-08-31) and `pasteMode` (since 2026-09-09) on a running recording — but `refreshBoundTitle` rides the 10s poll and calls `showBound` too, and the take-back once fired on the poll: *"după 2-3 sec de vorbit, fără să apăs niciun buton, tooltipul a arătat că s-a reconectat"* (fixed 2026-09-02). `showBound(_:deliberate:)` carries the difference; the poll is the one caller passing `false`. Only the sentence converts, never `replaceWispr`. The recipient is whoever the relay points at when the microphone closes; a bind during the hold changes nothing. → journal: *A bind mid-sentence changes the recipient*
- **A bind speaks for the next five seconds (`takeBindGrace`), armed in `bindFrontmostTerminal` only.** Measured 2026-09-09: 11:51:32 bound, 11:51:34 dictated at the caret; 11:55:45 bound, 11:55:48 dictated — 292 characters pasted into whatever had focus. Consumed by the first dictation that reads it; `replaceWispr` is never written. Not armed in `showBound`: `picker.onBindTTY` (the restart's restore) is not somebody pressing something. → journal: *…and so does the sentence that starts right after one (2026-09-09)*
- **A bind still resolving is a destination (`recordWhenBound`).** `bindFrontmostTerminal` spends 1–2 s in `osascript` (11:50:15 pressed, 11:50:17 bound) with `isBound` false, so a dictate gesture in that window did nothing, silently. Bank the press; a bind that finds nothing bindable drops it. → journal: *…and so does the sentence that starts right after one (2026-09-09)*

## `bound-tty` (`Outbox.publishBound`)

- **Publish the bare `ttysNNN`, never `/dev/ttysNNN`.** Publishing the path shipped once and matched nothing — no error, only a badge that never appeared. The handle keeps the device path (what AppleScript compares), `address` keeps the short form. IDE targets answer through `tty(ofPID:)` on the shell pid; a tmux pane answers the client's tty and fails to match rather than matching wrong; `.keystroke` has none. → journal: *The bound tty is published, so the status line can wear a microphone*
- **Written from `showBound` (binding) and `syncBorrowedGestures` (`listening`), one line with two words, a file not a route** — the bar re-renders every second in every session. → journal: *The bound tty is published, so the status line can wear a microphone*
- **Removed, never emptied; cleared at launch as well as at quit.** A marker outliving the process claims a binding that went with it. → journal: *The bound tty is published, so the status line can wear a microphone*

## Do not

- Do not set `AXManualAccessibility` on VS Code (screen-reader mode).
- Do not let any path send `\r` except the submitting Return; do not remove `TerminalBinding.escape`'s `\n` spelling.
- Do not paint the bound tab's `background color`: `~/.claude/hooks/session-color.sh` owns it and has the last word; `cursor color` is the only unclaimed per-tab property. → journal: *The bound tty is published, so the status line can wear a microphone*
