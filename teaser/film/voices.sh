#!/bin/zsh
# The spoken lines, synthesised in the guest (macOS `say`, 48 kHz stereo WAVs for BlackHole). Longer than the
# script's lines on purpose: an edge needs 4–6 s of dictation to be fully up.
source "$(dirname "$0")/lib.sh"
gsh 'cd ~/film/voice && mk() { say -v Daniel -r 172 -o "$1.aiff" "$2" && /opt/homebrew/bin/ffmpeg -loglevel error -y -i "$1.aiff" -af "adelay=300:all=1,apad=pad_dur=0.6,volume=2" -ar 48000 -ac 2 "$1.wav"; }
mk s02 "Make the header dark, [[slnc 350]] and the button orange. [[slnc 500]] Keep everything else as it is."
mk s03 "Move this badge [[slnc 1500]] up here, [[slnc 600]] right next to the headline."
mk s04 "Use this picture [[slnc 1300]] here. [[slnc 3200]] And fix this text. [[slnc 2600]] Thanks."
mk s05 "See how this flickers? [[slnc 600]] It should stay still. [[slnc 400]] Fix it."
mk s06 "I do not like this loop. [[slnc 500]] Simplify it, and keep the behaviour the same."
mk s07a "Start a new session, [[slnc 400]] review my last commit, [[slnc 300]] and tell me what could break."
mk s07c "Rename this function to parse order, [[slnc 400]] and update every place that calls it."
mk s07d "Hi Anna. Um, the release is ready. So, uh, we can ship it on Friday."
mk s08 "Is this library still maintained, [[slnc 400]] or has everyone moved on from it?"
mk s09 "Make the header dark, and the button orange."
for f in *.wav; do echo "$f $(/opt/homebrew/bin/ffprobe -v error -show_entries format=duration -of csv=p=0 $f)"; done'
