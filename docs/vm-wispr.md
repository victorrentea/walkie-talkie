# Wispr Flow in a VM: moving the teacher batch off Victor's screen

*Research and preparation, 2026-09-26. No VM had been started when this was written. The Sequoia
base image was already pulled into `/Volumes/Vic/tart` (by another session) and nothing here
touched it.*

Victor's idea: install Wispr Flow inside a Tart macOS guest and run the corpus labelling batch
(`helpers/teacher_label.py` → `helpers/wispr_loopback.py`) there. The batch would then post its
chords and paste its transcripts inside the guest while he works on the laptop, and the
suspend-when-Victor-is-typing gate would never have to fire.

**Verdict: go for a one-hour feasibility run, and hold the full batch until two things are settled.**
Nothing found here makes it impossible. One point is a **decision** rather than a technical
problem, and it applies to the whole teacher project, VM or not: Wispr's ToS forbids using its
output to train models (§1 below). The rest are setup steps, and the step list is at the end.

---

## 1 · Wispr Flow on macOS

### What is installed here

| | read from this Mac, 2026-09-26 |
|---|---|
| version | **1.6.957** (`CFBundleShortVersionString`), bundle id `com.electron.wispr-flow`, arm64 only |
| kind | **Electron**: `Electron Framework.framework`, four `Wispr Flow Helper (…).app`, `app.asar` (125 MB). `Squirrel.framework` plus `autoUpdater.setFeedURL` in `app.asar` pointing at `dl.wisprflow.com`, so **it updates itself** |
| nested helper | `Contents/Resources/swift-helper-app-dist/Wispr Flow.app` (`com.electron.wispr-flow.accessibility-mac-app`), the one `open -a "Wispr Flow"` wrongly resolves to (`docs/loopback.md`) |
| size | 509 MB |
| signature | `Developer ID Application: Wispr AI INC (C9VQZ78H85)`, **notarized, ticket stapled** (`spctl -a -vv` → *accepted, source=Notarized Developer ID*), hardened runtime, entitlements `allow-jit` + `device.audio-input` |
| minimum macOS | `LSMinimumSystemVersion` 12.0. The guest is Sequoia 15, so this is fine |

