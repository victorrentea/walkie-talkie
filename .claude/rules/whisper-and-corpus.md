---
paths:
  - "Sources/WalkieTalkie/Transcriber.swift"
  - "Sources/WalkieTalkie/MicRecorder.swift"
  - "Sources/WalkieTalkie/DecodeRate.swift"
  - "Sources/WalkieTalkie/InputDevice.swift"
  - "Sources/WalkieTalkie/VoiceCorpus.swift"
  - "helpers/**"
  - "evals/**"
---

# Whisper, the microphone and the voice corpus

Rules for the local recogniser (`LocalWhisper` + `helpers/whisper_helper.py`), the decode-time
estimate, the input device, the level meter and the corpus that every dictation is filed in.
Full history and reasoning: docs/journal.md — see the sections named after each rule below.

## One recogniser

- **There is one recogniser and no setting to change it.** The relay records through `MicRecorder`
  and transcribes locally with `mlx_whisper` (`pip install mlx-whisper`) plus `ffmpeg`; the model is
  `mlx-community/whisper-large-v3-turbo`, overridable with `RELAY_WHISPER_MODEL`. → journal: *The recogniser*
- **Never reintroduce the Wispr Flow database path.** Until 2026-08-29 the relay watched Wispr Flow's
  `flow.sqlite`, transcribed the WAV blob it found there, swallowed Wispr's own paste and fell back to
  Wispr's text. All of it went whole: `WisprWatcher.swift`, `FlowDB.swift`, `DictationMonitor.swift`,
  the `TranscriptionEngine` setting, `HotkeyTap.blockInjection`, and the `POST /engine`,
  `POST /test/corpus` and `POST /test/transcript` routes. If a fallback recogniser is ever wanted, it
  is a second *local* model, not another app's database. → journal: *The recogniser*
- **A daemon, not a subprocess per dictation — measured.** Importing `mlx_whisper` costs 7.4 s and
  the first transcription another 2.8 s for the weights, against 1.3 s once warm; shelling out each
  time would put ten seconds between the end of a sentence and the agent seeing it.
  `whisper_helper.py` starts once, warms up on a second of silence, answers one JSON line per request
  at ~0.1× the audio's duration. → journal: *The recogniser*
- **Loaded at launch, released when the session ends** (2026-09-06). `applicationDidFinishLaunching`
  calls `startWhisper`; the relay is a login item, so the ten seconds are free at launch instead of
  charged to the first sentence of the day. Resident cost: relay 56 MB, helper 2.5 GB once a
  transcription has run. → journal: *The recogniser*
- **Keep the two gesture call sites; `startWhisper` is idempotent.** ⌘⌃B binding a terminal and a
  wheel hold on a model that is not up still call it — they are what retries a launch load that
  failed (no `mlx_whisper`, most likely) instead of leaving the relay deaf until restart.
  `RELAY_SHOOT` is excluded: that run draws the state pages and quits. → journal: *The recogniser*
- **`recordWhenModelReady` is set only when the hold asked for the load.** A load started by a bind
  is Victor pointing the relay at a terminal, a different sentence, and must not open the
  microphone. → journal: *The recogniser*
- **The load shows as ⏳ in the menu bar only** (`⏳🤖`, `<model> — loading…` in its menu); nothing
  on the chip. `AppDelegate.setEngineLoading` is a one-liner into `StatusItem`. → journal: *The recogniser*
- **`GET /engine` reports which model is loaded and whether it is ready** — enough for a test to
  wait out a load. `POST /test/dictation` enters *below* the recogniser with a fabricated string, so
  it says nothing about it. → journal: *The recogniser*

## The decode-time estimate (`DecodeRate.swift`)

- **The estimate is a line fitted to the last fifty decodes**, `intercept + slope × audio`; a decode
  is a fixed round trip (JSON out, ffmpeg, the answer back) *plus* a cost per second of audio, and
  one ratio can fit one of those or the other. It drives the filling `Transcribing...` word (no
  seconds readout since 2026-09-08); rounding is up, deliberately. → journal: *The recogniser*
