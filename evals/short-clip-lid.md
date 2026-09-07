# Short clips: pinning the language, and telling the model his vocabulary

`CLAUDE.md` names this lever and says nobody has pulled it:

> **If the failure itself is ever worth fixing rather than forecasting**, the
> lever is that `language=None`: restricting language ID to `{ro, en}` would
> have caught every case counted above, since Victor speaks only those two.
> That is a change to the recogniser, not to the overlay, and it has not been
> made.

It would have caught every case. **Measured on 803 of his own clips: it catches
every case, and it is free.** A second change — telling the model the two dozen
words he actually says — turns out to be worth more than the first, and it is
the one that comes with a bill.

## What was run

803 clips, 317 minutes of audio, every row in
`~/.walkie-talkie/voice-corpus/corpus.jsonl` that carries an `asr` field, in one
process against one warm copy of `mlx-community/whisper-large-v3-turbo`. Four
configs each, 3212 decodes, 146 minutes wall. Nothing was sampled and nothing
was skipped: the full set fit inside an afternoon once the model was loaded once
instead of 3212 times.

| | `language=` | `initial_prompt=` |
|---|---|---|
| **A** — today | `None` | — |
| **B** | argmax over `{ro, en}` of the model's own LID | — |
| **C** | as B | `VOCAB` |
| **D** | `None` | `VOCAB` |

`condition_on_previous_text=False` in all four, never a variable — it is the one
decode setting already measured (3 of 20 dictations looped with it at its
default) and an eval that quietly turned it back on would be measuring that.

D exists so the two halves can be told apart, and it earns its place twice: it
proves the vocabulary gain does **not** depend on the language fix, and it proves
the language fix is the only thing that removes the wrong-language mode.

## First, the eval was measuring the wrong recogniser, and so was the corpus

The obvious baseline is the corpus's own `asr` column — one line per sample,
already on disk, no decoding needed. **It is not the local model.**
`corpus_harvest.py` writes `"asr": r["asrText"]` straight out of Wispr Flow's
database and `"text": best_text(edited, formatted, asr)` out of the same row, and
its first paragraph says so in as many words: *"No model runs here and none is
called."* Both halves are Wispr — one raw, one cleaned. They agree to a **median
WER of 0.008**; they are the same sentence with different commas.

Scoring `asr` against `text` measures Wispr's formatter. Everything below is
scored against **config A, decoded here with `whisper_helper.py`'s exact
settings**, which disagrees with `asr` at a median WER of **0.151** — the local
model's real error, not a bookkeeping difference.

The same provenance bites the wrong-language count. `detectedLanguage` in the
corpus is *Wispr's* pick on these rows, not the relay's:

| bucket | n | corpus `detectedLanguage` ∉ {ro,en} | **config A's own pick ∉ {ro,en}** |
|---|---|---|---|
| <2s | 14 | 0.0% | **50.0%** |
| 2–3s | 29 | 6.9% | **27.6%** |
| 3–4s | 36 | 5.6% | **19.4%** |
| 4–5s | 40 | 0.0% | **2.5%** |
| 5–6s | 35 | 0.0% | 0.0% |
| 6–8s | 69 | 0.0% | 0.0% |
| 8–12s | 106 | 0.9% | 1.9% |
| 12–30s | 300 | 0.0% | 0.0% |
| 30s+ | 174 | 0.6% | 0.6% |
| **all** | **803** | **0.7%** | **3.2%** |

The cliff in `CLAUDE.md` is the right shape and the right place — nothing past
five seconds, everything under four — but on the local model it is **two to three
times steeper** than the corpus column suggested. Half of everything under two
seconds comes back in a language he does not speak.

## The numbers

Cells are `median WER / share above 0.3 / rare-word recall / repetition loops /
wrong language / empty`.

