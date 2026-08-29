# Walkie Talkie

A small macOS overlay that **relays your dictation into a running coding agent**
— along with the text you had selected and screenshots of what you were looking
at — so you can drive the agent while looking at something else entirely: a
browser, an IDE, a projector.

It records and transcribes on its own, with a Whisper running on your Mac: click
the mouse wheel to start, click it again to stop, and the words go to whatever
agent is watching its queue rather than into whatever holds the caret. That is the whole
idea, and the name — it is not tied to any one agent (it was called Claude Bubble
until it turned out to work with all of them).

It is **one-way and non-interactive** by design. The agent gets your words; it
cannot ask you anything back, because you are not reading the terminal.

<img src="docs/idle.png" width="196" alt="the idle chip: a robot emoji and the session name, trailing the cursor">

At rest it is just a label riding along near your cursor, telling you *which*
session is listening — `folder@branch`, the same thing Claude Code's status line
shows. It disappears while you type and comes back when you move the mouse.

<img src="docs/listening.png" width="196" alt="dictating: the session name, a pulsing red dot, the shot count and the shot hint">

When dictation starts the chip stays where it is and grows one row: a pulsing 🔴,
how many pictures the message is carrying, and the two ways to add another
(`🔴 📸 ×2 🖱️/F3`). Behind that row the screen is photographed, whatever was
selected is captured and frozen for the whole dictation, and either the **back
mouse button** or **F3** attaches extra screenshots as you talk — the count going
up is the receipt.

The mouse button is borrowed **only while that row is up**, so a dictation never
needs the keyboard at all; the rest of the time the button keeps doing whatever
your mouse software says it does. Each shot records where the pointer was —
in the file name (`shot-01:23(mouse-at-1034x1466px).jpg`: how far into the
dictation it was taken, and where the pointer was in that image) and as **a red
target dropped on the desktop** for a couple of seconds. So pointing at something
while you talk about it is enough, and a shot aimed at the wrong thing is noticed
while the sentence is still being said.

Nothing is drawn *into* the picture: a mark painted over a frame covers the thing
it points at, and an agent reading the image cannot tell it from the UI.

Shots go to `~/Library/Caches/ro.victorrentea.wispr-relay/shots/<session>/`,
which macOS reclaims under disk pressure: they are a staging area, not an
archive.

<img src="docs/prompt.png" width="308" alt="the finished prompt with a Cancel button counting down">

The finished prompt is shown whole — and **held for 4–7 seconds behind a Cancel
button** before it is written anywhere. That delay is the feature: once a line is
in the queue the agent may already be acting on it, so the only honest moment to
cancel is before it is written.

Its last line is the pictures it carries and **when each was taken**, as m:ss
from the moment you started talking (`📸 ×2 0:38`). The count says the
shots landed; the times say *which* moments you caught, which is the thing you
cannot reconstruct once the panel is gone.

## Pointing at things in a web page

"Make **this** button blue and move **that** panel" is a sentence an agent cannot
act on. Hold **⌘⇧** over a page in Chrome and the element under the cursor is
outlined and named, DevTools-style; **⌘⇧-click** it and its CSS selector joins the
message you are about to dictate — the demonstrative arrives already resolved.

**It is live only while you are dictating** — the same window in which the back
mouse button is borrowed, and for the same reason. The chip grows a third row
saying so, right beside the cursor, behind Chrome's own icon: `select element
⌘⇧🖱️` before you have picked anything, then `×2 div#cart > span.price` once you
have. The held prompt lists
them with when each was taken:

```
↪ public Order placeOrder(Cart cart) {
extract the tax calculation out of this method
📸 ×2 0:38
🎯 0:12 main.content > button.buy-button
🎯 0:21 div#cart > span.price
```

**A quick ⌘⇧-click is still a quick ⌘⇧-click.** ⌘⇧-click opens a link in a new
tab and jumps to it, so the inspector arms only after the chord has been held on
its own for 400ms — longer than any shortcut, and longer than the hand takes to
click. Press any other key and the hold is abandoned. So the gesture is borrowed
twice over: only during a dictation, and only when you mean it. Outside that,
Chrome gets it back.

This half is a small **Chrome extension** in [`chrome-extension/`](chrome-extension/),
and it needs loading once:

> `chrome://extensions` → **Developer mode** on → **Load unpacked** → pick the
> `chrome-extension` folder.

It is an extension rather than the DevTools protocol because since Chrome 136
`--remote-debugging-port` is refused on the default profile — reaching *your*
browser, with your tabs and your logins, would mean relaunching it against a
throwaway profile. It also puts the work in the only place where no coordinate
maths is needed: inside the page, `elementFromPoint` and `getBoundingClientRect`
are already in the coordinate system the outline is drawn in, at any zoom.

The extension talks to the overlay over loopback only (`127.0.0.1:8917-8919`,
first free port per relay session; it posts to all of them, so several sessions
can share one browser). With nothing dictating, every relay refuses its probe and
the extension never arms at all — its toolbar badge is how you tell.

