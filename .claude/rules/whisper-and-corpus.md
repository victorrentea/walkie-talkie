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
- **`WisprWatch` is not that rule coming back** (2026-09-11). It reads no word, file or transcript —
  one CoreAudio boolean about a pid, so the halo can be up while Wispr Flow is listening. The rule
  above is about a *recogniser*; this is the orange dot. → journal: *The ring covers Wispr Flow's dictations too (2026-09-11)*
- **`MicRecorder.startMetering()` is `start(to: nil)` — the microphone open for a level and nothing
  else.** Same device, converter, tap and 16 kHz mono int16 the meter was fitted on, and no
  `AVAudioFile`: `append` writes only `if let file`, `stopMetering` discards. Nothing reaches the
  corpus, the model or the outbox, and it exists for exactly one caller — the halo, during a Wispr
  Flow dictation. Two clients on one input device is ordinary on macOS; Wispr's audio is untouched.
  → journal: *The ring covers Wispr Flow's dictations too (2026-09-11)*
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

- **One line per engine since 2026-09-23** — `Sample.engine` (`whisper-local` · `elevenlabs` ·
  `wispr-flow`; a line without it is the local model's). Until then only `LocalWhisperSource` ever
  called `record`: the file's last line was 2026-09-18, and every Scribe and Wispr sentence since
  had been timed against the local model's curve (2.7 s promised for a 0.7 s Wispr sentence). Each
  source files its own round trip **from its own close** and sets `DecodeRate.activeEngine`
  *before* `didStopListening`, so every `seconds(for:)` reader is asking about the right engine
  without naming one. Under eight samples the engine's `prior` is rescaled by the median
  measured/prior ratio (a ratio through the origin cannot describe a hosted engine's fixed round
  trip). `typical(for:)` is the line without headroom — what an animation that should end when the
  words land is fitted to; `seconds(for:)` stays the chip's near-worst case. Every filed sample
  logs `decode rate [engine]: …`, and one the rewind predicted logs `⏱️ transcription [engine]:
  predicted X (ceiling Y) … took Z — ±N%`. `swift test` covers it (`Tests/WalkieTalkieTests`).
- **The estimate is a line fitted to the last fifty decodes**, `intercept + slope × audio`; a decode
  is a fixed round trip (JSON out, ffmpeg, the answer back) *plus* a cost per second of audio, and
  one ratio can fit one of those or the other. It drives the filling `Transcribing...` word (no
  seconds readout since 2026-09-08); rounding is up, deliberately. → journal: *The recogniser*
- **The line is a median of slopes, and it carries measured headroom** (2026-09-16, *"estimările de
  timp cât durează transcrierea sunt subestimate"*). Theil–Sen — median of every pair's slope,
  intercept the median of the residuals — because one repetition loop in the window hands least
  squares the fit for the next fifty dictations. And the answer is `line × headroom`, where
  `headroom` is the **0.80 quantile of that line's own residual ratios**: the old fit was unbiased
  (median estimate/actual **1.10**) and still short on **40%** of dictations, and a bar that fills
  and sits there is the app claiming the words have landed. Replayed over the 640 decodes in the
  file: covered 60% → **74%** (short clips 52% → **65%**), bar-full-early 0.65 s → 0.55 s,
  unfinished bar 0.45 s → 0.63 s, median estimate/actual 1.10 → **1.27** — nowhere near the 4×
  that produced the 09-07 complaint below.
- **The machine load is recorded and still not modelled**, and that was re-asked with numbers on
  2026-09-16 rather than argued. The effect is real (median ratio **0.034×** under run queue 2,
  **0.085×** over 35) and it is already inside the window, because the last fifty decodes are the
  same machine in the same hours: against the fitted line's residuals the correlation is **0.13**
  with the load relative to the window's and **0.02** with the load itself. A `1 + c·ln(1+load)`
  term, a second regressor, the whole fit in log space and the twenty nearest samples in load each
  bought 1–3 points of coverage and paid for them one for one in unfinished bar.
- **Most of what is left is a Whisper repetition loop, and it cannot be predicted.** Pairing the
  file against `relay.log`'s `local whisper: … (cr N)` lines (577 decodes), the strongest signal is
  the transcript's **compression ratio** — 0.49 against the decode time, 0.52 against the line's
  residual — not the audio (0.42) and certainly not the load (0.03). The worst under-predictions
  are all one animal: 29.8 s decoded in 20.4 s at `cr 56.8`, 10.2 s in 9.4 s at `cr 51.5`, 4.1 s in
  9.6 s at `cr 37.1`, against `cr 1.3…1.5` for an ordinary sentence. It is known a second too late
  to predict anything, so **~4% of decodes will overrun any estimate this file can make by more
  than five seconds**; `chars` and `compression` are filed beside the seconds so the next person to
  ask can tell a slow machine from a Whisper talking to itself. Both are **optional** — six hundred
  lines were written before there was anywhere to put them.
- **Never put a narrow ratio filter back.** Until 2026-09-07 it was a mean ratio behind a
  `0.04…0.60` filter and `relay.log` shows it discarding the truth: `ignoring 0.033× (45.5s audio,
  1.5s decode) — outside 0.04…0.60` — nineteen such pairs, 22 s to 207 s of audio, every one warm,
  every one rejected for being *too fast*; this Mac decodes at 0.033×. What survived were short
  clips and cold decodes, the mean sat near 0.15, and a two-minute dictation was promised twenty
  seconds for four seconds of work (*"14 secunde și s-a terminat în 3"*). Least squares over those
  pairs is `0.0355 × audio − 0.10`, worst residual 0.39 s. → journal: *The recogniser*
- **`~/.walkie-talkie/decode-rate.jsonl` is appended forever**, one `{at, audio, decode, load, cold, chars?, compression?}`
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

## The microphone (`InputDevice.swift`)

Five devices Victor names by their picture — 🎙️ Elgato Wave XLR, 🎤 the DJI receiver, 🏛️ the
room's Stage Speakerphone (2026-09-22), 🎧 Bose, 💻 the built-in — one table (`InputDevice.known`),
and one resolver every reader shares. **The DJI transmitter over Bluetooth (`tx`, 📡/🎤) had a row
for one day and went on 2026-09-23** (Victor: *"vom scoate DJI mic mini tx din lista. pastram doar
RX pt moment cu emoji = 🎤"*); an old `tx` in `mic/choice` reads as `auto`. The receiver's needles
never include a bare `dji mic`, which is the transmitter's name (`DJI Mic Mini-B83BBE`).

- **The WH-1000XM3's microphone is never recorded through** (2026-09-23, Victor: *"niciodata nu voi
  folosi mic de pe WH casti bt"* — *"e f prost"*). `InputDevice.neverRecord` (`wh-1000`) sits
  beside the ladder; no row matches it, and the system-default fallback skips it too — to any other
  input, and with none left `select` answers nil and `MicRecorder.start` refuses. The HFP
  microphone is 16 kHz and opening it drags the headphones' playback down to 16 kHz mono as well.

- **The green `🎤 Listening to: <label>` tab is this app's** (2026-09-23, Victor: *"pune notificarea
  verde de jos sa vina de la walkie"*) — `MicAnnouncer`, on a device-list change or a `mic/choice`
  change, 0.6 s settle, never for the launch baseline, announcing `resolve()` and **not** the system
  default (addons moves the default off the WH on its own, and that must not raise a second tab).
  The look is addons' `BottomTabBanner`, reproduced here because this app may not depend on it.
- **`resolve()` is the single answer**, read by `select` (what records), by the chip's mark and by
  the menu's top row. Three readers computing "which microphone" separately is three ways for the
  glyph, the tick and the recording to disagree. → journal: *The chip says which microphone, and the menu picks it (2026-09-19)*
- **A pick whose device is not plugged in falls back to automatic, and the glyph follows the
  fallback.** The menu greys those rows, but a receiver can be unplugged *after* it was picked, and
  a dictation that records nothing because a setting outlived a cable is the exact failure this
  file exists to prevent. → journal: same
- **`auto` is the default and walks a ladder: 🎙️ XLR ▸ 🎤 DJI ▸ 🏛️ Stage ▸ 🎧 Bose ▸
  💻 built-in** (Victor,
  2026-09-19: *"the preference of mic to use is: XLR>DJI>BOSE>MAC … order them like this in menu and
  impl autoselection"*). **This supersedes *the DJI receiver is the microphone whenever it is
  plugged in*** — what that rule could not express is a desk with both the XLR and the receiver on
  it, which is his ordinary desk. The ranking is quality, not convenience: a condenser through a
  preamp, then a lavalier on his collar, then a headset, then a microphone two feet away across a
  desk with a projector fan in the room. → journal: same
- **`InputDevice.known` is that order, once.** It is the menu's rows top to bottom *and* the ladder
  `resolve()` walks — a menu whose order disagreed with the automatic pick would teach the wrong
  thing every time he opened it. The `Automatic` row spells it out
  (`Automatic — 🎙️ ▸ 🎤 ▸ 🏛️ ▸ 🎧 ▸ 💻`) rather than asking him to remember it. → journal: same
- **It is also `victor-macos-addons`' list, row for row** (2026-09-22). That app transcribes the
  room continuously through the same five microphones and shows the same five rows in its own menu;
  `🏛️ Stage` is here only because it was there, and it sits *below* the two lavaliers rather than
  second, where addons used to rank it — a far-field room mic with AGC beats a condenser pointed at
  one chair in a hall, but the DJI is on his collar wherever he walks, and Victor's stated order
  wins. Its `MicRosterTests` reads **this file** and fails when the two drift; nothing here reads
  anything of its, which is the direction the rule requires. → journal: *One microphone, two menus*
- **The system default is the last line of defence, not a rung.** It is consulted only when none of
  the four is present, because macOS points it at whatever last claimed it — including the eleven
  virtual devices on this Mac. Everything below about the receiver is what *automatic* meant until
  2026-09-19 and why following the system default is not an option. → journal: same
- **Matched on name AND manufacturer, both lowercased into one haystack.** The Elgato is the mirror
  of the DJI's case: `Wave XLR` is the product and `Elgato Systems` the maker, while `Wave Link
  MicrophoneFX` / `Wave Link Stream` are the virtual devices its driver installs, made by `Corsair
  Memory, Inc.` — so neither needle reaches them. → journal: same
- **The preference is a file, `~/.walkie-talkie/mic/choice`** (`MicChoice`), holding one id —
  `auto` or one of `known`'s — and **Victor Addons reads and writes the same file**, so a pick made
  in either menu lands in the other without a restart (*"când o schimb într-una, să se schimbe
  automat și în cealaltă"*). `UserDefaults`' `micDevice` is still written and is read **once**, as a
  migration, so a device picked before the file existed survives the upgrade. A file rather than a
  route, although both apps run an HTTP server the other calls: a route only works while both are
  up, and the microphone is picked between sessions at least as often as during one. **Its own
  subfolder** because the change notification is a `DispatchSource` on the *directory* — an atomic
  write replaces the inode — and `~/.walkie-talkie/` itself has `relay.log` and `outbox.jsonl`
  appended to constantly. The watcher fires on this app's own writes too, deliberately: the handler
  only makes the menu agree with the file, and doing that twice is free. **This does not make
  Walkie depend on addons** — it reads and writes its own home folder and does not care whether
  anything else on the Mac has heard of it. → journal: *One microphone, two menus*
- **The resolver still lives in `InputDevice`** beside the matching table: the thing that resolves
  a pick into a device is the only thing that can say whether the pick is still possible.
  → journal: same

## The DJI receiver, second rung of *automatic* (`InputDevice.swift`)

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

## `start(to:)` answers *is the microphone open*, and that is not *did I open it* (2026-09-20)

- **A session already open may not be answered with `nil`.** `nil` is this function's success, so
  `guard !isRecording else { return nil }` told every caller *the microphone is open* while opening
  nothing: the source logged `recording started`, the halo went up, the file it was handed was never
  created, and the upload of an empty WAV sat until the settle's timeout — **33 s, transcript lost,
  and not one line in `relay.log` saying why**. The only trace is an absence: `mic: recording
  through …` is logged once per real open, so a dictation without it recorded nothing.
- **The two cases it conflated.** The *same* destination twice (nil included) is one gesture
  arriving down two paths and keeps the old answer. A *different* destination means the open session
  is stale — a `cancel()` whose recogniser had nothing to cancel never reaches `meter.stop()`, and a
  `stop()` in flight is a CoreAudio teardown on another queue that the next gesture beats by
  seconds. The stale one is closed, its orphan file deleted, and the new recording starts, with a
  `Log.error` naming which it was: this defect's whole nature was its silence.
- **Metering never pre-empts a recording.** `destination == nil` arriving over an open recording is
  a ring wanting a level, and a ring is not worth a sentence; it reads the meter of the recording
  already open, which is what it wanted. The reverse — a recording over a metering session — is
  exactly the swallow above and is the case the fix exists for.
- **`close()` is the teardown `stop()` and the pre-emption share.** The caller holds `lifecycle`;
  `close()` takes `lock` only around field writes and **never across `removeTap` / `engine.stop()`**
  — see *Do not* below. Two copies of a close sequence whose order matters is
  the drift this repo keeps paying for.
- **A harness may not leave the relay `listening`.** `startDictation`'s first guard returns on it
  **silently**, so a stuck flag refuses every 🔼→ Victor makes with no log line and no chip change —
  measured 2026-09-20: a `evals/test_envelope.py` run left it set at 10:18 and the gesture was dead
  until a cancel was sent by hand at 10:39. That file cancels on `atexit` now
  (`_put_the_relay_down`), and `MicrophoneAfterACancel` in it is the regression test for the
  swallowed dictation — open, cancel, open, assert the device line both times. It never speaks.

## The labelling batch suspends itself when Victor is at the Mac (2026-09-22)

Rules for `helpers/human_watch.py` and `teacher_label.Gate`. Victor: *"dacă vezi
mouse move sau taste apăsate să auto-suspenzi scriptul pe durata activității
până la 5 min de inactivitate."* Full reasoning: `docs/teacher-loopback.md`, *The
gate*.

- **Never gate on `CGEventSourceSecondsSinceLastEventType`.** Measured
  2026-09-22: it read **0.02 s** immediately after this process posted two
  synthetic Shift events, so it counts the batch's own keystrokes as human
  activity — a run gated on it suspends after its first clip and never resumes.
- **The discriminator is the source pid**, from the same probe: hardware events
  carry `kCGEventSourceUnixProcessID == 0`, anything posted with `CGEventPost`
  carries the poster's pid and `kCGEventSourceStateID == 0`. The tap ignores
  **every** event with a pid, not only its own — Wispr's ⌘V is not Victor
  either, and treating it as activity would hold the batch down for ever.
- **Listen-only, and nothing else** (`kCGEventTapOptionListenOnly`): a bug in a
  watch that runs all night must not be able to swallow one of his keystrokes.
  Re-enable the tap on `kCGEventTapDisabledByTimeout` or the night goes deaf.
- **A cut-short clip is never a label.** `rig.dictate(abort=…)` raises
  `PlaybackAborted`; Wispr heard half a sentence, so anything it returns
  describes audio the corpus does not contain. The sample stays unlabelled and
  the next run takes it.
- **The locks follow the suspension, in both directions.** 🔒 standing over a
  batch that has stood down says *do not touch your own Mac* to a man already
  touching it, and a resume with no locks is the batch taking the keyboard back
  silently. `HandsOff.acquire()` is idempotent for exactly this.
- **Re-establish the paste sink before the first clip after a resume** — the
  front app is whatever he left there, and the alternative is a sentence of his
  own voice typed into it. `Gate.ensure_sink` waits rather than failing, and
  that is also why the *initial* front-app check no longer refuses: a gated run
  is launched from a terminal and walked away from.
- **`evals/test_human_gate.py`** covers the gate with a fake watch and fake
  locks; the tap itself is a measurement, not a test — `python3
  helpers/human_watch.py` is the live readout.

## Do not

- **Never hold `MicRecorder.lock` across a call into `AVAudioEngine`** (2026-09-24). The tap
  callback runs inside AVFAudio's realtime-messenger mutex and takes `lock` in `append`;
  `removeTap` waits for that mutex. `stop()` holding `lock` across `removeTap` froze the whole app
  on a 🔼← cancel — `sample`: main in `cancelDictationInFlight → LocalWhisperSource.cancel →
  MicRecorder.stop → closeLocked → removeTap → RealtimeMessenger → mutex`, the messenger thread in
  `TapMessage::RealtimeMessenger_Perform → append → lock`. The log shape: `no rewind …` and then
  never `caret halo off`, followed by `back click refused — the relay's own engine is mid-sentence`.
  `lifecycle` (a second lock `append` never takes) serialises `start`/`stop` across the engine calls.
- **`MicRecorder.lock` is not recursive: take it exactly once per public entry point, never again
  inside one.** Until 2026-09-24 `start(to:)` took it on its first line and held it to the `return`. On 2026-09-07
  the voiced-seconds commit reset the meter's two fields halfway down `start` inside a second
  `lock.lock()` — the reflex every CoreAudio-thread write to `voiced`/`noiseFloor` correctly
  follows — and deadlocked the **main thread** on the first dictation of the build, with the tap
  still logging mouse edges that led nowhere. The log shape that dates it: `🎙️ forward button —
  Replace Wispr` and then never `🎙️ local recording started`. Victor reported *"cum apas forward pe
  mouse se blochează"*; the forward button was innocent. → journal: *The mic's own lock is not recursive, and `start` already holds it*
- **Do not answer `start(to:)` with `nil` for a session that is already open unless it is the same
  destination.** `nil` is *the microphone is open*, and saying it while opening nothing loses the
  whole sentence in silence — see the section above.
- **Do not leave a harness run with `listening` set.** Cancel on the way out; the guard that
  refuses the next gesture is silent.
- **Do not reintroduce any of the Wispr Flow database path** (see *One recogniser*). → journal: *The recogniser*
- **Do not touch the language pin or the prompt without re-reading `evals/short-clip-lid.md`.** → journal: *The language is pinned to {ro, en}, and the prompt carries his vocabulary (2026-09-07)*
- **Do not re-key the corpus manifest as evidence about this model** — its `detectedLanguage`/`asr`
  are Wispr's. → journal: *It counts voiced seconds, not elapsed ones*