| bucket | n | A | B | C | D |
|---|---|---|---|---|---|
| <2s | 14 | 0.90 / 64% / 43% / 0% / **50%** / 0% | 1.00 / 64% / 43% / 21% / 0% / 0% | 0.35 / 50% / 57% / 29% / 0% / 0% | 0.65 / 57% / 43% / 29% / 50% / 0% |
| 2–3s | 29 | 0.50 / 66% / 25% / 0% / **28%** / 0% | 0.38 / 59% / 20% / 0% / 0% / 0% | 0.43 / 59% / 20% / 7% / 0% / 0% | 0.43 / 62% / 20% / 3% / 28% / 0% |
| 3–4s | 36 | 0.35 / 53% / 42% / 0% / **19%** / 0% | 0.35 / 53% / 47% / 3% / 0% / 0% | **0.17** / 44% / 53% / 3% / 0% / 0% | 0.21 / 44% / 44% / 0% / 19% / 0% |
| 4–5s | 40 | 0.18 / 35% / 68% / 2% / 2% / 0% | 0.18 / 35% / 68% / 0% / 0% / 0% | 0.19 / 30% / 64% / 0% / 0% / 0% | 0.19 / 30% / 64% / 0% / 2% / 0% |
| 5–6s | 35 | 0.14 / 29% / 52% / 0% / 0% / 0% | 0.14 / 29% / 52% / 0% / 0% / 0% | 0.11 / 20% / 48% / 0% / 0% / 0% | 0.11 / 20% / 48% / 0% / 0% / 0% |
| 6–8s | 69 | 0.12 / 13% / 81% / 1% / 0% / 0% | 0.12 / 13% / 81% / 1% / 0% / 0% | 0.14 / 17% / 79% / 0% / 0% / 0% | 0.14 / 17% / 79% / 0% / 0% / 0% |
| 8–12s | 106 | 0.16 / 17% / 70% / 1% / 2% / 0% | 0.16 / 17% / 68% / 2% / 0% / 0% | 0.15 / 19% / 69% / 2% / 0% / 0% | 0.15 / 19% / 70% / 1% / 2% / 0% |
| 12–30s | 300 | 0.15 / 14% / 77% / 1% / 0% / 0% | 0.15 / 14% / 77% / 1% / 0% / 0% | 0.15 / 13% / 76% / 1% / 0% / 0% | 0.15 / 13% / 76% / 1% / 0% / 0% |
| 30s+ | 174 | 0.20 / 21% / 69% / 1% / 1% / 0% | 0.20 / 21% / 69% / 1% / 0% / 0% | 0.19 / 18% / 70% / 2% / 0% / 0% | 0.19 / 18% / 70% / 2% / 1% / 0% |

Pooled. Mean WER is **capped at 1.0**; uncapped it is a report about four looped
clips and nothing else — one `af af af…` for a two-word reference scores 43.8 and
moves the mean of 119 samples by 0.37.

| set | cfg | n | wer med | wer mean≤1 | rare-rec | wer>0.3 | loop | wrong-lang |
|---|---|---|---|---|---|---|---|---|
| **<5s** | A | 119 | 0.333 | 0.393 | 50% | 51.3% | 0.8% | **19.3%** |
| | B | 119 | 0.300 | 0.371 | 51% | 49.6% | 3.4% | **0.0%** |
| | **C** | 119 | **0.222** | **0.324** | 52% | **43.7%** | 5.9% | **0.0%** |
| | D | 119 | 0.222 | 0.341 | 48% | 45.4% | 4.2% | 19.3% |
| **<8s** | A | 223 | 0.182 | 0.294 | 62% | 35.9% | 0.9% | 10.3% |
| | B | 223 | 0.182 | 0.282 | 63% | 35.0% | 2.2% | 0.0% |
| | **C** | 223 | **0.154** | **0.252** | 61% | **31.8%** | 3.1% | 0.0% |
| | D | 223 | 0.167 | 0.261 | 60% | 32.7% | 2.2% | 10.3% |
| **12s+** (control) | A | 474 | 0.167 | 0.203 | 72% | 16.5% | 0.8% | 0.2% |
| | B | 474 | 0.167 | 0.203 | 72% | 16.5% | 0.8% | 0.0% |
| | C | 474 | 0.167 | 0.199 | 72% | 14.8% | 1.1% | 0.0% |
| | D | 474 | 0.167 | 0.199 | 72% | 14.8% | 1.1% | 0.2% |
| **all** | A | 803 | 0.167 | 0.229 | 72% | 21.9% | 0.9% | 3.2% |
| | B | 803 | 0.167 | 0.226 | 71% | 21.7% | 1.4% | 0.0% |
| | C | 803 | 0.167 | 0.214 | 71% | 20.0% | 1.7% | 0.0% |
| | D | 803 | 0.167 | 0.217 | 71% | 20.3% | 1.4% | 3.2% |

