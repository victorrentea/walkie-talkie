# Teaser — what was decided (loads only when working in `teaser/`)

`README.md` here says how the pipeline works (script → voices → cuts → build). This file holds
Victor's decisions and the paid-for lessons, so a new session does not re-ask them. State on
2026-11-23: **cut v9, 84 s** (`out/teaser-v9.mp4`, `-720p`, `-labels`).

## What may and may not be shown

- **Never Wispr Flow** (edge of its terms) and **never ElevenLabs** (expensive): only the local model.
  Nothing with their names on screen.
- No "Cancel"/held-prompt feature, no RO+EN mixing, no lightning ring (halo = dust + edge dust).
- Hidden in every take: the corner hint bar and the crop's readouts (`hintBarHidden`,
  `cropReadoutsHidden`); `edgeDust.marksBoost 2` so the question marks read on film.
- While the screen recording runs, no dust of any kind (the app does this itself since 2026-11-23).
- Scripted, and fine to stay so: the terminal "Claude Code" is a stand-in (`film/agent.py`) that
  shows the prompt Walkie really delivered; cost amounts, question answers, the redactor's
  vocabulary and the wake word (`/test/wake`) are staged.

## The look Victor asked for

- **No punch-ins, ever** (no `crop` in `cuts.json`). Legibility comes from a **lower guest
  resolution** (960x540 HiDPI → 1920x1080 clips), not from zooming content.
- App switches are real **Cmd-Tab** with the switcher visible, not hard cuts.
- Mouse: curved, slightly irregular paths with ease-out (`film/mouse.py`); selections fast
  (rectangle ≤ 0.5 s, code selection ~0.3 s, made *while* the line is spoken).
- Subtitles: narrator white; what Walkie hears yellow with 🎙️; `WAKE WORD` tag on "Hey Claude.".
  A subtitle never covers what the cut is about (`sub: "top"`).
- Waiting (agent working, transcribing) is cut or sped up; a spoken line is never cut.
- Overlays drawn by `build.py`: `note` ("Cost of completed task" → the cost pill, s02),
  `struck` (what was first heard, red and struck through, above the corrected word, s07d),
  the s09 checklist card (last two ticks land as their lines are spoken), the end card
  (`Free · open source · built for macOS`, the GitHub link, `use it, fork it, tweak it`).
- Review copies carry the scene label (`label.py`).

## The script

- **The spoken text lives in the Google Doc "Agent Notes"** (see `~/.claude/CLAUDE.md`): only the
  spoken lines go there, no stage directions. Victor edits it there; read it back, his version
  wins, then bring it into `script.json`, run `tts.py`, rebuild.
- Scene 5: "Or film it." comes before "See how this flickers? Fix it.".
- Scene 4's user line is split ("Use this picture" / "here, and fix this text.") so the Cmd-Tab
  fits between the two gestures.
- The cost is no longer spoken; it is the `note` on the pill.
- Voices: Fish Audio, narrator "Ethan", user "Energetic Male". Music "Brain Dance" (Kevin MacLeod,
  CC BY 4.0): **the credit line goes in the video's description when published**. Victor asked
  whether a similar track could be generated (Suno / ElevenLabs music) and said to leave the audio
  as it is for now.

## Filming (Tart VM `wt-lab`)

- `film/setup.sh` → `film/round6.sh open` → takes → `round6.sh cut` → `film/teardown.sh`.
  Sidecar json per clip: event seconds and rects; time the cuts to the frames, sidecars run
  0.2–0.4 s late.
- **The nightly Wispr labelling run takes `wt-lab` from 22:00** until it finishes (01:30–04:00,
  deadline 08:00). Never film then, never interrupt it; `setup.sh` refuses a running VM.
- Guest kills go through `film/gkill.sh` (PID by PID); never `pkill`.
- Showing Victor a cut: 4 frames checked first; away from the Mac ⇒ AgentMail to Gmail, the
  labelled copy recompressed under ~3.7 MB (1280 wide, crf 32, AAC 96k) — larger attachments
  answer 413.
- Long work (filming, cutting) goes to subagents; one films, one edits, the main session only
  coordinates.

## Open on 2026-11-23

- s05: a second arrow (the guest's real cursor) shows beside the drawn pointer in a few frames;
  needs one more take now that the whole film is dust-free.
- The image-search page is a local replica wearing the Google logo — Victor has not said whether
  to keep it or use a neutral name before publishing.
- Weak spots Victor has seen listed and not yet ruled on: s01's terminal is a still picture for
  3 s; s07b's idle page under "or call out the wake word:"; s04's subtitle covers the Mic /
  Engine / To rows of the prompt panel; the struck word is small at 720p; after the bind the chip
  does not name the session.
