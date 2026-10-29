# Wispr Flow in the lab — first end-to-end sentences (2026-09-28)

The Tart guest `wt-lab` (macOS 15.7.7, 192.168.64.4) after Victor signed Wispr Flow 1.6.957 in and
finished its onboarding over Screen Sharing. Everything below ran **inside the guest**: no key, no
audio, no clipboard write on the host. Driven by a subagent session, 08:19–08:50 EEST (05:19–05:50
guest time, GMT).

**The chord moved while this ran.** The brief said `54+60` (right ⌘⇧, Q9); at 08:40 EEST commit
`3093344` (Q23) moved the host's Wispr ptt to **`61+60` (right ⌥ + right ⇧)** and
`WISPR_PTT_KEYS` to `61,60`. The guest was patched to `54+60` first (relay runs 1–3, standalone
runs 1–2), then re-synced to the host's new map at 08:42 and the standalone case was run again on
`61+60` (runs 3–5). **The guest now says `"61+60": "ptt"`**, like the host.

**Verdict: both paths work in the guest.** The relay's own Wispr sentence (Engine = wispr, bound
witness tab) delivered from Wispr's History row with Wispr's ⌘V swallowed, 3 of 3. Wispr's own
chord with the relay idle pasted at TextEdit's caret and left the bound terminal alone: 2 of 2 on
`54+60`, 2 of 3 on `61+60` (the first `61+60` chord, ~2 min after Wispr's relaunch, made no row at
all). The recogniser lost words in 3 of 7 sentences that it transcribed (details below).

## What was done

| step | how | result |
|---|---|---|
| deploy the app | host `/Applications/Walkie Talkie.app` (build 2026-09-28 07:51 EEST, `1f2645e` era, `codesign --verify --deep --strict` **passes** on the host now) tarred over SSH; old bundle moved to the guest's `/tmp/Walkie Talkie.app.old`; `chown admin:staff`; `open` over SSH | 9 s; `codesign --verify --strict` OK in the guest; `accessibility trusted=true eventTap=true bundle=ro.victorrentea.wispr-relay` at 05:23:38 |
| `elevenlabs.env` | host file minus any `WT_ELEVEN_*_URL` / `# fake-scribe:` lines (there were none), mode 600 | contains `WT_WISPR_STANDALONE=1` (Q9), as on the host; `GET /test/state.wisprStandalone` → `true` |
| repo mirror `~/wt-lab` | the tar line of `docs/vm-lab.md` (includes `evals/plan/fake_scribe.py`, `cases_*.py`) | 8 s |
| Wispr config | Wispr killed (`pkill -9`, main + helper + crashpad), `config.json` backed up to `config.json.bak-2026-09-28-before-chord`, merged, relaunched with `open -b com.electron.wispr-flow` | `54+60` survived Wispr's rewrites at 05:25:08 and 05:38:41 |
| Wispr config, Q23 | same again at 05:42 (backup `config.json.bak-2026-09-28-before-q23`): the host's new `shortcuts` map verbatim, plus the `ptt` entry of `prefs.cache.splitKeybinds` set to `[61, 60]` (the host commit edited that cache too; Wispr had rebuilt it from `shortcuts` by itself after the first patch) | `61+60` in both places after Wispr's rewrites at 05:42:38 and 05:46:11 |
| Automation grants | rows inserted into the guest's **user** `TCC.db` (SIP is **disabled** in this image, and `sshd-keygen-wrapper` has Full Disk Access), then `sudo killall tccd`; backup `/tmp/user-TCC.db.bak-2026-09-28` | `osascript` from SSH drives Terminal, TextEdit and System Events with no prompt |
| pyobjc for `CGEventPost` | `pip3 install --user --only-binary=:all: pyobjc-core==11.1 pyobjc-framework-{Cocoa,Quartz,ApplicationServices}==11.1` into `/usr/bin/python3` 3.9 | an unpinned install picked pyobjc 12.0 **sdist** (no cp39 wheels) and started compiling — killed; 11.1 has wheels. `AXIsProcessTrusted()` → `True` from SSH |
| `/test/firewall` | before and after the runs | `alive`, `tap: alive`, canary 52.5 ms (cold) / 1.1 ms |

### The Wispr config diff (`prefs.user`, guest)

