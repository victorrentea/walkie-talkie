# Wispr Flow as a teacher: the loopback, and the go/no-go it rests on

The local recogniser is at **WER 19.7% overall, 22.7% on Romanian, 7.1% on
English** (60 clips, 2026-09-01, `helpers/corpus_baseline.py`). Every cheap fix
lost — `large-v3` instead of turbo, forcing `language="ro"`, the Wispr dictionary
as `initial_prompt`. What is left is a LoRA on Romanian, and a LoRA needs a
corpus with labels.

This is where the labels come from: **Wispr Flow transcribes the audio, and its
reading is the label.** Knowledge distillation by pseudo-labelling — Wispr the
teacher, the local whisper the student, and the supervision costs nothing but
wall-clock.

## The asymmetry this exists to break

`helpers/corpus_harvest.py` takes pairs out of Wispr's own database, and it can
only ever take what Wispr still has. Wispr keeps its transcripts for ever and
prunes its **recordings** after about a week:

| measured 2026-09-01 | |
|---|---|
| transcripts in `flow.sqlite` | 12,186, back to January |
| recordings still there | 185, none older than six days |

So **98% of everything Wispr has ever transcribed is text with no audio**, which
is worth nothing to a fine-tune. The harvester is not badly written; it is racing
a deletion it cannot win.

Recording the microphone ourselves inverts the dependency. The audio is Victor's
and it keeps for as long as he likes; the label is asked for **afterwards**,
including for WAVs that are months old by then. The bottleneck disappears.

Two halves, in two repos:

| | where | what |
|---|---|---|
| **collection** | `victor-macos-addons` — `whisper-transcribe/corpus_recorder.py` | utterance WAVs of Victor's voice, all workday, gated on speech and on his voiceprint. See that repo's `docs/transcription.md`, *🎓 Voice corpus* |
| **labelling** | here — `helpers/wispr_loopback.py`, `wispr_probe.py`, `teacher_label.py` | plays each WAV into Wispr and reads back what it heard |
| **the seam** | here — `helpers/mic_corpus_ingest.py` | the addons app writes files; this side owns `corpus.db` |

## Wispr has no API, so we become its microphone

It transcribes a microphone and pastes into whatever has focus. That is the whole
interface. There is no endpoint that takes a file.

```
 ┌──────────────┐   sd.play()   ┌────────────────────┐   mic   ┌────────────┐
 │ corpus WAV   │ ────────────▶ │ Loopback device    │ ──────▶ │ Wispr Flow │
 └──────────────┘               │ (out side→in side) │         └─────┬──────┘
                                └────────────────────┘               │
 ┌──────────────┐                                                    │
 │ flow.sqlite  │ ◀──────────────── it writes the transcript ────────┘
 └──────────────┘
```

**BlackHole is not needed and is not installed.** Rogue Amoeba's **Loopback** is
already on this Mac (`ARK.driver` in `/Library/Audio/Plug-Ins/HAL/`) and already
publishes three virtual devices — `🔊FROM Zoom`, `🎙️TO Zoom`, `🔊OS Output`, the
first of which the live transcription's audience channel already reads from. A
device whose output side feeds its input side is exactly the pass-through this
needs, so the setup is a new Loopback device rather than a new driver.

**The push-to-talk chord was read out of Wispr's own config**, not guessed:
`~/Library/Application Support/Wispr Flow/config.json`, `prefs.user.shortcuts`,
where `"54+61": "ptt"` is macOS keycodes 54 (Right Command) and 61 (Right
Option). `WISPR_PTT_KEYS` overrides it, because it is a setting in an app we do
not control and it will move one day. The same file names the others, which is
worth knowing next time one is wanted: `"49+59+63"` is hands-free
(fn ⌃ Space), `"178+59+63"` Command Mode, `"53+59"` dismiss.

## The one-time setup nothing here can do for itself

Wispr's microphone is chosen in Wispr's own UI and nothing outside it can set it.

1. **Loopback** → new virtual device, named `🎓 TO Wispr` (the rig looks for that
   name first; `--device` overrides).
2. **Wispr → Settings → Microphone → `🎓 TO Wispr`.**
3. **Accessibility** for whichever terminal runs the batch — System Settings →
   Privacy & Security → Accessibility. Without it `CGEventPost` fails *silently*,
   so a whole overnight run would play audio into a device nobody is recording
   and report a hundred timeouts as though Wispr had rejected the channel.
4. **Put Wispr's microphone back** on `Built-in mic (recommended)` when the batch
   is done, or the next real dictation records silence.

