# Can Wispr Flow's text injection be blocked? — attack plan

**Status:** research done 2026-09-22; **① + ③ shipped the same evening** (see CLAUDE.md, *The
Wispr firewall*, and the journal). §5's quality test was skipped on Victor's word — the objective
was the block itself. ② (the extension host) and ④ are still open as the fallbacks they were.

**Produced by** a 10-angle research fan-out (TCC, event taps, AX writes, pasteboard, in-flight
cancellation, sandbox/VM, Wispr's own config, wrapper/shim, target hardening, an OS-mechanism
sweep), each angle adversarially refuted by a second pass, then synthesised. 23 agents.

**Read first:** `CLAUDE.md` → *The dictation source*, *Never reintroduce*;
`.claude/rules/dictation-source.md`; `docs/journal.md` → *Wispr Flow leaves the Engine list
(2026-09-22)* and the wrap sections.

---

## 0. Why this exists

Wispr Flow has the transcript quality Victor wants but **no API**: it delivers by injecting text
into whatever has focus. Everything the repo built — the Scratchpad wrap, the sink, the
`History` poll, `armKeyRedirect` — survives that injection rather than preventing it. On
2026-09-22 Victor removed Wispr Flow from the `Engine` menu entirely:

> *"scoate wisprflow ca sursă de dictare din lista de Engine — n-am reușit niciodată să-l
> integrăm ca lumea în fluxul nostru să-i preluăm ce text injectează."*

The removal shipped (one small diff: `applyEngineRow`, `engine(named:)`, `engineId`,
`engineMark`). `WisprFlowSource` is **not** deleted — 🔽 → still posts its chord raw,
`hearingChanged` still feeds the ⚡ ring — so if anything below lands, the Engine row comes back
cheaply.

---

## 1. The headline finding — the premise was wrong

**There is no Accessibility dictation path in Wispr at all.**

The log line that justified the entire Scratchpad subsystem —

```
direct AXValue set did not stick, falling back to clipboard paste
```

— is prefixed **`ConsentChatMessage:`**. It belongs to Wispr's *meeting-chat composer*, a
different feature, and carries **no dictation traffic**. Every dictation rung in the binary ends
in `Performed paste operation`.

So a dictation delivery is: **clipboard + a plain `CGEventPost` ⌘V at a location a session event
tap can see.** That is deletable, and **the relay already deletes it** —
`HotkeyTap.swift:2553` swallows `keycode 9 + maskCommand + isWispr(pid)`, and relay.log has
recorded it working.

Two conditions on the "yes":

- **(X)** Wispr keeps posting a session-visible `CGEventPost` rather than `CGEventPostToPid`.
  The helper imports both. One vendor release could change this silently. → open question 1.
- **(Y)** The relay's tap is verifiably alive at the moment of the paste. It currently cannot
  prove this. → idea 3, which is **mandatory**, not optional.

---

## 2. The plan, ranked

### ① Delete the Scratchpad wrap. Keep the swallow, the History row, drive Wispr by URL scheme.

**The loudest finding: this is a three-line deletion in code that already ships, not a new
mechanism.**

- Remove the `injectionArmedNow()` gate at `HotkeyTap.swift:2544` so the swallow branch at
  `:2553` is **stateless and always live**. That gate *is* the ordering bet that leaked 5/5 the
  evening it was measured — a ⌘V that arrives before the relay knows the microphone shut.
- Text comes from `WisprHistory`'s `formatted` row, already in use, 400–530 ms.
- Start/stop with `open -g wispr-flow://start-hands-free` / `wispr-flow://stop-hands-free`.
  Verified registered in `Info.plist` **and** in the asar dispatcher at `index.js` @8735158; the
  `showWindow()` call sits in a **later** branch, so **focus does not move**.

**What it deletes:** the Wispr window on screen at all — so no 17–40 ms flash, no
start-from-CLOSED precondition, no toggle-close ambiguity, no parking, no orphan sweep, no 120 s
dead-man's switch, no `armKeyRedirect`, no 200 ms/character AX re-insertion, no synthesized
chord, no `backButtonStamp` filtering. Roughly an entire subsystem.

**Cost to Victor:** zero visible. But Wispr standalone (the 🔽 → gesture) then needs the relay to
**re-post an identical ⌘V** — from a **dedicated serial queue**, *not* `DispatchQueue.main.async`:
the documented CoreAudio main-thread wedge would otherwise leave the relay eating Wispr's pastes
forever while never re-posting them.