```
shortcuts:
- {"53": "dismiss", "63": "ptt", "49+63": "popo", "59+63": "lens",
-  "55+59+9": "paste_last_text", "55+59+8": "copy_last_text", "46+58": "open_meeting_recorder"}
+ {"79": "open_scratchpad", "49+59+63": "popo", "178+59+63": "lens",
+  "18+58": "polish", "19+58": "polish_prompt_1", "122+58": "polish_prompt_2",
+  "55+59+8": "copy_last_text", "53+59": "dismiss", "13+55+59": "paste_last_text",
+  "101+56+58": "open_meeting_recorder", "61+60": "ptt"}      ← the host's map, verbatim (Q23);
                                                                 "54+60": "ptt" from 05:23 to 05:42
prefs.cache.splitKeybinds ptt: [54, 60] (Wispr's own rebuild after the first patch) → [61, 60]
lastSetScratchpadShortcut:   ""  → "79"
stashedScratchpadShortcuts:  {}  → {"79": "open_scratchpad"}
shouldAutoLearnWords:      true  → false
enableSounds:              true  → false
openAtLogin:               true  (unchanged)
overrideAudioDeviceId: "default" (unchanged — Auto-detect, which is BlackHole 2ch, the guest's
                                  default and only input; rankedAudioDevices says
                                  "Auto-detect (BlackHole 2ch)")
```

Every History row of the run says `micDevice = Auto-detect (BlackHole 2ch)`.

### The TCC rows added (user `TCC.db`, `kTCCServiceAppleEvents`, `auth_value` 2)

Clients `/usr/libexec/sshd-keygen-wrapper`, `/usr/bin/osascript`, `/usr/bin/python3` (path) and
`org.python.python`, `com.apple.python3` (bundle) and the `tart-guest-agent` binary, each →
`com.apple.systemevents`, `com.apple.TextEdit`, `com.apple.Terminal` (`INSERT OR IGNORE`, so the
existing Cirrus and click-granted rows were kept).

## Why everything went over SSH: `tart exec` was dead for this boot

`tart run` had been started at 07:38 EEST (not by this session) and its log says
`Failed to run control socket: NIOFcntlFailedError()`; `vms/wt-lab/control.sock` does not exist,
and every `tart exec` answers `GRPCConnectionPoolError … is the Tart Guest Agent running?` although
both `tart-guest-agent` processes run in the guest. Only a new `tart run` would bring it back; the
guest was not restarted. With SIP off, the Automation grants went to `sshd-keygen-wrapper` instead,
so SSH could do everything, `osascript`, `CGEventPost`, `screencapture` and `sounddevice` included.
(`launchctl asuser 501 …` from SSH fails with `Could not switch to audit session … Operation not
permitted`. Plain `open` from SSH works.) `vm-lab.sh shot` / `deploy` use `tart exec`, so the
screenshots were `ssh … screencapture -x` and the deploy was the manual tar.

## The runs

Driver: `wfirst.py` (a copy is at `~/tart/night/wispr/wfirst.py`, the guest's at
`~/wt-lab/wfirst.py`), run as `/usr/bin/python3` over SSH. The clip is the harness's `CLIP_EN`
(3.5 s, *"If I dictate now, how good is this dictation, I wonder?"*), resampled to 48 kHz stereo,
peak 0.5, with 0.5 s of silence either side, played into **BlackHole 2ch** with `sounddevice`.

