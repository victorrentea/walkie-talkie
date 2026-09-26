# The lab — a headless macOS guest for the live tests

A Tart VM (`wt-lab`) on Apple's Virtualization.framework, so that synthetic mouse and keys, the
witness Terminal tabs and the test audio stay inside a guest instead of on Victor's screen, his
speakers and his clipboard. Driven by `tools/vm-lab.sh`. First built 2026-09-26; an earlier
attempt a few days before failed and left no notes. This file is the notes.

**Everything lives on the external disk "Vic"** — `TART_HOME=/Volumes/Vic/tart`. The internal disk
had 88 GiB free and Victor wanted nothing big on it. `~/.tart` stayed at 0 B throughout.

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

Provisioned in `wt-lab` so far (not yet in `wt-base`):

- **BlackHole 2ch 0.7.1** (`brew install --cask blackhole-2ch`, 25 min 51 s of which almost all
  disk wait). The installer says a reboot is needed; `sudo killall coreaudiod` was enough. Devices
  after it: `Apple Virtual Sound Device` (output only — see *audio*) and `BlackHole 2ch` (2 in,
  2 out, now the default input).
- `pip3 install --user sounddevice numpy scipy` into `/usr/bin/python3` (3.9): numpy 2.0.2,
  scipy 1.13.1, sounddevice 0.5.6, 8 min 58 s. The harness parses as Python 3.9.
- **The harness's 440 Hz pass-thru check passes on BlackHole**: peak 0.30, 440 Hz share 0.999
  (the harness wants > 0.2). No microphone prompt for the recording side from `tart exec`.
- `~/wt-lab/plan/` = `evals/plan/` (without `__pycache__`), `~/wt-lab/voice-corpus/` = the three
  clips (+ `.txt`), symlinked into `~/.walkie-talkie/voice-corpus/<day>/` where the harness's
  hard-coded `CORPUS` looks for them.
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

By hand: `export TART_HOME=/Volumes/Vic/tart` first, **always** (without it Tart silently uses
`~/.tart` on the internal disk). Then
`nohup tart run wt-lab --no-graphics --no-audio --no-clipboard > $TART_HOME/wt-lab.log 2>&1 &`.

## How the USB disk shows up — it is a spinning disk

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
- Docker Desktop's VM (`com.apple.Virtualization.VirtualMachine`, 14 GB RSS) runs beside it on the
  host; `pgrep -f Virtualization` finds both. The lab's is the one with
  `/Volumes/Vic/tart/vms/wt-lab/disk.img` open.

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

## Running the suite in the lab

Goal (Victor, 2026-09-26 13:20): `evals/plan/harness.py` + `cases_*.py` run **inside the guest**,
nightly, so no synthetic input ever touches his screen.

```sh
export TART_HOME=/Volumes/Vic/tart
tools/vm-lab.sh up
# refresh the plan (tar keeps it simple; the guest has no git checkout)
COPYFILE_DISABLE=1 tar -C evals -cf - --exclude __pycache__ plan | tart exec -i wt-lab tar -C /Users/admin/wt-lab -xf -
tart exec wt-lab sh -c 'cd ~/wt-lab/plan && WT_LOOPBACK="BlackHole 2ch" HANDS_OFF=1 /usr/bin/python3 harness.py --report ~/wt-lab/report.md'
tart exec wt-lab cat /Users/admin/wt-lab/report.md > evals/plan/report-lab-$(date +%F).md
```

- **The injection device is `BlackHole 2ch`**, installed in the guest with brew. The guest has no
  Loopback app, and Virtualization.framework's own `Apple Virtual Sound Device` is output-only
  under `--no-audio` (and is Victor's real microphone without it), so it is not a candidate.
  BlackHole is one device with 2 in + 2 out wired straight through — what `loopback_alive()`'s
  `playrec(device=(idx, idx))` and `play()` expect.
- **`WT_LOOPBACK`** (added to `harness.py`, default `"🧪 WT Inject"`) names the device the
  harness plays into and self-tests.
- **Open: `INJECT` is hard-coded.** `cases_audio.py:13` and `cases_lifecycle.py:14` pass
  `INJECT = "WT Inject"` to `POST /test/mic`, which in the guest matches nothing. Either derive it
  from `harness.LOOPBACK` in those two files, or make the guest's device carry the name: an
  Aggregate Device called `🧪 WT Inject` wrapping BlackHole 2ch (created with
  `AudioHardwareCreateAggregateDevice` from a small Swift script — the guest has the CLT). Not done.
- **`hands-off` in the guest** is `~/bin/hands-off`, a no-op stub with the host's CLI: `run "<why>"
  -- cmd…` exports `HANDS_OFF=1` and execs `cmd`; `start`/`end`/anything else exit 0. There is no
  human at that screen to warn. The harness itself never calls `hands-off`; it only checks
  `HANDS_OFF` in the environment (`harness.py` `gesture()` and the case filter, and
  `cases_gestures.py`), so `HANDS_OFF=1` on the command line is all the gesture cases need.
  `looprun.sh` expects `hands-off run … --` around it; the stub satisfies that.
- `WT_WORK` defaults to `/tmp/wt-plan` — fine in the guest.
- The harness takes `~/.walkie-talkie/wispr-loop.lock` — the guest's own, so a host run and a lab
  run do not block each other.
- Still missing for a full run: the app deployed with the grants (above); `elevenlabs.env`; for
  the local-Whisper cases `mlx_whisper` + `ffmpeg` + the `whisper-large-v3-turbo` weights
  (whether MLX gets a GPU in a VZ guest is untested); `claude`/`codex` for the `cc`/`codex`
  tagged cases (they SKIP without).
- **Nightly**: the LaunchAgent below brings the VM up; the run itself would be a second host
  LaunchAgent (`StartCalendarInterval`) calling the four lines above. Not written yet — the disk
  speed decides whether a night is long enough.

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

## Starting with the host

`tools/ro.victorrentea.wt-lab.plist` — a **draft, not installed**: a user LaunchAgent that runs
`tools/vm-lab.sh up` at login (`RunAtLoad`) and on every volume mount (`StartOnMount`), so the lab
comes up when "Vic" appears. `up` exits 1 without the volume (harmless on other mounts) and is a
no-op when `wt-lab` already runs; `AbandonProcessGroup` keeps launchd from killing the
`nohup tart run` it leaves behind; no `KeepAlive`, so `down` stays down. Install line is in the
plist's header.