### It also pauses your music while you talk

The moment a dictation opens, every Chrome tab that is making sound is paused,
and exactly those tabs resume when it closes — a tab you had already paused by
hand is left alone. Nothing to turn on: it rides the same extension.

This has to happen inside the browser. CoreAudio funnels every tab through one
Chrome audio helper process, so from outside, "Chrome is making sound" is the
finest grain there is — you cannot name the tab, let alone stop it.
`chrome.tabs.query({audible: true})` is the per-tab answer, and it only exists in
here. The relay pushes the window over a second loopback socket
(`ws://127.0.0.1:8920`) rather than being polled, so the pause lands with the
recording row instead of up to a poll interval later.

It follows the *relayed* dictation, not the microphone: unbound, or with
forwarding paused, you are talking into some other app and your music is none of
the relay's business. If the relay dies mid-sentence the extension resumes on the
dead socket, so the music can never be left off with nothing alive to restore it.

## How it reaches the agent

Two ways, and they are not alternatives — the second is layered on the first.

### Typed straight into a terminal

Press **⌘⌃D** while looking at a terminal and the relay is pointed at it: every
dictation from then on is typed into that session and submitted, wherever your
cursor happens to be when you speak. No command to run in the terminal first,
nothing to arm, nothing watching a file.

A Terminal.app tab is addressed by its **tty** and a tmux pane by its **`%id`**,
so the delivery finds the target even when the window is behind others or on
another Space — and it never takes focus. Anything else (VS Code's integrated
terminal, IntelliJ's) is driven with a paste and a Return, which does move the
focus for a moment and puts it back.

**It refuses to type at a shell prompt.** Before every delivery the relay checks
what is running on the target, and if that is a shell it sends nothing: at a
prompt a dictation is not a message to an agent, it is a command to be executed.
The check is on the *shell*, not on any particular agent, and it fails closed.

The overlay's chip then names the session it is aimed at — `📍 petclinic@main ·
✳ fixing the tax bug`, the repo plus whatever the agent is currently calling
itself. Binding also draws a translucent blue rectangle over the window it just
captured, which shrinks and flies to your cursor: that window is now this chip.

### The outbox

While bound, the overlay *also* appends JSON lines to
`~/.walkie-talkie/outbox.jsonl`. Anything that watches that file can consume
them; there is no back-channel.

**Unbound, nothing is written** — and nothing else happens either: no dictation
can be started, no picture is taken, and no mouse button is borrowed. The app
runs from login and is aimed at nothing most of the day; a relay with no
destination has no business opening a microphone. Bind a terminal and both
routes come alive together.

```json
{"ts":"2026-07-30T08:12:03Z","session":"myrepo@main","kind":"dictation",
 "text":"extract the tax calculation out of this method",
 "selection":"public Order placeOrder(Cart cart) {","app":"com.microsoft.VSCode"}
```

Elements picked in the browser ride in an `elements` array of
`{path, tag, text, label, href, url, title, frame}`, in the order they were
picked, so the first demonstrative in the sentence is the first entry. `url` is
the page's address (the top document's, even when the element sits in an iframe —
the frame's own URL travels in `frame`), and `text` is what the element says: its
rendered text, or the `value` of a form control, which has none.

`kind` is `dictation` | `screenshot` | `session_end`. Every message carries the
`session` it belongs to, so several overlays can share one queue without an agent
acting on another project's words.

Any agent that can tail a file will do. The Claude Code side is the `relay` skill
in [`victorrentea/skills-private`](https://github.com/victorrentea/skills-private)
(`skills/relay/`),
which ships the built binary, installs `/relay`, and watches the outbox.

### Loopback control

The relay listens on the first free port of **8917–8919** (several can run at
once, each taking one):

| route | |
|---|---|
| `POST /bind` | point it at the frontmost terminal |
| `POST /unbind` | stop — the relay goes inert until something is bound again |
| `GET /target` | what it is currently aimed at |
| `POST /test/dictation` | `{"text":"…"}` — put a sentence through the whole path without speaking one |
| `GET /engine` | which recogniser is loaded, and whether it is ready |

## Input

| input | effect |
|---|---|
| **click the wheel** | Starts a dictation — red flash, screen captured, selection grabbed — and ends the open one. Only while a terminal is bound |
| **hold the wheel 2s** | Cancels the open dictation — the audio is discarded, nothing is transcribed |
| **hold left, click the wheel** | Re-points the relay at the window in front — the same call as ⌘⌃D |
| **back mouse button** | One more screenshot — but only while dictating; otherwise the button is untouched |
| **F3** | The same shot, from the keyboard |
| **hold ⌘⇧ in Chrome** | Outlines and names the element under the cursor |
| **⌘⇧-click in Chrome** | Adds that element's selector, page URL and text to the message; the page never sees the click |
| **Cancel** | Stops the displayed prompt from ever being written |
| click | On a prompt: send it now. Otherwise: pause / resume forwarding |
| hover | Reveals the ✕ that ends the session (panel states only) |
| menu bar 🤖 | Always there while the app runs — shows which session it is, plus **Pause/Resume** and **Quit** |

Paused, the chip reads `⏸️ 🤖 folder@branch` at 0.30 opacity and the menu bar
icon becomes ⏸️🤖. The point of pausing is to get the mouse and the keyboard
back — the wheel goes to the app underneath, the back button types Return again,
and no dictation can be started. The relay stops acting on everything: no context
capture, no screenshots, nothing written to the outbox.

## How dictation is captured

The relay owns the whole path. **Click the mouse wheel** while a terminal is bound
and it opens the microphone itself; **click it again** to end the recording, or
hold it for two seconds to throw the dictation away. Rebinding is the wheel with
the **left button already held** — a chord, so that a bare click is free to mean
the thing it means dozens of times a day. The WAV goes to a Whisper
running on this Mac, and the transcript goes to the agent — nothing is ever typed
or pasted into whatever holds the caret.

The selection is read via Accessibility (`kAXSelectedTextAttribute`), falling
back to a simulated ⌘C for apps that don't expose it — with the full clipboard,
every representation, snapshotted and restored around the probe.

### The recogniser

It needs `mlx_whisper` (`pip install mlx-whisper`) and `ffmpeg`, which
`mlx_whisper` shells out to for decoding; the model is
`mlx-community/whisper-large-v3-turbo`, overridable with `RELAY_WHISPER_MODEL`.

The weights are ~1.5 GB resident, so the helper is **not** started at login: it
comes up when a bind or a wheel click says a dictation is coming, and it is
released when the session ends. The menu bar's `Local Whisper` row says whether
it is loading, and what it is holding while it is up.

The interpreter is **found by probing, not taken from PATH**: an app launched from
Finder or a LaunchAgent inherits launchd's bare `PATH=/usr/bin:/bin:/usr/sbin:/sbin`,
where `python3` is Apple's — which has no `mlx_whisper` and cannot be given one.
The first `python3` that can see the module wins, and `RELAY_WHISPER_PYTHON` names
one outright. `/opt/homebrew/bin` and `/usr/local/bin` are put on the helper's PATH
for the same reason, so its `ffmpeg` is findable too.

There is one reading of each recording and nothing to fall back on, so a
low-confidence transcript is **sent with a warning** rather than swallowed:
silence is the one outcome you cannot notice and correct. The pre-send panel
holds it long enough to fix or cancel.

Measured over 442 real dictations (163 min): 2.5% of local transcripts come back
semantically broken, and they are overwhelmingly clips under five seconds, where
Whisper hallucinates fluent nonsense. A gate on decoder confidence catches most
of those; the message an agent receives says the text came through a recogniser
that can invent a sentence.

### The voice corpus

While the relay runs, every dictation also leaves the **recording** beside the
transcript, in `~/.walkie-talkie/voice-corpus/`:

```
2026-08-17/14-30-22-local123.wav    16 kHz mono — what you said
2026-08-17/14-30-22-local123.txt    what the model made of it
corpus.jsonl                        one line per sample, with metadata
```

It exists so a recogniser can be judged on **your own voice** later — the words
you actually say to an agent, at the speed and in the accent you say them. The
`.txt` is the transcript alone, so it can be diffed directly against another
model's output over the same WAVs; everything else (duration, detected language,
the app that was in front, `engine: "whisper-local"`) is in the manifest.

Note what it is **not**: a reference transcript. The line beside each recording
is what the model that produced it heard, so scoring that same model against it
would measure nothing.

Nothing prunes this folder — it is meant to accumulate, at roughly 35 MB a day
of speech. Delete it if you don't want it; the relay recreates only what arrives
after that.

## Build

```bash
./build-app.sh          # → /Applications/Walkie Talkie.app, signed
```

The `.app` wrapper is not cosmetic: macOS keys Accessibility and Screen Recording
grants to a signing identity plus bundle id, and a bare SwiftPM binary is ad-hoc
signed with a fresh identity on every rebuild — so you would re-grant permission
after every change. Set `CODESIGN_IDENTITY` to your own signing identity.

Requires macOS, **Accessibility** (event tap + selection read), **Screen
Recording** (screenshots) and the **Microphone**.

## Debug switches

- `kill -USR1 <pid>` — writes what is on screen to `~/.walkie-talkie/snapshot.png`.
  The overlay sets `sharingType = .none` so it never lands in the screenshots it
  takes, which also makes it impossible to photograph while working on it — and
  on macOS 15 the old opt-out below no longer buys it back. So it draws itself
  instead: the pictures above were made this way.
- `RELAY_DEMO=1` — walks the UI through its states with canned content, which is
  what makes those pictures reproducible. Nothing is written to the outbox.
- `RELAY_CAPTURABLE=1` — asks for `sharingType = .readOnly`. Kept for older
  systems; on macOS 15 `screencapture` returns a transparent image regardless.

## Licence

[The Unlicense](LICENSE) — public domain. Take it, change it, ship it, sell it;
no attribution required.