**Non-negotiable companion fix.** Identify Wispr by **`SecCodeCopyGuestWithAttributes` +
`SecCodeCheckValidity` against Team ID `C9VQZ78H85`**, keyed on `(pid, kp_proc.p_un.__p_starttime)`.
The current `proc_name` substring match with a never-pruned cache will, under an always-on drop,
eat an innocent app's ⌘V after a pid reuse. **Fail closed:** drop on the cheap name match, let the
signature check *demote* a false positive asynchronously, never authorise a first paste.

**Cheapest experiment.** Flip the gate in a debug build; ten real dictations with the wrap off
into TextEdit. Answer three things:
1. Does Wispr retry or escalate to its `using fallback element` / `as last resort` paste sites
   after a drop?
2. Does a `FailedPasteNotification` banner appear?
3. Does reading `NSPasteboard` from the relay silence the delayed-clipboard timer?
   (`DelayedClipboardProvider` is real — the sentence is a *promise*, and a swallowed ⌘V means
   nobody pulls it.)

**What kills it:** a visible Wispr error banner on every sentence, or an escalation that
double-inserts.

---

### ② Make Wispr refuse to paste — using Wispr's own extension host.

The shipped app contains a complete extension host. The deterministic hook is
**`modifyDictationRoute`** with a `dictationCompletedModifier` on the built-in route named
`"dictation"`. The executor at `index.js` @~4310300 breaks the chain on `{action:"handleExit"}`
and **no paste happens at all**. The extension gets `flow.runTerminalCommand` and a Node runtime,
so it can POST straight to the relay's HTTP server.

**Do NOT use `registerDictationRoute`.** That appends a route an LLM classifier picks between
("When in doubt, choose dictation"), so it would fire on some sentences and not others — which is
Victor's existing disease, reintroduced.

**Why it beats everything else:** it is not surviving the injection, it is the vendor's own
*hand me the text, do not paste* contract.

**The gate.** `feature-flags-cache.json` has `"extension-system": {"enabled": false}`. Flip it
locally: `"desktop-feature-flags-disk-cache": {"enabled": true}` is already set, hydration runs
before the PostHog fetch, and the host is constructed once in `launchApp` with no teardown. File
mode is 666, in his own home — **nothing in the bundle is touched, signature and notarisation
intact**.

⚠️ The file is **not** a flat map. Flip the nested path
`identified.flags["extension-system"].enabled`; an edit at the top level silently does nothing.

**Cheapest experiment (one afternoon, free, no vendor involvement):**
1. Back up `feature-flags-cache.json`. Flip the nested flag.
2. Quit Wispr **from its own menu**; relaunch **by full path**
   (`open "/Applications/Wispr Flow.app"` — never `open -a "Wispr Flow"`, which resolves to the
   nested helper).
3. `~/Library/Logs/Wispr Flow/` is **empty**, so verify by behaviour. Write
   `~/wispr-ext/relay/dist/index.js` exporting `main(flow)` that (a) POSTs a "loaded" ping at
   module load and (b) calls
   ```js
   modifyDictationRoute({
     routeName: "dictation",
     dictationCompletedModifier: async ({ formattedText }) => {
       /* POST formattedText to the relay */
       return { action: "handleExit" }
     },
   })
   ```
4. Register in `custom-paths.json` + `extensions-state.json`. Dictate one sentence into TextEdit.

Three outcomes, all informative: **nothing** (flag trick failed) / **load ping only** (hook wrong)
/ **text arrives and TextEdit stays empty** (done).

**What kills it:** hydration not taking, or an auto-update changing the API. Never ship it as a
dependency without the vendor flipping the flag — send one mail to support asking for
`extension-system` on for his account/uuid, in parallel, and don't block on it.

---

### ③ A liveness canary on the tap. **Mandatory companion to ①.**

A tap can report `CGEventTapIsEnabled() == true` and be functionally inert after a re-sign — and
`build-app.sh` re-signs Walkie Talkie (`Victor Addons Local Code Signing`, TeamIdentifier not set)
on **every** change. A green badge would read "up" exactly when the firewall is most likely dead,
and under an always-on fail-open drop that means a leaked sentence.

**Test:** rebuild, re-sign, relaunch with `open`, then check both `CGEventTapIsEnabled()` *and*
whether a real keystroke reaches the callback. If enabled is true and the callback is silent, the
canary is mandatory: at launch and after every wake, post a ⌘V-shaped event stamped with
`backButtonStamp` and assert the firewall tap saw it.

Skip measuring the `kCGEventTapDisabledByTimeout` deadline — it is folklore the code must handle
regardless.

---