Until step 2 is done, `--device '🎙️TO Zoom'` can probe the channel with the
device that already exists.

## The go/no-go, and it is genuinely a go/no-go

```bash
python3 helpers/wispr_probe.py --stage 1   # the setup, ~10 seconds
python3 helpers/wispr_probe.py --n 20      # all four stages
```

Four questions, stopping at the first failure:

1. **Is the channel there?** A virtual device, Accessibility, and a *harmless
   place for the paste to land*.
2. **Does Wispr hear a played-back file at all?** One WAV in, one row out of
   `flow.sqlite`. **This is the question the whole idea rests on.** If Wispr
   filters by device or refuses a virtual input, the idea dies here and nothing
   downstream should be built.
3. **Is the channel clean?** Replay N clips Wispr has *already* transcribed from
   its own microphone and compare its two readings of the same audio. A
   transcript that comes back plausible proves only that something was heard;
   this compares Wispr to Wispr, so any difference is the loopback. Median WER
   should be near zero — above ~0.15 the channel is losing something (check the
   device's sample rate and that the WAV is not being clipped on the way in).
4. **Is the teacher worth it?** The gap against the student, from
   `corpus_baseline.py`. The probe loads no model, on purpose.

## The three hazards, and what is done about each

**1 · Wispr pastes into whatever has focus.** A batch is an hour of Victor's own
speech typed into whatever was open — a source file, a commit message, a Slack
thread. Both the probe and the labeller read the front app and **refuse to start**
unless it is on the allow-list (TextEdit, Notes, Stickies, Wispr Flow, Finder).
Neither opens a document on somebody's desktop unasked; they stop and say so.

**2 · It synthesises keystrokes, thousands of times.** `teacher_label.py` raises
the 🔒 **hands-off locks** for the whole run (`~/bin/hands-off`) and drops them on
the way out — including on Ctrl-C and SIGTERM, because a killed batch that leaves
them up says *do not touch your own Mac* for ever. Locks on screen are the only
way Victor learns a batch is running; he is not reading the terminal.
`PushToTalk` is a context manager for the same class of reason: an exception
between press and release would leave Right Command held down for the rest of the
session.

**3 · It runs in real time.** A minute of audio costs a minute; there is one
Wispr, one microphone and one keyboard, so nothing here parallelises. That is
fine — it is a pass over an archive, run overnight, once. It is **resumable**:
every label is committed as it arrives, so a batch killed at 3 a.m. carries on.
Samples are taken **shortest first**, so a run that is cut short leaves behind the
most *samples*, not the most minutes.

It also gives up after five consecutive failures. Wispr having quit, lost its
network or had its microphone changed all look identical from here, and none of
them get better by pressing a key another four hundred times.

## What gets written

`teacher_text` is Wispr's **`asrText`** — the recogniser's raw reading.

**Not `formattedText`**, which has been through Wispr's LLM for punctuation,
capitalisation and its custom dictionary. Training a speech model on that teaches
the student to imitate a *text* model it does not have, and scores as errors every
comma it could not know about.

Nothing here touches `final_text`, and nothing overwrites a label already
written.

## The ceiling, written down so it is not forgotten

**Distillation reaches Wispr's level on Victor's voice and no further.** By
construction: the student is being trained to agree with the teacher. The only
labels in this corpus that could ever teach it to *beat* Wispr are the ones Wispr
did not write — `editedText`, what Victor fixed by hand after a wrong word, which
`corpus_harvest.py` already comes back for on a fortnight's re-read. There is not
much of it and it is the most valuable column in the whole store; weight those
samples harder at training time.

## Already measured and lost — do not re-try

| tried | result |
|---|---|
| `large-v3` instead of turbo | WER 24.0%, p90 73% — **worse**, despite being the bigger model |
| forcing `language="ro"` | ro 22.7 → 23.0% (flat), en 7.1 → 17.1% — **worse** |
| the 67-term Wispr dictionary as `initial_prompt` | 19.6 → 21.0% on clips that did not collapse — **worse** |

## Order of work

1. Collect — arm 🎓 in the addons app's Transcribing submenu. It only writes
   inside the work window, so an evening costs nothing.
2. `/usr/bin/python3 helpers/mic_corpus_ingest.py` — folds the day's WAVs into
   `corpus.db`. Cheap, idempotent, belongs beside the two-hourly harvester.
3. `python3 helpers/wispr_probe.py` — **the go/no-go**. Do not skip it.
4. `python3 helpers/teacher_label.py --limit 20` once, then `--all` overnight.
5. Only then the LoRA, with ten times the data.