**The bundle can simply be copied into the guest.** The copy uses the same `tar | tart exec -i`
that `tools/vm-lab.sh deploy` uses, which keeps the signature and xattrs. Because the notarization
ticket is stapled, Gatekeeper accepts it offline, and the Cirrus images have Gatekeeper disabled
anyway (`sudo spctl --global-disable` in their vanilla template). The alternative is the official
download, *"open the download, drag Wispr Flow into Applications, and launch it"*
([setup guide](https://docs.wisprflow.ai/articles/3152211871-setup-guide)), from
[wisprflow.ai/download](https://wisprflow.ai/download), which links to
`https://wisprflow.ai/downloads/login`, a page behind sign-in. Copying is simpler, and the app
updates itself afterwards either way.

### Authentication

- **Sign-in is an account login in a browser.** *"On desktop, sign-in opens in a browser"*, using
  *"Google, Apple, Microsoft, SSO, or email and password"*, and the session hands back to the app
  ([sync article](https://docs.wisprflow.ai/articles/5284722493-sync-flow-across-your-devices),
  [setup guide](https://docs.wisprflow.ai/articles/3152211871-setup-guide)). Another device has to
  use *"the same email and original sign-in method as your first device"*. In the guest this is a
  **human step** over Screen Sharing: Safari, Victor's Google (or other) login, maybe a 2FA tap on
  his phone.
- **The session is Supabase.** `~/Library/Application Support/Wispr Flow/session.json` holds one
  key, `sb-<project>-auth-token`. **Do not copy it into the guest.** Supabase refresh tokens are
  single-use: *"a refresh token can only be used once"*, with a 10 s reuse interval. Outside that
  interval, *"the whole session is regarded as terminated and all refresh tokens belonging to it are
  marked as revoked"* ([Supabase sessions](https://supabase.com/docs/guides/auth/sessions)). If the
  host and the guest shared one session, whichever refreshed second would log **both** out. For the
  same reason, **never clone a signed-in guest.** Two clones would hold the same session, and a
  `vm-lab.sh reset` from a base that carries a stale refresh token would revoke it. The guest signs
  in once, as its own device, and that VM is never cloned or baked back.
- **Device limits: none stated.** The ToS has none (see below). The help center says one account
  works across devices and names no cap ([manage your account](https://docs.wisprflow.ai/articles/7339517111-manage-your-flow-account)).
  `prefs.user.registeredDevices` on this Mac reads `["android", "darwin_arm64"]`: a per-platform
  list, not a per-machine count. Victor's plan is **`FLOW_PRO_MONTHLY`**, status `active`, from
  `prefs.user.subscription`. *"Recognized on every device signed into the same account."*
- **Offline: no.** The recogniser is remote. `degradedNetwork` and the `NoInternet` notification are
  in `config.json`, and `docs/loopback.md` measured `e2eLatency 1055 ms` with *"the remote
  recogniser did answer"*. The guest needs the network, and Tart's default NAT provides it.

### Permissions

Wispr's onboarding asks for **Microphone** and **Accessibility**, and nothing else
([setup guide](https://docs.wisprflow.ai/articles/3152211871-setup-guide)). Its own `config.json`
records the same two: `prefs.permissions = [accessibility: granted, microphone: granted]`. There is
no Input Monitoring or Screen Recording (`shouldOCRScreenCapture` is `false`).

### What the ToS and the docs say (read 2026-09-26)

From the [Terms of Service](https://wisprflow.ai/terms-of-service), *Last Updated: August 19, 2026*.
Each quote below was checked against the raw page text:

- **§3.B *Special Restrictions on Use of AI Features*:** *"You will not and will not permit anyone
  else to: … use the AI Features or any Output to develop, train or improve any AI or machine
  learning models"*. The same document defines Output: *"When you submit or provide audio … to the
  Services ("Input"), Wispr uses AI Features to generate outputs based on the Input ("Output")."*
  **This is exactly what the teacher batch does**, on the host today as well as in a VM: Wispr's
  `asrText` becomes the label a LoRA is trained on. The VM changes nothing about it. It is listed
  first because it is the one item here that is Victor's decision and not a setup step.
- **§3.A:** *"access, search, or create accounts for the Services by any means other than our
  publicly supported interfaces (for example, scraping or creating accounts in bulk)"*. The rig
  drives the shipped app through its own shortcut and microphone. That is a grey zone rather than
  scraping, but it is automated use.
- **Violations:** Wispr may respond with *"suspending a user's access to the Services, or
  terminating your account"*.
- **Devices, seats, VMs, rate limits: not mentioned in the ToS.**
- **VMs are unsupported, not forbidden.** *"iPad, Linux, Chromebooks, virtual machines, and remote
  desktop environments are not supported."* ([system requirements](https://docs.wisprflow.ai/articles/1036674442-supported-devices-and-system-requirements)).
  Nobody will help if it breaks. That is all the sentence says.

The account-level risk is the same one `teacher_label.py` already designs around: randomised gaps,
the backoff ladder, and the 3 h `teacher-cooldown` *"so this does not turn into a banned account"*.
A VM does not reduce it. If anything it raises it, because the guest can dictate around the clock,
concurrently with Victor's own dictation on the host, on the same account. Whether Wispr notices two
simultaneous streams is **unknown**, and the feasibility run should include one overlap on purpose.

### What syncs between host and guest, and what does not

From the [sync article](https://docs.wisprflow.ai/articles/5284722493-sync-flow-across-your-devices):

| | syncs? | consequence |
|---|---|---|
| **Dictation history** | *"Stored on each device; History never becomes a cross-device list."* | The guest's `flow.sqlite` is the guest's own, so the batch reads it **in the guest**. Nothing reaches the host's `flow.sqlite`, so `corpus_harvest.py` cannot swallow the rig's playback back into the corpus. That was the *"corpus eating its own tail"* incident behind `rig-runs/`, and it cannot happen here |
| **Shortcuts, microphone, sounds** | *"Set per device; another device will not copy them."* | Pinning the guest's mic to BlackHole cannot move the host's pin off `🎓 TO Wispr`, and the guest's chords have to be set in the guest |
| dictionary, snippets, languages, styles | sync | The guest inherits Victor's dictionary and `selectedLanguages: ["ro","en"]`, so the teacher behaves the same as on the host. Turn **auto-learn off** in the guest (`shouldAutoLearnWords`) so nothing learned there flows back |
| statistics | totals sync | The word counts go up. Harmless on Pro |

### The config keys the rig relies on

From `~/Library/Application Support/Wispr Flow/config.json` (48.6 KB) on the host:

```
prefs.user.shortcuts = {
  "54+61": "ptt",               ← Right ⌘ + Right ⌥ — what PushToTalk posts (WISPR_PTT_KEYS)
  "53+59": "dismiss",           ← ⌃Esc — post_wispr_dismiss() on an aborted clip (WISPR_DISMISS_KEYS)
  "49+59+63": "popo",           ← fn ⌃ Space, hands-free (WISPR_HANDSFREE_KEYS)
  "79": "open_scratchpad",      ← F18, rebound from ⌘⌥P (wispr_loop scenarios only; the batch never uses it)
  "178+59+63": "lens", "18+58": "polish", "19+58": "polish_prompt_1", "122+58": "polish_prompt_2",
  "55+59+8": "copy_last_text", "13+55+59": "paste_last_text", "101+56+58": "open_meeting_recorder" }
prefs.user.lastSetScratchpadShortcut = "79"
prefs.user.stashedScratchpadShortcuts = {"79": "open_scratchpad"}
prefs.user.overrideAudioDeviceId = "90960c04…"   ← salted Chromium deviceId; NOT portable
prefs.user.rankedAudioDevices = [{deviceId, name}, …]   ← Wispr's cache of the hash→name map
prefs.user.selectedLanguages = ["ro","en"]   prefs.user.openAtLogin = true   hideAppInDock = true
prefs.user.useAxContext = true   shouldAutoLearnWords   streamAudio = false   cloudSync = true
```

There is **no key named `micDevice`**. That is a column of `flow.sqlite`'s `History` table: the
microphone Wispr actually recorded from, per row. The rig reads it into `teacher_mic`. Every one of
the 2970 labels written so far says `🎓 TO Wispr (Virtual)`, so labels made in the guest will be
identifiable by `BlackHole 2ch`.

**What can be configured by copying and what cannot:**

- **Shortcuts: patch the guest's own `config.json` with Wispr quit.** Copy the host's
  `prefs.user.shortcuts` map (plus the two scratchpad keys) over the guest's. Do not record the
  chord in Wispr's UI over Screen Sharing: whether a VNC client delivers *Right* ⌘ / *Right* ⌥ as
  distinct from the left ones is unverified, and the chord is the one thing the rig cannot work
  without. The repo's rule *"nothing here may edit Wispr's config.json"* protects Victor's host
  install. The guest's install is a disposable copy, and it is edited only while Wispr is not
  running (it rewrites the file from memory).
- **Do not copy `config.json` wholesale.** It carries `prefs.deviceId`, `sessionId`,
  `anonymousId`, email and subscription. Cloning those would make the guest impersonate the host
  device.
- **The microphone: one click, in the guest.** `overrideAudioDeviceId` is a per-origin salted hash
  that cannot be computed from a device name (`wispr_preflight.wispr_microphone()`). Pick
  *BlackHole 2ch* once in Wispr → Settings → Microphone, then **close Settings**: the Microphone
  page holds the mic open and poisons runs (`wispr_settings_open()`). Auto-detect is not acceptable
  on the host (measured: it means the built-in mic). In a guest started with `--no-audio`,
  BlackHole would be the only input, but pin it explicitly anyway.

---

## 2 · What the batch needs in the guest

Read from `helpers/teacher_label.py`, `wispr_loopback.py`, `wispr_preflight.py`, `human_watch.py`,
`wispr_probe.py`, `docs/teacher-loopback.md` and `docs/loopback.md`.

**The batch uses `rig.dictate()`, not `rig.transcribe()`.** It posts the PTT chord itself with
`CGEventPost` and reads `asrText` from `flow.sqlite`. So **it does not need Walkie Talkie at all**:
no relay, no `/test/*` routes, no port 8917. The only relay-side module it touches is
`wispr_loop.take_runner_lock()`, a pid file at `~/.walkie-talkie/wispr-loop.lock`. Importing
`wispr_loop` pulls in `wispr_preflight`, but only its definitions: `teacher_label` never calls
`checks()`, so the relay/installed-build rows never run. (`transcribe()` would need the relay and
stores `formattedText` instead, which `docs/loopback.md` calls a corpus decision, not a refactor.)

| host dependency | in the guest |
|---|---|
| **Loopback `🎓 TO Wispr`** (Rogue Amoeba, paid) | **BlackHole 2ch** (`brew install --cask blackhole-2ch`, 0.7.1, a `.pkg`; the cask says *"You must reboot"* ([formulae.brew.sh](https://formulae.brew.sh/cask/blackhole-2ch))). It is a HAL plugin, *"no kernel extensions or modifications to system security necessary"*, installed at `/Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver`, with `sudo killall -9 coreaudiod` as the no-reboot alternative ([BlackHole README](https://github.com/ExistentialAudio/BlackHole)). No kext means no SIP or reduced-security dance in the guest. **Pass `--device BlackHole`**: `DEVICE_PREFERENCE` only knows the Loopback names. `extra_sources()` reads Loopback's `Devices.plist`, and a missing file returns `[]`, so no mic can be mixed in by construction |
| player: `sounddevice` + `numpy` (+ `scipy` for `resample_poly`, linear fallback without it) | the same wheels. `sounddevice`'s macOS wheel bundles `libportaudio.dylib`. Host versions: python.org **3.12.8 framework**, numpy 2.4.3, sounddevice 0.5.5, scipy 1.17.1, pyobjc 12.1 |
| `Quartz`, `ApplicationServices`, `CoreFoundation` (pyobjc) | `pyobjc-framework-Quartz pyobjc-framework-ApplicationServices` (Cocoa/CoreFoundation come with them) |
| **Accessibility for the interpreter** (`CGEventPost`, and `AXIsProcessTrusted` refuses to start without it) | see §3, *TCC*: the Cirrus base image already grants it to `org.python.python` and to `tart-guest-agent` |
| **Automation** (`osascript` → System Events for `paste_sink()`, → TextEdit for `wake_the_sink()`) | **not** pre-granted for python or the guest agent. Without it, the gated loop sits on a prompt nobody clicks (`ensure_sink` → "staying down", for ever). Insert the rows or click them once (§3) |
| Walkie Talkie, its routes | **not needed** |
| `~/bin/hands-off` | optional. If it is missing, `HandsOff` logs a warning and carries on. Install a no-op so the log stays clean (step 8) |
| corpus: `~/.walkie-talkie/voice-corpus/` (`VOICE_CORPUS_DIR`) | see *The corpus* below |
| `flow.sqlite` | the **guest's own** Wispr database, read `mode=ro`, same path. Nothing to mount |
| TextEdit as paste sink | present in the guest. `Gate.ensure_sink()` brings it forward before every clip |
| **the human gate** (`human_watch.py`) | keep it but make it inert: **`--quiet-minutes 0`**. `busy()` is `since_human < 0`, which is never true, while `ensure_sink()` still runs before each clip and keeps TextEdit in front. With `--ignore-human` the sink is checked only once, at start. A clip is still cut short if a *hardware* (pid-0) event reaches the guest, for example a click in a Tart UI window. `--no-graphics` has none, so the gate stays silent. The tap needs Accessibility, which the same grant covers |
| locks, cooldown, status file, `rig-runs/` | all under the guest's `~` and independent of the host's. The host's runner lock does **not** block the guest, which is the point: host tests and the guest batch can run together |

### The corpus

`pending()` on 2026-09-26 (read-only query), with the batch's own default filter
(`addons-mic` + `whisper-local`, no `teacher_text`, 1–120 s):

| | clips | audio |
|---|---|---|
| addons-mic | 1093 | 111 min |
| whisper-local | 1413 | 688 min |
| **total** | **2506** (977 under 3 s, 658 of 30 s or more) | **799 min**, **1.53 GB** of WAV, none missing |

The figure of **1529** in the brief is not today's queue: 2506 is. It may be an older count, or it
may have come from the 1.53 GB. The whole corpus directory is 3.4 GB (`mic/` 818 MB, `corpus.db`
5 MB). Probe stages 2–3 also need a few `wispr`-source clips (1269 with audio and `asr_text`).

At the batch's own estimate (`MEAN_GAP_SEC` 7.6 s + 3 s per clip + real time) that is about **21 h
of wall clock**: two nights, or one day and a night in a VM that never has to wait for Victor.

**Recommended layout, mount read-only, write locally, send out through a share:**

- host corpus as a **read-only** virtiofs share. The guest can never write into Victor's corpus,
  and nothing is copied.
- in the guest, a real `~/.walkie-talkie/voice-corpus/` holding a **copy** of `corpus.db`,
  `rig-runs/`, and one symlink per date directory (and `mic`) into the share. `teacher_label`
  resolves `CORPUS / wav`, and symlinks are followed.
- **Never** point the guest at the host's `corpus.db` over virtiofs. SQLite's locking across the VM
  boundary is not something to trust with a file that `mic_corpus_ingest` and the
  `voice-corpus-harvest` LaunchAgent write on the host.

### How the labels get back

The batch writes `teacher_text`, `teacher_at` and `teacher_mic` into **its** `corpus.db`,
committed per sample, and, with `--manifest PATH`, appends one JSONL row per label (`id, wav,
seconds, source, student, teacher, mic`, but no timestamp). Both are keyed by `samples.id`, which
is the stable primary key (Wispr's `transcriptEntityId` or the relay's stem).

- Point `--manifest` at a **read-write share** (`/Volumes/My Shared Files/out/labels-<date>.jsonl`).
  It is live, append-only, has a single writer, and the host can `tail` it.
- At the end, `sqlite3 corpus.db ".backup '/Volumes/My Shared Files/out/corpus-guest.db'"`.
- Merge on the host, **only into empty rows**, which keeps the batch's own rule (*"never
  overwrites a label already written"*). The host has sqlite 3.43, and `UPDATE … FROM` needs 3.33:

```sql
ATTACH '/Volumes/Vic/tart/wt-wispr-out/corpus-guest.db' AS g;
UPDATE samples SET teacher_text = x.teacher_text, teacher_at = x.teacher_at,
                   teacher_mic  = x.teacher_mic
FROM (SELECT id, teacher_text, teacher_at, teacher_mic FROM g.samples
      WHERE teacher_text <> '') AS x
WHERE samples.id = x.id AND (samples.teacher_text IS NULL OR samples.teacher_text = '');
```

- **Not over `tart exec … cat`.** Tart issue [#1347](https://github.com/openai/tart/issues/1347):
  guest stdout is lost *"when more than a few hundred KiB is sent quickly"* on macOS 12–15 guests,
  including *"output silently truncates while exit code remains intact (including exit 0)"*. It was
  reported on Tart 2.37 with the loss isolated to virtio-vsock, so 2.34 should be assumed affected.
  A share or `scp` is fine. `tart exec` stays fine for commands and for the small status file.

Next night: take a fresh `.backup` of the host `corpus.db` as the new guest copy. The merged labels
are then already in it, so the queue shrinks with no bookkeeping.

---

## 3 · Tart specifics (tart 2.34.0 on this host)

### Audio: the guest gets the host's microphone unless told otherwise

`tart run --help` on this host: `--no-audio  Disable audio pass-through to host.` So audio is **on
by default**, and the source shows what "on" means ([`Sources/tart/VM.swift`](https://github.com/cirruslabs/tart/blob/main/Sources/tart/VM.swift)):

```swift
if audio && !suspendable {
  inputAudioStreamConfiguration.source = VZHostAudioInputStreamSource()
  outputAudioStreamConfiguration.sink = VZHostAudioOutputStreamSink()
  …
} else {
  soundDeviceConfiguration.streams = [VZVirtioSoundDeviceOutputStreamConfiguration()]
}
```

By default the guest has a **microphone that is the host's default input**. That is exactly the
contamination `extra_sources()` exists to refuse, one level up: a Wispr on Auto-detect, or one that
wandered to "the built-in mic", would label clips with Victor's room. It would also make `tart` ask
the host for microphone permission. **Run the Wispr guest with `--no-audio`**, which leaves an
output-only stream with no sink. BlackHole needs no virtual hardware at all: it is a plugin inside
the guest's own `coreaudiod`, clocked in software. `tools/vm-lab.sh up` currently runs
`tart run "$VM" --no-graphics` with no way to add flags, so it needs a knob (see the steps). That
file belongs to the lab session and has uncommitted edits, so it is not changed here.

**BlackHole inside a Virtualization.framework guest is expected to work and has not been shown
to.** Nothing found either confirms or refutes it. Probe stage 1 (device visible, stream opens)
and stage 3 (Wispr-vs-Wispr WER on replayed clips, median should be ≈ 0) are the test, and they
decide the whole thing before anything else is built.

### A GUI session and privacy grants

The Cirrus images auto-login `admin`/`admin` (vanilla template: `kcpassword`,
`autoLoginUser admin`, screensaver and screen lock off, passwordless sudo). The guest is therefore
always in an Aqua session, which Wispr, `CGEventPost` and the event tap all need.

More useful: **the base image already writes TCC grants for us.** The base template ends with
`scripts/update-tcc-database.sh`
([macos-image-templates](https://github.com/cirruslabs/macos-image-templates), `templates/base.pkr.hcl`),
which `sudo sqlite3`-inserts into **both** the system and the user `TCC.db`:

- `org.python.python`: Accessibility, PostEvent, Microphone, ScreenCapture. That is the bundle id
  of the framework build's `Python.app`, i.e. the interpreter the batch runs in.
- `tart-guest-agent`: the same four. This covers commands started through `tart exec`.
- `/usr/bin/osascript` and `sshd-keygen-wrapper`: AppleEvents → `com.apple.systemevents`.

Missing are AppleEvents for python and the guest agent (→ System Events, → TextEdit), and all of
Wispr's grants. There are two ways to add them:

1. **Rows, over SSH**, the way the image's own build does it. That build runs this script over SSH
   with `sudo`, which is the proof that the route writes. Same table, same columns: `service`,
   `client_type` (0 = bundle id), `client`, `auth_value` 2, `indirect_object_identifier` = the
   target bundle id for AppleEvents. Then `sudo killall tccd` or reboot. Check the route on the day
   before relying on it: `csrutil status`, then a trivial `INSERT OR REPLACE`.
2. **Clicks over Screen Sharing** (`vm-lab.sh look`, admin/admin), once. Wispr's own two prompts are
   clicked this way anyway, because its onboarding shows them and the sign-in needs a human.

After the grants, do **not** `vm-lab.sh bake` the Wispr guest into `wt-base`: that would clone the
Supabase session and Wispr's `deviceId` into every future lab clone. Instead:

- **a dedicated VM `wt-wispr`**, cloned from `wt-base`;
- a stopped **pre-sign-in** clone `wt-wispr-golden` (Wispr, BlackHole, python and TCC rows, no
  account), so a rebuild costs one sign-in;
- `wt-wispr` itself is never cloned again.

### Running it unattended

**Launch the batch as a LaunchAgent in the guest**, not through a long-lived `tart exec`:

- the batch should not depend on a host process staying attached for 20 h;
- a launchd-spawned python is its own responsible process, so the `org.python.python` grants apply
  directly;
- a `gui/501` agent runs in the Aqua session.

`tart exec wt-wispr launchctl kickstart gui/501/ro.victorrentea.teacher-label` starts it.
`tart exec wt-wispr cat ~/.walkie-talkie/teacher-status.json` (small) or the share's JSONL watches
it.

### Two limits of the platform

- **Two macOS guests at most, concurrently.** Virtualization.framework refuses a third with
  `VZErrorDomain` code 6 ([Eclectic Light](https://eclecticlight.co/2022/08/04/virtualisation-on-apple-silicon-macs-8-how-apple-limits-vms/)).
  `wt-lab` plus `wt-wispr` fills both. The licence permits *"up to two (2) additional copies or
  instances … within virtual operating system environments on each Apple-branded computer you own
  or control"* for *"(a) software development; (b) testing during software development; … or (d)
  personal, non-commercial use"* ([macOS Sequoia SLA §2B(iii)](https://www.apple.com/legal/sla/docs/macOSSequoia.pdf)).
- **The host must stay awake.** A sleeping laptop pauses the guest mid-clip. The row then arrives
  late and is dropped by the lag check, which is safe but wasted. Hold `caffeinate -i -w <tart
  pid>` on the host for the length of a run. RAM is not a concern: 64 GB on the host against 8 GB
  per guest.

---

## 4 · Go / no-go

**Blockers and risks, ranked:**

1. **ToS §3.B forbids training on Wispr's output.** This is a decision, not a setup step, and it
   applies to the existing host runs equally. The VM neither creates it nor helps with it.
2. **BlackHole-in-VZ plus Wispr accepting it as a microphone is unverified.** It is cheap to settle:
   probe stages 1–3 in the first hour. This is the technical go/no-go, the same way `wispr_probe.py`
   was on the host.
3. **Tart passes the host mic in by default.** Run with `--no-audio`, which needs a knob in
   `vm-lab.sh up`, and confirm `teacher_mic = BlackHole 2ch` on the first labels.
4. **Sign-in is a human step and the session is fragile to cloning.** One Screen Sharing session.
   Never copy `session.json`, never clone the signed-in VM.
5. **Automation (AppleEvents) grants are missing.** Without them the gated loop stalls silently on
   an unclicked prompt. Add them as TCC rows or click them in a supervised `--limit 3`.
6. **Account-level behaviour** under round-the-clock dictation that overlaps Victor's own is
   unknown. Keep the backoff and cooldown as they are, consider a `--stop-after` per day, and watch
   for the `raw_transcript` streaks that preceded the host's stand-downs.
7. **The labels-back path.** Use a share or `scp`, never `tart exec` stdout (#1347), and merge only
   into empty rows.
8. **Platform limits:** the two-guest ceiling, and the host must not sleep.

**Verdict: GO for the feasibility hour. GO for the batch** once probe stage 3 comes back near zero
WER and Victor has made the call on item 1.

---

## The step list, for the day the VM is up

`TART_HOME=/Volumes/Vic/tart` throughout, as `vm-lab.sh` sets it.

1. **Make the Wispr VM.** `tart clone wt-base wt-wispr` (or clone from the image if `wt-base` is
   not there yet), then `tart set wt-wispr --cpu 4 --memory 8192`, then
   `mkdir -p /Volumes/Vic/tart/wt-wispr-out`.
2. **Boot it headless, with no audio and two shares.** This needs a flags knob in `vm-lab.sh`, or
   run by hand:
   ```sh
   tart run wt-wispr --no-graphics --no-audio \
     --dir corpus:$HOME/.walkie-talkie/voice-corpus:ro \
     --dir out:/Volumes/Vic/tart/wt-wispr-out &
   caffeinate -i -w $! &
   ```
   In the guest they appear as `/Volumes/My Shared Files/{corpus,out}`.
3. **Check the ground.** `tart exec wt-wispr id -un` should say `admin`. Then, over
   `ssh admin@$(tart ip wt-wispr)`: `csrutil status` and
   `sudo sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" "select client, service from access"`.
   The Cirrus rows should be there.
4. **BlackHole.** `brew install --cask blackhole-2ch`, reboot the guest, then
   `system_profiler SPAudioDataType | grep -i blackhole`.
5. **Python.** Install the python.org 3.12 framework pkg (or Homebrew `python@3.12`, also a
   framework build), then
   `pip install numpy sounddevice scipy pyobjc-framework-Quartz pyobjc-framework-ApplicationServices`.
   Verify:
   `python3 -c "import ApplicationServices as a; print(a.AXIsProcessTrusted())"` → `True`
   (the Cirrus row), and `python3 helpers/wispr_loopback.py --list` shows `BlackHole 2ch`.
6. **The repo.** Copy `helpers/` into the guest, or mount the repo read-only as a third `--dir`.
7. **Wispr.**
   - Copy it in:
     `tar -C /Applications -cf - "Wispr Flow.app" | tart exec -i wt-wispr sudo tar -C /Applications -xf -`,
     then `chown -R admin:staff`.
   - Launch with `open -b com.electron.wispr-flow` (never `open -a`).
   - **Over Screen Sharing** (`WT_LAB_VM=wt-wispr tools/vm-lab.sh look`):
     sign in with Victor's original method, grant Microphone and Accessibility (for both Wispr and
     its accessibility helper if asked), finish onboarding, pick **BlackHole 2ch** in Settings →
     Microphone, and **close the Settings window**. *(This is the one step that needs Victor, about
     10 minutes.)*
8. **Patch the guest's Wispr config, with Wispr quit.**
   - Quit it: `osascript -e 'quit app id "com.electron.wispr-flow"'`, and wait until the main
     executable has gone.
   - Back up the guest's `config.json`.
   - Merge into its `prefs.user` from the host's:
     - `shortcuts`, `lastSetScratchpadShortcut`, `stashedScratchpadShortcuts`;
     - `shouldAutoLearnWords: false`, `openAtLogin: true`, `enableSounds: false`.
   - Nothing else: not `overrideAudioDeviceId` and not the ids.
   - Relaunch, then confirm with `python3 -c 'import json;…'` that `"54+61": "ptt"` is still there
     after Wispr has rewritten the file.
9. **Automation grants.** Insert AppleEvents rows for `org.python.python` → `com.apple.systemevents`
   and → `com.apple.TextEdit` into the user `TCC.db`, then `sudo killall tccd`. Alternatively,
   click the two prompts during step 11.
10. **Stubs and corpus layout.**
    - `~/bin/hands-off` as a no-op: `#!/bin/sh` / `exit 0`.
    - `mkdir -p ~/.walkie-talkie/voice-corpus`, then symlink every date directory and `mic` from
      `/Volumes/My Shared Files/corpus/`.
    - On the **host**, snapshot the database into the share:
      `/usr/bin/sqlite3 ~/.walkie-talkie/voice-corpus/corpus.db ".backup /Volumes/Vic/tart/wt-wispr-out/corpus-in.db"`.
    - In the guest, copy that file to `~/.walkie-talkie/voice-corpus/corpus.db`.
11. **The go/no-go, supervised over Screen Sharing.** Open a blank TextEdit document, then:
    ```sh
    python3 helpers/wispr_probe.py --device BlackHole --stage 1
    python3 helpers/wispr_probe.py --device BlackHole --n 20
    ```
    Stage 3's median WER must be ≈ 0. Above ~0.15 the channel is losing something: check
    BlackHole's rate in Audio MIDI Setup and that `PLAY_PEAK` is not clipping.
12. **A short batch**, still watched:
    `python3 helpers/teacher_label.py --device BlackHole --quiet-minutes 0 --limit 20 --manifest "/Volumes/My Shared Files/out/labels-$(date +%F).jsonl"`.
    Every line should say ✓. Check `teacher_mic = BlackHole 2ch` in the guest db. Dictate once on
    the host at the same time (the overlap test from §1). Merge on the host with the SQL above and
    spot-read five labels against the audio.
13. **Clone the golden copy now if not done before sign-in.** Stop the VM and
    `tart clone wt-wispr wt-wispr-golden` only if it is *pre-sign-in*. Otherwise skip, and remember
    the rule: no clones of a signed-in guest.
14. **The unattended run.**
    - A `~/Library/LaunchAgents/ro.victorrentea.teacher-label.plist` in the guest runs the step-12
      command with `--all`, `--stop-after 10` (Victor's call), and `TEACHER_LOG` set to the share.
    - Start it with `launchctl bootstrap gui/501 …`.
    - Watch `teacher-status.json`.
    - At the end: `.backup` into the share, then merge on the host.

## Sources

- Wispr ToS: https://wisprflow.ai/terms-of-service (Last Updated August 19, 2026; raw page checked for each quote)
- Wispr system requirements: https://docs.wisprflow.ai/articles/1036674442-supported-devices-and-system-requirements
- Wispr sync across devices: https://docs.wisprflow.ai/articles/5284722493-sync-flow-across-your-devices
- Wispr account management: https://docs.wisprflow.ai/articles/7339517111-manage-your-flow-account
- Wispr setup guide: https://docs.wisprflow.ai/articles/3152211871-setup-guide
- Wispr download: https://wisprflow.ai/download (→ https://wisprflow.ai/downloads/login)
- Supabase refresh-token reuse: https://supabase.com/docs/guides/auth/sessions
- BlackHole: https://github.com/ExistentialAudio/BlackHole, https://formulae.brew.sh/cask/blackhole-2ch
- Tart audio config: https://github.com/cirruslabs/tart/blob/main/Sources/tart/VM.swift
- Tart exec output loss: https://github.com/openai/tart/issues/1347
- Tart guest agent (agent vs daemon): https://github.com/cirruslabs/tart-guest-agent
- Cirrus image templates (auto-login, TCC rows, guest-agent plists): https://github.com/cirruslabs/macos-image-templates
- Two-VM limit: https://eclecticlight.co/2022/08/04/virtualisation-on-apple-silicon-macs-8-how-apple-limits-vms/
- macOS Sequoia SLA §2B(iii): https://www.apple.com/legal/sla/docs/macOSSequoia.pdf