- **Never put a narrow ratio filter back.** Until 2026-09-07 it was a mean ratio behind a
  `0.04…0.60` filter and `relay.log` shows it discarding the truth: `ignoring 0.033× (45.5s audio,
  1.5s decode) — outside 0.04…0.60` — nineteen such pairs, 22 s to 207 s of audio, every one warm,
  every one rejected for being *too fast*; this Mac decodes at 0.033×. What survived were short
  clips and cold decodes, the mean sat near 0.15, and a two-minute dictation was promised twenty
  seconds for four seconds of work (*"14 secunde și s-a terminat în 3"*). Least squares over those
  pairs is `0.0355 × audio − 0.10`, worst residual 0.39 s. → journal: *The recogniser*
- **`~/.walkie-talkie/decode-rate.jsonl` is appended forever**, one `{at, audio, decode, load, cold}`
  per decode; the estimate reads only the tail. It supersedes `decode-rate.json`, which held bare
  ratios with no audio beside them — the reason the fault above could only be diagnosed from the
  *dropped*-sample lines of `relay.log`. → journal: *The recogniser*
- **The first decode after the helper starts is recorded but not fitted** — 2.8 s against 1.3 s
  warm, visible as a 4.3 s clip that took 7.3 s. `LocalWhisper.stop()` resets the counter, so the
  next helper's first is cold again. → journal: *The recogniser*
- **Ratios outside 0.005…1.0 are written down but not fitted.** Wide on purpose. → journal: *The recogniser*
- **Below eight samples, or under 15 s of spread, use a median ratio through the origin**; least
  squares on clustered points is a line through noise, and a median survives one cold decode. With
  nothing at all the fallback is `0.3s + 0.045×`. → journal: *The recogniser*
- **File on the success path only.** A decode that returned nothing says nothing about how long
  one takes. → journal: *The recogniser*
- **Load is recorded, deliberately not modelled** — *"loghează … câtă încărcare are mașina și cât
  a durat efectiv"* — so a better rule can be derived later; the recent decodes already *are* the
  machine's load. → journal: *The recogniser*

## Results, failures and the confidence floor

- **An empty result says `No words detected`, and nothing else** (2026-09-08). → journal: *The recogniser*
- **A failure has to be loud**: `⚠️ Whisper unavailable — …` sits on screen for twelve seconds and
  the log says why. There is nothing else to transcribe with. → journal: *The recogniser*
- **The confidence floor is −0.6 and is measured, not chosen.** Over 442 dictations a gate on the
  worst segment's `avg_logprob` at −0.6 caught 7 of the 11 semantically broken outputs and falsely
  rejected 0 of 40 good ones; `no_speech_prob` caught none. The 11 are fluent inventions (`Nu uitați
  să vă abonați la revedere!` for a sentence about an invoice), nearly all under 5 s. → journal: *The recogniser*
- **A low score warns; it never swallows the dictation.** One reading, nothing to fall back on;
  silence is the one outcome Victor cannot notice and correct. The warning goes on the panel and
  into `dictatedHint`. → journal: *The recogniser*

## Language pin and vocabulary prompt (2026-09-07)

- **Read `evals/short-clip-lid.md` before touching either setting** — 803 of his clips, 3212
  decodes, four configs; C (pin + prompt) ships. → journal: *The language is pinned to {ro, en}, and the prompt carries his vocabulary (2026-09-07)*
