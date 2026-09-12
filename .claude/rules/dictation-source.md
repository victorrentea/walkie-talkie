# The dictation source

Rules for `DictationSource`, `WisprFlowSource`, `LocalWhisperSource` and `tools/wispr-test.sh`.
Full history and reasoning: `docs/journal.md` — *Wispr Flow everywhere (2026-09-12)*.

## One interface, and nothing downstream may look behind it

- **`AppDelegate` holds a `DictationSource` and never names an implementation.** The chip, the
  halo, the settle, the corpus and the destination routing read the protocol only. The one place
  either concrete class appears is `wireDictationSource()` and the `/test/wispr*` routes, which are
  named after Wispr on purpose. → journal: *One interface, because a second branch is how the first
  one rots*
- **Every callback lands on the main queue.** The two sources produce their edges on three
  different threads between them (CoreAudio's listener queue, a transcription callback, the event
  tap), and what the callbacks drive is AppKit. One rule at the boundary, not a hop per call site.
- **`isRecording` is the source's; `listening` is the relay's.** The first answers *is a microphone
  open*, the second *does this app have a sentence in flight*. They are not the same instant and
  every gate in `AppDelegate` means the second.

## The gesture opens the dictation, the microphone confirms it

- **`didBegin` fires on the chord, not on the CoreAudio edge.** Measured 2026-09-12: 324, 478, 528,
  634, 674 ms warm — and **5.0 s and 6.0 s** cold. Everything a dictation opens with (the ring, the
  chip, the context shot, the ⌘C probe, the music pause) fires there, or he watches them arrive in
  two instalments. → journal: *The ring shrank away and came back*
- **The microphone edge must never re-open.** It cancels the retraction, logs `⚡ mic edge confirms
  the ring N ms after the gesture`, and returns. A second `didBegin` takes the halo down and puts it
  back, which is the flicker this whole section exists to remove.
- **`speculativeGrace` is 12 s** — the worst measured open × 2, never under three. A retraction is
  for a chord Wispr *ignored*; that is rare enough to be worth the patience, and a beacon that
  flickers is worse than one briefly wrong.
- **Push-to-talk is the one gesture that only raises the beacon.** Two held modifiers (right ⌘ +
  right ⌥) also fire on a ⌘⌥ meant for something else, and a false `didBegin` costs a screenshot
  and a ⌘C probe posted into whatever he is working in.

## Catching Wispr's transcript

- **Its delivery is a synthetic ⌘V — measured, not assumed** (2026-09-12): keycode 9, flags
  `0x20100000`, from pid 4904 `Wispr Flow`, 1.6 s and 5.9 s after the microphone closed on the two
  sentences that proved it. The `probe:` line in `relay.log` is that measurement and it is armed on
  every dictation, so the day it stops being a ⌘V the log says so. → journal: *The probe*
- **The swallow is narrow: V + ⌘, from a process whose name says Wispr, inside the capture
  window.** Victor's own ⌘V carries pid 0 and can never match; this app's own carries
  `backButtonStamp`.
- **Swallow the `keyUp` with the `keyDown`, and leave the ⌘ alone.** Passing a release whose press
  was swallowed hands the app underneath an orphan; the modifier goes out and comes back balanced.
- **`captureTimeout` is 30 s and is not the ring's timeout.** Wispr's round trip: avg 2.6 s, max
  22.8 s. Six seconds lost an 81-second dictation on the evening the wrap shipped. The capture costs
  one flag and can afford to wait; the ring is on screen and stops at `settleTimeout` (20 s).
- **A new dictation closes a capture still standing**, or it takes the next sentence's ⌘V as this
  one's answer.

## Do not

- **Do not read Wispr Flow's database.** The 2026-08-29 rule stands and Victor restated it when he
  asked for the wrap. The pasteboard is where Wispr itself puts the sentence a millisecond before
  it presses ⌘V, and `pasteText` puts its own there too.
- **Do not turn `copy_last_text` (⌘⌃C) back on by default.** It hands back *the last text Wispr
  produced* — after a failed sentence, the previous one — and delivering a five-minute-old
  paragraph as though he had just said it is worse than losing the sentence. Measured once: the
  chord went out and `changeCount` never moved. `WT_WISPR_COPY_FALLBACK=1`.
- **Do not delete `LocalWhisperSource`.** It is the fallback for the day a Wispr update changes how
  it delivers, the only recogniser that works with no network, and the baseline `evals/` scores the
  corpus against.
- **Do not let the corpus stop growing.** The halo's meter writes its WAV so a Wispr dictation has
  audio to file; `engine` distinguishes `wispr-flow` (through Wispr's formatting pass) from
  `whisper-local` (raw).
