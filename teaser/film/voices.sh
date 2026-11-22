#!/bin/zsh
# The spoken lines, synthesised in the guest (macOS `say`, 48 kHz stereo WAVs for BlackHole). Longer than the
# script's lines on purpose: an edge needs 4–6 s of dictation to be fully up.
source "$(dirname "$0")/lib.sh"
gsh 'cd ~/film/voice && mk() { say -v Daniel -r 172 -o "$1.aiff" "$2" && /opt/homebrew/bin/ffmpeg -loglevel error -y -i "$1.aiff" -af "adelay=300:all=1,apad=pad_dur=0.6,volume=2" -ar 48000 -ac 2 "$1.wav"; }
mk s02 "Make the header dark, [[slnc 350]] and the button orange. [[slnc 500]] Keep everything else as it is."
mk s03 "Move this badge [[slnc 1500]] up here, [[slnc 600]] right next to the headline."
mk s04 "Use this picture [[slnc 1300]] here. [[slnc 3200]] And fix this text. [[slnc 2600]] Thanks."
mk s05 "See how this flickers? [[slnc 600]] It should stay still. [[slnc 400]] Fix it."
mk s06 "I do not like this loop. [[slnc 500]] Simplify it."
mk s07a "Start a new session, [[slnc 400]] review my last commit, [[slnc 300]] and tell me what could break."
mk s07c "Rename this function to parse order, [[slnc 400]] update every place that calls it, [[slnc 300]] and the tests too."
mk s07e "Add a test for the pricing card."
mk s07d "Hi Anna. Um, the resilience for jay upgrade is, uh, ready, so we can ship it on Friday."
mk s08 "Is the Hystrix library from Netflix still maintained?"   # the bare "Is Hystrix still maintained?" comes out of Whisper as "histrix"
mk s09 "Fix the broken pricing card."
# round 6: the new user lines, in pieces — each piece is started at a named instant (say.py <wav> <epoch>), so a word falls on its gesture
mk s02a "Make the header dark,"
mk s02b "and this button"
mk s02c "orange."
mk s03a "Move this"
mk s03b "up here."
mk s06a "I do not like this loop."
mk s06b "Use streams."
mk s07e6 "Add a test for the two buttons."
mk s04bc "here, [[slnc 450]] and fix this text."
mk s04a "Use this picture"
mk s04b "here,"
mk s04c "and fix this text."
for f in *.wav; do echo "$f $(/opt/homebrew/bin/ffprobe -v error -show_entries format=duration -of csv=p=0 $f)"; done'