### ④ `sandbox-exec -p '(version 1)(allow default)(deny hid-control)'` — the only real OS-level block.

WindowServer's `CGXSenderCanSynthesizeEvents` resolves to
`sandbox_check_by_audit_token("hid-control", …)`, and `hid-control` **is** a bound operation
(verified: `sandbox-exec -p '(version 1)(allow default)(deny hid-control)' /usr/bin/true` exits 0;
a bogus operation name fails). A surgical per-process-tree deny of event synthesis — the ⌘V is
dropped **at the window server**, nothing lands anywhere, and `flow.sqlite` still gets the row.
Composes with ①'s URL trigger, which is what makes it survivable, because the deny almost
certainly also kills Wispr's own hotkey tap.

**Cost, possibly fatal:** launching `/Applications/Wispr Flow.app` under `sandbox-exec` is the
launch-by-path the repo forbids — a second TCC identity, Terminal as the responsible process, the
microphone grant at risk (the 8 Sep 2026 double-row precedent). `sandbox-exec` is deprecated;
Electron helpers inherit the profile.

**Cheapest experiment, without touching Wispr:** build a throwaway `poke` that posts ⌘V into a
scratch TextEdit; confirm it works unsandboxed; run the identical binary under the deny; watch
`log stream --predicate 'process == "WindowServer"'` for *"Sender is prohibited from synthesizing
events"*. Separately, on a harmless mic app: **does a `sandbox-exec`'d signed `.app` keep its TCC
microphone grant?** That answer decides this branch outright.

---

### ⑤ The non-activating sink — only if ① and ② both fail.

`WisprSink` is an `NSWindow(styleMask: [.borderless])` plus **one**
`NSApp.activate(ignoringOtherApps: true)` at `WisprSink.swift:224`. That single line is what
Victor rejected. `RelayPanel` already ships `[.borderless, .nonactivatingPanel]` and he types into
it daily while the terminal stays frontmost; and `WisprNotes.swift:285-289` measured that Wispr's
own Scratchpad is a non-activating panel that becomes key without its app becoming frontmost.

**Test:** `SinkPanel: NSPanel`, drop the activate call, wrap-mode off, caret in TextEdit, dictate,
assert `GET /test/sink` shows the sentence with `route == "paste"` **and**
`NSWorkspace.frontmostApplication` (never System Events) still reads TextEdit. Keep
`armInjectionCapture(swallow: true)` on for the run so a lost race eats the ⌘V instead of putting
it in his document.

**Honest caveat:** this *hides* the focus theft rather than removing it — the app underneath is
left frontmost with no first responder, which is the disease that forced `armKeyRedirect` at
200 ms/character. For ~500 ms per sentence instead of the whole sentence.

---

### Composition

**① + ③ is the shipping plan.** ② supersedes ① if the flag flip works. ④ is the fallback if
Wispr moves to `CGEventPostToPid`. ⑤ is the fallback if ④'s TCC cost is fatal.

---

## 3. Settled — these cannot work. Do not re-derive them.

This section is as valuable as the shortlist; it belongs in *Never reintroduce* once confirmed.

**TCC / permissions**
- Revoke-per-dictation: `tccutil` has exactly one verb, `reset`, which deletes the row and causes
  a prompt. There is no grant primitive and never has been.
- Writing `TCC.db`: `tccd` holds `com.apple.rootless.storage.TCC` / `com.apple.private.tcc.manager`
  — Apple-only. Full Disk Access is not a substitute; `tccplus` needs SIP **and** AMFI off.
- Hand-installed `.mobileconfig` PPPC: Apple says "Requires a device management service to
  install", "Requires user approval". MDM check-in is seconds, against a 57 ms window.
- Clicking "Allow" programmatically: consent sheets accept only hardware-tagged events, by design.
  Driving the Settings toggle by AX fails the same way and takes seconds.
- Denying the *helper's* bundle id: **already done** since 2026-09-13 (`auth_value=0`) and
  injection kept working — TCC attributes to the responsible parent, `com.electron.wispr-flow`.
- `kTCCServicePostEvent` as a per-app "no synthetic keystrokes" knob: real, per-app, and
  unwritable behind the same wall. Wispr has no PostEvent row and posts anyway.
- There is **no** configuration where the AX write dies and the ⌘V survives.
- ⚠️ **Accessibility is also Wispr's *input* context** (`Beginning AX context collection`,
  `AppContextUpdate`, `cursor-integration`). Any revoke plan trades away the formatting quality it
  exists to buy — unpriced, and nobody measured it.

