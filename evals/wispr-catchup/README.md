# Wispr catch-up: does Wispr write down the whole sentence when it starts listening late?

**Verdict (2026-09-30, 48 runs in `wt-lab`, 8 of Victor's clips):** mostly yes. In **21 of 24**
late-start runs through the real app, Wispr's row held the whole clip within Wispr's own run-to-run noise. The first words
survived in every run where the bridge started. The three misses were:

- one mid-sentence hole at 5 s late;
- one lost tail word group at 5 s late;
- one bridge that never started, whose words the local fallback saved.

Separately, **the bridge crashed the app twice**: `AVAudioPlayerNode.play()` throws inside
`AudioBridge.start`. That is the first thing to fix.

The feature is `67cc341`: `AudioBridge` holds every buffer from the gesture until Wispr's
input runs, then `BridgePacer` does three things:

- cuts the silence ahead of the first word;
- shortens pauses to 0.25 s;
- plays at 1.1× until live.

Brief: `PROMPT.md`.

## The rig (in the guest, as it ended up)

| part | what | why not the first idea |
|---|---|---|
| Wispr's microphone | **From Walkie** (the `../from-walkie` driver copied in), Auto-detect → it, as on his Mac | the plan kept Wispr on BlackHole 2ch — see below |
| the relay's "microphone" | **BlackHole 2ch** (`POST /test/mic`), the clip played into it by `guest.py` | **BlackHole 16ch reads as exact zeros in the relay** (`48000Hz × 16ch`, 3 tap restarts, DEAF), while two Python processes pass a 440 Hz tone through it fine |
| the bridge | default target From Walkie, `/test/bridge` on for L, off for B/P | with the bridge up, a second writer on From Walkie **wiped the baseline's audio** (Wispr wrote `So` for a 10 s clip): BlackHole's shared statics, the lab's Finding A |
| lateness | the gesture's start chord muted (`/test/wispr-chord`), posted **N s later** | `SIGSTOP` on Wispr stalled the whole guest's audio (a 10 s clip took 16 s to play and came back garbled); a Wispr that is not running is not a late start — the relay goes local at once, by design |
| speaking | the clip starts 0.2 s after the gesture, **no lead-in** (`wispr_loopback.LEAD_SEC = 0`) | the helper's 1.3 s lead-in is silence the pacer cuts, which hid the lag; polling `/test/state` for the mic is no good either — it answers in seconds while Wispr is frozen |

Runs per clip:

- **B**: the clip played straight into From Walkie with Wispr's push-to-talk held, twice. The
  closer of the two is each run's reference, and the WER between them is Wispr's own noise.
- **L**: through the relay, with Wispr warm (~0.3 s), 2 s late or 5 s late.
- **P**: what the pacer would hand over after 2 s / 5 s, rendered offline (lead cut, pauses →
  0.25 s, `ffmpeg atempo=1.1` while behind) and played as in B.

Scoring (`run.py`):

- words are normalised, with fillers (`ăăă`, `so`, `also`…) dropped;
- **head** / **tail** = at least 4 of the reference's first / last 5 words found in the
  hypothesis's first / last 8;
- **WER** is against the closer baseline.

## Results

| run | n | head kept | tail kept | WER median (max) | Wispr's own noise, median | caught up after release, s (median / max) | not Wispr's words |
|---|---|---|---|---|---|---|---|
| l:warm | 8 | 7/8 | 7/8 | 0.03 (1.00) | 0.06 | 0.2 / 0.7 | 1 |
| l:late2 | 8 | 8/8 | 8/8 | 0.04 (0.10) | 0.06 | 2.9 / 4.4 | 0 |
| l:late5 | 8 | 8/8 | 7/8 | 0.03 (0.39) | 0.06 | 7.9 / 10.5 | 0 |
| p:2 | 5 | 5/5 | 5/5 | 0.00 (0.18) | 0.06 | – | 0 |
| p:5 | 5 | 5/5 | 5/5 | 0.03 (0.07) | 0.06 | – | 0 |

| clip | run | head | tail | WER | noise | released, ms | cut, s | caught up, s | delivery |
|---|---|---|---|---|---|---|---|---|---|
| 09-26-41-local770 | l:late2 | ✓ | ✓ | 0.10 | 0.183 | 2481 | 0.59 | 4.0 | wispr-history |
| 09-26-41-local770 | l:late5 | ✓ | ✓ | 0.39 | 0.183 | 5489 | 0.43 | 10.5 | wispr-history |
| 09-26-41-local770 | l:warm | ✓ | ✓ | 0.05 | 0.183 | 319 | 0.0 | 0.2 | wispr-history |
| 09-26-41-local770 | p:2 | ✓ | ✓ | 0.18 | 0.183 | – | – | – | – |
| 09-26-41-local770 | p:5 | ✓ | ✓ | 0.07 | 0.183 | – | – | – | – |
| 12-24-46-local201 | l:late2 | ✓ | ✓ | 0.10 | 0.079 | 2362 | 0.59 | 4.4 | wispr-history |
| 12-24-46-local201 | l:late5 | ✓ | ✓ | 0.05 | 0.079 | 5538 | 0.59 | 8.8 | wispr-history |
| 12-24-46-local201 | l:warm | ✗ | ✗ | 1.00 | 0.079 | 1281 | 0.0 | – | local-fallback |
| 12-24-46-local201 | p:2 | ✓ | ✓ | 0.05 | 0.079 | – | – | – | – |
| 12-24-46-local201 | p:5 | ✓ | ✓ | 0.03 | 0.079 | – | – | – | – |
| 14-11-49-local492 | l:late2 | ✓ | ✓ | 0.10 | 0.05 | 2400 | 0.59 | 1.3 | wispr-history |
| 14-11-49-local492 | l:late5 | ✓ | ✓ | 0.10 | 0.05 | 5447 | 0.59 | 7.4 | wispr-history |
| 14-11-49-local492 | l:warm | ✓ | ✓ | 0.10 | 0.05 | 418 | 0.0 | 0.2 | wispr-history |
| 14-11-49-local492 | p:2 | ✓ | ✓ | 0.00 | 0.05 | – | – | – | – |
| 14-11-49-local492 | p:5 | ✓ | ✓ | 0.00 | 0.05 | – | – | – | – |
| 15-32-34-11l96 | l:late2 | ✓ | ✓ | 0.00 | 0.0 | 2369 | 1.94 | 0.2 | wispr-history |
| 15-32-34-11l96 | l:late5 | ✓ | ✓ | 0.00 | 0.0 | 5340 | 2.03 | 5.1 | wispr-history |
| 15-32-34-11l96 | l:warm | ✓ | ✓ | 0.00 | 0.0 | 447 | 0.0 | 0.2 | wispr-history |
| 17-42-24-local987 | l:late2 | ✓ | ✓ | 0.00 | None | 2388 | 0.93 | 3.4 | wispr-history |
| 17-42-24-local987 | l:late5 | ✓ | ✗ | 0.15 | None | 5318 | 0.59 | 8.4 | wispr-history |
| 17-42-24-local987 | l:warm | ✓ | ✓ | 0.00 | None | 289 | 0.0 | 0.2 | wispr-history |
| 20-18-05-11l273 | l:late2 | ✓ | ✓ | 0.00 | 0.0 | 2381 | 0.93 | 2.4 | wispr-history |
| 20-18-05-11l273 | l:late5 | ✓ | ✓ | 0.00 | 0.0 | 5349 | 1.18 | 9.2 | wispr-history |
| 20-18-05-11l273 | l:warm | ✓ | ✓ | 0.00 | 0.0 | 307 | 0.0 | 0.6 | wispr-history |
| 20-18-05-11l273 | p:2 | ✓ | ✓ | 0.00 | 0.0 | – | – | – | – |
| 20-18-05-11l273 | p:5 | ✓ | ✓ | 0.05 | 0.0 | – | – | – | – |
| 21-14-53-c0a2ee5f | l:late2 | ✓ | ✓ | 0.07 | 0.214 | 2324 | 0.43 | 3.5 | wispr-history |
| 21-14-53-c0a2ee5f | l:late5 | ✓ | ✓ | 0.00 | 0.214 | 5332 | 0.43 | 5.6 | wispr-history |
| 21-14-53-c0a2ee5f | l:warm | ✓ | ✓ | 0.06 | 0.214 | 287 | 0.0 | 0.2 | wispr-history |
| 23-02-45-local789 | l:late2 | ✓ | ✓ | 0.00 | None | 2352 | 1.78 | 0.2 | wispr-history |
| 23-02-45-local789 | l:late5 | ✓ | ✓ | 0.00 | None | 5386 | 2.53 | 3.9 | wispr-history |
| 23-02-45-local789 | l:warm | ✓ | ✓ | 0.00 | None | 348 | 0.0 | 0.7 | wispr-history |
| 23-02-45-local789 | p:2 | ✓ | ✓ | 0.00 | None | – | – | – | – |
| 23-02-45-local789 | p:5 | ✓ | ✓ | 0.00 | None | – | – | – | – |

## What the numbers say

1. **The head survives.** 23/24 L runs kept the first words. The one miss is the bridge that never
   started (4 below). Released 2.3–2.5 s after the gesture at 2 s late, and 5.3–5.5 s at 5 s late.
   The lead cut was 0.4–2.5 s.
2. **Catching up is slow.** From the release, it took 0.2–4.4 s at 2 s late, and **3.9–10.5 s
   (median 7.9) at 5 s late**. At 1.1× the speed-up gains 0.1 s per second of speech, so the
   shortened pauses do most of the work. On a 10–15 s sentence that started 5 s late, Wispr hears
   **most of the sentence sped up**, and the stop waits for the drain.
3. **The speed-up itself is harmless.** P runs at 5 s: WER median 0.03, max 0.07. That is below
   Wispr's own noise (median 0.06).
4. **The two damaged runs came through the live path, not the pacing.**
   - `09-26-41` at 5 s late lost *"să îmi pui lângă mouse nu microfonul, ci"* (WER 0.39). The
     same clip paced offline (P:5) scored 0.07. So something in the live bridge dropped or starved
     that stretch. My guess, not measured, is that its pause cut took quiet speech for silence.
   - `17-42-24` at 5 s late turned *"using my Gmail CLI automation"* into *"AI automation"*.
     Catch-up came 8.4 s after the release, i.e. after the clip had ended, so the tail was played
     fast and pause-cut.
5. **The bridge once failed to start**, with `could not aim at From Walkie (OSStatus 'nope')`.
   Wispr heard silence and reported `no_audio`. The local model stood in (Q14), so the words
   were not lost, but they were not Wispr's.

## Wispr's ceiling: how fast it can be fed (2026-09-30, evening)

Victor: *"accelerarea asta trebuie să aibă un anumit plafon, peste care probabil Wispr să nu mai
poată înțelege … îmi asum această procesare întârziată"*. And: *"I tend to speak faster in RO"*.

**Method.** Each clip was played **whole** at the given rate: time-pitch (`ffmpeg atempo`), no
pauses cut, the worst case for the pacer. It went straight into From Walkie with Wispr's
push-to-talk held (`guest.py r`, `host-rates.sh`). The comparison is against two plays of the same
clip at 1.0×.

This ran **on the host Mac** under hands-off, at Victor's call ("Mac now, full"), because the VM was
busy with `wispr-markers`. Walkie's bridge was switched off for the run, and its test sink window
caught the pastes.

The clips:
- the 8 of the late-start runs;
- plus his **4 fastest Romanian clips** in the corpus: 7.3–9.0 words per voiced second, against a
  3.6 median.

The rows are in `rates.jsonl`.

| rate | clips | WER median | WER max | within Wispr's noise + 5 pts | tail kept |
|---|---|---|---|---|---|
| 1.15× | 4 | 0.07 | 0.16 | 3/4 | 3/4 |
| 1.25× | 12 | 0.00 | 0.43 | 11/12 | 11/12 |
| 1.35× | 4 | 0.24 | 0.51 | 1/4 | 3/4 |
| 1.5× | 12 | 0.06 | 0.77 | 6/12 | 9/12 |
| 1.75× | 8 | 0.05 | 0.20 | 5/8 | 7/8 |
| 2.0× | 8 | 0.09 | 0.44 | 2/8 | 6/8 |

| clip | lang | Wispr's noise | 1.15× | 1.25× | 1.35× | 1.5× | 1.75× | 2.0× |
|---|---|---|---|---|---|---|---|---|
| 05-54-12-29822bad | ro fast | 0.0 | 0.09 | 0.00 | 0.09 | 0.09 | – | – |
| 08-41-20-wispr497 | ro fast | 0.0 | 0.00 | 0.00 | 0.03 | 0.03 | – | – |
| 09-26-41-local770 | ro | 0.034 | – | 0.02 | – | 0.09 | 0.20 | 0.27 |
| 11-09-42-wispr781 | ro fast | 0.25 | 0.16 | 0.43 | 0.38 | 0.77 | – | – |
| 12-24-46-local201 | ro | 0.0 | – | 0.05 | – | 0.05 | 0.07 | 0.12 |
| 14-11-49-local492 | en | 0.0 | – | 0.00 | – | 0.00 | 0.05 | 0.10 |
| 15-32-34-11l96 | ro | 0.0 | – | 0.00 | – | 0.00 | 0.00 | 0.06 |
| 17-42-24-local987 | en | 0.0 | – | 0.00 | – | 0.00 | 0.00 | 0.04 |
| 18-27-37-6c1db762 | ro fast | 0.059 | 0.04 | 0.06 | 0.51 | 0.22 | – | – |
| 20-18-05-11l273 | ro | 0.024 | – | 0.00 | – | 0.00 | 0.05 | 0.05 |
| 21-14-53-c0a2ee5f | en | 0.0 | – | 0.00 | – | 0.06 | 0.06 | 0.44 |
| 23-02-45-local789 | en | 0.0 | – | 0.00 | – | 0.14 | 0.00 | 0.07 |

**Verdict: 1.25× (`BridgePacer.Tuning.maxRate`).**
- At 1.25×, 11 of 12 clips stay within Wispr's own noise. The twelfth, `11-09-42`, already
  disagrees with itself by 25% at 1.0×.
- At 1.35×, his fast Romanian breaks: `18-27-37` goes from 0.06 to 0.51.
- At 1.5×, half the clips are past the noise, and the tail goes on 3 of 12.

English holds longer (clean to 1.75× on 3 of 4 clips), but the ceiling is set by his Romanian.

So the pacer runs 1.1× just behind live and ramps to 1.25× at 3 s behind. Whatever that cannot
absorb is drained after his stop, with no ceiling on the wait. Example: a start 5 s late with a stop
1 s after Wispr starts listening leaves ~5 s queued. With pauses cut to 0.25 s and 1.25×, that drains
in about 3–4 s after the stop.

Re-run: `CLIPS="a.wav b.wav" RATES="1.0 1.0 1.25 1.35" ~/bin/hands-off run "…" -- ./evals/wispr-catchup/host-rates.sh`
(host; Walkie up, From Walkie on), or `guest.py r` in `wt-lab`. Score with
`WT_EVAL_RESULTS=evals/wispr-catchup/rates.jsonl python3 evals/wispr-catchup/run.py --score`.

## Crashes: fixed (`7a16b48`, another session, same evening)

Two `SIGABRT`s in ~50 runs (guest `DiagnosticReports`, 17:09:14 and 17:44:43 UTC). Same frames:

```
+[NSException raise:format:]
AVAudioPlayerNodeImpl::StartImpl
-[AVAudioPlayerNode play]
closure #1 in AudioBridge.start(format:holding:)
  ← WisprFlowSource.startMeter()          (17:09)
  ← WisprFlowSource.feedOwnSentence(_:)   (17:44)
```

`play()` raises when the engine is not running by the time it is called. For example, the output
device's configuration changed between `engine.start()` and `play()`, which happens when a
From Walkie is being opened and closed by takes starting a second apart. Swift cannot catch an
NSException, so the relay dies mid-sentence.

**Recommendation:** check `engine.isRunning` after `start()`, and call `play()` through a
tiny Objective-C `@try` shim. On failure, log it and `return false`, which is the path that
already exists for *no device* and *engine would not start*, so the take falls back as it does
now. Neither the crash nor `could not aim` has been seen on the host's log.

## Recommendations

1. The crash guard above.
2. ~~Make catch-up faster than 1.1× when far behind~~ — **done** (`4ff902f` and after): a ramp to
   the measured **1.25×**, and the stop drains the rest with no ceiling (*Wispr's ceiling*, above).
3. Dump what the bridge actually plays (`WT_BRIDGE_DUMP=<wav>`), so the next hole like
   `09-26-41` can be heard rather than guessed at.

## Traps the rig paid for

- A **16-channel** BlackHole reads as zeros in the relay.
- **Two writers** on one BlackHole-driver device wipe each other.
- **`SIGSTOP`** on Wispr stalls the guest's audio.
- The `forward-right` gesture is a **toggle**: one lost stop inverts every later run. That is
  why `guest.py` now cancels any open dictation first (`settle()`).
- **Killing `run.py` does not kill `guest.py`**: `tart exec` keeps it running in the guest.
- A `pkill` of the guest relay is **deferred up to 600 s by the QuitGate** while sentences are
  held for a bind. `open` then only brings the old instance forward, and it quits later, mid-run.

## Host incident found on the way (fixed in victor-mac `2965a09`)

Victor Addons' From Walkie watchdog switched the device off under a running Walkie on his Mac, at
19:50:09 and 20:18:49, so Wispr fell back to the Elgato with no bridge. The watchdog read
`NSRunningApplication` from a background queue, where that list can be stale. It also fired
inside a restart's ~1 s gap. It now reads the process table too, and waits for two misses in a row.

## Re-run

```
# host, with wt-lab up, From Walkie copied into the guest's HAL folder (+ killall coreaudiod),
# the relay running there with Engine = Wispr, guest.py + clips/ copied to ~/wt-lab/evals/wispr-catchup/
TART_HOME=~/tart python3 evals/wispr-catchup/run.py                  # b,b,l:warm,l:late2,l:late5,p:2,p:5 per clip
TART_HOME=~/tart python3 evals/wispr-catchup/run.py --plan b,l:late5 --clips 09-26-41-local770.wav
python3 evals/wispr-catchup/run.py --table                           # these tables
```

`clips/` is not committed: those are Victor's own voice clips. `clips.json` names them
and where they came from in `~/.walkie-talkie/voice-corpus/`. Afterwards, restore the guest for
anyone expecting Wispr on BlackHole 2ch: remove `FromWalkie.driver` and `killall coreaudiod`.