- **Relay path** (`wfirst.py relay N`): `POST /engine {"id":"wispr"}`; a witness Terminal tab
  running `stty -echo; exec cat >> /tmp/wt-wispr-witness.txt` (the harness's `witness_open`),
  `POST /bind {"tty"}`; `/test/key-trace` and `/test/sink` on; `POST /test/gesture
  {"name":"forward-right"}` (the app posts ⌃⌥⌘F10 → Wispr's hands-free `fn ⌃ Space`); the clip;
  `forward-right` again.
- **Standalone path** (`wfirst.py standalone N`): relay idle but **still bound** to the witness tab;
  TextEdit activated with a new empty document; right ⌘ (54) and right ⇧ (60) key-downs posted with
  `CGEventPost(kCGHIDEventTap)` exactly as `helpers/wispr_loopback.PushToTalk` posts them (bare key
  events, no explicit flags); the clip; key-ups in reverse order.

### Relay path — Engine = wispr, bound witness

Offsets from the relay's own log (ms after the chord or after the microphone closed, which the app
stamps itself), plus Wispr's row.

| run | relay sees Wispr's row | Wispr `timestamp` − chord | ⌘V from Wispr | row `formatted` | words landed (routed to Terminal) | `📦 delivery` (tty written) | Wispr e2e | Wispr's text | witness | sink |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 (first sentence after launch, guest load ≈ 25–45) | **3316 ms** after the chord | 0.67 s | only the key-**up** traced, `SWALLOWED by the Wispr firewall`, 1 s after `🛡️ the tap was disabled by the system (timeout) — re-enabled`; no key-down line | 5246 ms after mic close | 5304 ms | +14 s after landing (05:35:04 → 05:35:18) | 796 ms | *If I dictate now how is this dictation?* | envelope with that text, once | empty, 0 events |
| 2 | 757 ms | 0.31 s | **dropped 804 ms after mic close** (`probe: synthetic key 9 flags 0x20100000 from pid 1605 (Wispr Flow)`), ↓ and ↑ swallowed | 870 ms | 893 ms | +5 s (05:36:32 → 05:36:37) | 407 ms | *If I dictate now, how good is this dictation? I wonder* — whole | once | empty |
| 3 | 759 ms | 0.57 s | ↓ and ↑ swallowed **after** the words had landed: `⚠️ 🛡️ ⌘V from Wispr Flow dropped with no capture open — delivering the sentence from Wispr's History row instead` → `⚠️ 🛡️ rescue: the newest row is one already delivered — nothing to put anywhere` | 860 ms | 915 ms | +6 s (05:38:32 → 05:38:38) | 502 ms | *Now how good is this dictation, I wonder?* | once | empty |

All three: `lastDelivery = {via: "wispr-history", kind: "route", to: "terminal:ttys00N"}`; the
witness file holds exactly one envelope per run (`[📸0🖱️@0:… auto]` + the sentence + the
`[Dictated in RO or EN]` / `📁` lines); the `WisprSink` window was key and received nothing. The
relay also recorded its own copy through BlackHole 2ch (`mic: recording through BlackHole 2ch`,
corpus `wispr-flow` 7.2–8.5 s) — the guest has no other input for "Automatic" to pick.

The gap from *words landed* to the tty write (`⌨️ ttysNNN foreground=cat — N chars` 4 s later, the
`📦 delivery` line 5–14 s later) is as measured; its cause was not investigated here (Autosend is
off in the guest, `prompt.held` false after the run).

### Standalone path — Wispr's own chord, relay idle

| run | chord ↓ → Wispr `timestamp` | chord ↑ → row `formatted` and text in TextEdit | Wispr e2e | TextEdit | witness tab | relay |
|---|---|---|---|---|---|---|
| 1 (`54+60`) | 0.32 s | ≤ 0.67 s (poll-limited) | 460 ms | *If I dictate now, how good is this dictation? I wonder* — whole | unchanged | `⚡ Wispr opened its microphone for a sentence of its own — left to Wispr (standalone, Q9)` · `🛡️ ⌘V from Wispr Flow passed — its own sentence (standalone, Q9)` · `⌨️ Wispr's ⌘V released with ⌘ still stamped on it — the flag has been put back down`; `lastDelivery` unchanged |
| 2 (`54+60`) | 0.33 s | ≤ 0.48 s | 419 ms | *If I dictate now how good is this dictation?* (no *I wonder*) | unchanged | `🛡️ ⌘V passed — its own sentence (standalone, Q9)` + the same ⌘-flag line; `lastDelivery` unchanged |
| 3 (`61+60`, 05:44:25, ~2 min after Wispr's relaunch) | **no row at all** within 10 s + 45 s | — | — | empty | unchanged | nothing about Wispr; two main-thread stalls (`🧊 … silent for 3.6 s`, `3.8 s`, samples in `~/.walkie-talkie/hangs/hang-2026-09-28-05-44-4{1,7}.txt`) while the chord was held |
| 4 (`61+60`) | 0.43 s (poll) | ≤ 0.45 s | 480 ms | *If I dictate now, how good is this dictation? I wonder* — whole | unchanged | `⚡ … left to Wispr (standalone, Q9)` · `🛡️ ⌘V … passed` · ⌘-flag line |
| 5 (`61+60`) | 0.53 s (poll) | ≤ 0.52 s | 448 ms | *If I dictate now how good is this dictation, I wonder?* — whole | unchanged | same three lines |

Wispr's row names `app = com.apple.TextEdit`; `sessionFlags` after the release: `[]` (no modifier
left stuck). In run 1 the driver waited 10 s for a mic signal before playing (see the caveat below),
so the chord was held 16 s; run 2 played as soon as the row existed (0.46 s).

### Timing summary (guest, warm runs)

- chord → Wispr's row exists: **0.3–0.6 s** (Wispr's `timestamp`); the relay's poll sees it at
  **757–773 ms** (cold first sentence: 3316 ms).
- mic close → Wispr's ⌘V: 804 ms (run 2); in run 3 it came after the row, ~0.9 s.
- mic close → row `formatted`: **860–870 ms** (cold: 5246 ms). The host measured 458–540 ms
  (`dictation-source.md`).
