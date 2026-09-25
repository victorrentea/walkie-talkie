# Walkie Talkie — engineering journal

This is the complete narrative that lived in `CLAUDE.md` until 2026-09-11, when it was moved
out so that it no longer loads into every session: every decision, the reasoning behind it,
the things tried and reverted, the measurements, and Victor's asks in his own words. **Nothing
was cut or rewritten** — the original text follows the contents, verbatim and in its original
order, headings included.

The durable rules were lifted out into `CLAUDE.md` (always loaded — build, launch, data
locations, the English-only UI, the things never to reintroduce) and `.claude/rules/*.md`
(loaded only when a matching file is touched — the traps already paid for, per area of the
code). Read those for *what*; come here for *why* and for the history behind a rule.

## Superseded on the way

The journal contradicts itself over time, because it was written as things changed. The
**later** section always wins. The main reversals, so nobody re-derives an expired rule:

- *Unbound is inert*, *What the rule was, and why the premise expired*, *`awaitingBind`* — retired 2026-09-11 — with nothing bound the app does everything and holds the sentence for a bind (`holdsForBind`)
- *F10 nu mai comută dictarea de două ori pe un singur gest* (2026-09-16) — the guard was right and both of its numbers were wrong; superseded 2026-09-18 by *One slow flick right is one gesture, and it cannot close what it just opened* (sliding window, 0.6 s, plus a 2 s dwell before the flick may stop)
- *The oblique wipe: a message replaces a message*, *What the cancel actually looked like…*, *`WT_SHOOT_WIPE` — because this is the least reviewable thing in the app* — **retired 2026-09-18**: `ChipWipe.swift`, its rule file and the `WT_SHOOT_WIPE` harness are deleted; a chip message is swapped in one frame (*The chip swaps in one frame*)
- *The DJI receiver is the microphone whenever it is plugged in* (2026-09-01) — superseded 2026-09-19: *automatic* is a ladder, 🎙️ XLR ▸ 🎤 DJI ▸ 🎧 Bose ▸ 💻 built-in, and the receiver is its second rung (*The chip says which microphone, and the menu picks it*)
- *Wispr Flow everywhere (2026-09-12)*, and every later line making Wispr one of the engines — superseded 2026-09-22 by *Wispr Flow leaves the Engine list*: it is not selectable at all any more, and keeps only 🔽 →. The wrap sections are **not** retired — they still describe the mechanism accurately and it is what the row would come back to
- *`PasteHint` — `⌘⇧P`, said once and faintly* (2026-09-22; recorded in `.claude/rules/replace-wispr-and-halo.md`, not here) — superseded 2026-09-23: the hint follows **every** delivered sentence (caret, bound, spawn, a held sentence's release, Wispr's routed ones) plus a cancelled prompt, at **0.80 for 2.5 s then a 0.5 s fade**, where it was caret and cancelled prompt only, at 0.20, 0.8 s up / 1.2 s down. Victor: *"indiferent prin ce mecanism am închis o dictare … uneori îl plasez greșit, lasă-mă să-mi amintesc constant"*
- *What a caret dictation carries* (2026-09-08) and 2026-09-19's *no initial screenshot at the caret* — superseded 2026-09-23 for the **forward click**: its caret sentence is the whole terminal envelope (context frame, `[Dictated in RO or EN]`) and is submitted into a Claude Code prompt; the back click's sentence is the words alone, at the caret even when bound (*Forward is a prompt, back is plain words*)
- *The spawn menu offers five open terminals* (2026-09-23, morning; recorded in `.claude/rules/spawn.md`, not here) — superseded the same evening by *Active Terminals: the spawn menu's first row*: the terminals moved from a third half under the folders to a hover submenu on the menu's first row, filled from the Claude Code sessions running on the machine rather than from the bind log
- *Pause is gone* — still true; pause was removed 2026-09-01 and is not coming back
- *The ring round the pointer* → *Spokes* → *What ships: `codex3`* — each superseded by the next; what ships is *What ships now: his picture, and it runs as a film*, plus *It is the beacon now* (2026-09-11) and *`DropArrow`*
- *The beacon is gone* (2026-09-11) — `RecordingBeacon.swift` is deleted; the halo is up for every dictation
- *`DropArrow`: three dashes and a head, pointing down at the cursor* (2026-09-11) — superseded 2026-09-12 by *Six heads closing in, instead of one arrow hanging above*; the shaft, the dashes and the march are gone, and since 2026-09-22 the heads are **twice the size** while the words are in flight (*The arrows double while the words are in flight*)
- *The chip says which microphone, and the menu picks it* (2026-09-19) — the mark `Listening(🎙️/E)...` is superseded 2026-09-22 by *The chip says what is hearing him and what is reading it*: no brackets, no slash, no letter — the device is on `Listening to 🎤...` and the recogniser's **logo** is one row down on `Transcribing via ⬮...`
- *The wheel is the relay's*, *Double-clicking the wheel turns the dictation into a spawn*, *The right chord…*, *⌘ + the wheel* — live only with *Use Logi Gestures* unticked; the default since 2026-09-09 is *The side buttons speak in function keys*; the ~18 ms side-button measurement in *Double-clicking the wheel* is corrected there
- *Mouse 4 is the shutter* (LinearMouse / Victor Addons Return) — LinearMouse uninstalled 2026-09-07; in Logi mode the app posts the Return itself (*Use Logi Gestures*)
- *⌘⌃D is this app's own key* (since 2026-08-26) — the bind key is ⌘⌃B since 2026-09-01 (*⌘⌃B binds, ⌘⌃D dictates*)
- *One line, always* (folded into *The words, a blank line, then one clause per line*) — replaced 2026-09-07
- *The shell guard is the load-bearing part* — “`.keystroke` targets cannot be guarded” — IDE targets are guarded since 2026-09-10 through the extension's shell pid; only the `.keystroke` fallback is not
- *Replace Wispr* — “the back button is handed back” — the back button is the shutter in that mode since 2026-09-08 (*What a caret dictation carries*)
- *The agent gets an 800px copy* — earlier 1000 px — 800 since 2026-08-22
- *Autosend* — “no ⌘Q key equivalent in the status menu” — Quit carries ⌘Q since 2026-09-13; the About row is a disabled `Version:` readout (*Version row and ⌘Q (2026-09-13)*)
- *Rebind to: the destinations already spoken to, most recent first* — *"fără nicio căutare prin transcripturi"* was about a **model** picking a session (13–17 s in `claude -p`); since 2026-09-12 the same list has a search field over the transcripts that is `rg` and nothing else (*The list takes typing, and searches the session journals*)
- *The wait says how long* — `Transcribing... 4s` — digits gone 2026-09-08 (*The wait fills too*)
- *The menu says what the model costs* — “starting the helper only when a dictation is coming” — the model loads at launch since 2026-09-06
- *The mouse is drawn* — the three-row bound idle chip with gesture rows — `showsGestureHints` is off since 2026-08-30 (*The chip teaches nothing; the menu does*)
- *The shutter also takes the selection* — “the row is 28 tall” — 22 pt since 2026-09-02, mark in the icon column (*The tally*)
- *The folder menu* — hardcoded six, below-left — pinned + recent since 2026-09-08; below-right since 2026-09-06
- *The spawn's flight leaves the dialog* — `reversed:`, outline — the spawn flight carries pixels and runs forwards since 2026-09-09 (*The little terminal grows out of the dialog*)
- *Autosend* / *Replace Wispr* — “deliberately not persisted” — both persist since 2026-09-07
- *Replace Wispr*, *Every row has an icon* — “one menu tick”, the `🔼` legend, the `Replace WisprFlow` row — **the row is gone since 2026-09-14**, replaced by the `Engine` picker (*The engine is a choice with two names on it*); the mode, its flag and the forward button are unchanged
- *The menu says what the model costs* — the disabled `Local Whisper — 1.6 GB RAM` row at the bottom of the menu — the same string is the `Engine` row's title since 2026-09-14
- **The night of 2026-09-13/14 supersedes a great deal of the same night.** The wrap changed shape four times in eight hours and the earlier sections are kept because the reasoning is the evidence; *The night the wrap found its shape* is the one that holds. Specifically:
  - *The loopback closes: gestures, state, a sink and a delivery field* — “the sink is going to become the wrap itself” — **the sink is the emergency mode**, rejected as the primary path the same evening
  - *The wrap is Wispr's own Scratchpad* — “a new note per dictation”, “no ⌘V posted”, “focus never moved” — all three are wrong: Wispr **appends** with `source = typed`, it **does** post a ⌘V (aimed at its own note), and the window **takes the key focus**
  - *Parking the Scratchpad…* — “Wispr frontmost **and** the window its main one is the honest test” — it becomes key **without** becoming frontmost; the test is the system-wide focused element's owner
  - *The wrap is Wispr's own Scratchpad*, *Five runs…* — “the window opens when the note is written, ~2 s after the words” — it opens at the **start of the hold** and lives for the whole sentence
  - *The row is the delivery; the note is the second opinion* — “the delivery waits for the window to be gone” — the paste is **addressed** (`postToPid`) since 2026-09-14 and waits for nothing
  - *Five runs…* — “the swallow must be off in Scratchpad mode” — it is **on in every mode**; letting it through put every sentence in his document twice
- *The ring covers Wispr Flow's dictations too* (2026-09-11) — the ring's half was **silently lost on 09-12** when Wispr became the source, and is restored 2026-09-18 on a different witness (`wisprHearing`, not `WisprWatch`); the section's `atCaret` half is **reversed** — a microphone that is not ours raises the ring and nothing else (*The ring comes back for the dictations he starts himself*)
- *The folder menu*, *Autosend* — “the app is `.accessory`” — `.regular` with a Dock tile since 2026-09-07 (*The Dock tile is the escape hatch*)
- *Scope: dictation helper only* — “`canBecomeKey` is false” — the panel becomes key only while the transcript is edited (*⏎ sends it, and clicking the words edits them*)

## Contents

- [Walkie Talkie — working notes](#walkie-talkie--working-notes)
  - [UI language: English only](#ui-language-english-only)
  - [The overlay's states are photographed, and the page is part of the change](#the-overlays-states-are-photographed-and-the-page-is-part-of-the-change)
  - [Bound to a terminal: the second destination](#bound-to-a-terminal-the-second-destination)
    - [IDE terminals go through the editor's own extension](#ide-terminals-go-through-the-editors-own-extension)
    - [Only terminals get bound](#only-terminals-get-bound)
    - [The handle is never a window](#the-handle-is-never-a-window)
    - [The shell guard is the load-bearing part](#the-shell-guard-is-the-load-bearing-part)
    - [tmux: `display-message -c` does not refuse](#tmux-display-message--c-does-not-refuse)
    - [The words, a blank line, then one clause per line (2026-09-07)](#the-words-a-blank-line-then-one-clause-per-line-2026-09-07)
    - [The bind flight](#the-bind-flight)
    - [What the chip says when bound: one row, and the destination app's own icon](#what-the-chip-says-when-bound-one-row-and-the-destination-apps-own-icon)
    - [⌘⌃B again on the same target lets go of it — the chord does not](#b-again-on-the-same-target-lets-go-of-it--the-chord-does-not)
    - [Rebind to: the destinations already spoken to, most recent first (2026-09-10)](#rebind-to-the-destinations-already-spoken-to-most-recent-first-2026-09-10)
      - [`bind(tty:)` normalises the tty, and that fixed a silent bug](#bindtty-normalises-the-tty-and-that-fixed-a-silent-bug)
    - [The list takes typing, and searches the session journals (2026-09-12)](#the-list-takes-typing-and-searches-the-session-journals-2026-09-12)
      - [Which tab a session from Tuesday is in — the join nobody had to write](#which-tab-a-session-from-tuesday-is-in--the-join-nobody-had-to-write)
      - [A closed window is not a dead end: ⏎ reopens the session](#a-closed-window-is-not-a-dead-end--reopens-the-session)
      - [The panel's own corrections, in the order they were found](#the-panels-own-corrections-in-the-order-they-were-found)
    - [A terminal that was closed lets go of the binding by itself (2026-09-07)](#a-terminal-that-was-closed-lets-go-of-the-binding-by-itself-2026-09-07)
    - [The loopback control surface](#the-loopback-control-surface)
    - [Restarting keeps the binding, and never interrupts a sentence (2026-09-09)](#restarting-keeps-the-binding-and-never-interrupts-a-sentence-2026-09-09)
    - [⌘⌃B binds, ⌘⌃D dictates (since 2026-09-01)](#b-binds-d-dictates-since-2026-09-01)
    - [⌘⌃D is this app's own key (since 2026-08-26)](#d-is-this-apps-own-key-since-2026-08-26)
  - [The rename, and the two places the old name survives](#the-rename-and-the-two-places-the-old-name-survives)
  - [Scope: dictation helper only](#scope-dictation-helper-only)
  - [Unbound is inert — retired (2026-09-11)](#unbound-is-inert--retired-2026-09-11)
    - [What the rule was, and why the premise expired](#what-the-rule-was-and-why-the-premise-expired)
    - [The outbox half of the 2026-08-27 decision stands](#the-outbox-half-of-the-2026-08-27-decision-stands)
    - [`awaitingBind`: one sentence, five minutes](#awaitingbind-one-sentence-five-minutes)
    - [The one gate whose price is outside this app](#the-one-gate-whose-price-is-outside-this-app)
    - [Pause still does not come back](#pause-still-does-not-come-back)
  - [Pause is gone](#pause-is-gone)
  - [Title states](#title-states)
  - [The recording rows](#the-recording-rows)
    - [`Listening...` is a progress bar, and it fills on speech (2026-09-07)](#listening-is-a-progress-bar-and-it-fills-on-speech-2026-09-07)
      - [It was a fade first, and the fade was the wrong instrument](#it-was-a-fade-first-and-the-fade-was-the-wrong-instrument)
      - [It counts voiced seconds, not elapsed ones](#it-counts-voiced-seconds-not-elapsed-ones)
      - [A tag pops out when it fills (2026-09-08; it said `HQ` from 2026-09-09)](#a-tag-pops-out-when-it-fills-2026-09-08-it-said-hq-from-2026-09-09)
      - [And then the minutes, in brackets (2026-09-09)](#and-then-the-minutes-in-brackets-2026-09-09)
      - [The meter](#the-meter)
      - [Two implementation traps, both paid for](#two-implementation-traps-both-paid-for)
      - [The wait fills too (2026-09-08)](#the-wait-fills-too-2026-09-08)
  - [One face, one size, one weight — everywhere on the chip](#one-face-one-size-one-weight--everywhere-on-the-chip)
  - [The wait is icon-sized, and it was the colour that mattered](#the-wait-is-icon-sized-and-it-was-the-colour-that-mattered)
  - [The mouse is drawn, and the buttons the gesture presses are red](#the-mouse-is-drawn-and-the-buttons-the-gesture-presses-are-red)
  - [The shutter and the ⌘⇧ pick are two gestures, and they cannot collide](#the-shutter-and-the--pick-are-two-gestures-and-they-cannot-collide)
  - [Two gestures are borrowed, and only while dictating](#two-gestures-are-borrowed-and-only-while-dictating)
  - [The music pauses for the length of a dictation](#the-music-pauses-for-the-length-of-a-dictation)
  - [Mouse 4 is the shutter, but only while dictating](#mouse-4-is-the-shutter-but-only-while-dictating)
  - [The wheel, dragged: a region instead of the display (2026-09-10)](#the-wheel-dragged-a-region-instead-of-the-display-2026-09-10)
    - [The shared module, and why it is a path dependency](#the-shared-module-and-why-it-is-a-path-dependency)
    - [The release matches the press, and in Logi mode both go through](#the-release-matches-the-press-and-in-logi-mode-both-go-through)
    - [A tap with an opinion about the button makes the overlay's poll useless](#a-tap-with-an-opinion-about-the-button-makes-the-overlays-poll-useless)
    - [The box follows the events, not a timer (2026-09-10)](#the-box-follows-the-events-not-a-timer-2026-09-10)
    - [The two keys are always on the readout, and light up when they act](#the-two-keys-are-always-on-the-readout-and-light-up-when-they-act)
    - [No border, and no vignette either](#no-border-and-no-vignette-either)
    - [`area-00:38(1200x800px).jpg`, and one sentence in the clause](#area-00381200x800pxjpg-and-one-sentence-in-the-clause)
    - [It cost a real bug in the paste path, found by this gesture refusing to fire](#it-cost-a-real-bug-in-the-paste-path-found-by-this-gesture-refusing-to-fire)
    - [Verified end to end](#verified-end-to-end)
  - [The shot's name is *when in the sentence* and *where the mouse was*](#the-shots-name-is-when-in-the-sentence-and-where-the-mouse-was)
  - [The agent gets an 800px copy, Victor keeps the retina frame](#the-agent-gets-an-800px-copy-victor-keeps-the-retina-frame)
    - [Three things that sound like improvements and are not](#three-things-that-sound-like-improvements-and-are-not)
  - [Every frame says which window it came from](#every-frame-says-which-window-it-came-from)
  - [The shutter also takes the selection](#the-shutter-also-takes-the-selection)
  - [A highlight is picked up on its own (2026-09-09)](#a-highlight-is-picked-up-on-its-own-2026-09-09)
  - [Shots live in Caches, one folder per relay session](#shots-live-in-caches-one-folder-per-relay-session)
    - [The cursor mark is on the screen, never in the picture](#the-cursor-mark-is-on-the-screen-never-in-the-picture)
  - [The DJI receiver is the microphone whenever it is plugged in](#the-dji-receiver-is-the-microphone-whenever-it-is-plugged-in)
  - [The voice corpus: audio kept beside the transcript, forever](#the-voice-corpus-audio-kept-beside-the-transcript-forever)
  - [The recogniser](#the-recogniser)
    - [The language is pinned to {ro, en}, and the prompt carries his vocabulary (2026-09-07)](#the-language-is-pinned-to-ro-en-and-the-prompt-carries-his-vocabulary-2026-09-07)
      - [B — the language pin removes an entire failure mode, for free](#b--the-language-pin-removes-an-entire-failure-mode-for-free)
      - [C — the vocabulary prompt is the bigger win, and it is not free](#c--the-vocabulary-prompt-is-the-bigger-win-and-it-is-not-free)
      - [The loop gate is the price of C, and it was already in the file](#the-loop-gate-is-the-price-of-c-and-it-was-already-in-the-file)
      - [Where the worst of it actually lives](#where-the-worst-of-it-actually-lives)
    - [What the local model is actually worth, measured](#what-the-local-model-is-actually-worth-measured)
    - [The menu says what the model costs](#the-menu-says-what-the-model-costs)
    - [The side buttons speak in function keys (2026-09-09)](#the-side-buttons-speak-in-function-keys-2026-09-09)
      - [The forward click starts Wispr Flow too, because Wispr cannot take the button (2026-09-09)](#the-forward-click-starts-wispr-flow-too-because-wispr-cannot-take-the-button-2026-09-09)
      - [The bind is a chord again: hold the left button, click the forward one (2026-09-09)](#the-bind-is-a-chord-again-hold-the-left-button-click-the-forward-one-2026-09-09)
    - [Use Logi Gestures — the tick that chooses between the two sets](#use-logi-gestures--the-tick-that-chooses-between-the-two-sets)
    - [The wheel is the relay's; mouse 5 is nobody's (except in Replace Wispr)](#the-wheel-is-the-relays-mouse-5-is-nobodys-except-in-replace-wispr)
    - [Double-clicking the wheel turns the dictation into a spawn (2026-09-05)](#double-clicking-the-wheel-turns-the-dictation-into-a-spawn-2026-09-05)
    - [The right chord means one thing again (2026-09-06)](#the-right-chord-means-one-thing-again-2026-09-06)
    - [The right chord has no hold to wait out (2026-09-04)](#the-right-chord-has-no-hold-to-wait-out-2026-09-04)
    - [A cancelled sentence is kept for five minutes (2026-09-10)](#a-cancelled-sentence-is-kept-for-five-minutes-2026-09-10)
    - [⌘ + the wheel: the destination that does not exist yet](#the-wheel-the-destination-that-does-not-exist-yet)
    - [The folder menu (2026-09-04)](#the-folder-menu-2026-09-04)
    - [The little terminal grows out of the dialog (2026-09-09)](#the-little-terminal-grows-out-of-the-dialog-2026-09-09)
    - [Two halves, and a line between them (2026-09-08)](#two-halves-and-a-line-between-them-2026-09-08)
      - [Where the bottom half comes from](#where-the-bottom-half-comes-from)
      - [The star](#the-star)
      - [`WT_SHOOT_MENU` — because this panel cannot be photographed either](#wtshootmenu--because-this-panel-cannot-be-photographed-either)
  - [Replace Wispr: the relay as a way to type](#replace-wispr-the-relay-as-a-way-to-type)
  - [The engine is a choice with two names on it (2026-09-14)](#the-engine-is-a-choice-with-two-names-on-it-2026-09-14)
  - [The front is a third thing Wispr takes, and the only one that can be given back (2026-09-14, 06:00)](#the-front-is-a-third-thing-wispr-takes-and-the-only-one-that-can-be-given-back-2026-09-14-0600)
    - [What a caret dictation carries (2026-09-08)](#what-a-caret-dictation-carries-2026-09-08)
    - [The ring round the pointer, when the destination is not a place (2026-09-09)](#the-ring-round-the-pointer-when-the-destination-is-not-a-place-2026-09-09)
      - [Spokes: the halo stylised with lines (2026-09-10, in progress)](#spokes-the-halo-stylised-with-lines-2026-09-10-in-progress)
      - [What ships: `codex3`, and the envelope became a plateau (2026-09-10)](#what-ships-codex3-and-the-envelope-became-a-plateau-2026-09-10)
      - [What ships now: his picture, and it runs as a film (2026-09-10)](#what-ships-now-his-picture-and-it-runs-as-a-film-2026-09-10)
      - [It turns while it is up, and it collapses into the pointer when it goes (2026-09-10)](#it-turns-while-it-is-up-and-it-collapses-into-the-pointer-when-it-goes-2026-09-10)
      - [It is the beacon now, and it breathes on his voice (2026-09-11)](#it-is-the-beacon-now-and-it-breathes-on-his-voice-2026-09-11)
      - [`DropArrow`: three dashes and a head, pointing down at the cursor (2026-09-11)](#droparrow-three-dashes-and-a-head-pointing-down-at-the-cursor-2026-09-11)
      - [`WT_SHOOT_HALO` also writes an arrow sheet](#wtshoothalo-also-writes-an-arrow-sheet)
      - [Measured, 2026-09-11](#measured-2026-09-11)
      - [`WT_HALO_DEMO` — the answer to *does it actually move*](#wthalodemo--the-answer-to-does-it-actually-move)
      - [`WT_SHOOT_HALO` — because a falloff cannot be judged from code](#wtshoothalo--because-a-falloff-cannot-be-judged-from-code)
  - [A bind mid-sentence changes the recipient](#a-bind-mid-sentence-changes-the-recipient)
    - […and so does the sentence that starts right after one (2026-09-09)](#and-so-does-the-sentence-that-starts-right-after-one-2026-09-09)
  - [⌘⌃P pastes the last dictation](#p-pastes-the-last-dictation)
  - [The chip teaches nothing; the menu does](#the-chip-teaches-nothing-the-menu-does)
  - [Size: minimal, per state](#size-minimal-per-state)
    - [The order of the rows, and Chrome is last (2026-09-09)](#the-order-of-the-rows-and-chrome-is-last-2026-09-09)
    - [The tally: what this dictation is carrying, read down the icon column (2026-09-09)](#the-tally-what-this-dictation-is-carrying-read-down-the-icon-column-2026-09-09)
  - [Two shapes: the chip and the panel](#two-shapes-the-chip-and-the-panel)
  - [The pointer is clean when nothing is bound](#the-pointer-is-clean-when-nothing-is-bound)
  - [The menu bar item](#the-menu-bar-item)
    - [Every row has an icon, and two alphabets share the column](#every-row-has-an-icon-and-two-alphabets-share-the-column)
    - [Autosend](#autosend)
    - [Prompt Log: the outbox read back as a page](#prompt-log-the-outbox-read-back-as-a-page)
    - [The 🤖 on the other screens](#the--on-the-other-screens)
  - [The bound tty is published, so the status line can wear a microphone](#the-bound-tty-is-published-so-the-status-line-can-wear-a-microphone)
  - [The beacon is gone — the halo took its job (2026-09-11)](#the-beacon-is-gone--the-halo-took-its-job-2026-09-11)
  - [The prompt is held, not sent](#the-prompt-is-held-not-sent)
    - [The send flight (2026-09-04)](#the-send-flight-2026-09-04)
    - [⏎ sends it, and clicking the words edits them](#sends-it-and-clicking-the-words-edits-them)
  - [Dark mode](#dark-mode)
  - [Opacity states](#opacity-states)
  - [Nothing beside the pointer draws a window](#nothing-beside-the-pointer-draws-a-window)
  - [The oblique wipe: a message replaces a message](#the-oblique-wipe-a-message-replaces-a-message)
    - [What the cancel actually looked like, and the two things wrong with it (2026-09-09)](#what-the-cancel-actually-looked-like-and-the-two-things-wrong-with-it-2026-09-09)
    - [`WT_SHOOT_WIPE` — because this is the least reviewable thing in the app](#wtshootwipe--because-this-is-the-least-reviewable-thing-in-the-app)
  - [Placement](#placement)
  - [Capture order: flash first](#capture-order-flash-first)
  - [Picking elements in Chrome](#picking-elements-in-chrome)
    - [It lives only while the recording row does](#it-lives-only-while-the-recording-row-does)
    - [The hint is the row, and the row is beside the cursor](#the-hint-is-the-row-and-the-row-is-beside-the-cursor)
    - [The cursor is a hand, not a crosshair](#the-cursor-is-a-hand-not-a-crosshair)
    - [⌘⇧ has to be *held*](#has-to-be-held)
    - ["Sometimes it does not catch the element" (2026-09-09)](#sometimes-it-does-not-catch-the-element-2026-09-09)
    - [⌘⇧-drag: where he would move it, without moving it (2026-09-09)](#-drag-where-he-would-move-it-without-moving-it-2026-09-09)
    - [The pick queue still survives a dictation opening](#the-pick-queue-still-survives-a-dictation-opening)
    - [What a pick carries: the page, and what the thing said](#what-a-pick-carries-the-page-and-what-the-thing-said)
    - [The clause: when, what, and on which page (2026-09-09)](#the-clause-when-what-and-on-which-page-2026-09-09)
    - [Why the row names the newest pick](#why-the-row-names-the-newest-pick)
  - [The selection is frozen for the whole dictation](#the-selection-is-frozen-for-the-whole-dictation)
    - […but it must not outlive it (2026-09-04)](#but-it-must-not-outlive-it-2026-09-04)
    - [Where a spawned window opens (2026-09-04)](#where-a-spawned-window-opens-2026-09-04)
    - [The spawn's flight leaves the dialog, and the dialog waits for it](#the-spawns-flight-leaves-the-dialog-and-the-dialog-waits-for-it)
  - [A stale bundle in /Applications is three bugs at once](#a-stale-bundle-in-applications-is-three-bugs-at-once)
  - [Never launch the installed app by its executable path](#never-launch-the-installed-app-by-its-executable-path)
  - [The app icon and the build stamp](#the-app-icon-and-the-build-stamp)
  - [The Dock tile is the escape hatch](#the-dock-tile-is-the-escape-hatch)
  - [The mic's own lock is not recursive, and `start` already holds it](#the-mics-own-lock-is-not-recursive-and-start-already-holds-it)
  - [The ring covers Wispr Flow's dictations too (2026-09-11)](#the-ring-covers-wispr-flows-dictations-too-2026-09-11)
  - [Six heads closing in, instead of one arrow hanging above (2026-09-12)](#six-heads-closing-in-instead-of-one-arrow-hanging-above-2026-09-12)
- [The forward click is the caret, and the arrow is the terminal (2026-09-12)](#the-forward-click-is-the-caret-and-the-arrow-is-the-terminal-2026-09-12)
  - [The ring goes down when he dismisses in Wispr (2026-09-12)](#the-ring-goes-down-when-he-dismisses-in-wispr-2026-09-12)
  - [The session row says the terminal's title (2026-09-12)](#the-session-row-says-the-terminals-title-2026-09-12)
  - [The envelope names no recogniser (2026-09-12)](#the-envelope-names-no-recogniser-2026-09-12)
  - [The ring grows out of the pointer (2026-09-12)](#the-ring-grows-out-of-the-pointer-2026-09-12)
  - [Only the installed bundle is a login item (2026-09-12)](#only-the-installed-bundle-is-a-login-item-2026-09-12)
- [Wispr's own row says when it is done (2026-09-12)](#wisprs-own-row-says-when-it-is-done-2026-09-12)
- [The shots clause becomes a list, and the folder becomes $WALKIE_SHOTS (2026-09-13)](#the-shots-clause-becomes-a-list-and-the-folder-becomes-walkie_shots-2026-09-13)
- [The loopback closes: gestures, state, a sink and a delivery field (2026-09-13)](#the-loopback-closes-gestures-state-a-sink-and-a-delivery-field-2026-09-13)
- [Every selection and every pick says when, and a pick says what it said (2026-09-13)](#every-selection-and-every-pick-says-when-and-a-pick-says-what-it-said-2026-09-13)
- [Version row and ⌘Q (2026-09-13)](#version-row-and-q-2026-09-13)
- [Three witnesses instead of one, and the ring stops waiting for CoreAudio (2026-09-13, evening)](#three-witnesses-instead-of-one-and-the-ring-stops-waiting-for-coreaudio-2026-09-13-evening)
- [The numbers, and the Scratchpad is the one that works (2026-09-13, night)](#the-numbers-and-the-scratchpad-is-the-one-that-works-2026-09-13-night)
- [The wrap is Wispr's own Scratchpad (2026-09-13, late)](#the-wrap-is-wisprs-own-scratchpad-2026-09-13-late)
- [Five runs to make the Scratchpad wrap real (2026-09-13, 23:20–23:31)](#five-runs-to-make-the-scratchpad-wrap-real-2026-09-13-23202331)
- [The row is the delivery; the note is the second opinion (2026-09-13, midnight)](#the-row-is-the-delivery-the-note-is-the-second-opinion-2026-09-13-midnight)
- [Parking the Scratchpad, and measuring whether it ever takes a key (2026-09-13, midnight)](#parking-the-scratchpad-and-measuring-whether-it-ever-takes-a-key-2026-09-13-midnight)
- [The Scratchpad takes the keyboard without taking the front (2026-09-13, after midnight)](#the-scratchpad-takes-the-keyboard-without-taking-the-front-2026-09-13-after-midnight)
- [The wrap, measured on the installed build (2026-09-14, 00:18)](#the-wrap-measured-on-the-installed-build-2026-09-14-0018)
- [The paste is addressed, so the delivery stops waiting (2026-09-14)](#the-paste-is-addressed-so-the-delivery-stops-waiting-2026-09-14)
- [Three ways to take the keyboard back, and what each one measured (2026-09-14, 01:00–01:15)](#three-ways-to-take-the-keyboard-back-and-what-each-one-measured-2026-09-14-010001-15)
- [The night the wrap found its shape (2026-09-13/14)](#the-night-the-wrap-found-its-shape-2026-09-1314)
- [The fifth stale ⌘, and the guard that finally works (2026-09-14, 02:48)](#the-fifth-stale--and-the-guard-that-finally-works-2026-09-14-0248)
- [What the cancel cost the sentence after it (2026-09-14, 03:30)](#what-the-cancel-cost-the-sentence-after-it-2026-09-14-0330)
- [The adversary's second round: four things that outlived their dictation (2026-09-14, 04:30)](#the-adversarys-second-round-four-things-that-outlived-their-dictation-2026-09-14-0430)
- [The heads stay up while the words travel to the caret (2026-09-15)](#the-heads-stay-up-while-the-words-travel-to-the-caret-2026-09-15)
- [The estimate stops guessing the middle (2026-09-16)](#the-estimate-stops-guessing-the-middle-2026-09-16)
- [The back button becomes the stop of the dictation it started (2026-09-17)](#the-back-button-becomes-the-stop-of-the-dictation-it-started-2026-09-17)
- [One slow flick right is one gesture, and it cannot close what it just opened (2026-09-18)](#one-slow-flick-right-is-one-gesture-and-it-cannot-close-what-it-just-opened-2026-09-18)
- [The chip swaps in one frame (2026-09-18)](#the-chip-swaps-in-one-frame-2026-09-18)
- [The chip says which microphone, and the menu picks it (2026-09-19)](#the-chip-says-which-microphone-and-the-menu-picks-it-2026-09-19)
- [The pictures are clean, and it is a measurement now (2026-09-19)](#the-pictures-are-clean-and-it-is-a-measurement-now-2026-09-19)
- [A box round it, with nothing selected (2026-09-19)](#a-box-round-it-with-nothing-selected-2026-09-19)
- [The region he framed travels at its own size (2026-09-19)](#the-region-he-framed-travels-at-its-own-size-2026-09-19)
- [The envelope becomes tokens where he made them (2026-09-19)](#the-envelope-becomes-tokens-where-he-made-them-2026-09-19)
- [ElevenLabs is the engine, and the freeze that found (2026-09-19)](#elevenlabs-is-the-engine-and-the-freeze-that-found-2026-09-19)
- [Two engines out, and a folder per dictation (2026-09-20)](#two-engines-out-and-a-folder-per-dictation-2026-09-20)
- [Ten minutes is the end of a sentence, and the row says so from the eighth (2026-09-20)](#ten-minutes-is-the-end-of-a-sentence-and-the-row-says-so-from-the-eighth-2026-09-20)
- [The ring says where the sentence is going (2026-09-21)](#the-ring-says-where-the-sentence-is-going-2026-09-21)
- [Wispr Flow leaves the Engine list (2026-09-22)](#wispr-flow-leaves-the-engine-list-2026-09-22)
- [The About page becomes a window (2026-09-22)](#the-about-page-becomes-a-window-2026-09-22)
- [Forward is a prompt, back is plain words (2026-09-23)](#forward-is-a-prompt-back-is-plain-words-2026-09-23)
- [Active Terminals: the spawn menu's first row (2026-09-23)](#active-terminals-the-spawn-menus-first-row-2026-09-23)

---

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
- `hqBadge` + `elapsedText` — `HQ` on the listening row once the bar fills, and
  `(2m)` after it. Both are language-neutral by luck rather than by design, and
  both must stay so
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
40 of them — each with the moment it appears and why it looks the way it does. It
is generated: the catalogue, the order, the sections and every word of prose live
in `Sources/WalkieTalkie/OverlayStates.swift`, the pictures are the real views
drawing themselves through `RelayWindow.snapshot`, and `docs/build-overlay-states.py`
only lays them out.

**The rule: no change to the overlay is finished until that page is rebuilt.**

```sh
./docs/shoot-overlay-states.sh      # shoots all 40 states, regenerates the HTML
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
- **Both editors' targets are guarded**, since 2026-09-10. `/bind` returns the
  shell's pid, the relay resolves a tty from it and runs the same
  `foregroundIsShell` test it runs on a Terminal.app tab — verified refusing
  `rm -rf build` on VS Code with zsh at the prompt, and on IntelliJ refusing
  `echo THIS MUST NEVER RUN` the same way.

  **IntelliJ was the exception for three weeks, and the reason was one unwrapped
  proxy.** Its connector is a `com.jetbrains.rdserver.terminal.BackendTtyConnector`
  even for a local tab with `terminalEngine=CLASSIC`, and this file recorded that
  as *the reworked terminal does not hand back a process*. It does:
  `BackendTerminalRunner.createTtyConnector` builds the ordinary
  `PtyProcessTtyConnector` and wraps it, and the wrapper is a `ProxyTtyConnector`
  whose entire content is a `getConnector()` returning the original — read out of
  the IDE's own bytecode rather than guessed at. `shellPid` searched the
  *wrapper's* hierarchy for `getProcess`, found nothing, and answered nil. It
  unwraps first now (`RelayTerminalService.unwrapProxy`, by method name, since
  the plugin compiles against neither the terminal plugin's interface nor the
  remote-dev module), and IntelliJ answers a real pid: `shellPID: 9323`, matching
  the zsh on that tab's tty.

  **What Victor actually saw was the warning**, reported as *"nu mai merge să fac
  bind de la terminalul de IntelliJ, îmi zice No Shell Guard"* — and the bind was
  working the whole time. Since 2026-08-28 the positive bind flash is gone
  (*the chip says the folder at that exact instant*), so on the one target that
  could not be guarded the **only** thing the gesture drew was a `⚠️`. A
  successful bind and a failed one looked the same, and the successful one looked
  worse. Now there is no flash on IntelliJ either, which is what every other
  target's success has looked like all along.
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

**The guard reads the whole foreground job, not its first process** (2026-09-08).
A prompt is a foreground group that is *only* a shell: a waiting zsh is alone in
it, and a zsh that started something is not in it at all (`Ss`, no `+`). Reading
only the first `+` line made Copilot CLI in a VS Code terminal permanently
undeliverable — VS Code's Copilot Chat launches it through
`…/globalStorage/github.copilot-chat/copilotCli/copilot`, a `#!/bin/sh` script
that does **not** `exec`, so the job is `sh` → `Code Helper (Plugin)` →
`copilot` → its MCP servers and the guard read `sh`. Measured on ttys014: every
dictation refused as "would run as shell" while an agent sat there waiting for
one; typed by hand into that same pane, `text` + `Return` submitted normally.
The rule that replaced it — *any non-shell in the group means a program is
running* — still refuses the case the old one was right about, a nested
interactive `bash`, which is one shell alone in the group. The name reported
skips app-bundle helpers, so that job says `copilot` rather than
`Code Helper (Plugin)`.

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

**And a third, learned the hard way on 2026-09-10: the far end has to *parse*
the JSON.** Every delivery into an IntelliJ terminal between that 09-07 change
and 09-10 arrived as one run-on line with a literal `\n\n` in the middle of it —
the words, two visible backslash-n, then all five clauses. The relay was right:
`IDEBridge.send` serialises with `JSONSerialization`, so a real newline goes out
correctly escaped. The IntelliJ plugin's `/send` picked the string back out with
a regex and unescaped exactly two sequences, `\"` and `\\`, so `\n` came
through as two characters. VS Code's extension calls `JSON.parse` and never had
it, which is why this was an IntelliJ-only fault and why it hid behind the shell
guard's `⚠️` in the same report. Measured by reading the bytes the pty actually
received, before and after. `RelayTerminalService.unescapeJson` handles the whole
escape set now, in one left-to-right pass — the old pair was also wrong in its
order, turning `\\"` into a bare quote.

The shots travel as **paths, not a `📸 ×2` count**:
the panel's preview is written for Victor, who needs only to know they landed,
while this is written for an agent, which can do nothing with a number and
everything with something to `Read`. `[selected: …]`, `[look at: …]`,
`[context: …]`, `[elements I picked in Chrome: …]` are the same split the outbox
makes in keys,
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

### Rebind to: the destinations already spoken to, most recent first (2026-09-10)

Victor's problem, said plainly: *"am o problemă constantă — nu mai știu în ce
terminal am făcut ce task"*. Fifteen to twenty Claude Code sessions in
Terminal.app by the afternoon, and the window that was fixing the Bluetooth
keep-alive is somewhere behind PowerPoint.

**The first design was a model, and it was the wrong one.** A Spotlight-style box
that took a typed description and had Haiku pick the session. Two measurements
killed it before a line was written: `claude -p` on this Mac costs **13 s for
sonnet and 17 s for haiku** (`TranscriptDistiller`, and the cost is the CLI's
startup, not the model), and both Anthropic keys in the secrets file are out of
credit. Victor's replacement is better than what it replaced: *"strict ceva
recent, fără niciun LLM, fără nicio căutare prin transcripturi"*.

**Because the answer never needed a model.** The destination he is looking for is
one he has already spoken to, there are a dozen at most, and each one already
carries a title its own agent keeps rewriting to say what it is doing — Claude
Code writes `✳ victor-macos-addons — Copilot logo alternating display` into the
tab, and that *is* the summary. Nothing had to be generated; it only had to stop
being thrown away.

- **`RebindHistory`** is a log of bindings, not a scan of the machine. A session
  never bound does not appear, which is also what keeps the list readable.
  Keyed by `address` (`ttys016`, `%3`, `IntelliJ IDEA`), capped at twelve, and
  persisted to `~/.walkie-talkie/rebind-history.json` — *"persistența, vreau"* —
  because this app is relaunched several times an hour while it is worked on, and
  a list that emptied each time would be empty exactly when it is needed.
- **The elapsed time is stamped in three places, and that is the whole
  correctness of it.** A binding ends in three ways: `unbind()`, a delivery that
  comes back `targetGone` (which calls `unbind()` itself), and — the common one —
  **a bind that displaces it**, which passes through neither. `TerminalBinding`
  now has one private `adopt`, and every bind goes through it. Stamping only in
  `unbind()` would have had every row Victor moved away from claim it was let go
  of hours later, when the app finally quit.
- **✨ means this app opened the window.** Passed at the single call site that
  spawns one (`adoptSpawnedWindow` → `bind(tty:spawned: true)`) rather than
  inferred, and **sticky**: re-binding a spawned window later does not make it
  stop having been spawned. The star is `✨` and not `★` because `★` is already
  spoken for in `SpawnFolderMenu`, where it moves a row between pinned and
  recent — two stars with different meanings in two menus of one app.
- **One AppleScript for every title, at the instant the submenu opens.**
  `TerminalBinding.liveTitles()` answers `ttysNNN → title` for the whole machine
  in ~30 ms, which is about what a *single* `title(forTTY:)` costs, and a dozen of
  those on a menu open would be felt. It doubles as the liveness check: a tty the
  history remembers and the map does not is a closed window, and its row is
  greyed rather than deleted behind him.
- **A popped-up list, not a submenu — and the arrow is why.** Victor's condition
  on the feature was that the menu bar stay instant (*"să nu dureze timp la
  click-ul pe iconița"*), which a submenu honours perfectly. It was still wrong:
  **AppKit reserves the disclosure-arrow gutter on every row of a menu as soon as
  one item has a submenu**, and the right-hand side of this menu is the gesture
  column `layOutGestures` lines up. One arrow moved all of it — *"a fugit toată
  coloana de meniuri din cauza >"*. So the row is `Rebind to…`, it builds an
  `NSMenu` on click and `popUp`s it at the pointer, and nothing about the
  laziness changes. **The pop-up is dispatched**, not run inline: the click is
  still closing the menu it came from, and a menu put up inside that closing
  lands underneath it and takes no clicks.
- **Plain titles, deliberately.** An attributed title stops AppKit dimming a
  disabled row (see the note above `layOutGestures`), and the rows that cannot be
  clicked — the one already bound, a closed window, an IDE panel with no
  Terminal.app tab to find — are exactly the ones that have to read as disabled.

#### `bind(tty:)` normalises the tty, and that fixed a silent bug

Callers hand it both spellings: `SpawnTerminal` returns `/dev/ttys014`, while
`POST /bind` carries the short `ttys014` that `relay-restart.sh` reads out of
`bound-tty`. **Every AppleScript in `TerminalBinding` compares against
Terminal.app's own answer, which is the path** — the title, the window frame and
the delivery all test `tty of t is …`.

So the short form built a `Target` that *looked* bound and could never find its
tab again: no title, no window frame, and the restart script told `→ re-bound to
ttys014` on a binding whose first delivery would come back `targetGone`. It had
been that way since the restart route was written (2026-09-09). One
`devicePath()` at the single door a caller-supplied tty comes through; proven by
the first rebind after the fix logging `window at 765,561 945×516` where it had
previously logged `frame unknown`.

### The list takes typing, and searches the session journals (2026-09-12)

Victor, at the panel that replaced the pop-up: *"când apare ecranul de sesiuni
recente … trebuie să pot să încep să tastez direct. Tastarea aceea trebuie să fie
un search peste mesajele scrise de mine sau de agent … nu thinking, nu tool
calls, ci doar mesajele vizibile în terminal … fără să mai ții lucruri în
memorie, ci direct pe jurnalele de sesiuni, pentru a putea găsi sesiunea care
îmi trebuie … live filtering la taste, cu [debounce] … 370 … sau 500"*.

**This is the transcript search the 2026-09-10 entry above ruled out, and the
reason it is back is that the thing ruled out was a model.** *"strict ceva
recent, fără niciun LLM, fără nicio căutare prin transcripturi"* was written
against a design that spent 13–17 s in `claude -p` to have Haiku pick a session.
Nothing here asks anything: it is `rg` and a line-by-line read of the same files.
Two stages, measured on this Mac over a 21-day window (1013 files, 1.3 GB):

| stage | cost |
|---|---|
| `rg -l -i -F <term>` over the window | **0.24 s** |
| parse of the files that matched, until 25 sessions are found | 0.2 s–2.9 s |

The second number is the whole range: a rare word finishes in a fifth of a
second because ripgrep hands back five files, and `hotspot telefon` takes 2.9 s
because *telefon* is in three hundred of them. That is why the rows **stream** —
`session_search.py` prints one JSON object per session as it finds it and the
panel appends them — rather than appearing all at once at the end.

- **Only what was on screen counts.** A hit is a human prompt or a text block the
  assistant printed; `thinking`, `tool_use`, `tool_result`, sidechains, hook
  output and the expansions of slash commands are all skipped. Not a nicety —
  raw, `bluetooth` matches **516 of 1013** transcripts, and about six of them are
  about Bluetooth.
- **Nothing is indexed and nothing is held.** The helper keeps one snippet and a
  counter per session whatever the file's size (the biggest here is 13 MB), and
  the app never sees a transcript at all, only the rows. An index would be a
  second thing to keep true; the file on disk is already true.
- **The fast half never waits for the slow half.** The destinations from
  `RebindHistory` filter by substring on the keystroke itself. The scan waits
  **370 ms** — his number, and the low end of the two he said, because what the
  pause is for is not calming the list but keeping four keystrokes from starting
  four scans. Every keystroke past it cancels the process the last one started.
- **An `NSMenu` cannot be typed into**, so the list is an `NSPanel` now
  (`RebindPanel`) — `.nonactivatingPanel` plus `canBecomeKey`, the trick
  `RelayPanel` already uses while the transcript is being edited, so it takes the
  keyboard without activating the app and the terminal behind it gets it back on
  close. Everything the pop-up did is kept: built at the instant it is asked for,
  the destination app's own icon per row, a row that cannot be clicked dimmed
  rather than hidden, and the whole thing dispatched out of the click that is
  still closing the menu it came from.

#### Which tab a session from Tuesday is in — the join nobody had to write

A search result is only useful if it can be bound to, and a transcript says
nothing about a terminal. It turns out the link is already on disk, twice, and
both halves come from Victor's own `terminal-title.sh` hook:

1. `/tmp/claude-terminal-title-<session>.tty` — the hook caches the tty it walked
   the process tree to find, so it need not do it twice. The file's mtime is when
   that session first fired a hook, i.e. when it started.
2. The tab's **title**, which the same hook writes as `✳ <folder> — <title>`,
   taken from the `ai-title` / `custom-title` records — the same two records the
   search reads for a row's name.

**The mtime is what makes the first one usable.** `ttys016` has belonged to a
dozen sessions this fortnight and every one of them left a claim file; the newest
claimant is the tenant and the rest are former ones. So: the tab must be open
(`TerminalBinding.liveTitles()` is the only thing that can say so) **and** the
session must be the newest claimant of it — with the title as corroboration when
it agrees, never as the only witness. Measured the day this was built: `ttys016`
was running *Lightning circle around mouse* while its tab still read
`✳ victor-vibe-board — Tablet star icon`, three sessions out of date, because the
hook refreshes a title on that session's own turns. Title-matching alone marked
every live session *window closed*.

#### A closed window is not a dead end: ⏎ reopens the session

Victor, on being told that row could only say *window closed*: *"cu un visual
hint, să ofere și asta, da"*. So it does — the row knows the session id and the
folder it belongs to, and that is exactly what `claude --resume <id>` needs.

- **The spawn is the one ⇧ + wheel makes, minus the prompt.** `SpawnTerminal`
  grew a second entry point (`resumeClaude`) and everything after the launcher is
  now shared with `launchClaude`: the same `do script`, the same tiling onto a
  lateral display, the same restoring of the front, the same
  `adoptSpawnedWindow` — flight, then bind. A resumed session is a destination
  that did not exist a second ago, which is the sentence a spawn already says.
- **The `cd` is load-bearing.** A session id is scoped to the project folder
  Claude Code filed it under; resumed from anywhere else it is simply not found.
  So a row only offers to reopen when that folder still exists, and otherwise
  stays what it was: dimmed, `window closed`.
- **The hint is on the selected row and nowhere else.** `⏎ resume it` in the
  accent colour, right-aligned, with the title given the width that is left; the
  footer says `⏎ reopen it with claude --resume` for the same row. Twenty-five
  rows each repeating it is noise, and an action nothing on screen mentions is an
  action nobody uses. The title says `closed` rather than `window closed` once
  reopening is on offer — the window is gone, the session is not.
- **A flash covers the wait.** `do script` plus a Claude Code starting up is a
  couple of seconds in which the panel has closed and the window is being tiled
  onto a screen he is not looking at; `✨ reopening <folder>…` is the only thing
  saying the ⏎ landed.

Verified end to end on 2026-09-12 through `POST /test/resume-session` (the ⏎ of
that row, since a window that has taken the keyboard cannot be clicked from a
script): `✨ resumed session 91f62dd6 in …/walkie-talkie on ttys009`, `ps -t
ttys009` showing `claude --resume 91f62dd6…`, the tab titling itself
`✳ Walkie-talkie dictation UI animations`, and the relay bound to it three
seconds later.

**And it took the folder fallback out of the liveness test.** Matching a tab on
the repo name alone called every session of a repo live as long as *any* tab was
open in it: it pointed a bind at a stranger's window, and — worse — it swallowed
the row, because a hit that claims a tty already listed above is dropped as a
duplicate. The session Victor searched for vanished from the list instead of
offering to reopen itself (seen with two sessions of this repo, one of them in a
tab that had moved on hours before). The title is now the only corroboration, and
with reopening on offer there is nothing left to buy with a guess.

#### The panel's own corrections, in the order they were found

- **`.menu` material, not `.hudWindow`.** A HUD is a dark slab in both
  appearances while `labelColor` follows the *system* one — in light mode the
  rows came out dark grey on dark grey.
- **A grey plate and an accent bar for the selected row, not a blue fill.** The
  second line of a row is a sentence in `secondaryLabelColor`; over accent blue it
  reads as a watermark. The plate is `labelColor` at 10 %, so the text on it keeps
  the contrast it has everywhere else.
- **`quaternaryLabelColor` is a separator's colour.** A dimmed row set in it is
  not dimmed, it is gone; the dim rung is one step, `secondary`/`tertiary`.
- **A destination keeps its tty even when it cannot be clicked.** The bound row is
  disabled, and with its tty dropped the session search found the same session
  again and listed it twice.
- **`POST /test/rebind-panel` `{"query": …}`** puts the panel up in the middle of
  the screen with the field filled in, because nothing else at a desk can click a
  menu row and then type into a window that takes the keyboard away.

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
| `POST /bind` `{"tty": "ttys004"}` | bind **that** session instead of the front one — no toggle, no flight, no flash. The restore half of a restart; see *Restarting keeps the binding* |
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

### Restarting keeps the binding, and never interrupts a sentence (2026-09-09)

`./relay-restart.sh` — and `docs/shoot-overlay-states.sh`, which stands the
installed app down to draw the catalogue, goes through the same two functions.
Victor's rule, in two halves said ten minutes apart: *"niciodată să nu mai dai
restart la Walkie Talkie … în dictare — oprești și aștepți să se termine
dictarea, să se livreze, abia apoi faci restart"*, then *"legat dar nu în
dictare poți să-l restartezi totuși, ideal ar fi să-l re-legi la același
terminal automat"*.

**A dictation in flight is a stop; a binding is a thing to put back.** The
restart is ordered from inside a session this app types into, so it is the one
destructive act here that is invisible to whoever ordered it: audio already
spoken is gone, and the binding is dropped under him with nothing on screen
saying why. It cost one on 2026-09-09, when the shoot script restarted the app
while he was bound.

- **The binding comes from `~/.walkie-talkie/bound-tty`**, the marker the status
  line already reads: absent unbound, `ttysNNN` bound. One `cat` rather than an
  HTTP round trip, and it is written from the one switch that owns it, so it
  cannot disagree with the chip. It is read **before** anything stands the app
  down — launch clears it. Whether a sentence is in flight is a different
  question and is asked of `GET /test/state`.
- **Six seconds after the relay goes idle.** The microphone closing is not the
  end of the sentence: the decode and the held panel come after it, and those
  are what deliver the words.
- **The restore addresses a tty, not the front window**, which is why the route
  had to exist: at the end of a build the frontmost window is whatever the build
  was watched in — precisely not the session that was bound. It is never a
  toggle, and it plays no flight and no flash: an app that has just replaced
  itself is not announcing a gesture Victor made.
- **The retry waits ten seconds for an answer, not one** (2026-09-09). A bind is
  one to two `osascript` round trips and the route answers only when it has
  finished, so `curl -m 1` timed out on a bind that had **succeeded** — and the
  loop, reading that as a failure, bound again, and again: seven re-binds over 70
  seconds after a single restart, measured. Each one is a deliberate bind, so one
  stole a binding Victor had made by hand in the meantime and another redirected
  a caret dictation he had just started. The retry is for a port that is not open
  yet, which fails in milliseconds; it must never fire against a bind still
  running.
- **A `.keystroke` target has no tty and cannot be restored**, the same hole the
  status line's microphone badge has. The script says so and the app is running
  either way.

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

## Unbound is inert — retired (2026-09-11)

**The rule is gone. With nothing bound the app now does everything it does
bound, and the sentence waits for the terminal Victor is about to point at.**
His ask: *"tot ce pot să fac când sunt legat de un terminal să pot să fac și
atunci când sunt nelegat, urmând a mă lega ulterior"*.

`AppDelegate.holdsForBind` is the switch, one `static let`, and it is the one
word to flip if the hold turns out to be worse than the refusal was.

### What the rule was, and why the premise expired

From 2026-08-27, `isBound` gated every path that could deliver. It was written
because the relay had just become a **login item**: it sat there all day, so
every sentence he spoke into a browser, a chat or a commit message was costing
him a screenshot, mouse 4 and ⌘⇧-click — **with nowhere for the words to go**.

The premise is that last clause, not the binding. A destination that arrives two
minutes late is still a destination, which is exactly the reading that already
exempted the two gestures carved out of the rule while it stood: `spawnPending`
(a session that does not exist yet) and `pasteMode` (the caret). `holdsForBind`
is the third exemption and it swallows the rule, because it answers the question
for the remaining case: **later**.

The gesture it exists for is the one Victor described — a thought arriving before
there is a window for it. Under the old rule the answer was to refuse the
gesture, so the thought had to survive the walk to a terminal in his head.

| gate | unbound, before | unbound, now |
|---|---|---|
| `captureContext` — flash, selection probe, screen capture | off | **on** |
| `plusOneShot` — mouse 4 | off | **on** |
| `areaShot` — the wheel drag | off | **on** |
| `syncBorrowedGestures` — mouse 4, ⌘⇧-click, the selection watcher | off | **on** |
| `syncLocalCapture` — the wheel's claim on the microphone | off | **on** |
| `StatusItem`'s **Start Dictation** row | greyed | **live** |
| `send` — the delivery | dropped | **held, then delivered** |
| the outbox line | not written | **written at delivery, not before** |
| `corpus.captureLocal` | on | on |

### The outbox half of the 2026-08-27 decision stands

That decision is recorded here as Victor being asked directly and choosing the
whole switch over half of it: *"an outbox filled all day for a watcher that is
usually not there is not a feature, it is a log of his private dictation."*
**Nothing about that changes.** A held sentence lives in memory and nowhere
else — `commit` returns into `holdForBind` *before* `Outbox.send`, and the JSONL
line is written at the moment of delivery. A relay left unbound all day still
leaves no log behind it.

### `awaitingBind`: one sentence, five minutes

- **One, not a queue.** A second dictation replaces the first, the way a second
  cancel replaces the recording being kept for recovery — the chip says *the*
  sentence being held, and a relay that had to ask which of three to deliver is
  answering a question nobody has. The one it replaces is not lost: ⌘⌃P still
  pastes it, because `lastDictation` is set above the hold.
- **Five minutes**, the same net `Recover Cancelled Dictation` is kept under.
  Long enough to cross the room and open a terminal, short enough that a
  sentence from this morning cannot land in an agent he binds this afternoon for
  something else. On expiry the chip says so — `⏳ held dictation expired — ⌘⌃P
  to paste it` — because the alternative is a sentence he believes is still on
  its way.
- **Released from `showBound`**, which is the one method every route into a
  binding passes through: ⌘⌃B, the chords, `POST /bind`, the restart's restore,
  a spawned window adopting itself. **Deliberate or not**, unlike the spawn and
  caret take-backs two sections down — those guard against the 10s poll stealing
  a destination, and a poll cannot produce a binding out of nothing, so it can
  never be the call that releases this.
- **The chip says it while he talks**: `⏳ bind to send — ⌘⌃B`, in the row every
  other destination takes, and it names the *gesture* because that is what this
  destination still is. It comes down the moment a bind lands.

### The one gate whose price is outside this app

`syncLocalCapture` is the one *Unbound is inert* deliberately refused to widen
even for the spawn and the caret, and widening it is the one part of this change
that costs something. With **Use Logi Gestures unticked**, the wheel is now the
relay's for as long as the relay is running — so middle-click stops opening
links in Chrome and closing tabs in VS Code, which is exactly the cost Victor
named when he moved the gestures onto the side buttons (*"folosesc middle click
sa inchid de ex taburi chrome/vsc"*). **In the default mode it costs nothing**:
`HotkeyTap` hands every mouse button straight back there and dictation is a
chord on the side buttons. The line to put back to `isBound` is one, and it is
named in `syncLocalCapture`'s own comment.

Its knock-on: the unbound double-click branch at the bottom of `HotkeyTap`'s
middle-button chain is now unreachable — the first click opens a dictation and
sets `wheelDictateAt`, so the second converts it to a spawn in the branch above,
which is the same gesture arriving at the same place. It is left standing
because it is what has to work again if `holdsForBind` is flipped back.

### Pause still does not come back

*Pause is gone* (below) rests on this rule, and the reasoning survives its
retirement — which is worth being explicit about, because it looks like it
should not. Pause existed to hand the mouse back and stop the app acting on a
sentence that was not for it. What answers that now is not *Unbound is inert*
but **Disconnect**, which already exists, is reachable from the chord and the
menu, and says which terminal it let go of. **Do not reintroduce pause**, and do
not make `holdsForBind` a menu tick — a tick for it would be pause under another
name.


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
| the dictation was cancelled | `🗑️ Cancelled` in the row `Listening…` was in — 1.5 s, swept in and swept out again by the oblique line (*The oblique wipe*). The 🗑️ came back on 2026-09-02: it was dropped while a flash still drew the lone 🎙️ title row above it, where Apple's lid-flying-off bin read as a second glyph on a two-glyph line; that row no longer appears under a flash, so the bin is the row's only picture |
| dictating in Replace Wispr | the drawn map pin + `at caret` — the same slot a spawn takes, and for the same reason |

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

The waits go with it — `⏳ Transcribing...` is the same slot at the next moment
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

#### A tag pops out when it fills (2026-09-08; it said `HQ` from 2026-09-09)

**The moment the last dot lights, a small blue `HQ` arrives at the end of the
row** — from almost nothing, overshooting well past its size and settling, with a
quarter turn on the way (`placeListenExtras`). Victor's ask: *"când se umple
complet listening-ul, să apară o steluță la final, cu un mic efect de explozie
mică … care compensează că am vorbit suficient de mult"*, and the day after:
*"la steluța care apare după listening, desenez un tag micuț care scrie HQ, de la
High Quality … un tag micuț, pe albastru"*.

**A star is a reward; a tag is a claim about the thing it is stuck on.** It was
⭐ for a day, and the star said *well done* and left him to remember what for.
What filling actually means is measured and specific — past three voiced seconds
the wrong-language mode is at its floor and the median WER of a short clip has
halved — so two letters say it where a picture could not. The animation, the
edge-triggering and the measured width are all unchanged; only the mark is
different.

- **Blue, and drawn** (`Glyphs.tag`). Every other mark on this row is a signal
  colour spent on an *event* — the 🔴 for *now*, `systemRed` for *this was
  captured*. A label is not an event, so it takes the one colour on the chip that
  has never meant one. Drawn rather than typed for this file's standing reason: a
  raw glyph in an attributed string on a label carrying a halo renders and turns
  every other character transparent (`applyTitleText`), and a word set in the
  row's own font would read as another word in the sentence rather than as a
  label stuck on it. A filled capsule says *tag* with no text at all.
- **`0.8 ×` the icon column, not the full 16pt.** The badge fills its box corner
  to corner where the emoji beside it sit a bearing in from the edge, so at equal
  height it was the largest thing on the row — the same correction Chrome's icon
  was given one row down.

**The bar already said this and said it too quietly.** It is done when there are
no dim characters left — which is a fact he has to *look at the row* to read, and
the whole reason the bar exists is that he is looking somewhere else while he
talks. A thing that **moves** is caught in peripheral vision; a thing that merely
stopped changing is not. The bar is the gauge, the star is the notification. It
also gives the row a state the last two steps could not tell apart: at eleven of
twelve characters, the difference between *nearly* and *enough* is one full stop.

- **It has never been ✨, in either form.** The sparkles are the spawn's mark, and
  on a spawn dictation both are on this very row — one in front of the word
  meaning *this session does not exist yet*, one behind it meaning *you have said
  enough*. Two identical glyphs saying two unrelated things is the row failing to
  say either. Checked in `docs/states/spawn.png`, where the two sit five
  characters apart.
- **An `NSImageView`, not a glyph in the attributed string.** It has to *move*,
  and a text attachment inside an `NSTextField` has no layer to animate —
  re-rasterising it at a new size every frame would put a relayout inside the one
  loop that must not have one.
- **A pop, which is what a small explosion is at 16pt**: 0.15 → 1.45 → 0.85 →
  1.08 → 1.0 over 0.42s. `CursorMarker`'s bloom is the app's other burst and is
  the wrong one here — that mark's whole job is to get *out of the way*, so it
  spreads and dies, while this one stays on the row for the rest of the sentence.
  The quarter turn is `CursorMarker`'s trick for `CursorMarker`'s reason: growing
  straight out is the motion easiest to miss on a screen that is already
  repainting. It runs *to* zero, so the star rests square.
- **The star is a function of the bar being full, and the pop is only the edge.**
  A state photographed at full warmth wears it with no transition having
  happened, which is what lets `OverlayStates` show it at all; and
  `applyEngineText` runs on every relayout and on `refreshChrome`, so a pop
  replayed each time would be a star flashing at the corner of his eye for the
  rest of the sentence — the opposite of a reward. `RELAY_SHOOT` skips it for the
  oblique wipe's reason: the catalogue photographs states, and this is a
  transition.
- **It is measured into the row's width** (`listenExtrasWidth`), not left to hang
  off the end, which the panel would clip. That makes the frame it arrives in the
  **one tick in a sentence allowed a relayout** — the rule the ramp is written
  under is about ink, which changes no geometry; the tag changes the width, once
  per dictation, at the exact moment the chip is meant to be noticed.

#### And then the minutes, in brackets (2026-09-09)

`🔴 Listening... [HQ] (2m)` — the whole minutes this dictation has been running,
after everything else on the row and only once the first one has gone by.
Victor's ask: *"să pui după toată povestea o paranteză rotundă în care treci
numărul de minute"*.

**It is the one fact the rest of the row cannot carry.** `Listening...` fills in
the first three voiced seconds and then never changes again, so from that moment
on nothing on the chip distinguishes a sentence from a monologue — and a
monologue costs real seconds at the other end: the decode is charged per second
of audio, and the panel he has to read while the Cancel clock runs is as long as
he made it.

- **Wall clock, not voiced seconds**, and that is the opposite choice from the
  bar directly to its left. The bar is a forecast about the *transcript*, so it
  counts only speech and stops when he stops; this answers *how long have I been
  at this*, where the thinking pauses are part of the answer.
- **Nothing under a minute.** `(0m)` is a readout saying only that a clock
  exists, an inch from what he is reading, for the length of every ordinary
  dictation — which is exactly the rent the model id was taken off this row for
  paying.
- **A label of its own, not a run in `engineInfo`.** The tag sits between the
  word and this, and the tag is an image view because it has to pop; a run
  appended to the attributed string would land *before* it.
- **A second clock, and it relayouts at most once a minute** (`startElapsed`).
  The ramp's timer cannot carry this — it stops the moment the bar fills, which
  is three voiced seconds in and therefore before the first minute of every
  dictation there has ever been. So this ticks once a second, watches the whole
  minute count, and does nothing at all on 59 ticks in 60; the one that acts
  changes the row's width, which is the case that has to go the long way round.
  Same bargain the tag's arrival strikes.
- **`pinListenElapsed` freezes it for `OverlayStates`**, which sets a state up
  and photographs it in the same millisecond and so has no minutes to let pass —
  the same reason `pinListenWarmth` and `pinTranscribeWarmth` exist.

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

`Transcribing...` is drawn the same way, on Victor's ask — *"la fel vrea să
colorezi transcribing, să-l colorezi de la întunecat la mai aprins, ca pe post de
progress bar"*. Same instrument, pointed at the one wait that has a **deadline**:
`DecodeRate` has already promised a number of seconds, so unlike the dictation
there is a real fraction to draw. The bar is that promise said in the way the eye
reads without stopping.

**And the seconds are gone, hours later the same day.** The row was
`Transcribing... 4s`, counting down beside the filling word, and Victor had the
number out as soon as he had lived with both: *"să scoți timpul efectiv în
secunde arătat de după, e doar stresant. Lasă să se sugereze progressbar-ul prin
culoarea textului"*.

- **A countdown is a deadline, and a deadline is a thing to watch.** The two say
  the same fact and ask different things of him: digits have to be *read*, they
  change under the eye every second, and a number falling toward zero invites
  checking whether it will get there — mid-dictation, an inch from what he is
  working on. The filling word is the same fraction taken in at a glance, with
  nothing to count: it is done when there are no dim characters left. That is
  `listeningWord`'s own argument — *brightness is judged against what is beside
  it*, so a count of characters beats a number — arriving one row later.
- **The estimate did not go, only its readout.** `transcribeDeadline`,
  `transcribeSpan` and `DecodeRate`'s fitted line are untouched and are what the
  bar is drawn from. Everything written below about how that number is arrived at
  is still live; it is now spoken in ink.
- **An estimate that runs out no longer needs saying out loud.** The number
  stopped being shown at zero rather than sitting at `0s` or counting up, which
  was the app declining to insist on a promise it had broken. The bar does that
  by construction: it arrives full and stays there.
- **`Transcribing...`, three full stops**, for `Listening...`'s reason: an
  ellipsis is one glyph and would light in one step.
- **Fifteen ticks a second, and nothing relayouts at all.** It used to, once a
  second, because the digits changed the row's width; with them gone the row is a
  fixed string whose ink changes, so the attributed value goes straight onto the
  label — `startWarmth`'s bargain, and this loop must never re-measure every row
  on the chip sixty times a decode. Taking the number off *removed* a relayout
  rather than costing one.
- **`pinTranscribeWarmth` had to exist the moment the digits went.** While the
  row carried a number, a photograph of this state said what it was about
  whatever instant it was taken at. Now the fill is the only thing that varies —
  and `setTranscribing(true)` with no audio behind it has no deadline, which
  `transcribeWarmth` answers with a **full** bar, so the catalogue's one picture
  of the wait would have been the one frame in which nothing is waiting. The
  `transcribing` shot pins 0.45, exactly as `listening-cold` and
  `listening-warming` pin theirs.
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

**A third rides the same switch since 2026-09-10, and takes far less**: a wheel
*drag* selects a region of the screen (*The wheel, dragged*). It is keyed on the
same `dictating` this method pushes to the tap, so it cannot outlive a sentence
either — but where these two take a whole button for the length of one, that one
takes nothing until the hand has moved six points, and a middle **click** is
handed back untouched.

Since 2026-08-28 the same switch also **pauses Chrome's music** (`MusicBridge`,
below). It is not a gesture, but it is the same window and the same argument: for
the length of a sentence, something that belongs to the rest of the machine is
borrowed and then handed straight back. Since 2026-09-02 it also raises the
**caret halo** — same switch, same window, and the reason it is that switch and
not a fourth place `listening` is written down. (It raised the *corner beacon*
until 2026-09-11, when the halo took that job and the beacon was deleted.)

**Both are borrowed in Replace Wispr too, since 2026-09-08** (`live`, full stop).
They were not, on the argument that both gestures exist to *add to a message* and
that mode has no message — one string, going where the caret is. Victor overruled
the premise rather than the conclusion: *"chiar dacă pornesc dictare la caret …
să poți să agăți și poze și elemente, exact ca la o dictare țintită către un
terminal"*. A paste **is** a message; it is simply one whose recipient is
whatever holds the caret, which is routinely another agent — a web chat, an
editor's assistant — where a frame and a selector are worth exactly what they are
worth in a terminal. See *Replace Wispr* for what the paste then carries.

**The cost is the back button, and it is the cost this app always pays.** In that
mode it gave Return (*"pe butonul de Back să dea Enter"*) because nothing was
borrowing it. It is the shutter now, for the length of a sentence — the same
narrow window every other dictation borrows it in, keyed on `listening` and not
on the mode, so outside it Victor Addons goes on typing Return with it.

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

## The wheel, dragged: a region instead of the display (2026-09-10)

**While a dictation is running — bound, unbound, or headed for the caret — the
wheel held down and dragged selects a rectangle of the screen, and that
rectangle is what joins the pictures.** The dimming, the box, ⌘ to move it whole,
⌥ to draw it from its middle, Esc to call it off: all of it is **Victor Addons'
crop**, because it is now literally the same code in both apps
(`victor-mac-kit`).

Victor's ask: *"if I click and drag the mouse wheel, it should behave exactly as
taking a screenshot of an area of the screen using the macOS add-on, with the
same behaviour of moving the window. Try to reuse, make a common module reused by
both projects … I don't need the yellow border around the picture, and as a
matter of fact I don't want the border at all either in the macOS add-ons — the
point is to get that picture attached to the pictures, but I should say this is
not the full screen, this is a selected area."*

**Why it earns a gesture of its own.** The shutter photographs a *display*
because a press is a moment and not a shape, and most of what comes back is the
desk around the answer: 800px of handover spent on a desktop, and an agent that
has to find the thing before it can read it. A drag is a shape. It is the same
hand on the same mouse, mid-sentence, saying *this bit here* while drawing a box
round it.

### The shared module, and why it is a path dependency

`~/workspace/victor-mac-kit` — `CropGeometry` (the arithmetic, unit-tested),
`CropSelectionOverlay` (the panels and the 60 Hz poll) and `CropCapture` (the
rectangle → a JPEG, by capturing the whole display and cropping at its real pixel
scale, because `screencapture -R` answers *"could not create image from display
with rect"* on macOS 15.7 for every rectangle it is given).

Both apps declare `.package(path: "../victor-mac-kit")`, so a fresh clone of
either needs the sibling beside it. That is the trade for being able to edit the
shared gesture and rebuild the app in one step — no push, no version bump, no
resolve — and both apps are only ever built on this Mac, from local.

**The two apps disagree about exactly two things**, and both are parameters:

- **The words**, `CropSelectionStyle`. Victor Addons speaks Romanian on screen;
  this overlay is English, per *UI language: English only* — it goes on a
  projector in front of an international room.
- **Which button is being dragged with**, `begin(button:from:)`. Addons holds
  ⌃P, lets go, and then draws a box with the left button. Here the drag is
  **already under way** — the wheel is down and the hand is moving — so the
  corner it started from is handed in and the box is live on the first frame.

One thing was fixed on the way out rather than copied faithfully: `CropPanel` now
refuses `constrainFrameRect`, so the selection can reach the top 25 points of a
screen instead of being quietly pushed below the menu bar — the trap `BindFlight`
and `CaretHalo` are already written under.

**And one thing was broken on the way out and put back.** The panels were given
`sharingType = .none` for an afternoon, as belt and braces over the beat that
already separates them coming down from the shutter. Everything else this app
draws near the pointer is invisible to capture for a good reason; this is the one
surface that must not be, because it is the one a person **aims** with. With the
flag on, the selection could not be reviewed by a screenshot, by a remote pair of
hands, or by anything but eyes on the glass at the instant it happens — which is
exactly how a box that had stopped following the mouse went unnoticed. The beat
is what keeps the dimming out of the picture, and always was.

### The release matches the press, and in Logi mode both go through

A middle press cannot be told from a middle click at the press — the difference
is whether the hand then moves — so `HotkeyTap.areaDrag` records the corner, hands
the event straight back, and takes nothing until the pointer has travelled
`areaDragThreshold`. **12 points**, on Victor's rule: *"ar trebui să ignori
click/dublu-click de wheel — doar drag ne interesează."* It was 6 for a day, which
is the right floor for *is this box worth capturing* (it is the same distance the
overlay refuses to call a selection) and too fine for *did he mean to drag at
all* — a click is never perfectly still. Nothing is lost by waiting, because the
corner was recorded at the press: the extra points buy only the moment the
dimming appears. **Verified with a listen-only tap tail-appended behind this
one**: a plain middle click during a dictation reaches the app underneath as a
`DOWN` and an `UP`, with nothing logged here — which is the whole promise of
*Use Logi Gestures*, since middle-click-to-close-a-tab is what that mode exists to
protect.

**The release goes out too, and it took a wedged pointer to learn why.** Victor
chose *pass the press, swallow the release* over the two alternatives on the
table — eating every middle click for the length of every dictation, or reviving
the replay deleted on 2026-09-06 — and swallowing the release turns out not to be
available at all. **A press that went out puts the button *down* in session
state, and a release this tap eats never takes it back up.** Measured the hard
way: a crop at 00:23 left `CGEventSource.buttonState` answering *middle: down*
**seven hours later**, and what Victor had for those hours was a VS Code editor
tab stuck to his cursor, because as far as the window server was concerned a drag
had been in progress since the night before.

So the rule is **ours only if the press was ours** (`areaPressPassed`). In Logi
mode the press goes out and so does the release, and the app underneath gets a
middle-down and a middle-up with the movement between them removed — a click it
ignores, because the two ends are in different places. With *Use Logi Gestures*
off the wheel's own branch swallows the press, so this swallows the release, and
the pair stays matched. Neither mode can leave the OS holding a button.

**With *Use Logi Gestures* off the press was swallowed and already means
something** — a dictation to end, and a 2 s timer that would cancel it — so the
drag *claims* it (`claimWheelPress`, the same claim the release and the hold race
for) and cancels the timer. The release then finds `tapped` false and fires
nothing. That branch also clears `wheelArmed` / `wheelDown` itself, because the
release never reaches the branch that normally clears them: left standing, they
would swallow the release of the **next** middle press — one this file passed
through — which is the orphan bug written a third time.

### A tap with an opinion about the button makes the overlay's poll useless

The overlay ends the selection when the driving button comes up, and it reads the
button the only way a panel with no key window can — `CGEventSource.buttonState`.
That is right for Victor Addons' left-button drag, which nothing intercepts, and
it is wrong here **in both directions at once**, one per gesture mode:

- **A swallowed release never reaches that state**, so the selection never ends.
  First run of the gesture: the finger came up, the box stopped following, and
  the dimming stayed on the screen with `buttonState` still answering *down*, its
  only way out being Esc — and a `swift` one-liner run to diagnose it hung for
  two minutes behind the drag the window server thought was in progress.
- **A swallowed press never puts it *down***, so with *Use Logi Gestures* off the
  very first tick would find the button up and end a selection that had not
  started. That one hid behind the other for a day: the wheel-mode crop was
  measured working, and it was working because the state was **already** stuck
  true from a Logi-mode drag four minutes earlier.

So the overlay stops looking. A drag handed in through `begin(from:)` is
`driven` — the button is the caller's to report, `onAreaEnd` →
`CropSelectionOverlay.endDrag()` is the report, and Esc or the right button stay
as the ways out that do not depend on the caller still being alive. A release
that lands **before** the panels are on screen is kept for `begin` for half a
second — long enough for the hop, short enough that a stale one cannot end the
next selection before it starts — because the two arrive by different routes and
a flick beats the overlay onto the screen.

**The threshold is measured off the event, not off `NSEvent.mouseLocation`.** An
event carries the position it was *made* at; the pointer answers where it is by
the time the tap asks. They differ by one event, which is nothing to a hand and
everything to a burst of posted events — the arm was silently skipped for a drag
delivered faster than the pointer could be read, which is exactly the shape every
test of this gesture has.

### The box follows the events, not a timer (2026-09-10)

Reported on the first real drag: *"nu văd live chenarul selectat în timp ce țin
jos wheel-ul — văd doar un chenar mic inițial și apoi, când dau release, cel
final."*

**It was not reproducible with posted events**, and that is the tell rather than
a dead end. A `driven` drag has every one of its motion events swallowed by this
tap before any window sees them, so the overlay was polling
`NSEvent.mouseLocation` from a 60 Hz `Timer` on the main run loop for a position
**the tap already had in its hand**. A timer is a request for a turn; a box that
stops following the hand while the button is held and catches up the instant it
is released is precisely what not getting one looks like. Measured here at 72
frames a second and a worst gap of 20 ms, which is exactly why the synthetic
version never showed it: the machine under a posted drag is not the machine
under a real one.

So the position is **pushed** — `CropSelectionOverlay.dragMoved(toCG:)` on every
swallowed drag event, drawing on arrival — and the timer keeps only what it alone
can see: Esc, the right button, and ⌘/⌥. The pointer read that remains is the
fallback for a poll tick with nothing pushed yet.

**And every selection now writes one line saying whether the box was drawn**:
`✂️ selection over 5.0s — 362 frames (59 pushed, 303 polled), worst gap 20ms`.
It took a bug report to ask that question the first time; the answer is now in
the log before anyone thinks to ask it again. `CropSelectionOverlay.log` is the
module's one diagnostic hook, pointed at each app's own logger.

### The two keys are always on the readout, and light up when they act

`386 × 232   ⌘ move   ⌥ centre`, with the word going from dim white to the accent
while its key is held. Victor, 2026-09-10: *"legenda «centre» și «move» să fie
mereu prezentă când fac crop, dar să devină colorate cuvintele când chiar se
întâmplă."*

They were appended to the size **only while the modifier was down**, which made
them a readout of something he already knew he was doing — on the one row he
looks at while framing. As a permanent pair they are the legend for the two keys
this gesture has, in the place he is already looking, and the colour becomes the
readout instead. They name the **key** rather than the effect for the same
reason: `⌘ move` on screen for the whole drag is how ⌘ gets learned, where the
`✥ move` they used to say is a symbol for something he can already see happening.

The colours live in the attributed string and not on the label, which is the trap
`RelayWindow.applySelectionText` is written under here: a `foregroundColor` set
on the layer does not win against the runs.

### No border, and no vignette either

The red vignette and the cursor mark exist to say *a picture was taken, and here
is where you were pointing* about something that happened in a millisecond with
nothing on screen to show for it. This one he watched himself draw, at the pixels
he drew it around. A mark lit over them afterwards is the same news, later, on top
of the thing he framed — which is also the argument that took
`ScreenCaptureFlash.flash(around:)` out of **Victor Addons** in the same change,
on Victor's instruction. The full-screen flash stays there: one keypress, no
gesture, nothing else to say it happened.

### `area-00:38(1200x800px).jpg`, and one sentence in the clause

It rides in the same list as the shots, in the same order, because *sequence is
what these messages are made of* — but an agent handed a rectangle of pixels has
nothing in it saying whether those edges are a screen's. So the name says
`area-` and the clause says once, only when one is present:

```
Anything named `area-` is a region I dragged a box around, not the whole screen —
its edges are mine, not the display's.
```

- **The pointer is deliberately not in the name**, where a full-screen shot
  carries it (*The shot's name is when in the sentence and where the mouse was*).
  There it answers *which of these thousand things was he pointing at*; here he
  answered that by dragging a box round it, and the pointer is merely the corner
  he let go on. Its place is taken by the size, which is the one fact about a crop
  that is not obvious from looking at it — and it is measured off the JPEG, never
  multiplied out of the screen's backing scale, for `tagCursor`'s reason.
- **`ScreenCapture.isArea` reads the prefix** rather than a flag beside the path,
  because the name is also what says it to the agent, and a second copy of that
  fact is a second thing to keep in step with it.
- **The handover copy is unchanged**: 800px on the long edge, so a crop smaller
  than that travels at its own size. The note now says *at most* 800px wide, which
  it always should have.
- **The menu gains a legend row**, `Select Screen Area — 🛞 drag`, permanently
  disabled like `Take Screenshot` and `Pick Element in Chrome`: *The chip teaches
  nothing; the menu does*, and this is the one row that puts `🛞` back in the Logi
  column — which it can, because a drag is not a click.

**The chip is untouched**: a crop counts in `📸 ×N` like any other picture, so
`docs/overlay-states.html` needs no new `Shot` and was not rebuilt. The one new
string is a failure flash, `⚠️ area capture failed`, which is the state
`listening-flash` already photographs (`⚠️ screenshot failed`) with different
words in it.

### It cost a real bug in the paste path, found by this gesture refusing to fire

`TerminalBinding.tap(key:command:)` — what `pressPaste` and therefore every
Replace Wispr dictation, every ⌘⌃P and every blind-paste delivery go through —
**stamped ⌘ onto the V's key events and never released it**. `CGEventSource`
reports whatever the last event's flags said, so a ⌘V whose last event is a key-up
*with ⌘ on it* leaves the session believing ⌘ is held: measured at `0x00100000`
after a single paste, and it stayed.

It self-heals the moment Victor touches a real key, which is why it had never been
reported. Two things read that state and are wrong until he does.
`postWisprHandsFree` waits for the watched modifiers to clear before sending
Wispr's chord — i.e. it spins its full 200 ms allowance after every paste — and
**every gesture gated on `bare` refuses while it stands**, which is how this was
found: a wheel drag declining to select an area, silently, straight after a caret
dictation had pasted. The same stale ⌘ would refuse the mouse-4 shutter.

The fix is the shape `postWisprHandsFree` already documents — a modifier going
down or coming up is a `flagsChanged` carrying the state the keyboard is *left
in*, not the key's own bit — and it is verified: `0x20100000` before, `0x20000000`
after, and a crop taken straight after a paste now arms.

### Verified end to end

Driven with real events rather than a fabricated transcript, because the whole
gesture is the mouse:

- **A crop is a crop.** An 800×500-point drag came back as `1600x1000px`, and
  cross-checked against an independent whole-display `screencapture` cut at the
  pixels the region should map to: **correlation 0.997** — which is what settles
  the Cocoa→image y flip and the retina scale, the one thing a picture cannot be
  judged on by eye.
- **The envelope.** Two crops in one dictation came out in order, stamped by
  offset, named by what was in front of him, with the `area-` sentence appended
  once.
- **The plain click survives** — `DOWN`/`UP` seen downstream, nothing logged here.
- **Both gesture modes, each from a clean button state and each leaving one.**
  `left/right/center` all `false` before and after the crop, in Logi mode and
  with the flag off — the assertion the seven-hour stuck button exists to make.
  With *Use Logi Gestures* off the press and the release are both swallowed
  (nothing downstream) and neither the 2 s cancel nor the release's *end the
  dictation* fired.
- **A flick past the threshold and released in the same millisecond** ends as a
  cancelled selection rather than a stuck panel, and **Esc mid-drag** cancels with
  no file written and no panel left.

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

**The chip says `“ selecting <his own words>` for four seconds** and then
collapses to `“ ×N` — the words dropped, not shortened (2026-09-09, Victor:
*"citatul îl ții un pic acolo și apoi îl colapsezi doar într-un număr"*).

It carried the highlight for the rest of the sentence until then, and the two
readings have different expiry dates. At the instant it lands he is asking *did
this catch the thing I meant?*, and his own words back are the whole answer;
once he has read them the only open question is whether any of them fell out,
which a count answers on its own. The old arrangement spent the widest row on
the chip restating something already checked, for as long as two minutes, an
inch from what he is reading.

- **Four seconds, and the hold is now every highlight's, not the shutter's.**
  It was 2.5s and it only existed to time out the verb; the words underneath it
  never went. The opening probe's highlight is as new to him as one a press read
  — it is whatever he happened to have selected when he started talking — so
  there is no reading on which one of them earns the seconds and the other does
  not.
- **`×1` is written out**, unlike `📸 ×N` and `🎯 ×N`, which say nothing at one.
  On those rows the count is a prefix to something; here it is *all that is
  left*, so a row that went blank for the first highlight would read as one that
  lost it.
- **`pinSelectionSettled()` is what lets the catalogue photograph it** —
  `OverlayStates` sets a state up and shoots it in the same millisecond, so the
  four seconds never pass there. Same reason `pinListenWarmth` exists, and
  `listening-selection-multi` is now that state: `×3` and nothing else.

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
The message still carries each highlight exactly once. The row carries the
highlight for four seconds either way, which answers *is it still there* but not
the question he has at the instant he presses — *did this catch the thing I
meant?* A picture is taken
silently and a selection is read silently, so without the verb the only
confirmation the shutter grabbed the right paragraph arrived in the terminal, a
sentence too late to reselect.

**It is deliberately not a `flash(_:)`.** A flash *replaces* the chip for a
second and a half, and the receipt has to sit beside the text it is about — so
the row that carries the highlight anyway is where it goes, and the two now end
together, since the words go when the four seconds do. (When this was written a flash was also a *panel*, thrown across
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
The chip shows the newest for four seconds and then the count alone — see
*The shutter also takes the selection* for why the words go.

## A highlight is picked up on its own (2026-09-09)

**While a dictation is running, whatever is highlighted is read every 0.6s and
filed the first time it is seen. No shutter press, and therefore no screenshot.**
`AppDelegate.pollSelection`, `SelectionCapture.readQuiet`.

Victor's ask, and his reason: *"de multe ori selectez text și apoi apas butonul
de back ca să ți-l dau, doar că asta face și poza la ecran, ceea ce uneori nu-i
nevoie … ai putea să preiei automat textul selectat printr-un polling, să vezi
dacă s-a selectat text nou în timpul dictării … dacă e nou; dacă l-ai mai văzut,
îl ignori. Și în felul ăsta n-aș mai fi nevoit să fac poze ca să-ți dau textul
selectat."*

**The shutter is one gesture doing two jobs**, and handing over a highlight was
only ever reachable through both of them. A retina frame costs a megabyte or two
on disk — in a folder capped at 300 — and ~550 tokens in the agent's context, and
it has to be *looked at* before anything can be read off it. The selection costs
the characters it contains and is already the thing he meant. Selecting the text
is a gesture he was making anyway; this makes it the whole gesture.

- **Accessibility only.** `readQuiet` is back from the dead, and the argument
  that removed it on 2026-08-31 is the argument for it here. It went because the
  **shutter** used it: a deliberate press with a deliberate subject, where
  stopping at AX meant a highlight in a Chrome page recorded nothing, silently,
  and the ⌘C was a price Victor asked to pay. None of that transfers to a poll. A
  synthetic ⌘C posted into whatever app is under his hand *once a second, all
  sentence*, would fight his own copying, spend 400ms of pasteboard wait per
  tick, and race its own clipboard restore.
- **So a Chrome page is still the shutter's job**, and that is the one real gap.
  ⌘⇧-click is the better answer there anyway: it addresses a page element as an
  element rather than as loose text.
- **A selection has to settle before it is filed: three identical reads in a
  row.** Dragging grows it under the cursor — `Hel`, `Hello wor`, `Hello world`
  — and a poll that filed the first thing it saw would put a fragment in the
  message *and* the whole line beside it. Victor's rule and his words for what
  three unchanged reads mean: *"3 selecții identice = m-am oprit"*. At a **one
  second** tick (*"pune 1s în loc de 0,6, să nu fie grabă"* — it shipped at 0.6
  for an hour) that is two seconds of a hand that has stopped, which is a much
  stronger statement and costs nothing that matters: the sentence is still being
  spoken.
- **The stamp is when it was *first* seen, not when it was confirmed** —
  *"reține și timestampul selecției"*. The two seconds spent making sure are the
  watcher's business; the offset in the message says where in the sentence the
  highlight happened, and filing it two seconds late would put every automatic
  selection behind the words it belongs to. Measured: a ⌘A two seconds into a
  dictation comes out `0:02`, not `0:04`.
- **One last read when the microphone closes** — *"la finele dictării preiei
  selecția activă încă o dată, să nu fi selectat exact pe final"*. The settle
  rule has a cost, and it is exactly at the end: a highlight made in the last two
  seconds never gets its three reads, and that is precisely the moment he selects
  the thing he has just finished describing. No settling there, deliberately —
  the drag is over, or he would not have stopped talking — but `polledSeen` still
  applies, so the highlight that has been up all sentence is not filed twice.
  `finalSelectionRead` posts to the same serial queue the ticks run on, so it
  lands after any read in flight, and what it has to beat is a round trip through
  the helper: a second at the least, against an AX call measured in milliseconds.
  Blocking the main thread for the AX timeout at the instant the microphone
  closes would be the worse trade — that is the frame the recording row is being
  replaced in.
  **`/test/dictation` makes the same call**, with the send hung off it, because
  the route hands a transcript over on the spot where a real one follows a
  decode: without that the one part of the watcher that only runs at the close
  would be the one part nothing could reach from a desk.
- **Once each, per dictation.** `polledSeen` is *"dacă l-ai mai văzut, îl
  ignori"*: a highlight left on screen is read every tick and filed on none of
  them after the first. A **set**, not a last-value check, so going back to
  something selected earlier in the same sentence is not a second entry either.
  Losing the highlight clears what was settling, so re-selecting the same text
  has to settle again rather than being filed off a stale half-read.
- **Silent when it finds nothing new.** `fileSelection` is shared with the
  shutter and takes `announceOnRepeat`, which is the one thing the two callers
  disagree about: a **press** that found a highlight already carried still earns
  the `“ selecting …` receipt — he aimed at something, and a shutter that says
  nothing reads as one that missed — while a **poll** that finds the same text
  has found nothing, and a row flickering once a second about an unchanged
  highlight is the opposite of a receipt.
- **In Replace Wispr too, since 2026-09-09.** It was `live && !pasteMode`, on
  the argument that `caretLine` carried no `[selected: …]` so a watcher there
  would gather text nothing would ever send. Victor took the premise away rather
  than the conclusion — see *Replace Wispr* — and `syncBorrowedGestures` now
  passes a bare `live`.
- **The first one still fills the frozen slot.** A dictation that opened with
  nothing highlighted takes the first thing he selects as its subject — that is
  `fileSelection`'s existing rule and it is exactly the shape of this feature: he
  starts talking, then selects the thing he is talking about.
- **Half a second of AX messaging timeout**, set on both the system-wide element
  and the focused one. `AXUIElementCopyAttributeValue` blocks until the app
  answers and the default allowance is seconds; an app mid-beachball would stall
  this queue tick after tick. A serial `DispatchQueue` is the other half — a read
  that outran its interval delays the next one instead of overlapping with it.
- **Driven from `syncBorrowedGestures`**, the one switch every edge of a
  dictation passes through, so the watcher cannot outlive the sentence. Both
  edges are logged (`👁 selection watcher on/off`), because this is the first
  thing in the app that reads the screen on a timer and *"why did it not pick up
  my selection"* has to be answerable from the log.

**Verified end to end** (TextEdit, a bound scratch terminal at a shell prompt so
the delivery was refused and the outbox line still written): a dictation opened
with nothing selected; ⌘A was filed three reads later and **stamped `0:02`**,
where it was seen and not where it was confirmed; ⌘A again filed nothing; and a
range selected a fraction of a second before the close came out as
`👁 selection watched at the close`. The envelope carried both — `[selected: …]`
and `[selected 0:07: …]` — with **no shots clause at all**, which is the whole
point.

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
- **The wait says how long, not only that it is waiting** (since 2026-09-02) —
  **in ink since 2026-09-08**, when the digits came off and the filling word took
  the job over whole (*The wait fills too*). What follows is how the number
  behind the bar is arrived at; it was on screen as `Transcribing... 4s` for six
  days. The rounding up was deliberate and still is: over is a pleasant surprise,
  under is a promise that is wrong every second it is on screen.

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

### The side buttons speak in function keys (2026-09-09)

**In the default mode this app takes no mouse button at all.** The wheel is
handed back, both side buttons arrive as keystrokes — and the old wiring is one
menu tick away, not one `git revert` away: see *Use Logi Gestures* at the end of
this section. The two sections below describe what that tick turns back on, and
are therefore still live documentation rather than history.

**What was measured, because it settles an argument the notes had wrong.** The
forward button was said to reach the tap as an ~18ms down-and-up pair however
long it was held, with the Bolt receiver, Logi's agent or Wispr Flow blamed for
throwing the duration away. All three are wrong:

- **There is no Bolt receiver.** The M650 is on **Bluetooth LE**, direct.
- **It is not 18ms — it is nothing at all.** A probe reading the raw HID input
  reports *below every event tap*, next to a `.cghidEventTap` listener, saw the
  wheel perfectly (`WHEEL ▼ … ▲ ținut 5272 ms`) and saw the side buttons **not
  once**, held or clicked.
- **Killing Logi Options+ changes nothing.** With `com.logi.cp-dev-mgr` booted
  out of launchd and the agent confirmed dead, the side buttons were still
  silent. The divert lives in the mouse, not in the agent — and on Bluetooth LE
  a diverted press leaves over Logitech's own GATT service, which is not the HID
  path, so nothing on the Mac can see it.
- **Wispr Flow is not it either**, by the same test.

So there is no hold to detect, and no lower layer to reach for. What Options+
*sends* is a different matter, and that is the way in: with a diverted button it
synthesises an ordinary event, which the tap sees like any other — caught in the
act, `TAP tastă ▼ code=124 (pid 75980)`, pid 75980 being `logioptionsplus_agent`.

**The design that follows.** Each side button is set to Options+ **custom
gestures**, and every gesture is a **Keyboard shortcut** of our choosing. That
buys five sentences per button — a click, and held-while-moving in four
directions — as chords nothing on macOS ships: ⌃⌥⌘ + a function key.

| gesture | chord | what it does |
|---|---|---|
| 🔼 → | ⌃⌥⌘F10 | start the dictation, or end the one open (the same call ⌘⌃D makes) |
| 🔼 ← | ⌃⌥⌘F11 | cancel it — throw the audio away |
| 🔼 ↑ | ⌃⌥⌘F8 | dictate at a session that does not exist yet |
| ◀️ held, then 🔼 | ⌃⌥⌘F7 | **bind** the terminal in front — no toggle |
| 🔼 | ⌃⌥⌘F7 | dictate at the caret: this app's microphone with Replace Wispr ticked, **Wispr Flow's** without it |
| 🔽 ↓ | ⌃⌥⌘F12 | unbind — the menu's Disconnect |
| 🔽 | ⌃⌥⌘F6 | a picture while dictating, **Return** at every other moment |
| 🔽 → | ⌃⌥⌘F5 | Wispr Flow's hands-free toggle — **only while Replace Wispr is ticked**, a free row otherwise |
| 🔼 ↓ · 🔽 ↑ · 🔽 ← | ⌃⌥⌘F9 · F4 · F3 | assigned in Options+, unclaimed here — free rows |

#### The forward click starts Wispr Flow too, because Wispr cannot take the button (2026-09-09)

**The click means one sentence in both modes.** With Replace Wispr ticked it
opens this app's own microphone at the caret, as it always did; unticked, the
caret belongs to Wispr Flow and the same click types **Wispr's** hands-free
chord instead of being handed on. `postWisprHandsFree`.

**And 🔽 → is the same toggle from the other side.** With Replace Wispr ticked
the forward click is spoken for — it is this app's own microphone at the caret —
so the one mode that hides Wispr behind a menu tick gets a gesture of its own
back. Outside the mode it stays a free row rather than a second way in: the
forward click already *is* this verb there.

**The chord is `fn ⌃ Space`, and it was read out of Wispr's own config rather
than off its settings screen** — `prefs.user.shortcuts` in `~/Library/
Application Support/Wispr Flow/config.json`, where it is stored as
`"49+59+63": "popo"`. The same file names the others, which is worth knowing the
next time one of them is wanted: `"54+61": "ptt"` (push to talk, ⌘→ held with
⌥→), `"178+59+63": "lens"` (Command Mode), `"53+59": "dismiss"`.

**Why the app has to be in the middle at all.** Victor asked Wispr for the
button directly first, and it cannot have it:

- The button is diverted **inside the mouse** and never reaches the Mac as a
  button — the measurement above — so Wispr's recorder has nothing to record.
- The ⌃⌥⌘F-key Options+ synthesises instead is refused as well: *"Shortcut must
  include a modifier key or a valid mouse button"*, tried on **🔽 →** (⌃⌥⌘F5), a
  free row that this tap provably passes through, so the chord did reach Wispr
  and was turned down there. The likely reason is the one measured for
  `postReturn`: Options+ never *presses* ⌃⌥⌘, it stamps them into the F-key's
  flags, so anything reading live modifier state sees a bare function key.

So Wispr keeps a shortcut recorded by hand at the keyboard, and the button
reaches it through here.

**The modifiers are pressed as keys, not just stamped as flags.** Wispr stores
the chord as three keycodes — 49 Space, 59 Control, 63 fn — which reads like a
listener watching keys go down rather than one reading an event's flags. So the
fn and the Control go out as real `flagsChanged` events around the Space. Four
events instead of two, and correct under either reading.

**And it waits `settleForOptionsPlus` first**, exactly like `postReturn` and for
exactly that reason: it is posted from the tap callback for F7, while Options+
has ⌃⌥⌘ on the wire, and ⌃⌥⌘ fn Space is not what Wispr is listening for.

#### The bind is a chord again: hold the left button, click the forward one (2026-09-09)

It was **🔼 ↓** — the forward button held while the mouse moved down — for the
one day the function-key set had existed. Victor's ask, and his reason: *"let's
go for holding the left button of the mouse, the main button, and clicking on
the forward mouse button — it's more natural, click to focus the thing and then
grab it"*.

**The hand is already doing half of it.** Pointing the relay at a terminal
begins with clicking into that terminal, so the button that says *this window*
is down at the moment the gesture is made; a downward drag says nothing about
which window it means, and it is a direction that has to be remembered rather
than one the motion already contains. It is the **left-plus-wheel chord
returning**, with the forward button where the wheel was — which is why it is
judged the same way: `leftIsHeld`, i.e. the button genuinely down (the window
server is asked as well as our own bookkeeping) and down for `chordHoldSeconds`,
so a left click that merely overlaps the gesture is not one.

- **It shares F7 with the caret dictation**, and the left button is the whole
  difference. That is safe because a *click* leaves nothing held: `leftDownAt`
  is cleared at the release, so the ordinary sequence — click into a field to
  place the caret, then click the forward button to dictate into it — is
  untouched.
- **The bind is not gated on Replace Wispr**, though the caret dictation on the
  same key is. It is the gesture that says *where the words go*, so it has to
  work whichever way the next sentence is headed.
- **F9 is a free row now**, not a second way in. "Instead of", not "as well as":
  two gestures for one verb is the thing the Options+ screen has room for and the
  hand does not.
- **The left button is watched in Logi mode too, and never taken.** That mode
  hands every mouse event straight back one comparison later; the one fact it
  now records on the way past is when the left button went down. Nothing in
  `HotkeyTap` may ever swallow one — it is how the Mac is used.

**The posted Return has to wait for the chord to wear off, and it took three
tries to get right (2026-09-09).** `postReturn` runs inside the tap callback for
the chord's own F6 — the one instant Options+ has ⌃⌥⌘ on the wire — and the
Return reached the front app wearing them: `code=36 mods=CTRL+OPT+CMD` on a
listen-only tap. Terminal hands that to Claude Code as ⌥⏎, so the button stopped
sending the prompt and started inserting blank lines instead. Two fixes were
measured before the one that holds:

- **Clearing the event's own flags is not enough.** `down.flags = []` came out
  clean against a *synthesised* chord and dirty against the real button. While
  the modifiers are live the window server merges the current state back into a
  posted key whatever the event says — the trap
  `KeySimulator.waitForModifiersReleased` exists for in victor-macos-addons.
- **Asking the system to wait for them is not enough either**, and this is the
  part that is genuinely surprising: `CGEventSource.flagsState` answers *clean*
  through the whole window. **Options+ never presses ⌃⌥⌘ as keys** — it stamps
  them into the F6 event's flags and sends one flags-cleared event afterwards.
  A poll on modifier state therefore falls straight through, and the Return went
  out 2 ms after the F6, still inside the merge window.
- **What works is sleeping past that trailing event.** The gap from the F6 to
  the flags-cleared event measured 12, 15 and 22 ms across presses;
  `settleForOptionsPlus` is 45 ms, off the tap thread, with the modifier poll
  kept *after* it for modifiers Victor is really holding. Nothing is noticeable
  between the click and the prompt going.

The same merge is visible on the selection watcher's ⌘C when it happens to fire
inside that window (`code=8 mods=CTRL+OPT+CMD`, caught on the same tap), so any
key this app posts near a gesture has the trap waiting.

**The numbers are duplicated in two places and must not drift**: Options+'s own
custom-gesture screen, and `HotkeyTap`'s `VK_F3…VK_F12`. Change one and the
gesture goes to whatever app claims that chord instead — silently, since a chord
nothing handles is a chord nothing complains about.

**The glyph vocabulary in the menu.** An emoji names the button by where it sits
on the mouse — `◀️` `▶️` are the left and right buttons, and because the side
buttons are stacked, `🔼` is the forward one and `🔽` the back one. The movement
is a **thin text arrow** after it (`🔼 →`), Victor's call: filled triangles were
picked over `⬆️`/`⬇️` for exactly that contrast, since a boxed arrow beside a
bare `↑` is not a difference you see at a glance. And the Chrome pick row lost
its `+` (`⌘⇧◀️`): the modifiers and the click are one continuous gesture, not two
things added together.

**What this bought, beyond the button.** The wheel is the browser's again.
*The wheel is the relay's* below states the price of the old design plainly —
while something is bound, which is hours, middle-click stops opening links in
new tabs in Chrome and closing them in VS Code. That price is now zero, and it
was Victor's reason for the whole move: *"ideea e sa evit sa emit middle click,
caci folosesc middle click sa inchid de ex taburi chrome/vsc."*

**One thing came back to the wheel on 2026-09-10 and costs none of that**: a
*drag* of it, while a dictation is running, selects a region of the screen. The
press goes straight past this tap and so does the release of a press that never
moved, so the click that closes a tab is untouched — see *The wheel, dragged: a
region instead of the display*.

**Two things were lost and neither is worth mourning.** The wheel clicked while
the prompt panel is open used to mean Send — ⏎ still does, and the button beside
the transcript says so. And `deferContext` went: the bare wheel's context shot
waited for the *release*, so the picture was of the screen his finger left before
a second click could turn the dictation into a spawn. A gesture that ends with
the mouse already moved has no such moment, and the spawn is its own direction
now rather than a conversion.

### Use Logi Gestures — the tick that chooses between the two sets

**Both gesture sets are compiled in and one of them is switched off.** Victor's
call (*"tine-le pt moment comentate pe cele vechi, sau cu feat togle check box in
menu: Use Logi Gestures (retinut intre restart)"*), and the toggle beat the
comments because a gesture set that only exists in a diff cannot be switched back
to on a Mac that needs it.

- **Ticked, the default.** The side buttons arrive as ⌃⌥⌘F3…F12 and every mouse
  button is passed straight through — one comparison in `HotkeyTap.handle` and
  out again. The left button is *watched* on the way past (when it went down is
  the other half of the bind chord) and, like everywhere else in that file,
  never taken.
- **Unticked.** The pre-2026-09-09 wiring, whole: the wheel carries the
  dictation, holds cancel, the left and right buttons are chord modifiers, mouse
  4 is the shutter and mouse 5 drives Replace Wispr.

**Why it is worth keeping rather than deleting.** The Logi gestures live in an
Options+ profile on *this* Mac. A fresh install, or a machine in a training room,
has no side buttons at all until that profile is rebuilt — and the wheel path
needs nothing but the app.

Three details that are easy to get wrong:

- **The default is on, and it has to be written out.** `UserDefaults.bool(forKey:)`
  answers `false` for a key never written, which would have shipped the wheel
  gestures to the Mac already configured for the new ones. The row reads
  `object(forKey:) as? Bool ?? true`.
- **The tap subscribes to the mouse in both modes.** The event mask is fixed when
  the tap is created and the tick can be flipped at any moment, so the events
  have to be arriving already. Rebuilding the tap on a toggle would mean tearing
  down the thing carrying ⌘⌃B while a dictation may be running.
- **The menu legend column carries both legends and picks one.** `restyleGestures`
  runs on the toggle as well as on every open, and the tab stop is measured
  against the wider of the two sets so the column cannot resize under the pointer.

**The back button's Return is posted by this app now — in Logi mode.** It used to be typed
upstream — LinearMouse, then Victor Addons' `BackButtonEnter` — and this tap's
only job was to *withhold* it mid-dictation and take the picture instead. Options+
owns the button, so nothing upstream types anything: `HotkeyTap.postReturn` makes
it, stamped with `backButtonStamp` so the tap can tell it from a Return Victor
typed. **If that branch is ever removed, the key he submits with all day stops
existing.**

### The wheel is the relay's; mouse 5 is nobody's (except in Replace Wispr)

> **Off by default since 2026-09-09**, and still live code. Everything below is
> what the menu's *Use Logi Gestures* turns back on when it is unticked; with it
> ticked the wheel is untouched and the side buttons arrive as chords instead.
> See *The side buttons speak in function keys* above.


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

> **Off by default since 2026-09-09**, and still live code — this is what the
> wheel does with *Use Logi Gestures* unticked. Ticked, the spawn is 🔼 ↑, a
> gesture of its own rather than a conversion of a dictation in flight. The
> measurement in this section is what made the side buttons look unusable;
> *The side buttons speak in function keys* corrects it.


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

### A cancelled sentence is kept for five minutes (2026-09-10)

**The audio goes to `~/Library/Caches/…/cancelled/` instead of to `rm`, and the
menu grows `Recover Cancelled Dictation`.** Victor's ask: *"reține înregistrarea
audio respectivă pe disk după cancel 5 minute, în caz că vreau totuși s-o
recuperez + menu entry de rigoare."*

The 2s hold below is the confirmation dialog this gesture does not have, and it
protects against exactly one thing: the **slip**. It does nothing about the
change of mind, and a sentence spoken once is gone in a way a screenshot never
is — he cannot take it again, because the second take is never the same sentence.

- **Five minutes, on a timer in the running process.** Long enough to notice,
  short enough that this is a safety net and not a second outbox: the file is
  deleted by the clock whether or not he looks, and a launch empties the folder
  outright, because the timer and the menu row's enabled state both live in a
  process that is now gone — a WAV nothing can offer him is his own voice sitting
  in Caches with no way to ask for it back.
- **Caches, for the shots' reason**, and a *sibling* of `shots` rather than a
  child: `ScreenCapture.prune` walks that folder counting `.jpg`s, and a folder
  of WAVs inside a walk is a folder something else already owns.
- **One is kept.** A second cancel inside the five minutes replaces the first —
  the row says *the* cancelled dictation, and a menu that had to ask which one
  is a menu answering a question nobody has.
- **The words come back and nothing else.** The frames, the picks and the
  highlights that dictation had gathered are cleared at the cancel and stay
  cleared: they are cheap to take again and the screen has moved on, which is
  the same split `releaseHeld` already makes when it restores picks but not
  frames.
- **Where it goes is decided at the recovery, not at the cancel.** The
  destination the cancelled sentence had is minutes stale — he may have bound
  something else since, or changed the mode — so it asks the same question a
  fresh dictation asks when it ends: bound → the terminal, otherwise the caret.
- **It is a menu row and deliberately not a gesture.** Cancelling is the
  deliberate act and this is the second thought about it, which happens at the
  speed of deciding rather than at the speed of a hand; a chord for it would be
  one more thing the wheel could be misread as doing. `POST /test/recover` is
  how it is reachable from a desk, for `/test/replace-wispr`'s reason.
- **The recovered audio is filed in the corpus**, which the cancel path never
  did: it is a real sample of his voice that now has a transcript beside it.

**Verified end to end**: a caret dictation opened with the real chord, four
seconds of audio, cancelled — `🗑️ dictation cancelled — 4.0s of audio kept for
5 min`, one WAV in the folder — then recovered through the route: decoded, filed
in the corpus, pasted, and the file gone.

**And the flash says `Cancelled`, not `Dictation aborted`** (Victor's ask, the
same day). The old wording named the thing it happened to, which the chip has
just spent the whole sentence saying; what a row beside the pointer carries is
the one word that changed. *Aborted* was also the harsher reading of a verdict
he now has five minutes to take back.

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
- **The pointer is a hand over a row** (2026-09-09, Victor's ask), the same
  convention `inspect.js` follows in Chrome with `grab`: this is something to
  take. The arrow says nothing, and over rows made of text the pointer reads as
  an I-beam — which is the one thing this panel never offers, since it never
  becomes key and there is nothing to type into. It goes on a `.cursorUpdate`
  tracking area and **not** in `resetCursorRects`: cursor rects are reset by the
  *key* window, so on a panel deliberately never key they never fire at all,
  while `.activeAlways` on a tracking area is what makes a background app's
  cursor stick. The area covers the star too, which is right — it is the other
  thing on the row that is clicked.
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

### The little terminal grows out of the dialog (2026-09-09)

**A spawn no longer sends an outline to the new window — it sends the window.**
A small terminal is born just under the pre-send dialog, carrying a picture of
the session that has opened, and grows over a second until it lands on the real
one pixel for pixel.

Victor's ask: *"from the dialogue … it creates a terminal right under it and
then slowly move it out of the screen in about … one second, rather than having
that just the frame flying out. Attention: this only applies for creating new
terminals — if the message goes to an existing one, the frame thing keeps"*.

**It is the bind flight's own argument for carrying pixels, arriving late.**
That flight ends *small, at the cursor*, so the pixels are what identify which
window became the chip. The two outlined flights end **on** a window at full
size — and that is why they refuse a picture: the destination is something
Victor is *reading*, and a copy pasted over it covers the very thing it is
pointing at. A spawn's destination did not exist a second ago and has nothing to
cover, so the objection does not reach it, and what is left is the picture doing
what it does best. **Only the spawn changes**: `sendFlight`, to a terminal that
was already open, is untouched.

- **It lands invisibly, and that is the effect.** The picture is grabbed from
  the *destination* rectangle, so at the end of the travel it lies pixel for
  pixel on what is already there — the same seam the bind flight opens with, run
  backwards. What is left to dissolve is the white border, over
  `spawnFlightRest`.
- **`BindFlight.fly` grew one parameter for it**, `picturing:`, defaulting to
  `source`. Every other flight photographs the rectangle it leaves; this is the
  one case where the pixels come from the far end.
- **The seed is the destination in miniature** — `AppDelegate.spawnSeed`, 96pt
  tall with **the window's own aspect ratio**, 12pt under the anchor and clamped
  into that anchor's screen. The shape is half of what makes it read as a
  terminal at that size, the picture inside it the other half; a rectangle of
  this app's own proportions would read as another chip.
- **One second, not the send flight's 0.7** (`spawnGrowSeconds` against
  `sendFlightSeconds`, which is what `spawnFlightSeconds` was renamed to when
  the two parted company). A receipt for words that have already gone is glanced
  at on the way back to work; this one is the only thing on screen that says
  *which of the monitors around him* the session went to, and it says it by
  travelling the whole way there.
- **No `reversed:` anywhere in a spawn any more.** Both branches now run
  forwards, from a seed to the window. The panel-less fallback anchors under the
  chip instead of under the dialog, so the two are one sentence with two
  starting points rather than two animations.
- **The grab has the limit it always had**: `CGWindowListCreateImage` on a
  screen rectangle returns what is on that patch of screen, so a destination
  window buried under something else is photographed with whatever is on top. On
  the path this is written for the window has just been tiled into a free cell
  on a lateral monitor, so there is nothing on top of it.

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
minus the catalogue, since this panel has one layout rather than 40 states.

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
every bind plays (`AppDelegate.flySpawnedWindow`). Since 2026-09-09 it is that
window *carrying its own pixels*, growing out from under the dialog — see
*The little terminal grows out of the dialog*. A spawn is the one destination
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
(and `Transcribing...`), and `RelayWindow.spawnCollapsed` is the switch.

- **The 🔴 keeps the glyph column.** A frozen recording row is indistinguishable
  from a hung app, which is the one thing the pulse is here to rule out, and it
  cannot be given up for a mark that never moves.
- **The held panel keeps its title row.** It is parked in a corner, read whole,
  and *where these words are about to go* is exactly what a panel with a Cancel
  button on it has to say out loud.
- **Only the spawn.** Replace Wispr's `at caret` names a destination that
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
| what travels | words, shots, selections, picks | the words, plus any shot or pick he took |
| review | the held prompt, 3–5 s | none — it is pasted |
| back button | the shutter | the shutter (was Return until 2026-09-08) |

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
- **…but a bind mid-sentence overrules it**, since 2026-09-09: the left-plus-wheel
  chord made while a caret dictation is running sends the words to that terminal
  instead, and the chip stops saying `at caret`. The mode itself is untouched.
  See *A bind mid-sentence changes the recipient*.
- **No context shot, and that is not only a saving.** The automatic frame exists
  to be read by an agent beside the words; here there is no agent and no message.
  The real reason is the selection probe that comes with it: it posts a ⌘C into
  whatever field he is about to dictate into, and this is the one mode where that
  field is the whole subject. **This survives 2026-09-08 unchanged** — the
  shutter and the picker are live here now, but nothing *automatic* is: he asked
  for both in the same breath (*"nu trebuie să facă poză originală"*).
- **The shutter and the ⌘⇧-pick work here, since 2026-09-08** — see *What a
  caret dictation carries* below.
- **`at caret`, not `at the caret`** (2026-09-09, Victor's ask). The article was
  doing nothing: every other destination row on the chip is a bare name —
  `petclinic@main`, `workspace` — and a definite article in front of one of them
  reads as prose where the rest of the column is labels. It is also the row this
  mode leans on hardest, since it is the only destination that is not a place.

- **The chip says `at caret` behind the drawn map pin**, in the slot a spawn
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
  `at caret` on every sentence it takes, so a mode left on is visible
  before a word is spoken. `AppDelegate` seeds the flag and the tap from
  `StatusItem.isReplaceWispr` at launch **without** going through
  `setReplaceWispr`: that call flashes the overlay, and a restored mode is not an
  event to announce.
### What a caret dictation carries (2026-09-08)

**The shutter and the ⌘⇧-pick are live in Replace Wispr, and what he attaches is
pasted with the words.** Attach nothing and it pastes the transcript alone, byte
for byte as it always did.

```
schimbă prețul ăsta și butonul de sub el

[elements I picked in Chrome, on https://shop.example/cart, oldest first, each stamped with when in the sentence I clicked it: 0:12 div#cart > span.price (1.299,00 lei) · 0:21 button.buy-button (Cumpără acum)]
```

`AppDelegate.caretLine` is `terminalLine` with everything **automatic** taken out
and everything **deliberate** kept, in the wording it already has — his line was
*"nu trebuie să facă poză originală și nu trebuie să vină cu tot sufixul standard
… dar să pot să fac poză, în care caz poate să arate ca cel obișnuit"*:

| clause | terminal | caret |
|---|---|---|
| the words | ✓ | ✓ |
| `[the shots I took: …]`, `[elements I picked in Chrome: …]` | ✓ | ✓ — identical wording |
| `[selected: …]` | ✓ | ✓ — identical wording, since 2026-09-09 |
| the context frame, `[Focused window: …]` | ✓ | — none is taken |
| `[this text was dictated in RO or EN…]` | ✓ | — |

- **Why the paths stay and the language hint goes.** Both are addressed to a
  reader; the difference is who is certain to be one. A frame's path and a CSS
  selector are inert text to anything that is not an agent — noise in a commit
  message, but noise he asked for by pressing a shutter. The hint is
  unconditional ceremony on every sentence, and this mode's whole claim is that
  what he says is what gets typed: a stray sentence about mis-hearing pasted into
  a Slack message is the mode failing at its one job.
- **The selection joined them on 2026-09-09**, and it was the one attachment
  this mode refused. Victor's ask: *"even during the dictation at the caret, not
  bound to a terminal, I still want to capture selection of text during the
  dictation"*. What refused it was an argument about the **probe**, not about
  the highlight — `SelectionCapture.read` falls back to a synthetic ⌘C and the
  field under the caret is the one he is dictating *into* — and that argument
  only ever covered the *automatic* capture, which this mode still does not do.
  A highlight that gets here was read by a shutter press or watched settling for
  two seconds, and both are gestures he made. So `plusOneShot` calls
  `stashExtraSelection` here too (it is the only route that sees a highlight in
  a **Chrome page**, where the watcher's AX read is blind), and
  `syncSelectionWatch` is passed a bare `live`.
- **The one thing to keep in mind is what the caret is sitting in.** The watcher
  reads through Accessibility, and in this mode the focused field is the field
  the words are about to be pasted into — so a selection he made *there* to be
  replaced by the dictation is a selection this will file. It has to settle over
  two seconds first, which is longer than that gesture survives in practice, and
  the chip says `“ selecting …` before a word is pasted.
- **The bookkeeping had to be opened by hand.** `captureContext` is what normally
  sets `dictationInFlight` (which makes `plusOneShot` *attach* a frame rather than
  send it off alone) and `dictationStartedAt` (the zero every shot is named from),
  and this mode never calls it. Without both, a shot taken at the caret would be
  named by wall-clock and then dropped for want of a destination.
- **`caretLine` clears `pendingScreen` even though it can never be set.** It calls
  `shotsClause(screen: nil)` regardless, so a frame that *did* arrive would
  silently survive to be attached to the next sentence. One line, and it stops
  the method depending on a fact about its callers.
- **Both `/test` routes now honour the mode**, which is how any of this was
  checked at a desk: `/test/dictation/start` opens a *caret* dictation when
  Replace Wispr is on (otherwise it falls at `captureContext`'s first gate
  whenever nothing is bound — the state this mode is designed for), and
  `/test/dictation` pastes `caretLine` instead of calling `send`. Verified end to
  end through `/pick`: two picks in, the envelope above out, and the next
  sentence bare — the queue drains.
- **It cost a crash to learn, and the lesson is old.** The first version of that
  start route called `overlay.setSpawnDestination` directly, and `ElementPicker`'s
  callbacks run on its **listener thread** — `layoutContent` sets a window frame,
  and off the main queue that took the whole app down with a `SIGTRAP` inside
  `NSWMWindowCoordinator`. Every AppKit call in a picker callback needs its own
  hop; `captureContext` never had the problem because it already does one.

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

### The ring round the pointer, when the destination is not a place (2026-09-09)

**Whenever a dictation is headed for the caret, a wide yellow halo swells round
the pointer once he stops talking — nothing at all while he is still talking,
15% at its loudest.** `CaretHalo.swift`, switched from `syncBorrowedGestures`
beside the beacon — and since 2026-09-11 it is up for every dictation and the
beacon is gone; see *It is the beacon now*.

Victor's ask: *"when this mode is activated … draw a little halo ring around the
mouse … about 100 pixels, to warn me that I need to basically pick somewhere to
paste it … by default it's 10% … but grows in opacity up to 50% after two
seconds of low voice … over another two seconds"*.

**Every other destination this app has is a thing he pointed at and a thing the
chip names.** A terminal's icon and `petclinic@main`, a folder off the menu, ✨
for a session that does not exist yet. `at caret` is a name too, and that is
exactly the problem — it is the one destination that is not a place but
*wherever the focus happens to be when the words arrive*. A sentence spoken with
the focus in the wrong window is pasted into the wrong window, found afterwards,
with nothing having said so at the time.

**The chip cannot carry this**, and that is why the ring is round the pointer
rather than beside it. The chip rides the cursor and macOS hides the cursor the
moment he touches the keyboard — which is precisely the gesture this is about.
A ring is read at the edge of vision without being read at all, and what it is
drawn round is the thing he has to move.

- **Silence is the trigger, and that is the whole design.** While he is talking
  the paste is not imminent and the halo has nothing to ask, so there is nothing
  on screen. Stopping is the signal — the sentence is about to be pasted, and it
  is the last moment placing the caret is still free. Absent exactly while he is
  busy, present exactly when he is not.
- **5% at rest, arrived at from both directions in one evening.** It was 10%,
  on the argument that a mark present and ignorable is one he learns to
  recognise before he ever needs it — a number chosen for a 100pt ring, and one
  that does not survive the halo being 300pt across: at that size a tenth of an
  opacity is not a faint mark, it is a wash over everything under his hand, all
  sentence, every sentence. So Victor set it to **zero**, and then, minutes
  later, to **five**. Zero was the overcorrection: it is the halo *arriving*
  that says the paste is imminent, and something has to be there for the arrival
  to be a change in — with nothing at rest the swell is a shape materialising
  out of empty desktop, which is a bigger event than the thing it reports.
  **15% at the top rather than 50%** for the first of those reasons.
- **Two seconds before it starts**, because the gaps *inside* a sentence are
  ordinary: he pauses to think mid-dictation constantly, and a ring brightening
  on every breath would be a light flashing at the corner of his eye for the
  length of every sentence — the failure that keeps the `HQ` tag's pop
  edge-triggered.
- **`MicRecorder.quietSeconds`, not `level`.** (Still true of the silence
  trigger, which is `DropArrow`'s since 2026-09-11; the ring's own brightness
  *is* read off `level` now.) The beacon's readout falls
  linearly over three seconds by design, so "quiet" measured through it would be
  "quiet, plus however loud the last syllable was" — two and a half seconds of
  lag after a shout and none after a murmur. This is the **voiced bar itself**,
  the same test `voicedSeconds` counts: a hop clears it or it does not, and the
  clock restarts when one does. Counted in audio rather than wall clock, so it
  cannot run on while the microphone is shut.
- **`pasteMode`, not `replaceWispr`** — this sentence's destination, not the
  menu tick. A bind made mid-sentence takes `pasteMode` away and the ring goes
  with it, which is right: there is a terminal now, and the chip is naming it.
- **And `pasteMode` alone.** It shipped as `pasteMode && !isBound`, on the
  reading that a binding is a second answer to *where do these words go*. It is
  not: in this mode they go to the caret whether or not a terminal is bound, so
  the one sentence the ring exists to prevent is exactly as available bound as
  unbound. Victor, correcting it within the hour: *"nu ne-legat e cheia, ci dacă
  transcriu at caret (legat sau nu)"*. If anything the bound case is the worse
  one — the chip carries a terminal's name and icon all day, so `at caret` is
  the row that has to be **noticed** changing.
- **It shipped as a thin blue ring and lasted about an hour**, on this file's
  standing argument that blue is the one colour here that has never announced an
  *event*. Victor replaced it within the hour — *"inelul să fie galben, raza de
  3× mai mare și grosimea 5× mai mare, dar cu fade out spre exterior și
  interior"*, then a reference picture and *"ca un halou"*. The colour argument
  left out where this particular mark lives: over whatever he is working in, at
  10%, in the corner of his eye. Blue at a tenth is the first thing to vanish
  against a dark editor; gold is the most luminous of the signal colours and
  survives being that faint, which for a warning is the property that decides
  it. It crosses Victor Addons' capture yellow and that costs nothing — that one
  is a full-screen vignette lasting a second, this is a halo round the pointer
  lasting a sentence.
- **One colour, and symmetric — the reference picture was of a picture.** It
  was read off Victor's image and shipped with a near-white inner rim, a gold
  body, an amber tail and a long outer falloff against a short inner one; he
  took all of it back the same evening (*"să nu fie multi-color. doar galben,
  gradient similar de opacitate și înăuntru și afară"*). In that image the hues
  are what make it read as *light*, looked at on its own; here it is drawn over
  his actual work at a fraction of an opacity, and a second and third hue do not
  survive being that faint — they read as a smudge with a colour cast, and on a
  dark editor the white rim came out grey. The asymmetry went with them: it was
  borrowed from how a glow behaves round a bright hole, and there is no bright
  hole here — what is in the middle is the pointer. A band heavier on one side
  reads as a ring lit from somewhere, which is a fact about a light source that
  does not exist.
- **`spread` is one number**, the falloff either side of the core, and doubling
  it is the whole of *"2× mai lat … mai gros adică"*.
- **The reference PNG was keyed out and measured, and lost.** Asked twice
  whether the white background could not simply be removed (*"chiar nu poți
  scoate bg alb să fie transparent?"*), so it was: the ground is a flat
  `(246,246,246)`, which makes the classic unmultiply exact — `a = 1 −
  min(P/B)`, then `C = (P − (1−a)·B) / a` — and it recovers clean gold with the
  swirls and the sparkle intact. **At 100% it is the better picture. At 15% it
  is nothing at all**, and at 5% less than that: a glow authored on white takes
  its brightness *from* the white, so with the white gone what is left over a
  dark editor is olive mud, and over a light one it disappears. The source's own
  compression artefacts also become visible once the low-alpha pixels are
  divided back up. A third try — his texture as a mask, the app's gold through
  it — was blown out white on dark at full strength and mud at 15%, i.e. no
  better. The drawn gradient wins for one reason: it is a smooth falloff, so it
  looks the same at a twentieth of an opacity as at full, which is the only
  regime this thing ever runs in. Victor picked it with the contact sheet in
  front of him. **Do not re-key that image**; if the halo is ever wanted with
  texture, the opacities have to go up with it.
- **`NSColor.systemYellow` is deliberately not used.** It is dynamic and shifts
  with the appearance, and this is drawn over whatever is on screen rather than
  over the app's own surfaces: it has to be the same gold on a white page and on
  a dark terminal.
- **100pt was answering the wrong question.** It was picked as the smallest
  circle that still reads as one round a 20pt cursor — right for a mark *on* the
  pointer, and this is not that: it is the only thing on screen saying where a
  whole sentence is about to land. At 100pt and 10% it was polite to the point of
  being missable, which is the failure it exists to prevent. The core now sits at
  150pt out.
- **A radial gradient, not a stroked ring**, because the whole shape is a
  falloff and a `CAShapeLayer`'s stroke has one alpha across its width. The
  cross-section is `CaretHalo.profile`: peak at the core, zero at `core ±
  spread`, half-way in between, and **no stop that is not zero at one end**, so
  there is no radius at which the alpha steps.
- **Drawn rather than shipped as that PNG**, which was the literal reading of
  *"uite o imagine de folosit"*. The picture has an opaque light-grey background
  baked into it, so over a dark editor — where this spends half its life — it
  would be a grey square with a halo in it. A gradient has real transparency,
  costs no asset, is resolution-free, and takes the panel's own opacity when the
  swell brightens it.
- **`RelayPanel`, not `NSPanel`.** `constrainFrameRect` drags a borderless
  window back onto the display and under the menu bar, which for something
  pinned to the pointer is precisely wrong — at the top of the screen it would
  shove the ring off the cursor to keep it whole. Same trap `BindFlight` and
  `UnbindPop` are written under.
- **Global *and* local mouse monitors**, like the chip: the chip is riding the
  same cursor and is not click-through, so without the local half the ring would
  stop dead every time the pointer crossed it.
- **Never in a screenshot** (`sharingType = .none`) — the shutter is live in
  Replace Wispr, so this would otherwise be a gold halo burned into the very
  frames it is standing over, at the widest thing this app draws. Asked about
  directly (*"în pozele făcute să nu intre acest ring"*) and **verified twice**,
  because the flag is easy to write and impossible to see:
  `screencapture -l <its window id>` answers *could not create image from
  window*, the same refusal the overlay gives; and a whole-screen
  `screencapture` taken with the halo up shows **no gold annulus at the
  pointer** — mean R−B in the core band is −19.03 against −17.20 well outside
  it, i.e. ordinary content variation, where 5% of this gold would have added
  about +11. It therefore cannot be *reviewed* with a screenshot either, which
  is what `WT_SHOOT_HALO` is for.
- **Both edges are logged** (`◯ caret halo on/off`), for the selection
  watcher's reason: neither condition behind it is visible on screen, so *"why
  did the halo not come up"* has to be answerable from the file.

#### Spokes: the halo stylised with lines (2026-09-10, in progress)

Victor: *"cercul halou la dictation at caret să fie alcătuit din «spițe»: linii
de 3-5 px grosime concentrice, mai transparente spre interior și exterior, exact
ca haloul ca feeling, dar stilizat cu liniuțe"* — plus *"overall, să fie haloul
1.5× mai opac"*, which is why `rest` and `alert` are now **7.5% and 22.5%**.

`CaretHalo.Design` is the vocabulary and `WT_HALO_DESIGN=<name>` runs the app
with a candidate, because a contact sheet answers *what does it look like* and
the question that decides this one is whether it is still bearable an inch from
the work at the twentieth sentence. **`smooth` is still what ships**; nothing
below is live until he picks one.

Every design is the **same falloff** with a different pattern of strokes under
it, so a choice between them is a choice about texture and nothing else.

**Round one was judged by an adversarial reviewer and lost**, which is the
useful part. It proposed rings, spokes, weave, compass, spiral and arcs; the
review measured, rather than looked, and found:

- **Peripheral vision is a low-pass filter, and hairlines have no low
  frequencies.** Through a mild blur the six lost **86–94%** of their contrast
  against the ground where the smooth band lost **14%**. This mark is only ever
  seen out of the corner of an eye — that is not a detail of the brief, it is
  the brief.
- **Flux.** Integrated light per design at **100%** against the shipping halo at
  **22.5%**: spokes 0.71×, rings 0.66×, compass 0.60×, arcs 0.42×, weave 0.31×,
  spiral 0.08×. A pattern of strokes covers a tenth of the pixels an annulus
  does, so at the same nominal alpha it is a tenth of the mark — and no opacity
  setting recovers a fill factor.
- **Two ideas, four variations.** rings/weave/arcs are concentric circles with
  dash duty cycle as the only variable, which a blur integrates back into
  circles; compass is rings + spokes stacked; spiral collapses into arcs once
  chirality stops being visible, which is below about 30%.
- **Half of them stopped being a halo.** arcs and spiral read as *loading
  spinners* — saying *wait* at the exact moment the mark must say *act* —
  compass has cardinal axes and therefore direction, which an isotropic mark
  round a pointer must not, and spokes reads as a sunburst badge implying
  outward motion where this means *land here*.

Round two is drawn against those findings and is what `Design` holds now —
`bands`, `rings`, `waves`, `spokes`, `stipple`, `slots`:

- **Strokes are 4–5pt and feathered.** The pattern is blurred by ~1.2pt before
  the falloff is applied, which is the whole answer to the blur measurement: a
  soft-edged stroke keeps the low frequencies that survive being looked past.
- **Flux is normalised to the reference.** Each design's total light is measured
  against the smooth band's and scaled to match, capped at 3× so a sparse
  pattern cannot become hard opaque hairlines. That is what makes *1.5× more
  opaque* mean the same thing whichever design is chosen.
- **`slots` inverts the figure and the ground**: the solid band with twelve
  radial slots cut out of it, so the mass — and the peripheral visibility — is
  the reference's and the stylisation is in the gaps.
- **`stipple` is dots rather than dashes.** A dot has no direction and no
  handedness, which is what kept the spinner and compass readings out of it.
- **`waves` draws the falloff twice**, in the alpha and in the stroke width:
  6pt at the core down to 2pt at the rim.

Round two was measured too, and lost differently. **Only `slots` reached the
reference** (flux 0.99×, blurred peak 42 against 41) and it did so by *being* the
reference with holes in it — while filling the dark core with twelve converging
wedges, which is the one structural property that makes this a ring **around** the
pointer rather than a shape **under** it. Everything else sat at 0.07–0.38× and
five of six had no resting state at all on white. Two further findings worth
keeping:

- **The ring family converged on the incumbent rather than diverging from each
  other.** After a peripheral blur, `smooth`, `rings`, `waves` and `slots`
  correlate 0.97–1.00: not three concentric designs plus a reference, but the
  reference at four brightnesses. Ring *count* is a parameter, not a design —
  and a parameter where more is always better has one right answer.
- **`stipple` reads as a selection marquee.** Two concentric dotted circles is
  the grammar of marching ants and drop targets everywhere on the machine; an
  affordance says *click me*, and this mark's whole job is to point attention
  away from itself.

Round three took the one prescription the review gave — **mass out of geometry,
never out of alpha** — and doubled `waves`' stroke to 10pt at the core. It is the
most interesting failure of the four rounds: foveally a clearly ringed object
(sharp correlation 0.245 with the reference), peripherally the reference's own
signature (blurred 0.964), which is exactly the *lines up close, halo from the
corner of the eye* the brief asks for. It still came in **3.4× short of the
light**, and at 10pt a stroke is a band rather than a *liniuță* — four thick
concentric bands with dark gaps read as a **bullseye**, which aims where the halo
is meant to be ambient.

**The structural conclusion, and it is the useful part.** The smooth band covers
**20.4%** of its disc at peak brightness; strokes over the same annulus top out at
**9–15%** before they stop reading as strokes, and by then they are already at the
reference's peak brightness, so there is no alpha left to spend. **Adding lines to
nothing cannot reach the halo's visibility — the brief as stated is
unsatisfiable**, and that boundary has now been tested from both sides.

`ripple` is the inverse and is where this is resting: **the band at full mass with
its alpha modulated ±25% by a radial sinusoid**, five cycles, enveloped to flat at
both rims. Flux stays ~1.00× because it is the halo minus a little rather than
nothing plus a lot; the resting state survives because it *is* the resting state;
and it reads as concentric banding without becoming a target, because no radius
ever goes dark. It is `slots`' mass-preserving move without `slots`' gear.

**One trap worth keeping.** The first review measured stroke widths off the
*downscaled* contact sheet and reported 2–3px against a brief asking 3–5; the
render is 4× larger than the sheet, so those were 8px strokes. Its **flux**
numbers were unaffected — area-averaging preserves them — and they are the ones
that mattered. When a sheet is downscaled for review, say by how much.

#### What ships: `codex3`, and the envelope became a plateau (2026-09-10)

**Victor picked it out of the gallery of twelve** — short radial reeds that stop
short of the centre, drawn by **Codex (GPT-5.5)** against the same brief and the
same kill list. It is the one texture nothing here arrived at over four rounds:
everything drawn on this side was either concentric or a full-band sunburst, and
this is neither. Its reeds are *short* — they do not span the band, so they never
line up into rays from a common origin, which is exactly what made `spokes` read
as a badge.

**And the envelope became a plateau, because he drew it.** He marked up a render
with two circles — green at **r 103**, red at **r 193** — and asked for it to be
fully opaque only between them, with the fade to either side much more
pronounced: *"să fie full opac doar între cercul verde și cercul roșu … poza tre
să aibă transparență parțială pe periferie/interior"*.

That is not a tweak, it changes what the shape *is*. A single peak at the core is
a **glow**: one bright radius with everything else on the way to it. A plateau is
a **band with soft edges**: a wide region that simply is the halo, and two ramps
that stop it having one. For a texture made of many small marks the plateau is
the honest envelope — with a peak, the marks near the core are lit and the rest
are on a gradient toward not existing, so the field reads as a ring with a bright
middle rather than as a field.

`plateauInner` / `plateauOuter` are named constants because **two things read
them**: the envelope, and the texture's own code, which spreads its reeds across
the plateau and thins them into the ramps. A number that appears in a drawing and
in the alpha multiplying it must not be able to drift.

**The envelope settled on his exact spec**: *"a linear, progressive fade out from
the center 20% of thickness of the ring which is full opacity (before overall
fadeout at animation time)"*. Full alpha across the **central fifth** of the
ring's thickness, a straight line to nothing at both rims, and the parenthesis is
the important half — there are two fades and they compose. This one is spatial
and fixed, and the temporal one (`rest` → `alert` on silence) is a single alpha
over the whole panel: what the picture *is*, against what it is *doing*.

It replaced two earlier shapes in one step — a peak at the core, then a wide
plateau between the two circles he drew with gamma-curved ramps. The result is
more transparent than the gamma ever made it, because the ramps are simply much
longer: most of the ring is now fading rather than solid. Measured on the render,
ink above ground across the radius: 0 at the inner rim, a clean rise to full by
the plateau, flat across it within 8%, and a linear fall to 0 at the outer rim.

**The texture became one field for the same reason.** Codex had drawn it as a
dense band between two radii plus two thin scatters outside them, which is what
the *previous* envelope wanted. Under this one the ring is mostly ramp, so a
texture concentrating its ink in the middle fifth would leave the fade to be
carried by a handful of stragglers. The reeds are now uniform across the whole
ring — area-weighted, since an annulus at r has 2πr to fill — and the envelope
does all the fading, which is what *linear, progressive* asks for. Its lengths
are a fraction of the ring's thickness rather than a count of points, so the
texture survives the halo being resized; it has already been scaled once.

**Two corrections came before that, both from one look at the real thing.**

- **The flux gain was clipping the fade, which is the one arrangement in which
  the envelope cannot shape the light.** It read `min(1, coverage × gain ×
  envelope)`, so at a gain of 2.5 every pixel whose envelope was above 0.4
  saturated: both ramps were cut to a hard edge somewhere inside themselves and
  the picture *ended* instead of thinning out. Victor saw it at once — *"the
  image itself should be fading out inner/outer"*. The clamp belongs on the
  **ink**, with the envelope applied after it, and then the falloff on screen is
  exactly the falloff drawn.
- **The ramps are curved rather than straight** — *"nu poți accentua
  transparența pozei pe interior și exterior și mai mult?"*. A linear ramp is
  half lit at its middle, which over a wide fade is a lot of half-lit picture;
  `rampGamma` 2.2 puts that same span at 19%, so the ink spends most of the ramp
  close to gone and only lifts near the plateau. Measured on the render: the
  inner ramp's mid-point went from 20% of the band's ink to 6%, the outer from
  21% to 9%. The plateau's edges do not move — they are the circles he drew.

**And it is 0.7× the size** (`core` 105, was 150), also his. The texture carries
its light in many small marks spread over the whole annulus, so at the old radius
it covered more screen than the band ever did while saying the same thing: the
mark got bigger the moment it stopped being a single soft ring.

**The swell was never broken, and the test route is why it looked it.**
`/test/dictation/start` opens no microphone, so `MicRecorder.quietSeconds` stays
at zero and the halo sits at rest for ever — which reads exactly like a fade that
has stopped working. Driven with a real caret dictation and no speech, the panel
measures `0.075 · 0.075 · 0.127 · 0.209 · 0.225` at one-second intervals: two
seconds of patience, two of swell, exactly as designed.

**The correction went back to Codex's own session** (`codex exec resume --last`),
which is worth writing down as a working method: it still had the brief, the kill
list and its own reasoning, so the ask was three lines rather than a page, and
what came back was its design rebalanced rather than a fresh one that happened to
look similar.

**One thing it got wrong is arithmetic, not design, and was fixed here.** Its
reeds were spread evenly *in radius*, which is not evenly *in space*: an annulus
at r has 2πr of circumference to fill, so a constant count per radius thins out as
it goes. Measured on the first render — mean ink peaking at r≈130 and **40% down
by the red circle**, i.e. a gradient inside the region that is supposed to be
uniformly opaque. `sqrt` of the lane puts the count in proportion to r; the
density is then constant and the envelope is the only thing shaping the light.

#### What ships now: his picture, and it runs as a film (2026-09-10)

Victor sent an electric blue-and-magenta lightning ring: *"use this as the halo
when dictating at caret … faded out dynamically by the same rules"*. It shipped
as a still for an hour and he rejected it on sight — *"nu e animat!! trebuie să
fie multiframe: cu frame-urile decupate din imaginea pe care ți-am dat-o … tre
să pară că se animă ca un clip, nu doar fade in, fade out"*.

**The swell was never the animation.** It is the *state*: quiet while he talks,
insistent once he stops. What he was asking for is the ring being *alive* while
it sits there, which is a different axis entirely — and the still could not have
it at any opacity.

So the asset is **`assets/caret-halo-5x5.png`**: the 25 frames of his GIF
(`neon-electric-ring.gif`, 236px, authored at 20fps), keyed off black and packed
five across. Keying off black is exact where keying off white was not — a glow on
black *is* its own premultiplied form, so `a = max(r,g,b)` recovers it with
nothing to divide back up. That is the whole difference between this and the
September reference that came out olive mud on a dark editor.

Around it, `CaretHalo.filmLayer` and nothing else moved — same `core`, same
plateau envelope, same 2s of patience and 2s of swell:

- **The film is measured once, not per frame.** The alpha of all 25 is averaged,
  and the one transform that puts that mean ring's radius (86px) on `core`
  (105pt) is used for every frame. Measuring each separately would let the ring
  breathe a pixel or two per frame, which on a mark this size reads as the halo
  pulsing in and out of true.
- **The envelope is a mask, not a pixel pass.** A radial `CAGradientLayer` built
  from the same `profile` masks the whole film. With 25 frames the per-pixel
  multiply the still used would be 25× the launch cost for something the GPU
  gives away.
- **Discrete keyframes on `contents`.** Lightning does not tween: an interpolated
  cross-fade between two crackles is a blur, which is the *fade* he was
  objecting to. `isRemovedOnCompletion = false`, because the panel is ordered out
  between dictations rather than rebuilt — an animation that tidied itself away
  would leave a still ring the second time the halo came up.
- **The grid comes out of the file name** (`-<cols>x<rows>`, absent meaning one
  frame), which is the whole of the configuration: a still and a film are then
  the same code path, and a different sheet plays by being dropped in.
- **The light is still matched on the panel.** The film carries 0.51× the band's
  flux, so `artworkGain` is 1.98 and the two states run at **14.8% and 44.5%**,
  the same light as 7.5%/22.5% of the gold band. It is paid in panel opacity
  rather than in the bitmap because most of this band is already near opaque:
  any gain in the pixels flattens the filaments into a solid annulus, which is
  the one feature the picture was chosen for.

**And it runs at a third of the GIF's rate** — *"mai lentă animația 3×"*, watched
live at 20fps. The frames were authored for a clip that is looked *at*; this one
lives an inch from what he is reading while he dictates, and that fast it is a
flicker at the edge of vision rather than a mark that happens to be alive. 25
frames at 6.7fps come round in 3.75s.

#### It turns while it is up, and it collapses into the pointer when it goes (2026-09-10)

Victor, in one sentence with two halves: *"când se oprește dictarea … lightning-ul
acela din jur, haloul de lightning, să se micșoreze către mouse, făcând fade pe
ultimele 20% din drum. Și în timp ce e activ, să aibă o mișcare de rotație în
jurul mouse-ului continuă"*.

**The turn is the one motion that has the cursor as its subject.** The film
already crackles — 25 frames coming round every 3.75s — and that says *alive*
while saying nothing about the thing it is drawn round. A rotation does, because
the centre is the only part of the picture that does not move, and the centre is
the pointer. One revolution takes **16s**: 41pt/s at the rim, slower than a hand
moves and an 84° drift over one loop of the film. Anything brisker is a thing
spinning next to what he is reading — the objection that already took the film
down to a third of its authored rate. Clockwise, which is `CursorMarker`'s
direction and the app's only other rotation.

**The collapse replaces `orderOut`.** A mark that simply stops being drawn says
only that: it stopped. Shrinking into the pointer says where the sentence is
going — everything this ring has been warning about converges on the point it
converges on — and it lands at the moment the microphone closes, a decode ahead
of the paste. Half a second, on `BindFlight`'s argument at a smaller scale: a
receipt glanced at on the way back to work, not a gesture to be studied.

- **The fade is the last fifth of the *travel*, not of the time**, and under any
  curve but a straight line those are different instants. Both the scale and the
  ink are therefore sampled against one eased progress (smoothstep, 24 steps) and
  the fade keyed off that. For the first four fifths the ring does nothing but get
  smaller, at whatever brightness the swell had left it — so it reads as one
  motion rather than as a dissolve that happens to shrink.
- **It keeps chasing the pointer while it collapses.** The hand is usually already
  moving toward wherever the words are going, and a ring shrinking onto the spot
  the pointer has left converges on nothing. Same reason `BindFlight` re-reads the
  cursor every frame instead of sampling it once. The mouse monitors therefore
  outlive `hide` by those 0.5s, which is why `show` installs them only when there
  are none — a dictation opening inside the collapse would otherwise leak a pair.
- **Two layers, because two animations on one `transform` overwrite rather than
  compose.** That is written down in `CursorMarker`, whose bloom and quarter turn
  had to become a single `CATransform3D` for exactly this reason. Here the pair is
  worse than that one — the spin never ends and the collapse is one-shot — so they
  are simply given a layer each: a `stage` that scales, the halo underneath that
  turns. The stage is ours rather than the view's backing layer, which AppKit
  resets on any layout it feels like doing.
- **Neither animation writes a model value.** The spin is `isRemovedOnCompletion
  = false` for the film reel's reason (the panel is reused between dictations, so
  a self-tidying animation would leave a ring that turns for one sentence and
  stands still for every one after). The collapse fills forwards and is removed
  on the beat the panel is ordered out, so the layer snaps back to full size
  unseen — it has to, or the next dictation's ring comes up at 2% of its size.
- **A `show` arriving mid-collapse takes it back whole**, animations removed and
  a generation counter invalidating the delayed `orderOut` — otherwise the old
  collapse's tidy-up puts the *new* dictation's ring away half a second after it
  came up.
- **It ends at 2%, not at zero.** Four points across is below the ink of the
  filaments it is made of, so it is gone as a picture before it is gone as a
  number, and a layer scaled to nothing has no defined last frame.

**`WT_HALO_DEMO` now ends with it** rather than with `exit(0)`: the collapse is
the half of this that no still can show and that a demo cut off mid-frame cannot
either, so the last half-second of every demo is the ring going where it goes.

#### It is the beacon now, and it breathes on his voice (2026-09-11)

**The ring is up for every dictation, not only a caret one, and its brightness
and its size both ride `MicRecorder.level`.** It replaces the microphone on the
bottom edge outright — see *The beacon is gone*.

Victor, in one breath and correcting himself inside it: *"în loc de microfonul
care apare jos pe centrul ecranului, aș dori ca fulgerele să pulseze în același
ritm al discuției, cu același fade-out care se întâmplă acum la microfon.
Acestea ar trebui să pulseze, crescând dimensiunea cu zece la sută. Nu, chiar
20% față de cât e default, și apoi să se contracte înapoi, în timp ce se rotește
totodată."* So it is **0.2 and not 0.1**, and the rotation is the `spin` that
landed the day before.

- **He gave the old reading up knowingly.** The ring's presence *was* the
  message — `at caret` dictations and nothing else — and making it the beacon
  spends that: *"asta va implica și că va trebui să arăți fulgii de zăpadă,
  haloul de fulgi de zăpadă și când dictezi cu țintă. Însă, da? Fac și eu
  schimbarea asta."* What the caret dictation lost is given back by `DropArrow`,
  below, in a shape a ring never had.
- **The envelope is `RecordingBeacon`'s, verbatim**: `floor + (ceiling − floor)
  × level`, sampled at 20 Hz, with the three-second linear fall living in
  `MicRecorder`. The numbers are the ring's own and unchanged — `rest` 7.5% and
  what was `alert` is now `loud` at 22.5%, because what those were calibrated
  for is *how much of this ring a screen can carry while he works under it*,
  which the reason for lighting it does not change.
- **The swell is a scale off the same sample**, so a syllable is one event
  rather than two effects that coincide — and **from the voice, never from a
  timer**: a ring breathing on a clock proves a clock is running, which is the
  exact substitution that took the beacon's own free-running blink out.
- **Three motions, three layers.** `stage` belongs to the collapse, the film to
  the spin, the new `pulse` between them to the swell. Core Animation gives a
  layer one `transform`; this is `CursorMarker`'s rule (*two animations on one
  transform overwrite rather than compose*) arrived at a third time.
- **The panel grew by the same 20%.** `side` was measured to hold exactly the
  falloff at rest, so at full voice the outer glow was being cut off **square**
  by its own window — the one thing the falloff must not have. Found by the
  contact sheet, not on screen.
- **What silence means has flipped, and the two seconds did not.** The ring used
  to climb over two seconds of quiet; it now falls quiet, because it answers *is
  the microphone open* rather than *where do these words go*. `patience` and
  `swell` are unchanged and are `DropArrow`'s schedule now.

#### `DropArrow`: three dashes and a head, pointing down at the cursor (2026-09-11)

**While a dictation headed for the caret is waiting for him to stop talking, a
dotted amber arrow fades up above the pointer and marches down into its own
arrowhead.** `DropArrow.swift`.

*"ca să pot distinge când dictez fără țintă, vreau ca atunci când tac, când nu
mai vorbesc, să apară o animație … o săgeată punctată cu trei linii și un vârf
de săgeată în jos din dreptul mouse-ului, care se plimbă cu mouse-ul, ca să
sugereze cumva că trebuie să lase acel prompt undeva"*.

It exists because the ring stopped being able to say this: a ring on screen now
means the microphone is open, which is equally true of a sentence headed for a
bound terminal. An arrow pointing down at the cursor **names the gesture** —
*put it somewhere* — where a ring only ever said *something is different about
this one*.

- **The silence schedule is inherited whole**: `CaretHalo.patience` of quiet,
  then `CaretHalo.swell` to fade in, to a ceiling of 0.75. Two seconds rather
  than instantly for the old reason — the gaps *inside* a sentence are ordinary,
  and anything arriving on every breath is a light flashing at the corner of his
  eye for the length of every sentence.
- **Armed on `pasteMode`, re-read on every `setActive`**, so a ⌘⌃B mid-sentence
  gives the words a terminal and the arrow stops asking him to place them. The
  ring stays up: the microphone is still open.
- **Three dashes are drawn as five.** The group slides down exactly one period
  and repeats, so the dash that goes under the head has to be replaced at the
  top by one that was off the end; a gradient mask fades the top of the shaft,
  so what reads is three dashes flowing into the arrowhead and nothing arriving
  from nowhere. Linear, one period a second — a dash that eased would be a dash
  hesitating.
- **Amber, over a blue-and-magenta ring**, which is the one hue in the app's
  palette that cannot be mistaken for part of it at a glance, with a shadow
  outline so it survives a white page.

**It has a window of its own, and the contact sheet is what proved it had to.**
It was a layer in the halo's panel — the obvious build, since that window
already follows the pointer, and two windows chasing one cursor is two chances
to be a frame apart. But **the halo's window alpha is the voice**, and this
appears exactly when the voice has stopped: the arrow was being drawn through
the ring's *floor*, 0.75 × 0.148, i.e. a stain. No layer opacity recovers it,
because the number it would have to undo is on the window. So it has a panel,
and `CaretHalo.follow` places both off one `origin()` in one call — the frames
cannot be a frame apart because there is only one frame.

#### `WT_SHOOT_HALO` also writes an arrow sheet

`WT_SHOOT_HALO=/tmp/halo.png` now leaves `/tmp/halo-arrow.png` beside it: the
ring at both ends of its swell and the arrow over it, on a dark ground and a
light one (`CaretHalo.shootArrow`). A second file rather than two more rows,
because neither is a *design* — the first sheet is a gallery of textures and
this is one texture in two states with something drawn on top of it.

**It is the only way to look at the arrow at all.** The ring can at least be
watched through `WT_HALO_DEMO`; the arrow appears two seconds into a silence in
the middle of a caret dictation, on a `sharingType = .none` window. It earned
its keep twice on the first run — the clipped window and the crushed arrow are
both faults it found and neither was visible from the code.

**The arrow is drawn at its own opacity in that sheet**, in a host of its own,
precisely so the sheet cannot reproduce the bug that gave it a window.

#### Measured, 2026-09-11

Through `WT_HALO_DEMO` on a fabricated sentence — six seconds of syllables at 3 Hz,
six of silence — read back off the window server, which is what makes any of it
provable rather than asserted:

- **The ring's alpha** rides the voice between **0.148** and **0.445**, which is
  `opacity(rest)` and `opacity(loud)` at the film's 1.98 gain, and sits flat at
  the floor for the whole of the silence. The beacon's envelope, from outside
  the app.
- **The swell is 20%**, measured on the arrow sheet as the radius of the lit
  band's peak: **94.5pt at rest against 113.5pt at full voice, ratio 1.201**.
  Measured at the *peak* and not at a threshold, because a threshold moves with
  brightness and the two states differ in both.
- **The arrow is a second window at the same origin**, fading **0.164 → 0.333 →
  0.483 → 0.633 → 0.750** over the two seconds after the voice stops, holding at
  its ceiling, and gone the frame speech resumes — while the ring's own window
  sat at 0.148 throughout and jumped to 0.436 on the same frame.


#### `WT_HALO_DEMO` — the answer to *does it actually move*

`WT_HALO_DEMO=25 ./.build/debug/WalkieTalkie` puts the real panel round the real
pointer for 25 seconds with **no dictation**, driving `quietSeconds` off a clock
wrapped to one 6s cycle, so what is on screen is 2s at rest, 2s of swell, 2s
alarmed, repeating.

**It is the only thing that sets `CaretHalo.capturable`** (`sharingType`
`.readOnly` instead of `.none`), and that is the point: the panel is invisible to
every screen capture by design, so *"show me that it animates"* otherwise has no
answer — a recording of it is a recording of the desktop behind it. Nothing is
leaked by the exception: the demo has no dictation, no transcript and no chip in
the frame.

Measured through it on 2026-09-10, which is the shape of the proof to repeat:

- `CGWindowListCopyWindowInfo` on the panel, twice a second: `352×352` pinned at
  the pointer, alpha `0.148 · 0.165 · 0.239 · 0.313 · 0.388 · 0.445 · 0.445 …
  0.148`, i.e. rest, two seconds of ramp, the plateau, and the wrap. The swell,
  from outside the app.
- Six `screencapture` shots of the display the pointer was on, cropped to that
  same rect: the ring in every one and **a different pattern of filaments in
  each**, mean absolute difference 1.0–1.6 over the crop with the alpha barely
  moving between them. That is the film, and it is the half a still cannot show.

#### `WT_SHOOT_HALO` — because a falloff cannot be judged from code

`WT_SHOOT_HALO=/tmp/halo.png ./.build/debug/WalkieTalkie` draws the halo on a
dark ground and a light one, at both its opacities, and quits
(`CaretHalo.shoot`). Same argument as `WT_SHOOT_MENU` and `WT_SHOOT_WIPE`: the
panel is `sharingType = .none`, so the only other way to look at it was to start
a caret dictation — which answers *is it there* and not *does it look like the
picture he sent*.

**One row per design since 2026-09-10**, with the shipping halo as the top row:
a sheet of proposals with nothing to be different *from* is one nobody can judge,
and the question being asked of the spokes is precisely whether they still feel
like the halo.

**Two grounds, because this shape spends its life over both** and one that reads
on a white page can vanish on a dark editor; that is exactly the fault that took
it off blue. The columns are **the two states and 100%** — the profile at full
strength being the only way to judge a falloff drawn at a twentieth of an
opacity. The state columns carry each row's own `opacity(_:for:)`, so the
picture's row is drawn at the 16%/49% it actually runs at rather than at the bare
7.5%/22.5%; the full-strength column takes no gain, since it is there to judge
the falloff and not the state.

It paid for itself on the first run twice over — the band was so wide it read as
a filled disc rather than a ring, and **the sheet itself was lying**, applying
the opacity to the host view *and* to the draw, so one column came out at 1% and
looked like a bug in the gradient.

**Verified end to end** by driving the real chord — ⌃⌥⌘F7 posted at a desk, the
gesture Options+ sends — with Replace Wispr on, reading the panel back off the
window server: `108×108 alpha=0.100` centred on the cursor while silent for a
second, `0.426` at about three seconds, `0.500` from four on. Re-checked bound
after the condition came out.

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

**A caret dictation converts the same way, since 2026-09-09.** Victor's ask:
*"sesiunea de dictare pornită pentru paste … trebuie să se poată converti într-o
sesiune legată de un terminal, prin același gest … tot tipul actualizat în
consecință, și într-adevăr să se trimită nu la caret, ci în terminal"*. He starts
a Replace Wispr dictation with the forward button, decides mid-sentence that the
words belong to an agent after all, makes the left-plus-wheel chord at that
terminal, and the sentence goes there.

It is the spawn rule arrived at from the other side, and it needed writing for
exactly the same mechanical reason: `pasteMode` is decided at the press and
consumed in `stopLocalRecording`, so without this the words went to the caret
however deliberately he had just pointed at a terminal. `showBound` takes it back
on the same three conditions — a paste in flight, a recording running, and a
**deliberate** bind, never the 10s poll.

- **Only the sentence, never the mode.** `replaceWispr` — the menu tick, what the
  forward button means — is untouched, so the *next* press opens another caret
  dictation, which is what the tick says it does. Clearing the mode here would
  make a bind a hidden way to switch it off, discoverable only by finding it
  already off.
- **The chip is the other half of the ask.** `setSpawnDestination(nil)` takes the
  map pin and `at caret` down, and the line the bind writes a moment later —
  the destination app's icon and `petclinic@main` — is the top row again, which
  is the honest answer to where the words go. Same reason the spawn's row is
  taken back rather than left to be wrong for the rest of the sentence.
- **Both ways of ending it still work.** The forward button goes on toggling
  (`replaceWispr` is still on, and `onPasteToggle` stops a running recording
  whatever its destination), and the wheel becomes available the instant the
  binding lands, since `syncLocalCapture` is keyed on `isBound`.

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

### …and so does the sentence that starts right after one (2026-09-09)

**A bind speaks for the next five seconds.** A dictation opened inside them goes
to the terminal that was just bound — even when the gesture that opened it was
the forward button's, which in Replace Wispr means *the caret*. Victor's ask:
*"rezolvă race-ul ăsta ca să pot imediat ce am legat terminalul să pot și începe
dictarea"*.

**It is the rule above, reaching a few seconds earlier.** There the chord lands
while the words are being spoken and takes the destination back; here it landed a
breath *before* the first of them, which is a fact the sentence had no way to
know. Both are the same sentence: a bind is the one gesture whose whole content
is where the words go, so it outranks a mode that answers *wherever the caret
is*.

His own afternoon is the measurement (`relay.log`, 2026-09-09): 11:51:32 bound
ttys014 and 11:51:34 dictated — at the caret; 11:55:45 bound ttys009 and 11:55:48
dictated — at the caret, 292 characters pasted into whatever had focus instead of
going to the agent he had just pointed at. The one he opened nine seconds later
(11:53:49 → 11:53:58) was the deliberate dictate gesture and went where he meant.
Every failure is a gesture made **two or three seconds** after a bind.

- **Consumed by the first dictation that reads it** (`takeBindGrace`), so it is a
  grace and not a mode: a caret dictation started a minute later is untouched, so
  is the second one inside the same window, and `replaceWispr` — the tick, what
  the button means — is never written. Same rule the mid-sentence take-back
  follows for the same reason.
- **Five seconds**, which is the 2–3s measured plus the hand. Long enough to
  cover the travel from the chord to the button, short enough that it cannot be
  lived in.
- **Armed on the gesture route only** — in `bindFrontmostTerminal`, not in
  `showBound`. `picker.onBindTTY`, the restore half of a restart, is not somebody
  pressing something, and a relay that has just replaced itself must not redirect
  the first thing he says afterwards.

**And a bind still resolving is a destination.** That is the literal race in the
report: `bindFrontmostTerminal` spends one to two seconds of `osascript` working
out what it is looking at (measured: 11:50:15 pressed, 11:50:17 bound), and for
all of it `isBound` is false — so a dictate gesture made in that window fell
through `hasDestination` and did **nothing at all**, silently, with not even a
line in the log. It is banked on `recordWhenBound` and honoured when the terminal
is known, exactly as `recordWhenModelReady` banks a press made against a model
that is still loading, and for that flag's reason: the intention is unambiguous,
and asking him to make it again means noticing nothing happened first. A bind
that finds nothing bindable drops the banked press with it.

**Verified end to end** by driving the real chord — ⌃⌥⌘F7 is a keystroke, so the
gesture Options+ sends can be posted at a desk, which is what makes this path
testable at all without a hand on the mouse. Bound, then the button: `🎙️ forward
button just after a bind — dictating at the terminal, not the caret`, with the
selection watcher and the context frame a bound dictation gets. The button
pressed 0.25s into a bind: `holding it`, then `bind landed — opening the
microphone the press was waiting for`. And with a binding in place but no fresh
bind, the same button still opens a caret dictation — no watcher, no frame.

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
the pulse, `Listening...`, `Transcribing...`, the destination, and the tally of
what this dictation is carrying — frames, highlights, picks (*The tally*). The
shots row came back on 2026-09-09 carrying **only its count**; the mouse and
`+ selection` beside it are still behind `showsGestureHints`, and that legend
replaces the count rather than sharing the line with it.
(`Preparing…` was on that list until 2026-09-06,
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

### The order of the rows, and Chrome is last (2026-09-09)

Top to bottom on the chip: **the dictation's state** (`🔴 Listening... [HQ] (2m)`,
or a wait), **the destination**, **the shots**, **the quoted highlight**, and
**Chrome**. Victor's rule for the last two: *"citatul să apară mereu deasupra
Chrome-ului … Chrome trebuie să fie mereu ultima din listă"*.

They were the other way round until then, and the argument that reorders them is
about what each row *belongs to*. A highlight is part of **this** message — it
was read at the shutter, it rides out with the words, and it goes when they do —
so it sits with the frames above it. The ⌘⇧ row is the odd one out twice over:
before he has picked anything it is not a payload at all but an invitation, and
after he has, it is the one row that survives *between* messages. A thing that
outlives the message belongs at the foot of it — and a row that shuffles up and
down as a highlight comes and goes is a row he has to find again every time,
beside a cursor he is not looking at.

### The tally: what this dictation is carrying, read down the icon column (2026-09-09)

```
🔴 Listening... [HQ] (2m)
[Terminal] petclinic@main
📸 ×3
“  public Order placeOrder(Cart…      → ×2 after four seconds
[chrome] ×3 ⤢
```

Victor's ask: *"an emoji of the camera and the number representing how many
pictures have been taken for this dictation … basically an overview of how many
elements in Chrome, how many pictures and selection text blocks were captured
during the current dictation. If any, of course."*

**The `📸 ×N` row is back**, and for a different reason than the one that removed
it. It went when the red vignette and the cursor mark took over as the shot's
receipt — those land at the moment of the gesture, which is a better answer to
*did that press take* than a number he has to look down at. But that is not the
question three minutes and four presses into a dictation: *what am I about to
send* is, and until the held panel opens the total exists nowhere.

- **`×N`, nothing at zero** — *"if any, of course"*. In a bound dictation it says
  `×1` from the first frame, because he took that picture by starting to talk
  (`publishShotCount`); in Replace Wispr, which takes no automatic frame, the row
  appears the moment he presses the shutter.
- **The overview is the icon column read downwards**, not a fourth row restating
  the other three. All three rows already share `glyphBox`, so the counts line up
  under each other and each is two characters wide.
- **It shows through the decode as well as the sentence** — `RelayWindow.gathering`
  is `listening || transcribing`, which is Victor's *"during dictation on
  whatever state"*: what he attached does not stop being attached while he waits
  for the words. The **invitation** half of the Chrome row stays on `listening`
  alone, since ⌘⇧ goes back to the browser the instant the microphone closes and
  a row offering it then would be a lie about which gestures are live.

**And the Chrome row collapses like the selection row above it**, four seconds
after the newest pick: *"the Chrome icon should also be followed only by the ×2
… I don't want to see the div thing here"*. It is the same bargain one row up,
for the same reason — the selector answers *did the click catch the button or the
div around it* at the instant it lands, and after that it is the longest string
the chip can carry, restating something already checked beside a cursor he is
trying to work with. The clock restarts on every pick, because every pick is a
new answer to that question.

**`⤢` after the count means one of them was dragged** — Victor's *"diagonal
2-sided arrow … next to the number, to tell whether there is any move element"*.
It is a fact about the **queue**, not about the newest entry (`publishPicks` asks
`contains { $0.move != nil }`), which is exactly the kind of thing a count cannot
say about the things it counted: the message carries *move it to here* and not
only *this element*. Typed rather than drawn, in the row's own font, so it reads
as punctuation beside the number rather than as a second picture on a row that
already has one.

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

**The pictures are always 2×**, whatever screen the shooter ran on (2026-09-09).
`bitmapImageRepForCachingDisplay` answers at the backing scale of the display the
window is on, so the catalogue came out 1× with the external monitors awake and
2× on the built-in Retina panel — and then *every* file in `docs/states/` turns up
in the diff with nothing in the change to explain it. `snapshot` now builds the
rep itself at a fixed 2×. The page lays each picture out at its size in **points**
(`build-overlay-states.py` writes `width=`/`height=` from the manifest), so the
extra pixels are sharpness and nothing else moves.

- `./docs/shoot-overlay-states.sh` → all 40 states at once, and the page that
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
| `Recover Cancelled Dictation` | `arrow.uturn.backward` | |
| `Take Screenshot` | 📷 | `⬇️` |
| `Select Screen Area` | ✂️ | `🛞 drag` |
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
tty — **yellow while it is bound**.

The line carries one fact: `ttys006`. It is written from `showBound`, the one
switch that owns it.

**Same problem the caret halo solves, at the other end of the sentence.** The
halo answers *is it hearing me?* (the corner beacon did until 2026-09-11); this
answers *which of these twenty terminals is it aimed at?* — and the chip, which is the only thing that has ever
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

## The beacon is gone — the halo took its job (2026-09-11)

**There is no longer a microphone on the bottom edge of the screen.**
`RecordingBeacon.swift` is deleted; what answers *is it still hearing me?* is now
the ring round the pointer, which is up for **every** dictation and breathes on
his voice. See *The ring round the pointer* for what it does and what that cost.

Victor's ask: *"în loc de microfonul care apare jos pe centrul ecranului, aș
dori ca fulgerele să pulseze în același ritm al discuției, cu același fade-out
care se întâmplă acum la microfon"*.

**The argument the beacon was built on is intact and is what moved.** The chip
says a dictation is running and says it *beside the cursor*, which is the one
place he is not looking while he talks — he dictates while reading another
display, with a full-screen window up, and macOS hides the pointer the moment he
touches the keyboard, taking the chip with it. That is still true, and the halo
answers it better than an 84pt emoji on the bottom edge did, for one reason the
beacon spent three weeks failing to find: **it is drawn round the thing his hand
is on**, so there is no spot to have to look at. The beacon moved twice looking
for that spot — a 150pt corner, then Wispr Flow's badge slot, then the bottom
edge — and the halo needs none of them.

What is kept, verbatim, is the **envelope**: a floor plus the voice's share of
the way to the top, resampled at 20 Hz, with `MicRecorder.level`'s three-second
linear fall doing the fade-out. `CaretHalo.refresh` is `RecordingBeacon
.watchLevel` with a scale spent alongside the alpha. Everything written down
about why that fall is three seconds and why it is linear — *"I find myself
speaking a lot to keep it open"* — is still live and now lives in `MicRecorder`.

**Two things the beacon had are genuinely gone**, and both were answers to being
a separate window in a fixed place: the pointer-avoidance (it took itself off
screen when the cursor came near, so he could click under it) and the one-panel-
per-display machinery. A mark centred on the cursor cannot be in the way of the
cursor, and it is on the pointer's screen by construction.


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
`🗑️ Cancelled` is there, with nothing on screen saying the second
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
picture has no ink the new row is already showing through it, `Cancelled`
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

### What the cancel actually looked like, and the two things wrong with it (2026-09-09)

Reported by Victor as *"apare dictation cancelled și de pe aia strălucește D-ul,
cumva, mult straniu — nu-mi place cum arată"*. Both faults were visible in the
first contact sheet and neither was guessable from the code.

**The row that no longer fits was being guillotined.** The chip hugs its current
state, so `🔴 Listening... [HQ]` over `petclinic@main` is 23pt taller than the
one-row `🗑️ Cancelled` that replaces it — and the window has already
resized by the time the sweep plays. Top-aligned and clipped to the host, the
second row was therefore **cut through the middle of its letters** and sat there
sliced for the whole third of a second, in every frame before the edge reached
it. Nothing about a line crossing the chip says the row under it should end in a
horizontal cut; that is the "strange" part he was looking at, and the sweep was
being blamed for it.

Nothing can *show* the extra row — the window is the size it is — so the fix is
to let it leave rather than sever it: a vertical ramp over the last `fadeHeight`
(12pt) of what fits, which reads as the row going out of frame, which is what is
actually happening. It is a mask on a holder layer wrapping the picture, since
the picture's own mask is already the sweep and a layer has one.

**And the band was a flare, not a brightening.** 26pt wide at 0.90 alpha put a
white blob over two glyphs of *both* strings at the seam — where the outgoing
`Lis` and the incoming `Dic` are already superimposed by the cross-fade — so the
first letter of the new message arrived inside a bright smudge. That is the D.
It is now **13pt at 0.55**, which is what *"a bit brighter"* asks for, and the
soft edge went 7pt → 3pt so the two strings ghost across one letter instead of
two. Compared frame by frame on three sheets before choosing.

### `WT_SHOOT_WIPE` — because this is the least reviewable thing in the app

`WT_SHOOT_WIPE=/tmp/wipe.png ./.build/debug/WalkieTalkie` draws the cancel sweep
as a strip of 13 frames on a dark ground and quits (`ChipWipe.shoot`,
`RelayWindow.shootWipe`).

It took a bug report to notice a row being cut in half for a third of a second,
dozens of times a day, and that is the whole argument. The chip is invisible to
every screen capture (`sharingType`), the sweep lasts 0.32s, and it is drawn in
**layers** — so `RelayWindow.snapshot`, which draws the *view* tree and stands a
wipe down before it does, cannot see it either. Reviewing a change meant
provoking a cancel and watching, twelve times, and being sure of nothing. Same
argument as `docs/overlay-states.html` and `WT_SHOOT_MENU`, same answer: the real
layers drawing themselves.

- **`CALayer.render(in:)` honours `mask`** — checked with a throwaway program
  before any of this was written, because the entire effect is two masked
  pictures and a stencil, and a renderer that ignored masks would have produced a
  confident lie. (It ignores *animations*, which is why the next point exists.)
- **The motion is posed, not animated.** `picture()` returns its layer **and** a
  `pose(t)` that sets the same three values the CA animations set — the edge's
  position, the band's, the glow's opacity — so the sheet is the effect at an
  instant rather than an impression of it. `ease(t)` is CoreAnimation's
  `easeInEaseOut` written out (the cubic Bézier `0.42, 0, 0.58, 1`, solved by
  Newton), because a sheet drawn from a different curve than the one that ships
  is a picture of something nobody sees.
- **On a dark ground.** The chip is bare and its ink is white with a halo: on
  white the brightening is invisible, on transparency it is unjudgeable. A
  terminal is what this actually sits on.
- **It drives the two layouts by hand**, not through `flash(_:)` — that hands the
  sweep to `rememberChip`/`wipe`, which plays it on screen over a third of a
  second, which is the thing that cannot be photographed.

**The picture it sweeps away is taken at the top of `layoutContent`, not at the
flash**, and that is the one piece of this that is not about drawing. Cancelling
is four calls in one call stack — `setListening(false)`, `clearSelection()`, then
`flash("🗑️ Cancelled")` — and the first two each relayout the chip.
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

### "Sometimes it does not catch the element" (2026-09-09)

Reported as *"deseori când sunt pe Chrome și apăs ⌘⇧ jos, nu prinde elementele
uneori"*, with the guess that something in the page is slow to load. It is not
the page. There are exactly two causes, and only one of them is a delay.

**The first is not a bug: the gesture only exists while a dictation is open.**
`/ping` answers 503 outside one (`ElementPicker.dictating`), so a ⌘⇧ hold made
before he has started talking arms nothing at all and the click goes to Chrome —
by design, because ⌘⇧-click is how a link opens in a new tab and jumps to it, and
a browser that stopped doing that all day would read as broken. Measured on this
Mac while the relay sat idle: `GET /ping` on 8917 → **503 in 1.4ms**. This is the
common case and the answer to it is *start the dictation first*.

**The second is real latency, and it was serial when it did not have to be.**
`tryArm` used to ask for the probe only after the 400ms hold had already elapsed,
so the two waits ran one after the other: 400ms, then the message to the service
worker, then its answer. The loopback half of that is free — 1.4ms to a live
relay and **0.2ms** to a refused port, so the three-port fan-out is noise — but an
MV3 service worker is torn down after ~30s idle and has to be *started* before it
can handle the message, which is the variable few hundred milliseconds nobody was
paying attention to. Inside that gap `armed` is still false, so a click falls
straight through to Chrome: the gesture "does nothing", and doing it again more
slowly works, which is exactly how a timing threshold feels from the outside.

Two changes, and the first is the fix:

- **The probe now starts with the hold, not after it** (`beginHold` sets
  `probing`, `tryArm` awaits it). The worker gets the whole 400ms to wake up in,
  and in the ordinary case the answer is already sitting there when the timer
  fires — so arming happens at the 400ms the gate was designed to cost and not at
  400 plus a wake. It costs nothing when the hold turns out to be a shortcut: the
  answer is dropped, and the worker caches it for a second anyway.
- **A spinner says the wait is happening.** 150ms after the chord completes, if
  the outline is not up yet, a small ring appears beside the cursor and goes when
  the arm is decided either way. Victor asked for it by name — *"mi-ar plăcea o
  rotiță, un loading pe parcurs"* — and it is what turns *the gesture is
  unreliable* into *the gesture is not ready yet*. 150ms rather than immediately
  because every ⌘⇧ shortcut passes through this same code and is poisoned by its
  third key within a few tens of milliseconds, so a shortcut never sees one.
- **And the arm time is logged**, one line per hold:
  `[walkie] armed 431ms after ⌘⇧ went down`. The one number that answers "why did
  it not catch it", and the only way to tell the two causes apart from the
  outside — a refused arm prints nothing at all.

**The spinner is the one departure from *a page that never sees ⌘⇧ held never
gets a node from us*.** A hold that lasts 150ms now builds the UI even if the arm
is then refused. The node is still 0×0, still `pointer-events:none`, still inside
a closed shadow root — and the alternative is a gesture whose latency is
invisible, which is the whole complaint.

### ⌘⇧-drag: where he would move it, without moving it (2026-09-09)

**Hold the chord, press on an element, drag, let go — and the message says the
element moves from one page coordinate to another. Nothing in the page moves.**
Victor's ask: *"să permit drag and drop de elemente prin extensie, dar să nu mut
nimic în pagină … să capturăm poziția originală și coordonatele … dragul se duce
translucent, doar chenarul, fără nimic … și când îl las, la mouse-up, comunică
unde a ajuns elementul"*.

```
[element I picked in Chrome, on https://shop.example/cart, stamped with when in the
 sentence I clicked it: 0:12 div#cart > span.price (1.299,00 lei), moved from
 120,340 to 500,205 (top-left, page coordinates)]
```

**Nothing in the page is touched**, which is what makes this safe on somebody's
live application in front of a room: the element keeps its position, its styles
and its listeners, and the only thing that travels is the rectangle this
extension was already drawing on top of it. What reaches the agent is an
*instruction* — move this, to there — to be carried out in the source, not a
change already made in the DOM that the next render would throw away.

- **Only the outline travels, and translucent** — `.dragging` clears the fill and
  the glow and dashes the border. A filled box is a picture of where the element
  would go, drawn over the very thing the drop is being judged against.
- **The cursor closes.** `grab` → `grabbing`, the page's own convention for *you
  are holding this*, and the natural second half of the hand the outline already
  puts up.
- **Page coordinates, top-left**, of the element's own corner and not of the
  pointer (the grab offset inside the element is subtracted at the drop). A
  *viewport* corner is a fact about how far the page happened to be scrolled at
  that instant, which is the one thing certain to have changed by the time
  anybody reads the message; a page corner is where the element sits in the
  document, which is what a rule that moves it would be written against. The
  `from` corner is measured against the scroll at the grab and the `to` corner
  against the scroll at the drop, so a page scrolled mid-drag still reports two
  corners in one frame.
- **The live readout is the payload.** The label follows the box saying
  `500, 205 page`, because he is aiming at a coordinate and a drop he cannot read
  until the message arrives is a drop he has to make twice.
- **The pick still fires at the press, and the drag amends it.** The outline
  turning green under his finger is the receipt and it must not wait for a
  release that may be a second away — and at the press nothing can know whether a
  drag is coming. So a drag sends the same element again with its two corners on
  it, and `AppDelegate.record` **replaces** the entry it already has when the
  incoming pick carries a `move` and the newest pending pick has the same path.
  One gesture, one element in the message. Matched only against the newest entry,
  so two deliberate picks of two different things can never collapse into one.
- **A drag abandoned by letting the chord go sends nothing.** The gesture was not
  finished, and a drop nobody made is not a coordinate to report.
- **Under `DRAG_MIN_PX` (4) it was a click**, which is the existing behaviour
  untouched: the press picked, the release does nothing.

Verified end to end at a desk through the loopback routes, since the gesture
itself needs a browser and a hand: `/test/dictation/start`, two `/pick`s (one
carrying a `move`), then `/test/dictation` — the envelope above came out on the
clipboard, and repeating the same path with and then without a move produced
**one** entry carrying the move, which is the amendment rule.

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
title, frame}`, plus `move` when he dragged it — built in `describe()`
(`inspect.js`), re-read and clamped by `ElementPick(json:)`, emitted by
`ElementPick.json`. Nothing in that chain may rename or drop a key: the `relay`
skill documents them by name, and an agent reading an old key it no longer gets
is worse than an agent with fewer keys. Adding one is free, which is how `move`
arrived.

`move` is `{from: {x, y}, to: {x, y}}`, the element's top-left corner in page
coordinates before and after — see *⌘⇧-drag*. It is parsed **all or nothing**
(`ElementPick.move(_:)`): the page is hostile input, and a half-parsed corner
would put `0,0` into the message as if he had dropped it there.

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

### The clause: when, what, and on which page (2026-09-09)

```
[elements I picked in Chrome, on https://shop.example/cart, oldest first, each
 stamped with when in the sentence I clicked it: 0:12 div#cart > span.price
 (1.299,00 lei) · 0:21 button.buy-button (Cumpără acum), moved from 120,340 to
 500,205 (top-left, page coordinates)]
```

It read `[pointed at: <path> (<text>)]` until then, and Victor named all three
things missing from it in one breath: *"dacă se aleg mai multe elemente pe
parcursul dictării, ele trebuie toate să fie capturate împreună cu timpul la care
au fost clickate … și nu «pointed at» ca text, trebuie să-i spui că picked
element in Chrome … și să-i spui și URL-ul paginii în care ai făcut pick, nu doar
path-ul, că nu e relevant"*. `AppDelegate.picksClause`, shared by `terminalLine`
and `caretLine`.

- **Every pick was already carried; the *stamps* were not.** The list has been
  complete since the queue existed — what the message dropped was *when*, which
  the held panel has shown all along (`pickLines`). That is the half that orders
  a sentence against its own pointing, and `−0:08` is the normal case rather than
  an oddity: he finds the thing, then says what to do with it. Both readings now
  come out of one `stamp(_:since:)`, so the panel and the envelope cannot drift.
- **The zero had to be carried to get there.** `dictationStartedAt` is cleared as
  the message is built and the panel holds the prompt for seconds afterwards, so
  `Message.startedAt` travels for `Message.spawn`'s reason: the fact is true at
  the press and unavailable at delivery.
- **The page, because a selector without one is not an address.**
  `div#cart > span.price` resolves in any number of documents, and an agent's
  first move on being handed one is to work out which — a question already
  answered in `pick.url` and simply never said out loud.
- **Factored out when they all came from one page**, which is the usual case and
  the difference between one URL and five copies of one. The same bargain
  `shotsClause` strikes with the shots' directory, and it says something true
  besides. Mixed pages put the URL on each entry, and an entry whose URL is
  missing blocks the factoring outright — otherwise it would silently inherit
  another entry's page.
- **`picked … in Chrome`, not `pointed at`.** The old wording named the gesture;
  this one names what arrived, which is a DOM element out of a browser and not a
  direction.
- **Singular and plural are both written**, because the clause is a sentence and
  `elements I picked … oldest first: 0:12 button` for one pick reads as a list
  with something missing from it.

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
   the `🗑️ Cancelled` flash draws *over* the chip rather than resetting
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

- **an external display beside the laptop** → the window is **tiled** across
  every non-Retina screen *lateral to the primary*, left to right. *"tile them
  somehow so that they don't overlap with others… use all the monitors you have
  around"*.
- **nothing but the Retina display** → there is nowhere to move it to, so it opens
  **behind** instead.

**The screen above is not one of them, since 2026-09-09** — Victor: *"start the
terminals on the lateral screens, not on the screen above"*. At home the built-in
display has three identical Dells around it: one left (`x = -1920`), one right
(`x = 1728`) and **one stacked directly above** it (`-89, 1117`), and that third
one was taking a third of the spawns. A screen over the laptop is the one place
on that desk he has to lift his eyes off the keyboard to read, so a session
opening there is a session he has to go and find — the exact failure the tiling
was written to remove, moved from the Retina display to the one above it.

**"Lateral" is measured, not named.** A screen is *stacked* when it shares more
than half of **its own** width with the primary's horizontal span; stacked
screens are dropped. Two consequences are deliberate: the primary is never
stacked, so a desk of nothing but external monitors still tiles across all of
them; and a sliver of overlap — two monitors side by side but nudged — is
*beside*, not above, which is why the test is a share of the width rather than
any overlap at all. Verified against the four real displays: the two side Dells
kept, the one above dropped, the Retina one dropped as before. The window still exists and `adoptSpawnedWindow` still binds
  it a beat later — delivery goes through `do script … in <tab>`, which does not
  need the window in front.

**Neither case activates Terminal any more (2026-09-08).** The tiled one used to,
and `activate` is an *application*-level raise: it lifts every window Terminal
owns, on every display, so putting one new window on a side monitor also threw
the sessions Victor keeps on the built-in screen over whatever he was reading —
*"toate terminalele sar în față, inclusiv cele de pe retina… nu ar trebui să
apară nimic nou în față pe retina"*. Measured with Finder frontmost and Terminal
already running: `do script` creates the window and **does not** take the front,
so dropping the line is the whole fix. The quarter-second restore afterwards
stays, for the one case that still steals it — a Terminal launched from cold by
`do script` — and it now runs in both branches. It can only give back the
*focus*: windows an activation raised stay raised, which is why `activate` had to
go rather than be undone after the fact.

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

**The little terminal then leaves the dialog** — `BindFlight.fly(from:
spawnSeed(under: promptFarewell, like: window), to: { window }, picturing:
window)`, the same call the send flight makes with two arguments changed. It flies the moment
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

**The fallback is the same flight born under the chip**, for a spawn that never
showed a panel — there is then nothing but the pointer to leave from, which is
where Victor first put it before he corrected himself. What follows is why the
direction was chosen, and it is still the argument for both.

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

## The ring covers Wispr Flow's dictations too (2026-09-11)

The halo had become the microphone's beacon that same day — up for every
dictation, breathing on the voice, with `RecordingBeacon` deleted under it. Then
Victor pointed out the hole in the word *every*: it was every dictation **this
app** runs, and this app is not what he dictates with most of the time.

*"vreau … să apară acest cerc de fulgere în jurul mausului și atunci când
folosesc, de exemplu, Wispr, ca să dictez"*, and then the reason, which is the
part that settles it: *"mai este o diferență dacă nu am activat opțiunea de
înlocuire Wispr Flow; dacă aceasta nu este activată, atunci Wispr trebuie folosit
în tot, în orice context în care dictez, fie că este terminal, câte terminale noi,
fie că este binduit … că este la cursor, peste tot"*.

Replace Wispr is a tick that is down far more often than it is up. With it down,
Wispr Flow is the dictation tool, in every context — into a terminal, into a
bound one, into a fresh one, into whatever holds the caret. A beacon that is dark
for the commonest dictation of the day cannot be believed on the rare one: the
absence of the ring would stop meaning *nothing is listening* and start meaning
*nothing of mine is listening*, which is not a distinction his eye is making at
the edge of vision.

So there is **no gate**, in line with the rule already written for the ring: not
on `pasteMode`, not on a binding, not on the Replace Wispr tick. Wispr's
microphone is a second way for the same question to be answered yes.

### The signal: one boolean about a pid, and the two that were rejected

`WisprWatch` asks CoreAudio for `kAudioProcessPropertyIsRunningInput` on every
audio process object whose bundle id starts with `com.electron.wispr-flow` —
prefix, because Wispr Flow is Electron and spreads over `com.electron.wispr-flow`,
`.helper` and `.accessibility-mac-app`, and which one holds the device is its
business and changes between versions.

**This is not the Wispr Flow database coming back.** The standing rule —
*never reintroduce the Wispr Flow database path* — is about a **recogniser**:
about this app reading `flow.sqlite`, transcribing the blob it found there and
swallowing Wispr's own paste. Nothing here reads a word, a file or a transcript.
It reads the same fact the orange dot in the menu bar is drawn from, and it would
be equally true of any app that opened the microphone; Wispr Flow is named only
because it is the one that means *Victor is dictating*.

Two cheaper-looking signals were measured and dropped:

- **The device's `kAudioDevicePropertyDeviceIsRunningSomewhere`** answers *is
  anybody using the input*, and on this Mac that is permanently yes. Measured
  2026-09-11 with nothing being dictated: `ai.krisp.krispMac` and
  `com.rogueamoeba.audiohijack` both at `runningInput = 1`, all day. A flag that
  is always true is not a signal.
- **The chord this app already types.** `HotkeyTap.postWisprHandsFree` posts
  `fn ⌃ Space` on every forward-button click outside Replace Wispr, so the relay
  does know about one of the ways a Wispr dictation begins. It is still the wrong
  thing to draw a ring from: it says *a chord went out*, not *the microphone
  opened*; it is a **toggle**, so the relay's idea of the state drifts the first
  time Wispr misses one or he ends the dictation from Wispr's own window; and it
  knows nothing about a dictation he started from the keyboard himself. The
  device cannot be wrong about this, and nothing else can be right about it.

Listeners rather than a poll, two kinds: one per process on the flag itself, and
one on the system object's `kAudioHardwarePropertyProcessObjectList` that
re-subscribes when a client appears or goes away. The second is not optional —
an Electron helper is only filed as an audio object once it first touches audio,
so the process that will hold the microphone this afternoon need not exist when
the app launches.

### The ring breathes, so the relay opens its own microphone alongside

`WisprWatch` can only say *open* or *closed*, and a boolean cannot drive a ring
whose whole design is that it moves on syllables — a ring breathing on a timer is
exactly the substitution that killed the beacon's free-running blink. Asked
whether that was worth a second microphone, Victor said yes: *"Da, deschide
microfonul"*.

So `MicRecorder.startMetering()` — `start(to: nil)`: the same device, the same
converter, the same tap, the same 16 kHz mono int16 the meter's constants were
fitted on, and **no `AVAudioFile`**. There is no path for the audio to be kept
even by accident; `append` writes only `if let file`, and `stopMetering` throws
the session away rather than handing a recording back. Nothing reaches the
corpus, the model or the outbox.

Two apps on one input device is ordinary on macOS — each client taps the hardware
and neither sees the other, so Wispr's audio is not touched or degraded — and the
orange dot is already lit by Wispr itself, so nothing new appears in the menu bar.

`wisprMeter` is a **second `MicRecorder`**, not a mode on the first: the two
sessions are started by different things and can overlap (a wheel dictation
opened during a Wispr one), and one `AVAudioEngine` has one input tap. Apart,
the relay's own recording can never be interrupted or re-pointed by something
another app did. `AppDelegate.voiceMeter` picks between them — the relay's own
session wins when it is running, because that is the one with a transcript riding
on it — and it is the only thing `CaretHalo.level` and `.quietSeconds` read.

### And the arrow, because Wispr pastes at the caret

*"Da, ca la at-caret"*. A Wispr dictation ends in a paste wherever the focus
happens to be, which is the exact failure `DropArrow` was drawn for, so
`setActive` is called with `atCaret: pasteMode || (wisprDictating && !listening)`
— the relay's own dictation outranks it on that half only, because while a wheel
dictation is live the destination is the relay's to name and the chip is naming
it. The ring itself is `listening || wisprDictating`, with nothing outranking
anything: the microphone is open either way.

## Six heads closing in, instead of one arrow hanging above (2026-09-12)

`DropArrow` shipped the literal reading of the first ask — three dashes marching
down a shaft into an arrowhead, the whole thing above the pointer — and lived
that way for an afternoon. Victor came back with a different shape and the
reason inside it: *"trebuie ca, atunci când mă opresc din dictare, să apară trei
capete de săgeți de sus și trei capete de săgeți de jos care clipesc cumva spre
interior, spre cursor, ca să-mi atragă atenția să depun dictarea undeva … dacă
vorbesc, ele fac fade-out repede, dar cum nu se mai aude voce, fac … ca și cum
m-ar atrage privirea spre locul în care e cursorul, ca să pun textul unde
trebuie"*.

### What was wrong with the arrow is what the replacement is built out of

An arrow hanging above the pointer is a thing to **read**, and reading costs a
fixation. It says *down there* while sitting somewhere else, so the eye lands on
the arrow first and on the cursor second — and the cursor is the entire message.
It is also **off-centre by construction**: the only asymmetric shape on screen is
the one thing guaranteed to catch the eye, and it was catching it in the wrong
place.

Six heads closing in from both sides say it without being looked at:

- **Symmetric about the hot spot.** There is nothing off to one side to fixate
  on, and the only thing the arrangement can point at is its own centre, which is
  the pointer. The shape cannot be misread because it is not read.
- **The flash runs outside → inside.** What moves is a *convergence* rather than
  an object, and peripheral vision is built to follow convergence — that is the
  property being borrowed, and it is exactly what he described wanting
  (*"ca și cum m-ar atrage privirea spre locul în care e cursorul"*).
- **Open Vs, never filled triangles.** A stroke reads as a direction and a fill
  reads as an object; six objects around the pointer would be six things in the
  way of what they are pointing at.

The dashes' rule survives the redesign, moved from the march into the flash:
**linear, no easing.** A hint that hesitates is a hint being admired.

### Geometry and the wave

Three a side — two do not read as a sequence, four crowd the ring's inner rim.
`gap` 18 pt from the hot spot to the innermost pair, `step` 13, so the heads span
18…44 pt: inside the halo's hole (~36 pt) and the inner ramp of its band, where
the film is at its faintest. 18 rather than the 14 the old arrow used above the
pointer, because the macOS cursor's body hangs *below* the hot spot and this
arrangement has a head down there now.

Both heads of a ring share one layer and therefore one flash — they are the two
halves of a single event closing in, and a pair that could drift a frame apart
would read as two hints rather than one.

The wave is a keyframed `opacity`, `dim` → 1 → `dim` over the first fifth of a
1.4 s cycle and dark for the rest: a beat between sweeps is what makes it a pulse
rather than a shimmer. The phase is **`timeOffset`, never `beginTime`** —
`beginTime` is an absolute point on the layer's timeline, and this panel is built
once and shown again on every silence for the rest of the day, so the phases
would be set relative to whenever it happened to be built. The outermost ring
gets the largest offset, so it is furthest along its cycle and lights first.

**`dim` is 0.40, and the number came off the white half of the contact sheet.**
At 0.28 the unlit heads read perfectly well over a terminal and all but vanished
on paper — 0.28 × `ceiling` is 0.21 of amber on white, held up by the shadow
outline alone. The lit head is still 2.5× its neighbours, which is all the wave
needs.

### Going away is a fade now

*"ele fac fade-out repede"*. `quiet` snaps to zero on the first voiced buffer, so
the panel used to be ordered out between two frames — a disappearance sharp
enough to be its own event, at the exact moment his attention should be going
back to the sentence. `recall` is 0.18 s: gone before he has finished the next
word, and nothing snaps.

The fade needs a `fading` flag rather than just a completion handler. Every 20 Hz
tick through a silence-that-ended would otherwise start another one, and a fade
that has since been overruled would order out a panel that is visible again —
which is why `refresh` puts the alpha back through `animator()` while one is in
flight, and drops `fading` so the old completion handler stands down. `hide()`
(a bind mid-sentence, the dictation ending) stays a hard cut: nothing is being
asked for any more, so there is nothing to fade out of.

### The `NSNumber.init` trap that killed it seven seconds in (2026-09-12)

The heads shipped and the app **crashed on the first dictation that raised
them** — 20:31:39 the microphone opened for a Wispr sentence, 20:31:46 `SIGTRAP`
in `-[NSApplication _crashOnException:]`, and the relay was simply gone with its
log ending mid-dictation. Nothing in `relay.log` says anything: an NSException
thrown inside a `CATransaction` flush is not a Swift error and there is no line
to write.

The crash report's exception backtrace is the whole story:

```
QuartzCore  copyFloatVector(NSArray*, bool*)
QuartzCore  -[CAKeyframeAnimation _setCARenderAnimation:layer:]
CoreFoundation  ___forwarding___          ← an unrecognised selector
```

`a.keyTimes = [0, 0.06, 0.22, 1].map(NSNumber.init)` compiles, and the bare
function reference **resolves to an `NSValue` initialiser**: the array comes out
full of `NSConcreteValue`, which has no `floatValue`, so `copyFloatVector` sends
one into the forwarding machinery and out comes an exception on the main thread
inside a flush. Reproduced in isolation — a bare `CAKeyframeAnimation` added to a
layer in a window — printing the element classes either side of the change:

```
.map(NSNumber.init)   keyTimes: NSConcreteValue ×4   exit 133 (SIGTRAP)
[0, 0.06, 0.22, 1]    keyTimes: __NSCFNumber ×4      exit 0
```

Bare literals under the `[NSNumber]?` contextual type bridge correctly, and are
what every other keyframe in this app already uses (`CaptureEffects`,
`CaptureFlash`, `RelayWindow`) — `ChipWipe` spells out `NSNumber(value:)` where
the values are computed. The mistake existed in exactly one line in the repo.

**Why the contact sheet said it was fine.** `DropArrow.picture()` is *posed* —
that is the rule it was written to follow — so it never builds `flash()` at all.
A static render of six heads is a picture of a shape, and the bug was in a
`CAKeyframeAnimation` no still can contain.

**`WT_HALO_DEMO` is the regression check, and it would have caught this.** The
demo arms the arrow (`setActive(true, atCaret: true)`) and drives six seconds of
fabricated syllables followed by six of silence, so it crosses `patience` at
t = 8 and raises the heads for real. Measured both ways on 2026-09-12:
`WT_HALO_DEMO=11` exits **133** with the bug and **0** with it fixed. Anything
animated in here gets eleven seconds of demo before it gets installed.

## The ring is up before anything is opened (2026-09-12)

The morning's ask was the crash (*Six heads closing in…*, below/above depending on where you
start reading). The afternoon's was what the crash had been hiding: *"cercul de fulgere trebuie
să apară imediat ce Wispr Flow începe să înregistreze"* — immediately, not when the first level
sample arrives.

The edge itself was never slow. `WisprWatch` is two CoreAudio listener blocks, so the boolean
arrives on the watcher's queue the moment Wispr's helper opens the input; the log had `wispr flow
opened the microphone` and `◯ caret halo on` in the same second all along. What was slow was
everything the handler did *before* asking for the ring:

1. **`wisprMeter.startMetering()` ran first, on the main thread.** It is a synchronous device
   open — `AVAudioEngine.inputNode`, `InputDevice.select`, `installTap`, `engine.start()`. Tens to
   hundreds of milliseconds on a good day. Measured 2026-09-12 in a `.build/debug` binary, which
   has no microphone grant of its own: `-[AVAudioEngine inputNode]` **never returned at all**. With
   the old ordering that is not a ring that fails to breathe, it is a Wispr dictation with no ring
   whatsoever, and an app frozen with it.
2. **`CaretHalo.makePanel()` ran inside the first `show()`** — decoding the 236×236 ×25 sprite
   sheet and integrating its alpha twice, once for the centroid and mean radius and once for the
   flux `artworkGain` is matched against. Measured **419–438 ms**, paid by the first dictation of
   the day, in the one place in the day it must not be paid.

So: the ring goes up first (`syncBorrowedGestures()` moved above the meter), the meter opens on a
serial `wisprMeterQueue` where it can take as long as it likes, and the panel is built at launch by
`CaretHalo.prewarm()` — the same trade `applicationDidFinishLaunching` already makes for the
Whisper weights, for the same reason: the relay is a login item that is up before he is.

A third wait was found by the same hang and is the more dangerous of the three, because it does not
need a missing grant to bite. **`MicRecorder.level` and `.quietSeconds` took the same `NSLock` that
`start(to:)` holds across the device open**, and they are read from the halo's 20 Hz timer *on the
main thread*. A slow microphone open therefore froze the whole app — ring included — for its whole
duration: the beacon that exists to say *I am hearing you* stopped moving precisely because a
microphone was being opened. Both getters are `lock.try()` now and return the last value they saw
when contended. A readout sampled at 20 Hz has nothing to gain from being exactly current and
everything to lose from being late.

`⚡ ring up <n> ms after Wispr Flow opened the microphone` is written on every real edge, measured
from `WisprWatch.edgeAt` (stamped on the watcher's own queue immediately before the hop to main),
and suppressed for the test route, which enters below the watcher and would otherwise print the age
of the last real dictation.

### The chevrons unbound were never gated — they were crashing

Victor also asked for the inactivity chevrons during a Wispr dictation *"și când nu e bindat"*.
Nothing gated them: `atCaret` is `pasteMode || (wisprDictating && !listening)` and the halo's half
of `syncBorrowedGestures` reads no `hasDestination` at all, so an unbound Wispr dictation arms
`DropArrow` exactly like a bound one. What made them look absent was the `.map(NSNumber.init)`
crash: the heads are *built* at `CaretHalo.patience`, so every Wispr dictation with a two-second
pause took the app down at the instant they were due — bound or not. Verified after the fix with
`POST /unbind` then `POST /test/wispr {"on": true}`: the ring came up, the app was still alive
seven seconds later, and a screen recording of `WT_HALO_DEMO` shows the three amber heads above the
pointer inside the dimmed ring.

### `POST /test/wispr` — because the signal belongs to another app

`WisprWatch` reads a CoreAudio boolean about a process this app does not own, so before this route
the ⚡ ring, the chevrons and (now) the ✕'s cancel could only be exercised by actually dictating
into Wispr Flow. That is how a crash in the chevrons survived a day of testing: the one path
nobody can run at a desk is the one Victor runs fifty times a day. It enters at
`wisprDictationChanged(_:measured:)`, the watcher's own edge, and opens the relay's meter like the
real thing.

## The ✕ cancels the dictation (2026-09-12)

*"Butonul ✕ de pe chip trebuie să anuleze dictarea, nu doar să închidă chip-ul."*

The ✕ is hidden until the pointer is over the overlay, and the overlay is a panel he can reach
**during a dictation** (`setHovering` — *"It comes back with the panel — during a dictation, and on
the prompt"*). So at the one moment it is actually reachable it was doing the one thing it must
not: `endSession`, which announces the session's end to the watching agent and quits the app that
is drawing the ring.

It cancels first now, and only ends the session when there was nothing to cancel
(`cancelDictationInFlight` returns whether there was). Two microphones, two cancels:

- **The relay's own dictation** goes through `cancelLocalRecording` exactly as it always did — audio
  kept for five minutes, nothing transcribed, nothing sent.
- **A Wispr Flow dictation** is not this app's to end from the inside, and the 2026-08-29 rule
  against reading Wispr's database is not being reopened for a cancel. What is available is the way
  this app already talks to Wispr Flow: a chord on the wire. `HotkeyTap.postWisprCancel()` posts
  **Escape** — Wispr's own *discard this, paste nothing* — built out of `postWisprHandsFree` and
  sharing everything that makes that correct: the Options+ settle, the wait for Victor's own
  modifiers to come off the wire (a held ⌘ would make this ⌘Escape, which is something else
  entirely in half the apps he dictates into), the `hidSystemState` source, and `backButtonStamp` so
  this app's own tap knows the keystroke is its own. Bare, with no flags: posting it under whatever
  `flagsState` happens to say is a different chord on a bad day.

The ring comes down on Wispr's **own** closing edge, not on the cancel. Nothing here guesses at the
state, so a cancel Wispr ignores leaves the beacon truthfully lit rather than lying about a
dictation that is still running.

The menu bar's *Cancel Dictation* row now reads `isDictationCancellable` (`localRecording ||
wisprDictating`) instead of `isRecording`. `isRecording` still gates *Start Dictation*, *New
Session* and *Recover Cancelled Dictation*, all of which are about the relay's own microphone and
must go on being.

## The ring is up on Wispr's keystroke (2026-09-12)

Putting the ring ahead of `startMetering` was not enough: *"cercul tot apare târziu"*. The
CoreAudio edge is the truth about the microphone and it is not the first observable thing about the
dictation — between Victor's finger and `kAudioProcessPropertyIsRunningInput` sit Electron waking,
an overlay window and a device open.

The earliest observable moment is the keystroke that asks for it, and this app already has every
key event in its hands. Which keystroke is not a guess either: Wispr Flow writes its own shortcuts
into `~/Library/Application Support/Wispr Flow/config.json` under `prefs.user.shortcuts`, keyed by
keycodes joined with `+`, and reading it settles three things at once:

| shortcut | code | what |
|---|---|---|
| `49+59+63` | `popo` | fn ⌃ Space — the hands-free toggle `postWisprHandsFree` has been posting all along |
| `54+61` | `ptt` | right ⌘ + right ⌥ held — push-to-talk |
| `53+59` | `dismiss` | **⌃Escape** — which is what `postWisprCancel` should have been posting, and was not |

Push-to-talk is two modifiers and nothing else, so it never produces a `keyDown` at all: it is a
`flagsChanged`, and the test has to be on the **device-dependent** bits (`NX_DEVICERCMDKEYMASK`
0x10, `NX_DEVICERALTKEYMASK` 0x40) because it is specifically the right-hand pair. Matching
`.maskCommand`/`.maskAlternate` would raise the ring on every ⌘⌥ in the day.

A ring raised on a guess has to be able to come down again: `wisprSpeculativeGrace` is 1.5 s, and
if no microphone follows the keystroke the ring goes and the log says why. That is also why the
CoreAudio edge stays — it is the confirmation, not the trigger. A beacon that lies is worse than a
beacon that is late, which is the whole reason this was not simply moved onto the keystroke and
left there.

Both numbers are logged, which is what Victor asked for: `⚡ ring up <n> ms after <gesture>
(speculative — waiting for the microphone)` and `⚡ mic edge confirms the ring <n> ms after the
hotkey`. Measured through `POST /test/wispr {"hotkey": true}` on 2026-09-12: **0.6–0.7 ms** from
the gesture to the ring, against a 50 ms target. The second number is his to read off a real
dictation — it is the gap this whole change exists to cover.

The meter comes up with the guess rather than with the confirmation, so the ring breathes from the
first syllable; `MicRecorder.start(to:)` is a no-op on a session already open, so the confirming
edge costs nothing when it arrives.

### `⬅️` cancels a Wispr dictation too

The forward button held and the mouse flicked left (`VK_F11` under ⌃⌥⌘ from Logi Options+, and the
wheel held with Logi gestures off) is `onLocalCancel`, and it went straight to
`cancelLocalRecording`. It goes through `cancelDictationInFlight` now, like the ✕ and the menu row:
the gesture that abandons a sentence must not depend on which app happens to be hearing it. Local
behaviour is byte-identical — `cancelDictationInFlight` tries `localRecording` first and only falls
through to Wispr when there is no local recording to throw away.

## The ring goes down when the words land (2026-09-12)

*"Cercul și săgețile trebuie să dispară când textul a fost inserat, nu când s-a oprit
înregistrarea."* Between the microphone closing and the words appearing is the whole
transcription — another app's round trip, for a Wispr dictation — and it is exactly the stretch in
which he is waiting and has nothing to look at.

`settling` is a fourth reason for the ring to be up, beside `listening`, `wisprDictating` and
`wisprSpeculative`, and it carries `settlingAtCaret` so the chevrons do not disarm underneath it.
How it ends depends on whose paste it is:

- **Wispr's** is another app's ⌘V and there is nothing of it to observe from here except the
  pasteboard changing under it — Wispr writes the transcript there and presses ⌘V, exactly as
  `pasteText` does. Polled at 20 Hz, and **only while settling**: a permanent pasteboard poll is a
  different and much worse thing than a two-second one.
- **The relay's own caret dictation** ends its settle from `pasteText` itself, at the ⌘V rather
  than at the transcript: the words are on screen when the key goes out, not when the model handed
  them over.
- **A bound dictation is deliberately not settled.** Its words go through the held prompt — up to
  seven seconds of countdown with a panel on screen already saying so. A ring hanging over that is
  a second indicator for a state that already has one, and it would outlive `settleTimeout`.
- **A cancel never settles.** There are no words to wait for, so the ring goes at once.
  `wisprCancelling` is what tells the closing edge that arrives a moment after Wispr's ⌃Escape not
  to start a settle for a sentence that was thrown away.

`settleTimeout` is 6 s and the log always says which thing ended the ring: `⚡ ring down: <reason> —
<n> ms after the recording ended`, one of *pasted at the caret* / *Wispr pasted at the caret* /
*timed out waiting for the text* / *nothing was recorded* / *cancelled*. Measured 2026-09-12
through the test routes: a pasteboard write one second into the settle ended it at **1051 ms** with
*Wispr pasted at the caret*; with nothing written, at **6298 ms** with *timed out waiting for the
text*.

## Wispr Flow everywhere (2026-09-12)

*"Wispr Flow is the dictation source for everything"* — the caret, a spawned session, and the
bound terminal that had been the local model's alone since 2026-08-29. Wispr is better at his
accent, it is already running, and it is what his hand reaches for. The relay's job stops being
*be a recogniser* and becomes *decide where the words go*.

### One interface, because a second branch is how the first one rots

The two paths did not look alike from the outside and that was the whole problem. The relay's own
microphone went through `startLocalRecording` / `stopLocalRecording`, produced a transcript and a
WAV, and everything downstream hung off it. Wispr Flow went through `wisprDictationChanged` and
produced **a boolean** — the ring knew a microphone was open and nothing else did. The Wispr path
spent a month with no transcript in it precisely because it was a branch nobody exercised.

So `DictationSource`: `start` / `stop` / `cancel`, `didMaybeBegin` / `didBegin` /
`didStopListening` / `didTranscribe` / `didEnd`, and a `meter` the halo breathes on.
`WisprFlowSource` and `LocalWhisperSource` implement it; `AppDelegate` holds one and names neither.

| | `WisprFlowSource` | `LocalWhisperSource` |
|---|---|---|
| start | posts Wispr's own hands-free chord | opens `MicRecorder` |
| begins | on the chord, confirmed by CoreAudio | synchronously, inside `start()` |
| level | a second `MicRecorder` alongside Wispr's | the recording's own meter |
| transcript | Wispr's delivery, intercepted | `LocalWhisper` over the WAV |
| audio | the meter's WAV, kept for the corpus | the recording itself |

`localRecording` became `listening`, and the rename is the point: *is a microphone open* is the
source's question and `isRecording` answers it, where every gate in `AppDelegate` means *does this
app have a sentence in flight*. For Wispr those are seconds apart.

### The probe — how Wispr Flow delivers, measured

Nobody knew. The deleted `blockInjection` predated two Wispr versions, and the three candidate
answers — a synthetic ⌘V, a key-by-key type, an Accessibility insertion — need three different
mechanisms to catch. So the capture window logs every synthetic key it sees, capped at six lines,
and the first real dictation answered it:

```
21:35:59 probe: synthetic key 9 flags 0x20100000 from pid 4904 (Wispr Flow)
21:35:59 ⌘V from Wispr Flow — 1580 ms after the microphone closed (taken)
21:35:59 🗣️ wispr transcript via Wispr's ⌘V — 96 chars
21:36:00 ⌨️ ttys007 foreground=claude — 582 chars
21:36:00 ⌨️ delivered to the bound terminal
```

**Keycode 9 is V, `0x20100000` is `maskCommand` with the device-dependent left-⌘ bit, pid 4904 is
Wispr Flow.** It is a ⌘V, this app's head-inserted session tap sees it before the front app does,
and swallowing it is the whole wrap. A second sentence measured the same thing at 5926 ms.

An Accessibility insertion would have shown up here as **nothing at all**, which is why the probe
is armed on every dictation and stays: the day Wispr changes, `relay.log` says so.

### The wrap, and the flag it lives behind

`wrapWispr` (menu tick, on by default): swallow the ⌘V — V with ⌘, from a process whose name says
Wispr, inside the capture window — read `NSPasteboard`, and deliver the words the way the local
path always did. Bound: `send(kind: "dictation")`, the held prompt, the shots, the picks, the
selection. Unbound: `pasteText(caretLine(words:))`, which is the same paste Wispr was about to
make, one caret later. Off: Wispr pastes where the focus is and the relay only draws the ring.

Victor's own ⌘V carries pid 0 and can never match; this app's own carries `backButtonStamp`. The
`keyUp` is swallowed with the `keyDown` — an orphaned release is a key the app underneath thinks is
still down — and the ⌘ itself is left alone, so it goes out and comes back balanced.

**This is not the database coming back.** The pasteboard is where Wispr itself puts the sentence a
millisecond before it presses the key; `pasteText` puts its own there too. Nothing in `Sources/`
opens a file of Wispr's.

### The ring shrank away and came back

The first evening's build shipped with the old `wisprSpeculativeGrace` of 1.5 s, and Victor
reported it within minutes: *"the lightning starts fast, but only later the yellow screenshot
bubble appears, and there is a pause in which the lightning ring disappears, only to reappear"*.

The log is the whole story:

```
21:35:41 ⚡ ring up 0.9 ms after fn ⌃ Space (speculative — waiting for the microphone)
21:35:43 ⚡ ring down: no microphone within 1500 ms of the hotkey
21:35:47 wispr flow opened the microphone
21:35:47 ⚡ ring up 29 ms after Wispr Flow opened the microphone
21:35:47 context screen captured: shot-00:00(...)
```

**Six seconds from the chord to Wispr's microphone.** Every previously measured gap was warm —
324, 478, 528, 634, 674 ms, which is what 1.5 s was fitted to. Cold, Electron takes ten times that,
and the grace expired in the middle of it: ring up, ring *shrinks away*, ring back four seconds
later with the chip and the screenshot bubble arriving for the first time.

Two fixes, and the second is the one that matters:

1. **`speculativeGrace` is 12 s** — the worst measured open × 2, never under three. A retraction is
   for a chord Wispr *ignored*, which is rare enough to be worth the patience.
2. **The dictation opens on the gesture.** `didBegin` fires on the chord, so the ring, the chip,
   the context shot, the ⌘C probe and the music pause all happen at the same instant; the CoreAudio
   edge **confirms** and returns. A second `didBegin` would take the halo down and put it back,
   which is exactly the flicker. Verified through the test routes with a five-second gap:

   ```
   21:43:22 ⚡ POST /test/wispr {hotkey} — opening the dictation on the gesture
   21:43:22 ◯ caret halo on   👁 selection watcher on   ⏸️ pausing audible Chrome tabs
   21:43:22 context screen captured: shot-00:00(...)
   21:43:27 ⚡ mic edge confirms the ring 5025 ms after the gesture
   ```

   One `⚡ ring up`, no `ring down` between them.

**Push-to-talk is the exception and stays beacon-only.** It is two held modifiers and nothing else,
so it fires on any right ⌘⌥ — and a false `didBegin` costs a screenshot and a ⌘C probe posted into
whatever he is working in. `onWisprMaybeStarting` carries a `confident` flag now; fn ⌃ Space is
confident, the modifier pair is not.

### Six seconds was not enough for the words either

The same evening, an 81-second dictation was lost: the capture window closed at six seconds and
Wispr's ⌘V arrived after it, so the relay never saw it. Wispr's round trip measured avg 2.6 s over
71 dictations, min 0.27, **max 22.8**. So `captureTimeout` is **30 s** and `settleTimeout` is
**20 s**, and they are deliberately different numbers: the capture is a flag nobody sees and can
afford to wait, where a ring standing for half a minute would stop meaning anything.

`⚡ ring down: routed to <session>` is the line that says the wrap worked — the bound path ends the
settle itself now, where the first build left it to time out at eight seconds *after* the words had
already been delivered.

### `copy_last_text` is written, and off

⌘⌃C (`55+59+8` in Wispr's own config) puts the last transcript on the pasteboard without a
microphone, and it was the fallback for a delivery the tap never saw. It is off by default from the
hour it was written, for two reasons: it hands back *the last text Wispr produced* — after a failed
sentence, the **previous** one, and delivering a five-minute-old paragraph as though he had just
said it is worse than losing the sentence — and measured once, the chord went out and
`NSPasteboard.changeCount` never moved. `WT_WISPR_COPY_FALLBACK=1` for whoever wants to work on it.

### The corpus does not die with the local model

`VoiceCorpus` needs a WAV, and the only one the relay wrote came from `stopLocalRecording`. The
halo's meter — a second `MicRecorder` open alongside Wispr's, there for `level` — deliberately
threw its session away. It writes a file now, and the label beside it is Wispr's own transcript:

```
21:37:24 corpus: 21-37-24-wispr434 — 844 KB, 27.0s (wispr-flow)
```

`captureLocal(engine:)` stamps it, the stem says `wispr` where it used to say `local`, and the
distinction matters: a `wispr-flow` label has been through Wispr's formatting pass — punctuation,
capitalisation, its custom dictionary — where a `whisper-local` one is raw recogniser output. An
absent field is a question a reader asks; a wrong one is an answer they believe.

### The local model is retired, not deleted

No gesture and no menu row starts it, and the weights are no longer loaded at launch — 1.5 GB
resident for a fallback nobody reaches. It stays selectable (`WT_SOURCE=whisper`) for three reasons
that are the same reason: the wrap rests on intercepting another app's ⌘V and the day that changes
there has to be something to fall back to; it is the only recogniser that works with no network;
and `evals/` scores the corpus against it, so a model that cannot be run is a baseline that cannot
be measured.

### Two apps are called Wispr Flow, and `open -a` picks the wrong one (2026-09-13)

An afternoon of "Wispr Flow will not stay running": `open -a "Wispr Flow"` returned 0, a pid
appeared for about 100 ms, and then nothing — no crash report in `DiagnosticReports`, nothing in
the unified log, `config.json` still parsing and still on Auto-detect. Nothing was crashing.

Wispr ships a **nested** Accessibility helper at `/Applications/Wispr Flow.app/Contents/Resources/
swift-helper-app-dist/Wispr Flow.app` — bundle id `com.electron.wispr-flow.accessibility-mac-app`,
executable also named `Wispr Flow`. LaunchServices resolves the *name* to it, and it quits itself
when it has no parent. The one-line proof:

```
osascript -e 'POSIX path of (path to application "Wispr Flow")'
→ /Applications/Wispr Flow.app/Contents/Resources/swift-helper-app-dist/Wispr Flow.app/
```

It poisons the *check* as well as the launch: `pgrep -x "Wispr Flow"` and `pgrep -f "Wispr
Flow.app"` both match the helper, so a preflight can report Wispr running when only the helper is.
`helpers/wispr_preflight.py` matches the anchored executable path
(`^/Applications/Wispr Flow.app/Contents/MacOS/Wispr Flow`), and the remedy line says
`open "/Applications/Wispr Flow.app"` — never `-a`.

It rhymes with *Never launch the installed app by its executable path*: both are macOS resolving a
name to something other than the bundle you meant, and both cost hours because the symptom is
silence rather than an error.

### Dismissing Wispr after `formatted` does not stop it pasting (2026-09-13)

The last wrap that needed neither a permission change nor an app change, and it is dead. Wispr
writes `formattedText` into its row at `status = formatted`, so the sentence is readable before
anyone has been handed it: read the row, post Wispr's own ⌃Escape (`53+59`), keep the words, let
nothing be inserted. Measured with `dismiss-before-paste`, five runs, a real TextEdit document front
and key throughout:

| dismiss delay | formatted → ⌘V | inserted into the victim | text still in the row |
|---|---|---|---|
| control | **57 ms** | yes | yes |
| 0 ms | — | **yes** | yes |
| 300 / 600 / 900 ms | — | **yes** | yes |

**The window is 57 ms, not a second.** The ≥1 s gaps that suggested this idea were the relay's own
`pasteGrace`, not Wispr's behaviour.

**And the chord does not stop it.** It is delivered — the tap logs `probe: synthetic key 53 … (Python)`
and `🗑️ ⌃Escape — Wispr Flow's dismiss, pressed by hand while the words were in flight` — and Wispr
inserts anyway, from 0 ms upward. By `formatted` it has committed; ⌃Escape discards a sentence still
in flight, not one already written. The delay column never mattered.

The readable half stands: `formattedText` survived every dismiss. **The row is where to read the
sentence; it is not where to stop it.**

`POST /test/cancel` cannot do this, which is worth writing down: `WisprFlowSource.cancel()` with the
microphone closed and a capture standing — the exact state at `formatted` — abandons the relay's own
capture and returns *without posting anything*; only `isRecording || speculative` reaches
`postWisprCancel`. The harness posts the chord itself, with Accessibility checked first.

### Auto-detect is not the system default input (2026-09-13)

The harness was built on one sentence from *The harness, and the one setting Victor has to change*:
`rankedAudioDevices` contains `{"deviceId": "default", "name": "Auto-detect (MacBook Pro)"}`, **so
with Auto-detect picked Wispr follows the system default input, which is scriptable**. That was a
reading of a config file, never a measurement. It is false.

Five runs, system default input pointed at `🎙️TO Zoom` by `POST /test/input`, the relay's own meter
logging `mic: recording through 🎙️TO Zoom — 48000Hz × 2ch` beside them. Wispr's own `micDevice`
column, every time:

```
12593  raw_transcript  ro.victorrentea.wispr-relay  Built-in mic (recommended)
12591  raw_transcript  ro.victorrentea.wispr-relay  Built-in mic (recommended)
12589  raw_transcript  ro.victorrentea.wispr-relay  Built-in mic (recommended)
```

Wispr resolves *Auto-detect* to the built-in microphone, not to whatever the system default is. It
never heard the WAV. What it recorded was the room, and the numbers say so — the `audio` blob in its
own row against the clip we played:

| | RMS | peak | frames over the speech floor |
|---|---|---|---|
| the fixture we play | 297.0 | 2839 | 11% |
| what Wispr recorded | 37–109 | 1120–3155 | 0–1% |

**Confirmed once more with the network up.** A DNS outage ran through the same hour and had Wispr's
remote recogniser returning nothing, so for a while the two explanations were entangled. The run
after it cleared settles it — `e2eLatency 1055 ms`, so the recogniser answered — and the numbers are
not attenuation of the same signal, they are a different signal:

| | RMS | peak | voiced |
|---|---|---|---|
| the clip as actually played (normalised) | 1713.7 | 16383 | 54% |
| what Wispr recorded, same run | **58.9** | **650** | **0%** |

29× down on a digital pass-through is not possible. That is a quiet room through the built-in
microphone. Six runs, six times `Built-in mic (recommended)`.

Two hours went into "Wispr is not completing transcriptions", and Wispr was completing them
correctly — of silence.

**The topology that came out of it (2026-09-13, later).** Not just the click: a new Loopback device
**`🎓 TO Wispr`** whose sources are the physical `MacBook Pro Microphone` *and* Pass-Thru, with
Wispr's microphone pinned to it permanently. Victor's daily dictation goes mic → device → Wispr
exactly as before, and the rig plays its WAVs into the same device. Nothing has to steer the system
default input any more, which removes the switch, the restore, and the whole class of bug where a
run leaves his Mac recording from a virtual cable. `--switch-input` keeps the old path for the
devices Wispr is not pinned to.

Two more things the same evening: the clip is **resampled to the device's rate** (16 kHz corpus,
48 kHz device — PortAudio is not obliged to raise a mismatch, and 3×-speed audio comes back as
confident nonsense rather than as an error), and the harness's **primary text source moved to
Wispr's own `History` row**. That is a departure from *do not read Wispr's database*, and a
deliberate one: the rule is about the **relay**, a live path where the pasteboard is the answer;
a harness wants the text regardless of where Wispr put it, and the sink can miss an insertion no
tap sees. The sink stays as a cross-check.

**The fix is the one `docs/teacher-loopback.md` wrote down in the first place**: *Wispr → Settings →
Microphone → the Loopback device*. The Auto-detect route was invented to avoid asking Victor for that
click, because the device id is a salted hash; the click is not avoidable. `wispr_preflight.py` now
requires Wispr's microphone to **be** the device the run plays into and says so in words, and every
run reports `micDevice` afterwards and fails on a mismatch — a preflight that reads a config file
cannot be the last word on what another process will do with it.

Two smaller things the same evening, both the harness fooling itself:

- **The chord lands in the sink.** `fn ⌃ Space` with the sink key arrives as `typed+keyDown+typed+
  keyDown — 4 chars`. A run where Wispr never opened its microphone reported the transcript `"tu"`.
  The sink is now cleared *after* the microphone edge, and one-character keystroke events never count.
- **A toggle chord left open records for ever.** A row of **495 seconds** with an empty `app` read at
  first like Victor dictating for eight minutes; it was this rig's own chord with nobody coming back
  for it. Every exit path now stands the dictation down, gated on the state so it can never take away
  one he started.

### The harness, and the one setting Victor has to change

`tools/wispr-test.sh <file.wav>` plays a WAV into a virtual input device, triggers a **real** Wispr
dictation through `POST /test/wispr-handsfree` (the app posts the chord — it has the Accessibility
grant, the script has none and needs none), waits for the relay to say what it did, and prints the
transcript with the ⚡ timings. It restores the system input on every path including Ctrl-C, and
raises the 🔒 hands-off locks for the run.

**It is blocked on one setting.** Wispr's microphone lives in `prefs.user.overrideAudioDeviceId` as
a Chromium `MediaDeviceInfo.deviceId` — a per-origin salted hash that cannot be computed from a
device name, in a file Wispr's own process rewrites. But `rankedAudioDevices` contains
`{"deviceId": "default", "name": "Auto-detect (MacBook Pro)"}`, and with *Auto-detect* picked Wispr
follows the **system default input**, which is scriptable. `POST /test/input {"name": …}` is the
scripting (`InputDevice.setSystemDefault`, because `SwitchAudioSource` is not installed on this
Mac and CoreAudio wants a device id). Until that one setting is changed the preflight says so in
words rather than playing a WAV into a device nobody is recording:

```
✗ Wispr microphone is pinned to a device (e671febe…).
  Victor: Wispr → Settings → Microphone → 'Auto-detect (MacBook Pro)'.
```

`--speaker` is the way round it in the meantime: play the clip out loud and let whatever microphone
Wispr is on hear it. Crude, correct, and the only mode that makes a noise.

## The forward click is the caret, and the arrow is the terminal (2026-09-12)

The evening the wrap shipped Victor tested it from the mouse and found the forward button
doing the wrong thing: *"apăsând butonul forward, click normal, el tot dictează legat de
fereastră, când ar fi trebuit să dicteze la cursor"*. The log agreed — every `🎙️ forward
button — Wispr Flow's hands-free toggle` was followed by `⚡ ring down: routed to
walkie-talkie`.

**Why.** With Replace Wispr unticked the click did not open a dictation of its own; it posted
Wispr's chord raw and let the tap notice it (`onWisprMaybeStarting` → `gestureSeen`). A
dictation the relay did not start has no `pasteMode`, so at the microphone's close
`latchedAtCaret` read the state — bound → the terminal. That was correct for a sentence *Victor*
started with Wispr's own chord, and wrong for the one gesture whose whole meaning is *at the
caret*.

**The vocabulary, restated by Victor in one message and now the rule:**

> butonul forward pornește dictare la caret (indiferent dacă e legat ceva) · forward+right
> move: dictare legată (dacă e legat ceva) · forward+left move: cancel dictare (la caret sau
> legată) · forward+up move: dictare în terminal nou · toate indiferent că Wispr sau model
> local e selectat.

So `VK_F7` goes through `onPasteToggle` → `startDictation(paste: true)` in every mode, and the
source does the starting: `WisprFlowSource.start()` posts the same chord it always did, with
`pasteMode` already set — the chip says `at caret`, no context shot, no ⌘C probe, and the ⌘V it
catches is put through `pasteText` where the caret is. The local model reaches the same line
through its own `start()`. `VK_F10` (🔼 →) is unchanged and is the bound dictation; `VK_F11` was
already `cancelDictationInFlight`, which reaches `source.cancel()` in either mode and either
destination.

Two things went with it. **The five-second bind grace** in `onPasteToggle` — the click made
just after a bind went to the terminal — is gone from that path: *indiferent dacă e legat
ceva* leaves no room for a click that sometimes means the other destination. And
`dictationBegan` tests `pasteMode` before `isBound`: a caret dictation with a terminal bound
would otherwise have taken the picture and posted the ⌘C into the field he is about to
dictate into. **🔽 → (`VK_F5`) posts the raw chord in both modes now**, because it is the one
gesture left that hands the sentence to Wispr and lets the relay route it by state; it had
been gated on Replace Wispr only because the forward click already did that with the tick off.

### The ring goes down when he dismisses in Wispr (2026-09-12)

*"După ce Wispr Flow termină (ok sau cancelled), tooltipul dispare relativ repede (corect),
dar fulgerele rămân pe ecran încă multe secunde în plus (greșit)."* The log had the shape:
`wispr flow closed the microphone` at 21:55:53, then nothing, then `⚡ ring down: timed out
waiting for the text — 20358 ms`. The chip goes at the close; the ring waits for the words
(`settleTimeout`, 20 s), and a sentence Wispr discards sends none.

The halo's own collapse is 0.5 s (`CaretHalo.collapse`) — not the animation. Two probes were
run before touching anything: `CGWindowListCopyWindowInfo` on Wispr's windows (its pill lives
in a fixed 512×586 `Status` window at layer 1000 whose frame never moves through a dictation —
no signal) and the Accessibility tree of that window (readable, `AXWebArea` under it; kept as
the next thing to try for the *Wispr silently produced nothing* case).

What ships is the half that has a keystroke behind it: **Wispr's dismiss is ⌃Escape (`53+59`)
and the tap sees him type it.** `onWisprMaybeCancelling` → `WisprFlowSource.dismissSeen()`:
during a speculative opening it ends the guess outright; with the microphone open it sets
`cancelling` so the closing edge reports `.cancelled` instead of arming a capture; with the
words in flight it closes the capture and ends the settle. Watched, never taken, and this app's
own `postWisprCancel` is stamped `backButtonStamp` and not reported. The case that still waits
the full 20 s is Wispr failing on its own — no ⌘V, no ⌃Escape — and the AX tree is where the
answer to that will come from.

### The session row says the terminal's title (2026-09-12)

*"Când dictez la o sesiune legată de un terminal, aș vrea să văd pe rândul doi, unde apare
sesiunea țintă, numele terminalului către care se duce. Numele folderului e un pic vag."*

`Target.title` had been read since the `custom title` work and refreshed on the 10 s poll, and
never shown: the chip's `identity` returned `boundFolder ?? boundLabel`. Two sessions in one
repo share `walkie-talkie@master` to the letter; the title Claude Code keeps rewriting —
`✳ walkie-talkie — Walkie talkie terminal naming` — is the one string on the machine that
tells them apart, and it already carries the folder in front of the summary. So `setBound`
takes a `title:`, `identity` prefers it (cut from the head at 44, `fitHead`, because a title
puts its subject first), and the folder row stands where there is no terminal to ask. The
menu bar keeps the folder; the *Rebind to…* list already shows every title.

### The envelope names no recogniser (2026-09-12)

`dictatedHint` said *transcribed by a local Whisper*. Since Wispr Flow became the source the
same envelope wraps its sentences too — *"elimină bucata aceea din text pentru că acum poate
să fie și Wispr Flow"* — so it says *transcribed automatically*. The clause's job is that the
words were spoken and heard by a machine; which machine is a claim the reader would have had
to disbelieve half the time.

### The ring grows out of the pointer (2026-09-12)

*"Haloul de fulgere să înceapă mărindu-se din cursor, unde apare mic. Se mărește la începutul
dictării, după ce apare bula galbenă, dacă este dictare legată. Să facă poză, apare bula aceea
care arată că s-a luat poziția mouse-ului și apoi face zoom out."*

The collapse already said *the sentence went into the pointer* (half a second, smoothstep,
into a 2 % dot). The opening is that motion reversed, and only for the dictation that has a
reason to start at a point: a bound (or spawn) sentence takes a picture, and `CaptureFlash`
marks where the pointer was when it was taken. So `CaretHalo.setActive(fromPointer:)` holds
the stage at `collapseEnd`, `grow()` is called beside `CaptureFlash.announce` and blooms it
over `expand` (0.5 s), and the two arrive in the order he described: bubble, then the ring
out of it. The order in `dictationBegan` is the other way round — the picture is taken a
line before the ring is raised — so `growOnShow` keeps the call until `show` runs; and a
bubble that never comes (no destination, a refused screen) is covered by `growGrace`, 1.5 s,
after which the ring grows on its own rather than standing as a four-point dot for a whole
sentence. A caret dictation comes up whole, as before — nothing marks the pointer there —
and `grow()` on a ring not held small is a no-op, which is what keeps a second bloom from
ever happening over a full-size ring.

### Only the installed bundle is a login item (2026-09-12)

*"Apare întruna acest mesaj «Login Item Added», la fiecare reinstall. E chiar necesar să-l
văd?"* — the banner said **WalkieTalkie**, no space, which is the debug executable's name and
not the app's. `sfltool dumpbtm` had **32** login items called `WalkieTalkie`, every one
pointing at `.build/arm64-apple-macosx/debug/WalkieTalkie`, beside the one real `Walkie
Talkie` at `/Applications`. Every `RELAY_SHOOT` run (the states page) and every `WT_SHOOT_*`
run went through `startAtLogin()`, and the debug binary is ad-hoc signed with a cdhash that
changes on every build, so `SMAppService.mainApp.status` answered `.notRegistered` each time
and the app dutifully registered a new item — which is what the banner reports. The installed
app, signed with the stable local identity, has said `already a login item` at every launch
since 2026-08-29 and never triggered it.

`startAtLogin()` now returns unless `Bundle.main.bundleURL` ends in `.app`. The 32 stray rows
cannot be removed from here — `SMAppService` unregisters only the running app, and `sfltool
resetbtm` resets *every* login item on the Mac and makes each re-ask for approval — so they go
by hand: System Settings → General → Login Items & Extensions, the `WalkieTalkie` rows (not
`Walkie Talkie`).

## Wispr's own row says when it is done (2026-09-12)

*"But how do you know in that case when Wispr Flow finished dictating?"* — I did not. The relay
had three signals about Wispr, all indirect: the microphone's closing edge, a synthetic ⌘V from
Wispr's pid, and the pasteboard's `changeCount`. Twice that evening (22:07, 22:32) a sentence was
inserted into Terminal with **none of the last two** — no synthetic keystroke from any process
(the probe logs every one during the capture) and no pasteboard change — and the relay waited its
full `settleTimeout` with the lightning on screen, then declared *the source returned nothing*.
An Accessibility insertion, as far as anything outside Wispr can tell; the same Terminal took a
⌘V two minutes earlier.

Victor: *"Let's run a bunch of experiments for you to figure out how you can detect when Wispr
Flow finishes the transcription, including looking into its own files on disk (or perhaps where
else stuff gets saved in the database)."* Four observers ran side by side through his dictations:

- **`CGWindowList`** — the pill lives in a fixed 512×586 `Status` window at layer 1000 whose
  frame never moves. Dead.
- **The Accessibility tree** of that window — readable (`AXWebArea`), and it does not change
  through a dictation. Dead.
- **The unified log** (`log stream --process "Wispr Flow"`) — silent. **`nettop`** — nothing
  usable. `config.json` has no insertion-method setting to pin Wispr to ⌘V. Dead.
- **`flow.sqlite`, table `History`** — one row per dictation, created at the gesture with
  `status = ''`, filled at the end: `formatted` (+ `pastedText`, the exact text inserted, `app`,
  `e2eLatency`), `dismissed`, `empty`, `no_audio`, `error`. The 22:32 row was `formatted` **711 ms**
  after the microphone closed, 168 chars into Terminal — while the relay sat for 20 s. Over 589
  dictations in 30 days: e2e p50 2.2 s, p90 3.5 s, p99 7.1 s, max 13.7 s. The query costs 6 ms
  on the 3.5 GB file, WAL mode, a reader never blocks the writer.

**What was built** (Victor: *"ok. build"*): `WisprHistory` — a read-only handle, one query,
`mode=ro`. `beginCapture` takes the newest row only if its `startedAt` is this dictation's (a
chord Wispr ignored leaves the previous *finished* row on top, and reading that as "done" would
end every settle on the first tick), then polls it every 150 ms. `formatted` gives the ⌘V one
second (`pasteGrace`) — the ordinary paths deliver and close the capture underneath the timer —
and only then delivers `pastedText` as a new `DictationDelivery.insertedElsewhere`: at the caret
that was the destination and the sentence is already there; at a terminal the router sends it on
and logs that the copy at the focus is a stray it cannot take back. `dismissed` ends as a
cancel, `empty` / `no_audio` as *No words detected*. `settleTimeout` drops from 20 s to 8 s (the
p99), now only the net behind the row.

**The rule.** *Never Wispr's database as a recogniser or fallback* stands for what it was about —
nothing here transcribes, and the pasteboard path is untouched while a ⌘V is still possible.
What changed, by Victor's decision, is that one file of Wispr's is opened read-only for the one
question nothing else on the machine can answer.


## The shots clause becomes a list, and the folder becomes $WALKIE_SHOTS (2026-09-13)

What shipped until today was one sentence:

```
[the shots I took, in /Users/victorrentea/Library/Caches/ro.victorrentea.wispr-relay/shots/2026-09-12-22-43-03/, oldest first, each named by what was in front of me: shot-00:05(mouse-at-1681x591px)-small.jpg = Terminal — ✳ victor-effects — Victor Effect menu shortcuts layout. Each is at most 800px wide; drop the -small for the full-resolution original.]
```

Victor rewrote it by hand and asked for exactly this shape:

```
screenshots during dictation are in: $WALKIE_SHOTS/2026-09-12-22-43-03/ oldest first:
- shot-00:05(mouse-at-1681x591px)-small.jpg in 'Terminal — ✳ victor-effects — Victor Effect menu shortcuts layout'
Each is ≤800px wide; drop the -small for the full-resolution original.
```

Four changes, each with its own reason:

- **A `- ` list instead of `; `-joined prose.** Five frames joined with semicolons is a
  paragraph an agent has to parse back into a list, through window titles that carry their own
  punctuation. A line per frame says where one name ends and the next begins at a glance — and
  Victor reads these himself, in a field in front of him.
- **`in '…'` instead of `= …`.** An equals sign claims the two sides are the same thing; the
  left is a file and the right is the window it was taken in front of. The quotes also take
  over the delimiting job the brackets used to do: a title is arbitrary text, and something has
  to say where it ends.
- **`$WALKIE_SHOTS` instead of the Caches path.** The 53 characters before the session stamp
  are identical in every envelope this app has ever sent, and the stamp — the only part that
  differs per run — was being read at the end of them. This is **not** a token argument
  (*Three things that sound like improvements and are not* settled that: the addressing is a
  rounding error beside the pixels); it is a legibility one. `AppDelegate.shotsRootAbbreviated`
  rewrites the prefix and falls back to the literal path for anything outside `Outbox.cacheRoot`.
- **`≤800px` instead of `at most 800px`.** Same fact, four words shorter, and still interpolated
  from `ScreenCapture.handoverWidth` — the one-place rule stands.

**The variable has to be real, and it lives outside this repo.** `~/.zshrc` exports
`WALKIE_SHOTS="$HOME/Library/Caches/ro.victorrentea.wispr-relay/shots"`. Nothing in the app can
set it: the envelope is pasted into a terminal that was already running when the relay bound to
it, so its environment is the shell's, not the app's. A checkout on a machine without that line
ships a path the agent cannot open — which is the one thing worth knowing before anyone
"simplifies" the variable back to an absolute path.

The context frame's own clause keeps its brackets and its wording; only the folder in it is
abbreviated the same way. `evals/variants.py` still renders the pre-2026-09-13 shape on purpose:
its fixtures are real files in a temp directory, where `$WALKIE_SHOTS` would resolve to nothing.

## The loopback closes: gestures, state, a sink and a delivery field (2026-09-13)

Two dictations went wrong on 2026-09-13 and neither could be reproduced at a desk, which is
the fact this section is really about.

The first was 2.5 seconds of talking into Word. `WisprWatch` reads one CoreAudio boolean about
another process's input and it is 0–6 s late; worse, it publishes an edge only when the value
it re-reads *differs* from the last one, so a dictation shorter than its own lag produces no
open edge and no close edge at all. Everything the wrap hangs off `didStopListening` —
`beginCapture`, the swallow window, the `History` poll, the settle — is armed from that close.
None of it ran. Wispr pasted straight into Word with its own ⌘V, the relay never saw a thing,
and the ring stood for twelve seconds until `speculativeGrace` gave up and wrote *Wispr ignored
the chord* about a sentence that had in fact been delivered.

The second was a 🔼↑ spawn. The first click stopped the microphone; the close edge came three
seconds late, set `listening = false` and entered the settle; a second 🔼 click landed inside
that settle, and `onPasteToggle` asks only about `listening`, so it **started a second
dictation**. `gestureSeen` then called `endCapture(quiet: true)` and disarmed the first
sentence's swallow window. Wispr's ⌘V arrived a second later and landed in the Terminal that
happened to be in front. The chip spent twelve seconds on a dictation that did not exist.

The fixes are not here. What is here is the apparatus that makes both of those reproducible
without a hand on the mouse and assertable without a pair of eyes, because the common half of
the two failures is that **nothing outside the process could see what had gone wrong**. Four
pieces.

**`POST /test/gesture {"name": …}`.** Every side-button gesture reaches this app as a keystroke
and nothing else — Options+ diverts the button inside the mouse and emits ⌃⌥⌘ plus a function
key (*The side buttons speak in function keys*). So the honest way to fake one is to post that
chord, and `HotkeyTap.postGesture` does exactly that: `keyDown` + `keyUp` at `.cghidEventTap`,
flags `control|alternate|command`, stamped with `backButtonStamp`. It enters the tap's
`useLogiGestures && ctrl && opt && cmd` branch by the same door a real gesture does, and every
guard on the way runs as it would for his hand.

Three things about it are worth writing down. **The app's own tap sees the post**, which is what
the whole route rests on: the tap is created at `.cgSessionEventTap` and the post is at
`.cghidEventTap`, one level below it, so the event climbs through the session tap on its way to
the front app — the same property `postWisprHandsFree` has relied on since 2026-09-12.
Measured, not assumed: with a dictation open, `POST /test/gesture {"name":"forward-left"}` put
`🖱️ POST /test/gesture forward-left — posting ⌃⌥⌘F11` in the log and
`🗑️ dictation cancelled via ⬅️ forward button flicked left` immediately under it — byte for
byte the line a real 🔼← writes. **The stamp does not hide it**: the gesture branch never looks
at `backButtonStamp`; the two branches that do are the injection swallow and the probe, which
is precisely where this app's own keystrokes must not be counted as another app's delivery, so
stamping is strictly quieter and changes nothing about what fires. And **it is an instance
method, not a static one** beside its siblings, on purpose: `VK_F3…VK_F12` are instance
constants of `HotkeyTap` and a static poster cannot see them. A second table of the same ten
keycodes is exactly the drift *The numbers are duplicated in two places and must not drift*
warns about, so the poster reaches for the originals instead — the ten names map onto the same
`let`s the switch cases read.

One sub-case is not fakeable and says so in the route table: ⌃⌥⌘F7 with the left button
genuinely held is the **bind** chord, and `leftIsHeld` asks the window server whether a physical
button is down. Nothing posted can make that true, so `forward-click` from the loopback is
always the caret dictation.

**`GET /test/state`.** One read, everything an assertion needs, and it changes nothing. The two
flags that would have named both failures on sight are in it: `capturing`, which was false
through the whole Word dictation while `listening` was true, and `settling`, which was true when
the second click arrived. Beside them, `speculative`, `isRecording` (the source's microphone,
which is not `listening`), `ringUp`, the chip's rows as strings, the latched destination
(`pasteMode` / `atCaret` / `spawnPending` / `awaitingBind` / `bound`), `historyRow`, `source`,
`wrapWispr`, `sinkOpen`, `lastRingDown` and `lastDelivery`. Timestamps are ISO-8601 **with
milliseconds** — the outbox line's own `ts` stays at second resolution, because it is documented
by name in the `relay` skill, and because a second cannot order a settle against the click that
landed inside it.

Almost none of this is new state. What the route cost is `private(set)` on three flags
(`WisprFlowSource.capturing`, `WisprFlowSource.historyRow`, `CaretHalo.live`) and one accessor
on the overlay: `RelayWindow.renderedRows`, filled at the end of `layoutContent` from the rows
that were just laid out rather than re-derived from the state that produced them — so a test
asserts what is on screen and not what was meant to be. Glyphs are not in it: a row is an image
view beside a label and the image is `Glyphs`' own rendering, so what survives is the words,
which is what an assertion is written against. At rest the chip is a lone 🎙️ and the array is
empty; open a dictation and it reads `["Listening...", "🤖 /", "×1"]`.

The read hops to the main thread and waits on a semaphore, for `onTestDictationStart`'s reason:
the chip and the halo are AppKit's and the listener queue is not, and that asymmetry took the
app down with a `SIGTRAP` the first time it was ignored. Two seconds, then it answers with an
error rather than hanging the listener.

**The `delivery` field.** `🗣️ wispr transcript via …` was the only place the answer lived, and a
log line is not something a test can assert on. So `DictationResult` grew a `via` — `wispr-cmdv`,
`wispr-history`, `pasteboard`, `local-whisper`, `test` — which is recorded and never branched on
(the router's question is still `delivery`), and `commit` writes
`{"via", "kind", "to", "at"}` into the outbox line beside the words.

The half that matters is the half that writes **no** outbox line: a caret paste, a sentence
Wispr had already inserted (`.alreadyInserted`), one it inserted somewhere else
(`.insertedElsewhere`), and a sentence held for a bind that has not landed. Those are recorded
too, into `lastDelivery`, and they are the four cases the file could never name — which is
exactly what happened on 09-13, when the words went into Word and into a Terminal that was
merely in front. `to` is resolved at the moment of delivery and never remembered, the same rule
the send flight runs on: `terminal:ttys002`, `caret`, `spawn:<folder>`, `held`. Verified on all
four paths; the terminal one also appears in `outbox.jsonl`.

**The sink — and it changed shape halfway through being written.** It started as a test
instrument: a plain 500×200 window titled *Walkie sink* with an instrumented `NSTextView` in it,
so `GET /test/sink` could answer *did anything leak into the front app, and by which route* with
a list instead of a guess. Then Victor said what it is actually for, and it stopped being a
throwaway window.

His design: **only Wispr's transcription engine.** Walkie gives Wispr its inputs and takes its
outputs synthetically, and Wispr never inserts into the real app at all. Under that the wrap
stops being *swallow the ⌘V and hope* — which is precisely the mechanism that failed twice today,
once because the swallow was never armed and once because a phantom sentence disarmed it — and
becomes *hold the focus, catch the insertion by whatever route it arrives, hand the focus back,
deliver the words ourselves*. The sink is that focus. So it is `WisprSink`, in its own file, with
an API rather than a POST handler: `open` / `close`, `becomeKey` / `restoreFocus`, `text`,
`events`, `clear`, and an `onArrival` callback.

**The scope of that wrap is already fenced, and the fence is the interesting part.** It applies
only to dictations *this app started* — its own chord, stamped `backButtonStamp` — and only while
the **Wrap Wispr Flow** tick is on. A dictation Victor starts with his own keyboard shortcut is
Wispr's and is left alone: taking the focus off him for one of those would be the app interfering
with a tool he is using directly, which is a different thing from wrapping a dictation it asked
for itself.

**What is not yet known is the timing, and that is what the loop is for.** Nobody knows whether
Wispr Flow picks the app it will insert into at the *chord* or at *insertion time*. The two give
opposite instructions — hold the key window from the moment the dictation opens, or take it only
at the stop gesture and give it back a moment later — and nothing in Wispr's config, its log or
its AX tree says which. So `becomeKey()` and `restoreFocus()` are separate calls and
`POST /test/sink {"key": true}` / `{"restore": true}` drive them separately, so the runner can
measure both hypotheses against a real dictation. **Nothing on a real path calls the sink today**,
and nothing may until that measurement exists.

The window shrank with the change of purpose: 40×20, borderless, four points inside the
bottom-left of the visible frame. Under the wrap it will be taking the keyboard during ordinary
dictations, and a 500×200 panel appearing over his work every time he talks is not a thing that
can ship. A borderless window can be any size at all — what it cannot be is *offscreen*, so it
sits just inside the corner rather than beyond it, and `canBecomeKey` has to be overridden to
true, which is the property that makes `RelayPanel` safe and the one this window must give up.
40×20 was tried and takes key focus; 1×1 was not risked for an instrument whose whole job is to
hold focus reliably. The level is `.normal`, not `.floating`, for the same reason it is not a
panel: the question it answers is what an ordinary key window would have received.

`becomeKey` remembers the frontmost application and — one `AXUIElementCopyAttributeValue` on the
system-wide element, no traversal — the focused element, and `restoreFocus` puts both back. Two
details that only showed up on the wire: it must **never record this app as the previous one**, or
the restore re-activates the sink it is letting go of and the window still has the keyboard
afterwards; and with nothing to go back to it calls `NSApp.deactivate` rather than `NSApp.hide`,
because hiding would take the chip and the halo down with it, and those are the two things that
must stay on screen through a dictation.

The route attribution survived the rewrite unchanged, because it is the whole point: `paste`
(⌘V), `ax:…` (an Accessibility write, named after whichever setter fired — `selectedText`,
`value`, or a legacy attribute), `typed` (an `insertText` that was not a paste), `keyDown` (raw).
A paste reaches `insertText` as well, so `paste(_:)` sets a flag first; without it every ⌘V would
be reported twice, once honestly and once as though Wispr had typed it. `onArrival` is debounced
150 ms after the last insertion, because two of the four routes arrive in pieces — an AX write
can be a selected-text replace followed by a value set — and a wrap that delivered on the first
fragment would deliver a third of the sentence.

One thing it needed that nothing else in this app has ever needed: **the app has no Edit menu**,
so a plain `NSTextView` would never receive ⌘V at all. `main.swift` installs the minimum a
`.regular` app owes its menu bar — About, Hide, Quit — and nothing in it carries `paste:`. The one
route the whole sink exists to catch would have arrived and done nothing, silently, which is the
exact failure shape being tested for. So the view answers `performKeyEquivalent` for ⌘V itself,
rather than the sink installing an Edit menu while it is up: the menu bar is Victor's, and a route
that works by changing the app's menus would be testing the menus.

**It is the one deliberate exception to *nothing in it ever calls `NSApp.activate`*.** That rule
exists because a dictation helper that steals focus takes the caret away from the work it is
meant to be typing into — and being the caret is precisely what this window has to do. The
exception is fenced rather than argued away: the sink remembers whose keyboard it took and gives
it back, nothing but a POST opens it today, and when it is wired in it will be for the app's own
dictations only. It is not bindable — `bindFrontmostTerminal` asks Terminal, tmux and the two IDE
bridges what is in front and this window belongs to none of them — and it cannot appear in
`docs/states/`, because `RelayWindow.snapshot` photographs `root` directly and never enumerates
the app's windows.

Measured end to end: with the sink as the key window and Replace Wispr on, `POST /test/dictation`
put `tiny sink check` in the view and
`{"route":"paste","chars":15,"text":"tiny sink check","at":"…Z"}` in the event list, and
`lastDelivery` read `{"via":"test","kind":"route","to":"caret"}`. `{"restore": true}` then gave
the keyboard back (`key` false) and `{"key": true}` took it again, naming `Terminal` as the app it
had come from. That is the 2026-09-13 caret failure, reproduced unattended and asserted on —
which is the whole point.


## Every selection and every pick says when, and a pick says what it said (2026-09-13)

The frames have said *when* since the day they were named: `shot-00:05(mouse-at-1681x591px)`
is five seconds into the sentence, and the clause under them is a `- ` list, one frame a line.
Nothing else in the envelope did. A highlight arrived as `[selected: …]` with no offset at all,
or as `[selected 0:31: …]` in a bracket of its own; a picked element arrived in a `·`-joined
sentence that quoted sixty characters of what the thing said. Victor asked for the same reading
on all three, in one sentence: the agent should know **when** in the dictation each selection and
each pick happened, relative to what he was saying — and, for a pick, **what the element said**.

So there are now three lists in the envelope and they are the same list:

```
text selected during dictation:
- 00:00 in 'IntelliJ IDEA — OrderService.java': "public Order placeOrder(Cart cart) {"
- 00:19 in 'Google Chrome — Stripe docs': "amount is in the smallest currency unit"
screenshots during dictation are in: $WALKIE_SHOTS/2026-09-13-19-13-09/ oldest first:
- shot-00:12(mouse-at-1681x591px)-small.jpg in 'Google Chrome — Stripe docs'
Each is ≤800px wide; drop the -small for the full-resolution original.
elements picked in Chrome during dictation, on 'https://shop.example/cart' (Cart — Shop), oldest first:
- 00:12 div#cart > span.price: "1.299,00 lei"
- 00:21 button.buy-button, moved from 120,340 to 500,205 (top-left, page coordinates): "Cumpără acum"
```

**The frozen selection is line one of its list, not a clause above it.** It is still the
subject and still first; what used to separate it from the extras — that it was there before he
started — is now said by its own `00:00` instead of by living in a different bracket. And the
one case the old shape could not express is exactly the case worth having: a dictation that
opens with nothing highlighted takes the first mid-sentence highlight into the frozen slot
(`fillsTheBlank`), and *that* one did not happen at zero. It happened eleven seconds in, while
he was already saying something, which is the whole reason an offset is worth printing.

**`in '…'` is the shots clause's own punctuation, doing the same job.** He highlights in one
window and talks about another all day; which window it was is the half a quoted string cannot
carry. The reading is `WindowContext.describe()`, the same one every frame gets — and it is
taken **when the highlight is filed**, never at delivery. The envelope is built seconds later,
behind the held panel, and a title read there names the window he ended up in front of. That is
the same rule the cursor position, the shot offset and the frame's own title already follow, and
it has been wrong in this app once for each of them.

One thing it cost, and it is the kind that does not show up until it does: `WindowContext` hops
to the main queue and *waits* there, and everything that publishes to the chip takes `stateLock`
**from** the main queue. Read under the lock — which is where it naturally wants to go, since the
decision *is this highlight novel* is made under the lock — the two are a deadlock with a
selection on one side of it. It is read before the lock is taken, and the cost is one
Accessibility call for a highlight that turns out to be a repeat.

**Two clocks became one calculation with two paddings.** `mm:ss` in the envelope, because the
envelope already has a clock in it — every frame it hands over is named `shot-00:05` — and a
highlight reading `0:05` beside a frame reading `00:05` is two readings an agent has to satisfy
itself are the same reading. `m:ss` on the chip, because the chip is a few characters wide beside
his cursor and a leading zero there is a column spent on nothing. The arithmetic is
`clock(_:pad:)`; `stamp` and `envelopeStamp` are the two paddings over it. The rule that the
panel's `pickLines` and the message's stamps cannot drift is unchanged — it just now means *the
numbers cannot drift*, which is what it was ever about.

**A pick quotes 2000 characters instead of 60, and says what it left behind.** `text` has been in
the payload since picks existed and was capped at 160 in the page and printed at 60 in the line —
enough to *recognise* a button by, which is all the clause ever did with it: `button.buy-button
(Cumpără acum)`. But what he ⌘⇧-clicks is as often an error box, a table row or a paragraph as it
is a button, and 160 characters of one of those is a sentence cut off before it says anything.
*"this button"* resolves to a selector; *"the error it showed me"* resolves to nothing unless the
words travel. So the cap is 2000, said in two places that must not drift (`TEXT_MAX` in
`inspect.js` slices, `ElementPick.textLimit` guards — the page is hostile input and the extension
is not the only thing that can POST to `/pick`), and the untruncated length rides beside it as
`textChars`, measured **before** the slice, so the line can end `… (truncated, 3600 chars)`
rather than simply stopping. A quotation that stops reads as the whole of what the element said,
and acting on the half of an error message that fitted is worse than knowing there is more to
fetch.

The move went *before* the quotation for the same reason: it is an instruction to carry out in
the source, and an instruction at the far end of a paragraph of page copy is one nobody reads.
The page's **title** joined its URL, and is factored into the heading only when the URL and the
title are *both* unanimous — two picks on one address with two titles is a page that changed
under him, and one of the two names would be wrong.

**Nothing renamed, nothing re-meant.** `selection` still carries the first highlight as a bare
string, `selections[].at` is still `m:ss`, `elements[].text` is still what the element said. What
arrived beside them is `selectionAt` / `selectionIn`, `selections[].seconds` / `.in`, and
`elements[].at` / `.textChars`. The offsets in the JSON are **numbers** and the ones in the line
are `m:ss`: the string is for reading, and anything comparing two picks would otherwise be
parsing a clock back. The `relay` skill documents these fields by name, and the standing rule in
that chain is that adding a key is free and renaming one is not.

**The selection was the one attachment no test could reach**, and that is why it had never been
asserted. A shot, a pick and the words themselves all have loopback routes; a highlight is read
off the screen with Accessibility or a ⌘C, so checking how the envelope renders one meant
genuinely selecting text in another app, by hand, mid-dictation, and then reading the outbox. So
`POST /test/selection {"text": …}` fakes the **reading** and nothing else: it enters at
`fileSelection`, the door the watcher and the shutter both come through, and the offset, the
window reading, the frozen-slot rule and the *already carried* skip all run as they do for his
hand.

`evals/test_envelope.py` is what it exists for — one fabricated dictation carrying two highlights
and two picks, driven through the loopback against the installed relay, asserting the shapes
above and the outbox keys under them. It asks the **microphone** (`isRecording`, `settling`,
`speculative`) whether Victor is talking rather than asking `listening`, because
`/test/dictation/start` sets `listening` and nothing on the fabricated path ever produces the
microphone edge that clears it — guarding on `listening` would mean one run of the file locking
out the next. It delivers to a tty nothing is listening on: the outbox line is written at
delivery, and delivery to a tty with no tab comes back `targetGone` without a keystroke reaching
any window, which is the only way to get a real envelope out of a relay that must not type into
anything. It puts his binding back, and it re-binds until the line appears, because with nothing
bound the sentence is *held* rather than dropped and no line is written at all.

The Chrome extension has to be **reloaded by hand** in `chrome://extensions` before any of the
pick half is live — `inspect.js` changed, and an unpacked extension serves the JS it was loaded
with until it is told otherwise. Until then a pick still arrives; it arrives with 160 characters
of text and no `textChars`, which the envelope renders as a quotation that stops.

## Version row and ⌘Q (2026-09-13)

Victor: *"in victor-effects, macos addon and walkie talkie, separate a disabled row Version:
sep 7, hh:mm above the Quit menu entry, mapped to cmd-q, for cleanliness"*.

The three menu bar apps now end the same way: a separator, a disabled `Version: <build>` row,
then `Quit ⌘Q`. Here that replaced the clickable About row (`Victor's Walkie Talkie (<build>)`,
which opened `AboutPage` in the browser) — the page is still on the Dock tile's main menu, where
the app is actually frontmost. The stamp is still the executable's mtime (see *The menu bar
item*). The ⌘Q hint reverses the *no key equivalent* note under *Autosend*: it still only fires
while the menu is open, but the hint is what makes the row read as Quit, and consistency across
the three menus won over the pedantry.

## Three witnesses instead of one, and the ring stops waiting for CoreAudio (2026-09-13, evening)

Five end-to-end runs through the Loopback device that evening transcribed perfectly, and
`WisprWatch` saw **no microphone edge in any of them**. That is the sentence this whole
section is about. The five runs were not failures — Wispr heard the WAV, the row said
`formatted`, the words came back in 0.6–1.1 s — and the app's one model of *is Wispr
listening* was blind through every one of them, because Wispr is pinned to `🎓 TO Wispr`
whose physical source keeps the stream warm, so `kAudioProcessPropertyIsRunningInput`
never changes and the notification only fires on a change.

Both of Victor's failed dictations earlier that day are the same fact from the other end:

- **18:18:04, into Word.** 2.5 s of talking, no open edge and no close edge — the dictation
  was shorter than the watcher's own lag. `beginCapture` is armed from the close, so the
  swallow window, the `History` poll and the settle never existed; Wispr pasted into Word
  with its own ⌘V and the relay never saw a thing. The ring stood for twelve seconds and
  then `speculativeGrace` wrote *Wispr ignored the chord* about a sentence that had been
  delivered.
- **18:18:36, the spawn.** The close edge came three seconds late, a second 🔼 click landed
  inside the settle, `onPasteToggle` asked only about `listening` and started a phantom
  dictation, whose `gestureSeen` called `endCapture(quiet:)` and disarmed the **first**
  sentence's swallow. Wispr's ⌘V landed in whatever Terminal was in front.

The common half is not the timing. It is that **one signal was the only witness**, and it is
a signal about another process's audio device — the one thing in this arrangement nobody
controls.

### `WisprState` — the phase, and what each signal is allowed to prove

`WisprState` is a five-phase machine (`idle` · `warming` · `listening` ·
`transcribing(status)` · `done(status)`) with four inputs, each with its own latency and none
of them authoritative alone:

| input | what it proves | measured |
|---|---|---|
| the chord this app posts | a dictation was **asked for** | it is the clock |
| a **100 ms poll** of `kAudioProcessPropertyIsRunningInput` | a microphone **is** open | one tick |
| `WisprWatch`'s CoreAudio notification | the same fact, pushed | **0–6 s, sometimes never** |
| the `History` row at 150 ms | Wispr **has the sentence** | the row is created at the gesture |

The poll and the notification are deliberately two inputs and not one. Collapsing them into
the faster one would throw away the number the next feature needs — Victor's replay buffer
has to know when Wispr is *ready to be spoken to*, and the gap between the pull and the push
is the closest thing to that measurement there is. So every `listening` transition logs both:
`wispr state: warming → listening — poll saw the microphone, poll saw it 412 ms after the
chord, notification never`.

The machine owns nothing — no timers, no CoreAudio, no SQLite, no AppKit — which is what
makes `POST /test/wispr-state/simulate` possible: a fresh machine with a fake clock, driven
by a scripted sequence, answering with its transitions. That is the unit test. It is a route
rather than an XCTest target because the package is one `executableTarget` with a
`main.swift`, and splitting the app into a library for one test file is a worse trade than a
route that runs in under a millisecond and touches nothing in the running relay.

The phase is surfaced **source-agnostically**, as `DictationPhase` on `DictationSource`.
`isRecording` only ever answered the middle of the five, so the warm-up a cold Electron costs
and the seconds Wispr spends formatting both reached the relay as the same undivided *not
recording* — and a settle written against that cannot tell *the words are late* from *the
words are lost*. `LocalWhisperSource` answers the same five with an empty status.

### The ring is *microphone open*, and the chip carries the wait

Victor's direction, the same evening: **the ⚡ ring is the relay's own knowledge that a
microphone is open**; the tooltip says where the words go. So:

- The ring goes **down on the relay's own stop** — the 🔼 click, ⌘⌃D, the second 🔼→, the end
  of a `/test` run — not on a CoreAudio edge. `WisprFlowSource.stop()` closes the listening
  phase itself and the edge only confirms and logs `⚡ the mic edge closed N ms after the
  relay had already stopped`, which is the number that made this necessary.
- The chip shows `Transcribing...` for the whole settle. That is the claim the ring used to
  make by standing, minus the lie that a microphone is open.
- `endSettling`'s line is no longer `⚡ ring down`; it is `✍️ the words landed`. The ring and
  the words were the same instant until today and the day they stopped being one is the day
  the log started lying about which. `RingDown` grew a sibling (`lastSettled`), because *why
  did the ring go* and *why did the wait end* are two questions with two different fixes.
- **`beginCapture` is armed at the start chord.** The swallow, the pasteboard watch and the
  row poll now cover the whole sentence; only the 30 s deadline starts at the close, because
  *how long may the words take* is counted from the last word. A missing edge costs nothing —
  the window is simply open, which is one flag.
- **`speculativeGrace` may only retract a ring for a chord that left no row.** Wispr creates
  the `History` row at the gesture, so the row's *absence* is the honest test for *Wispr
  ignored the chord*; a row that exists confirms the dictation exactly as the microphone used
  to, and the log says which — `Wispr never created a row within 12 s of the chord` against
  `Wispr's own row (the relay saw no microphone) confirms the ring`.
- The row poll now **adopts** the row rather than taking a snapshot at the close: it refuses
  the row that was on top when the capture was armed (unless that one was still open) and
  takes the first newer one whose `startedAt` is this dictation's.

### A click during the settle is a stop, or it is nothing

`onPasteToggle` asks about `listening || source.isRecording` first, then about
`settling || phase.isWaitingForWords` — and in the second case it does nothing at all and
says so. `startDictation`'s own guard grew `!settling` beside it. Behind both,
`retireCaptureIfSettled` replaces the unconditional `endCapture` in `gestureSeen`: a capture
whose row is **not terminal** belongs to a sentence still in flight and a new gesture does
not get to disarm it.

### `raw_transcript` and `processing` are progress, not silence

Both statuses were on the wire that evening and neither was in the switch, so a settle sat
out its full eight seconds on a sentence that was arriving. The vocabulary is now in one
place (`WisprState.intermediateStatuses` / `terminalStatuses`) and the settle's give-up asks
the source before it fires: while the phase is `transcribing` it re-arms, bounded by the
capture's own 30 s. Eight seconds is the right number for *nothing has come back*; it is the
wrong number for a row that says `processing`, and Wispr's tail runs to 22.8 s.

### The sink cross-check, explained — and a bug nobody was looking for

The runner's sink cross-check disagreed with the row in 5/5 runs, and the explanation is two
separate things.

**The sink was right.** With the capture armed at the *close*, Wispr's ⌘V routinely arrived
**before** the relay knew the microphone had shut — 22:30:24 against a close edge at 22:30:27
— so it was never swallowed, and it landed in the sink because the sink was the key window.
24 characters against the row's 23 (`Commit and push the fix` plus a trailing space). That is
a match, not a mismatch. What it also means is that **once the swallow is armed at the start
chord the sink can only ever see what leaks**, and a cross-check written as *sink text must
equal row text* will now fail on every correct run. The runner's assertion has to invert: an
armed, working wrap leaves the sink **empty**.

**The relay was wrong, and in a way nothing was watching for.** In three of those five runs
the transcript the relay delivered was 163 characters of a Word rental contract —
`Semnături, PROPRIETAR CHIRIAȘ …` — filed in `corpus.jsonl` at 22:19:46, 22:20:19 and
22:29:55 beside audio of Victor saying *"Commit and push the fix"*. Wispr writes the
transcript to the pasteboard, presses ⌘V, and **puts the previous clipboard back**. The
capture's `clipboardAt` baseline was taken at the microphone's close, which is *after*
Wispr's write, so the only pasteboard move the relay ever saw was the restore — and
`the pasteboard moved but no ⌘V was seen` delivered it as the sentence. (163 and not 166
because Swift counts `\r\n` as one `Character`; the corpus text has three of them.)

Two fixes, and the second is kept even though the first makes it redundant today. Arming at
the start chord puts the baseline before Wispr's write, so the first move seen is the
transcript. And `deliver` now refuses a pasteboard whose contents are **exactly what they
were before he started talking** — keeping the capture alive, because the row usually answers
a beat later — and reads the string at the instant the change is seen rather than 250 ms
afterwards, because the restore lands inside that gap.

### The row as the delivery, not the fallback

Victor rejected both candidate wraps the same evening. The **sink** works — measured 3/3, Wispr
picks its insertion target at the *end*, and a window that takes the keyboard 1–5 ms after the
stop chord receives the text — but it steals focus during every dictation and he may be
clicking or typing at that instant. **Revoking Wispr's Accessibility grant** works on paper and
breaks Wispr as a standalone tool, which it has to go on being.

What is built for whichever wrap wins is the path itself: `historyIsTheRoute`
(`WT_WISPR_HISTORY_ROUTE=1`, `POST /test/wispr {"historyRoute": true}`) makes `formatted`
deliver **immediately**, with no `pasteGrace` for a ⌘V that is not coming, taking the words
from `pastedText` **or `formattedText`** — a Wispr that inserted nothing fills the second
column and leaves the first empty — and always as `.route`, because nobody but the relay is
going to put that sentence anywhere. The ⌘V swallow stays armed behind it as the safety net.
`WisprHistory.Entry` grew `formattedText`, `micDevice` and `language` for it.

### The Scratchpad chord, and the one chord this app has to hold

The third candidate is Wispr's own **Scratchpad**, and it touches neither the focus nor the
permissions. Per Wispr's docs its *Open Scratchpad* shortcut carries three gestures: tap opens
and closes the window, **hold is push-to-talk into the Scratchpad**, double-tap is hands-free
into it while visible. Victor's is `"35+54+61": "open_scratchpad"` — P + right ⌘ + right ⌥.
The hypothesis to test is that a *held* chord dictates into Wispr's own note (filed in
`flow.sqlite`'s `Notes` / `NoteVersions`, with a `History` row whose `app` is
`com.electron.wispr-flow`) and inserts nothing anywhere.

`POST /test/wispr-scratchpad {"down": true}` presses the chord and **leaves it down**;
`{"up": true}` releases in reverse order; `{"tap": true}` is the press-and-release. The chord
is read from `prefs.user.shortcuts` at call time by *action name*, because the action is the
stable thing and a hard-coded chord posts a keystroke into whatever owns it after a rebind —
and it is about to be rebound: the fallback is **`79`, a single F18**, since a chord held for
the length of a sentence must not be one that hijacks every key he presses while he talks.
`WISPR_SCRATCHPAD_KEYS` overrides, and is the same variable `helpers/wispr_loopback.py` reads,
because the rig posts this chord too.

Two things about the hold are worth writing down. It is the only poster in `HotkeyTap` that
leaves the keyboard down between two calls, and a stuck right ⌘ is a Mac that has stopped
working — so it carries a **120 s dead-man's switch**, every release is idempotent, and the
chord that is actually down is remembered so a rebind mid-sentence cannot make the release
post a different one. And the modifiers go out with their **device-dependent bits**
(`NX_DEVICERCMDKEYMASK` / `NX_DEVICERALTKEYMASK`): Wispr's own push-to-talk reader
distinguishes the right ⌘ from the left, so a chord posted with a plain `.maskCommand` is a
different chord as far as it is concerned.

One thing the hold made necessary elsewhere: **this app's own hands-free chord is now stamped
out of its own tap**. `HotkeyTap`'s `fn ⌃ Space` branch gained the `backButtonStamp` check the
⌃Escape branch has always had, because the chord became a *toggle* on the far side — a
hands-free chord seen while a dictation is open is now read as Victor ending it — and without
the stamp `postWisprHandsFree` would hand the source its own start back as a stop, a
millisecond later.

## The numbers, and the Scratchpad is the one that works (2026-09-13, night)

Built, installed and verified on the running app. Four things were being asked, and the third
answered a question the design had only argued about.

**The state machine at rest and on a script.** `GET /test/state` answers `phase: "idle"` and a
`wispr` block; `POST /test/wispr-state/simulate` runs a scripted day in under a millisecond.
Six scenarios, all passing — the happy path with both lags, the 09-13 Word failure (**no
microphone signal at all**, the row as the only witness, `done(formatted)`), a chord Wispr
ignored (`done(timeout)`, no row), a late notification producing exactly **one** `listening`
transition, and all five terminal statuses plus an unknown one terminating.

The simulator earned its keep in its first minute by finding a bug in the thing it was written
to test. `chordAt > 0` was standing in for *a chord has been seen*, and a fake clock that starts
at zero makes those two different questions — the route came back with null lags and no offsets
on a script that had both. Wall-clock time is never zero, so the real path had hidden it
perfectly. That is the whole argument for an injectable clock in one bug.

**One real caret dictation, 22.5 s through `🎓 TO Wispr`.** The transcript came back
character-for-character, and the three witnesses answered in this order:

| witness | when |
|---|---|
| Wispr's `History` row appeared | **357 ms** after the chord |
| the 100 ms poll saw the microphone | **607 ms** |
| `WisprWatch`'s CoreAudio notification | **5590 ms** |

`wispr state: warming → listening — Wispr created a row, poll saw it never after the chord,
notification never` is the line at 357 ms, and it is the thesis: at the moment the dictation was
confirmed **neither microphone signal had spoken**. The notification arrived 9.2× later than the
poll and 15.7× later than the row. Under yesterday's code that dictation had one witness and it
was the slowest of the three.

The rest of the run, in order: the stop chord closed the listening phase itself
(`🎙️ the microphone is closed — POST /test/wispr-handsfree (22521 ms of speech)`), `⚡ ring down`
followed immediately, the row went to `processing` and the settle waited on it, Wispr's ⌘V
arrived 790 ms after the close and was **taken** — armed since the start chord — and
`✍️ the words landed: pasting at the caret` closed it at 792 ms. `lastRingDown` and `lastSettled`
name the two events separately, 793 ms apart.

**A forward click inside the settle does nothing, and says so.** With `settling` true,
`ringUp` **false** and the chip reading `["Transcribing...", "bind to send"]`,
`POST /test/gesture forward-click` put `🔼 forward click while the words are still in flight —
nothing to start, nothing to stop` in the log and left `listening` false. That is 2026-09-13's
second failure, posted from a script, refusing to happen.

Two more numbers off the same run. The settle's extension works —
`the settle waits: Wispr Flow is still working — 8 s in` and `— 17 s in` on a row that never
answered, then `done(timeout)` at 30 s with `Wispr never created a row`, which is the *other*
message and the right one. And Wispr's Scratchpad toggles on a **250 ms** press-and-release but
not on a 60 ms one, so `{"tap": true}` is reported as a tap rather than as a hold and a caller
that wants the window toggled times its own.

### `WisprNotes`, and the `History` row is not the witness there

The runner's experiment settled the wrap. F18 held 20 s: the text landed in Wispr's own `Notes`
(a **new note per dictation**, with a `NoteVersions` row beside it, `source = initial`), the
victim TextEdit document was untouched, **focus never moved**, **no ⌘V was posted**, the
pasteboard was written and then restored by Wispr, and the round trip was **432 ms**. The
Scratchpad window opened in the background. Nothing was inserted anywhere, which is the whole
thing every previous candidate was trying to buy with either a stolen focus or a revoked
permission.

`WisprNotes` is the reading half — `Notes` joined to its newest `NoteVersions` row, read-only,
`via: "wispr-notes"`, wired to no gesture. Three things it had to get right:

- **The `History` row cannot be the witness here.** Measured in the same run: on a Scratchpad
  dictation `History.app` names the **front app**, not the destination — it said TextEdit for a
  sentence that went into Wispr's note. `app` answers *what was in front*, which for every other
  kind of dictation is accidentally the same thing as *where the words went*, and here is not.
- **A modified note counts as much as a new one.** The run measured a new note per dictation, and
  the Scratchpad is a *notepad*: nothing promises it will not append to an existing one, and a
  reader watching only for new ids would go silent for ever the day it starts. The test is
  `max(createdAt, modifiedAt) >= since`; the delivery is the newest `NoteVersions` **content**
  rather than the accumulated note, or a dictation appended to yesterday's note would deliver
  yesterday's note too.
- **One handle, not two.** `WisprFlowDB` now holds the read-only connection both readers share —
  `mode=ro` in the URI on top of the flag, 50 ms busy timeout, dropped on any error. Opening a
  second connection against a 3.5 GB WAL file another process is writing is not a thing worth
  doing twice for the sake of file locality.

Verified against the runner's own dictation: `GET /test/wispr-notes` answers note
`3e088dcb-…`, 24 characters, `"Commit and push the fix "`, version `initial`.

## The wrap is Wispr's own Scratchpad (2026-09-13, late)

Four candidates were built or measured in one evening and three of them work. The one that
shipped is the only one that costs Victor nothing, and the argument is worth keeping because
"it works" turned out to be the least interesting property of the other three.

| candidate | does it work | why not |
|---|---|---|
| swallow the ⌘V | yes, most of the time | it depends on a keystroke another process may or may not post, inside a window this app may or may not have armed — both 09-13 failures |
| the **sink** (take the key window at the stop) | **yes, 3/3** | it takes the focus off a man who may be clicking or typing |
| **revoke Wispr's Accessibility grant** | yes | Wispr stops working as a standalone tool |
| **hold *Open Scratchpad*** | **yes, 3/3** | — |

The sink's measurement is the one that made the decision easy, because it settled a question
that had been open all day: **Wispr picks the app it will insert into at the end, not at the
chord.** Taking the keyboard 1–5 ms after the stop chord was enough, three times out of three,
and the `History` row's `app` column named the relay although TextEdit had been in front for the
whole dictation. So the sink needs the focus for a moment rather than for a sentence — and
Victor still said no, and was right to: a dictation helper whose ordinary behaviour is to
interrupt him is one he cannot leave running all day, and "only for a moment" is not a promise
that survives a busy Electron app. It stays as the emergency path and as the test instrument.

Revoking the Accessibility grant was rejected for a shape of reason worth naming separately: it
does not break the relay, it breaks **Wispr**. An app this one has quietly disarmed is not a tool
he still has.

And one thing that is not a candidate at all, measured the same evening: the window between
Wispr's row saying `formatted` and its ⌘V is **57 ms**, and a ⌃Escape posted after `formatted`
does not stop the paste. There is no *cancel the insertion*. There is only *do not ask for one*.

### The Scratchpad, and the precondition that is the whole feature

Wispr's *Open Scratchpad* shortcut carries three gestures on one binding, and the middle one is
the wrap: **hold it and Wispr dictates into its own note.** Measured — F18 held 20 s: a new
`Notes` row with its `NoteVersions` row, the victim TextEdit document untouched, **focus never
moved**, **no ⌘V posted**, the pasteboard written and restored by Wispr, e2e **432 ms**, and the
Scratchpad window opening in the background afterwards.

That last clause is not a footnote. Four runs established the precondition:

- Window **closed** at the start → a note is written, 3/3.
- Window **open** at the start → Wispr transcribes perfectly (`History` says `formatted`) and
  writes **no note at all**. The sentence is lost, and closing the window afterwards does not
  commit it.

And Wispr opens that window at the end of *every* dictation. So **the thing that breaks a
sentence is the previous sentence**, the failure arrives one dictation after its cause, and
nothing at the moment of the mistake looks wrong. That is the shape of bug this journal has spent
two days on, and it is designed against rather than hoped about: the window is checked **twice**,
once before the hold (`holdScratchpad`) and once after the capture (`closeScratchpadAfterwards`,
called from `endCapture` so it runs on every way out — delivered, dismissed, empty, timed out).
Both close by posting a ~250 ms press and then **polling the window list until it is gone**; a
60 ms press does nothing at all, because Wispr is telling a tap from a hold by duration.

A window that will not close stands the mode down to `sink`, loudly, and the next `start()` that
finds it closed puts it back. The one failure this mode must never have quietly is holding a
chord that writes nothing.

### The three modes, and the two flags that are not the same flag

`WrapMode` is `scratchpad` (default) · `sink` (emergency) · `off` (the tick down), resolved from
the tick, `WT_WRAP_MODE`, `POST /test/wrap-mode`, whether Wispr actually has an `open_scratchpad`
shortcut, and whether the window last refused to close. `/engine` and `GET /test/state` answer
`wrapMode` **and `wrapWhy`**, because a wrap that silently fell back to the emergency path is
precisely what nobody notices.

Two flags are latched at the gesture and they answer different questions. `startedMode` says
**how the chord was posted**, so it says what `stop()` has to undo: a dictation opened by holding
a key is ended by releasing *that* key, whatever the menu says by then. `intercepting` says
**whether the relay delivers these words**. They come apart on `POST /test/wispr-handsfree`,
which posts Wispr's own chord — nothing held, no sink to take — while the wrap is on and the ⌘V
is still the relay's to swallow, which is the behaviour the loop is written against. Folding them
into one flag broke that route the first time it was tried.

### A dictation he starts is his

Victor's line, and it is the fence round the whole wrap: a dictation *he* opens — his own
keyboard chord, or 🔽→ which posts Wispr's chord raw — is **Wispr's**. The relay draws the ring
for it, because the ring means *a microphone is open* and that is true, and does nothing else: no
swallow, no pasteboard watch, no Scratchpad, nothing routed. It ends on Wispr's own row with
`.silent("")`, which is *nothing worth a banner*. `relayStarted` is that distinction and `deliver`
carries the guard as well as the callers, because the cost of one call site ever missing it is a
sentence he spoke into another app arriving in an agent's terminal.

Every path out of a Scratchpad dictation releases the chord: `closeListening` as a belt, the
`speculativeGrace` drop separately because it is the one exit that does not go through it, and
`HotkeyTap`'s 120 s dead-man's switch behind both. A stuck right ⌘ is a Mac that has stopped
working, and the reason F18 is the binding is that a chord held for a whole sentence must not be
one that hijacks every key he presses while he talks.

The window Wispr leaves open is his window in his tool, so the menu gained one row — **Close
Wispr Scratchpad** — rather than the relay deciding to keep shutting it. Whether that should be
automatic beyond the wrap's own cycle is Victor's to say.

## Five runs to make the Scratchpad wrap real (2026-09-13, 23:20–23:31)

The wrap was written against a measurement taken with no event tap armed, and every one of the
four things that reading got wrong cost a run to find. The fifth run is the product path working
end to end; this is what the four before it were.

**Run 1, 23:20 — the chord went out as `⌃⌥⌘F18`.** The hold was logged, 5.2 s, and Wispr ran an
ordinary dictation and pasted. `postScratchpad` posted **immediately**, and the gesture that had
started the dictation was `POST /test/gesture forward-click` — `⌃⌥⌘F7` — a millisecond earlier.
Wispr was offered a chord it does not have bound. This is `mouse-gestures.md`'s own sentence —
*any key this app posts near a gesture has the same trap waiting* — and `postWisprHandsFree`,
`postWisprCancel`, `postWisprCopyLast` and `postReturn` have all been written under it since
2026-09-09. This poster was the one that was not. It now waits `settleForOptionsPlus` and then for
the modifiers, on a **serial queue** so a press and a release can never overtake each other, with
the bookkeeping (`scratchpadHeld`, the dead-man's switch) left at the call site because `stop()`
reads it milliseconds later.

A one-minute probe settled it before any rebuild: `POST /test/wispr-scratchpad {"down"}`, three
seconds, `{"up"}`, with nothing else on the wire — and Wispr's window list went from `['Status']`
to `['Status', 'Scratchpad']`. A bare F18 is read as a Scratchpad dictation; one wearing three
modifiers is not.

**Run 2, 23:24 — the wire never went bare, because `/test/gesture` never let it.** With the settle
in, the log said `wire clear after 200 ms` — the ceiling — and the paste came back again.
`postGesture` posts `⌃⌥⌘F-key` down and up and **nothing else**, so `CGEventSource` goes on
reporting three held modifiers until the next real keystroke heals it. A real Options+ gesture
posts its own trailing flags-cleared event 12–22 ms later (measured 2026-09-09) and that is what
`settleForOptionsPlus` was fitted to; this route posted none, so every *wait for a bare wire* loop
behind it simply ran out. It is the stale-⌘ bug of `area-crop.md` for the third time in this
repo, and the rule is the same one: **release the modifier with a `flagsChanged` carrying the
state the keyboard is left in.** With that, `wire clear after 0 ms`.

**Run 3, 23:26 — the swallow was stealing Wispr's own paste.** The chord was right, the Scratchpad
window opened, and the delivery still came back `wispr-cmdv`. Reading the database rather than the
log is what showed it: **every run so far had written a note**. Wispr *does* post a ⌘V in
Scratchpad mode — the earlier *no ⌘V at all* was measured with no tap armed — and it is aimed at
**its own note window**. The relay was swallowing it. Run 3's sentence ended up appended to run
2's note as ` commit and push the fix `, doubled, with `source = typed`. So the swallow is off in
this mode and the probe stays on: taking that key is this app reaching into another app's
conversation with itself.

**Run 4, 23:28 — `via: wispr-notes`, and the words went into the note instead of the caret.** Two
more things wrong, both about the window.

The first: **it takes the keyboard when it opens**, and it opens when Wispr *writes the note*,
about two seconds after the words are readable. `pasteText` fired the moment the note appeared
went straight into the Scratchpad — the note grew to 141 characters and the TextEdit document
Victor was looking at stayed empty. So the close moved **before** the delivery: read the note,
wait for the window, close it, verify, and only then hand the words to the caret.

The second: **Wispr does not reliably start a new note.** Run 4 appended to a note from four
minutes earlier, and a `typed` version's `content` is the whole accumulated notepad — 70
characters delivered for a four-word sentence, and growing. The delivery is now the **new portion
only**: the note's text with the pre-dictation text stripped off the front by longest common
prefix, which handles a fresh note and an appended one with the same code.

And the close itself had to learn to wait. A close fired at the delivery finds nothing open,
reports success, and the window appears a second later — still there at the start of the next
dictation, which is the state that costs a sentence. `closeWhenItAppears` polls for up to four
seconds for it to show, then closes and verifies.

### Run 5, 23:31 — the product path

```
23:31:38  wispr state: idle → warming — the relay asked for a dictation (scratchpad)
23:31:39  🗒️ scratchpad chord DOWN — 79 held (wire clear after 0 ms)
23:31:39  wispr history: row 12627 is this dictation's — 604 ms after the chord
23:31:39  ⚡ Wispr's own row confirms the ring 612 ms after the gesture
23:31:39  wispr state: warming → listening — Wispr created a row, poll saw it never …, notification never
23:31:43  🎙️ the microphone is closed — the relay's own stop gesture (5036 ms of speech)
23:31:43  ⚡ ring down: the microphone closed — the words are in flight
23:31:44  🗒️ scratchpad chord UP — 79 released (wire clear after 0 ms)
23:31:44  ⌘V from Wispr Flow — 453 ms after the microphone closed (Wispr pasting into its own Scratchpad; left alone)
23:31:44  wispr history: formatted 531 ms after the microphone closed (Wispr's own e2e 381 ms) — waiting for the Scratchpad note
23:31:46  🗒️ wispr scratchpad: note 4c6a7f52 (typed) — 23 chars, 2627 ms after the microphone closed
23:31:47  🗒️ the Scratchpad window is closed — delivering the words to the caret
23:31:47  🗣️ wispr transcript via Wispr's Scratchpad note — 23 chars, 3290 ms after the microphone closed
23:31:47  ✍️ the words landed: pasting at the caret
```

TextEdit ended with `commit and push the fix`, once. Wispr's window list ended at `['Status']`.
The frontmost application, sampled every 200 ms through the whole run, was **TextEdit and nothing
else**. `lastRingDown` is the release and `lastSettled` is the landing, 3.3 s apart.

The cost of the mode, in the same numbers: Wispr's own round trip was **381 ms**, the note was
readable **2096 ms after the row said `formatted`**, and closing the window took a further
**663 ms**. So the words land about **2.8 s after Wispr is done**, against a few hundred
milliseconds for a ⌘V it is allowed to post. That is what not touching his focus costs, and it is
worth saying out loud rather than discovering later.

**And the wrap off still means off.** `POST /test/wrap-mode {"mode": "off"}` then a
`/test/wispr-handsfree` pair: `intercepting false`, the ring up and down on the relay's own
gesture, `lastDelivery` untouched, and the silent dictation ending at the capture's own timeout
with `wispr: Victor's own dictation is over and the relay took nothing from it` — quiet, with no
banner, because a relay complaining that another app's tool worked is not a message.

## The row is the delivery; the note is the second opinion (2026-09-13, midnight)

The Scratchpad wrap shipped waiting for the note, and the note is the wrong thing to wait for.
Measured on the first working run: the `History` row said `formatted` **531 ms** after the
microphone closed, and the note was not readable until **2627 ms** — Wispr writes it when it opens
its window — with another **663 ms** to close that window before the words could safely be pasted.
So the mode was 2.8 s slower than the ⌘V it replaces, and every millisecond of that was spent
waiting for **a copy of the same sentence**.

The distinction that was missing: **the note is where Wispr pastes; the row is where Wispr writes
what it heard.** The note was never the source of truth — it is the sink the wrap chose precisely
*because* it is not Victor's document. The row has been the completion signal since 2026-09-12 and
has carried `formattedText` since this morning, and in Scratchpad mode it carries it while the
note is still being written.

So: deliver from the row the instant it is terminal, and let everything about the window happen
afterwards on its own time — wait for it to appear, close it, verify, and then read the note as a
**cross-check** rather than as a delivery. `WT_SCRATCHPAD_DELIVER=note` goes back to waiting,
because the day the two disagree is the day someone will want to look at the other one.

The cross-check normalises case and punctuation away first, and that is not laziness: Wispr's
paste arrives as ` commit and push the fix ` where its row says `Commit and push the fix.` — the
same sentence, dressed differently, because one went through its formatting pass on the way to a
text view and the other did not. Only a disagreement about the **words** is worth a line, and what
it would mean is the wrap delivering something other than what Wispr heard, which is the failure
this whole mode exists to avoid.

**The one thing that must not race.** Delivering at 531 ms means pasting at the caret while the
Scratchpad window is about two seconds from opening — and that window *takes the keyboard when it
opens*, which is how 70 characters of the relay's own delivery ended up appended to Wispr's
notepad with the document Victor was looking at left empty. At `formatted` the window is normally
not open yet, so the ordinary path pastes straight away; if it *is* open — left over, or Wispr
being quick — it is closed first and the words follow. The check is a window-server call
immediately before the delivery, which is the last honest moment there is.

## Parking the Scratchpad, and measuring whether it ever takes a key (2026-09-13, midnight)

Victor's ask, and the reason for it is the whole of his objection to the sink: the Scratchpad is a
side effect of the wrap, not something he asked to look at, and a window that can take his
keyboard is a window that can eat a keystroke meant for his work.

**Parked**, through Accessibility and without activating anything: as small as Wispr allows, at
the bottom-right of the **second** display when one is attached — a training Mac spends its day
extended onto a projector and the corner of *that* is the one place a stray window costs nothing —
all but an **8 pt sliver** past the edge. Visible enough to notice, small enough to ignore, far too
small to click into by accident.

Three details that are the whole of the implementation:

- **There is no `AXMinimumSize`.** The window simply refuses to go below its own layout minimum,
  so the measurement is *ask for 1×1 and read back what it settled on*, once, and log it.
- **AX coordinates are not AppKit's.** Accessibility measures from the top left of the main screen
  with y going **down**; AppKit measures from the bottom left with y going up. Getting that
  backwards puts the window off the *top* of the world instead of off the bottom, which looks
  exactly like the call having failed.
- **Read the frame back.** macOS clamps a window it thinks is escaping, and where it ended up is
  the only thing worth logging.

**Whether Wispr remembers it** is a question the log answers rather than a thing assumed: every
time the window appears it says `scratchpad reopened at <frame>` and whether that is where it was
parked. If it is, parking is a one-off; if it is not, it is parked again, every time, and the
count of times it came back elsewhere is in `/test/state`.

**And the keyboard.** For the whole of every Scratchpad dictation the window is polled at **50 ms**
with one question: has it ever become key. Wispr frontmost **and** this window its main one is the
honest test — a background window cannot take a key, and either half alone is a false positive.
The answer is `everBecameKey` in `/test/state.scratchpad`, with the moment it happened beside it,
and if it is ever true the log says so in capitals, because the sentence it would be describing is
*a keystroke of his landed in Wispr's note*.

## The Scratchpad takes the keyboard without taking the front (2026-09-13, after midnight)

The loop asked the question Victor actually cares about and got the answer he was afraid of. One
`z`, posted 1.5 s after the stop gesture, flags cleared:

| | wrap-caret | wrap-bound |
|---|---|---|
| frontmost, whole run | TextEdit | TextEdit |
| `z` in the victim document | yes | **no — empty** |
| `z` in Wispr's note | **yes** | **yes** |
| `z` in the delivered text | **yes** | **yes** |

`wrap-bound` is the one that removes the doubt: the document he was looking at stayed empty, and
the character turned up in the bound agent's terminal *folded into the dictation* —
`commit and push the fix z`. **Wispr's Scratchpad window becomes key without its application
becoming frontmost.**

That has three consequences and each got its own fix.

**The test for key focus was wrong, and it was wrong in this file too.** The watcher written an
hour earlier asked *is Wispr frontmost and is this its main window*, on the reasoning that a
background window cannot take a key. It can. `NSWorkspace.frontmostApplication` would have said
TextEdit for the whole of the run that proved it, so the watcher would have reported
`everBecameKey: false` for ever and told Victor the opposite of the truth. The test is now the
**system-wide focused element's owner** — `AXUIElementCreateSystemWide` +
`kAXFocusedUIElementAttribute` + `AXUIElementGetPid` — with the window's own `AXFocused` beside
it, and frontmost is not consulted at all, because it is the thing that lied.

**The window is shut on sight.** It used to be closed after the delivery, which left it up for the
two seconds Wispr takes to write the note plus however long the close took. The 50 ms watcher is
now armed at the **release**, and the 250 ms press goes out the moment the window is seen —
cutting its life to the 0.1–0.4 s the close itself costs. `lastOpenMs` is that number, measured
every time rather than assumed once.

**And for exactly that stretch, his keys are given back to him.** The tap takes every key that
came from **real hardware** — pid 0, unstamped — and re-posts it with `postToPid` to the
application that was frontmost at the *stop gesture*. That moment is the last one at which the
answer is unambiguous, precisely because the thief never becomes frontmost and there is nothing to
read afterwards that would say so. Wispr's own synthetic keys carry its pid and this app's carry
`backButtonStamp`; neither is touched. The branch sits **below** the app's own chords in `handle`,
so ⌘⌃B and ⌘⌃D go on working while the keyboard is borrowed.

Swallowing real keystrokes is the most dangerous thing in `HotkeyTap`, so it has two hard limits
and no judgement: it is armed only while the window is *observed* to be open, and it expires by
itself after **10 s** whatever anyone forgets. It logs the **keycode and nothing else** — a log
that records what he typed is a log that must not exist — and `WT_SCRATCHPAD_REDIRECT_KEYS=0`
turns it off.

The fourth consequence needed no fix, because it was already on its way: the `z` reached the agent
*inside the sentence* only because the note was the delivery. With the row delivering instead, a
stray keystroke in the note cannot be folded into a transcript — the row carries what Wispr heard
and nothing else, and the note has been demoted to a cross-check that logs a disagreement rather
than shipping one.

## The wrap, measured on the installed build (2026-09-14, 00:18)

Two caret dictations through the product path, with one `z` posted during the first.

| | run 1 | run 2 |
|---|---|---|
| delivery | `wispr-history` → caret | `wispr-history` → caret |
| words landed, after the microphone closed | **488 ms** | 3337 ms (the close needed a retry) |
| Scratchpad visible on the main display | **19 ms** | **19 ms** |
| Scratchpad existed | 5706 ms | 7293 ms |
| …of that, after the close was asked | 440 ms | 3289 ms |
| `everBecameKey` | **true** | **true** |
| keys redirected / passed | **1** / 1 | 0 / 1 |
| frontmost, whole run | TextEdit | TextEdit |
| Wispr windows afterwards | `['Status']` | `['Status']` |

TextEdit ended with `zcommit and push the fix.Commit and push the fix.` — the `z` in the document
he was looking at, each sentence once, nothing in the note.

**The window is `AXStandardWindow` at window layer 3.** Victor's *it sits on top of everything* is
a number now: layer 0 is an ordinary window and this is three above it. Its minimum size is
**300×300** — Wispr refuses smaller — and parked at the bottom-right of the one display it settles
at `1720,1089` on a `1728×1079` screen, clamped from the `1720,1109` asked for, which leaves the
8 pt sliver. **Wispr does not remember the frame**: it reopens at `1428,817` every time, so the
park happens on every open rather than once.

`everBecameKey` is **true**, every run, with the line that proves it: *the system-wide focused
element belongs to Wispr Flow, frontmost is TextEdit*. The watcher written an hour earlier, which
asked whether Wispr was frontmost, would have answered false for ever.

Three bugs the two runs found, all fixed in this build:

**The note was still racing the row.** `pollNote` was called before the row was read, so the note
path could win — and it did, 13 ms after the microphone closed, shipping the single `z` a
keystroke had put in the note. One character delivered as a dictation. The note is read only under
`WT_SCRATCHPAD_DELIVER=note` now; otherwise it is a cross-check and nothing else.

**Every sentence arrived twice.** Wispr's ⌘V had been let through, on the reasoning that it
belongs to Wispr's own note — true while the note was the delivery, false once the window is being
closed at the release: the paste arrives ~450 ms later with nowhere of its own to go and lands in
**his document**, lowercased, beside the relay's proper copy. The swallow is back on in every mode.

**A stale close edge ended the next dictation.** Run 2 was over 600 ms after it began, because the
CoreAudio notification for run *1* arrived six seconds late and `edge(false)` took it. A witness
that never saw the microphone open cannot report it closing: both the notification and the poll
now need `notifyMs` / `pollMs` for *this* dictation before their close is honoured.

And one number that is not where it should be. The delivery still waits for the window to be gone,
because a paste made while the Scratchpad holds the key focus lands in the note — 488 ms when the
close takes first time, 3337 ms when it does not. The row is ready at ~400 ms and the honest way
to decouple the two is to post the relay's own paste with `postToPid` to the app it is meant for,
rather than to whatever happens to hold the focus. Not built.

## The paste is addressed, so the delivery stops waiting (2026-09-14)

The last number that was in the wrong place. The row is ready **400 ms** after the microphone
closes and the words were landing at 488 ms on a good close and **3337 ms** on one that needed a
retry, because the delivery was gated on Wispr's window being gone. The gate was there for a real
reason: a ⌘V posted at the session while the Scratchpad holds the key focus lands in **its** note,
which is a bug this journal has already paid for once.

The fix is to stop posting at the session. `CGEvent.postToPid` delivers straight into one
application's event queue — it bypasses the session entirely, so it reaches the app whether or not
that app is frontmost and whether or not some other window has taken the key focus. Which is
exactly the shape of the problem: the thief never becomes frontmost, so *frontmost at the chord* is
both knowable and correct.

So `DictationResult` grew **`focusPid`** — *which process these words were meant for* — and it is
deliberately a pid and deliberately source-agnostic. The fact being recorded is **the caret was
here when he asked**, which is a property of any recogniser whose machinery might move the focus
under a sentence, not a Wispr quirk to branch on. `WisprFlowSource` fills it only in Scratchpad
mode, from the app it remembered at the chord; every other path leaves it nil and means *whatever
has the caret*, which is what `/test/dictation`, the five-minute recovery of a cancelled sentence
and ⌘⌃P all correctly mean. Bound-terminal and spawn deliveries never went through the focus at
all. One field, one caller, no second branch — which is the rule this file is under.

`TerminalBinding.pressPaste(to:)` is the addressed half, and it is shorter than its sibling rather
than longer: the stale-⌘ cleanup that `tap(key:command:)` exists for is about
`CGEventSource.flagsState`, which is *session* state, and an event posted to a pid never enters it.
The `flagsChanged` pair still goes out — to the same pid — because a Cocoa app builds ⌘V out of a
modifier it believes is down.

**Who holds the keyboard is a log line now, not a gate.** It still says so when the Scratchpad is
open at the moment of delivery, and whether it has the focus, because that is worth knowing; it no
longer decides anything.

One thing deliberately left as a measurement rather than a fix: the close is asked up to three
times, and each attempt now logs **which one worked and whether the window was parked at the
time**. The open question is whether a window pushed to the edge of the screen is harder for Wispr
to toggle — and nothing is un-parked to find out, because un-parking would put it back over his
work, which is the thing being avoided. The log accumulates the evidence; the decision waits for
enough of it.

## Three ways to take the keyboard back, and what each one measured (2026-09-14, 01:00–01:15)

The letters die because an application that is **frontmost with no key window has no first
responder**: Wispr's Scratchpad is a non-activating panel that becomes key without becoming
frontmost, and a plain character posted to the app underneath is dropped. ⌘V survives the same
trip because it goes through `performKeyEquivalent`, which needs no first responder — which is why
the addressed paste works and the addressed letters do not.

Three ways out were tried against
`./tools/wispr-loop.sh wrap-bound --probe-offsets=-3,-1,0.3,0.8,1.5,2.5,4`.

**A — minimize the Scratchpad on sight. Rejected: it kills the dictation.** A minimized window
cannot hold key focus and cannot be seen, and it looked like the whole answer. With
`AXMinimized = true` set the moment the 25 ms watcher sees the window, the dictation **never comes
back at all**: no row reaching `formatted`, no delivery, no ring down, nothing in the bound tty.
Wispr's Scratchpad dictation needs its own window live — the same shape as the sink holding the key
window, which breaks it the same way. The precondition the wrap rests on is that the window is
*closed* when a dictation **starts**; it is not that the window is dispensable while one runs.

One thing survived from A and is an improvement on its own: `windowIsOpen()` now asks
**Accessibility** whether the window exists rather than asking the window server whether it is on
screen. *Exists* and *is visible* are two questions, and the close, the retry and the precondition
all want the first; `windowIsOnScreen()` keeps the second, which is all `visibleMs` ever needed.

**C — give the victim its key window back through AX. Rejected: it does not flip.** The window he
was typing in is remembered at the chord (`AXFocusedWindow` of the frontmost application) and told
to be `AXMain` and `AXFocused` again the instant the theft is detected. The log is the result:
`Wispr's Scratchpad took the keyboard — handed it back to TextEdit; the focus owner is still
Wispr`. Re-activating the application had already been tried and could not work for a reason worth
keeping: `activate` says *be frontmost*, and it already was — what it lacked was a key window, and
neither call produces one against a panel that has taken it.

**B — hide Wispr's application for the dictation. Not run.** A's result predicts it: hiding an
application takes its windows off screen exactly as minimizing one does, and the Scratchpad
dictation did not survive that. Spending a build to confirm it would buy a second copy of the same
answer.

### And the thing the three experiments were actually chasing

`wrap-caret` passes **7/7 with the same code and the same mechanism** — measured on this build:
`key redirect: pid=32184, 5 key(s) seen`, every letter in the victim. `wrap-bound` loses all seven
with `pid=88211`, and `ps` says both pids are TextEdit. Same target, same redirect, opposite
outcome.

The difference is not in the relay. It is **what else has a window**: `wrap-bound` opens a scratch
Terminal to bind to, and that Terminal holds the key window — so TextEdit, the app the letters are
addressed to, has none, and they are dropped exactly as the theory predicts. `wrap-caret` has no
Terminal in the picture, TextEdit keeps its key window, and the same five redirected letters land.

Which makes the scenario's expectation the thing to look at rather than the redirect. With a bound
terminal on screen, a keystroke Victor makes belongs to whatever has the key window, and *the
victim document* is not automatically that. The measurement that settles it is one run of
`wrap-bound` that also looks in **the bound tty** for the probe letters.

The redirect is kept, because on the evidence it works wherever the app it is aimed at has a key
window to receive them, and it cannot manufacture one: A says Wispr's window cannot be taken away
mid-dictation, C says the focus cannot be taken back from it.

## The night the wrap found its shape (2026-09-13/14)

Eight hours, four shapes, and the one that holds. This section is the consolidated account; the
sections above it are kept because the reasoning is the evidence, and every claim of theirs that
did not survive is named in *Superseded on the way* at the top.

### What it started as, and why that could not work

The wrap was *swallow the ⌘V Wispr posts and insert the words ourselves*. Two of Victor's
dictations failed on 09-13 and both failed the same way: the whole apparatus — the swallow, the
`History` poll, the settle — was armed from `WisprWatch`'s CoreAudio **closing edge**, and that
edge is **0–6 s late and sometimes absent altogether**. It publishes only when the value it
re-reads differs, so a dictation shorter than its own lag has neither edge; with Wispr pinned to
the Loopback device `🎓 TO Wispr`, whose physical source keeps the stream warm, it produced **no
edge at all in five successful runs**. A 2.5 s sentence went into Word with the relay blind to it,
and twelve seconds later `speculativeGrace` announced *Wispr ignored the chord* about a sentence
that had been delivered.

### Three witnesses, measured

`WisprState` joins four inputs, none authoritative alone. On one real dictation:

| witness | proves | spoke at |
|---|---|---|
| the chord this app posts | a dictation was **asked for** | it is the clock |
| Wispr's `History` row appearing | Wispr **took the chord** | **357 ms** |
| a 100 ms poll of `kAudioProcessPropertyIsRunningInput` | a microphone **is** open | **607 ms** |
| `WisprWatch`'s notification | the same fact, pushed | **5590 ms** |

`wispr state: warming → listening — Wispr created a row, poll saw it never after the chord,
notification never` is the line at 357 ms, and it is the thesis: at the moment the dictation was
confirmed, **neither microphone signal had spoken**. The notification was 9.2× slower than the
poll and 15.7× slower than the row.

Two rules came out of it and both are load-bearing. **Arm at the start chord**, so a missing edge
costs one flag instead of a sentence. And **a witness that never saw the microphone open may not
report it closing** — a close belonging to the previous sentence arrived six seconds later, 600 ms
into the next one, and ended it before a word was spoken.

### The ring stopped meaning two things

Victor's reading: the ⚡ ring is *a microphone is open*, and the tooltip is where the words go. So
the ring comes down at the relay's **own stop gesture**, the chip carries `Transcribing...` for the
settle, and `endSettling` logs `✍️ the words landed` rather than `⚡ ring down`. `RingDown` grew a
sibling, because *why did the ring go* and *why did the wait end* are two questions with two
different fixes. And a 🔼 click while the words are in flight became a stop or nothing — never the
phantom second dictation that threw away the first sentence's swallow window.

### Four candidates for the wrap, three of which work

| candidate | works | verdict |
|---|---|---|
| swallow the ⌘V | mostly | depends on a keystroke another process may or may not post, inside a window this app may or may not have armed |
| **the sink** (take the key window at the stop) | **3/3** | Victor: it takes the focus off a man who may be clicking or typing. **Emergency mode.** |
| **revoke Wispr's Accessibility grant** | yes | breaks **Wispr** as a standalone tool |
| **hold *Open Scratchpad*** | **yes** | **shipped** |

The sink's measurement settled a question that had been open all day: **Wispr picks the app it
will insert into at the end, not at the chord** — taking the keyboard 1–5 ms after the stop chord
was enough, 3/3, and the row's `app` column named the relay although TextEdit had been in front
throughout. And one thing that is not a candidate at all: the window between the row saying
`formatted` and the ⌘V is **57 ms**, and a ⌃Escape posted after `formatted` does not stop the
paste. There is no *cancel the insertion*; there is only *do not ask for one*.

### The Scratchpad, and the five runs it took to get right

Wispr's *Open Scratchpad* shortcut **held** dictates into its own note. The first measurement —
F18 held 20 s, text in `Notes`, victim untouched, focus unmoved, no ⌘V, 432 ms — was taken with no
event tap armed, and three of its four claims turned out to be wrong. Each cost a run.

1. **23:20 — the chord went out as `⌃⌥⌘F18`.** Posted a millisecond after `/test/gesture`'s own
   `⌃⌥⌘F7`, with those modifiers still on the wire. `mouse-gestures.md` says it already: *any key
   this app posts near a gesture has the same trap waiting*.
2. **23:24 — the wire never went bare**, because `postGesture` posted the chord down and up and
   **nothing else**, leaving three modifiers held as far as `CGEventSource` was concerned. It is
   the stale-⌘ bug of `area-crop.md` for the third time in this repo.
3. **23:26 — the swallow was stealing Wispr's own paste.** Reading the database rather than the log
   showed that every run so far had written a note; Wispr *does* post a ⌘V and it is aimed at its
   own window.
4. **23:28 — the words went into the note instead of the caret.** The window **takes the keyboard
   when it opens**, so a paste fired the moment the note appeared went into the note. And Wispr
   does not reliably start a new note: it **appends**, with `source = typed`, whose content is the
   whole accumulated notepad — 70 characters delivered for a four-word sentence.
5. **23:31 — green**, end to end, `via: wispr-notes`, the sentence once in TextEdit, the window
   closed, the frontmost app TextEdit throughout.

Then the model itself was corrected: **the window appears at the start of the hold and lives for
the whole sentence**, not at the end. So the watcher is armed at the chord, the window is parked on
sight, and the close is asked at the release — **exactly once**, because the close is a toggle and
the second ask re-opens what the first shut.

### The row is the delivery

The note is where Wispr *pastes*; the row is where Wispr writes *what it heard*. Waiting for the
note made the mode 2.8 s slower for a copy of the same sentence — the row is `formatted` at
~400–530 ms, the note not readable until 2627 ms, plus 417–663 ms to close the window. So the row
delivers at `formatted`, and the note became a cross-check that normalises case and punctuation
away and compares only the **new portion**.

The last gate went on 09-14: the paste is **addressed**. `DictationResult.focusPid` carries the pid
of the app he was looking at at the chord, and `postToPid` puts the ⌘V into that application's own
queue, bypassing the session and therefore whoever holds the key focus. **Words land at
~410–490 ms.**

### The keyboard, and the limit of what can be done about it

The finding Victor was afraid of, measured: **the Scratchpad becomes key without its application
becoming frontmost.** A `z` typed 1.5 s after the stop went into the note and reached the bound
agent *inside the sentence*, with `frontmostApplication` reading TextEdit the whole time. Three
consequences. The test for key focus must be the **system-wide focused element's owner**, never
frontmost. The window is **closed on sight** (its life is now the close's own 417–445 ms). And
every real keystroke is re-posted to the app he was looking at, decided per key, with ⌘ and ⌃ always
passing so ⌘Tab and ⌘Space stay the system's.

And the limit, which three experiments established rather than guessed: **the redirect cannot
manufacture a key window.** An application that is frontmost with no key window has no first
responder, and a character posted to it is dropped — ⌘V survives the same trip only because
`performKeyEquivalent` needs none. Minimizing Wispr's window kills the dictation outright; setting
`AXMain`/`AXFocused` on the victim's window logs *the focus owner is still Wispr*; re-activating the
application does nothing, because it was already frontmost. So the redirect lands 7/7 where the
victim keeps its key window and 0/7 where another window holds it.

### The shape that holds

Hold the chord from a closed Scratchpad, park the window the moment it appears, guard his keyboard
while it is up, release at the stop and ask the close once, deliver from the row at `formatted`
with an addressed ⌘V, and read the note afterwards only to check the two agree. The sink is the
emergency mode and may not take the key window while any of this is running. A dictation Victor
starts himself is Wispr's, and the relay does nothing to it but draw the ring.

## The fifth stale ⌘, and the guard that finally works (2026-09-14, 02:48)

Two things closed in one night's last hour, and one of them is a rule this repo
has now paid for five times.

**The keyboard guard ships on.** Run alone under the loop's own lock, all three
`wrap-*` scenarios put **7/7 probe letters into the victim document at every
offset** — including the two typed while the clip was still playing — with none
in Wispr's note, none inside the delivered sentence, `redirectedAX = 5` and
deliveries at 12–18 ms. Every earlier reading that contradicted this was taken
while **two harness instances were typing into the same document at once**, which
the runner proved by finding its own three-letter sweep arriving from another
process's pid. That contamination is also the whole explanation of the doubled
letters and the two-pid traces that cost most of the night. There is a lock file
now, and no measurement of this is worth anything without it.

**And the fifth stale ⌘ was in the fix for the fourth.** After a bound dictation
the trace showed the relay's own ⌘C leaving the session at ⌘-down:

```
⌨️trace ↓ key 8 pid <ours> flags 0x20100000 — passed
⌨️trace ↑ key 8 pid <ours> flags 0x20100000
```

`KeySimulator.simulateKeyPress` had been given a trailing `flagsChanged` earlier
that evening, and it had **two** faults that a passing test did not see:

1. **The key-up still carried the modifier.** `CGEventSource.flagsState` reports
   whatever the *last* event's flags said, so a release stamped with ⌘ **is** the
   session believing ⌘ is held. Whatever is posted afterwards is a second
   mechanism papering over the first.
2. **The clearing event was announced on the wrong key.** It was built with
   `virtualKey: keyCode` — the **C** of ⌘C. A `flagsChanged` is a *modifier*
   transition; one carrying a letter's keycode is not one, and the window server
   need not apply it. The clear silently did nothing.

Both are fixed: the release is bare and the clear is announced on the modifier's
own key. `HotkeyTap.postGesture` had the same second fault and got the same
treatment.

The guard grew accordingly, because a test that passed this is a test that was
not asking the right question. `evals/test_stale_modifier.py` now fails a poster
whose **key-up carries a modifier** *and* whose `flagsChanged` is announced on
something that is not a modifier key — the pair, because the five posters that
were measured leaving the wire clean all carry a modifier on the key-up and are
rescued by an honest clear. Its `--self-test` reads both historical versions of
the same function out of git and asserts the scan rejects each:

```
✓ the scan rejects `simulateKeyPress` at fc74df6~1 — it stamped ⌘ on a key-up and posted nothing after
✓ the scan rejects `simulateKeyPress` at 2cc4ff1 — it cleared the flags on the typed key, not on a modifier
✓ and accepts it at HEAD
```

Two occurrences of one bug in one function, four builds apart, and the second was
introduced by the fix for the first. That is the argument for the test existing
rather than the paragraph.

## What the cancel cost the sentence after it (2026-09-14, 03:30)

Three defects the runner measured on `3b4be96`, and two of them are the same
mistake: *the sentence Victor threw away went on being treated as a sentence in
flight*.

**The regression, and it is the price of the `discardOnArrival` fix.** Keeping
everything armed after a cancel is right — Wispr may still paste, and that key
belongs to nobody — but it was written as though nothing else would happen for
the thirty seconds of `captureTimeout`, and what happens is that Victor asks for
the **next** dictation. Two independent refusals, measured as `never listening
(8.1 s)`: `retireCaptureIfSettled` would not let a non-terminal row go, so
`beginCapture` returned early and the new sentence had no swallow, no row poll
and no delivery at all; and the phase stayed `transcribing`, which
`onPasteToggle` and `startDictation` read as *words in flight*, so the click was
answered with *nothing to start, nothing to stop*. Both were true statements
about the old sentence and neither was a reason to refuse the new one. The
capture is now **retired on the gesture**: `endCapture` gives back everything it
holds and arms the new dictation's own capture in the same call, and the one
thing that outlives it is the swallow, **keyed by the rowid it was armed for**.
`WisprHistory.entry(rowid:)` exists for that — once a second dictation has
started, `newest()` is the new row, and the old `status(of:)` compared against it
and answered `""` for ever, which reads as *not terminal* and is how the capture
came to be immortal in the first place.

**And the window Wispr reopens.** The close asked at `closeListening` works; what
nobody was watching for is the **second** window, the one Wispr opens ~2 s later
when it writes its note. On an ordinary dictation `endCapture` runs at ~450 ms
and catches it. On a cancelled one `endCapture` waits for Wispr to finish
transcribing words nobody wants, so the window stood over his work for **3.2 s**
with his keystrokes going into the note. `armDiscardClose` now re-arms the close
the moment the cancel has its answer — the row for that dictation terminal, or
`pasteGrace` since the ⌃Escape — and `WisprScratchpad.closeIsInFlight` is there
so that the earlier ask and this one cannot become the double tap that re-opens
what the first one shut.

**The seventh stale ⌘, and the first this app did not cause.** `wispr-alone`
leaves the session at `sessionFlags == ["command"]`: Wispr's ⌘V key-up carries ⌘
and posts no `flagsChanged` behind it, and with the relay stopped there is no tap
to put it back. So the relay heals it at launch instead, after
`SingleInstance.enforce`, by comparing what the window server believes against
what is physically down — `flagsState` against `keyState` on both of each
modifier's keycodes — and posting a stamped `flagsChanged` **on the modifier's
own keycode**, carrying the state the keyboard is left in rather than `[]`, so a
modifier he really is holding survives the clearing of one he is not. The rule of
`area-crop.md` has now been paid for seven times and this is the first payment
that is a *reader* rather than a poster: every previous occurrence was this app
leaving a flag behind, and this one is this app finding one.


## The adversary's second round: four things that outlived their dictation (2026-09-14, 04:30)

Nineteen attacks, no leaked text, five findings — and four of them are the same
shape as each other: *something belonging to a sentence that is over arrived
afterwards and was taken for something belonging to the next one.*

**A chord that went out late (Finding 1).** The one the round was worth running
for. `postScratchpad` moves its bookkeeping now and hands the keys to a serial
queue that waits for a bare wire, so on an 18 ms dictation — a cancel landing
right behind the gesture — the hold arrived **after** everything had ended.
Wispr read the down/up as a *tap*, opened its Scratchpad, and the window stood
for **57 s** with the keyboard guard already disarmed. The harness had sampled
`['Status']` and exited 0 thirteen seconds too early, which is the other lesson:
the check that found it was the one made after the harness said it was finished.
A queued hold now carries the epoch of the dictation that asked for it and is
dropped at post time when that epoch has moved on; a release is only ever dropped
when the hold it releases never went out, because a key stuck down is worse than
anything this is protecting against. And because there will be other ways for a
window to end up standing there, `endCapture` arms a 12-second sweep that closes a
Scratchpad nobody is dictating into — `orphan Scratchpad closed`.

**An edge that arrived late (Finding 2).** `notifyMs = 4109`: the CoreAudio
notification's *open* came in after the relay's own stop and, in one run, before
the delivery. The relay read it as a dictation Victor had started by hand,
announced `dictation abandoned (a new dictation started)`, put the ring back up,
restarted the halo and the recorder, and took it down again 500 ms later. The
close-edge rule for this was written on 2026-09-13 — *a witness that never saw the
microphone open may not report it closing* — and its mirror was simply missing.
It is now asked before the state machine is told, because `notify(true)` takes an
idle machine into `listening` and would put the phase back into a finished
sentence.

**A test route that was two routes (Finding 3).** `/test/wispr-handsfree`
promised a hand-started dictation and called `gestureSeen(relay: true)`, so the
relay swallowed Wispr's ⌘V and re-delivered the sentence itself — `via:
wispr-cmdv` on a run whose whole point was that it would only watch. The
observation-only control the contract needs is now `{"hand": true}`; the old
behaviour stays because it is the transcribe primitive everything else is built
on. Two questions, two calls.

**And two ways to wait thirty seconds for nothing (Finding 5, Attack 12).** Wispr
killed mid-settle, and two seconds of digital silence that left a row in
`raw_transcript` with every text column empty for ever. Both ended in `No words
came back` at `captureTimeout`, half a minute of a chip promising words. The
first is answered by asking whether Wispr's **main** process is still there —
anchored on the executable path, because the bundle id and the name both match
the nested helper — and the second by giving an empty row eight seconds before
calling it what it is: *No speech was heard*.

Finding 4 is the runner's: a spawn scenario left its binding and its Terminal
window behind.

## The engine is a choice with two names on it (2026-09-14)

`Replace WisprFlow` is off the menu. In its place is one row that says which
recogniser is listening and opens the list of both:

```
  Engine: Wispr Flow…
       ✓ Wispr Flow
         whisper-large-v3-turbo — 1.6 GB RAM
```

**What the checkbox could not say.** Victor: *"în meniu nu mai trebuie să fie un
checkbox «Wispr» sau nu, ci un submeniu din care să aleg modelul de utilizat …
să fie acolo «Wispr Flow», respectiv numele modelului local MLX … aș vrea o
distincție mai clară decât «da» sau «nu» pentru Wispr. Așa se vede și numele
modelului, dacă mă întreabă cineva ce folosesc."* A tick names one engine and
leaves the other one unnamed, and the unnamed one is precisely the half he is
asked about in a room — *what are you dictating with?* has an answer with a
version number in it, and the menu was the one place that answer could live.

The engine had in fact never been pickable at all. It was `WT_SOURCE=whisper` or
a `dictationSource` key written by hand; a doc comment in `AppDelegate` had been
promising "the menu's *Dictation source* row" since 2026-09-12 to a menu that
had no such row. The model's **name** was in the menu — a disabled readout at the
bottom, `whisper-large-v3-turbo — 1.6 GB RAM` — which is how the two rows ended
up being one: the readout is now the picker's second line, and its title when it
is the one running.

**Why that row and not another.** `Replace WisprFlow` reads, to the hand on the
mouse, as *Wispr Flow: yes or no* — it is named after the app it competes with,
which is exactly the question the new row answers, in the place he went looking
for it. It is not the same question: the mode it ticked is *where a caret
dictation goes*, and that mode is untouched — the forward side button still opens
a dictation that is pasted at the caret, `AppDelegate.replaceWispr` still gates
it, and the preference moved from the row to `AppDelegate.replaceWisprKey` so it
still survives a launch. What the mode lost is its tick, and with it its mouse-5
legend — the menu is the only place a gesture is written down in this app, so
that is a real cost, taken deliberately on his instruction.

**It is a submenu, with the arrow — after one build where it was not.** The
first cut popped the list up at the pointer, on the trap `Rebind to…` paid for on
2026-09-10: one disclosure arrow makes AppKit reserve the gutter on every row of
the menu and the gesture column shifts with it (*"a fugit toată coloana de
meniuri din cauza >"*). That argument was carried over rather than re-tested, and
Victor looked at the result: *"nu e bine. tre submeniu obișnuit cu >, nu un
modal"*. A list of two that appears detached from the row it came from reads as a
modal rather than as a branch of the menu, and the gutter is the cheaper of the
two costs at that size. `Rebind to…` keeps its pop-up, because its list is long,
live and searched — the reason was never the arrow alone.

The two rows are rebuilt in `applyEngineRow`, which `menuWillOpen` already calls
for the row above; the submenu needs no delegate of its own, because the only
thing that changes in it is the model's footprint.

**The switch is five assignments and a re-wire.** `AppDelegate.setEngine` nils the
old source's five callbacks, assigns `source`, writes the preference and re-runs
`wireDictationSource()`. Nothing else in the app is told, because nothing else in
the app knows there is more than one answer — which is what `DictationSource` was
for (*One interface, because a second branch is how the first one rots*). This is
the first time that protocol has been asked to do the thing it was written for.

Two things it does that are not obvious:

- **It refuses with a sentence in flight** — `listening`, `settling`,
  `speculative` or `source.isRecording`. A source swapped between
  `didStopListening` and `didTranscribe` takes the words with it: the old one is
  left holding a transcript with nobody wired to receive it, and the settle then
  runs out over a sentence that was already spoken. The menu is told what is
  *actually* running either way, so a refused pick cannot leave a tick beside an
  engine that is not listening. The tick is drawn from the app's answer and never
  from the click, for that one reason.
- **Picking the local model brings its weights up on the spot.**
  `LocalWhisperSource.prepare()` is deliberately a no-op — it is a fallback and
  nothing should pay ten seconds for it at launch — but choosing it from the menu
  *is* the gesture that asks for it. A first dictation answered with `the local
  model is still loading` would read as the switch having failed.

`GET /engine` answers `engine` (`wispr` / `whisper`) beside the display name, so
a test can assert the pick landed without matching a string meant for the eye.


## The front is a third thing Wispr takes, and the only one that can be given back (2026-09-14, 06:00)

Victor, after a morning of caret dictations out of a terminal: *"in timpul dictarii la caret cu
wisprflow, am pierdut de 3 ori focusul pe aplicatia pe care eram. fix cand wisprflow pus sa
transcrie. eram intrun terminal si focusul a fost pierdut de acolo. a trebuit sa dau click"*.

**The log names the thief, twice, in the same second as this app's own chord.** Both losses are in
`relay.log` under a `🎙️ forward button — a dictation at the caret`:

```
05:56:01  🗒️ scratchpad chord UP / DOWN / UP — 79
05:56:01  ⌨️ the front app changed since the chord — his keys go to pid 92966, not 46446
05:58:38  🗒️ scratchpad chord UP / DOWN / UP — 79
05:58:38  ⌨️ the front app changed since the chord — his keys go to pid 92966, not 46446
```

46446 is Terminal. **92966 is `com.electron.wispr-flow`** — Wispr's own application, not the
`accessibility-mac-app` helper that owns the Scratchpad and posts the ⌘V. So it is not the
transcription taking the front and it is not Wispr's floating pill: it is the **close toggle the
wrap posts at the stop gesture**, which Wispr answers by activating itself. Nothing was putting the
front back afterwards, so he clicked his way back by hand — three times, which is how it got
reported.

**This is a third, separate loss, and the first one that can be undone.** The two already written
down are the *key window* (`The keyboard, and the limit of what can be done about it`) and the
*keystrokes in the tail* (`The measured truth about his keystrokes`). Both are Wispr's
**non-activating** panel taking key focus while the victim stays frontmost, and *Three ways to take
the keyboard back* closes that door: `activate` says *be frontmost* and the app already is. **The
front is the opposite case.** When Wispr's application activates, the victim really is behind —
`activate` has something left to say, and so does `AXRaise` on the window he was typing in. The
line in `dictation-source.md` that says the theft cannot be undone is about the key window and
stays true; it must not be read as *nothing about focus can be repaired*.

**It hangs off the close, not off a watcher, and that is a safety decision.** Every close in
`WisprScratchpad` — the dictation's, the precondition's at the chord, the idle sweep's orphan —
now funnels through `finishEnsure` → `onCloseFinished`, and `WisprFlowSource.putTheFrontBack` is
what listens. The alternative, reacting to `didActivateApplication` the moment Wispr comes forward,
was rejected: it would hand the front back **while Wispr is still writing its note**, and Wispr
picks its insertion target at the end — that is the failure `WisprHistory` exists because of, with
the sentence landing in his document instead. After the close, the note is written and the window
is gone, so there is nothing left to aim anywhere.

What it will not do:

- **Nothing at all unless Wispr is frontmost right now.** If he has already clicked back himself,
  or never lost it, the whole thing is one `frontmostApplication` read.
- **It gives the front to the app he was in when Wispr took it** (`frontBeforeLast`), not to the
  one that was in front at the chord — he may have clicked elsewhere mid-sentence, and putting him
  back into the window he left would be a second theft dressed as a fix. `focusPid` is the
  fallback, and a dead pid is skipped (`kill(pid, 0)`).
- **It stops rather than fight.** Five handbacks in a minute and it leaves the front where it is
  and says so: Wispr and the relay each activating in answer to the other is a fight the man
  watching loses either way.
- **Twice per close, at +0.45 s and +1.5 s**, because the toggle's effect lands when Wispr gets to
  it and not when the chord goes out.

The handback logs under `🪟` and says whether it worked, because *the focus owner is still Wispr*
is a thing this app has written before and it has to be as easy to see when it is a front as when
it was a key window.

### Measured, after the first attempt did not work (06:13 → 06:14)

`activate` alone is **not** the sentence. The first build did what the failed experiment C in
*Three ways to take the keyboard back* does — `activate(options: [])` plus
`AXRaise` / `AXMain` / `AXFocused` on the window he was typing in — and with the theft provoked on
purpose (tap the Scratchpad open, activate Wispr, let the idle sweep close it) it reported its own
failure twice: `🪟 the close took the front to Wispr Flow … and it would not go back to Terminal —
Wispr Flow is in front`. A **background** application asking for somebody *else* to be frontmost is
the request macOS declines.

**`AXFrontmost` on the application element is the one that is granted**, because it is asked with
the Accessibility trust this app already holds. With
`AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), kAXFrontmostAttribute, true)`
added, the same provoked run reads `front after the tap: Wispr Flow` → `Terminal` 2.6 s later, and
the log says `🪟 … — Terminal has it back`. The `activate` call stays beside it and both results
are logged (`activate=…, AXFrontmost=…`) so the next failure names itself.

**And the harness cannot see this loss, which is why it shipped.** `wispr_loop.frontmost_app()`
asks System Events for *the first process whose frontmost is true*, and during the provoked theft
that answered **`Terminal` while `NSWorkspace.frontmostApplication` answered `Wispr Flow`** — so
`focus never moved off the victim` was green throughout a run in which the front was Wispr's. Both
`wrap-caret` and `wrap-bound` pass on the fixed build with `['TextEdit']`, and that is worth
exactly as much as the witness is. A rig that is meant to catch a stolen front has to read the
front the way the window server does.

## Nothing this app draws is in the picture (2026-09-14)

Victor, by mail while away from the keyboard: *"Atunci când faci poză la ecran în timpul dictării,
în poză să nu apară decorațiunile puse de … Walkie-Talkie. Cercul de fulgere, săgețile verticale
sau bila galbenă care crește, bum, efectul de tap. Pentru durata screenshot-ului, decorațiunile se
ascund și apoi se reafișează."* The three are `CaretHalo` (the ring's lightning frames), `DropArrow`
and the `.tapRipple` marker `CaptureFlash` draws at every shutter.

**They are already invisible to every capture, and the guarantee was re-measured rather than
quoted:**

| | |
|---|---|
| every window this process owns | `kCGWindowSharingState == 0`, except AppKit's own menu-bar strips |
| a control panel at `.readOnly`, `screencapture -x -D`, both displays | **3600 magenta samples** — it is in the frame |
| the same panel at `.none` | **0** — it is not |
| two real mid-dictation frames (13 and 14 Sep, halo riding every dictation since 2026-09-11) | no gold annulus at the recorded pointer |

So the hide-and-restore he asked for was **not built**: it would buy nothing, and it would cost a
blink of his own UI at the exact moment the shutter's confirmation is meant to be drawn — the tap
ripple *is* the receipt for the capture it would be hidden from. What the request is really about
is that the guarantee must not lapse silently, and the answer to that is a test, not a mechanism:
`evals/test_capture_decorations.py` counts the windows each file makes against the `sharingType`
lines it sets, and its `--self-test` proves it fails on a bare panel.

**What *is* in his frames is the other two apps.** `victor-macos-addons` and `victor-effects`
contain no `sharingType` anywhere, so the hands-off 🔒 corners, the amber frame, the bottom-left
banner and any effect playing from the tablet all land in these pictures — the 14 Sep 06:27 frame
has the hands-off badge sitting beside the pointer. That is defensible there (a decoration nobody
can screen-share is not on the projector during a training), so it is left alone and named here
instead of being quietly changed from this repo.

## The highlight lands inside the sentence (2026-09-14)

The same mail: *"Vreau același lucru și pentru selecție. Doar că textul selectat trebuie inserat
într-o etapă de postprocesare în transcripție, în locul markerului pe care l-ai lăsat acolo. … Și
ca fallback, în cazul în care markerul nu este detectat în textul transcris, pui transcripția ca
acum, la final."*

The shot marker built that morning says `screenshot one` into Wispr's ear and comes back as
`[shot 1]` — a **reference**, because a picture cannot be inside a line of text. A highlight can:
it is text already. So the second kind says `selected text one` and the rewrite puts **the words
themselves** where the marker was, quoted, at the point in the sentence he made the selection at.

What that cost, in order:

- **`ShotMarker.Kind`** — `shot` | `selection`, and everything else shared: the `say` clips, the
  gap gate, the Loopback device, the number words and the digit forms, and now a **single regex
  with two alternatives**, so one scan over the transcript keeps a picture and a highlight in the
  order he made them. Two passes would each rewrite the string the other was measured against.
- **Two words, not one.** `selection one` is a phrase a recogniser hears in ordinary speech;
  `selected text one` is not. The false-positive that matters is his own sentence being eaten.
- **Separate counters per kind.** `screenshot three` and `selected text three` cannot be confused
  for each other, so sharing a counter would only make the third picture `screenshot five`.
- **Reserved under the lock that decided the highlight is new, spoken after it is released.**
  `reserveMarkerLocked` is called inside `fileSelection`'s critical section — two highlights a
  second apart can finish filing in the other order, and a number read off a list position would
  then quote the wrong paragraph — while `speakMarker` runs outside it, because the marker waits
  for a gap in his speech and `stateLock` is taken from the main queue by everything that draws
  the chip.
- **The fallback is an absence.** A highlight whose marker was found is **dropped** from
  `text selected during dictation:`; one whose marker was lost keeps the line it always had. So
  the list is exactly what it was, minus the rows that are already in the sentence — and nothing
  is ever in both places, which is the way an agent comes to believe there were two highlights.
- **The frozen selection gets no marker.** `stashSelection` runs at 0:00, before there is a
  sentence for a marker to sit inside; it is the subject and it leads the list. The one that
  arrives mid-sentence through `fillsTheBlank` goes through `fileSelection` and does get one.
- **The corpus gets neither the marker nor the paragraph** —
  `resolve(inlineSelections: false)`. Wispr's recording heard the marker and the relay's did not;
  *neither* of them heard the text he had highlighted, and a transcript filed beside audio that
  quotes a page of code is a pair whose words are not in its sound.
- **Clamped at the same 400 characters the clause clamps at**, for the clause's own reason: a
  selection can be an entire file, and this one goes into the middle of a sentence he reads back.
  The outbox keeps the whole of it, now with `selections[].marker` and `selections[].inlined`
  beside it — the one place *why is this highlight not under the sentence* is answerable later.
- **A marker spoken by `finalSelectionRead` reaches nobody.** That read files a highlight after
  the microphone has closed, so its number goes into a device Wispr has stopped listening to and
  the fallback list is where the highlight lands. It costs one number out of ten; gating it would
  mean reading a main-thread flag from the shutter's thread, which is the race `markMarker` exists
  to avoid.

The rewrite is unit-tested standalone (the `ShotMarker` half compiles against a `Log` stub):
inline substitution inside a Romanian sentence, the digit form Wispr's `pastedText` column
produces, both kinds in one sentence in order, the corpus form, a marker naming a highlight that
was never filed, and ordinary prose (`the selected text below is fine`) left untouched.

## The Dock tile restarts it (2026-09-14)

Victor: *"When I open the walkie-talkie again from the sidebar in macOS, it should restart it
rather than refocus on it. Instead of quitting and restarting, I should just click on the icon
on the left that would restart the application."*

The tile has been there since 2026-09-07 as the **escape hatch** — ⌥-click → Force Quit, the
argument that won `.regular` over `.accessory`. What it has never had is a use for an ordinary
click. The reopen it answers with is *make the app active and show its windows*, and there is
nothing here to show: the overlay is a `.nonactivatingPanel` that is already on screen whatever
is frontmost, so the default gesture is a menu bar appearing and nothing else. Meanwhile the
thing the tile is actually next to in his day — the restart after a build — was a terminal, a
script and a folder to be in.

So `applicationShouldHandleReopen` is the restart, and returns `false`: the app is on its way
out and a flash of a frontmost relay is exactly the refocus he asked to be rid of.

**It is `relay-restart.sh` from the inside, and it keeps both of that script's promises.**

- **A dictation in flight is a stop, not a thing to be got past.** The script waits on
  `GET /test/state` and then sleeps six seconds blind, because from outside the
  process that is the whole of what can be known. Inside it, the same question is exact:
  `listening || settling || phase.isWaitingForWords || overlay.isHoldingPrompt` — the microphone,
  the recogniser still answering, and the panel with a Send button under it. The click says
  `↻ restarting after this sentence` once and then waits with no ceiling, because a sentence ends
  when Victor ends it. Measured with a faked microphone: the reopen at 15:14:12 logged the wait
  and left the pid alone, and the restart went through in the same second the dictation was
  cancelled.
- **A binding is a thing to put back.** The tty cannot travel in `bound-tty` — that file is
  cleared at quit *and* at launch — so it is parked in `~/.walkie-talkie/.rebind` (beside
  `.replacing`, under `--home` with everything else) and taken exactly once by the instance that
  comes up, time-boxed at 60 s so a relaunch that never happened cannot point tomorrow's relay at
  a window he closed last night. The restore is `bind(tty:)` off the main thread with three
  attempts a second apart, `showBound` and no flight, no toggle, no flash — a binding being
  restored, not a gesture pointing at the window in front.

**`open -g -n`, not a `pkill` and a launch.** The `-n` is `main.swift`'s own relaunch argument
and it is doing the same work here: LaunchServices starts the replacement, so the privacy grants
stay keyed to the bundle identifier, and `SingleInstance.enforce()` in the newcomer stands this
instance down *and* writes `.replacing`, so `applicationWillTerminate` does not announce a
`session_end` at the agent watching the outbox. Killing ourselves first would only add a window
in which no relay is running. The `-g` is the half that is specific to this gesture: a Dock click
activates the app on the way in — the Dock's doing, not the app's — and `open` would hand the
front to the replacement as well, ending a restart with Walkie Talkie sitting in front of the
terminal he was typing in. Measured: after the restart the frontmost app was still Code, and the
`/target` route answered `bound: true, ttys018`.

The arguments travel with it, so a `--home` or `--label` instance restarts as itself.

Reachable from a desk without touching the mouse, which is how all of the above was measured:
`open "/Applications/Walkie Talkie.app"` on the running app sends the same reopen event the Dock
does. 1.3 s from the click to a re-bound relay, three times over.

## Every ring grows out of the pointer now (2026-09-14)

*"Când începe o dictare, acel cerc de fulgere să apară din mouse, să se mărească în momentul în
care începe să asculte. Tot timpul apare cât se poate de repede și apoi face un fel de zoom in…
așa cum face zoom out, se micșorează la final, se mărește din centru spre exterior când începe
dictarea, pentru o durată comparabilă cu cea de închidere."*

The bloom was built on 2026-09-12 for one case: a **bound** sentence takes a picture, `CaptureFlash`
marks the point the pointer was at, and the ring grows out of the mark the bubble just made. The
caret ring was left arriving whole on the argument that nothing marks the pointer there — which was
an argument about the *bubble*, not about the ring. What Victor is describing is the collapse played
backwards, and the collapse is the same half-second whatever the words were aimed at.

So `fromPointer: Bool` became `CaretHalo.Opening`, three cases and the difference between two of
them is only *what the bloom waits for*:

| | held at | blooms |
|---|---|---|
| `.afterFlash` | `collapseEnd`, 2 % | on `grow()`, beside `CaptureFlash.announce` — the bound and spawn sentences, in the order he asked for on 09-12 |
| `.fromPointer` | `collapseEnd`, 2 % | one main-queue hop after the panel is ordered front — everything else |
| `.whole` | full size | — the state shots, and `setActive(false)` |

`.fromPointer` could not simply reuse the waiting path: `growGrace` is 1.5 s, and a dictation with
nothing to announce would have stood as a four-point dot for a second and a half before doing
anything. It could not skip the hop either — the bloom has to start after `orderFrontRegardless`,
or the first frame on screen is a ring that is already half grown. Nothing else moved: the keyframes,
the smoothstep and `expand` (0.5 s, which *is* `collapse`) are the ones the collapse has used since
2026-09-10, so *"o durată comparabilă cu cea de închidere"* was already true and stayed untouched.

The call site is one line — `opening: (listening && !atCaret) ? .afterFlash : .fromPointer` — and it
covers the speculative ring as well, which is the one Victor sees most: a dictation he starts from
Wispr's own chord now comes out of his mouse like the rest of them. `WT_HALO_DEMO` opens
`.fromPointer` too, since that is the one run of this panel a screen recording can contain.

## The heads stay up while the words travel to the caret (2026-09-15)

Victor, at the end of a caret dictation: *"Dacă dictez la caret, după ce dictarea se oprește,
fulgerul dispare, doar că rămân săgețile care curg până când efectiv se inseră textul la caret.
Rămân săgețile … în sensul în care să-mi atragă atenția că dictarea încă se procesează și curge
spre cursor și să nu plec cu cursorul de acolo."*

It is the hole the 2026-09-13 split left, and it only exists for one kind of sentence. The ring
means **microphone open** and goes down at the stop gesture — that was the whole point of the
split, because a ring standing for twelve seconds over a sentence Wispr had already pasted into
Word was indistinguishable from a ring still hearing him. The chip took over the wait with
`Transcribing...`. Which is the right thing to say, in the wrong place: he is looking at the
cursor, not at the chip, and a **caret** sentence is the one case where where he is looking is
also *where the words are going to land*. Half a second to two seconds of nothing on screen, at
the one moment moving the mouse costs him the destination.

So the six heads — which were never about the microphone at all — stay. `CaretHalo.setDelivering`
is `settling && settlingAtCaret`, set from `syncBorrowedGestures` **before** `setActive`, because
the collapse that follows is what reads the flag to decide whether the arrow goes down with the
ring. `arrow.armed` becomes `(on && atCaret) || delivering`.

Three things had to give, and each of them is a thing that used to belong to the ring:

- **The meter stops being the driver.** `DropArrow.refresh(quiet:)` ramps the heads in over
  `patience` + `swell` — four seconds of silence — which is a question about whether he has
  stopped talking. Past the microphone's close the answer is yes and is not in doubt, and a meter
  that keeps answering must not be allowed to dim them. `hold(at:)` sets them to `ceiling` and
  `holding` makes `refresh` a no-op until `hide()`. The fade in is `recall`'s 0.18 s, not the
  swell's two seconds: the wait has already started.
- **The pointer monitors outlive the ring.** They were installed in `show()` and removed in the
  collapse's completion; `follow()` is what moves the heads, so that teardown would have left them
  standing where the pointer used to be. `releaseMonitorsIfIdle()` — `!live && !closing &&
  !delivering` — and `follow()` runs on the same three.
- **They go in a cut.** `endSettling` for this mode is the paste itself (`pasting at the caret`, a
  line before `pasteText`), so the heads vanish on the frame the words appear on, and the words are
  what replaces them. A fade there would still be asking him to stay put after the sentence had
  landed.

Nothing that rides the pointer can be screenshot, so `GET /test/state.arrowsUp` is the only way an
assertion can ask whether they are up.


## The estimate stops guessing the middle (2026-09-16)

Victor, the mirror image of the 2026-09-07 complaint: *"estimările de timp cât durează
transcrierea sunt subestimate, parcă. Revizuiește-ți algoritmul care calculează cât timp
transcrie modelul local text în funcție de lungime și încărcarea mașinii."*

The first thing the replay said is that the old line was not *wrong*. Over the 640 decodes
already in `~/.walkie-talkie/decode-rate.jsonl`, `intercept + slope × audio` fitted by least
squares to the last fifty had a median estimate/actual of **1.10** — it was, if anything,
slightly long on the typical sentence. It was nevertheless short of the truth on **40%** of
dictations, because what it fitted was the *middle* of a distribution whose spread is a factor
of 1.8 either way, and the countdown is not a symmetric instrument. The bar fills to the end and
stays there; past that point the app is claiming the words have landed. Being right on average
buys nothing, because the half of the time it is short is the half he notices.

### Two changes, both measured on the file

**The line is a median of slopes.** Theil–Sen — the median of the slopes of every pair at least
a second apart in audio, with the intercept the median of the residuals. A Whisper repetition
loop or a decode that hit a thermal wall lands in the window as one point ten times the size of
the others, and least squares hands that point the fit for the next fifty dictations.

**The answer is `line × headroom`**, where `headroom` is the 0.80 quantile of that same line's
own residual ratios over the same window, clamped to 1.0…3.0. The fit stops answering *how long
will this take* and answers *how long will this take at worst, ordinarily*.

Replayed over the same 640 decodes, sample by sample, each prediction made from only the
decodes before it:

```
                           covered   short clips   bar full early   bar unfinished   median est/actual
least squares, mean          60%         52%           0.65s            0.45s              1.10
Theil–Sen × q0.80            74%         65%           0.55s            0.63s              1.27
```

*Covered* is the fraction of dictations whose words arrived before the bar filled. Fourteen
points of it for 0.2s of average unfinished bar, and the median estimate moves 1.10 → 1.27 —
nowhere near the 4× that produced *"14 secunde și s-a terminat în 3"*. The quantile is where the
two complaints are balanced against each other: 0.70 leaves the bar filling early on a third of
dictations, 0.90 buys six more points of coverage for twice the unfinished bar, and the
asymmetric loss between them is flat, so the choice is which complaint to answer.

### The load was asked again, with numbers this time

`DecodeRate` has recorded the 1-minute run queue since 2026-09-07 and has never modelled it, on
the argument that the recent decodes already *are* the machine's current load. That is an
argument, and Victor's ask named the load explicitly, so it was re-asked as a measurement.

The effect is real: the median ratio runs **0.034×** with the run queue under 2 and **0.085×**
over 35, a factor of 2.5. And it is already inside the window, because the last fifty decodes
are the same machine in the same hours. Against the fitted line's residuals the correlation is
**0.13** with the load relative to the window's median and **0.02** with the load itself. Every
form it was tried in — a `1 + c·ln(1+load)` term on the slope at c = 0.1…0.5, a second regressor
fitted from the window, the whole fit in log space, the twenty samples nearest in load — bought
1–3 points of coverage and paid for them one for one in unfinished bar. The rule stands, and now
it stands on numbers.

### What is left is a Whisper talking to itself, and it is not predictable

Pairing `decode-rate.jsonl` against the `local whisper: ro (-0.17, cr 1.48) — 584 chars` lines
in `relay.log` gives 577 decodes with the recogniser's own reading beside them. The strongest
signal in the data is not the audio (log-log correlation **0.42**) and certainly not the load
(**0.03**) — it is the transcript's **compression ratio**, **0.49** against the decode time and
**0.52** against the line's residual. The worst under-predictions are all one animal:

```
 29.8s audio → 20.40s   cr 56.8    186 chars
 10.2s audio →  9.40s   cr 51.5    669 chars
  4.1s audio →  9.60s   cr 37.1    445 chars
```

against `cr 1.3…1.5` for an ordinary sentence. Whisper caught in a repetition loop, generating
hundreds of tokens nobody said. None of it is knowable when the row opens, so **~4% of decodes
will overrun any estimate this file can make by more than five seconds**, and raising the
quantile does not touch them: at 0.95 it is still 3%, bought with an average of two seconds of
unfinished bar on every other sentence.

So `chars` and `compression` are filed beside the seconds now — optional on `Sample`, because
six hundred lines were written before there was anywhere to put them — for the same reason the
load is: so the next person to ask has numbers rather than an argument. What they answer is *was
that a slow machine or a Whisper talking to itself*, after the fact, which is the only moment
anyone can answer it.


## The back button becomes the stop of the dictation it started (2026-09-17)

Victor: *"Atunci când dictez cu Wispr Flow, cu butonul de Back și gestul în dreapta, butonul de
Back trebuie să se transforme în a opri Wispr Flow din dictare. Să nu mai fie necesar să fac,
încă o dată, gestul de Back cu dreapta. Să fie mai confortabil. Și după ce Wispr Flow nu mai
dictează, revine butonul de back la tasta obișnuită de Enter."*

🔽 → is the one gesture that hands a sentence to Wispr Flow **raw** — `postWisprHandsFree`, the
chord and nothing else, no swallow, no Scratchpad, no routing. It is a toggle, so ending that
dictation meant making the whole flick a second time: back button down, mouse right, back button
up, with the hand already back on the keyboard. The gesture is *made with the back button held*,
which is the whole observation — the thumb is already resting on the one button that could end
the sentence on its own.

So for the length of that one sentence the back **click** is its stop. F5 arms `wisprGestureAt`,
F6 consumes it in `claimWisprStop` and posts **the same `postWisprHandsFree` chord the second
flick would have posted** — one stop, two buttons, nothing that can drift apart.

### What the arm is measured against, and why it is not `listening`

The obvious flag was the relay's own. It is the wrong one: **with the Engine on the local model
the relay is blind to a 🔽 → dictation entirely.** That gesture posts Wispr's chord raw, and with
`LocalWhisperSource` wired up nothing in this app is watching Wispr — no `WisprWatch`, no history
poll, no capture. `listening` stays false for the whole sentence. And that is not an exotic
configuration: it is the one he dictates into *other applications* from, which is what 🔽 → is
for.

So the question is asked of Wispr's microphone directly. `AppDelegate.wisprMic` is a second
`WisprWatch` with **no `onChange` at all**, started at launch whichever engine is up and sampled
from the tap thread — `sampleIsRunningInput`, three CoreAudio reads over a cached list of object
ids, safe from any thread and cheap enough to ask inside a keystroke's callback.

**`wisprSource`'s own watch could not be borrowed.** Its `onChange` drives
`edge(_:measured:)`, which sets `isRecording`, opens a capture and starts a meter — on a source
that may not be the one wired up. A sampler must answer and do nothing else.

### The two edges

- **Before the microphone opens** there is a gap: 324–674 ms warm and **5–6 s cold**, measured
  2026-09-12, the same numbers `speculativeGrace` is built on. The arm covers it with a 12 s
  grace from the chord, because the button has to work in that gap too — and a chord Wispr
  ignored altogether must not leave the back button a stop for the rest of the day.
- **After it closes** there is nothing to be told. The sample simply answers *no*, and the button
  is Return again — which is the half of the ask that would otherwise have needed an edge, a
  flag and something to keep them honest.

### And it is retired, not merely read

A reading is not an ending. The first shape had the arm going up on F5 and coming down only when
something asked about it — which is fine for the sentence he stops himself, and wrong for every
other way one ends: Wispr's own silence timeout, a ⌃Escape, the window closed. The arm would be
left standing, and the next time Wispr's microphone opened for some **other** reason the back
button would read that as its own sentence still running and stop it, with the grace long expired
and the open microphone making the check say yes regardless.

So `AppDelegate.watchBackStop` polls the sampler every 250 ms **for the length of the arm and no
longer**, and `HotkeyTap.retireWisprStop` takes it down on the first close after an open — or when
the grace expires with no open at all, which is the chord Wispr ignored. A poll rather than the
sampler's `onChange` for the reason the source's own 100 ms poll exists: the CoreAudio
notification is 0–6 s late and produced no edge at all in five of five successful runs
(2026-09-13).

### Measured on the installed build the day it shipped

Engine on the **local model** throughout, which is the case the microphone witness exists for —
`listening` read `false` for every second of every one of these, and the button worked anyway.

| | |
|---|---|
| `backStopsWispr` before any gesture | `false` |
| after `POST /test/gesture {"name":"back-right"}` | `true` |
| the back click that followed | `🎙️ ⬅️ back button — stopping the dictation 🔽 → started` |
| a **second** 🔽 → instead | logged `(the stop)` — the microphone was open, so the flick was read as the end, and the arm went down with it |
| the microphone closed by Wispr's own chord, not by a gesture | `⌨️ the back button is Return again — Wispr Flow's microphone closed` |
| the poll against the CoreAudio notification, on that run | **16:46:06 against 16:46:09** — the poll retired the arm three seconds before the notification arrived at all |

That last row is the whole argument for the poll in one line.

### Two things it deliberately does not do

- **It does not take the shutter from any other dictation.** A 🔽 → sentence is Wispr's own: the
  relay rings for it and routes nothing, so a picture taken during one has no message to attach
  to. Every relay-started dictation keeps the back button as its shutter.
- **It does not wait for the microphone's close to release the claim.** That close is a poll
  away, and a second back click inside it would post the toggle again and *open* a dictation —
  which is worse than a missing Return. `claimWisprStop` consumes the arm at the click.

`GET /test/state.backStopsWispr` says which of its two meanings the button carries right now:
the gesture is a keystroke a script can post, but what it did to the button is otherwise
invisible from outside the process.

### …and it survives a restart, because that is how it was lost (2026-09-17, evening)

Victor, hours after it shipped, asking for the feature again: *"când pornesc dictarea de Wispr
Flow cu butonul de Back și gestul în dreapta și Wispr Flow mă transcrie, trebuie să pot opri
Wispr Flow cu un click simplu pe butonul de Back."* Which is what the morning built, and the
first thing the log says is that it works — `🎙️ ⬅️ back button — stopping the dictation 🔽 →
started` at 19:25:56 and again at 19:34:41, both on the installed build, both while the Engine
was the local model. Re-running it from the desk that evening passed too: arm, click, Wispr's
row 12957 created at the chord and the microphone shut by the click.

The log also says where it went. **19:29:06 a 🔽 → dictation; 19:29:14 the app relaunched** —
eight seconds in — and the next thing in the file is a second flick at 19:30:57, a minute and a
half later. The arm lives in `HotkeyTap`'s memory, so the restart simply took it: mid-sentence,
with no sign of anything happening, the button went back to typing Return into his terminal and
the only way out was making the whole flick again. That is not a rare accident in this repo — the
Dock tile restarts the app, `build-app.sh` replaces it, `relay-restart.sh` kills it from outside,
and none of the three knows a 🔽 → dictation is running: with the Engine on the local model the
relay is blind to one, which is the same blindness `wisprMic` exists for.

So the arm is parked on disk, beside the binding and under `--home` with it —
`Relaunch.stashBackStop`, written **whenever the arm moves** rather than at the restart, because
a crash and an outside `kill` announce nothing. At launch `restoreBackStopAfterRestart` puts it
back on **two** conditions: the marker is there and younger than three minutes, *and* Wispr's
microphone is open right now. The second is what makes it safe — a marker left by an instance
whose sentence is long over finds a shut microphone and is thrown away, so the back button is
never handed to a dictation Victor started with his own keyboard. The age travels with the
marker, so the 12 s cold-start grace is not handed out a second time; past it the arm stands on
the microphone alone, which is the honest test for *that sentence is still running*. The question
is asked 1.2 s after launch, because `WisprWatch` enumerates the audio process list on its own
queue and answers *closed* until it has.

Measured on the installed build: arm at 19:41:07, `./relay-restart.sh` straight through the
dictation, `⌨️ the back button is the stop again — a restart landed inside a 🔽 → dictation
(3183 ms in)` at 19:41:11, the back click stopping it at 19:41:14, and Wispr's row 12958
`formatted`.

**And the silent branch got a line.** Every other outcome of that button says something in the
log; a Return typed over an open Wispr microphone said nothing at all, so *the back click did not
stop my dictation* had no evidence behind it and cost an evening of reading timestamps. It now
says `⌨️ ⬅️ back button — Return, though Wispr Flow's microphone is open: this dictation was not
started by 🔽 →`, which separates the two very different causes — the arm was never up, or it was
taken down under him — before anyone has to guess. Asked only on a click, so it costs the three
CoreAudio reads nothing else pays for.

## The music also pauses for a dictation the relay did not start (2026-09-18)

*"atunci când Wispr e detectat că ascultă, de exemplu, acum țin Command și Option apăsat, trebuie
să se pauzeze muzica și apoi să se rezume când încetează transcrierea, adică atunci când Wispr
oprește transcrierea. Așa cum se întâmplă pe modelele locale."*

The pause has ridden `listening` since 2026-09-03 — *the relay has a sentence in flight* — and
that covers every gesture this app owns. What it does not cover is the commonest dictation of the
day: with the Engine on the local model, Victor holds right ⌘⌥ (Wispr's own push-to-talk) to
dictate into whatever is in front of him, and none of `DictationSource`'s five events are wired to
`wisprSource` then — `wireDictationSource` only ever wires whichever source *is* the engine, and
`setEngine` nils the outgoing one's callbacks out. So the relay saw the chord, named it in the log
(`⚡ right ⌘⌥ — Wispr push-to-talk — Victor's own dictation; the ring is all the relay does with
it`), and let the track play straight through the sentence.

**The signal is `WisprState.listening`, and the choice matters.** The obvious candidate is
`wisprMic`, the always-on `WisprWatch` — one CoreAudio boolean, no state machine. It is the wrong
one for exactly the reason the machine was written on 2026-09-13: the notification is 0–6 s late
and produced **no edge at all** in five of five successful runs, and in this configuration
`wisprSource.prepare()` is never called either, so its own `watch` is not started and the 100 ms
poll has an empty process list to sample. What actually fires is Wispr's `History` row, which is
written at the gesture — measured **182 ms** on the 08:50 dictation of that morning, against a
poll and a notification that both read `never`. The phase is the join of all three, so it is right
whichever of them happens to be alive.

`WisprFlowSource.hearingChanged` publishes every edge of that phase, and it is deliberately
**not** a sixth `DictationSource` event: a dictation Victor starts himself stays Wispr's — no
screenshot, no ⌘C probe, no route — and this says only *a microphone is open right now*, which is
the whole of what the music has ever needed. It is wired once at launch beside `wrapWispr`, not in
`wireDictationSource`, because it does not belong to whichever source is wired up. `AppDelegate`
mirrors it into `wisprHearing` and `syncMusic` is the OR: `music.setActive(listening ||
wisprHearing)`. `MusicBridge` resumes exactly the tabs it stopped and drops a repeat of the
current state, so the two halves can be recomputed from either side in any order — and they have
to be, because when the Engine *is* Wispr both are true for the same sentence and they go down in
the same call stack.

**It resumes where his own dictations resume** — at the end of the `listening` phase, not when
the words land. With mic edges alive that is the microphone closing; in the ⌘⌥ case, where
nothing can see the microphone, it is the row turning terminal, which is Wispr stopping
transcribing — which is how he phrased it.

**And a ceiling, because the failure mode is silence.** The only thing that lowers `wisprHearing`
is the machine leaving `listening`, and that phase is driven by rows Wispr writes; a Wispr that
dies mid-sentence (it did, 03:53 that same night) would otherwise leave his tabs muted with
nothing on screen saying why. Ten minutes — far past the longest dictation in the corpus, 197 s —
and it logs as an error, because reaching it is a bug and not a timeout.

Measured on the installed build, Engine on the local model: `wispr state: idle → listening` →
`⏸️ dictation open — pausing audible Chrome tabs`, then `listening → transcribing` →
`▶️ dictation over — resuming them`.

### The release of ⌘⌥ is the end of the sentence (2026-09-18)

*"nu se prinde când Wispr se oprește când apas cmd-opt și dau release la taste."*

The pause landed; the resume did not. The start of a push-to-talk dictation has been read off
the keyboard since 2026-09-12 — `⚡ right ⌘⌥ — Wispr push-to-talk` — but its **end** never was,
and every other witness the relay has for *the microphone shut* turned out to be unavailable in
exactly this configuration:

- the CoreAudio notification is 0–6 s late and gave no edge at all in five of five runs (09-13);
- the 100 ms poll samples `WisprWatch.sampleObjects`, which only `start()` fills — and with the
  Engine on the local model `wisprSource.prepare()` is never called, so the list is empty;
- Wispr's `History` row is the one that does fire, but `sawRow` only leaves `listening` on a
  **terminal** status. Measured at 09:00:22 that morning: row 12978 adopted at 165 ms, then
  `raw_transcript` — intermediate — and the phase sat in `listening` from 09:00 to 09:04 with
  his music off the whole time. The 08:50 sentence had only appeared to work because its poll
  happened to catch the row already `formatted`.

The keyboard says it at the instant it happens, for nothing. `HotkeyTap` was already tracking
`wisprPTTDown` and computing the falling edge — it simply threw it away. It now reports it
(`onWisprPushToTalkReleased`), and `WisprFlowSource.pushToTalkReleased` turns it into the
ordinary `closeListening`, which is the one door every other stop already goes through: the
machine moves to `transcribing`, the capture deadline is armed, `hearingChanged` falls and the
music comes back.

**Two gates, and they are not the same gate.** `startedByHeldPair` — only a sentence this pair
*started* may be ended by it, because a ⌘⌥ pressed for something unrelated in the middle of a
hands-free sentence is ordinary. And `isRecording` — a tap too short for Wispr to have made a row
leaves the guess `speculative`, and *that was not a dictation* is a different claim from *the
sentence is over*; `speculativeGrace` owns that one and has its own words for it. No hold-time
floor is needed: Victor's `config.json` keeps `ptt` on `54+61` and the hands-free toggle on
`49+59+63`, so a release of this pair is never a toggle in disguise.

**`onWisprMaybeStarting` now carries a `WisprStart` value** (`.handsFree` / `.pushToTalk`) instead
of a `why` string and a `confident` bool. Both were derivable from the gesture, and the release
has to be paired with *its own* press — a distinction a string could only have been matched on.

Measured on the installed build, Engine on the local model, with the pair synthesised and a
⌃Escape behind it so nothing was pasted: press at 09:07:07, `listening` at 188 ms,
`⏸️ dictation open — pausing audible Chrome tabs`; release at 09:07:09,
`wispr state: listening → transcribing — right ⌘⌥ released — his push-to-talk is over (2012 ms
after the chord)`, `▶️ dictation over — resuming them`. The pause lasted exactly as long as the
hold.

## The ring comes back for the dictations he starts himself (2026-09-18)

Victor, on a morning where he had been dictating with the Engine on something other than Wispr:
*"când pornesc Wispr Flow cu gestul de mouse back sau când activez eu Wispr Flow cu tastele, de
exemplu Command Option ținute apăsate, să apară același cerc cu fulger în jurul cursorului. Fără
tooltip neapărat, dar fulgerul să arate că cineva ascultă."*

It reads as a feature request and it is a **regression report**. *The ring covers Wispr Flow's
dictations too* (2026-09-11) put `wisprDictating` in the halo's gate precisely for this — Replace
Wispr is down most days, so Wispr Flow is what he dictates into everywhere and a beacon dark for
the commonest dictation of the day is worth nothing on the rare one. On 2026-09-12 Wispr became
the **source**, and the gate was narrowed to `listening || speculative` on the reading that
`listening` now covered every Wispr dictation.

It does not. `listening` is *the relay has a sentence in flight*, which is a claim about **this
app**, not about a microphone. Three ways to be dictating are outside it, and they are not corner
cases:

- 🔽 → posts Wispr's hands-free chord **raw, in every engine** — that flick never sets `listening`;
- his own keyboard chords — fn ⌃ Space, or right ⌘⌥ held — reach the relay through
  `onWisprMaybeStarting`, which is wired into `WisprFlowSource`, so with the Engine on the local
  model or on ElevenLabs **nothing arrives at all**: the source is not wired, none of the five
  `DictationSource` events fire, and not even `speculative` goes up;
- a dictation started from Wispr's own window, which the relay never hears about by any route.

So for six days the microphone was open with nothing round the pointer to say so, in exactly the
configuration the 09-11 section was written for.

**The witness is `hearingChanged`, which already existed** — added the same morning for the music
(*The music also pauses for a dictation the relay did not start*), and it is the right one for the
same reason: it is every edge of `WisprState.listening`, wired **at launch** rather than in
`wireDictationSource`, so it survives the Engine being something else. Going back to `WisprWatch`,
which is what the 09-11 rule names, would not work — measured 0–6 s late on 09-13 with no edge at
all in five of five runs, and with the Engine elsewhere its `sampleObjects` list is never even
filled. `WisprState` joins it with Wispr's `History` row, written at the gesture: 182 ms.

The halo's gate is now `listening || speculative || wisprHearing`, and the edge goes through
`syncBorrowedGestures` — the one switch every edge of a dictation already passes through, which is
why adding a fifth reason for the ring to be up costs one term and a hop.

**And that was still not enough for 🔽 →, for a reason worth writing down.** The keyboard branch
that reports Wispr's own chords *deliberately ignores this app's own posts* — `backButtonStamp`,
2026-09-13, or `postWisprHandsFree` would hand the source its own start back as a stop a
millisecond later. So the one gesture that posts Wispr's chord raw reached `WisprState` through
**no witness at all**: no chord, therefore no row poll, therefore never `listening`, therefore no
`hearingChanged`. The stamp was protecting against the chord coming back round *through the tap*,
and the fix is to say it directly instead — `HotkeyTap.onWisprRawChord` →
`WisprFlowSource.noteRawChord(closing:)`, `relay: false` (the sentence is still Wispr's own) and
`confident: true` (this app posted the chord; there is no gesture to have misread). Measured on the
installed build with the Engine on the local model: `POST /test/gesture {"name": "back-right"}` →
`wisprHearing: true`, `ringUp: true` on the first read after the flick, `relayStarted: false`,
`backStopsWispr: true`; the back click behind it → `wispr state: listening → transcribing — Victor's
own 🔽 → (the stop)`, `◯ caret halo off`, `▶️ dictation over`, arm retired, phase `idle`.

**What is deliberately not restored is the arrow.** The 09-11 section also made `atCaret` true for
a Wispr dictation (*"Da, ca la at-caret"*), on the sound argument that Wispr pastes at the caret.
Two things have changed under it. The heads say *the words are landing here, do not move the
mouse* — a promise about a delivery, and for a foreign sentence this app is not making one; and
their schedule is silence, read off `source.meter`, which for a dictation the relay is not running
is a recorder that is not running, so what they would be reading is a **stale** number rather than
a quiet one. `foreignMic` (`wisprHearing && !listening && !speculative`) forces `atCaret` false.
Victor asked for the lightning and for nothing else — *"fără tooltip neapărat"*.

For the same reason the ring will not **breathe** for one: it pulses on `source.meter.level` and
nothing opens the relay's microphone alongside Wispr's here. It sits at rest alpha, which is
honest — *a microphone is open* is the whole of what is known about a sentence that belongs to
another app.

Two smaller things came out of it. The 600 s ceiling that lets the music back on when Wispr's
machine never leaves `listening` now calls `wisprIsHearing(false)` instead of undoing the flag and
the music by hand: it was two things to undo, it is four now, and a ceiling that forgets one leaves
a ring standing at the pointer for ever — which is the 09-15 failure the idle sweep exists for. And
`GET /test/state` answers `wisprHearing`, because nothing that rides the pointer can be
screenshot and a ring with `listening`, `speculative` and `settling` all false is otherwise
unexplainable from a desk.

## Speechmatics, and the first transcript that is written while he is still speaking (2026-09-18)

Victor sent the Speechmatics voice-agents page and asked three things in one breath: is there an
API, can the dictation be **streamed** to it live, and is the price really better than what we are
already paying. Yes, yes, and it depends on which of their products the number came off — the page
he was reading advertises **Agent STT** (their `linden-1` model, `/v2/agent`, 350 ms end-of-speech,
$0.30/h down to $0.15 at volume, launched the day before), while the ordinary real-time endpoint is
the one this app actually wants and the portal prices the Pro tier at $0.129/h. Both are under
`ElevenLabsSource`'s $0.40 (`scribe_v1`) and around or under its $0.22 (`scribe_v2`), and neither
number is worth defending to the second decimal: `WT_SM_RATE` exists so the menu row can be
corrected without a build, and **if the row and the invoice disagree the invoice is right.**

The turn-detection half of Agent STT — start of speech, end of turn, silence — is worth nothing
here and is the reason the plain endpoint won. This app already knows when the sentence is over: he
lets go of the key. What it did not know was anything at all until he did.

**What is actually new is where the work happens.** Every engine in this app so far is a round trip
*after the fact*: `ElevenLabsSource` uploads a WAV at the release, `LocalWhisperSource` hands a file
to a daemon at the release, `WisprFlowSource` waits for another application's pipeline to run at the
release. The wait he watches at the end of a dictation is that whole reading, and it grows with the
length of what he said. Speechmatics is fed as he speaks, so what is left when he lets go is the
tail — the last words, plus whatever the recogniser was holding back to see how the sentence ended.
That is a different shape of latency, not a faster server, and it is the only thing worth adding a
fourth engine for.

**It cost one new file again**, which is the third time that interest has been paid: a case in
`engine(named:)`, a row in the Engine submenu, a `speechmaticsReady` closure, a line in
`VoiceCorpus`'s tag table, and `describe()` in `/engine`. The `if` in `setEngine` that named
ElevenLabs when a picked engine had no key became a table on the way past — with two keyless engines
an `if` naming one of them is a silent failure at the next gesture.

**The plumbing was already there and that is not luck.** `MicRecorder.onBuffer` was written on
09-14 so `AudioBridge` could carry his voice to the Loopback device Wispr listens to; what it hands
out is the converted buffer — 16 kHz mono int16, markers spliced in sequence — which is precisely
what `StartRecognition` is told to expect (`pcm_s16le`, `sample_rate: 16000`). So the stream needs
no conversion, and the marker mechanism works unchanged: what is in the file is what the recogniser
heard.

**It records as well as streams, and the WAV is load-bearing twice.** `VoiceCorpus` files the audio
of every sample and a stream is not audio anybody kept; and a socket that dies mid-sentence leaves
that file as the only copy of words already said. So `die()` does **not** interrupt the recording
while the microphone is open — it records the reason and the failure is reported once, at the
release, through `DictationEnd.failed` with the audio attached, which is the case ElevenLabs
introduced this morning and the second engine has now justified.

**The one thing it gives up: the language is pinned.** Speechmatics detects a language in batch
only, so a real-time session must be told before the first word — the exact opposite of
`ElevenLabsSource`, which deliberately pins nothing because his Romanian carries English technical
words and `language_code: "ro"` would tell the recogniser that `git rebase` is Romanian. Default
`ro`, `WT_SM_LANG` overrides, and **the menu row prints the language**, both in the submenu and in
the short title: an engine that can spend all day listening for the wrong language has to say which
one it is listening for, in the place the pick is made.

**Measured against the live endpoint before the key existed** (junk key, `tools/speechmatics-test.sh
--corpus 1`): a rejected key **does not fail the handshake**. The WebSocket opens, `StartRecognition`
goes out, and the server closes with `4001 not_authorised`. What URLSession reports for that is
*Socket is not connected* — a banner that sends whoever reads it to debug the network. So the close
frame's reason is read and preferred over the transport error. That run also confirmed the framing,
the endpoint and that a corpus WAV is already in the format the API wants.

Two things are **guesses and say so in the code**: `confidenceFloor = 0.6` on the mean word
confidence (the failure it is aimed at is the wrong pinned language, which comes back fluent and
wrong, the same way a short Romanian clip read as Italian does on Scribe), and `max_delay = 1.0`
against a floor of 0.7 — a little more context punctuates better, and the flush at `EndOfStream`
means that choice does not lengthen the wait he sees. Both belong in `evals/`.

`tools/speechmatics-test.sh` streams **at the speed the audio was spoken**, which is the part worth
writing down: a WAV blasted down the socket measures the server's throughput, not his wait. It
prints partials as they arrive, then *first words N s in* and *tail N s after the release* — the
number this engine exists for — and `--corpus [n]` puts its reading beside the transcript already
on disk.

**And the thing it makes possible that nothing else here can:** partials are on, the newest one is
in `GET /engine`, and the chip still says `Transcribing…` like it does for every other engine.
Putting his words on screen as they are recognised is a change to the overlay, not to a recogniser,
and it is now one field away.

### "Poți să setezi și română, și engleză ca limbi de output așteptate?" — no, and what replaces it (2026-09-18)

Asked straight after the engine landed, and the answer is a flat no with three doors checked and
shut, so nobody re-derives it in a month:

- **One `language` per real-time session.** Not a list, not a fallback chain.
- **The bilingual packs are a fixed set of seven** — `ar_en`, `cmn_en`, `en_ms`, `en_ta`,
  `cmn_en_ms_ta`, `tl`, and `es` with `domain: bilingual-en` — and Romanian is in none of them.
  These are real code-switching packs ("speakers who switch between the languages in that pack"),
  which is exactly what he wanted; it just does not exist for his pair.
- **`melia-1`, the model that switches by itself**, does not list Romanian among its transcription
  languages and is not offered on the real-time endpoint anyway.
- **`linden-1`** (Agent STT, the model on the page he sent) supports *the same languages as
  real-time* — one at a time. Their own wording is that full multilingual is "coming soon", which is
  a roadmap, not a feature. `WT_SM_MODEL=linden-1` is wired anyway, and moves the endpoint to
  `/v2/agent` on its own, so the day it ships it is one variable.

**What actually answers the question is `additional_vocab`.** The session stays Romanian, and the
English words inside his Romanian — the part a Romanian pack is worst at, and the entire reason he
asked — are declared up front. It works in real time, Speechmatics caches it after the first session
so it does not cost start-up time, and the ceiling is 20,000 entries against their own advice of
under 1000.

**The list is built from his corpus, not from imagination.** 2,804 transcripts, 112k words, counted:
`screenshot` 191, `push` 179, `commit` 160, `skill` 158, `git` 116, `prompt` 77, `github` 72,
`java` 71, `markdown` 62, `copilot` 57, `token` 56, `tooltip` 55, `repo` 50, `dictation` 38,
`subagent` 37, `branch` 35, `pr` 31. Those are the English words that really occur inside his
Romanian, and they are the list. One measured confusion went in as a `sounds_like`: **`whisper flow`
appears 35 times against `wispr flow`'s 45** — the recognisers already write the wrong one of those
two about two times in five.

**And one candidate was thrown out after looking at it, which is the part worth keeping.**
`worship` occurs **225** times in the corpus — four times more often than `wispr` — and it reads like
a perfect mishearing to teach. It is not: the context is `worship worship worship worship …` for a
whole paragraph. That is the **local model's repetition loop**, a failure of a different engine on
one clip, and teaching a new recogniser to expect it would have been inventing a problem out of
another engine's bug. A frequency table is evidence of what was *written*, not of what was *said*.

The file lives at `~/.walkie-talkie/speechmatics-vocab.txt` and is **re-read at every dictation** —
the whole point is that a word which came back wrong is fixed by editing a line, and a list that
needs a restart between noticing and fixing is a list that stops being maintained.
`tools/speechmatics-vocab.txt` is the checked-in starter, `tools/speechmatics-test.sh` sends **his**
copy so an A/B measures what the app actually sends, and `GET /engine` answers the entry count,
because *did my edit take* is the only question a health check can settle.

## Gemini, the fifth engine — and the live-text chip that will not be built (2026-09-18)

Two things came out of the same message, and the first is a decision not to build something.

**The live transcript stays off the screen.** Speechmatics streams, so the obvious next move was
partials on the chip — words appearing as he speaks. Victor's answer: *"nu mi se pare un câștig
prea mare, din moment ce eu vreau să mă concentrez pe ce îi cer, nu să citesc ce am scris … mă va
face să mă opresc și să tot corectez ce am scris"*. That is not a scheduling objection, it is the
feature being wrong: the dictation is aimed at an agent, and a man reading his own sentence as it
lands is a man editing instead of thinking. `enable_partials` stays on because it costs nothing and
`GET /engine` is how a live session is debugged; nothing draws it, and nothing should propose it
again unasked.

**And then the actual ask:** *"un model de voice-to-text care să suporte în română și engleză bine,
cu un preț bun, rulat în cloud, care merge cu latență mică, mai ieftin decât celălalt pe care l-am
implementat deja"*. Three constraints, and each of the two cloud engines already here fails one —
Scribe detects the language and costs $0.22/h; Speechmatics is cheaper and is pinned to one
language.

### What the market actually costs, per hour of audio

| | $/h | ro + en | the catch |
|---|---|---|---|
| Groq `whisper-large-v3-turbo` | 0.04 | — | **it is the model already in `LocalWhisperSource`**, the one he found weak on Romanian |
| Gemini 3.5 Flash-Lite | ~0.035 | yes | quality on his voice unknown |
| **Gemini 3.8 Flash** | **~0.09** | yes | audio bills at the input rate, 32 tok/s |
| Groq `whisper-large-v3` | 0.111 | — | still Whisper |
| Speechmatics | ~0.13 | one language | already here |
| `gemini-3.5-transcribe` | 0.18 | yes | purpose-built STT, least likely to take an instruction |
| OpenAI `gpt-4o-mini-transcribe` | 0.18 | yes | |
| ElevenLabs Scribe v2 | 0.22 | yes, and the best published Romanian WER (3.1% FLEURS) | already here |
| ElevenLabs **Scribe v2 Realtime** | 0.39 | yes, auto-switching, 150 ms | the only one that is both streaming and bilingual — and the dearest |

### The measurement that decided it, and it was run on his own corpus

He has an `OPENAI_API_KEY` in his shell, so rather than quoting benchmarks the nearest equivalent
was run on four corpus samples that mix Romanian with English technical words — about **two cents**
of his account. What it showed, on one sample, is the whole argument for this engine:

```
pe disc        : …preluat automat de Cloud Code și de Copilot…
4o-mini        : …preluat automat de CloudCode și de Copilot…
4o-mini+vocab  : …preluat automat de Claude Code și de Copilot…   1,09 s
```

One field — the terms from `vocab.txt` in the prompt — and *Cloud Code* becomes *Claude Code*. That
is the thing Speechmatics has no mechanism for, because there is no Romanian-English pack to ask
for. So `GeminiSource` sends a Romanian instruction with the shared vocabulary appended, and
`DictationVocabulary` was lifted out of `SpeechmaticsSource` on the way: the list is a fact about
Victor, and two copies of it under two vendors' names is one copy that goes stale. Speechmatics
still gets it structured with `sounds_like`; Gemini gets the **terms only** — pronunciations handed
to a language model are two misspellings taught to it.

### The failure mode that came with it, and the gate that finally uses the VAD

The same run caught the thing to be afraid of. `gpt-4o-transcribe` — the larger model — was handed
**24.8 s** of Romanian and returned **one and a half sentences**. Not garbled, not hallucinated:
*shortened*, fluently, with nothing anywhere marking the loss. An acoustic model that cannot hear a
word writes the wrong word and he sees it; a language model that cannot follow a passage writes a
tidier version of it. Nothing else in this app can catch that — there is no confidence to fall, no
language probability to slip, and the text reads perfectly.

The obvious guard is *characters per second of audio*, and **it does not work**. Over the 2,039
corpus samples longer than six seconds: median **9.9** characters per wall-clock second, p10 5.7,
p5 **4.3**. The truncation sits at **3.1** — inside his own ordinary tail, because a man pausing to
think produces the same number. A floor that catches it fires on **3.9%** of good dictations, and a
warning that cries wolf one time in twenty-five is a warning he stops reading.

What works is dividing the pauses out. `MicRecorder.voicedSeconds` has existed since 2026-09-07 and
`whisper-and-corpus.md` has said *"the next move is a VAD gate … nothing gates on it yet"* ever
since. This is the first thing that does. Replayed through `evals/voiced-seconds.py`: **25.9**
characters per voiced second at the median, p1 12.4, and not one sample of 440 under 6. The same
truncation scores **12.7** — 5.8 s of actual voice, 74 characters, against the 222 the engine that
recorded it produced from the same audio.

So the floor is **13**: above the one failure measured, firing on **1.1%** of his real dictations
(5 of 440). It is one observed failure and not a distribution of them, and the number moves when
there are more — but it is 3.5× sharper than the obvious version, and the obvious version is what
would have shipped without the replay.

### Three smaller things, each of which would have cost a dictation

- **Thinking is `LOW`, and there is no off.** Gemini 3 Flash defaults to `MEDIUM` and **rejects**
  `MINIMAL` with a 400. On a transcription every thinking token is latency in front of a man
  standing with his finger off the key. Not sent at all to a `*-transcribe` model.
- **A 400 is retried once with everything optional stripped out** — so a model this file has never
  seen still transcribes, one round trip later, instead of failing on a field name. **Except a 400
  about the key**: Google answers an invalid key with a 400 too, and re-uploading the whole
  recording to be told the same thing is a second upload and a second second of his settle.
- **The key goes in `x-goog-api-key`, never `?key=`.** Both are accepted; one of them puts the key
  in every proxy log between here and Google.

Verified against the live endpoint with a junk key before any key existed: the model path resolves,
the body parses, 78 vocabulary terms load into the prompt, and the only thing missing is the key.

## One slow flick right is one gesture, and it cannot close what it just opened (2026-09-18)

Victor, the evening after the F10 guard shipped: *"if I hold down the forward button on the mouse
and move the mouse to the right, that gesture, if I keep moving it to the right, both starts and
then immediately ends the transcription. Can we somehow prevent this? So until I stop the right
movement. Or at least just put a two seconds minimum threshold between stopping after starting."*

The same failure as *F10 nu mai comută dictarea de două ori pe un singur gest* (2026-09-16), which
was supposed to have fixed it — and the log said why it had not: `F10 re-triggered` had never once
been printed. The 0.35 s window was wrong in two independent ways.

**It was measured against the last F10 the tap acted on, not the last one it saw.** A dropped
re-fire left `lastF10At` where it was, so a train arriving every ~300 ms went *dropped, acted on,
dropped, acted on* — the guard halved the re-fires instead of swallowing them. The window now
slides: every tap stamps `lastF10At`, dropped ones included, so the guard lasts as long as the
motion does rather than as long as one interval.

**And a third of a second was the wrong size for a flick made slowly.** The 2026-09-16 reading was
that Options+ "re-fires on the tail" of one motion — one extra tap. What Victor is describing is a
gesture engine that goes on firing for as long as the hand keeps moving, which no single-interval
guard can size correctly. 0.6 s is longer than any gap inside one continued movement and far
shorter than letting go of the button, moving back and pressing again.

**The second half is his own fallback, and it is worth having even with the window fixed.** The
sliding window is a guess about how somebody else's gesture engine behaves; `gestureStopDwellSeconds`
(2 s) is a statement about what the gesture *means* — inside two seconds of the microphone opening,
➡️ can only be the flick that opened it, arriving again. It reads `openSentenceAge`, the clock now
kept on `ownDictation` rather than on `dictating`, so it covers the speculative ring, the settle and
a caret dictation with nothing bound; a guard that counted only sentences with a destination would
still let the flick close a caret one it had just opened.

**Only the stop is guarded.** A flick that would start a dictation, the left-held bind chord, and
the mid-sentence redirect to the bound terminal are never delayed, and neither ⌘⌃D nor the ⬅️ cancel
is touched at all: a key pressed twice inside a second is a hand meaning it, and the gesture that
throws a sentence away must never be the one that waits. The price is accepted and is small — a
deliberate one-word dictation cannot be closed with the same flick for two seconds, and ⌘⌃D closes
it at once.

## The chip swaps in one frame (2026-09-18)

Victor, on the cancel: *"when, for example, it says cancelled, there is a weird animation, like some
sort of a cropping of the text just after. I think it's due to the attempt to do an animation of a
lightning or something back in the days. Stop, remove that animation and make it not flicker any
kind of. I wish I could be able to test it, but it's very fast."*

The lightning is `ChipWipe` — the 60° line with a 13 pt band of light stencilled by the text's own
pixels, which carried every chip message in and out from 2026-09-08. The cropping is its other
half: a chip that shrinks between the two messages (`🔴 Listening…` over `petclinic@main` is 23 pt
taller than `🗑️ Cancelled`) leaves the outgoing picture taller than the window it is drawn in, and
the `fadeHeight` ramp added on 2026-09-09 softened that cut without removing it. Both of those had
already been fixed once each, and the effect was still the thing he notices about cancelling a
dictation.

**So it is gone, not tuned again.** `ChipWipe.swift` (614 lines), `rememberChip`, `chipBefore`,
`wipe()`, `shootWipe`, the `WT_SHOOT_WIPE` harness in `main.swift` and `.claude/rules/chip-wipe.md`
are all deleted; `endFlash` lost its `wiped:` parameter and `snapshot` lost the `ChipWipe.cancel()`
it had to make before photographing anything. `clearFlash(animated:)` keeps its parameter as a
no-op rather than being renamed through its two call sites — it asked for a transition, and there
is no longer a transition to ask for.

**The argument the wipe was built on is not wrong; it was outranked.** A fade says *this is
ending*, a wipe says *this became that* — true, and worth 0.32 s somewhere a page is being turned.
The chip is not that place: it is an inch from what he is reading, it changes dozens of times a
day, and every one of those changes was spending a third of a second drawing attention to itself.
The one transition that never costs him a glance is the one that is over before the next frame.

**What it cost to learn**, kept here because the mechanics are re-derivable and the conclusion is
not: three iterations (instant → half-second dissolve → oblique wipe), two rounds of tuning inside
the wipe itself (the band from 26 pt at 0.90 down to 13 at 0.55; the `fadeHeight` ramp for the
clipped row), a purpose-built contact-sheet harness because the effect could not be photographed
any other way, and a rule file of twenty-odd paid-for traps. The end state is the one the app
started with. *"I wish I could be able to test it, but it's very fast"* is the whole verdict: an
effect that has to be photographed frame by frame to be judged is one nobody asked for.

## The chip says which microphone, and the menu picks it (2026-09-19)

Victor: *"Listening(E)... turns to Listening(🎙️⇒E)... (XLR) or Listening(💻⇒E)... (Mac's
microphone) or Listening(🎤⇒E)... (for the RX portable bt mic) or Listening(🎧⇒E)... (for BOSE mic),
and source should be selectable via menu too. those unavailable disabled."*

One list serves both halves — `InputDevice.known`, four entries of picture, name and the strings
CoreAudio answers with. The alternative was a glyph table beside the chip and a device table beside
the menu, which is two places to disagree about what he is talking into.

**The separator is the sentence, and it ended up a slash.** `(🎙️/E)` reads *this device feeds that
engine*, which is the one pair of facts he cannot recover by looking at anything else mid-sentence;
the menu answers both, two clicks away and behind whatever is in front of him. He asked for `⇒` and
changed it to `/` within the hour, which is the right call: `Listening` is also a progress bar that
lights a character at a time (`RelayWindow.applyEngineText`), and a wide arrow in the middle of it
made a four-character mark read as a diagram. The slash says the same thing in one narrow glyph.

**The glyph is what `resolve()` would open, not what the menu is ticking.** They come apart the
moment a cable does: a pick whose device is gone falls back to *automatic* rather than to silence,
because a dictation that records nothing on account of a setting outliving a receiver is precisely
the failure `InputDevice` was written to prevent. So the menu's top row says *what would record*
and the tick stays on *what he asked for*, and the two together say **you asked for the receiver,
you are on the built-in** — the sentence he needs when a cable has come out. The mark is re-read at
every `dictationBegan` for the same reason.

**The list is the four he named, and that is a decision.** This Mac answers `kAudioHardwarePropertyDevices`
with fifteen inputs, eleven of them virtual — Loopback's `🎙️TO Zoom`, `🎓 TO Wispr`, `🔊FROM Zoom`,
Wave Link's two, Zoom's, Teams', Webex's, Iriun's. A menu offering all of them would be a device
chooser, which System Settings already is and does better; what it would not be is readable at a
glance while he is teaching.

**`Automatic` had to stay, and to be the default** — in a workshop the only thing he does is plug
something in, and a picker with four rows and no automatic would have retired that rule without
anybody deciding to. What it *means* changed the same evening: *"the preference of mic to use is:
XLR>DJI>BOSE>MAC … order them like this in menu and impl autoselection"*. So automatic is now a
**ladder** — 🎙️ XLR ▸ 🎤 DJI ▸ 🎧 Bose ▸ 💻 built-in, the first one that is here — and it
supersedes *The DJI receiver is the microphone whenever it is plugged in* (2026-09-01). That rule
was written on a desk with one microphone on it; it cannot say anything about a desk with the XLR
*and* the receiver, which is his ordinary desk. The ranking is quality and not convenience: a
condenser through a preamp, a lavalier on his collar, a headset, and then a microphone two feet
away across a desk with a projector fan in the room.

**One array is the order in both places.** `InputDevice.known` is the menu's rows top to bottom and
the ladder `resolve()` walks, and the `Automatic` row spells the ladder out with the same four
glyphs. A menu ordered differently from the automatic pick would teach the wrong preference every
time he opened it — and the `Automatic` row would be the one place in the app where *what it does*
was a thing to remember rather than to read.

**The system default is the last line of defence and deliberately not a rung.** It is consulted
only when none of the four is on the desk: macOS points it at whatever last claimed it, including
the eleven virtual devices here, which is the failure `InputDevice` exists to stop being normal.

**Matching is on name *and* manufacturer**, which the DJI taught (product `Wireless Mic Rx`, brand
only in the manufacturer string) and the Elgato confirms from the other side: `Wave XLR` is the
product, `Elgato Systems` the maker, and the `Wave Link MicrophoneFX` / `Wave Link Stream` virtual
devices its driver installs are made by `Corsair Memory, Inc.` — so neither needle reaches them.

**A pick is never refused mid-sentence**, unlike the engine. Switching recognisers rewires five
callbacks under a sentence in flight; `InputDevice.select` is read once, at `MicRecorder.start`. So
the pick lands on the next sentence and cannot disturb this one — which is also the honest
behaviour, because the words already spoken really did come through the old device. The flash says
so: `🎚️ 🎙️ Elgato Wave XLR — from the next sentence`.

**The honest caveat, which is written in the code and not only here:** with the Engine on Wispr
Flow the glyph names the device the *relay's* recorder is on — the one feeding the level meter and
the voice corpus — while the words come from Wispr's own microphone, chosen inside Wispr and pinned
to a Loopback device on this Mac. The four pictures are true for the four engines that record for
themselves.

**The states page pins the mark**, `(🎤/W)`, for the reason it already pinned `(W)`: `resolve()`
answers with whatever is plugged into this Mac when the shooter runs, and an unpinned page would
change its `Listening…` pictures every time a cable moved.

**And it shipped cut in half, which is the part worth writing down.** Victor, an hour later:
*"the tooltip next to mouse only shows now Listening(🎙️/"* — the state route answered with the
whole string while the chip drew `Listening(🎙️/` and stopped. Two old traps in this file, both
about the same thing, neither of which this row had been made to follow:

- **The row is measured with `measure(_:font:)`**, which knows one font and cannot answer for a run
  that is a picture. On the real chip: **158** asked for, **161.5** drawn. A label 3.5 pt short does
  not clip 3.5 points off the end — it drops the whole tail, engine letter, brackets and dots.
- **A colour emoji went in as a *character***, where the ✨ ten lines above it in the same function
  goes in as an image precisely because a raw emoji in a haloed label is the failure that once cost
  the spawn row its entire word.

So the glyph is now `Glyphs.emoji` → `inline`, cached per character (`wordGlyphs` — the ramp reads
it fifteen times a second and that function scans a 72 pt render pixel by pixel), and both rows that
ask *how wide is this* now ask the label. `rowWidth` is deleted: its last caller was this row, and a
helper that measures plain text with one font has no business near a string that carries pictures.
The glyph stays **fully lit** through the ramp — a picture has no unlit state that reads as *not
yet*, and dimming it by alpha is the halo problem the opaque grey `dim` exists to avoid.

Verified against the real device list on his desk, through `POST /test/mic` (the same call the menu
row makes) and by reading the rows back out of AppKit (`GET /engine.mic.rows`, which exists because
a menu is the one surface here that cannot be photographed from a shell): `xlr` → `🎙️ Elgato Wave
XLR`; `rx` and `bose`, neither plugged in, fall back and come back `disabled` in the menu; `auto`
→ the XLR, because it is the first rung that is present. The chip itself by snapshot.

## The pictures are clean, and it is a measurement now (2026-09-19)

Victor, by mail: *"Când Walkie Talkie face film sau poză, legat sau nelegat, în poza aceea
trebuie să nu apară nici tulipa mouse-ului, nici lanțul de fulgere, nici orice alte săgeți care
ar mai fi fost pe ecran din partea lui Walkie. Trimite-mi o dovadă, o poză făcută care să arate
că nu sunt artefacte de la Walkie."*

The guarantee was already there and already guarded — `sharingType = .none` on every window,
`evals/test_capture_decorations.py` counting the windows a file makes against the lines it sets.
What was missing is the half a source scan cannot reach: **a file, measured**. And one path had
never been measured at all. `ScreenFilm` does not shell out to `/usr/sbin/screencapture`; it
calls `CGDisplayCreateImage` in-process, which is a *different capture client*, and nothing said
the window server honours the flag for that one on this Mac.

So `evals/capture-proof/` is a run, not an argument. Four scenes — three unbound, one bound to a
throwaway `ttys002` — each with a page of text in Chrome, one word selected by script (a real
browser selection: `document.body.focus()` first, or Chrome paints nothing), the pointer parked
on that word, and a dictation opened through `POST /test/dictation/start` so the halo, the ring
and the chip are all up. `◯ caret halo on` precedes `context screen captured` in the log every
time. Then four frames: the app's own (`ScreenCapture.grab`, the same call the 🔽 shutter makes)
plus its 800 px handover copy, an independent `screencapture`, a 20-frame `WT_SHOOT_FILM=4`
recording, and a control taken seconds earlier with nothing open.

**Zero ring pixels, zero chevron pixels, zero cursor-mark pixels** in a 1200 px box around the
pointer — in all of them, bound and unbound. The halo's ring is r=105 pt = 210 px, so that box
holds it three times over, and the same two masks over the app's own `WT_SHOOT_HALO` render
count 179 683 and 1 537: a zero read against a number that is not zero. The reading that needs
no colour model at all is better still — **the app's shot differs from the control in 0.0% of
its pixels, 0 changed regions**: the frame taken with everything up is the frame taken with
nothing up. The film frames differ in 0.03–0.07%, 8–10 regions, every one the menu-bar clock, a
menu-bar extra or a tab favicon, none within 600 px of the pointer.

**The thing that *is* in the frames belongs to Victor Addons.** hands-off draws four 🔒, an
amber frame and a cursor badge, and sets no sharing type, so anything shot while the locks are
up carries them — and a reader would file them under Walkie. The harness therefore takes its
control frame five seconds after the last release, and the only input it synthesises is the
pointer move. It is also why the shutter itself is never posted as a chord in this run: the
`00` context shot is taken over HTTP, and it is the same `ScreenCapture.grab` the 🔽 picture is.

### The second question: does an agent know which word (2026-09-19)

*"dovedind cu eval ca un agent intelege reliable despre ce cuvant e vorba … Poate ar fi chiar
util să le dăm separat poza decupată de ansamblul complet al paginii."* 24 runs, four words,
three conditions, two repeats, answers graded on two things because three of the four words
appear **twice** in their own paragraph with the highlight on the second.

| condition | right word | occurrence pinned |
|---|---|---|
| the whole screen, 800 px | 8/8 | 4/6 |
| the wheel-drag crop alone | 8/8 | 6/6 |
| both files together | 8/8 | 3/6 |

**The word is never the problem.** 24/24, even from the 800 px handover copy of a 3456 px
screen — the text survives the downscale better than the 4 px cap-height suggests. What the crop
buys is *which one*: handed the page an agent quotes the sentence, and the sentence holds both
occurrences; handed the crop it quotes the lines it was given. **Handing over both was worse
than the crop alone** — the page invites the wider quote back. Small sample, and the direction
is the opposite of the obvious one, which is the only reason it is worth writing down: the crop
is not a cheaper page, it is a narrower question.

No frame of his screen is committed with the harness — this repo is public.


## A box round it, with nothing selected (2026-09-19)

Victor, straight after the eval above: *"Dar dacă nu selectez text, ci doar drag wheel în jurul
unui paragraf sau propoziție, înțelege agentul ce text e vorba? Din poză adică."* Every
condition of `capture-proof` had a **highlight** in the frame, which is a blue rectangle telling
the reader where to look. Take it away and the only thing that says *this text* is the box the
wheel left behind — which does not exist in the picture at all: it is four numbers in the file's
name.

`evals/pointing-proof/` is that question, 96 runs, four scenes, one target **sentence** each and
never the first of its paragraph. The page is rendered headless at 1728×1117 @2× — 3456×2234,
the geometry the capture eval ran on — so nothing of his desk is in the directory.

| condition | runs | right sentence | right place |
|---|---|---|---|
| the whole screen at 800 px, rectangle in the name — **what ships** | 28 | **21/28** | 22/28 |
| the same, with both frame sizes and the scale factor spelled out | 12 | 7/12 | 7/12 |
| the same, with the full-resolution original beside it | 12 | 10/12 | **12/12** |
| the screen **and** the framed region as a second 800 px file | 16 | **15/16** | 15/16 |
| the region alone, 800 px — what the app did before 2026-09-14 | 28 | **28/28** | 28/28 |

**Yes, three times in four** — and the quarter that misses mostly misses by a *paragraph*: six of
the seven wrong answers quote another block of the page, not a neighbouring sentence. Against the
crop's 28/28 that is p = 0.006, and p = 0.001 pooling the two conditions that hand over nothing
but the 800 px screen.

**The cause is arithmetic the reader has no pixels for.** `tagArea` measures the rectangle off
the full-resolution JPEG (3456 wide) and the file that travels is the 800 px copy, so every
reader rescales by 4.3× by eye, onto text whose cap height is four pixels: *"mapped the dragged
rectangle's full-res coords to the small screenshot by scale … landing on the last two lines of
paragraph 3"*, and paragraph 3 was not the one. **Saying the scale out loud does not fix it** —
the `sized` row hands over both sizes and the factor and scores 7/12. It was never the
arithmetic.

**What fixes it is pixels**, and the cheap version keeps the 2026-09-14 semantics: the screen as
it is, *plus* the framed region as its own 800 px file. 15/16, at 550 tokens, with the display
still in the envelope so *"in zona aia să apară ceva"* is still sayable. The full-resolution
original gets *right place* to 12/12 but costs a 3450-token read and only when the agent thinks
to take it. Neither is built — the pointing-versus-cropping call is his.

**And one limit no format reaches:** a rectangle over wrapped text selects a band of *lines*, not
a sentence. Scene 2's box was located exactly by both runs that then missed — *"it tightly bounds
this paragraph's four lines, no more, no less"* — and they quoted the paragraph, which is what the
box really contains. For a sentence inside a paragraph the highlight is still the instrument.


## The region he framed travels at its own size (2026-09-19)

The measurement above ended with a recommendation and no code. Victor read it and picked the
option: *"Trimite atât ecranul original + 800px ca până acum, dar și selecția originală decupată
(nescalată)."* So a wheel drag now writes **three** files instead of two:

| file | who it is for |
|---|---|
| `shot-1-00:04(area-928x877-to-2528x1357px).jpg` | Victor — the display, retina, as `screencapture` made it |
| `…-small.jpg` | the agent — 800 px, *where* the region is on the screen |
| `…-zoom.jpg` | the agent — *what it says there*: that rectangle cut out, **not scaled** |

- **The cut comes out of the frame, not out of a second capture.** `screencapture -R` again is
  200 ms later and photographs a screen that has had time to move; cropping the JPEG already
  written is the same instant by construction. It costs a decode and a re-encode — the ~100 ms
  the burned-in cursor mark was removed from `grab` for — and that is affordable here only
  because `fileArea` runs on a background queue with the crop panels already down.
- **No `-small` for the cut-out.** It is the unscaled copy or it is nothing, and
  `handover(for:)` already falls back to the file itself when no small sibling exists, so the
  clause lists it as it is. The ceiling is the reader's own: any image is fitted to 2000 px
  before it is charged for, so the worst a zoom can cost is a retina desktop's ~3450 tokens,
  and a band of text is 400–900.
- **One drag is still one picture.** The zoom is a sibling found by name, exactly like `-small`:
  not in `paths`, not in `📸 ×N`, not counted by `prune` (which now drops both siblings with
  their frame). In the clause it is an **indented** row under its frame — a flat list of two
  reads as two shots and puts the `[shot N]` enumeration out by one.
- **Two sentences in the clause had to move.** The area line said the rectangle was *in that
  picture's own pixels*, which is false for the 800 px copy the reader is actually holding; it
  now says *in the pixels of the full-resolution frame*, and adds *its `-zoom` is that rectangle
  cut out at full size: the screen says where, the zoom says what*. The width note gains *a
  `-zoom` is the exception: it is not scaled at all*, because a reader told everything is
  ≤800 px and handed a 1600 px band has been lied to about the one file that matters here.
  (The `sized` condition measured that better wording does not *fix* the addressing — but a
  sentence that is wrong is still worth correcting.)
- **`POST /test/area` is new, and it is why any of this could be checked.** The gesture needs a
  held middle button and a hand that moves: `/test/gesture` posts chords, and the overlay's own
  selection is driven by events the tap swallows, so the three files were reachable only by
  making the drag. The route enters at `fileArea` — below the crop UI, above the naming, the
  cutting, the marker, the attachment and the chip's count — and answers `frame` · `handed` ·
  `zoom`. `fileArea` takes a rect and a screen now instead of the module's `Selection`, whose
  memberwise initialiser is internal to `victor-mac-kit`.
- **Measured on the running build**, `evals/test_envelope.py::AreaFrame`, 5/5: an 800×240-point
  drag came back as `area-928x877-to-2528x1357px`, a `-zoom.jpg` of exactly **1600×480**, a
  handover copy of 800, one indented row under its frame, both new sentences in the note, and
  one picture in the outbox.
- **Two older classes in that file are red and were before this change** — `EnvelopeShape` and
  `SelectionMarkers` both fail their `setUpClass` with *the dictation never reached the outbox*,
  with this change's class not running at all. They are about the marker rewrite, which moved to
  timestamps earlier the same day: `/test/dictation` enters below the recogniser, so there are no
  `words[]` to place a cue against and the inline `(screenshot: shot#01)` those tests assert can
  no longer be produced by that route. Left alone here; it is the marker change's tail, not this
  one's.


## The envelope becomes tokens where he made them (2026-09-19)

Victor sent the template himself, in full, and asked two things of it: *"Is it clear what I mean?
… evaluate to see whether even a Sonnet model can understand what the symbols in this
transcription mean"*, and *"the end goal, as you can tell, is to reduce the amount of clutter at
the end of the dictation and those footers"*.

**What it says, in one line:** every attachment becomes a bracket standing at the word he made it
at, and the footer stops being prose about pictures and becomes a legend keyed by those brackets.

```
[📸0🖱️@1000:800] Uite pagina asta. [📸1🖱️@2400:1180] Linia asta e problema,
[selected: "…" from app Google Chrome] și vreau să o rescriu. [📸3✂️900,345→2594,574]
În zona asta trebuie să apară un tabel. [chrome-selection-1: Notes on latency budgets]
Titlul rămâne. [🎦1⏺️] Uite cum se derulează, [🎦1⏹️5s] gata.

[Dictated in RO or EN]
[=$WALKIE_SHOTS/2026-09-19-17-32-15]
[📸0 = 📁/screenshot-0-800px.jpg at 800px width, or -original.jpg at 3456x2234px]
[📸3✂️ = user-selected area between corners (x,y) (900,345)→(2594,574) at
 📁/screenshot-3.jpg; also available -800px and -original.jpg]
[chrome-selection-1 = div.wrap > h1 at https://interact.victorrentea.ro/notes]
```

### The eval he asked for, before the code

`evals/envelope-symbols/` — one scene with six attachments, real files on disk under the names
each envelope uses, eleven questions a reader can only answer by understanding the markings
(*which file shows only the region I framed; where was my pointer at 📸1; which screenshot was
automatic; how long did the recording run; what does `-original` mean*). Three envelopes × two
models × three repeats.

| envelope | chars | Sonnet | Opus |
|---|---|---|---|
| what shipped before | 1810 | 30/33 | 32/33 |
| **Victor's template** | **925** | **33/33** | **33/33** |
| the same with the derivable rows collapsed into one convention line | 763 | 32/33 | 33/33 |

**Even Sonnet reads the symbols perfectly, and it reads them better than the prose they
replaced** — at half the characters. The three the old envelope lost are `-original`'s
resolution, which it never stated. The shrunk variant is 18% smaller again and cost Sonnet the
one question that is *inferred* rather than said (which frame was automatic), so **his exact
template ships**.

Both models, in every run, volunteered the same two things in the `unclear` field, and both are
worth acting on:

- ***which one is automatic* is inferred**, from 📸0 having no press behind it. It is right every
  time and it is still a guess. Five characters fix it if he wants them: `[📸0🖱️@1000:800 auto]`.
- **a gap in the numbering reads as a lost picture.** The sketch jumps 📸1 → 📸3 and every single
  run remarked on it. So the implementation numbers the pictures **consecutively as they attach**:
  0 for the context frame, then 1, 2, 3.

### What the code does now

- **The file names are Victor's**: `screenshot-<n>-800px.jpg` (what travels), `-original.jpg`
  (his), and for a drag `screenshot-<n>.jpg` — the region, unscaled, from yesterday's change.
  The pointer, the rectangle and the offset are **out** of the names; they are in the tokens.
- **The number is the file's and the token's, one digit**, reserved at the gesture
  (`reservePicture`) and unconditional — it names a file whether or not a marker can be placed.
  `ScreenCapture.number(of:)` reads it back off the name.
- **`ShotMarker.Token` is the whole vocabulary**, and `render` became a lookup: the tokens are
  built where the facts are (the pointer, the corners, the application) and `ShotMarker` decides
  only *where they go*.
- **The context frame leads the words** rather than riding a cue — he took it by starting to
  talk, so there is no gesture to measure. `±` in his sketch: absent at the caret, where this
  mode has never taken one.
- **`[Focused window: …]` is gone** (his template has no slot for it) and the language hint is
  four words. The folder is said **once**, as `📁`, and only when something is in it.
- **A token the words could not carry keeps its row and gains the clock** (`… at 0:08`). That is
  every Wispr dictation: placement needs word timings, which only the engines that own their own
  recording return.

### Measured on the running build

`POST /test/area` + the shutter + `/test/selection` + `/pick` + `/test/dictation`, read back off
the outbox:

```
[📸0🖱️@2634:1674] [selected: "public Order placeOrder(Cart cart) {" from app Walkie Talkie] uite aici …

[Dictated in RO or EN]
[=$WALKIE_SHOTS/2026-09-19-19-06-06]
[📸0 = 📁/screenshot-0-800px.jpg at 800px width, or -original.jpg at 3456x2234px]
[📸1 at 0:01 = 📁/screenshot-1-800px.jpg …]
[📸2✂️ at 0:03 = user-selected area between corners (x,y) (928,877)→(2528,1357) at 📁/screenshot-2.jpg; …]
[chrome-selection-1 at 0:05: "Notes on latency budgets" = div.wrap > h1 at https://…]
```

`evals/test_envelope.py` (AreaFrame + FrameList, 10 cases) and `evals/test_marker_place.py`
(10 cases) both green against it.

### What is not done

- **The screen recording keeps its own clause and its old file names.** `[🎦1 = …]` is keyed like
  the rest, but `ScreenFilm` still writes `film-<stamp>/sheet.jpg` and `frame-NNNN.jpg`, and there
  is no `[🎦1⏺️]` / `[🎦1⏹️5s]` in the words — the start and the stop would each need a cue, which
  is a change to the recording gesture rather than to the envelope.
- **`-2` is appended to the base, not the suffix** (`uniqueBase`): every dictation in a session
  folder makes a `screenshot-0`, so `screenshot-0-2-original.jpg` / `screenshot-0-2-800px.jpg`.
  A `-original-2` would have broken the sibling arithmetic the whole naming rests on.


## ElevenLabs is the engine, and the freeze that found (2026-09-19)
### The second door, closed — and the live path, run (2026-09-20)

The freeze had two doors and only one was shut that night. The other is
`RelayWindow.startWarmth`'s 15 Hz ramp, which reads `MicRecorder.voicedSeconds`
**on the main thread** — and that property was the one meter reading that took
`lock` rather than trying it, while `start(to:)` holds `lock` across the whole
device open. So a wedged CoreAudio froze the app through the ramp even after the
open itself had moved off the main thread.

`voicedSeconds` now uses `lock.try()`, which is the shape `level` and
`quietSeconds` beside it have had all along; a contended read returns the last
value instead of waiting. It costs 64 ms of a ramp that fills over seconds, and
it buys the rule worth having: **no UI thread ever waits on a device open.**

**And with the audio stack recovered the next morning, the live path Victor asked
for ran for real** — macOS's Romanian voice through the speakers, the relay's own
microphone, ElevenLabs, gestures posted as chords while the sentence was being
spoken (`evals/envelope-live/run.py`):

```
[📸0🖱️@2204:510] Uite ce am pe ecran acum. În zona [📸1✂️760,794→2160,1234] asta vreau să apară un buton nou, la fel ca celelalte
```
```
[📸0🖱️@2204:510] Butonul ăsta [📸1🖱️@2204:510] și cel de aici [📸2🖱️@2204:510] trebuie [chrome-selection-1: Salvează] să arate la fel. Schimbă-le pe amândouă.
```

Two shutter presses and a Chrome pick, each standing where the press fell,
placed off Scribe's own word timings (`⏱️ marker cue: shot 1 at 2.46s into the
recording`, `shot 2 at 4.05s`). The one thing to know about the placement is
visible in the first: a press lands between the two words nearest it, so *"În
zona [📸1✂️…] asta"* rather than after *asta* — a word's width, not a clause's.

**Still open, and the same class**: `LocalWhisperSource`, `SpeechmaticsSource`
and `GeminiSource` open the microphone inline on the main thread. They are picks
rather than the default, so they are not on the path a wedge would take first.


Victor, on the same thread as the template: *"Wispr Flow nu mai e motorul meu de dictare default.
Reține asta; o să trec la 11 Labs. Wispr Flow va rămâne motor de dictare atunci când vreau să
dictez o idee, nu un prompt, cu gestul acela de back plus dreapta. … M-a mulțumit calitatea, atât
în română, cât și în engleză, și știe și să pună timpii pe cuvinte. Lucru foarte important."*

The timings are the load-bearing half: the tokens the envelope was rebuilt around
(`[📸1🖱️@…]`, `[selected: …]`) can only stand where he pressed if the recogniser says where every
word was, and Wispr cannot. So the default moves, `engine(named:)`'s fallback moves with it (a typo
now picks the default rather than a third engine), and the rule that said *never the default, the
one engine that uploads must not be reachable by a typo* is **spent rather than repealed** — he has
chosen the wire, knowingly, for something it buys.

### The first gesture froze the relay, and that is not the engine's fault

It froze three times before the cause was clear, and each time it looked like a crash: no crash
report, no `session_end`, the HTTP port accepting connections and never answering. `sample` on the
wedged process says it in one stack:

```
AppDelegate.startDictation → ElevenLabsSource.start()
  → MicRecorder.start(to:) → -[AVAudioEngine inputNode]
    → AVAudioIOUnit_OSX::BindToDeviceInternal → AUHALOutputUnit setDeviceID:
      → CoreAudio HALC_ProxyObject::HasProperty → mach_msg      (never returns)
```

**CoreAudio was wedged for input binds on this Mac that evening** — a second session was driving
the Loopback device for a batch job — and `MicRecorder.start(to:)` is a synchronous device open. On
the main thread. So the bind that never came back took the menu, the overlay, the routes and every
gesture with it.

- **Wispr never hit this** because it does not open the microphone to dictate; only the halo's
  meter does, and only while a Wispr dictation is already running. The moment ElevenLabs became the
  default, the very first gesture of the day went straight into it.
- **`WisprFlowSource` had already solved it** — `meterQueue`, with the comment *"`MicRecorder.start(to:)`
  is a synchronous device open and it was being run on the edge, in front of the ring"*. The three
  sources that own their recording never got the same treatment, because none of them had ever been
  the default.
- **`ElevenLabsSource` now opens, stops and cancels on its own `audioQueue`**, and `start()` answers
  immediately — which is this repo's own rule anyway (*the dictation opens on the gesture, the
  microphone only confirms it*). Verified against the still-wedged audio stack: the gesture starts a
  dictation, the ring goes up, the context frame is taken, and **the app stays answering**.
- **A second path is still there and is not fixed**: `RelayWindow.startWarmth`'s timer reaches the
  meter on the main thread, and with the audio stack wedged it froze the app the same way once the
  first path was off it. `LocalWhisperSource`, `SpeechmaticsSource` and `GeminiSource` open inline
  too. Same bug, three more doors.

**The lesson worth keeping**: a device open is IPC to another daemon; it can hang for reasons that
have nothing to do with this app, and it may never be on the thread the app is drawn on.

### Seeing the envelope without a microphone

With the audio stack down, the template's samples had to come from somewhere. Two small additions
to the loopback surface, both permanently useful:

- **`POST /test/dictation {"words": […]}`** — the transcript *and* the timings a recogniser would
  have returned, so `ShotMarker.place` runs for real instead of being skipped.
- **`POST /test/dictation/start {"clock": true}`** — a wall-clock marker clock for the run, since
  with no recording open there is no ruler for a press to be an offset into and every cue is
  dropped.

`evals/envelope-live/samples.py` is what they are for: macOS's Romanian voice speaks the sentence
into a WAV, **ElevenLabs Scribe** transcribes that WAV (real text, real `words[]`), the gestures are
made at chosen seconds through the real routes, and the relay renders the envelope. ElevenLabs' own
text-to-speech would have been the better voice and is not reachable — this key is scoped to
speech-to-text (`missing_permissions: text_to_speech`).

Three of them, rendered by the running build:

```
[📸0🖱️@2634:1674] Uite ce am pe ecran acum. În zona asta [📸1✂️760,714→2280,1194] vreau să apară un buton nou, la fel ca celelalte

[Dictated in RO or EN]
[=$WALKIE_SHOTS/2026-09-19-19-46-15]
[📸0 = 📁/screenshot-0-800px.jpg at 800px width, or -original.jpg at 3456x2234px]
[📸1✂️ = user-selected area between corners (x,y) (760,714)→(2280,1194) at 📁/screenshot-1.jpg; also available -800px and -original.jpg at 3456x2234px]
```

```
[📸0🖱️@2634:1674] Butonul ăsta [chrome-selection-1: Salvează] trebuie să fie verde, nu albastru

[Dictated in RO or EN]
[=$WALKIE_SHOTS/2026-09-19-19-46-15]
[📸0 = 📁/screenshot-0-3-800px.jpg at 800px width, or -original.jpg at 3456x2234px]
[chrome-selection-1 = div.toolbar > button.primary at https://petclinic.victorrentea.ro/orders]
```

Note what the footer does **not** say in either: no `at 0:03`. The clock appears on a row only when
its token could not be placed in the words — which is every Wispr dictation, and no ElevenLabs one.


## Two engines out, and a folder per dictation (2026-09-20)

Three things, all his, all small to say and none of them cosmetic.

### Speechmatics and Gemini are gone

*"Renunță la Speechmatics și `GeminiSource`. Scoate-le din cod pt moment."*

Removed **whole**, the way the Wispr database path went in August: `SpeechmaticsSource.swift`
(795 lines), `GeminiSource.swift` (532), `tools/speechmatics-test.sh`, `tools/gemini-test.sh`,
`DictationVocabulary.swift` — which existed only for those two and had no callers left the moment
they went — their two menu rows, their `engine(named:)` cases, their `(S)` / `(G)` chip letters,
their corpus tags, their `/engine` blocks and their thirteen `WT_SM_*` / `WT_GEMINI_*` switches.
1,327 lines of source and two tools, in one commit, so `git show` on it is the whole of what
bringing either back would take. Everything measured about them stays in this journal: the
bilingual-pack dead end, the `4001 not_authorised` close frame, the truncation Gemini's prompt was
gated against with `voicedSeconds ≥ 13`.

**A side effect worth naming**: two of the three remaining main-thread microphone opens went with
them. `LocalWhisperSource` is the only one left, and it is a pick, not the default.

### `[📁=…]`, not `[=…]`

*"N-ar trebui să fie `[📁=$WALKIE_SHOTS/…]`?"* — yes. Every row under it spends the symbol
(`📁/screenshot-0-800px.jpg`) and the line that **defines** it was the one line not carrying it.
One character, and the legend is closed.

### One folder per dictation, which is the real answer to his last question

*"Și în mesajele ulterioare se termină cu … după numele pozei în loc de -original. Cum se prinde
sesiunea de restul?"*

What he was looking at was `screenshot-0-2-800px.jpg` in the second envelope of a session. Every
dictation numbers its pictures from `📸0`, the session folder held all of them, so the second
sentence collided with the first and `uniqueBase` hung a `-2` in the middle of the name — a
disambiguator with no meaning to anybody, inside a name whose whole job is to be read, and the
`-original` sibling then reads as `screenshot-0-2-original.jpg`, which is exactly the confusion in
his question.

The fix removes the collision instead of labelling it: **`shots/<session>/<dictation>/`**,
`Outbox.dictationDir(start)`, stamped `HH-mm-ss` from the moment the sentence opened. Every
picture in it is `screenshot-<n>` with nothing appended, for ever, and `📁` in the envelope now
means *this sentence's artifacts* — which is what the one `[📁=…]` line was always trying to say.
A shutter with no dictation around it still writes into the session folder, where such a picture
has always gone.

**`prune` had to learn the new depth in the same commit**, or the 300-frame cap would have counted
nothing and deleted nothing — the identical trap `film-<stamp>/` fell into and has a warning about
two hundred lines up. It walks sessions *and* their dictation folders now, with `film-` skipped
because `pruneFilms` owns those.

Verified on the running build, two dictations one after the other in the same session:

```
[📁=$WALKIE_SHOTS/2026-09-20-10-18-28/10-18-34]
[📸0 = 📁/screenshot-0-800px.jpg at 800px width, or -original.jpg at 3456x2234px]

[📁=$WALKIE_SHOTS/2026-09-20-10-18-28/10-18-43]
[📸0 = 📁/screenshot-0-800px.jpg at 800px width, or -original.jpg at 3456x2234px]
```

Two `screenshot-0`s, no `-2` anywhere, and the session is the parent of both.
`evals/test_envelope.py` (AreaFrame + FrameList, 10 cases) and `evals/test_marker_place.py` (10)
are green against it.

### The silent `nil` that swallowed a dictation, and the whole-envelope samples it was hiding

He asked for something small — *"vreau un exemplu cu o dictare care are și text, nu doar poză …
parcă impresia este că ce mi-ai trimis sunt doar footere"* — and it was small: `evals/envelope-live/`
already speaks a Romanian sentence through the speakers, records it on the relay's own microphone,
transcribes it with Scribe and posts the gestures mid-sentence. Running it is the whole job.

It came back with no words in it at all, three times, and the way it failed is worth the section.

**What the first run produced** was not an envelope but three *shot-only* messages, with the shot
number reading `📸2026`:

```
[📁=$WALKIE_SHOTS/2026-09-20-10-18-28]
[📸2026✂️ = … at 📁/screenshot-2026-09-20-10-37-01.jpg; …]
```

That number is `ScreenCapture.number(of:)` reading the year out of a timestamped name, and the
timestamped name is what a shutter with **no dictation around it** is called. So the pictures were
real and the sentence they belonged to had never opened.

**The first cause: `listening` is sticky, and `startDictation` returns on it silently.** A run of
`evals/test_envelope.py` at 10:18 left `listening = true` with no recorder behind it — that file's
own docstring said so and called it harmless (*"./relay-restart.sh clears it"*). It is not
harmless. `guard !listening, !source.isRecording, !speculative, !settling else { return }` is the
first line of `startDictation`, and that `return` writes nothing anywhere. For twenty-one minutes
every 🔼→ posted its chord, logged `POST /test/gesture forward-right — posting ⌃⌥⌘F10`, and did
nothing at all. **Victor's own gesture was dead the whole time and nothing on screen or in the log
said why.** `POST /test/cancel` cleared it, and the log's answer confirmed the diagnosis: *"…and
the recogniser had nothing to cancel"*.

**The second cause is the real one.** With the state clean the gestures opened dictations again,
and the transcripts still never arrived:

```
the settle waits: ElevenLabs Scribe is still uploading — 8 s in
the settle waits: ElevenLabs Scribe is still uploading — 25 s in
✍️ the words landed: timed out waiting for the text — 33208 ms after the microphone closed
```

Scribe was not slow — a probe clip through `tools/eleven-test.sh` came back in **0.75 s**. What
those runs were uploading was an **empty file**, and the tell is an absence: `mic: recording
through MacBook Pro Microphone` is logged once per dictation by `MicRecorder.start(to:)`, and for
those two runs it is not in the log at all. The recorder said yes and never opened the device.

```swift
func start(to destination: URL?) -> String? {
    lock.lock(); defer { lock.unlock() }
    guard !isRecording else { return nil }   // ← nil means "the microphone is open"
```

`nil` is this function's success. So **any session still open swallowed the next dictation
whole**: the source logged `recording started for ElevenLabs`, the halo went up, the file it named
was never created, and the upload of nothing sat there until the 33-second timeout. The two ways
to get there are both ordinary — a `cancel()` whose recogniser had nothing to cancel never reaches
`meter.stop()`, and a `stop()` that *is* running is a CoreAudio teardown on `audioQueue` that the
next gesture can easily beat by three seconds.

**The fix distinguishes the two cases the guard was conflating.** The same destination twice is a
gesture arriving down two paths and keeps the old answer. A **different** destination means the
open session is stale and the caller is live, so the stale one is closed, its orphan file deleted,
and the new recording starts — loudly, because this failure's whole nature was its silence.
Metering is deliberately not allowed to pre-empt: `destination == nil` over an open recording is a
ring wanting a level, and a ring is never worth a sentence. The teardown `stop()` and the
pre-emption share is `closeLocked()`, which takes no lock, because
*`MicRecorder.lock` is not recursive* has been paid for once already.

**And the harness stops leaving the relay unusable.** `evals/test_envelope.py` cancels on its way
out now (`_put_the_relay_down`, on `atexit`). A test file is allowed to leave a mess in its own
files; it is not allowed to leave the app dead for the person whose Mac it is running on.
`MicrophoneAfterACancel` in the same file is the regression test: open, cancel, open again, and
assert each dictation logged the device line. It never speaks, so it is safe to run mid-workshop.

**With that fixed, the samples he asked for came out first time** — the words, the tokens standing
where the presses fell, and the footer keyed to them:

```
[📸0🖱️@1263:1562] Uite ce am pe ecran acum. În zona [📸1✂️760,794→2160,1234] asta vreau să apară un buton nou, la fel ca celelalte

[Dictated in RO or EN]
[📁=$WALKIE_SHOTS/2026-09-20-10-44-20/10-44-29]
[📸0 = 📁/screenshot-0-800px.jpg at 800px width, or -original.jpg at 3456x2234px]
[📸1✂️ = user-selected area between corners (x,y) (760,794)→(2160,1234) at 📁/screenshot-1.jpg; also available -800px and -original.jpg at 3456x2234px]
```

```
[📸0🖱️@1263:1562] Uite aici. [📸1🖱️@1263:1562] Linia asta e problema. [selected: "public Order placeOrder(Cart cart) {" from app Walkie Talkie] Hai să o rescriem mai simplu

[Dictated in RO or EN]
[📁=$WALKIE_SHOTS/2026-09-20-10-44-20/10-44-44]
[📸0 = 📁/screenshot-0-800px.jpg at 800px width, or -original.jpg at 3456x2234px]
[📸1 = 📁/screenshot-1-800px.jpg at 800px width, or -original.jpg at 3456x2234px]
```

```
[📸0🖱️@1263:1562] Butonul ăsta [📸1🖱️@1263:1562] și cel de aici [📸2🖱️@1263:1562] trebuie [chrome-selection-1: Salvează] să arate la fel. Schimbă-le pe amândouă

[Dictated in RO or EN]
[📁=$WALKIE_SHOTS/2026-09-20-10-44-20/10-44-56]
[📸0 = 📁/screenshot-0-800px.jpg at 800px width, or -original.jpg at 3456x2234px]
[📸1 = 📁/screenshot-1-800px.jpg at 800px width, or -original.jpg at 3456x2234px]
[📸2 = 📁/screenshot-2-800px.jpg at 800px width, or -original.jpg at 3456x2234px]
[chrome-selection-1 = div.toolbar > button.primary at https://petclinic.victorrentea.ro/orders]
```

Note the second one: the highlight goes **in front of the clause it belongs to** and the frame list
under the words does not repeat it — inline *or* listed, never both. And the third's footer has no
`at 0:0N` stamps anywhere, because with Scribe's word timings every token found a place in the
sentence and nothing had to fall back to the clock.

**The caret variant is not measured here and is not guessed at either.** Delivering a caret
dictation means pasting into whatever is frontmost, and the dead-tty trick that makes a terminal
envelope safe has no caret equivalent — so it was not run rather than typed into a window nobody
was watching. What `caretLine` does with these tokens is unchanged: the words and the deliberate
attachments in the same shapes, `[📁=…]` and its legend rows, no automatic `📸0` and no
`[Dictated in RO or EN]`.

### The rows that differed by one digit — and the five characters that paid for folding them

*"Chiar e nevoie de astea? Nu inferă agentul singur că în loc de `1` trebuie să pună `2`? Trage
eval."*

He was looking at this, and he was right to:

```
[📸1 = 📁/screenshot-1-800px.jpg at 800px width, or -original.jpg at 3456x2234px]
[📸2 = 📁/screenshot-2-800px.jpg at 800px width, or -original.jpg at 3456x2234px]
```

**The eval was rebuilt so the question is the one he asked.** `evals/envelope-symbols/` had two
plain frames, where the repetition is barely visible and the inference is trivial; the scene now
renders **three** (📸0, 📸1, 📸2 whole screens, 📸3 the framed region), and two questions were
added that only a collapsed row can lose — *which file shows screenshot 2 at full resolution* and
*where was the pointer for 📸2*. Exactly one thing differs between arms.

36 runs, 13 questions, Sonnet and Opus, six repeats each:

| envelope | chars | Sonnet | Opus |
|---|---|---|---|
| `victor` — a row per frame, what shipped | 1047 | 78/78 | 78/78 |
| `onerow` — the plain rows folded into `[📸n = …]` | 887 | **76**/78 | 78/78 |
| **`onerow_auto` — the same, plus ` auto` on 📸0** | **892** | **78/78** | **78/78** |

**The inference is not close: `s2_full` is 36/36.** Every run of every arm answered
`screenshot-2-original.jpg` — which means instantiating `n` *and* applying the `-original` rule to
a frame no row mentions. `mouse2` is 36/36 as well. Two rows that differ by one character were
paying for nothing.

**What folding costs is the one question the footer never answered.** *Which frame was automatic*
has always been an inference — 📸0 has no gesture behind it — and both models said so in the
`unclear` field in **every run of both rounds**. While each frame had a row of its own the
inference held; with one templated row Sonnet answered `none` twice out of six, and its reason is
the useful part: *"No screenshot marker lacked a deliberate 🖱️/✂️ action tag, so I couldn't
identify one taken automatically."* Four of six against six of six is not significant by itself
(Fisher, p ≈ 0.45); it is the stated reasoning that makes it worth acting on, and it is the same
thing both models have now asked for twice, unprompted.

So ` auto` ships with the fold — **five characters that turn the last guess in the envelope into a
fact** — and the pair is 78/78 on both models in **155 characters less** than what it replaces.

```
[📸0🖱️@1263:1562 auto] uite aici [📸1🖱️@1263:1562] si mai [📸2🖱️@1263:1562] jos si [📸3🖱️@1263:1562] inca una gata

[Dictated in RO or EN]
[📁=$WALKIE_SHOTS/2026-09-20-12-10-29/12-10-36]
[📸n = 📁/screenshot-n-800px.jpg at 800px width, or -original.jpg at 3456x2234px]
```

**The fold has four conditions and they are computed, not assumed.** Two or more plain frames (one
templated as `📸n` is a riddle where its own digit was a fact); the same resolution, because
`size(path)` is per frame and two displays disagree; a real `-800px` sibling, since
`handover(for:)` falls back to the original and a row promising `screenshot-n-800px.jpg` would
then name a file that is not there; and **no clock on any of them**. That last one is the Wispr
case and it is the important one: with no word timings the tokens cannot go in the sentence, the
rows carry `at 0:08` instead, and an offset is per-frame information no template can hold. An area
frame is never folded in either — it carries corners.

`evals/test_envelope.py` pins both halves: `FoldedFrameRows` drives a dictation *with* word
timings and asserts one templated row, no per-frame rows, the tokens still in the words and `auto`
on 📸0 and nowhere else; `FrameList.test_rows_that_carry_a_clock_are_never_folded` drives the
route that has no timings and asserts the opposite.

**Three stale tests came out of the same pass.** `EnvelopeShape` was still asserting the *prose*
envelope — `text selected during dictation:`, `elements picked in Chrome during dictation, …
oldest first:` — which Victor's template replaced on 2026-09-19; it had been failing for a day
behind `the dictation never reached the outbox`, so nobody had read what it was actually
complaining about. It asserts the shipped shape now. `SelectionMarkers` is a different case and is
**skipped rather than fixed**: it guards the *spoken* marker, retired on 2026-09-18, so all four of
its assertions fail for the one reason that is not a defect — the feature is off, and turning it
on means relaunching the relay with `WT_SHOT_MARKERS=1`, which a harness cannot do to an app that
is already running. What ships is the timestamp marker and `evals/test_marker_place.py` guards it.

And `MicrophoneAfterACancel` learned to **skip** when Wispr Flow holds the microphone: with the
labelling rig running in another session, `startDictation` refuses outright — *one engine at a
time* — so the dictation never opens the device for a reason that has nothing to do with what is
being asserted. It went red once and green twice inside a minute before that guard went in.

## Ten minutes is the end of a sentence, and the row says so from the eighth (2026-09-20)

Victor: *"Uneori se întâmplă să rămână pornit microfonul în dictare. Vreau să implementăm un hard
stop la zece minute, iar de la opt minute să înceapă progresiv pe subtextul dictate listening …
un fel de highlight, un fel de background pe subtext galben care să se — sau ceva, o culoare
vizibilă, cărămiziu, ceva care să se întindă pe tot textul timp de un minut, încet, și apoi să
înceapă să clipească pentru încă un minut. Între minutul nouă și minutul zece, practic iar, la
minutul zece, efectiv se întrerupe dictarea și se termină. Orice ar fi fost, legată, nelegată, se
termină. Injetează la cursor sau trimite la terminalul legat sau deschide terminalul nou, dacă e
un terminal nou."*

**The failure being closed is a microphone nobody is talking into.** A gesture that opened a
dictation he walked away from, a Wispr row that never turned terminal, a recogniser that died with
its input still running — until now the only thing that ended any of those was Victor noticing,
and the longest dictation in the whole corpus is **197 s**, so ten minutes is not a ceiling
anything real is anywhere near.

**It is a stop, not a cancel** — `source.stop()`, the ordinary end of every sentence, so the words
go through the destination this dictation already had: the caret, the bound terminal, or the
session the spawn was going to open. That is the sentence of his the ceiling is about: *injectează
la cursor sau trimite la terminalul legat sau deschide terminalul nou*. Ten minutes of speech is
not something to throw away for running out of clock, and a cancel here would be the ceiling
deciding the sentence was worthless. The one case that cannot be stopped is a relay `listening`
with no microphone behind it (`source.isRecording == false`) — there is nothing to deliver and
only a ring to put down, so that falls through to `cancelDictationInFlight`, which is the same
escape hatch the ✕ has had since 2026-09-14.

**The warning had to be the row itself.** `Listening...` says exactly the same thing at ten
minutes as at ten seconds: the bar fills in the first three voiced seconds and never moves again,
and `(9m)` is a number he has to read and then compare against a ceiling he has to remember. The
chip is read in peripheral vision while he talks, so what works there is something *changing*,
which is the same argument the `HQ` pop is built on.

**Behind the text, never in it.** Every channel of ink on that row is spoken for — the letters are
the ramp, the blue capsule is `HQ`, the opaque grey is *not yet* — so a fourth meaning painted in
ink would overwrite one already there. A background overwrites nothing, and it cannot re-run the
halo failure this file has warned about since `applyTitleText`, because it draws no glyph at all.

- **Eight to nine: it grows.** Left to right across the whole row, the same direction the bar
  fills in, so the two readings never fight each other. Width rather than deepening colour, for
  the reason the ramp is a count rather than a fade: a colour judged over a terminal, an editor or
  a photograph is a question he has nothing to compare against, while an edge crossing the words
  is a position on the row itself.
- **Nine to ten: it breathes**, about once a second, at full width. A state became an event,
  because at that point there is a minute left and something to do about it. The **words** never
  flicker — what pulses is the ground — so the row stays readable through exactly the minute he is
  most likely to still be talking into it.
- **The colour is brick, not yellow.** He asked for the property rather than the hue (*"galben …
  sau ceva, o culoare vizibilă, cărămiziu"*), and yellow is the one signal colour that disappears
  over half of what this chip rides on. `systemRed` blended 0.30 toward `systemOrange` at 0.55
  alpha, resolved **inside `draw(_:)`** where `NSAppearance.current` is set — a
  `CALayer.backgroundColor` is a fixed `CGColor` and would be the same brick over a dark terminal
  and a white page, which is the rule *never hardcode a literal colour on a variable backdrop*.

**Cost, and the loop rule.** `RelayWindow.startOverrun` arms **one** timer that fires at eight
minutes and, in every dictation Victor has ever made, never fires at all; the fifteen-a-second
tick starts only when there is something for it to move and dies with the dictation. It is written
under the ramp's rule — it never reaches `layoutContent`, because all it touches is one frame and
one `alphaValue` on a view nothing is measured from. The right-hand edge it spans to is recorded
by `placeListenExtras`, which already knows where the minutes end.

**One constant, read from both sides.** `RelayWindow.overrunCeiling` is the only thing in that
file something outside it reads: `AppDelegate.armDictationCeiling` schedules against it, so the
warning and the stop cannot end up being about different minutes. The ceiling is armed in
`dictationBegan` — with the microphone, not with the gesture, because a Wispr dictation begins
when Electron wakes up and a ceiling armed at the chord would spend that gap counting — and
cancelled in `dictationStoppedListening`, which is the one place `listening` goes false.

Two new states on the catalogue, `listening-overrun` and `listening-overrun-blinking`, pinned
through `pinListenOverrun(_:)` for `OverlayStates`' reason: the two minutes this is about are the
two no shot could otherwise wait for. The blink is photographed at its **dim** end, or the picture
would be indistinguishable from the full wash above it.


## The ring says where the sentence is going (2026-09-21)

**One preference became three, one per destination.** Victor, in one dictation: *"tendrils să fie
.7x mărime (mai mic). tunnel să fie la dictarea la caret. tendrils dacă sunt legat și sparks dacă
dictez în terminal nou"*, and, when the menu was still a single list: *"să nu apară niciunul
selectat. Dacă îl selectez precis, atunci toate trei sunt puse pe același. De fapt, mi-ar plăcea să
pot alege separat cele trei efecte. Poți să faci cu submeniuri toate … F7, F9 rămân doar de preview
așa. Și Wispr Flow, când dictează, să fie dictare la caret."*

The halo had been *what this app looks like*; it is now *what this sentence is for*. There are
exactly three destinations a dictation can have, and every one of them is already decided before
the microphone opens — `AppDelegate.syncBorrowedGestures` computes `atCaret` from `pasteMode`,
`isBound` and `spawnPending` on every edge. `HaloDestination` is that same expression given a name,
and `HaloStyle.current(for:)` a preference per case:

| destination | what it is | Victor's pick |
|---|---|---|
| `caret` | Replace Wispr, an unbound sentence, **and any dictation Wispr Flow runs on its own** | Tunnel |
| `bound` | ⌘⌃B was pressed; the words are typed into that terminal | Tendrils |
| `spawn` | `Start dictation to new claude` | Sparks |

**The foreign microphone is a caret dictation here, and only here.** `atCaret` deliberately
excludes it (*The ring comes back for the dictations he starts himself*, 2026-09-18): that flag
arms `DropArrow`, and the heads promise a delivery this app is not making. What the ring *wears*
is a different question with a different answer — Wispr types where the caret is, whoever started
it — so the destination reads `atCaret || foreignMic`, and the arrow is left exactly as it was.

**Pushed only while the ring is up.** A bind made in silence does not reach into an F7 preview and
change the effect under him; a bind made mid-sentence does, in the same sync that stops the arrow
asking for a place to paste.

**The menu has both shapes, because he asked for both.** The full list stays at the top of
`Halo fx` and sets all three at once, ticked only while all three agree — with three different
picks nothing is ticked and the row drops its readout, since naming one of the three would be the
one claim that is false. Under it, a row per destination (`At the caret: Tunnel`, `Bound terminal:
Tendrils`, `New claude: Sparks`), each carrying the same list under its own arrow. `Fx engine`
stays last.

**F7/F9 stop writing; the wheel keeps writing.** They are the same cycle, and that was the point:
F7/F9 are pressed *outside* a dictation to browse the list, so with three preferences a keystroke
that saved would quietly rewrite whichever destination was last worn. They now draw without saving
(`CaretHalo.use`). The wheel's dial turns **only while the ring is up**, where the destination is
known, so it writes that destination's row and the flash names it: `✨ Tendrils · Bound terminal`.

**Tendrils ×0.7** the same evening (0.728 → 0.51), the move Sparks got the night before. The
number the app draws at is `HaloStyle.Preset.scale`; the page's own `FORMULAS` entry still says
0.728, and `assets/voice-halo` is pinned to a tag, so the two are out of step until the page is
re-vendored.

**`POST /test/halo` previews by default now.** `{"style": …}` draws it for this run and writes
nothing; `{"style": …, "for": "bound"}` writes that destination's preference; `{"for": "spawn"}`
alone wears that destination's dress. A harness looking at effects has no business leaving his
three picks rearranged behind it. The answer carries `destination` and `picks` beside `style`.

**The old `haloStyle` key is not read any more.** It held one answer to a question that now has
three, and the three defaults above are better than any migration of it would have been.

## Wispr Flow leaves the Engine list (2026-09-22)

Victor: *"scoate wisprflow ca sursă de dictare din lista de Engine — n-am reușit niciodată să-l
integrăm ca lumea în fluxul nostru să-i preluăm ce text injectează."*

**It is a capability, not a ranking.** The other two engines hand this app a transcript;
Wispr Flow pastes into whatever has focus, and every one of the mechanisms in *The wrap, end to
end* exists to survive that rather than to prevent it. The Scratchpad parking, the sink window,
the `History` poll at `formatted`, the key redirection, the 57 ms between `formatted` and the
⌘V — all of it is the price of one missing thing, a string returned to the caller, and none of
it bought that outright. A recogniser whose words the relay cannot be *sure* of catching is a
recogniser that loses sentences, and the settle, the corpus and the envelope all assume the
words come back.

**What actually changed is four lines and a list.** `applyEngineRow` iterates
`["whisper", "eleven"]`, `engine(named:)` has no `wispr` case, `engineId` answers `eleven` for
anything that is not the local model, and `engineMark` lost `(W)`. Everything else about
`WisprFlowSource` stands, because the class was never only a recogniser:

| what still runs on `wisprSource` | why |
|---|---|
| 🔽 → posts Wispr's own chord raw | dictating *an idea rather than a prompt*, Wispr inserting where he is typing — which is the whole point of that gesture and needs no interception at all |
| `hearingChanged` → the ⚡ ring | the one witness wired whichever engine is live, so a dictation he starts himself still shows a ring |
| `noteRawChord`, `pushToTalkReleased`, the back button's stop | the gesture vocabulary, unchanged |
| `wisprSource.meter` | the level meter for a dictation the relay did not start |
| `wrapWispr` / `wrapMode` / `WisprSink` / `WisprScratchpad` | not reachable from any engine pick any more, and deliberately not deleted — see below |

**The wrap is left standing rather than deleted**, which is a decision and not laziness. The
same evening Victor asked for the row to go he asked for the question behind it to be taken
seriously for the first time — ten agents on whether the injection can be *blocked* outright
(TCC revoked and restored per-app mid-sentence, a permanent event tap keyed on Wispr's pid,
`EnableSecureEventInput`, owning the pasteboard inside the 57 ms, `SIGSTOP` between `formatted`
and the ⌘V, Wispr in a VM, a faceless target process, or a setting inside Wispr nobody has
looked for). If any of those lands, the row comes back and the wrap is what it comes back to.
`git show` on this commit is the whole of the menu change either way.

**The stored preference migrates by falling through.** A Mac that had `dictationSource=wispr`
in `UserDefaults` from before today now launches on ElevenLabs, because `engine(named:)`'s
default catches it — deliberately, rather than keeping a case that would let an engine run that
the menu can no longer name. An engine that is live but unpickable is the one state where the
chip and the menu disagree, and that is worse than a silent migration.

## The About page becomes a window (2026-09-22)

Three asks in one evening, and each one threw out the answer to the one before it.

**"să fie nu webpage ci pagina swift de about".** `AboutPage` rendered an HTML string, wrote it
to `~/Library/Caches/…/about.html` and handed it to `NSWorkspace`. The reason it was a page is
in its own doc comment and is *not* the reason it changed: this app never activates itself, so a
modal it puts up arrives behind whatever is in front and steals focus from the bound terminal.

That argument is against an **`NSAlert`**, not against a window. A `.nonactivatingPanel` is what
the overlay already is — it comes up in front, takes no focus, and the terminal underneath keeps
the caret. `AboutWindow` is that panel at `.floating`, with `becomesKeyOnlyIfNeeded` (nothing in
it takes typing) and `orderFrontRegardless`, never `makeKeyAndOrderFront`. The page was costing
three things: every drawing rasterised **twice** to base64, one per palette; a file in Caches the
system may purge, plus a stylesheet duplicating what AppKit already knows about type and spacing;
and leaving the app to read about the app.

**Rendering it is what found the bugs, and they were all one bug.** `.cgColor` on a dynamic
`NSColor` resolves *there and then*, so anything coloured at construction is frozen in whatever
palette the process was in. The dark snapshot came back with an invisible mouse and five white
cards. Both are now painted in `draw(_:)` — `MouseView` from `effectiveAppearance`, `CardBox`
likewise — and both ask for a redraw in `viewDidChangeEffectiveAppearance`. The page's old
comment already said `performAsCurrentDrawingAppearance` does not fix it and that passing the
colours in does; that is still true, and what changed is only *what they are chosen from*: this
view's appearance rather than the process's.

**"cauta o schita in care sa se vada si butoanele laterale"**, and then, on sight of the result,
**"1 singura poza, din diagonala cumva sa se vada toate butoanele"**.

The first ask produced `Glyphs.mouseSide` — the left flank traced off Logitech's own *Product
Overview* schematic, callout 8 being the back/forward pair. Tracing it taught two things worth
keeping: the tail is a quarter-round whose corner three samples and a midpoint quadratic turn
into a **chip out of the back of the mouse** (so 49 columns, ends unsmoothed), and the wheel from
the side is a **hump breaking the shell line**, not a disc — drawn as a filled circle it read as
a ball stuck on the nose.

The second ask threw that away, and rightly. Two views is not a drawing, it is a drawing plus an
instruction to assemble one mouse out of two pictures — which is the work the picture existed to
save. `Glyphs.mouseIso` is the three-quarter, traced off Logitech's
`m650-graphite-large-3qtr-front-angle` gallery render, and it has all five buttons in one frame.
The render has a real alpha channel, so for the first time the silhouette is not sampled off ink:
72 points marched from the centroid, **IoU 0.998** against the real alpha. The interior came out
of a luminance pass (the green LED at u 0.509, v 0.192 is exact to a pixel) and a dark-blob pass
over the flank, which is what settled that the thumb buttons are **one trough split in two**
rather than two islands.

Two correction passes, both found by rendering. Every hand-listed interior point loop came out
**too thin** — a lens drawn through a few points is narrower than the band it was read off — so
the strip, the well and the wheel became `bar`s taking an axis and a width as numbers. And the
wheel at 0.18 × 0.15 is a circle, which on the end of the strip reads as a lollipop; at 2:1 along
the mouse's own axis it reads as a wheel.

**"sa apara o fereastra swift cu indicatii de ce buton e ce simbol si ce face. ajustat dupa
alegerea actuala de gestures."** The `Version:` row was already wired to it; what was missing was
the second half. The panel printed **both** vocabularies side by side with the inactive pair
faded — four columns describing a mouse that has one set of gestures at a time — and the
per-button notes were hand-written, i.e. a second copy of `gestureRows` that described the Logi
set while the menu might be on the wheel set. Now `actions(for:)` reads the live table and picks
the active chord, the headings name `Logi` or `Wheel`, and the table has three columns. A chord
that presses two buttons appears under **both**, because `◀️ + 🔼` is a fact about each of them.

That change forced the layout: under `Wheel` the wheel carries seven gestures and the forward
button carries none, so five fixed-width cards became a ragged grid. A vertical list is what a
legend is anyway — and a button idle in the live set now says `unused in the Wheel set` rather
than `—`, which read as *this button does nothing*.

**The copy is English**, finally, and that is the rule catching up with the move: it was Romanian
for as long as it was a browser page, and became an app string the moment it turned into an
AppKit panel. `vocabulary` says `Logi` / `Wheel`, the two words the `Mouse Gestures` row already
uses, so the panel and the menu cannot come to call the same set different things.

## The firewall (2026-09-22, evening)

Victor, twelve hours after taking Wispr Flow out of the Engine list: *"scopul e să interceptăm
outputul lui wisprflow fără ca acesta să apuce să dea paste/injecteze textul. Îi luăm transcrierea
din db, dar tre' blocată app să nu mai insereze (cât walkie e pornit)."* Then, as the first cut
re-posted the dropped paste for his own chord: *"vreau wisprflow să NU mai fie lăsat să insereze
text el."* And the case that decides the routing: *"e focusată app1, dar walkie e legat la
terminalul 2. wispr să nu insereze în app1, ci textul să ajungă în term 2."* Constraints from the
two failed attempts: *"NU accept soluție care să mute focusul în alt câmp. nici scratchpad nu
încerca — nu ne-a mers."*

**What made it a three-line change rather than a fourth subsystem** is the attack plan's headline
finding: Wispr has no Accessibility dictation path at all. The log line that justified the
Scratchpad — `direct AXValue set did not stick, falling back to clipboard paste` — belongs to its
meeting-chat composer. Every dictation ends in a plain `CGEventPost` ⌘V that a session tap sees,
and the tap already swallowed it — behind a gate armed per dictation, which is the ordering bet
that leaked 5/5 on 09-13. So:

- **The drop is stateless.** `HotkeyTap` eats keycode 9 + ⌘ from a Wispr pid, both halves, always.
  No arm, no window, nothing to be early or late for. `WT_WISPR_FIREWALL=0` for one run.
- **The words come from the row and only the row.** `historyIsTheRoute` is the default; the
  pasteboard watch is off under the firewall and `injected()` treats the ⌘V as a dropped key, not
  as the words. One source of truth instead of two racing Wispr's own clipboard restore.
- **Every Wispr sentence is the relay's.** `intercepting = wrapWispr`, whoever pressed the chord;
  and `wireDictationSource` wires `wisprSource`'s five callbacks whichever engine is picked, so
  his own chord with ElevenLabs as the engine is booked, dressed and routed like ⌘⌃D — to the
  bound terminal, or to the caret when nothing is bound.

**Three iterations in one evening**, each one a sentence from Victor:

1. First cut re-posted the dropped ⌘V for a hand-started sentence — the relay's own key, Wispr's
   clipboard. Green in the loop (1 copy in TextEdit, focus untouched) and rejected: that is still
   Wispr's text landing where Wispr aimed it.
2. Second cut delivered through the relay but read the words off the pasteboard at the ⌘V
   (`wispr-cmdv`, because the key arrived 30 ms before `formatted`). Rejected: the DB is the source.
3. Third cut: the row, and the routing follows the binding. `hand-started` 3/3,
   `hand-started-bound` 2/2 — 195 chars in the tty, **0 in the app in front** — `caret-short` and
   `bound` green with Wispr as the engine. Row `formatted` 458–540 ms after the microphone closed,
   the ⌘V dropped 407–506 ms after it, words landed 5–10 ms after the row.

**Two things the plan called non-negotiable, both in:** `isWispr` fails closed on the name and
demotes off the tap thread when the code is not signed by Team ID `C9VQZ78H85`, keyed on
`(pid, start time)`; and the **canary** — `build-app.sh` re-signs on every change and a tap can
report enabled while inert, so `proveAlive` posts a stamped bare V key-up at launch and after
every wake and asserts the callback saw it (0.9–3.8 ms). `POST /test/firewall` runs one on demand.

**Left as found:** the harness's *Wispr's microphone opened before the clip played* is red on
every hand-started run (10 s, then the clip is played anyway and transcribed) — the CoreAudio
watch does not see the Loopback edge for a chord the relay did not post; it was red before this
evening and it is not the firewall's. The plan's §5 quality test (Scribe+cleanup vs Wispr) was
not run: Victor said the objective was the block. ② (Wispr's own extension host, the vendor's
*hand me the text, do not paste* contract) stays the better endgame if a Wispr update ever
switches to `CGEventPostToPid`.

## `raw_transcript` is a finished sentence Wispr never labelled (2026-09-22, late)

Five dictations in twenty minutes came back as **nothing**, or worse. Victor caught the last one
on screen — *"l-am prins în flagrant: aștepta waiting transcribing, dar Wispr deja transcrisese
textul"* — the chip promising words while the paragraph sat, whole, in Wispr's own History window.

**What the row said.** Wispr's `History` has three text columns and a `status`. The ordinary path,
watched at 150 ms with `tools/wispr-row-watch.py` the same evening:

```
row 16759  status=∅            asr=0    pasted=0    formatted=0
row 16759  status=processing   asr=0    pasted=0    formatted=0     +29.6s
row 16759  status=formatted    asr=306  pasted=319  formatted=319   +33.7s   e2e=4152
```

All three columns appear **in the same tick as the terminal status**. There is no moment in which
a row that is still working carries words. The five failures looked like this instead:

```
16755|raw_transcript|382|382|382|2868|18:28:31
16752|raw_transcript|434|434|434| 383|18:25:21
16750|raw_transcript|779|779|779| 368|18:22:21
```

Complete — every column and `e2eLatency` written — and stopped at `raw_transcript` for ever. Not a
new failure, only a loud night: **21 rows in the 30 days to 2026-09-22 carry text and are still
`raw_transcript`**, the oldest from July, and Wispr has never come back to one of them. In the
relay's own log every single `raw_transcript` arrives **after** `processing`, which is to say the
status goes backwards and stays there. `raw_transcript` in `intermediateStatuses` was right for the
row with *nothing* in it (row 12814, two seconds of digital silence) and wrong for this one.

**What the relay did with it.** Called it progress, waited out the whole 30 s of `captureTimeout`
with the ring lit — and then delivered **whatever was on the pasteboard**:

```
18:24:22  🗣️ wispr transcript via copy_last_text —  1 chars → spawn:…/victor-macos-addons
18:27:01  🗣️ wispr transcript via copy_last_text — 25 chars → caret
```

One character and twenty-five, routed into an agent as a sentence, for dictations of 779 and 434
characters sitting finished in the row. The fallback chord was never posted — `copyFallbackEnabled`
has been off by default since the hour it was written, for exactly this reason (*a dictation that
silently becomes an older one is a sentence he cannot trust*) — but the branch **below** it read
`NSPasteboard.changeCount` anyway. A thirty-second window in which Victor copies things is not
evidence; that branch was the fallback's own bug with the fallback switched off.

**The fix, both halves.**

- `rawTextSettled` — a `raw_transcript` row whose words have held still for `rawTextGrace` (0.8 s)
  is read as `formatted` **for the switch only**, so every path below it is the one a formatted row
  takes; `state.sawRow` and the log keep Wispr's own word, because the row really did stop there.
  The grace is belt to the watcher's braces: nothing has ever been seen writing those columns
  early, and what it delays is a sentence he is waiting for.
- The pasteboard at the timeout is an answer **only when the relay asked it one** (`askedForCopy`).
  And before a sentence is called lost, the row is read once more — a terminal status the poll
  missed, or a `processing` that finished during the last second, is still the words.

**The tool.** `tools/wispr-row-watch.py` — read-only, 150 ms, prints one line per *change* to
(status, the three text columns, `e2eLatency`) of the newest rows. It is the only way to see from
outside Wispr whether a status means *arriving* or *abandoned*, and it is what turned "maybe the
timeout is too short" into a measurement. Victor asked for it in the same breath as the bug: *"un
mecanism de capturare din ochi tochi pentru ce face Wispr Flow transcrieri."*

## The chip says what is hearing him and what is reading it (2026-09-22, evening)

Three asks in one evening, and they turn out to be one change.

**First, the letter becomes a logo.** The engine mark had been `(W)` / `(E)` / `(L)` since
2026-09-18 and `Listening(🎙️/E)...` since the microphone joined it on 2026-09-19. Victor:
*"fără paranteză, să scrie apoi emoji-ul device-ului folosit, apoi slash în continuare, dar în
loc de litera care urmează, aș vrea să am logo-ul lor stilizat cu gri. Exact culoarea fontului.
De la Wispr Flow, de la 11 Labs — e acel semn cu o pauză într-o bulină — sau, respectiv, Mac-ul,
dacă este transcris cu motorul local."*

A letter is a thing to *decode*, and the proof of it is the comment that had to sit over the
table: `L` and not `W` for Whisper, because the two recognisers whose names begin with the same
letter were exactly the two he most needed to tell apart. A logo needs no legend.

- **ElevenLabs** is a pause in a ring — the two bars of their wordmark as they are worn on the
  icon, and the ring keeps the mark from reading as a second slash beside the one in front of it.
- **Wispr Flow** is five bars, traced off `electron.icns` the way the mouse outlines in `Glyphs`
  were traced off Logitech's schematic: bars 18 px wide on a 28 px pitch inside an ink box of
  129 × 128, heights `1.00 / 0.43 / 0.66 / 0.44 / 1.00`.
- **The local model** is the Apple mark, typed rather than traced — `U+F8FF` is a monochrome glyph
  in the system font, so it takes the row's ink like any other character. It is also the honest
  picture: the other two are logos of somewhere his voice is being *sent*, and this one is the
  machine it does not leave.

**They travel as characters.** `RelayWindow` may not know there is more than one recogniser —
that is `DictationSource`'s rule and the reason the Wispr path could rot unnoticed for a month —
so the logos are private-use scalars (`Glyphs.Engine`) inside the mark string, and
`applyEngineText`'s existing *non-ASCII is a picture* branch draws them. `AppDelegate` still hands
the chip a string; the chip still cannot branch on what it means. They are cached on the colour
**as it resolves**, not as it is named: the chip's ink is `secondaryLabelColor`, two different
greys in the two appearances under one name, so a key built from the name would have handed back a
dark-mode logo after a switch to light for the life of the process.

**Then, the same evening, the mark came apart.** *"Am răzgândit un pic: când fac listening să
scrie «listening to» și apoi emoji-ul device-ului ascultat. Respectiv, când fac transcribing, să
zici «transcribing via» și să pui simbolul tool-ului care face transcrierea efectivă."*

Which is right, and it retires the design problem the slash was the answer to. `Listening 🎤/⬮...`
says both facts at the one moment only the first of them is true: while the microphone is open
nothing has been transcribed, and by the time something has, the microphone is shut. So the
device stays on `Listening to 🎤...` and the recogniser moves one row down to
`Transcribing via ⬮...`, each with the preposition that makes it a sentence rather than a code.
The separator is gone with the pairing.

The one thing that had to be added downstream: `transcribeString` never had the *non-ASCII is a
picture* branch, because until that evening every character in that row was ASCII. A raw glyph in
an attributed string on a label that carries a halo draws itself and leaves every other glyph
transparent — the failure this file has warned about since `applyTitleText`, and the one that once
cost the spawn row its entire word.

## The arrows double while the words are in flight (2026-09-22)

*"Când o dictare la caret este în procesul de transcriere, săgețile cele trei de sus și jos care
arată spre cursor trebuie să se dubleze ca mărime … Cele care apar atunci când fac o pauză în
dictare să rămână ca până acum."*

`DropArrow` has had two states since 2026-09-15 and they were drawn identically. The silence one
is a **suggestion**: he has stopped talking, the caret could still go anywhere, and he may
perfectly well go on speaking — in which case the heads fade and nothing was owed. `hold` is not a
suggestion: the microphone is shut, the sentence is coming, and the pointer must not move until it
lands. One size for both left the moment with a deadline in it looking exactly like the moment
without one.

**Size, and not colour, speed or count**, because size is the only channel this shape has left —
the amber is *this is the arrow*, the wave's rhythm is *inward*, three a side is the sequence.
Doubled, the outermost pair sits 88 pt from the hot spot, past the ring's hole and into its band,
which is where a bigger shape has to be to stay legible at all. It is a transform on the container
about its own centre, so the arrangement stays symmetric about the pointer — which is the whole of
why it is six heads and not one arrow.

**Instant, both ways.** Core Animation animates a transform over a quarter of a second unless told
otherwise, and neither end wants that: the growth *is* the message, and the shrink is only ever
seen on a window that has already been ordered out. `refresh` runs at 20 Hz and sets it back to 1
on every tick, so the assignment is guarded on the value or it is twenty chances a second for an
implicit animation.

`WT_SHOOT_HALO`'s arrow sheet gained a middle column, `words in flight`. Same argument as the
sheet itself: this is the one pose of this shape that is on screen for a fixed second or two of
every caret dictation and can therefore never be looked at for long enough to judge.

## `⌘⇧P`, said once and faintly, where it is the answer (2026-09-22)

*"După ce ai dat cancel la dictare sau după ce s-a încheiat o dictare la caret … ideea că paste-ul
poate se pierde … să apară foarte transparent, încă un hint, cu tastele pe care le apăs ca să dau
paste la acel prompt. Și cumva să apară foarte faint, și apoi să crească opacitatea … și apoi să
dispară. Un singur puls de la transparent la mai opac și apoi din nou transparent."*

`⌘⇧P` is the one gesture in this app that is only ever wanted after something went slightly wrong
— the ⌘V landed in the window that had the focus rather than the one he meant, or Cancel threw
away a sentence he then wished he had. Both are moments of mild alarm, and a shortcut recalled at
leisure is no use at a moment of mild alarm. So it is said **where** the loss happens, at the
instant it happens, and nowhere else.

**Not after a cancelled dictation**, which is the one reading of his words I did not take. There
is no sentence there — the ✕ kills the audio before any transcript exists — so `⌘⇧P` would paste
the sentence *before* last, which is the `copy_last_text` failure under its own standing *never
reintroduce* rule, arriving by a new door. That case already has `Recover Cancelled Dictation`,
offered in its own banner.

**The ceiling is his number, twice given, unprompted: ten to twenty per cent.** It ships at 0.20
with `WT_PASTE_HINT_PEAK` to move it. The arithmetic behind agreeing: this appears after *every*
caret sentence, dozens of times a day, over the thing he is working in. At full ink that is an
interruption charged on every success in order to help with the occasional failure. At a fifth it
is visible to a glance that goes looking and beneath notice to one that does not, which is the only
setting at which something can be said this often.

**Placed once and it does not follow.** By the time it has faded up he may be reaching for the
keys, and a hint that walks away from the cursor as he moves is the single dotted arrow `DropArrow`
threw out in 2026-09-12 — a thing to look at rather than a thing to notice. It takes a window of
its own for `DropArrow`'s reason: everything else this app draws near the pointer hangs its meaning
on the window's own alpha, and here the alpha *is* the message.

`WT_SHOOT_HINT` draws it on a dark ground and a light one, at its real opacity and at full ink —
the only way to judge a mark whose whole design is a number between nothing and not much.

## The row was greyed out above a list of the sentences it would paste (2026-09-22)

*"În prompt history apar elemente, dar «paste last prompt» e dezabilitat. Nu prea are sens asta,
nu?"*

It does not. `Paste last prompt` was enabled off `lastDictation`, which lives in memory and is born
nil, so every relaunch — a Dock click, `relay-restart.sh`, a rebuild — greyed the row out while the
*Prompt history* submenu three pixels above it listed twelve sentences the key would happily have
pasted. Two rows reading two different stores, and only one of them survives a restart.

`pastableDictation` is now the one question both the key and the row ask: this run's
`lastDictation`, else the newest line in the outbox, as the envelope `MessageLog` already hands the
history rows. **Read lazily and at most once a run** — `MessageLog.recent()` parses the whole
outbox, two megabytes today and growing forever, and this is asked at every menu open; it is only
ever consulted while `lastDictation` is still nil, which is to say until the first sentence of the
run.

A caret sentence writes no outbox line and so cannot be seen here. That is honest rather than a
gap: what the fallback restores is the last sentence that was *sent somewhere*, which is exactly
the set the submenu lists — so the two now agree by construction, which was the complaint.

### The row says *taking longer than usual* (2026-09-22, late)

Victor, minutes after the fix above went in: *"dacă durează > 150% din cât trebuie pe statistic, să
zică adauge la tooltip «🤔Taking longer than usual...»"*.

The bar already said it, in ink: `Transcribing via ⬮...` fills over `DecodeRate`'s estimate and,
past it, simply arrives full and stays there — *"what I am past my own estimate looks like when it
is not a number"*, written on 2026-09-08 when the seconds came off the row. That reading was enough
while the only thing past the estimate was a slow decode. It stopped being enough the same evening,
for the reason the section above is about: **a full bar and a lost sentence look exactly alike**,
and four of them in twenty minutes sat there for thirty seconds each.

- **The threshold is `transcribeSpan`**, which *is* `DecodeRate`'s promise and the very number the
  ink is drawn from. A second clock would be a second opinion, and the day the two disagreed the
  words and the ink beside them would be saying different things about the same wait.
- **The note is outside the bar** — appended after the word, always lit. `transcribeWarmth` is a
  fraction turned into a count of characters, so adding the note to `transcribeWord` would move the
  ramp under a row that is already half filled.
- **Its arrival is a relayout, and the third one a dictation is allowed** (the `HQ` tag and the
  once-a-minute `(Nm)` are the others). The rule that the 15 Hz ticker never reaches
  `layoutContent` stands: this is one edge, not a frame.
- **No estimate, no note.** With `audio == 0` there is no ticker and no deadline — there is no
  statistic to be 150 % of, and a row that guessed would be inventing one.

`transcribing-overdue` is the 46th shot in `OverlayStates.swift`; `pinTranscribeOverdue` is how a
state defined by a stretch of elapsed time gets photographed without waiting it out.

## `⌘⇧P` becomes a row of the chip (2026-09-23, afternoon)

Victor, on the keycap that had followed the pointer since the morning: *"It looks like now it has a
border around it, with a different font, which is wrong. I just want you to display yet another row
in the mouse tooltip. Technically, it's just like, for example, transcribing Kamikaze … It should
have the icon of the paste … the text should say 'Paste again', and then the shortcuts, just like
any text in the tooltip."*

- **`KeycapView` and its window are gone.** `PasteHint` keeps only *when* (`pulse` for `hold` = 3 s,
  a second pulse restarts, `hide` cuts); the drawing is `RelayWindow.pasteRow` — `📋 Paste again  ⌘⇧P`.
- **One constructor for both rows**, `installEmojiRow`, so the face (`hintFont`), the ink, the glyph
  (`Glyphs.emoji` at `iconInk`) cannot drift between `☠️ Kamikaze` and it. Layout, height, the halo
  on the bare chip — every line that touches a Kamikaze view has a paste twin, and
  `evals/test_paste_row.py` checks exactly that (with a `--self-test` of four mutations).
- **The chip's width now asks both emoji rows.** Kamikaze had never been measured into `natural` and
  got away with it under longer rows; the paste row is often the only row, and unmeasured it is a
  chip 0 wide.
- **It survives typing**, like a flash: the chip fades to zero while he types, and the paste row is
  shown right after a caret sentence — the moment he is most likely to be typing past it.
- The window's two reasons for existing — its own alpha, the keycap outline — were the two things he
  rejected, which is why this is a reversal and not a restyle.

## Forward is a prompt, back is plain words (2026-09-23)

Victor restated the side buttons in one dictation, then added two things (transcribed; "carrot"
is *caret*):

> "The forward click should be transcribing, basically prompting, at the carrot. There will be
> those metadata, the screenshot of the screen, the fact that is dictated, and any other feature,
> including prompting and picking pictures for an agent. Clicking the back button on the mouse
> starts a plain voice transcription with no sorts of prompting tweaks around it. It should be just
> clean voice that I had. The bound dictation is activated by forward click and moving the mouse to
> the right. Forward click and moving the mouse upwards starts a terminal in a new session."
>
> "If during a plain transcription, on the back button, the back button ends it, there is no
> screenshot in a clean dictation. Enter is dispatched if I do a back click and move the mouse to
> my right."
>
> "Make the dictation @. Hit Enter to trigger. For example, if I am putting my @ into a Claude Code
> terminal prompt, it should already submit the prompt as it's actually a prompt."

### Spec against what the code did that morning

| (button, gesture) | spec | before | changed |
|---|---|---|---|
| 🔼 click | caret, **prompt**: context frame, `[Dictated in RO or EN]`, highlights, picks, pictures | caret, `caretLine`: deliberate attachments only, no frame, no hint | **yes** |
| 🔼 click, caret in a Claude Code prompt | submitted | never an Enter | **yes** |
| 🔼 → | the bound terminal | `toggleDictation` | no |
| 🔼 ↑ | a new terminal and session | the spawn | no |
| 🔽 click | plain words at the caret | Wispr's toggle, **routed by the binding**: bound, it went through `send` → `terminalLine`, so `[Dictated in RO or EN]` leaked in and the terminal delivery pressed Return; marker splicing, the recent-highlight probe and kamikaze all ran | **yes** |
| 🔽 click, plain dictation open | stop it | stop (fixed at 15:17 the same day) | no |
| plain dictation | no picture at the start or the end | no context frame, the click not a shutter; ⌃⌥P still shot | **yes** |
| 🔽 →, plain dictation open | stop, clean words, Return | only Return, the sentence left running | **yes** |
| 🔽 →, otherwise | Return | Return | no |

**"Bound dictation" needed no interpretation**: the rule file had carried his own vocabulary since
2026-09-12 — *"🔼 click = caret; 🔼 → = legată"* — and *legată* is the terminal ⌘⌃B points at.

### What changed

- **`caretPrompt` and `cleanSentence` on `AppDelegate`**, the two things a caret sentence can be.
  `startDictation(paste:)` sets the first (every caller passing `paste` is the forward click);
  `noteCleanStart`, from both of `wisprSource`'s begin callbacks, sets the second off the back
  click's arm (`backStopsWispr`), which the tap raises before the chord's announcement reaches the
  main queue and retires at the stop click — hence latched at the begin and carried to `deliver`.
  The held right ⌘⌥ and a hand-started Wispr sentence with nothing bound are neither, and keep
  `caretLine`'s old envelope.
- **The prompt is `terminalLine`, pasted.** `caretLine(words:full:)` builds `send`'s `Message`
  field for field and renders it with `terminalLine`, so the caret and the bound prompt cannot
  drift; `dictationBegan` takes the context frame for it. This reverses 2026-09-19's *"if I'm
  dictating at caret, we still don't do an initial screenshot"* — the ⌘C probe that was the real
  reason caret sentences went picture-less left on 2026-09-16, so the frame costs the field he is
  dictating into nothing.
- **Submitted where the caret is a Claude Code prompt** — `TerminalBinding.frontClaudePromptTTY`:
  Terminal.app in front, a non-shell in front on its selected tab (the shell guard's
  `foregroundCommand`/`isShell`), and a process on that tty owning a fresh
  `~/.claude/cwd/.last-<pid>` (`publishedDirectory(onTTY:)`, how the chip already knows a session
  is there). Then the bound terminal's own write (`writeToTerminalApp`: text, bare Return, the
  review Return). Anything else is the ⌘V with no Enter. **IDE terminals are deliberately not
  covered**: nothing outside VS Code or IntelliJ can say whether the caret is in the terminal pane
  or a source file, and an Enter in a source file is an edit. No cancel window — the caret never
  had one.
- **Plain means the words.** `cleanLine` drains the caret envelope's bookkeeping (so nothing rides
  the next sentence) and returns the words; `deliver` skips the marker rewrite and kamikaze for
  it; `dictationBegan` skips the frame and `probeRecentSelection`; `plusOneShot` refuses ⌃⌥P while
  the arm is up. **It goes to the caret even when a terminal is bound** — the coordinator's call,
  on two readings: *"cum ar fi Wispr normal"* (the same afternoon), and a bound delivery always
  presses Return, which here is 🔽 →'s to give. Victor may override it. A sentence started with
  **Wispr's own keyboard chord** still follows the binding (the firewall's motivating case).
- **🔽 → during a plain sentence** posts the back click's own stop chord, drops the arm and raises
  `onBackSubmit`; `deliver` presses `postReturn` 0.3 s after the paste. At any other moment it is
  Return, as it was.

### The guard

`evals/test_gesture_spec.py` is the spec as a table — eight (button, gesture) rows, 35 checks —
each checked against the real `case VK_Fn:` branch, the `AppDelegate` callback it raises and the
delivery it ends in. `--self-test` applies ten mutations, each one the previous behaviour coming
back (the old caret envelope, the forward click going to the terminal, the Enter without the
session-file check, plain text following the binding, ⌃⌥P shooting a plain sentence, the shutter
before the stop, 🔽 → as only Return, …), and all ten are caught.

Not tested live: nothing here can press a real side button, and the app was not restarted.

## Active Terminals: the spawn menu's first row (2026-09-23)

Victor, dictated that evening: *"In the project pop-up, the project selection one, when I open a
new terminal, I want the first option to be a menu that says 'Recent', or 'Active Terminals', and
then when I hover over it, a submenu opens that lets me bind this prompt to that terminal."*

That morning the same menu had grown a third half — *Or send to an open terminal*, the five
terminals most recently bound that were still open, under the folders
(`RebindHistory.openTerminals`). His *"Recent"* is that list; what he asked for is where it lives
and how it opens. It is now the first row, `Active Terminals ›`, and its rows hang off it in a
submenu on hover.

- **Found by looking, not remembered.** The morning's list came from the bind log, so a session
  he had never spoken to was not in it. The submenu lists every Terminal.app tab on whose tty a
  process owns a fresh `~/.claude/cwd/.last-<pid>` — `TerminalBinding.activeAgentSessions()`:
  `liveTitles()` (one `osascript`), one `ps -ax -o pid=,tty=`, and `publishedDirectory(ownedBy:)`
  per pid on those ttys, the same two guards the chip's folder label runs on. A plain shell,
  `ssh`, `vim` or a closed window is not offered.
- **What a row says** (`ActiveTerminals.items`, pure, `swift test`): the folder name alone when it
  is unique; when two sessions share a folder, the task out of the tab title
  (`✳ human-review — Pe CodeCity…` → `human-review — Pe CodeCity…`), else the tty
  (`human-review · ttys013`), and the tty on top of a task two sessions share. Alphabetical, the
  menu's own rule. The terminal bound now is ticked `✓` in `NSMenu`'s state column.
- **Empty is drawn, not hidden** — `Active Terminals — none`, dimmed, no chevron, no submenu. A
  row that comes and goes moves every folder under it between two openings. The row is measured
  for its longer label up front, so the answer landing (~100 ms after the menu, off the main
  thread) restyles it in place; nothing under the hand moves and the clock is not restarted.
  Hovered before the answer: one dimmed `Looking…`.
- **A pick is a bind, and the words leave by the bound terminal's own delivery**
  (`AppDelegate.redirectSpawn`): the spawn is cleared **at the click**, the tty bound off the main
  thread, `showBound` then the window brought forward (the morning's *menu rebinds bring the
  terminal forward*). `deliverToTerminal` → `writeToTerminalApp`, its Return and its review
  Return — no second path.
- **Three ways it could have lost or doubled the sentence, closed.** *The settle*: `showBound`
  drops a spawn only while `listening`, and the menu still answers for a second or two after the
  microphone closes — the morning's rows, picked there, bound the terminal **and** opened a new
  session. Clearing the spawn at the click fixes it for whichever moment. *The bind in flight*: it
  is an `osascript`, and words landing inside it would have gone to the terminal bound before;
  `commit` holds them (`spawnPickInFlight`, quietly) and the pick's `showBound` releases them —
  and `dictationStoppedListening` does not latch the caret for a pick still binding. *The terminal
  gone*: a pick that cannot bind puts the spawn back (`spawnAfterFailedPick`) — re-armed if the
  sentence is still being spoken or transcribed, the held message sent as a spawn if it already
  arrived — rather than a hold the 10 s poll would release into the old binding. A pick after
  `send` took the words is refused, as a late folder always was.
- **The submenu is a second panel, not an `NSMenu`**, for the menu's own reasons. Hovering it
  suspends the fade exactly as the menu does (`hoveredMain || hoveredSub`); a folder row entered
  takes it away after 0.3 s (`submenuGrace`) unless the hand reaches it — the diagonal every
  cascading menu has to forgive.
- **`WT_SHOOT_MENU` draws it open**, with this Mac's real sessions (`WT_SHOOT_BOUND=ttysNNN` for the
  tick). `evals/test_active_terminals.py` holds the row to being the last one `build` adds (the
  first on screen — the layout is bottom-up), unconditional, `emptyLabel` when empty, the pick
  routed to `redirectSpawn` and `commit`'s hold; `--self-test` moves it, hides it and drops the
  hold, and all three are caught.

Not tested live: the app was not restarted (restarts go through `./relay-restart.sh`), so the
hover, the click and the delivery were not driven on the running relay.

## `⌘⇧P` stays up while he presses keys (2026-09-23, evening)

Victor: *"the hint about what keys to press after dictation transcription ends should remain next to
the mouse, whatever I press. I think I pressed Command-Z, and it disappeared from near the mouse.
They should stay there just in case I need to paste it again."*

- **Nothing hid the row on a key** — the log shows only the delivery's pulse. The flat 3 s ran out
  under the undo: the first thing he does on seeing words land wrong is `⌘Z`, and that is exactly
  the stretch the row exists for.
- **Every keystroke now restarts `hold`** (`PasteHint.watchKeys`, a passive global `keyDown`
  monitor installed only while the row is up). The row goes 3 s after the *last* key, or when the
  next dictation raises the ring (`hide`) — never because of a key.
- **Then 5 s, not 3** — Victor, the same evening: *"let it be 5 seconds."* `PasteHint.hold = 5`,
  still counted from the last key.

## ElevenLabs + Live: the words beside the pointer (2026-09-25)

Victor: *"in meniul de engine de transcriere: optiune noua: ☁️ ElevenLabs + Live · ascunde pt
moment wispr flow · ☁️ ElevenLabs · 💻 Local. move the details of what models into the tooltips.
the option+streaming will display +1 line in the mouse caption 💬 <the last 7 words of dictation
live-transcribed>, entering from right, exiting left: to show me what I'm talking about"*.

- **The stream is a caption, not a recogniser.** What is delivered is still the batch transcript
  of the recording (`scribe_v1`/`v2` per `WT_ELEVEN_MODEL`) — word timings, spliced markers,
  retry, corpus audio all unchanged. The realtime model (`scribe_v2_realtime`, $0.39/h published
  2026-09-25 on elevenlabs.io/pricing/api) only feeds the chip, so a dropped socket costs the
  caption and never a sentence. Using its committed text *as* the delivery (no upload wait) is
  the obvious next step and was not taken without asking: it would lose the word timings the shot
  markers are placed by unless `include_timestamps` is proven equivalent.
- **Protocol probed before it was written** (`wss://api.elevenlabs.io/v1/speech-to-text/realtime`,
  `xi-api-key`, `audio_format=pcm_16000`, `input_audio_chunk` + base64): 15 s of a corpus WAV
  in 85 ms chunks → `session_started` at once, partials about once a second, the last word's
  punctuation revised between partials (`gun.` → `gun,`) — which is why the ticker compares word
  lists by common prefix and slides only when the words already on screen are still there.
- **Chunks before `session_started` are held and flushed**, so the first words are not lost to
  the handshake.
- **The row's width is reserved for the whole sentence** so the chip does not grow word by word;
  the words move inside a fixed window instead (`overlay-chip.md`).

## A failed cloud transcription falls back to the local model (2026-09-25)

Victor: *"implement a fallback: in case the transcription model selected is unavailable,
fallback to the local model, rather than giving up on the transcription."*

- **Where:** the top of `AppDelegate.dictationEnded`, before the failure branch clears the
  sentence's flags — the fallback needs the settle, the destination and `cleanSentence` exactly as
  the cloud engine left them, so the words land where they would have.
- **What counts as unavailable:** whatever ends in `.failed` with the WAV in hand — transport
  error, HTTP 4xx/5xx after the one retry, and (new) **no API key**, which used to refuse the
  gesture and now records and fails at the upload instead. Wispr is out of scope: its audio is
  never this app's.
- **The wait before the fallback was shortened**: `requestTimeout` 45 → 20 s and no retry after a
  timeout, since the retry of a hung connection only delayed the local model.
- **Tested:** the local half on a corpus WAV through `POST /test/local-fallback` — model cold,
  6.0 s for a 3.5 s clip, text correct. **Not yet tested end to end** with a real failed upload
  and a delivery (that needs a real sentence and a destination).