- **The language is pinned to `{ro, en}`.** Wrong-language decodes went 3.2 % of all clips,
  19.3 % under 5 s, 50 % under 2 s → 0 % in every bucket, at −22 ms (faster: the encoder pass was
  already run to pick a language). The whole change:

  ```python
  model = ModelHolder.get_model(MODEL, mx.float16)   # the cache transcribe() uses
  mel   = A.log_mel_spectrogram(samples[:A.N_SAMPLES], n_mels=model.dims.n_mels, padding=A.N_SAMPLES)
  mel   = A.pad_or_trim(mel, A.N_FRAMES, axis=-2).astype(mx.float16)
  _, probs = model.detect_language(mel)
  language = max(("ro", "en"), key=lambda c: probs[c])   # ← the whole change
  ```

  `pick_language` returns **None** on anything unexpected, falling back to Whisper's own
  unrestricted pick: a helper whose job is to answer must not stop answering because a library
  moved a symbol. → journal: *B — the language pin removes an entire failure mode, for free*
- **Every term in the vocabulary prompt is attested in his own transcripts.** Recall on prompted
  identifiers 0.67 → 0.88 (`Claude` 0.33 → 0.85, `frontend` 0.10 → 0.70, `petclinic` 0.00 → 0.60);
  median WER under 5 s 0.300 → 0.222. `Devoxx`, `repo`, `VS Code` were guessed, checked (0, 1, 2
  occurrences) and thrown out. Capped at 224 tokens, attention weights the tail hardest — a short
  list of things that break, not a glossary. → journal: *C — the vocabulary prompt is the bigger win, and it is not free*
- **The prompt's cost cuts both ways.** 7.0 % of clips improved by >0.1 WER, 4.7 % got worse: it
  biases toward its own words, so `clone` and `cloud` both come out `Claude` on a clip that says
  neither. A trade, not a free win. → journal: *C — the vocabulary prompt is the bigger win, and it is not free*
- **Nothing changes past 12 s** — `condition_on_previous_text=False` drops the prompt after the
  first window. Both settings are short-clip medicine. → journal: *C — the vocabulary prompt is the bigger win, and it is not free*
- **The loop gate is `compressionRatio` at 2.4 (`loopCeiling`).** The prompt costs repetition
  loops (`af af af…` gzips at 39 where prose sits near 1.5); it catches all 12 catastrophic
  regressions and fires on none of the 802 good clips. It warns, it does not swallow.
  **`avg_logprob` cannot do this job** — it caught 2 of 14 loops, because a loop is *confidently*
  wrong. Two numbers, two failure modes. → journal: *The loop gate is the price of C, and it was already in the file*
- **The next move is a VAD gate, not a better prompt.** Every top regression is a clip with almost
  no speech (`you` 1.3 s, `VoxxedDays.` 0.6 s). `MicRecorder.voicedSeconds` is already that VAD;
  nothing gates on it yet. → journal: *Where the worst of it actually lives*

## What the model is worth, measured

442 dictations, 163 minutes, scored against the transcripts the relay was receiving at the time —
a disagreement rate, not an error rate. → journal: *What the local model is actually worth, measured*

| | all | ro | en |
|---|---|---|---|
| semantic similarity | 0.918 | 0.908 | 0.948 |
| rare-word recall | 87.1% | 84.2% | 94.9% |
| WER | 19.4% | 21.1% | 12.8% |

- **Judge by rare-word recall, not WER.** 86.0 % semantically equivalent, 2.5 % broken, the broken
  ones almost all under 5 s (13.6 % vs ~1 % longer). Romanian errors are wrong words, not endings
  (content-WER 21.8 %, unchanged). A mangled identifier costs the agent everything, a verb ending
  nothing. Median speed 0.105× realtime. → journal: *What the local model is actually worth, measured*

## The corpus manifest is not this model's evidence

- **`detectedLanguage` and `asr` in `corpus.jsonl` are Wispr Flow's fields, not this model's.**
  `corpus_harvest.py` copies Wispr's row wholesale (`asr` is `r["asrText"]`; *"No model runs here
  and none is called"*). The first voiced-seconds table read the language off that column and
  understated every figure about three times. `asr` is not a second opinion to score against: it
  disagrees with `text` at median WER 0.008 because they are two fields of the same row. Evidence
  about the local recogniser comes from re-decoding (`evals/short-clip-lid.md`). → journal: *It counts voiced seconds, not elapsed ones*