**The empty column is not comparable to the 71%-under-1s figure in `CLAUDE.md`,
and the eval set is why.** A row qualifies here by having an `asr` field, which
every Wispr-harvested row has — but the local model's own empties were never in
this file to begin with, so config A's 0.0% is an artefact of who was invited.
What the column honestly measures is whether B, C or D turn a clip that had words
into one that has none, and none of them ever did.

## What it says

### 1. Restricted language ID removes the failure completely, and costs nothing

**26 of 803 clips came back in a language he does not speak. B and C: zero.**
Not reduced — gone, by construction, and the column is printed anyway as the
sanity check that the pinning actually reached the decoder.

**And it is free.** This is the surprise. `transcribe(language=None)` already
runs `detect_language` on the first window before it decodes a word; B does the
same encoder pass outside and `transcribe` then skips its own. Standalone the
pass costs a median of **612 ms** (flat across every bucket — it is one encoder
pass over a fixed 30-second window, so a 0.6s clip pays the same as a
twenty-minute one). Paired against A on the same clip, end to end:

| | median Δ latency vs A |
|---|---|
| B | **−22 ms** |
| C | +15 ms |
| D | +5 ms |

Below the noise, and if anything on the right side of it. There is no
cheaper recipe hiding here either: computing the mel over 30 seconds instead of
60 saves nothing (361 ms vs 388 ms over 40 clips, same pick on 40 of 40) because
the cost is the encoder, not the spectrogram.

### 2. The vocabulary prompt is the bigger win, and the LID is not what buys it

Recall on the prompted terms themselves, over their 490 occurrences in the
references. **C and D are identical to two decimals on every single term** — the
gain is the prompt, entirely, and does not care what language was pinned.

| term | n | A / B | C / D |
|---|---|---|---|
| `petclinic` | 5 | **0.00** | 0.60 |
| `frontend` | 10 | **0.10** | 0.70 |
| `agentic` | 5 | 0.20 | 0.80 |
| `claude` | 52 | **0.33** | **0.85** |
| `md` (i.e. `CLAUDE.md`) | 61 | 0.44 | 0.82 |
| `backend` | 25 | 0.44 | 0.92 |
| `subagenți` | 10 | 0.50 | 0.60 |
| `intellij` | 17 | 0.59 | 0.88 |
| `jetbrains` | 3 | 0.67 | 1.00 |
| `code` | 79 | 0.78 | 0.90 |
| `walkie` / `talkie` | 15 / 15 | 0.93 / 0.80 | 0.93 / 1.00 |
| `prompt` | 17 | 0.88 | **0.82** ↓ |
| `wispr` | 3 | 0.00 | 0.00 |
| **pooled** | **490** | **0.67** | **0.88** |

**`Claude` at 0.33 is the number that justifies the whole config.** Two thirds
of the time Victor says the name of the agent he is talking to, the recogniser
writes something else — `cloud`, `claw`, `cloud code`, and `CLAUDE.md` as
`CloudMD`:

```
REF  Pune chestia asta în claude.md pe git!
A    Pune chestia asta în CloudMD pe ghid.
```
```
REF  Extract the Java code style rules out of CLAUDE.md into a Java skill
     on this project, and then commit push it.
A    Extract the Java code style rules out of CloudMD into a Java skill
     on this project and then commit push it.
```