**AX writes**
- Vetoing another process's AX write: `AXObserverCallback` returns `void`; `grep -ci will` over
  `AXNotificationConstants.h` returns 0; the write is a mach message to the *target's* AX server
  with no third process on the path; Endpoint Security has no AX event class.
- **There is no AX dictation path at all** — see §1.
- Removing the focused element so Wispr gives up: its ladder **escalates** —
  `No valid element to focus, performing paste after app activation` → `as last resort`. Strictly
  worse: he loses the front **and** gets the paste.
- `AXManualAccessibility` teardown: Wispr sets it to *read* context; tearing it down degrades the
  transcript and blocks nothing.

**Pasteboard**
- `pasteboardChangedOwner:` never fires cross-process; there is no pasteboard notification or KVO
  on macOS; `changeCount` polling is the only detector.
- `NSPasteboardAccessBehavior` (15.4): read-only property, no setter, no defaults key, and an app
  isn't listed until it trips an alert. Gates *reads*, not writes.
- Blanking / poisoning the clipboard: probabilistic, races Wispr's own
  `Restoring pasteboard contents in `, destroys Victor's real clipboard, produces a user-visible
  Wispr failure.
- Reading the promise first so the relay "wins": a promise can be fulfilled by more than one
  reader. It blocks nothing.
- `setString("")` instead of `clearContents()`: a ⌘V of an empty string **deletes his selection**.

**Process surgery**
- `task_for_pid` / `task_suspend` / `DYLD_INSERT_LIBRARIES`: hardened runtime (`flags=0x10000`),
  entitlements are exactly `cs.allow-jit` + `device.audio-input`, no `get-task-allow`, no
  `disable-library-validation`, SIP on. **POSIX signals are the only process-level handle.**
- Reaching Wispr's own `CancelPaste`: the helper's only transport is **stdin** from the Electron
  parent (`stdin EOF, parent process is gone`). No XPC, no mach service, no socket. You would have
  to be the parent.
- SIGKILL on the helper every sentence: the relaunch ladder is `[0,1e3,2e3,4e3,8e3,16e3]` and the
  counter resets only after 60 s of life. Victor's cadence is ~26 s, so **sentence 6 hits
  `HelperPersistentFailure` and Wispr is bricked until restart.** Escape hatch only, ≤1 kill / 65 s.
- Re-signing or patching `app.asar`: breaks the stapled ticket and the updater, must be redone
  every auto-update, and violates *Wispr must keep working standalone*.

**Other**
- `EnableSecureEventInput`: blocks *interception*, not *posting* (TN2150). Worse, Wispr ships
  `SecureInputMonitor` and the string `Secure input is blocking keyboard shortcuts` — it detects
  the hold and reports it, it kills the **start** of the dictation, and it kills the relay's own
  taps. `kCGSSessionSecureInputPID` is also known to go stale until logout.
- IMK input source, Endpoint Security, DriverKit HID filters, `hidutil`, Karabiner: all sit below
  or beside the CGS event stream; a synthesized ⌘V never passes through them.
- Screen Time / ManagedSettings / MDM app restrictions / Focus modes /
  `CGSSetDenyWindowServerConnections`: wrong granularity, or process-local.
- Wispr's `appDenyList`: enterprise-only (`prefs.user.enterprise: null`,
  `teamDomainStatus: "forbidden"`), locally wiped at boot (`Clearing enterprise data`), checked
  **live** per paste, and matches the **frontmost** app — i.e. it only fires in the scenario Victor
  already rejected.

---

## 4. Open questions

1. **`CGEventPost` or `CGEventPostToPid`?** The helper imports both. Relay log lines prove the
   session tap sees Wispr's ⌘V, so it is `CGEventPost` *today*. Nobody has an automated assertion.
   **Add one line to the test suite** that greps relay.log for the
   `↓/↑ key 9 pid <wispr> flags 0x20100000` pair after a scripted dictation, and re-run after every
   Wispr update. Its **disappearance** — not a missing sentence — is the alarm.
2. **Does Wispr show a user-visible banner when its paste is dropped?** `FailedPasteNotification`,
   `PasteBlocked` and the `failed-paste-notification` flag all exist. Ten minutes to check, and it
   decides ①'s usability.
3. **Does Wispr retry or escalate after a swallowed paste?** Three paste sites with distinct
   strings; nobody has run 1, 2, 10 consecutive drops.
4. **Eager vs delayed clipboard.** Both `Using delayed clipboard rendering` and
   `Using original immediate clipboard setting` exist. Which branch runs, on what condition.
