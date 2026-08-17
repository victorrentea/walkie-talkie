# Wispr Relay

A small macOS overlay that **relays [Wispr Flow](https://wisprflow.ai) dictation
into a running coding agent** — along with the text you had selected and
screenshots of what you were looking at — so you can drive the agent while
looking at something else entirely: a browser, an IDE, a projector.

Wispr Flow types its transcript wherever the caret is, which is exactly wrong
when you are talking *about* something you are only reading. Wispr Relay takes
that same speech and sends it somewhere else: to whatever agent is watching its
queue. That is the whole idea, and the name — it is not tied to any one agent
(it was called Claude Bubble until it turned out to work with all of them).

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

Bound or not, the overlay appends JSON lines to `~/.wispr-relay/outbox.jsonl`.
Anything that watches that file can consume them; there is no back-channel.

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
| `POST /unbind` | back to outbox-only |
| `GET /target` | what it is currently aimed at |
| `POST /test/dictation` | `{"text":"…"}` — put a sentence through the whole path without speaking one |
| `POST /test/corpus` | `{"id":"<transcriptEntityId>"}` — collect the voice-corpus sample for a Wispr row that already exists |

## Input

| input | effect |
|---|---|
| start dictating | Red flash, screen captured, selection grabbed — all automatic |
| **back mouse button** | One more screenshot — but only while dictating; otherwise the button is untouched |
| **F3** | The same shot, from the keyboard |
| **hold ⌘⇧ in Chrome** | Outlines and names the element under the cursor |
| **⌘⇧-click in Chrome** | Adds that element's selector, page URL and text to the message; the page never sees the click |
| **Cancel** | Stops the displayed prompt from ever being written |
| click | On a prompt: send it now. Otherwise: pause / resume forwarding |
| hover | Reveals the ✕ that ends the session (panel states only) |
| menu bar 🤖 | Always there while the app runs — shows which session it is, plus **Pause/Resume** and **Exit** |

Paused, the chip reads `⏸️ 🤖 folder@branch` at 0.30 opacity and the menu bar
icon becomes ⏸️🤖. Wispr Flow itself keeps working exactly as before — the point
of pausing is to dictate into a browser, a chat, a commit message without those
words also reaching the agent. The relay just stops acting on the transcripts:
no context capture, no screenshots, nothing written to the outbox.

## How dictation is captured

[Wispr Flow](https://wisprflow.ai) pastes its transcript wherever the caret is,
which is useless when you are dictating *about* something you are only reading.
So the overlay reads Wispr's own local history instead:
`~/Library/Application Support/Wispr Flow/flow.sqlite`, opened **read-only** and
polled once a second for rows newer than a watermark taken at startup.

The selection is read via Accessibility (`kAXSelectedTextAttribute`), falling
back to a simulated ⌘C for apps that don't expose it — with the full clipboard,
every representation, snapshotted and restored around the probe.

### The voice corpus

While the relay runs, every dictation also leaves the **recording** beside the
transcript, in `~/.wispr-relay/voice-corpus/`:

```
2026-08-17/14-30-22-a1b2c3d4.wav    16 kHz mono — Wispr's own audio, copied
2026-08-17/14-30-22-a1b2c3d4.txt    what Wispr made of it
corpus.jsonl                        one line per sample, with metadata
```

This is groundwork for one future decision — whether a **local ASR model** could
replace Wispr Flow — and it collects paired data now because it cannot be
collected later: Wispr keeps each recording for roughly a fortnight and then
drops it, leaving the text alone.

The audio is Wispr's own `History.audio` blob, which is already a complete
16 kHz mono 16-bit `.wav`; the relay copies bytes and never opens the
microphone. That is what makes the eventual comparison like-for-like — both
models score the same signal.

The `.txt` holds Wispr's *formatted* text and nothing else, so it can be diffed
directly against another model's output. The manifest carries the raw `asr`
string beside it, which is the fairer reference: the formatted text has been
through Wispr's LLM post-processing, and charging a plain recogniser for
punctuation and casing would flatter the wrong side.

Nothing prunes this folder — it is meant to accumulate, at roughly 35 MB a day
of speech. Delete it if you don't want it; the relay recreates only what arrives
after that.

## Build

```bash
./build-app.sh          # → /Applications/Wispr Relay.app, signed
```

The `.app` wrapper is not cosmetic: macOS keys Accessibility and Screen Recording
grants to a signing identity plus bundle id, and a bare SwiftPM binary is ad-hoc
signed with a fresh identity on every rebuild — so you would re-grant permission
after every change. Set `CODESIGN_IDENTITY` to your own signing identity.

Requires macOS, **Accessibility** (event tap + selection read) and **Screen
Recording** (screenshots). Wispr Flow is optional — without it, screenshots still
work and nothing else does.

## Debug switches

- `kill -USR1 <pid>` — writes what is on screen to `~/.wispr-relay/snapshot.png`.
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
