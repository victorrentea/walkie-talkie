# Claude Bubble

A small floating macOS overlay that relays Victor's input — Wispr Flow
dictation, typed notes, screenshots — into a running Claude Code session, so he
can drive Claude while looking at something else entirely.

Consumed by the `bubble` skill in [`victorrentea/ai`](https://github.com/victorrentea/ai)
(`skills/bubble/`), which ships the built binary and arms the watcher on the
Claude side.

## How it talks to Claude

The bubble is a **one-way producer**. It appends JSON lines to
`~/.claude-bubble/outbox.jsonl`; the skill arms a blocking `wc -l` watcher on
that file, which wakes Claude whenever a message lands. There is no back-channel
— Claude cannot ask Victor anything, because he isn't looking at the terminal.

```json
{"ts":"2026-07-29T08:12:03Z","kind":"dictation","text":"make this shorter","selection":"the paragraph he had selected","app":"Google Chrome"}
```

`kind` is `dictation` | `typed` | `screenshot` | `selection`.

## Input modes

| input | effect |
|---|---|
| **Mouse 5** | Wispr push-to-talk. Snapshots the on-screen selection at that instant; the finished transcript is sent with it. Observed, never swallowed — Wispr still gets the click. |
| **⌃⌥S** | Stash the current screen selection as the prefix for the next message. |
| **⌃⌥P** | Screenshot the display under the cursor and send it. |
| **double-click** | Expand into a text box; ⏎ sends, ⇧⏎ newline, esc cancels. Grows as you type. |
| **single click** | Pause / resume forwarding. |
| **drag** | Move it. |

Shortcuts avoid everything `victor-macos-addons` claims (⌃P, ⌃⇧P, ⌃W, ⌃⌥C,
⌃⌥V, ⌘⌃C, ⌘⌥C, ⌘⌃A, ⌘⌃V, ⌘⌃⌥C, ⌘⌃⌥D) and Wispr's own ⌘⌥V.

## Capturing dictation

Wispr Flow pastes its transcript wherever the caret is — which is useless when
Victor is dictating *about* a browser he's reading. So instead of intercepting
keystrokes, the bubble reads Wispr's own history DB:

`~/Library/Application Support/Wispr Flow/flow.sqlite` → table `History`

- opened **read-only** while Wispr keeps writing (the `-wal`/`-shm` siblings are
  readable by the same user, so committed rows show up immediately)
- polled once a second for `timestamp > watermark`, where the watermark is taken
  at startup — launching never replays the 11k-row history
- a dictation counts as finished at `status IN ('formatted','raw_transcript')`;
  text is `formattedText`, falling back to `asrText`
- served by Wispr's own `idx_history_timestamp_archived_status`, ~6 ms per poll

Note `axText` / `textboxContents` are present in the schema but never populated,
so the selection has to be captured by the bubble itself.

## Capturing the selection

Two strategies, in order:

1. **Accessibility** — `kAXSelectedTextAttribute` on the focused element. Side
   effect free, never touches the clipboard.
2. **Simulated ⌘C** — for apps that don't expose selection over AX (much web
   content). The full clipboard (every representation, not just plain text) is
   snapshotted and restored afterwards.

An empty read never clears an existing stash: pressing Mouse 5 somewhere with
nothing selected must not discard what ⌃⌥S deliberately captured a moment ago.

## Build

```bash
./build-app.sh          # → /Applications/Claude Bubble.app, signed
```

The `.app` wrapper is not cosmetic. macOS keys Accessibility / Screen Recording
grants to a signing identity + bundle id; a bare SwiftPM binary is ad-hoc signed
and gets a fresh identity on every rebuild, forcing a re-grant each time.
Signing the bundle with the stable local identity (`Victor Addons Local Code
Signing`) makes the permission stick across rebuilds — verified by reinstalling
and re-signing with the app still reporting `accessibility trusted=true`.

## Permissions

- **Accessibility** — required, for the event tap and the AX selection read.
  Logged explicitly at startup (`accessibility trusted=… eventTap=…`), because a
  tap can exist and silently receive nothing.
- **Screen Recording** — required for ⌃⌥P and for the automatic context capture.

## Every capture shows a red vignette

Both grabs announce themselves the same way — a red border fading inward, then
out: the deliberate ⌃⌥P shot *and* the automatic one taken when dictation
starts. A frame of the screen leaves the machine either way, and the silent one
is precisely the one nobody could audit. The dictation capture is guarded so it
fires once per dictation, not once per trigger.

Red, not yellow: yellow is `victor-macos-addons` saying it captured something,
red is this bubble saying it went to Claude.

## Screenshots never contain the bubble

Belt and braces: the panel sets `sharingType = .none` *and* hides itself for the
duration of the grab (`screencapture` is a separate process taking a fresh frame,
so not being on screen is the only guarantee).

Display numbering for `screencapture -D` comes from `CGGetActiveDisplayList`,
**not** the online list — online includes asleep/mirrored displays, so with a
sleeping external monitor the index overshoots and `screencapture` rejects it
outright ("Invalid display specified"), silently producing no file.
