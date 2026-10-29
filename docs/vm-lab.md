# The lab — a headless macOS guest for the live tests

> **Since 2026-10-30 the external disk "Vic" is out of the picture altogether** (Victor: *"renunțăm la
> discul extern cu totul. E prea lent"*). Everything lives in **`TART_HOME=~/tart`** on the internal
> disk (set in `~/.zshenv`, and the default of `tools/vm-lab.sh` / `tools/wt-night.sh` since that day;
> the new MacBook Pro has 1.2 TB free). `wt-lab` came back from Vic on 2026-10-26 (`rsync -a --partial
> --exclude control.sock` with the VM stopped, same image, so Wispr's sign-in inside it survives).
> **`wt-base` and `fx-lab` stayed on Vic and are not used any more** — a `reset` + `up` pulls the base
> image again (~25 GB) into `~/tart`. Every `/Volumes/Vic/…` path below is history.

A Tart VM (`wt-lab`) on Apple's Virtualization.framework, so that synthetic mouse and keys, the
witness Terminal tabs and the test audio stay inside a guest instead of on Victor's screen, his
speakers and his clipboard. Driven by `tools/vm-lab.sh`. First built 2026-09-26; an earlier
attempt a few days before failed and left no notes. This file is the notes.

**Everything lived on the external disk "Vic"** — `TART_HOME=/Volumes/Vic/tart` — until
2026-09-29, when **`wt-lab` moved to the internal disk, `TART_HOME=~/tart`** (Victor, 28 Sep: *"move
the VM back on my Mac disk to increase speed"*; the HDD made a boot take minutes and every guest
build read through it). Copied with `rsync -a --exclude control.sock` with the VM stopped, booted
and SSH'd from the new home, then the old copy renamed `wt-lab.moved-2026-09-29` on Vic. The base
image `wt-base` and the OCI cache stay on Vic (not needed to run the lab); the night stamp moved with
the VM, so the weekly 02:00 gate no longer depends on Vic being mounted. The table below is the
2026-09-26 layout.

## What exists (2026-09-26)

| | where | size |
|---|---|---|
| Tart | `/opt/homebrew/bin/tart` → `/Applications/tart.app`, **2.34.0, pinned** | |
| OCI cache: `ghcr.io/cirruslabs/macos-sequoia-base:latest` (sha256:4947ac5a…) | `/Volumes/Vic/tart/cache/OCIs/…` | 31 GB (50 GB sparse `disk.img`, 25.3 GB compressed download) |
| `wt-base`: the image, 4 CPU / 8 GiB, untouched since the pull | `/Volumes/Vic/tart/vms/wt-base` | 31 GB |
| `wt-lab`: the working clone, provisioned (below) | `/Volumes/Vic/tart/vms/wt-lab` | 31 GB apparent, shares its blocks with `wt-base` |
| guest's own log | `/Volumes/Vic/tart/wt-lab.log` | |

`du` counts `wt-base` and `wt-lab` separately (62 GB for `vms/`), but `df` did not move when
`wt-lab` was cloned: it is an APFS clone. The volume went from 70 GiB used before the pull to
~134 GiB after it.

**The guest**: macOS 15.7.7 (24G720), user `admin` / password `admin`, passwordless `sudo`,
auto-login into Aqua, 1024×768 display, time zone GMT. Disk: 50 GB image, **~20 GiB free** in
`/System/Volumes/Data` (grow with `tart set wt-lab --disk-size N` while it is stopped if the app,
Whisper models and logs need more). Homebrew 6.0.22 at `/opt/homebrew`; Xcode Command Line Tools
at `/Library/Developer/CommandLineTools`; `python3` on the default PATH is **`/usr/bin/python3`
3.9.6** (brew's 3.14.7 is at `/opt/homebrew/bin/python3`, later on PATH). `Terminal.app` is
there. SSH (OpenSSH 9.9) and Screen Sharing (RFB 003.889) answer on the NAT address
(`tart ip wt-lab`, 192.168.64.4 on the first boot). `tart-guest-agent` runs both as a daemon and as
an agent in admin's GUI session, so **`tart exec` runs as `admin` inside Aqua** (`launchctl
managername` = `Aqua`): `open`, `osascript` and `screencapture` work from it.

Provisioned in `wt-lab` and **baked into `wt-base` on 2026-09-27 00:11** (clean SSH shutdown in 50 s,
`bake` 4.5 s; `wt-lab` left stopped). The grants came along; `elevenlabs.env` did not — it was
deleted from the guest before the shutdown, so copy it in after every `reset`/`up`:

- **BlackHole 2ch 0.7.1** (`brew install --cask blackhole-2ch`, 25 min 51 s of which almost all
  disk wait). The installer says a reboot is needed; `sudo killall coreaudiod` was enough. Devices
  after it: `Apple Virtual Sound Device` (output only — see *audio*) and `BlackHole 2ch` (2 in,
  2 out, now the default input).
- `pip3 install --user sounddevice numpy scipy` into `/usr/bin/python3` (3.9): numpy 2.0.2,
  scipy 1.13.1, sounddevice 0.5.6, 8 min 58 s. The harness parses as Python 3.9.
- **The harness's 440 Hz pass-thru check passes on BlackHole**: peak 0.30, 440 Hz share 0.999
  (the harness wants > 0.2). No microphone prompt for the recording side from `tart exec`.
- `~/wt-lab/voice-corpus/` = the three clips (+ `.txt`), symlinked into
  `~/.walkie-talkie/voice-corpus/<day>/` where the harness's hard-coded `CORPUS` looks for them.
- **`~/wt-lab/` mirrors the repo root** (night of 2026-09-26): `relay-restart.sh`,
  `safe-restart.sh`, `tools/restart_gate.py`, `helpers/`, `evals/` (without `evals/work`,
  `evals/plan/vm`, `__pycache__`), plus `run-phase.sh` / `run-d.sh` (below). The cases compute
  `REPO` as three `dirname`s up from `evals/plan/cases_*.py`, so the plan must sit at
  `~/wt-lab/evals/plan` for `TR17`/`TD10` to find `./relay-restart.sh`. The first run's
  `~/wt-lab/plan/` (REPO = `/Users/admin`) is stale — do not run from it.
- **The local engine**: `pip3 install --user mlx-whisper` into `/usr/bin/python3` 3.9 (mlx 0.29.3
  cp39, mlx-whisper 0.4.3, torch 2.8.0, numba 0.60 — 5 min 10 s) and `brew install ffmpeg`
  (`HOMEBREW_NO_AUTO_UPDATE=1`, 4 min 40 s, run in parallel with pip). No `RELAY_WHISPER_PYTHON`
  is needed: the app's probe tries launchd's PATH first, and `/usr/bin/python3` finds the module in
  admin's user site-packages. **MLX runs in the VZ guest** (Metal on the paravirtualized GPU):
  `helpers/whisper_helper.py` on `.warmup.wav` downloaded `whisper-large-v3-turbo` (1.5 GB, in
  `~/.cache/huggingface`) and answered in 4 min 35 s total, peak 2.1 GB. A cold start in the app
  then takes 33–77 s (reading the weights off the USB disk) against ~3 s on the host; warm decodes
  ~3 s for a 3.5 s clip.
- **The app is the host's 20:33 build** (HEAD 2e2d8d5), copied in over SSH on 2026-09-26 21:54; the
  first run had a 15:01 build (before most of fix batches 1–5). The grants held
  (`accessibility trusted=true eventTap=true` at the relaunch).
- `tmux` 3.7c (`brew install tmux`, 15 s) for `TD13`.
- `~/bin/hands-off` — a stub (see *Running the suite*).
- Tailscale 1.102.3 (`brew install tailscale`, `sudo tailscaled install-system-daemon`), **not
  logged in** (see *From the phone*).
- Screen Sharing's legacy VNC password turned on, password `admin` (see *From the phone*).

## Start, stop, look

```sh
tools/vm-lab.sh up        # clones wt-base → wt-lab if missing, boots headless, waits for the agent
tools/vm-lab.sh sh <cmd>  # tart exec as admin in the GUI session
tools/vm-lab.sh down      # guest shutdown, then reap
tools/vm-lab.sh look      # Screen Sharing on Victor's screen — only when he asks for it
```

By hand: `export TART_HOME=~/tart` first (already in `~/.zshenv`), **always** — without it Tart silently uses
`~/.tart`. Then
`nohup tart run wt-lab --no-graphics --no-audio --no-clipboard > $TART_HOME/wt-lab.log 2>&1 &`.

## How the USB disk showed up — it is a spinning disk (history: not used since 2026-10-30)

"Vic" is a **WD Elements 25A1** (a 2.5" USB hard drive, 3 TB, APFS, `Owners: Disabled`), behind
a 5 Gb/s bridge. It sustained 16–28 MB/s at 240–300 IOPS whenever the VM was busy. Everything the
guest does is bound by that:

| step | time |
|---|---|
| `tart pull` (25.3 GB compressed, network-bound) | 24 min (12:28 → 12:52) |
| `tart clone <OCI image> wt-base` | **25 min 50 s** — a real copy (+~35 GB on the volume, ~28 MB/s), see traps |
| `tart set wt-base --cpu 4 --memory 8192` | instant |
| `tart clone wt-base wt-lab` | **0.15 s** — APFS clone |
| first boot → `tart ip` answers | 485 s |
| first boot → SSH / VNC banners | 683 s / 684 s |
| first boot → `tart exec wt-lab true` works | **1146 s (19 min)** |
| `brew install --cask blackhole-2ch` | 25 min 51 s |
| `sudo killall coreaudiod` + `system_profiler SPAudioDataType` | 1 min 38 s |
| `pip3 install --user sounddevice numpy scipy` | 8 min 58 s |
| the 1.5 s 440 Hz playrec check, cold Python | 53 s |
| `brew install tailscale` + daemon install | 1 min 33 s |

The host side was idle meanwhile (`tart run` 0 % CPU, the VZ process ~3 %); the guest's
processes sat at 0 % CPU waiting on reads. Tart's defaults make it worse: the root disk is
attached with `sync: .full` (every guest flush goes to the platters) and automatic caching.
Later boots, measured after the setup above:

| boot | SSH banner | `tart exec` works |
|---|---|---|
| 1st (fresh clone, first-boot work) | 683 s | 1146 s |
| 2nd, after a `tart stop` (pulled plug) | ~30 min | **never** — stale `control.sock`, see traps |
| 3rd, after a clean shutdown, Tart defaults | 294 s | **577 s** |
| 4th, `--root-disk-opts=caching=cached,sync=none` | 332 s | 593 s |
| 5th (2026-09-26 21:45), 25 min after the first run's stop — host page cache still warm | ~130 s | **280 s** |

**Host caching and `sync=none` bought nothing for a boot**: after a stop the host's page cache
holds none of the guest's blocks, so the boot is the same ~10 minutes of reads off the platters.
`vm-lab.sh` keeps Tart's safe defaults. Even booted, the guest stays slow: a
`system_profiler SPAudioDataType` took 98–247 s, and the 1.5 s 440 Hz check from a cold Python 53 s.
A clean guest shutdown took 64 s and 140 s; the third did not finish within 300 s and was cut by `tart stop` (that boot ran with `sync=none`). Whether that left the guest filesystem dirty is not verified — boot it once and check before the next `bake`.

**What would make it usable**: an SSD. The same `TART_HOME` on any USB-C/Thunderbolt NVMe would
cut the boot to well under a minute (the image is the same; `tart clone` onto the new volume is a
one-off copy). Short of that: keep `wt-lab` running rather than booting it per run (the draft
LaunchAgent below), so a nightly run pays only the tests' own reads. `tart suspend` needs
`--suspendable`, which drops the virtio sound device (BlackHole is a software driver and would
stay) — untested, and a resume would still read 8 GiB of RAM image off the disk.

## Traps (every one of them hit on 2026-09-26)

- **Since 2026-09-28 `wt-lab` carries a signed-in Wispr Flow: never `reset`, `bake` or `tart clone`
  it** — the session is single-use and would be revoked (`docs/vm-wispr.md`, top and *Done
  2026-09-28*). Boot, shut down and redeploy the app as before.
- **`tart exec` can be dead for a whole boot with no stale socket** (2026-09-28): `wt-lab.log` said
  `Failed to run control socket: NIOFcntlFailedError()`, `vms/wt-lab/control.sock` did not exist,
  and every `tart exec` answered `GRPCConnectionPoolError` while both guest agents ran. Only a new
  `tart run` brings it back. Meanwhile SSH does everything, including `osascript` to Terminal and
  TextEdit: SIP is off in this image and the user `TCC.db` now has AppleEvents rows for
  `sshd-keygen-wrapper` (list in `docs/vm-wispr.md`). `vm-lab.sh shot`/`deploy`/`api` go through
  `tart exec` and fail with it — use `ssh … screencapture -x` and the manual tar deploy.
- **`tart stop` is a pulled plug.** It SIGINTs `tart run`, whose handler cancels the task and
  calls `VZVirtualMachine.stop()` — no guest shutdown (Tart 2.34 `Commands/Stop.swift`,
  `Run.swift:593`, `VM.swift`). It returned in 0.13 s. `vm-lab.sh down` now runs
  `sudo shutdown -h now` in the guest first and only reaps with `tart stop` after 600 s. Do the
  same by hand before `bake`, or the base inherits a dirty filesystem.
- **Tart's default audio is the host's speakers and microphone.** Without `--no-audio` the guest
  gets `VZHostAudioInputStreamSource` + `VZHostAudioOutputStreamSink` (`VM.swift:350–357`): the
  app in the guest would hear Victor's room, anything it plays would come out of his speakers, and
  macOS would ask *him* to grant `tart` the microphone. `vm-lab.sh up` passes `--no-audio`; the
  guest then keeps an output-only `Apple Virtual Sound Device` with no host sink.
- **Tart's default clipboard is shared both ways** (Spice agent via `tart-guest-agent`). The app
  delivers with ⌘V and snapshots the pasteboard — in the lab that would be Victor's clipboard.
  `vm-lab.sh up` passes `--no-clipboard`.
- **Cloning out of the OCI cache copies; cloning a local VM clones.** Same volume, same
  `clonefileat` in the stack (`sample` showed `VMDirectory.clone` → `copyfile` → `clonefileat`),
  yet the first clone wrote ~35 GB for 26 minutes and the second took 0.15 s. So: pull once,
  clone the image once into `wt-base`, and from then on only clone `wt-base`. `reset` + `up` is
  cheap; deleting `wt-base` is not. The OCI cache (31 GB) could be dropped with `tart prune` once
  `wt-base` exists; it is kept for now because the disk has 2.6 TiB free.
- **`vm-lab.sh shot` used to default to `~/.tart/`** — now `$TART_HOME/wt-lab-screen.png`.
- **The guest agent comes up long after SSH.** On the first boot `tart exec` failed with
  `GRPCConnectionPoolError … is the Tart Guest Agent running?` for 7½ minutes after SSH answered.
  `wait_agent` now waits 900 s (a warm boot needs ~580 s here, the very first one needed 1146 s) — rerun `up`
  (it does not boot twice) rather than concluding the agent is broken.
- **A stale `control.sock` breaks `tart exec` for the whole run.** The pulled-plug stop leaves
  `vms/wt-lab/control.sock`; the next `tart run` logs `Failed to run control socket: bind…
  Address already in use (errno: 48)` and carries on, the guest boots, SSH answers — and every
  `tart exec` fails with `GRPCConnectionPoolError`, which reads exactly like a slow guest agent.
  Cost 30 minutes. `vm-lab.sh up` now deletes the socket before `tart run`.
- **`tart ip` answers from the previous DHCP lease** (`/var/db/dhcpd_leases`) before the guest is
  up — it is no readiness signal. SSH's banner or `tart exec true` are.
- **SSH works with password `admin` without `sshpass`**: `/usr/bin/expect` (in macOS) can type it;
  a 10-line script did the clean shutdown when `tart exec` was down. A non-login SSH shell has no
  `/opt/homebrew/bin` on PATH.
- **A `brew install --cask` that needs a reboot does not.** BlackHole's pkg says "requires
  restarting now"; `sudo killall coreaudiod` loads the HAL driver.
- **`lsof` would not see the guest's VNC server** (runs as root, on demand) — test with the RFB
  handshake from the host: `printf '' | nc -G 3 -w 3 $(tart ip wt-lab) 5900 | head -c 12`.
- **`ssh -o BatchMode=yes admin@$(tart ip wt-lab)` fails with `Host key verification failed`**
  when the guest's key is not in `known_hosts` (BatchMode cannot ask). Give it its own file:
  `-o UserKnownHostsFile=<scratch>/known_hosts -o StrictHostKeyChecking=accept-new` — never
  edit Victor's `~/.ssh/known_hosts` for a guest whose key changes with every `reset`.
- **`tart exec` is fragile; SSH is the fallback for everything but the harness.** A `tart exec …
  nohup … &` sometimes does not return although the child is detached (the warm-up of the helper
  held it past a 120 s cap, the child ran on), and right after `up` it answers
  `GRPCConnectionPoolError` for a while. Copy files, poll logs, `open` the app and shut down over
  SSH. **The harness itself must go through `tart exec`**: it drives Terminal with `osascript`,
  and the Automation grant belongs to `tart-guest-agent` — from SSH it would be
  `sshd-keygen-wrapper` asking, with nobody to click. **And the microphone grant** (wave 4,
  2026-09-29): over SSH the harness's reads of BlackHole are exact zeros — `loopback_alive()` says
  the pass-thru is dead and TM1/TM2 SKIP (`evals/plan/vm/wispr/2026-09-29-wave4/aborted1/`). Never
  launch a phase over SSH, even when `tart exec` is slow to come up: wait for it, or reboot.
- **`down` must use SSH** (`ssh … 'sudo shutdown -h now'`, then wait for `tart list` to say
  `stopped`). `vm-lab.sh down` sends the shutdown through `tart exec`; with the agent down that
  call fails silently and the loop waits 600 s before the pulled plug.
- **`codesign --verify --strict` fails on the installed app** (`file added: …/Resources/.warmup.wav`
  — written into the bundle after signing), so `vm-lab.sh deploy` dies at its first check. The app
  runs and keeps its grants all the same (the requirement is on the signature, not on the sealed
  resources). The night deploy was by hand over SSH: `pkill -x "Walkie Talkie"`, move the old
  bundle aside, `tar -C /Applications -cf - "Walkie Talkie.app" | ssh … 'sudo tar -C /Applications
  -xf -'`, `chown`, `open`. (In the guest `pkill` is fine — the restart gate protects Victor's
  dictation, and there is none there.)
- Docker Desktop's VM (`com.apple.Virtualization.VirtualMachine`, 14 GB RSS) runs beside it on the
  host; `pgrep -f Virtualization` finds both. The lab's is the one with
  `~/tart/vms/wt-lab/disk.img` open.

## Still needs a hand: the privacy grants

The app needs, in the guest, exactly what it holds on the host (host `TCC.db`, 2026-09-26):
**Accessibility**, **Screen Recording**, **Microphone**, and **Automation → Terminal**
(`kTCCServiceAppleEvents`, target `com.apple.Terminal`). None of these can be granted from the
command line on a SIP-on guest. The grants key on the designated requirement — `identifier
"ro.victorrentea.wispr-relay" and certificate leaf = H"70d7d521…"` (the local "Victor Addons Local
Code Signing" cert) — so they survive rebuilds signed with the same cert, and `deploy`'s `tar`
keeps the signature (no quarantine xattr, so Gatekeeper does not interfere).

Order, once:

1. `tools/vm-lab.sh up` then `tools/vm-lab.sh deploy` (copies `/Applications/Walkie Talkie.app`
   in and `open`s it — never start it by its binary path, see the root `CLAUDE.md`). Also copy
   `~/.walkie-talkie/elevenlabs.env` (mode 600) into the guest's `~/.walkie-talkie/` — the
   ElevenLabs cases need it and it is a secret, so it is not in the image yet.
2. Over Screen Sharing (`vm-lab.sh look`, or from the phone — below), in the guest:
   - System Settings ▸ Privacy & Security ▸ **Accessibility** ▸ ＋ ▸ Applications ▸ Walkie Talkie ▸ on.
   - … ▸ **Screen & System Audio Recording** ▸ ＋ ▸ Walkie Talkie ▸ on (it asks to quit & reopen: *Later*,
     then `vm-lab.sh deploy` again).
   - **Microphone**: start one real dictation — ⌘⌃D over Screen Sharing, or
     `vm-lab.sh api test/gesture '{"name":"forward-right"}'` (`/test/dictation/start` opens no
     mic) — and click *Allow* on the prompt; stop it the same way.
   - **Automation**: the first `POST /bind` to a Terminal tab raises *"Walkie Talkie wants to
     control Terminal"* — *Allow*. The harness's own `osascript … tell application "Terminal"`
     raises the same prompt for **whoever runs the harness** (`tart-guest-agent` when it runs via
     `tart exec`, `sshd-keygen-wrapper` via SSH) — run `vm-lab.sh sh osascript -e 'tell application
     "Terminal" to get name'` once and allow it too.
   - Codex can do these clicks instead (it reaches the guest only through Screen Sharing, which is
     a window on Victor's screen — so only when he is away from the Mac, under `hands-off`).
3. `tools/vm-lab.sh bake` — folds `wt-lab` into `wt-base` (instant clone). From then on
   `reset` + `up` gives a clean guest with the grants, BlackHole , the Python packages, Tailscale and the stub.

## The first two runs (2026-09-26)

- **First run, 18:18–18:42 UTC** (`evals/plan/vm/report-vm-{A,G,AU}.md`): 65 cases, 33 PASS. It
  differed from the host for reasons of the guest, not the app: no local Whisper in the guest (TL4
  FAIL, TL6/TL7 SKIP), the plan at `~/wt-lab/plan` so `./relay-restart.sh` did not exist relative to
  `REPO` (TR17, TD10 ERROR), the app on the batch engine instead of `eleven-live` (LC13, B2 SKIP), an
  older 15:01 build, and `tart exec` giving out mid-evening, so only three short batches ran.
- **Night run, 21:45–00:11 EEST** (`evals/plan/vm/night/report-vm-night.md`): all four phases,
  133 case runs, **100 PASS, no regression attributable to the app**. 14 verdicts moved against the
  host's regression run: 9 because the **ElevenLabs account hit its 10 000-credit quota** (`HTTP 401
  quota_exceeded` on every request and on the realtime socket — the host's log shows it too, since
  20:07), 4 because the guest is slow or configured differently (a cold model load 33–77 s off the
  HDD, a 12 s main-thread freeze at relaunch, frame pacing, autosend off in the guest / on on the
  host), 1 for want of Wispr Flow. One real defect only the lab reaches: **TD21** — Terminal in the
  guest reuses a closed tab's tty within 10 s and the binding silently moves to the new tab.

## Running the suite in the lab

Goal (Victor, 2026-09-26 13:20): `evals/plan/harness.py` + `cases_*.py` run **inside the guest**,
nightly, so no synthetic input ever touches his screen.

What the night run of 2026-09-26 did (`evals/plan/vm/night/`, all four phases, 2 h 10 min
including the provisioning):

```sh
export TART_HOME=/Volumes/Vic/tart
tools/vm-lab.sh up                                   # 4 min 40 s that night (warm host cache)
KH="-o BatchMode=yes -o UserKnownHostsFile=$SCRATCH/known_hosts -o StrictHostKeyChecking=accept-new"
IP=$(tart ip wt-lab)
# the repo mirror: REPO in the cases = ~/wt-lab (9.4 MB tar, 2.5 min to unpack on the USB disk)
COPYFILE_DISABLE=1 tar -cf - --exclude __pycache__ --exclude evals/work --exclude evals/plan/vm \
  relay-restart.sh safe-restart.sh tools/restart_gate.py helpers evals | ssh $KH admin@$IP 'tar -C ~/wt-lab -xf -'
ssh $KH admin@$IP 'curl -s -X POST 127.0.0.1:8917/engine -d "{\"id\":\"eleven-live\"}"'
# a phase: launched through `tart exec` (the Automation grant is tart-guest-agent's), detached with nohup
tart exec wt-lab sh -c "nohup bash ~/wt-lab/run-phase.sh A 1200 'LC1,LC2,…' >/dev/null 2>&1 </dev/null & echo launched"
ssh $KH admin@$IP 'tail ~/wt-lab/night/run-A.log'    # poll over SSH; PHASEDONE marks the end
scp $KH admin@$IP:wt-lab/night/report-vm-A.md evals/plan/vm/night/
```

`run-phase.sh NAME CAP IDS` runs one `harness.py --only IDS` with `WT_LOOPBACK="BlackHole 2ch"
HANDS_OFF=1 WT_COLD_WHISPER=kill WT_ALLOW_SPAWN=1 WT_ALLOW_RELAUNCH=1`, SIGINTs it at `CAP` s and
SIGKILLs it 30 s later, and writes `~/wt-lab/night/report-vm-NAME.md` + `run-NAME.log`. `run-d.sh
CAP PER_CASE ID…` is phase D: one process per case, each after 30 s of `busy == false` (the host
used 60 s; 30 s keeps D inside two hours). Both scripts live only in the guest (copies in
`evals/plan/vm/night/`). Measured phase times: A 8 min (50 cases), B 7.5 min (28), C 10 min (31),
D 96 min (23 processes, 30 s idle before each).

- **The injection device is `BlackHole 2ch`**, installed in the guest with brew. The guest has no
  Loopback app, and Virtualization.framework's own `Apple Virtual Sound Device` is output-only
  under `--no-audio` (and is Victor's real microphone without it), so it is not a candidate.
  BlackHole is one device with 2 in + 2 out wired straight through — what `loopback_alive()`'s
  `playrec(device=(idx, idx))` and `play()` expect.
- **Finding A lives in BlackHole, not the relay** (waves 3–4): BlackHole 0.7.1's function-static
  write clock is shared by every reader, so a second reader (Wispr) can turn the relay's stream into
  flowing zeros; none of `MicRecorder`'s three restart steps brings it back. **Recommended, not
  installed:** a second BlackHole from a separate driver bundle for the relay (e.g. the
  `blackhole-16ch` cask), each clip played into both — details in `docs/vm-wispr.md`, *Corrected
  2026-09-29*. Until then a DEAF take in the lab is the rig's, and the app says so.
- **`WT_LOOPBACK`** (added to `harness.py`, default `"🧪 WT Inject"`) names the device the
  harness plays into and self-tests.
- **`INJECT`**: `cases_audio.py` and `cases_lifecycle.py` derive it from `harness.LOOPBACK`
  (`LOOPBACK.replace("🧪 ", "")`). **`cases_gestures.py:43` still hard-codes `"WT Inject"`** —
  the night run patched only the guest's copy with the same one-liner (`sed` in
  `~/wt-lab/evals/plan`); the repo still needs it, and a fresh `tar` of the plan undoes the patch.
- **`hands-off` in the guest** is `~/bin/hands-off`, a no-op stub with the host's CLI: `run "<why>"
  -- cmd…` exports `HANDS_OFF=1` and execs `cmd`; `start`/`end`/anything else exit 0. There is no
  human at that screen to warn. The harness itself never calls `hands-off`; it only checks
  `HANDS_OFF` in the environment (`harness.py` `gesture()` and the case filter, and
  `cases_gestures.py`), so `HANDS_OFF=1` on the command line is all the gesture cases need.
  `looprun.sh` expects `hands-off run … --` around it; the stub satisfies that.
- `WT_WORK` defaults to `/tmp/wt-plan` — fine in the guest.
- The harness takes `~/.walkie-talkie/wispr-loop.lock` — the guest's own, so a host run and a lab
  run do not block each other.
- Still missing for a full run (after the night of 2026-09-26): `claude`/`codex` for the
  `cc`/`codex` cases; tmux (`TD13`); Wispr Flow (`TG7`, the Wispr posters in `TG29`); a second
  display (`LC11`, `LC18`); a way to sleep the guest (`TD23`); ElevenLabs credits (the account was
  at its 10 000-credit quota that night — see *The first two runs*). The full list is in
  `evals/plan/vm/night/report-vm-night.md`.
- **Nightly**: written and installed on 2026-09-27 — see *Nightly* below.

## From the phone

The guest serves Screen Sharing itself (the macOS VNC server on 5900), independent of Tart —
`tart run --no-graphics` stays as it is, and Tart's `--vnc` is not used.

- **Client**: AVNC on the S24U (as for `victor-mac`).
- **Address**: `wt-lab:5900` over Tailscale (MagicDNS `wt-lab.tail7dd942.ts.net`) once the guest
  has joined the tailnet. Without Tailscale the guest is only reachable from the host
  (192.168.64.x NAT).
- **Auth**: security types offered were `30, 33, 36, 35` (ARD) — no plain VNC password. The legacy
  VNC password was turned on with
  `sudo …/ARDAgent.app/Contents/Resources/kickstart -configure -clientopts -setvnclegacy -vnclegacy yes -setvncpw -vncpw admin`
  + `-restart -agent`; now `30, 33, 36, 2, 35`. So: user `admin`, password `admin` (type 30) or
  VNC password `admin` (type 2). Weak on purpose; the guest is reachable only from the host and
  the tailnet.
- **Tailscale**: `brew install tailscale` (the CLI formula with `tailscaled`, not the
  `tailscale-app` cask, which needs an interactive sudo), `sudo tailscaled install-system-daemon`
  (launchd `com.tailscale.tailscaled`, starts at guest boot), then
  `sudo tailscale up --hostname=wt-lab`. **The login was not completed** — Victor opens the URL
  `sudo tailscale up --hostname=wt-lab --timeout=25s` prints (or `tailscale status`, which shows
  it while logged out). The URL is minted per boot: the one printed on 2026-09-26 15:33 was `https://login.tailscale.com/a/283bb29013cb2`; after a reboot `tailscale status` says only *Logged out.* and a new `tailscale up` prints a new one. Once logged in, the node key persists in tailscaled's state and the guest rejoins by itself at boot. After joining: disable key expiry for `wt-lab` in
  the admin console, and `tailscale ip -4` in the guest gives its 100.x address.
- **Baking a logged-in guest** copies its node key into `wt-base`; two clones running at once
  would fight over the `wt-lab` identity. `reset` deletes `wt-lab` before `up` clones, so one at a
  time is fine.

## Nightly (2026-09-27) — **on demand only since 2026-09-29**

**Victor, 2026-09-29 11:40: *"Being hit by external APIs makes this integration test suite not run
automatically … I think it's a bit abusive. I will only run it on demand and send you out to run this
test and fix findings when I experience some issues myself during the day."*** The LaunchAgent is
unloaded and parked in `~/Library/LaunchAgents.disabled/`; nothing fires at 02:00 any more. The run
is started by hand, when he asks: `WT_NIGHT_FORCE=1 tools/wt-night.sh start` (the gate's weekly age
and hour window are skipped; the disk and running-session checks stay), or a Claude session drives
the guest directly (`tools/vm-lab.sh up`, the `run-*phase.sh` chains, harness through `tart exec`).
The stamp is now only a record of the last run. The rest of this section describes the automatic
rig as it was built, kept for when it is wanted again.

Victor, 2026-09-27: *"vreau sa configurezi suita de teste de walkie sa ruleze in fiecare seara cand ai
hdd extern conectat, dar max 1/sapt automat. sa fie rulata si de claude intr-o sesiune interactiva
pornita noaptea la 2:00 si sa repari ce defecte gasesti, daca pica ceva. + trimite o rulare
exploratorie sa se joace cu app. totul in VM."*

**What fires when.** The LaunchAgent `ro.victorrentea.wt-night` (`tools/ro.victorrentea.wt-night.plist`,
symlinked into `~/Library/LaunchAgents/`, bootstrapped) runs `tools/wt-night.sh start` every day at
**02:00**. `start` runs `gate`, which lets it through only when:

- the stamp **`~/tart/night/last-run`** (`$TART_HOME/night/last-run`) is absent or older than **6 d 12 h** — so at most one
  automatic run a week, and a 02:00 job still fires on the 7th night despite drift;
- no tmux session `wt-night` younger than 20 h exists (a live run). An older one is last week's,
  left open to read: `start` renames it `wt-night-<YYYYMMDD-HHMM>` and keeps it;
- the hour is **01–05**. launchd does not skip a calendar trigger missed while the Mac slept: it fires
  it **at wake**. Without this check a Mac asleep at 02:00 and woken at 09:00 would boot the VM during
  Victor's work day; with it, that wake is a logged refusal and the next 02:00 tries again.

Then `start` writes the stamp and opens a detached tmux `wt-night` (in the repo) running
`claude --permission-mode auto --name wt-night --remote-control wt-night "$(cat evals/plan/vm/night/PROMPT.md)"`
through `zsh -lc`, with the native build first on PATH, as `~/workspace/claude-rc.sh` does. When
claude exits the pane drops to a shell, so the transcript stays. `--remote-control <name>` is the
flag for one interactive session with RC (`claude --help`, 2.1.283); it runs fine beside the
`claude remote-control` server in tmux `claude-rc` (the smoke on 27 Sep: `/remote-control is active`,
a session URL, the answer). `WT_NIGHT_RC=0` drops the flag if RC ever blocks or asks for a login.
The session's claude.ai URL is scraped from the pane into `~/.walkie-talkie/night/session-url`, for
the `Claude-Session` trailer of its commits.

**What the session does** — `evals/plan/vm/night/PROMPT.md`, a runbook with hard caps: pre-flight and
ElevenLabs credits (5 min) → `vm-lab.sh up` (20) → deploy the installed app, `elevenlabs.env`, the repo
mirror (15) → phases A/B/C/D with the 26/27 Sep ID lists (2 h 30) → triage against last night (30) →
at most three fix iterations, each through `./relay-restart.sh --build` on the host and a redeploy
(1 h 30) → one Opus subagent playing with the app in the guest, ≥ 25 unscripted actions, findings
`X1…` (45, while the guest is otherwise free — one driver at a time) → report, journal entry, VM
down (15). No new work after 07:00, VM down by 07:45. Unclear defects become questions `Q1…` in the
report, not guesses. The session stays open at the end.

**Engine and credits.** Desk tests prefer the local engine: the harness sets `whisper` at start and
only the ElevenLabs-specific cases switch to an eleven engine and restore it. Those cases run only
with **≥ 3 000 credits** left this month, otherwise they are SKIP `credit cap`, never defects — the
harness enforces it with `WT_ELEVEN_MIN_CREDITS` (default 3000; being added with a fake realtime server
by a separate change). Why: on 26 Sep one host test day spent 46 % of the month's 10 000 credits.
The balance is read from `GET /v1/usage/character-stats?start_unix=<ms>&end_unix=<ms>&breakdown_type=model`
(`xi-api-key`), summed against 10 000 from the 1st of the month; our key lacks `user_read`, so
`/v1/user/subscription` answers `missing_permissions`.

```sh
tools/wt-night.sh status                    # stamp age, tmux alive?, launchd state, last report, log tail
WT_NIGHT_FORCE=1 tools/wt-night.sh start    # run tonight / now: skips the weekly age and the 01–05 hour
tools/wt-night.sh smoke                     # tmux + claude with a one-word prompt, checks the pane, kills it
tmux attach -t wt-night                     # watch (detach: Ctrl-B D); or Remote Control session "wt-night"
launchctl bootout gui/$(id -u)/ro.victorrentea.wt-night                  # disable
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/ro.victorrentea.wt-night.plist   # enable again
```

`WT_NIGHT_FORCE=1` never overrides the disk check or a live `wt-night` session.

**Where things go.** Reports: `evals/plan/vm/night/<YYYY-MM-DD>/` (`report.md`, `merged.md` from
`merge.py`, per-phase reports and logs, `notes.json`, `exploratory.md`), committed and pushed by the
session; screenshots beside the VM, `~/tart/night/<date>/` (on the external disk until 2026-10-30). On the internal disk only logs:
`~/.walkie-talkie/night/launcher.log` (every gate decision), `launchagent.log` (launchd's stdout),
`history.log` (one line per night: date, counts, commit, report path).

`tools/ro.victorrentea.wt-lab.plist` (VM up at login and on every mount) stays a **draft, not
installed**: the night session brings the VM up and down itself, and that agent would keep it running
all day.