This is exactly the failure `CLAUDE.md` says plain WER cannot see: *"a mangled
identifier costs the agent everything, a wrong verb ending costs nothing."*
`CloudMD` is one word of a twenty-word sentence — 5% WER, and an instruction the
agent cannot follow.

Note what did **not** move: the general rare-word recall is flat at 71–72% across
all four configs. The prompt buys the words that are *in* it and nothing else,
which is the honest reading of what a 65-token prompt can do.

### 3. The 12s+ control says the changes are invisible where the problem is not

474 clips at twelve seconds and over: median WER **0.167 in all four configs**,
rare-word recall **72% in all four**, capped mean 0.203 → 0.199. Nothing here is
better and nothing is worse.

That is the expected shape and the mechanism explains it. `transcribe` seeds
`all_tokens` with the prompt, then — because `condition_on_previous_text=False` —
sets `prompt_reset_since = len(all_tokens)` after **every** window. So a clip
under 30 seconds is prompted throughout and a two-minute one is prompted for its
first thirty seconds and decoded bare after that. The vocabulary reaches the
place the failure lives and mostly cannot reach anywhere else.

### 4. The bill for C is repetition loops, and it lands on non-speech

This is the regression check the config was run for, and it found something.

| | loops, all 803 | worse than A by >0.1 WER | better than A by >0.1 |
|---|---|---|---|
| A | 7 | — | — |
| B | 11 | 10 | 9 |
| C | **14** | **38** | **56** |
| D | 11 | 35 | 53 |

C is net positive by 56 to 38, and 12 of its 38 regressions are loops. The three
worst are all clips that were never speech:

```
0.6s   REF  VoxxedDays.                     ← Wispr's reading of 0.6s of noise
       A    Teşekkür ederim.
       C    af af af af af af af af af … (~220 times)
```
```
1.3s   REF  you
       A    안녕하세요.
       C    af af af af af af af af af … (~220 times)
```
```
1.7s   REF  5 minutes.
       A    Thank you.
       C    af af af af af af af af af … (~220 times)
```

Junk in, junk out — but a different junk, and a worse one. `Thank you.` is a
harmless line for an agent to receive; four hundred repetitions of `af` is not.
Restricted to clips whose reference is four words or more (102 of the 119 under
five seconds), the loop rate is 1.0% for A against 3.9% for C — three extra
clips out of a hundred, and the median WER goes 0.317 → 0.222 in exchange.

**The existing confidence floor does not catch them; the compression ratio
does.** The relay already gates on `avg_logprob < −0.6` (`Transcriber.confidenceFloor`),
and that catches **2 of C's 14 loops** — a loop is *confidently* wrong, which is
the whole reason it is a loop. `compression_ratio > 2.4` catches **14 of 14**,
and flags 5 non-loops of which **0** have a WER under 0.3. `whisper_helper.py`
already sends `compression_ratio` and `Transcriber.swift` already parses it into
`Result.compressionRatio` — it is simply never read. That is the mitigation, and
it is free.

| | loops caught by `avg_logprob < −0.6` | by `compression_ratio > 2.4` | good outputs falsely flagged |
|---|---|---|---|
| A | 3 of 7 | 5 of 7 | 2 |
| B | 4 of 11 | 9 of 11 | 2 |
| C | 2 of 14 | **14 of 14** | **0** |
| D | 3 of 11 | 11 of 11 | 0 |

### 5. The transcripts that got fixed

The aggregate moves four points. These are what four points look like — every
one a clip A returned in a language he does not speak.

