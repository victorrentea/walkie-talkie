# Walkie Talkie teaser

A ~60 s promo cut, rebuilt from scratch by one command:

```
python3 teaser/build.py          # -> teaser/out/teaser-v4.mp4 (1920x1080, 30 fps, H.264 + AAC)
                                 #    and teaser-v4-720p.mp4, the copy small enough for a mail
python3 teaser/build.py --plan   # the timeline only, nothing rendered
```

`script.json` is the source of truth: scenes, their target length, and the lines
(`who: "n"` narrator, `who: "u"` the user dictating). Media is not in git (`.gitignore`):
`footage/` (filmed separately), `audio/` (generated), `music/` (downloaded), `out/`.

## Pieces

| file | what it does |
|---|---|
| `tts.py` | one clip per line into `audio/`, cached by a hash of provider + voice + text, so a script edit re-synthesises only the changed lines |
| `cuts.json` | the edit: which seconds of which clip each scene shows, punch-ins, subtitle position |
| `build.py` | timeline, per-scene picture, subtitles, sound mix, mux |

**Footage and the edit**: the takes in `footage/` are long and uncut; `cuts.json` is the
edit. Per scene it lists sub-cuts played in order: `clip` (file in `footage/`, default the
scene id), `in`/`out` seconds of that clip, optional `crop: [x, y, w, h]` (a punch-in on the
1920x1080 source), `line` (the index of the scene's line this cut starts under: the cuts of
one line share that line's time and are stretched together to fill it, which is what keeps
a spoken line over its picture), `sub: "top"` (subtitle at the top during this cut) and
`speed` (fixed instead of stretched). A cut can also take `start` (seconds into the scene, instead of `line`), `line: [i, part]`
(a part of a split line) and `blur: [x, y, w, h]` (smears a region of the source). `_at` gives a
scene's line start times by hand; a list for one line splits it at its punctuation into that
many parts, each with its own start, audio and subtitle both. Two more keys beside the scenes: `_target` overrides a
scene's target seconds from `script.json` (never below its speech), `_tight` lists scenes
cut to the length of their speech. `build.py --plan` prints every cut with its place in
the film and its resulting speed. A scene with footage but no entry plays its clips whole
(0.75x to 3x); a scene with no clip gets a dark placeholder card. The scene whose id ends
in `-end` is always the generated end card.

**Timeline**: a scene lasts `max(target, its speech + gaps)`, and its end then moves to the
nearest beat of the music that still leaves room for the speech. Hard cuts on whole frames.

**Subtitles**: drawn with Pillow as full-frame PNGs and overlaid for the time their audio
plays; narrator white, user yellow with the microphone from Apple Color Emoji. A long line
is shown one sentence at a time, the switch placed on the pause in the audio.

**Sound**: mixed in numpy. Every voice clip is levelled to the same RMS; the music sits
12 dB lower under speech (ramped, gaps under 0.7 s do not pump), and the master goes
through a limiter to about -15 LUFS.

A dry run that does not touch the real cut:
`TEASER_FOOTAGE=/tmp/x/footage TEASER_OUT=/tmp/x/out.mp4 python3 teaser/build.py`.

## Voices

Fish Audio (`~/.claude/fish-audio.env`), model `s2.1-pro-free`, public catalogue voices:

| role | voice | Fish id |
|---|---|---|
| narrator (default) | Ethan | `536d3a5e000945adb7038665781a4aca` |
| narrator, alternative | Adrian (deeper, slower) | `bf322df2096a46f18c579d0baa36f41d` |
| narrator, alternative | Slax (lowest, measured) | `c5f56a6cc2ec4fa8920cb4c5889a3fb7` |
| user | Energetic Male | `802e3bc2b27e49c2995d23ef70e6ac89` |

`python3 teaser/tts.py --samples` writes the first line in the three narrator voices to
`audio/samples/narrator-<name>.mp3`. To switch: `CAST` in `tts.py`.

`tts.py` tries ElevenLabs first (`~/.walkie-talkie/elevenlabs.env`) and falls back to Fish
on a 401/403. On 2026-11-22 that key answered `missing the permission text_to_speech`
(it is scoped to speech-to-text), so every clip is Fish. The refusal is remembered for a
day in `audio/.refused.json`; delete it after changing the key's scope.

## Music

**"Brain Dance" by Kevin MacLeod**, 124 BPM (the composer's figure; `build.py` measures
124.0 on the file), 3:35. The cut starts 4 beats in, after the track's opening swell.

- Download: <https://incompetech.com/music/royalty-free/mp3-royaltyfree/Brain%20Dance.mp3>
  -> `teaser/music/brain-dance.mp3`
- Licence: Creative Commons Attribution 4.0, free of charge, credit required. Read on
  <https://incompetech.com/music/royalty-free/licenses/> on 2026-11-22: "Creative Commons
  -- Free. No charge. Requires that you credit the music."
- **Credit line, to paste wherever the video is published** (the text that page generates):

  ```
  "Brain Dance"
  Kevin MacLeod (incompetech.com)
  Licensed under Creative Commons: By Attribution 4.0
  http://creativecommons.org/licenses/by/4.0/
  ```

The credit is not burned into the video; it belongs in the description of wherever it is
posted (or pay the site's Standard License, 30 USD, to drop it).