5. **Does a `sandbox-exec`'d signed `.app` keep its TCC grants?** Decides ④ outright. Testable on a
   harmless mic app.
6. **Cross-session event containment** (only if isolation is revisited): Apple's Fast User
   Switching doc says background sessions do not *receive* input; it says nothing about where an
   event *posted from* one is dispatched. Ten-minute test: fast-user-switch to a new `wispr`
   account, `osascript … keystroke "XXXX"`, switch back, look at TextEdit.
   ⚠️ The researchers' TCC-isolation claim was **wrong**: Accessibility / PostEvent / ListenEvent
   live in the **system** TCC.db, machine-wide; only Microphone and Camera are per-user. And plain
   Fast User Switching creates the session — the ssh+VNC bootstrap is not needed.
7. **The 57 ms figure is one sample through a 150 ms poll** (`historyTick = 0.15`). The
   `dismiss-before-paste` experiment therefore **never observed the event it concluded about**. If
   anyone re-opens in-flight cancellation, build the instrument first: kqueue on
   `flow.sqlite-wal` (measured 0.21 ms) — and handle `NOTE_DELETE/RENAME/REVOKE` plus re-open,
   because the WAL is recreated on checkpoint and on every Wispr quit, after which an `O_EVTONLY`
   fd watches a dead inode and **silently never fires again**.
8. **Quality cost of an AX-blind Wispr** — unmeasured, and it is the hidden price of every
   revoke-flavoured plan.

---

## 5. The honest alternative — do this first

**The premise may already be out of date, and Victor wrote the correction himself.**
`docs/journal.md:10976`, 2026-09-19:

> *"Wispr Flow nu mai e motorul meu de dictare default. Reține asta; o să trec la 11 Labs. Wispr
> Flow va rămâne motor de dictare atunci când vreau să dictez o idee, nu un prompt… M-a mulțumit
> calitatea, atât în română, cât și în engleză, și știe și să pună timpii pe cuvinte."*

That *"m-a mulțumit calitatea"* is about **ElevenLabs**. Supporting evidence:

- Wispr's own Canto page evaluates on **English only** (10 hours of English dictations, "did not
  lead either evaluation" on FLEURS / Common Voice) and publishes **no Romanian number**.
- ElevenLabs publishes **3.0% FLEURS / 5.5% Common Voice** on Romanian.
- Of **773** Romanian Wispr rows in the corpus, Victor edited **49**. The LLM formatting pass
  leaves **49.5% of Romanian sentences word-identical** after normalisation (median word-level
  change 0.0096) — on Romanian it is mostly punctuation.

**So the sliver actually in dispute is small:** "dictez o idee, nu un prompt", where what you'd be
buying is the **server-side formatting pass and the personal dictionary**, not the acoustic model.

**Test that, not raw ASR.** Take 20 of the 237 corpus clips that already carry Wispr's own
`teacher_text` and a WAV, run Scribe, pass the output through one Claude cleanup prompt, and print
three columns — `wispr / scribe raw / scribe+cleanup` — for Victor to read. ~$0.02 of Scribe plus
pennies of LLM. Touches nothing.

**What is lost by leaving Wispr out of the Engine menu:** the formatting pass and the dictionary on
idea-dictation, and nothing else. **Wispr-as-teacher is unaffected** — `helpers/teacher_label.py` +
`wispr_loopback.py` already run Wispr unattended at scale with the paste aimed at an allow-listed
sink, and have produced 2432 labelled clips for the fine-tune. That rig never had the injection
problem, because nobody is looking at the screen.

---

## 6. Recommended order of work

1. **The three-column quality test** (20 min, ~$0.02). It can close this whole file.
2. If Scribe+cleanup ties → leave Wispr out of the Engine menu, keep it as the teacher, and move
   §3 into *Never reintroduce*. **Stop here.**
3. If it does not tie → open question 2 (ten minutes: does a dropped paste show a banner?), then
   **① + ③** together. ① is three lines; ③ is not optional.
4. **②** in parallel as the better endgame — one afternoon, and it is the only option where Wispr
   itself agrees not to paste.

---

## 7. Provenance and caution

Claims in §1–§4 come from static analysis of the shipped `app.asar` and binary, from `codesign`
and `defaults` reads on this Mac, from Apple documentation, and from a handful of read-only shell
probes. **Items explicitly marked "verified" were executed; the rest were read, not run.** The
adversarial pass killed the majority of proposals — §3 is that graveyard and is the more reliable
half of this document.

Nothing in this research modified Wispr Flow, TCC state, or the relay.