```
2.5s   REF  Deschide primul owner.
       A    Δευκείτε πριμου ούναρ                        [el]
       B    Descide primul owner                         [ro]
```
```
2.6s   REF  Ignoră partea a doua și dă-i.
       A    Игнора партая отдава, щи дай.                [ru]
       C    Ignora partea a doua și dai.                 [ro]
```
```
1.8s   REF  Trage link și la ăsta.
       A    اترجى الانكشي لابسته                          [ar]
       C    Trage link și la vista.                      [ro]
```
```
3.4s   REF  Claude asked something, and I said ok.
       A    Claude a demandé quelque chose et je lui ai dit ok    [fr]
       B    Claude asked something and I said ok.                 [en]
```
```
4.7s   REF  Dacă în șase luni n-ai atins nimic la "markdow-nurile"
            astea, nu meriți mărire.
       A    Dár af af af af af af af af af af af …        [is]
       C    Dacă în șase luni n-ai atins nimic la mardaunurile
            astea, nu meriți mărire.                      [ro]
```

That last one is the whole argument in one clip: the baseline picked Icelandic
off a four-second Romanian sentence and fell straight into a loop; C returns the
sentence, near-perfectly, one compound noun off.

### 6. And the ones that got broken

Honesty about the other direction. B's failure mode is the mirror of A's: where A
answered non-speech with a short foreign phrase, B answers it with a loop in a
language it was ordered to use.

```
4.0s   REF  Factura creată, mi-o pui în download să mă uit la ea.
       A    Faktur að kreja það með pýinn download sem að útla ég.   [is]
       B    The encouragement rate rate rate rate rate rate rate …   [en]
       C    Facture rate rate rate rate rate rate rate rate …        [en]
```

Both readings are useless; neither is better. And the worst non-loop regression
C causes is a **truncation**, which is the one shape worth watching for, because
it is silent:

```
14.4s  REF  Te rog, sumarizează discuția pe care am avut-o la prânz,
            de la 12:30 la 13:30, și atașează sumarul conversației
            la mailul…
       A    Te rog, sumarizează discuția care am avut-o la prânz de
            la 12.30 la 1.30 și atașează sumarul conversației alea…
       C    Să-mi dă la 1.30 și atașează sumarul conversației alea
            la mail-ul Gmail ca draft…
```

C dropped the first clause. One case in 803, and the only one of its kind found.

## Two references where Wispr is the one that is wrong

`CLAUDE.md` is explicit that the line beside a recording is not ground truth, and
these are the proof. Wispr carries Victor's surname in a personal dictionary and
writes it over a word that sounds like it. The local model, which has never heard
of him, gets it right and is scored wrong for it:

```
REF (Wispr)  … Use all the monitors you have around Rentea for this.
A            … Use all the monitors you have around the retina for this.
```
```
REF (Wispr)  … placed outside of the Rentea screen if there is any other screen…
A            … placed outside of the retina screen if there is any other screen…
```

Two rows out of 803 do not move an aggregate. They are written down because a
four-point difference in a disagreement rate is not a result until somebody has
looked at what is inside it, and `--suspect` is the switch that looks.

## The recommendation

**Make both changes. Take the restricted LID unconditionally; take the
vocabulary prompt with the compression-ratio gate beside it.**

- **B is a free repair of a documented failure.** It removes 100% of the
  wrong-language mode — 3.2% of all clips, 19.3% under five seconds, 50% under
  two — at a measured **−22 ms**, and leaves the 474-clip control bucket
  bit-for-bit unmoved. There is no argument against it that survives the paired
  latency number.
- **C is where the value is.** Pooled recall on the words that identify what he
  is talking about goes **0.67 → 0.88**; `Claude` alone goes 0.33 → 0.85. Median
  WER under five seconds goes 0.333 → 0.222 and the share above 0.3 goes 51% →
  44%. On the 12s+ control it changes nothing in either direction.
- **The gate is not optional.** C adds seven repetition loops across 803 clips
  and the `−0.6` floor sees two of them. `compression_ratio > 2.4` sees all
  fourteen with zero false rejects, and both the helper and `Transcriber.swift`
  already carry the number — reading it is the entire change.