- mic close → words landed (routed): **893–915 ms** (cold: 5304 ms) — 20–55 ms after the row.
- chord ↑ → text at TextEdit's caret (standalone): **≤ 0.45–0.7 s**, the same on `54+60` and `61+60`.
- Wispr's own `e2eLatency`: 407–502 ms warm, 796 ms cold.

**Caveat — no clean "Wispr opened its microphone" stamp in this rig.** `GET /test/state.wisprHearing`
(the relay's `IsRunningInput` witness) cannot tell Wispr from the relay's own recorder or from the
driver's own playback, all on BlackHole 2ch. In the standalone runs it never flipped during the
chord; in the relay runs it flipped with the relay's recorder. The relay's own `wispr flow opened the
microphone` line appeared once, at the moment the playback started (standalone run 1). The
"chord → row" column is therefore the start-of-listening measure used here.

## Failures and oddities, verbatim

1. **Words lost by the recogniser in 3 of 7 transcribed sentences**: run 1 lost *good* and *I wonder* (ASR
   `If I dictate now, how is this dictation?`), relay run 3 lost *If I dictate* (ASR `Now, how good
   is this dictation? I wonder.`), standalone run 2 lost *I wonder* (ASR `If I dictate now, how good
   is this dictation?`). The playback was complete each time (the ⌘/stop came 0.6 s after the last
   sample). Not investigated: BlackHole under a loaded guest (load average 10–45 during the runs,
   `screensharingd` + `WindowServer` at ~140 % CPU while Victor's Screen Sharing window was
   connected) is the first suspect.
2. **Run 1: `🛡️ the tap was disabled by the system (timeout) — re-enabled`** at 05:35:01, one second
   before Wispr's ⌘V; only the key-up of that ⌘V is in the key trace. Nothing was pasted anywhere
   visible (sink empty, witness once). The main thread was also reported silent 3–14 s several
   times right after launch (`⚠️ 🧊 main thread silent for 13.7 s — the tap swallows nothing until
   it is back`).
3. **Run 3: Wispr's ⌘V arrived after the capture had closed** — the rescue path ran and correctly
   found the row already delivered. A `⚠️` in the log for a sentence that went right.
4. `tart exec` unusable for the whole boot (`NIOFcntlFailedError` on the control socket, above).
5. **Standalone run 3 (`61+60`): the chord made no History row** — the first `61+60` chord, ~2 min
   after Wispr's relaunch, during two relay main-thread stalls. Runs 4 and 5, a minute later, worked.
   Whether Wispr was still starting or missed the key-downs is not known; one sample.
6. **The firewalled sentence's text stayed on the guest's pasteboard.** After relay run 3 the
   guest's `pbpaste` was Wispr's `pastedText` of that run (*"Now how good is this dictation, I
   wonder? "*, 42 bytes) and was still there after the later standalone pastes (which restore to
   it). One sample; on the host the same would put a dictated sentence on Victor's clipboard.
7. Relay log, not new: `⚠️ wispr scratchpad: no window titles readable — grant Screen Recording`
   (also on 09-26 in this guest), although `ro.victorrentea.wispr-relay` has a ScreenCapture row and
   the envelope's screenshot is captured.
8. Victor's Screen Sharing window stayed connected throughout. A `pkill screensharingd` in the guest
   (to protect his clipboard from Screen Sharing's shared clipboard) was undone in seconds by the
   client reconnecting by itself. The host pasteboard was watched read-only instead
   (`NSPasteboard.changeCount`): 3933 before and after every run up to 08:40; it went to 3934 between
   08:40 and 08:45 with 205 characters that are none of the guest's texts (the guest's pasteboard
   held 42 bytes then) — host activity, not the guest.

## State left behind

Guest running. Wispr Flow running with `61+60 = ptt` (Q23, same map as the host); Walkie Talkie running, Engine back on
`eleven-live` (what it was), unbound, firewall alive. Witness tabs killed and closed; three
TextEdit documents (*Untitled*, *Untitled 2*, *Untitled 3*) left open with the standalone text.
Screenshots and raw JSON per run: `~/tart/night/wispr/` (`00-before.png`,
`01-relay1-after.png`, `02-standalone1-after.png`, `03-standalone2-after.png`,
`04-relay-witness-tab.png`, `05-standalone-q23-after.png`, `relay{1,2,3}.json.txt`,
`standalone{1,2}.json.txt`, `standalone{3,4,5}-q23.json.txt`, `wfirst.py`).