- **Voiced seconds, not wall clock, sort the failures.** Median dictation is 38 % voiced (p10
  14 %). The local model's own picks over 803 re-decoded clips, before the language pin:

  | voiced | decoded into a language Victor does not speak |
  |---|---|
  | 0–1s | **42%** |
  | 1–2s | **15%** |
  | 2–3s | **1%** |
  | 3–4s | 2% |
  | 4s+ | **0%** |

  against 50 / 28 / 19 / 2 / 0 % by wall clock. The pin removed that failure; the bar still stands
  for everything else that is worse with less to hear. → journal: *It counts voiced seconds, not elapsed ones*

## The DJI receiver (`InputDevice.swift`)

- **Match on name AND manufacturer.** The receiver's USB product name is `Wireless Mic Rx`; the
  brand is only in the manufacturer string `DJI Technology Co., Ltd.`. Matching both is what keeps
  it working across the Mic 2 / Mic Mini line. → journal: *The DJI receiver is the microphone whenever it is plugged in*
- **Never follow the system default input.** This Mac has four virtual inputs (Loopback's `🎙️TO
  Zoom`, Wave Link, Iriun, Teams) plus every headset that ever pairs; any can become the default
  between two dictations and hand back an empty transcript. Same room: peak 16552 through the
  receiver against 855 through the built-in. → journal: *The DJI receiver is the microphone whenever it is plugged in*
- **Chosen per recording, never cached.** `AudioDeviceID` is reassigned on every replug; nothing
  is remembered, which is also what makes unplugging mid-workshop fall back to the built-in. → journal: *The DJI receiver is the microphone whenever it is plugged in*
- **Always set a device, even the default one.** The input unit keeps whatever device it was last
  told about, so a recording after the receiver was unplugged would still aim at a device that is
  gone. → journal: *The DJI receiver is the microphone whenever it is plugged in*
- **Take the tap format from `inputFormat(forBus: 0)`, never `outputFormat`.** `outputFormat` does
  not refresh when `kAudioOutputUnitProperty_CurrentDevice` is set under it: with the receiver
  selected it still said 1ch 44100 while `inputFormat` said 2ch 48000. `installTap` then throws
  `Input HW format and tap format not matching` — an NSException Swift cannot catch — and the
  process aborts the instant a dictation starts (`SIGABRT`, three crash reports, 2026-09-01 18:28).
  Only reachable when the chosen device's format differs from the previous one's. → journal: *The DJI receiver is the microphone whenever it is plugged in*
- **Only the log line says which device.** `mic: recording through Wireless Mic Rx — 48000Hz ×
  1ch` is the only evidence if the switch ever fails; the chip has no room for it. → journal: *The DJI receiver is the microphone whenever it is plugged in*

## The voice corpus (`VoiceCorpus.swift`)

`~/.walkie-talkie/voice-corpus/<day>/HH-mm-ss-<ms>.wav` + `.txt`, one line per sample in
`corpus.jsonl`. It exists so a recogniser can be judged on Victor's own voice later.

- **Beside the outbox, not in Caches.** A corpus is worthless unless it accumulates; `--home` moves
  it with the outbox. → journal: *The voice corpus: audio kept beside the transcript, forever*
- **Day folders; ~35 MB/day of WAV, ~1 GB a month; nothing prunes it.** If that bites, `afconvert`
  to FLAC halves it losslessly — never compress lossily, which puts a second codec between his
  voice and the model being judged. → journal: *The voice corpus: audio kept beside the transcript, forever*
- **The `.txt` is the transcript and nothing else**, ending in a newline; duration, language, front
  app and `engine: "whisper-local"` live in the manifest. Every dictation is stamped with **no
  second reference transcript** — a duplicated text field reads as a comparison that never
  happened. → journal: *The voice corpus: audio kept beside the transcript, forever*
- **The line beside a recording is not ground truth.** It is what the model that produced it
  heard. A field that merely looks like a correction is not one either: the old "what the user
  edited afterwards" column recorded where the text had been pasted, not what was misheard. → journal: *The voice corpus: audio kept beside the transcript, forever*
- **`captureLocal` is called from `stopLocalRecording` beside `send`, never through it.** Filing is
  not acting on a dictation, so it runs for a delivery refused at a shell prompt and for a caret
  dictation alike. → journal: *The voice corpus: audio kept beside the transcript, forever*
- **Read the bytes on the caller's thread**, before the queue hop: the staged WAV is deleted as soon
  as `captureLocal` returns, and a copy queued for later would race it. → journal: *The voice corpus: audio kept beside the transcript, forever*
- **The clock is the key**, `HH-mm-ss` plus the millisecond — one microphone, so two samples cannot
  share a second, and the millisecond keeps a retry from overwriting one. → journal: *The voice corpus: audio kept beside the transcript, forever*

## `MicRecorder`: format, floor, meter

- **16 kHz mono 16-bit through `AVAudioConverter`**, from the device's native rate — the format
  Whisper resamples to and the format every corpus sample is in. Anything under 0.35 s is dropped as
  a misfire. → journal: *A cancelled sentence is kept for five minutes (2026-09-10)*
- **Ask for the microphone while the model loads, not at the first press.** The grant dialog is
  modal and a refusal costs a trip through System Settings; mid-sentence with an agent waiting is
  the wrong moment. → journal: *A cancelled sentence is kept for five minutes (2026-09-10)*
- **A recording is sent even below the confidence floor**; the banner says the score and the panel
  holds it long enough to fix or cancel. → journal: *A cancelled sentence is kept for five minutes (2026-09-10)*
- **`MicRecorder.meter` runs on the converted 16 kHz buffer**, per 1024 frames (64 ms): RMS against
  an adaptive noise floor, 9 dB over it to count as speech, absolute floor 180 underneath. Constants
  come from the corpus replay `evals/voiced-seconds.py` and transfer only because the meter sees the
  same audio. → journal: *The meter*
- **Adaptive, because one threshold cannot serve both microphones** (DJI peaks 16552, built-in
  855). Instant attack down, 2 % release up. The absolute floor catches a recording that is
  entirely room tone. **Both reset per recording** — a carried floor is a floor for a room,
  microphone and distance that may all have changed. → journal: *The meter*

## The menu row

- **`Local Whisper — 1.6 GB RAM` is a disabled readout, read when the menu opens.** The number is
  `ri_phys_footprint` from `proc_pid_rusage` — Activity Monitor's "Memory", not `ps`'s RSS, since
  MLX puts weights in unified memory. A dead helper has no footprint and the row goes back to its
  bare name, so it doubles as proof the helper is alive. → journal: *The menu says what the model costs*

## Do not

- **`MicRecorder.lock` is not recursive: take it exactly once per public entry point, never again
  inside one.** `start(to:)` takes it on its first line and holds it to the `return`. On 2026-09-07
  the voiced-seconds commit reset the meter's two fields halfway down `start` inside a second
  `lock.lock()` — the reflex every CoreAudio-thread write to `voiced`/`noiseFloor` correctly
  follows — and deadlocked the **main thread** on the first dictation of the build, with the tap
  still logging mouse edges that led nowhere. The log shape that dates it: `🎙️ forward button —
  Replace Wispr` and then never `🎙️ local recording started`. Victor reported *"cum apas forward pe
  mouse se blochează"*; the forward button was innocent. → journal: *The mic's own lock is not recursive, and `start` already holds it*
- **Do not reintroduce any of the Wispr Flow database path** (see *One recogniser*). → journal: *The recogniser*
- **Do not touch the language pin or the prompt without re-reading `evals/short-clip-lid.md`.** → journal: *The language is pinned to {ro, en}, and the prompt carries his vocabulary (2026-09-07)*
- **Do not re-key the corpus manifest as evidence about this model** — its `detectedLanguage`/`asr`
  are Wispr's. → journal: *It counts voiced seconds, not elapsed ones*