- **D is the control that says the two are separable**, not a candidate: it buys
  the identical vocabulary gain and leaves the wrong-language mode fully intact.

### `initial_prompt`, exactly

```
Claude Code, CLAUDE.md, Copilot, subagent, subagenți, MCP, skill, hook, prompt,
commit, push, backend, frontend, IntelliJ, JetBrains, Walkie Talkie, Wispr Flow,
petclinic, agentic.
```

65 tokens under the `ro` tokenizer, against Whisper's cap of 224 — and the cap
that decided the length was not the tokenizer but that a long prompt is itself a
source of hallucination. Every term is attested in his own references and most
are measurably broken; `Devoxx` (n=0), `repo` (n=1) and `VS Code` (n=2) were
guessed, checked and thrown out. `--vocab` prints the derivation, per term, per
config.

### The restricted language ID, exactly

```python
from mlx_whisper.transcribe import ModelHolder
from mlx_whisper import audio as A
import mlx.core as mx

model = ModelHolder.get_model(MODEL, mx.float16)      # the same cached weights
                                                      # transcribe() itself uses
mel = A.log_mel_spectrogram(samples[:A.N_SAMPLES],
                            n_mels=model.dims.n_mels, padding=A.N_SAMPLES)
mel = A.pad_or_trim(mel, A.N_FRAMES, axis=-2).astype(mx.float16)
_, probs = model.detect_language(mel)                 # dict over all 99 codes
language = max(("ro", "en"), key=lambda c: probs[c])  # ← the whole change
```

Three things about it worth keeping:

- **The restriction is one line.** `detect_language` already returns the full
  probability distribution, so taking the argmax over two keys of it needs no
  second forward pass, no tokenizer mask and no patch to the library.
- **`ModelHolder.get_model`, not `load_models.load_model`.** That is the cache
  `transcribe` uses, keyed on the repo path — asking it here means the LID pass
  and the decode share one 2.5 GB copy of the weights instead of two.
  `mx.float16` matches `transcribe`'s default (`fp16=True`); asking for float32
  would fill the holder with the wrong dtype and every later decode would use it.
- **The mel is over the first 30 seconds only.** Upstream computes it for the
  whole file because it needs all of it to decode anyway; a twenty-minute clip
  would otherwise pay for forty windows to answer a question asked of the first.

### Caveats

- **The reference is Wispr, not truth.** Every number is a disagreement rate.
  A 4-point move in median WER is a 4-point move against another recogniser that
  is itself wrong sometimes, in ways `--suspect` only partly finds.
- **The clips under two seconds are mostly not speech.** 17 of the 119 clips
  under five seconds have a reference shorter than four words, and they are where
  the loop rate is worst (17.6% for C against 0% for A). On the 102 that *are*
  sentences, C's loop rate is 3.9% against A's 1.0%.
- **The empty-output rate here cannot be compared with the corpus's**, for the
  selection reason above.
- **Nothing was measured about the live path.** These are 803 files decoded back
  to back on a warm model; the relay decodes one clip at a time behind a chip
  that is counting down. The latency numbers are paired and same-process, which
  is the fair comparison, but they are not a stopwatch on a dictation.

## Reproducing

```sh
python3 evals/short-clip-lid.py             # 803 × 4, ~146 min, resumable
python3 evals/short-clip-lid.py --report    # the tables above
python3 evals/short-clip-lid.py --fixed     # the 26 wrong-language clips, all four readings
python3 evals/short-clip-lid.py --vocab     # the prompt's derivation, per term
python3 evals/short-clip-lid.py --suspect   # rows where Wispr is the one that is wrong
```

Rows land in `evals/work/short-clip-lid.jsonl` (gitignored, one per sample per
config) and a rerun skips what is already there, so a two-hour run that dies at
minute 90 resumes. The interpreter is the one that has `mlx_whisper`, found the
way `Transcriber.pythonPath` finds it — on this Mac `/usr/local/bin/python3`,
and **not** `/usr/bin/python3`.
