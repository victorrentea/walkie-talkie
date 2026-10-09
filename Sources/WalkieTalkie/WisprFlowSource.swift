import AppKit
import ApplicationServices
import AVFoundation
import Foundation

/// **Wispr Flow, driven and read as if it were this app's own microphone.**
///
/// Victor's decision, 2026-09-12: *Wispr Flow is the dictation source for
/// everything* — the caret, a spawned session, and the bound terminal that used
/// to be the local model's alone. Wispr is better at his accent, it is already
/// running, and it is what his hand reaches for; the relay's job is to stop
/// being a second recogniser and start being the thing that decides **where the
/// words go**.
///
/// Three problems stand between that decision and a `DictationSource`, and this
/// file is the three answers.
///
/// ## 1 · Starting it — a chord, not an API
///
/// Wispr has no API. It has shortcuts, and it writes them into its own
/// `~/Library/Application Support/Wispr Flow/config.json` under
/// `prefs.user.shortcuts`, keyed by keycodes joined with `+`. The relay posts
/// the hands-free one (`49+59+63` = fn ⌃ Space) through
/// `HotkeyTap.postWisprHandsFree` and the dismiss one (`53+59` = ⌃Escape)
/// through `postWisprCancel`. Both were already here and both are correct in
/// ways that took a day each to find — the Options+ settle, the wait for
/// Victor's own modifiers to come off the wire, the `hidSystemState` source,
/// the stamp that keeps this app's own tap from reading them as gestures.
///
/// **The chord is a toggle and its state is never tracked from here.** Wispr
/// misses one, or Victor ends a dictation from Wispr's own window, and a
/// counter in this process is wrong for the rest of the day. `WisprWatch`'s
/// CoreAudio edge is the only truth about whether the microphone is open.
///
/// ## 2 · Hearing it — a second microphone for the ring
///
/// `WisprWatch` answers one boolean. A beacon that breathes on his voice needs
/// a level, so the relay opens the input *alongside* Wispr and meters it. Two
/// clients on one input device is ordinary on macOS; Wispr's audio is not
/// touched.
///
/// **And since 2026-09-12 that session writes a WAV**, because it is the only
/// recording of a Wispr dictation that will ever exist on this disk. Retiring
/// the local model would otherwise have killed `~/.walkie-talkie/voice-corpus/`
/// — *"the one thing here that cannot be regenerated"* — on the day the last
/// local dictation was spoken. The label beside it is Wispr's own transcript.
///
/// ## 3 · Reading it — the delivery, intercepted
///
/// Wispr's entire output interface is *it types the sentence into whatever has
/// focus*. There is no clipboard-only mode (the whole 45 KB config was read on
/// 2026-09-12: `polishAutoPaste`, `instructPasteOnEmptyContext`,
/// `focusModeBlockedApps` and three notification strings, and nothing that
/// turns the paste off), and **its database is not an option** — the 2026-08-29
/// rule stands and Victor restated it when he asked for this.
///
/// What is left is the delivery itself. Wispr writes the transcript to the
/// pasteboard and presses ⌘V, and this app's event tap is head-inserted on the
/// session tap, so it sees that ⌘V *before the front app does*. Under
/// `wrapWispr` (default on) the relay **swallows it** and inserts the words
/// itself — into the bound agent through the held prompt, or at the caret
/// through `pasteText`, which is the same paste Wispr was about to make. With
/// the flag off nothing is taken: Wispr pastes as it always did and the relay
/// only watches, which is what every build before today did.
///
/// The swallow is narrow on purpose: the key has to be **V with ⌘**, from a
/// **process whose name says Wispr**, inside the window between the microphone
/// closing and the deadline. Victor's own ⌘V carries pid 0 and can never match.
final class WisprFlowSource: DictationSource {
    /// What `Message.engine` says for these words — and what tells the envelope
    /// they came with no word timings (`Message.wordsUntimed`).
    static let engineLabel = "Wispr Flow"

    let name = "Wispr Flow"

    /// **The whole of the wrap, in one flag.** On: the relay takes Wispr's
    /// paste and delivers the words itself, so Wispr looks exactly like the
    /// local recogniser to everything downstream. Off: Wispr inserts its own
    /// text wherever the focus is and the relay only draws the ring — the
    /// behaviour of every build before 2026-09-12, kept because it is the one
    /// thing to fall back to if a Wispr update changes how it delivers.
    var wrapWispr = true {
        didSet {
            guard wrapWispr != oldValue else { return }
            Log.info("wispr wrap \(wrapWispr ? "on" : "off") — \(wrapMode.rawValue): \(wrapReason)")
        }
    }

    /// **How the relay takes Wispr's words**, and the three answers are three
    /// different relationships with another app (Victor's decisions, 2026-09-13).
    ///
    /// | mode | Wispr is told | the words come from | what it costs |
    /// |---|---|---|---|
    /// | `scratchpad` | *Open Scratchpad*, **held** for the sentence | its own `Notes` row | nothing — no insertion, no focus moved |
    /// | `sink` | the hands-free chord | the relay's own key window | the keyboard, for a moment, during every dictation |
    /// | `off` | the hands-free chord | nobody — Wispr inserts where the focus is | the wrap |
    ///
    /// The order matters and so does why the other two were rejected. **The sink
    /// works** — measured 3/3 on 2026-09-13: Wispr picks its insertion target at
    /// the *end*, so a window taking the keyboard 1–5 ms after the stop chord
    /// receives the text. Victor rejected it as the primary path anyway, because
    /// it takes the focus off a man who may be clicking or typing at that
    /// instant, and a dictation helper whose ordinary behaviour is to interrupt
    /// him is not one he can leave running. **Revoking Wispr's Accessibility
    /// grant** also works and was rejected for its own reason: Wispr has to go on
    /// being usable on its own, and an app this one has quietly disarmed is not.
    ///
    /// The Scratchpad costs nothing because it is Wispr's own answer to *dictate
    /// somewhere that is not the caret*. Measured: F18 held 20 s, the text in
    /// `Notes`, the victim document untouched, **focus never moved**, no ⌘V
    /// posted, e2e 432 ms.
    enum WrapMode: String {
        case scratchpad
        case sink
        case off
    }

    /// `WT_WRAP_MODE=sink` for one run, and `POST /test/wrap-mode` for the loop.
    /// Nil means *decide from the tick and from Wispr's own configuration*.
    private var modeOverride: WrapMode? =
        ProcessInfo.processInfo.environment["WT_WRAP_MODE"].flatMap { WrapMode(rawValue: $0.lowercased()) }

    /// The mode in force this instant, and a sentence saying how it got there —
    /// both in `/engine` and `GET /test/state`, because a wrap that silently
    /// fell back to the emergency path is exactly the thing nobody notices.
    var wrapMode: WrapMode {
        guard wrapWispr else { return .off }
        if let modeOverride { return modeOverride }
        // **With the firewall up there is nothing to wrap** (2026-09-22): the
        // tap drops Wispr's ⌘V whatever the mode, and the words come from the
        // `History` row. No window, no sink, no held chord — `.off` here means
        // *Wispr is asked plainly and never gets to paste*, which is the shape
        // the Scratchpad and the sink were both approximations of.
        if hotkeys.wisprFirewallOn { return .off }
        guard !scratchpadBroken else { return .sink }
        return HotkeyTap.scratchpadIsConfigured ? .scratchpad : .sink
    }

    var wrapReason: String {
        guard wrapWispr else { return "the wrap is off (WT_WRAP_WISPR / POST /test/wrap-mode — there is no menu row since 2026-09-14) — Wispr inserts where the focus is and the relay only draws the ring" }
        if let modeOverride {
            return "forced to \(modeOverride.rawValue) by WT_WRAP_MODE / POST /test/wrap-mode"
        }
        if hotkeys.wisprFirewallOn {
            return "the firewall drops Wispr's ⌘V at the tap and the History row is the delivery — no window, no sink"
        }
        if scratchpadBroken {
            return "the Scratchpad window would not close, and a held chord writes no note while it is open — the sink until it does"
        }
        return HotkeyTap.scratchpadIsConfigured
            ? "Wispr has an open_scratchpad shortcut — the relay holds it and reads the note"
            : "Wispr has no open_scratchpad shortcut — falling back to the sink, which takes the keyboard for a moment at every stop"
    }

    /// `POST /test/wrap-mode {"mode": "scratchpad"|"sink"|"off"|"auto"}`.
    func setWrapMode(_ raw: String) -> [String: Any] {
        if raw.lowercased() == "auto" {
            modeOverride = nil
            scratchpadBroken = false
            wrapWispr = true
        } else if let mode = WrapMode(rawValue: raw.lowercased()) {
            if mode == .off { wrapWispr = false }
            else { wrapWispr = true; modeOverride = mode }
            if mode != .off { modeOverride = mode }
        } else {
            return ["ok": false, "error": "unknown mode \(raw)", "modes": ["scratchpad", "sink", "off", "auto"]]
        }
        Log.info("wispr wrap mode → \(wrapMode.rawValue): \(wrapReason)")
        return ["wrapMode": wrapMode.rawValue, "why": wrapReason]
    }

    /// **Whether this dictation is the relay's to take.**
    ///
    /// Victor's line, 2026-09-13: a dictation *he* starts — his own keyboard
    /// chord, or 🔽→ which posts Wispr's chord raw — is Wispr's. The relay draws
    /// the ring for it because the ring is *a microphone is open* and that is
    /// true, and it does nothing else: no swallow, no Scratchpad, no routing.
    /// Taking over a tool he reached for directly is a different thing from
    /// wrapping a dictation this app asked for itself.
    private(set) var relayStarted = false
    /// **Walkie's sentence, whoever's chord**: `relayStarted` or the raw chord
    /// 🔽 → posts (`walkiePosted`). The relay delivers both, so both owe the
    /// countdown a WAV — see `closedTakeAudio`.
    private var walkieOwned = false

    /// **The mode this dictation opened in**, latched at the gesture. `wrapMode`
    /// can change under a sentence — the tick is a menu row and the loop posts
    /// `/test/wrap-mode` — and a dictation started by holding a key must be
    /// ended by releasing *that* key, whatever the menu says by then.
    private(set) var startedMode: WrapMode = .off

    /// **The app he was looking at when he asked**, remembered at the chord — the
    /// last moment it is unambiguous, because the window that will take the
    /// keyboard never becomes frontmost. It travels out on
    /// `DictationResult.focusPid` so the caret paste can be *addressed* instead
    /// of aimed at whatever holds the focus, which is what lets the delivery fire
    /// at `formatted` rather than waiting for Wispr's window to close.
    ///
    /// **Remembered in every mode, not only the caret's** (2026-09-14). It was
    /// filled inside `guardTheKeyboard`, behind a guard that returned early when
    /// the frontmost application was the relay itself — and a spawn dictation
    /// puts the relay's own folder menu in front at exactly that moment, so
    /// `wrap-spawn` and `wrap-bound` armed no redirect at all and lost every
    /// probe keystroke. The destination of the sentence has nothing to do with
    /// whose keyboard it is.
    private(set) var focusPid: pid_t?

    /// **The last application that was frontmost and was not this one.**
    ///
    /// The fallback for the moment the relay's own menu or panel is in front
    /// when the chord goes out. Kept by subscription rather than asked for,
    /// because by the time it is wanted the answer has already been spoiled.
    private var lastFrontPid: pid_t = 0

    /// **The app that was in front before the one that is in front now.**
    ///
    /// Whose front Wispr took is a different question from whose front it was at
    /// the chord: he may have clicked into another window while he was talking,
    /// and putting him back into the one he left would be a second theft dressed
    /// as a fix. This is the first answer `putTheFrontBack` tries; `focusPid` is
    /// the fallback.
    private var frontBeforeLast: pid_t = 0

    /// When the front was last given back, newest last — a rate limit and
    /// nothing more. Wispr and the relay each activating in answer to the other
    /// is a fight the man watching loses either way, so after
    /// `frontHandbackLimit` inside `frontHandbackWindow` it stops.
    private var frontHandbacks: [Date] = []
    private static let frontHandbackLimit = 5
    private static let frontHandbackWindow: TimeInterval = 60

    /// For `GET /test/state` — the flag above, which is not `startedMode`.
    var isIntercepting: Bool { intercepting }

    /// **The wrap's apparatus is armed for this sentence** — latched at the
    /// gesture, exactly like `startedMode`, and deliberately a *different*
    /// question from it.
    ///
    /// `startedMode` says **how the chord was posted**, so it says what `stop()`
    /// has to undo: a dictation opened by holding a key is ended by releasing
    /// that key. This says **whether the relay delivers the words**. They come
    /// apart on `POST /test/wispr-handsfree`, which posts the hands-free chord —
    /// so its `startedMode` is `off`, no key is held and no sink is taken — while
    /// the wrap is on and the ⌘V is still the relay's to swallow. Folding the two
    /// into one flag broke that route the first time it was tried.
    private var intercepting = false


    // MARK: - Events

    var didMaybeBegin: ((String) -> Void)?
    var didBegin: (() -> Void)?
    var didStopListening: (() -> Void)?
    /// **Wispr named the microphone this sentence is going through** — its
    /// `History.micDevice`, the moment it is non-empty and whenever it changes.
    /// Main thread, like the row poll it comes out of.
    var micNamed: ((String) -> Void)?
    /// **Wispr's microphone is open for this sentence — the first time** (Q20,
    /// 2026-09-28): until then the chip says `Opening Wispr Flow...`, because a
    /// cold Wispr is deaf for 0.3–6 s after the chord (W11).
    var micOpened: (() -> Void)?
    /// **His own Wispr sentence, whose ⌘V the firewall dropped while the relay's
    /// row was in flight** (Q19, 2026-09-28) — the words, for the caret.
    var foreignSentence: ((String) -> Void)?
    /// **Wispr is out of this sentence and the relay's own recording carries it
    /// on** (batch 4, 2026-09-29) — the reason, for the chip. See `holdOwnTake`.
    var onOwnTake: ((String) -> Void)?
    /// **Why the relay's own recording is carrying this sentence alone** — nil
    /// while Wispr is in it. Set by `holdOwnTake` (Wispr never answered the
    /// chord, F1; Wispr quit mid-sentence, item 3), cleared by `closeListening`
    /// at HIS stop. While it stands `isRecording` is true (a microphone — the
    /// relay's — is open), no chord is posted to Wispr, and Wispr's microphone
    /// edges are not this sentence's.
    private(set) var ownTakeOnly: String?
    private var ownTakeSince: CFAbsoluteTime = 0
    /// Whether this sentence ever saw Wispr's microphone open (poll or edge).
    /// A row with no microphone behind it is not a recording (W2).
    private(set) var micSeen = false
    /// The relay's own recording's voiced seconds, read at its close (Q14).
    private var recordingVoiced: TimeInterval = 0
    /// What `micNamed` last said for the adopted row, so a 100 ms poll says it once.
    private var namedMic = ""
    var didTranscribe: ((DictationResult) -> Void)?
    var didEnd: ((DictationEnd) -> Void)?

    /// **Wispr's microphone is open — and this is the one event that is reported
    /// whether or not this source is the engine.**
    ///
    /// The five events above are `DictationSource`'s, and they only reach the app
    /// when this object *is* `source`: with the Engine on the local model nobody
    /// wires them, and a dictation Victor starts himself with ⌘⌥ then happens
    /// with the relay silent about it — which is what he found on 2026-09-18,
    /// music playing over a push-to-talk sentence that the log had already named
    /// (`⚡ right ⌘⌥ — Wispr push-to-talk`).
    ///
    /// It is deliberately narrower than `didBegin`: a dictation the relay did not
    /// ask for is still Wispr's — no screenshot, no ⌘C probe, no route — and this
    /// says only *he is talking to a microphone right now*, which is the whole of
    /// what the music has ever needed (`MusicBridge`). Set once at launch, not in
    /// `wireDictationSource`, because it does not belong to whichever source is
    /// wired up.
    ///
    /// **`WisprState.listening` and not `WisprWatch`**, for the reason the machine
    /// exists: the CoreAudio edge is 0–6 s late and produced no edge at all in
    /// five of five runs on 2026-09-13, and with the Engine on the local model
    /// this source's own `watch` is never even started (`prepare()` is not
    /// called), so the poll sees nothing either. The phase joins those two with
    /// Wispr's `History` row, which is written at the gesture and is the signal
    /// that actually fires — measured 182 ms on 2026-09-18.
    var hearingChanged: ((Bool) -> Void)?

    // MARK: - State

    private(set) var isRecording = false

    /// **The measured state machine** — see `WisprState`. Everything below feeds
    /// it and nothing below asks it a question it cannot answer from its own
    /// three inputs; `phase` is the one thing the rest of the app reads, through
    /// `DictationSource`.
    let state = WisprState()
    /// `.listening` while the relay's own recording carries the sentence
    /// (`ownTakeOnly`): the machine is at rest (Wispr is out of it), the
    /// sentence is not.
    var phase: DictationPhase { ownTakeOnly != nil ? .listening : state.phase }

    /// **The 100 ms pull that replaced a push nobody could trust.**
    ///
    /// `WisprWatch`'s notification is kept (it can be earlier than a tick, and
    /// the lag between the two is the number `WisprState.lags` exists to take),
    /// but it is no longer the only witness: measured 2026-09-13 it is 0–6 s late
    /// and, with Wispr pinned to the Loopback device `🎓 TO Wispr`, it produced
    /// **no edge at all** in five successful runs. Running only between the chord
    /// and the words (`WisprState.wantsPoll`), because a permanent CoreAudio poll
    /// is the thing this app spent 2026-09-11 arguing itself out of.
    private var inputPoll: Timer?
    private var lastPollSaw = false
    /// `POST /test/wispr {"on": …, "via": "poll"}` (batch 5): what the 100 ms poll
    /// reads instead of CoreAudio — a desk has no Wispr microphone to watch, and
    /// the real kill's order is the poll's close first, the exit after. Cleared
    /// at the next relay chord.
    private var testPollSays: Bool?
    private static let pollTick: TimeInterval = 0.1

    /// Wispr Flow is running at all. Asked of the process list rather than
    /// remembered: it is quit and relaunched like any other app.
    /// **W19 (2026-09-28): the main executable, anchored** — a bundle-id prefix
    /// also matches the nested Accessibility helper, so a helper-only Wispr
    /// passed and the sentence died 300 ms later as *Wispr Flow quit*.
    var isReady: Bool { Self.wisprMainIsRunning }

    /// **Yes** — Wispr's microphone is pinned to the Loopback device
    /// `🎓 TO Wispr`, whose output side any app can speak into, and measured
    /// 2026-09-14 the marker arrives in `asrText` and survives the formatting
    /// pass into `formattedText`. See `ShotMarker`.
    var acceptsAudioMarkers: Bool { true }

    /// **Two mechanisms, and which one is in force is whether this app owns the
    /// path into Wispr.**
    ///
    /// With the bridge up the marker is written into the stream Wispr is being
    /// fed (`MicRecorder.insert`), so it arrives **between** two of his words —
    /// deterministic, nothing to mask it, no gap to wait for. Without it, the
    /// marker can only be *played into* the Loopback device and is therefore
    /// summed with his voice, which measured 2026-09-14 means it vanishes over
    /// continuous speech — and it is not a level that can be raised, since it is
    /// already the louder of the two. So that path waits for a gap and accepts
    /// the ceiling. → `AudioBridge`, `ShotMarker.maskCeiling`
    func mark(_ kind: ShotMarker.Kind, index: Int) {
        if bridge.isRunning, let pcm = ShotMarker.pcm(kind, index: index, in: MicRecorder.fileFormat) {
            // **Into his next pause, never over a word** (2026-09-30). Spliced at
            // the next buffer, as this used to be, a marker lands mid-phrase:
            // measured in `evals/wispr-markers/`, that is where Wispr drops them
            // (16/20 mid-phrase against 19/20 in a pause, formatted) and where the
            // splice cuts his word in two (`trei- Screenshot eight. Sute de mii`).
            let said = ShotMarker.Said(kind: kind, index: index)
            markerLock.lock()
            waitingMarkers.append((said, pcm, CFAbsoluteTimeGetCurrent()))
            markerLock.unlock()
            meterQueue.async { [weak self] in self?.spliceWhenQuiet() }
            return
        }
        ShotMarker.play(kind, index: index,
                        whenQuiet: { [weak self] in
                            (self?.meter.quietSeconds ?? 0) >= ShotMarker.gapNeeded
                        })
    }

    /// **Splice every waiting marker once he pauses** — polled on `meterQueue`
    /// every `markerGapTick` while one waits. The pause is the recorder's own
    /// `quietSeconds` (his voice only: a spliced marker is never metered), and
    /// `markerPause` of it.
    private func spliceWhenQuiet() {
        markerLock.lock()
        let waiting = !waitingMarkers.isEmpty
        markerLock.unlock()
        guard waiting, meter.isRecording else { return }   // closed: the stop took them
        guard meter.quietSeconds >= Self.markerPause else {
            meterQueue.asyncAfter(deadline: .now() + Self.markerGapTick) { [weak self] in self?.spliceWhenQuiet() }
            return
        }
        markerLock.lock()
        let batch = waitingMarkers
        waitingMarkers = []
        said += batch.map(\.said)
        markerLock.unlock()
        let level = Self.voiceLevel(meter.meterHops)
        for (n, m) in batch.enumerated() {
            // Two presses in one breath: a quarter second between them, as the
            // back-to-back pairs were measured (20/20).
            if n > 0, let gap = Self.silence(0.25) { bridge.noteMarker(gap); meter.insert(gap) }
            let clip = Self.levelled(m.pcm, to: level)
            bridge.noteMarker(clip)
            meter.insert(clip)
            Log.info(String(format: "📣 marker %@ %d spliced into Wispr's stream in his pause, %.0f ms after the press",
                            m.said.kind.rawValue, m.said.index, (CFAbsoluteTimeGetCurrent() - m.pressedAt) * 1000))
        }
        // One sequence, two destinations (`MicRecorder.onBuffer`): the same
        // buffer reaches Wispr's ear *and* the WAV this app is filing, so the
        // corpus keeps the words that name it.
        markersInAudio = true
    }

    /// **The stop's share: whatever is still waiting goes to Wispr now**, behind
    /// the last of him, straight into the bridge (the recorder is about to be
    /// cut off from it). Called just before `closeInput`. Not in the WAV — the
    /// corpus gets the cleaned words for a take like that (`markersInAudio`).
    private func flushWaitingMarkers() {
        markerLock.lock()
        let batch = waitingMarkers
        waitingMarkers = []
        said += batch.map(\.said)
        markerLock.unlock()
        guard !batch.isEmpty else { return }
        let level = Self.voiceLevel(meter.meterHops)
        for (n, m) in batch.enumerated() {
            if n > 0, let gap = Self.silence(0.25) { bridge.noteMarker(gap); bridge.schedule(gap) }
            let clip = Self.levelled(m.pcm, to: level)
            bridge.noteMarker(clip)
            bridge.schedule(clip)
            Log.info(String(format: "📣 marker %@ %d never met a pause — handed to Wispr at the stop, %.0f ms after the press",
                            m.said.kind.rawValue, m.said.index, (CFAbsoluteTimeGetCurrent() - m.pressedAt) * 1000))
        }
    }

    private static let markerGapTick: TimeInterval = 0.04
    /// **A pause, not the breath between two words** — 0.3 s of quiet
    /// (2026-09-30, the first dry run in `wt-lab`). At `ShotMarker.gapNeeded`
    /// (0.12 s, sized for the played path's onset) the splice fired between
    /// *bug number* and *forty*: one marker vanished and Wispr merged the other
    /// into `screenshot 240`. The eval's pauses were ≥ 0.24 s, spliced mid-way.
    private static let markerPause: TimeInterval = 0.3

    /// **His voice's level in this take**: the median RMS of the voiced hops of
    /// the last ~13 s (`MicRecorder.meterHops`, int16 units). Nil before he has
    /// said enough to measure.
    private static func voiceLevel(_ hops: [MeterHop]) -> Float? {
        let voiced = hops.suffix(200).filter(\.voiced).map(\.rms).sorted()
        guard voiced.count >= 5 else { return nil }
        return voiced[voiced.count / 2]
    }

    /// **The marker at his voice's level** (2026-09-30, the overnight suite).
    /// His recorded clips sit at ~−33 dB; a take louder than that heard the
    /// marker as a quiet second voice and two runs lost markers that had been
    /// spliced. The eval matched each marker to the voice around it (active RMS)
    /// and so does this: the louder half of its 64 ms hops against `level`,
    /// clamped to 0.25…8×. A copy — the cached clip is shared.
    private static func levelled(_ pcm: AVAudioPCMBuffer, to level: Float?) -> AVAudioPCMBuffer {
        guard let level, level > 0, let src = pcm.int16ChannelData?[0], pcm.frameLength > 0,
              let out = AVAudioPCMBuffer(pcmFormat: pcm.format, frameCapacity: pcm.frameLength),
              let dst = out.int16ChannelData?[0] else { return pcm }
        let n = Int(pcm.frameLength), hop = 1024
        var rms: [Float] = []
        var i = 0
        while i + hop <= n {
            var sum: Float = 0
            for k in i..<(i + hop) { let v = Float(src[k]); sum += v * v }
            rms.append((sum / Float(hop)).squareRoot())
            i += hop
        }
        guard !rms.isEmpty else { return pcm }
        let loud = rms.sorted().suffix(max(1, rms.count / 2))
        let active = (loud.map { $0 * $0 }.reduce(0, +) / Float(loud.count)).squareRoot()
        guard active > 0 else { return pcm }
        let gain = min(8, max(0.25, level / active))
        for k in 0..<n { dst[k] = Int16(max(-32767, min(32767, Float(src[k]) * gain))) }
        out.frameLength = pcm.frameLength
        return out
    }

    /// Zeros in the recorder's format.
    private static func silence(_ seconds: TimeInterval) -> AVAudioPCMBuffer? {
        let format = MicRecorder.fileFormat
        let frames = AVAudioFrameCount(seconds * format.sampleRate)
        guard let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        b.frameLength = frames
        if let d = b.int16ChannelData {
            for c in 0..<Int(format.channelCount) { d[c].update(repeating: 0, count: Int(frames)) }
        }
        return b
    }

    /// What this take really carried, for the result.
    private var saidThisTake: [ShotMarker.Said] {
        markerLock.lock(); defer { markerLock.unlock() }
        return said
    }

    /// **How long Wispr still has to listen for audio this app has not handed
    /// over yet.** The stop chord waits this out, or Wispr ends the sentence on a
    /// tail still sitting in the player's queue. Zero with the bridge down.
    ///
    /// **No ceiling since 2026-09-30** (was 8 s, 3 before From Walkie). The
    /// catch-up speed is capped at what Wispr can still transcribe
    /// (`BridgePacer.maxRate`), so a late start leaves seconds of him queued at
    /// the stop, and every one of them is his sentence — Victor: *"îmi asum
    /// această procesare întârziată"*. The only thing that ends the wait early is
    /// a queue that stops moving (`drainStall`): a stuck player must not leave
    /// the microphone open.
    var bridgeDrainSeconds: TimeInterval { bridge.queuedSeconds }
    /// A queue that has not shrunk for this long is a stuck player, not a backlog.
    private static let drainStall: TimeInterval = 2
    /// Main-only: the stop's drain wait — the queue last seen and when it last shrank.
    private var drainSeen: TimeInterval = 0
    private var drainMovedAt: CFAbsoluteTime = 0

    let meter = MicRecorder()

    /// **His voice, carried to Wispr by this app** — through From Walkie, on
    /// by default since 2026-09-29 (`AudioBridge`). While it is up, a shot marker
    /// is *spliced* into the stream instead of played over it.
    private let bridge = AudioBridge()

    /// Whether this sentence's WAV has a marker spliced into it — true only on
    /// the bridged path, where `mark` splices rather than plays. Reset with the
    /// meter, because it describes one recording.
    private var markersInAudio = false

    /// **Markers pressed and not yet spliced** — waiting for his next pause
    /// (2026-09-30). Victor: *"I'd prefer waiting the next pause to insert the
    /// marker to missing the marker."* No ceiling while the take is open; the
    /// stop hands whatever is still waiting straight to the bridge. Under
    /// `markerLock`, with `said` — read from the main thread at the stop and at
    /// delivery, written on `meterQueue`.
    private var waitingMarkers: [(said: ShotMarker.Said, pcm: AVAudioPCMBuffer, pressedAt: CFAbsoluteTime)] = []
    /// What this take's stream really carried, in splice order — the list
    /// `ShotMarker.resolveStrict` holds the transcript to. Reset with the meter.
    private var said: [ShotMarker.Said] = []
    private let markerLock = NSLock()

    private let watch = WisprWatch()
    private let hotkeys: HotkeyTap
    /// Where the meter is opened and closed, off the main thread — see
    /// `AppDelegate.wisprMeterQueue`, whose whole argument moved here with it:
    /// `MicRecorder.start(to:)` is a synchronous device open and it was being
    /// run on the edge, in front of the ring.
    private let meterQueue = DispatchQueue(label: "ro.victorrentea.wispr-relay.wispr-meter")
    /// Touched only on `meterQueue`, so the stop queued at the closing edge can
    /// never be overtaken by the read that wants its result.
    private var recording: (url: URL, duration: TimeInterval)?
    /// **The same take, readable on main** (2026-09-29) — published by
    /// `stopMeter(keep: true)`, cleared by the next `startMeter`, for the
    /// speculative local decode (`closedTakeAudio`). Only ever read: the take is
    /// `recording`'s, and `endWithRecording` still ends the sentence on it.
    private var keptTake: TakeAudio?

    /// A gesture was seen and no microphone has confirmed it yet.
    private var speculative = false
    private var speculativeDrop: DispatchWorkItem?
    /// When the gesture was seen, so the confirming edge can say how long the
    /// guess had to wait — the number that settled `speculativeGrace`.
    private var gestureAt: CFAbsoluteTime = 0
    /// **How long a guess is allowed to stand unconfirmed — 12 s, and the number
    /// is measured (2026-09-12).**
    ///
    /// It was 1.5 s, fitted to the five `mic edge confirms the ring N ms after
    /// the hotkey` lines in `relay.log`: 324, 478, 528, 634, 674 ms. Every one of
    /// those is a *warm* Wispr. Victor's dictations on the evening of 09-12
    /// measured **5.0 s and 6.0 s** from the chord to `wispr flow opened the
    /// microphone`, and the whole of what he saw was the bug: the ring came up
    /// on his keystroke, **shrank away** two seconds later when the grace ran
    /// out, and came back four seconds after that with the screenshot bubble and
    /// the chip. *"the lightning starts fast, but only later the yellow bubble
    /// appears, and there is a pause in which the ring disappears"*.
    ///
    /// So: the worst measured open × 2, never under three seconds. A retraction
    /// is for a chord Wispr **ignored** — it was not running, the shortcut had
    /// been changed — and that is rare enough to be worth twelve seconds of
    /// patience. A beacon that flickers is worse than one that is briefly wrong,
    /// which is the opposite of the trade the 1.5 s was making.
    private static let speculativeGrace: TimeInterval = 12

    /// The microphone closed and the words have not arrived.
    ///
    /// `private(set)` since 2026-09-13 so `GET /test/state` can say whether the
    /// swallow window is armed — the 2.5 s Word dictation failed precisely
    /// because it never was, and nothing outside this file could see that.
    private(set) var capturing = false
    /// When the swallow window was armed — the **start** chord since 2026-09-13,
    /// not the microphone's close.
    private var armedAt: CFAbsoluteTime = 0
    private var captureFrom: CFAbsoluteTime = 0
    /// How long the sentence being transcribed was spoken for — the audio
    /// `DecodeRate` files Wispr's round trip against. 0 once filed, and for a
    /// cancel, so nothing is filed twice or for a sentence nobody wanted.
    private var spokenFor: CFAbsoluteTime = 0
    private var captureDeadline: DispatchWorkItem?
    private var clipboardWatch: Timer?
    private var clipboardAt = 0
    /// **What was on the pasteboard before the dictation, and it is the fix for
    /// three sentences that were never spoken** (2026-09-13).
    ///
    /// Wispr writes the transcript to the pasteboard, presses ⌘V, and **puts the
    /// previous contents back**. While the capture was armed at the microphone's
    /// close — 0–6 s late — the baseline `changeCount` was taken *after* Wispr's
    /// own write, so the only move the relay ever saw was the restore, and it
    /// delivered the restored clipboard as the transcript. Measured in the
    /// corpus: three runs on the evening of 09-13 filed 166 characters of a Word
    /// rental contract (`Semnături, PROPRIETAR CHIRIAȘ …`) as Victor's dictation,
    /// against audio of him saying *"Commit and push the fix"*.
    ///
    /// Arming at the start chord fixes the ordering; this is the belt beside it,
    /// and it is worth keeping for the day Wispr changes the order again: a
    /// pasteboard whose contents are **what they were before he started talking**
    /// cannot be this sentence, whatever the change count says.
    /// **The one place this app reads the pasteboard's text**, and it is
    /// guarded because the delivery path runs exactly when Wispr — and, in a
    /// test, the harness — are rewriting it.
    ///
    /// Three cheap defences, none of which can catch a fault but all of which
    /// shrink the window it needs:
    ///
    /// - **Ask `types` first.** It is the question that says whether there is a
    ///   string at all, and `stringForType:` on a pasteboard without one still
    ///   walks the type cache — which is where the crash was.
    /// - **Sandwich it in `changeCount`.** A pasteboard that moved while it was
    ///   being read may hand back a mixture of two owners' contents; the caller
    ///   is better off with nothing than with half a sentence.
    /// - **Read once.** Every caller on the delivery path comes here, so a
    ///   delivery costs one read rather than one per branch that wondered.
    static func pasteboardString() -> String? {
        Clipboard.with { board in
            guard board.types?.contains(.string) == true else { return nil }
            let before = board.changeCount
            let text = board.string(forType: .string)
            guard board.changeCount == before else { return nil }
            return text
        }
    }

    /// The string as it stood the instant the change was first seen — read then
    /// rather than 250 ms later, because the restore lands inside that gap.
    private var clipboardMoved: String?
    /// Whether the fallback chord has been posted for this sentence, so a
    /// pasteboard that never moves cannot make the relay type ⌘⌃C twice.
    private var askedForCopy = false
    /// **The longest the relay waits for words that may never come — 30 s, and
    /// it was 6 and that cost a sentence (2026-09-12).**
    ///
    /// Wispr's round trip was measured at avg 2.6 s over 71 dictations, min
    /// 0.27, max **22.8** — the tail is a cold network and a long clip. Six
    /// seconds was fitted to the average and it let go of an 81-second dictation
    /// on the evening it shipped: the ⌘V arrived after the window had closed, so
    /// the relay never saw it and Wispr pasted into whatever was in front.
    /// Measured the same evening: **5.9 s** on one sentence, a second one past
    /// six.
    ///
    /// This is the wrap's own window and it is deliberately far longer than the
    /// ring's: the ring is a thing Victor looks at and 30 s of it would be a lie,
    /// where a capture window is a thing nobody sees and costs one armed flag.
    private static let captureTimeout: TimeInterval = 30
    /// How long the fallback chord is given, once it has been posted.
    private static let copyGrace: TimeInterval = 3

    /// **The `copy_last_text` fallback is off by default, and it is off for a
    /// reason that showed up the hour it was written (2026-09-12).**
    ///
    /// ⌘⌃C asks Wispr for *the last text it produced* — not *the text from the
    /// sentence that just ended*. If this sentence produced nothing, the chord
    /// hands back the **previous** one, and the relay would deliver a paragraph
    /// Victor spoke five minutes ago into an agent as though he had just said it.
    /// A dictation that goes missing is a sentence he repeats; a dictation that
    /// silently becomes an older one is a sentence he cannot trust.
    ///
    /// Measured on the first run: the chord went out and `NSPasteboard
    /// .changeCount` never moved, so it does not even buy the case it was
    /// written for. `WT_WISPR_COPY_FALLBACK=1` turns it back on for whoever
    /// wants to work on it; the probe (2026-09-12) showed the ⌘V path is the
    /// real one and this was only ever the insurance.
    private static let copyFallbackEnabled =
        ProcessInfo.processInfo.environment["WT_WISPR_COPY_FALLBACK"] == "1"

    private var cancelling = false
    /// **The close `cancelling` drives is ⌘⌃X's, not a cancel** (2026-09-28):
    /// Wispr is dismissed the same way, but the relay's own recording goes to
    /// the local model instead of to Recover.
    private var handingToLocal = false

    /// **The sentence is cancelled but Wispr has not finished with it.**
    ///
    /// Set by a cancel that lands during the settle. Everything stays armed —
    /// the swallow, the row poll, the deadline — and every route that would
    /// have delivered drops the words instead. It is cleared by `endCapture`,
    /// which runs when Wispr's row goes terminal, when its ⌘V is seen, or at
    /// `captureTimeout`; the Scratchpad window goes with it.
    private var discardOnArrival = false

    /// **When the ⌃Escape dismiss went out for a cancel during the settle.**
    /// The clock the early close is measured from — see `armDiscardClose`.
    private var dismissedAt: CFAbsoluteTime = 0
    private static let discardCloseKey = "discard-close"

    /// **The row of a cancelled sentence whose capture a new gesture superseded**
    /// (2026-09-14).
    ///
    /// A cancel during the settle keeps everything armed until Wispr is finished,
    /// and that is right — but it may not hold the *next* dictation hostage for
    /// the 30 s of `captureTimeout`, which is exactly what it did: `capturing`
    /// stayed true, `retireCaptureIfSettled` refused to let a non-terminal row
    /// go, and the relay measured **never listening (8.1 s)** on the gesture
    /// after it. So the capture is retired at once and only this much of it
    /// survives: the swallow, **keyed by the rowid it was armed for**, so Wispr's
    /// late ⌘V for the sentence Victor threw away still lands nowhere.
    private var retiredDiscardRow: Int64?
    private var retiredDiscardUntil: CFAbsoluteTime = 0
    private var retiredDiscardTerminalAt: CFAbsoluteTime = 0
    /// Wispr's pid when the retired row was adopted (batch 3's dead-row rule).
    private var retiredDiscardPid: pid_t = 0
    /// Five seconds, against Wispr's own p99 of 7.1 s counted from the *chord* —
    /// this is counted from a row that is already being transcribed, and the
    /// claim is let go earlier than this on every ordinary run (the row goes
    /// terminal and `pasteGrace` passes). It exists so a row Wispr abandons
    /// cannot keep the swallow armed over Victor's next sentence for ever.
    private static let retiredDiscardCeiling: TimeInterval = 5

    /// **Wispr's own row for this dictation** (`WisprHistory`, 2026-09-12) —
    /// the completion signal for a delivery the tap cannot see. Taken at the
    /// microphone's close as the newest row whose `startedAt` is this
    /// dictation's; polled every `historyTick` while capturing.
    /// `private(set)` for `GET /test/state`: *is Wispr's own row being polled,
    /// and which one* is the difference between a settle that will end on its
    /// own and one that will sit out `settleTimeout`.
    private(set) var historyRow: Int64?
    /// The newest rowid at the moment the capture was armed, so a row that was
    /// already there when he started talking can never be read as this
    /// dictation's answer — the failure that would otherwise end every settle on
    /// the first tick now that the poll starts at the **gesture** rather than at
    /// the microphone's close.
    private var priorRow: Int64?
    /// …unless that row was still open, in which case it *is* this dictation's:
    /// Wispr creates the row at the gesture and the relay can be reading a
    /// millisecond after it.
    private var priorRowWasOpen = false
    /// The Scratchpad note that was newest when this dictation opened, so the
    /// one Wispr writes at the end can be told from it — by id for a new note,
    /// by its stamp for one Wispr appended to.
    private var priorNoteId: String?
    private var priorNoteStamp: TimeInterval = 0
    /// **The note's whole text before this dictation**, because Wispr does not
    /// reliably start a new note: measured 2026-09-13, it appended to the note
    /// from a run four minutes earlier with `source = typed`, and a delivery of
    /// `NoteVersions.content` would then have handed over the accumulated
    /// notepad — 70 characters for a four-word sentence, growing every time.
    private var priorNoteText: String?
    /// Whether the note path has already dealt with the Scratchpad window, so
    /// `endCapture` does not tap the chord a second time behind it.
    private var scratchpadWindowHandled = false
    /// **What wakes the row readers** (batch 3, 2026-09-28): Wispr's commits to
    /// `flow.sqlite-wal`, gated by `PRAGMA data_version`, with a 1 s safety tick —
    /// the 150 ms `historyPoll` timer (and the retired-discard and discard-close
    /// timers beside it) are gone. `WisprHistoryWatch`.
    private let historyWatch = WisprHistoryWatch()
    private static let captureWatchKey = "capture"
    private func stopHistoryPoll() { historyWatch.unsubscribe(Self.captureWatchKey) }
    /// When the row said `formatted`, so the ⌘V that normally follows gets
    /// `pasteGrace` to arrive before the text is taken from the row instead.
    private var historyFormattedAt: CFAbsoluteTime = 0
    private static let pasteGrace: TimeInterval = 1.0
    /// **When the relay itself posted ⌃Escape at the adopted row** — the cancel
    /// during the settle (batch 3's dead-row rule: still `processing` 1 s later,
    /// Wispr has abandoned it). 0 = no dismiss of the relay's own; ⌘⌃X in flight
    /// posts none (Wispr is left to finish).
    private var relayDismissedAt: CFAbsoluteTime = 0
    /// Wispr's main pid when the row was adopted (batch 3's dead-row rule).
    private var pidAtAdoption: pid_t = 0
    /// `wisprLive.rowSeen` — the last (row, status) the capture's reader saw
    /// change, and when (wall clock): the desk measures the watch with it.
    private var rowSeen: (rowid: Int64, status: String, at: Date)?

    /// **The row is the delivery, not the fallback** — off by default, and the
    /// shape the wrap is heading for (Victor, 2026-09-13, evening).
    ///
    /// The wrap as built is *swallow Wispr's ⌘V and insert the words ourselves*,
    /// and it failed twice on 09-13 for the same reason both times: it depends on
    /// a keystroke another process may or may not post, inside a window the relay
    /// may or may not have armed. The candidate that replaces it does not depend
    /// on a keystroke at all — **take Wispr's Accessibility grant away**, so it
    /// can neither write through AX nor post a synthetic ⌘V, and read the words
    /// out of its `History` row. The sink was the other candidate and Victor
    /// ruled it out the same evening: holding the key window through every
    /// dictation is not something to do to a man who may be typing.
    ///
    /// With this on: `formatted` delivers **immediately** (there is no ⌘V to wait
    /// `pasteGrace` for), the text comes from `pastedText` or `formattedText`
    /// (`Entry.text` — a Wispr that inserted nothing fills the second), and the
    /// delivery is always `.route`, because nobody but the relay is going to put
    /// the sentence anywhere. The ⌘V swallow stays armed as the safety net for
    /// the day the grant comes back.
    ///
    /// `WT_WISPR_HISTORY_ROUTE=1`, or `POST /test/wispr {"historyRoute": true}`.
    ///
    /// **On by default since 2026-09-22**, the day the firewall went in: the ⌘V
    /// never lands anywhere, so waiting `pasteGrace` for it is a second of
    /// nothing. `WT_WISPR_HISTORY_ROUTE=0` puts the wait back.
    var historyIsTheRoute = ProcessInfo.processInfo.environment["WT_WISPR_HISTORY_ROUTE"] != "0" {
        didSet {
            Log.info("wispr history route \(historyIsTheRoute ? "on — the row is the delivery, no ⌘V is waited for" : "off — the ⌘V is the delivery and the row is the backstop")")
        }
    }
    /// Wall clock of whichever came first, the gesture or the microphone — the
    /// row's `startedAt` has to be at or after this to be this dictation's.
    private var openedAt: TimeInterval = 0

    private static let bundlePrefix = "com.electron.wispr-flow"

    // MARK: - Life

    init(hotkeys: HotkeyTap) {
        self.hotkeys = hotkeys
        // The machine decides when the poll is worth running; nothing else may.
        // **And every edge of `listening` is published** — see `hearingChanged`.
        state.onTransition = { [weak self] previous, next, _ in
            guard let self else { return }
            // Q9: the relay's own Wispr sentence is over — its ⌘V tail runs out
            // in `HotkeyTap.wisprOwnedTail`.
            if next == .idle {
                self.hotkeys.setWisprRelayOwned(false)
                // B (2026-09-28): the tail is row-aware — see `startTailWatch`.
                self.startTailWatch()
            }
            self.syncInputPoll()
            if previous.isListening != next.isListening {
                self.hearingChanged?(next.isListening)
            }
        }
        watch.onChange = { [weak self] on in self?.edge(on, measured: true) }
        hotkeys.onWisprMaybeStarting = { [weak self] start in
            // His keyboard, not the relay's — `relay: false`.
            DispatchQueue.main.async {
                self?.gestureSeen(start.why, confident: start.isConfident, relay: false)
            }
        }
        // His own push-to-talk: Wispr listens to From Walkie, so the relay has to
        // carry his voice there — from the key, not from Wispr's input.
        hotkeys.onWisprPushToTalk = { [weak self] in
            self?.feedOwnSentence("right ⌥⇧ — Wispr's push-to-talk")
        }
        startFeedWatch()
        hotkeys.onWisprMaybeCancelling = { [weak self] in
            DispatchQueue.main.async { self?.dismissSeen() }
        }
        hotkeys.onInjectedPaste = { [weak self] from in
            DispatchQueue.main.async { self?.injected(from: from) }
        }
        // B: a row whose ⌘V the tap let through is pasted by Wispr — never again by us.
        hotkeys.onForeignPastePassed = { [weak self] row in
            // TX8b (lab wave 3): his ⌘V passed and nothing landed in TextEdit —
            // where did it go? The front app and the clipboard at the pass
            // (the count only, never the text), and whether Wispr's restore moved it.
            DispatchQueue.main.async {
                guard let self else { return }
                // Read here, not on the tap thread: the count is an IPC round trip.
                let count = Clipboard.changeCount
                self.lastForeignRow = max(self.lastForeignRow, row)
                let front = NSWorkspace.shared.frontmostApplication
                let own = PasteboardTimeline.lastOwnCount
                Log.info("🛡️ his ⌘V passed (row \(row)) — front: \(front?.bundleIdentifier ?? "?") pid \(front?.processIdentifier ?? 0); clipboard #\(count)" + (count == own ? " = the relay's own last write (Q17) — NOT Wispr's item" : " (the relay's own last write #\(own))"))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    let now = Clipboard.changeCount
                    Log.info("🛡️ 0.7 s after his passed ⌘V: clipboard #\(now)" + (now == count ? " — unchanged (no restore by Wispr)" : " — moved (Wispr's restore)"))
                }
            }
        }
    }

    /// **Watch Wispr's microphone whichever engine is wired up** (Victor,
    /// 2026-09-21: *"ori de câte ori Wispr Flow interceptează vocea, trebuie să
    /// fie o animație pe ecran … că pornesc cu apăsat taste, că pornesc din
    /// gesturi de mouse"*).
    ///
    /// Everything else this source does for a foreign dictation is already
    /// unconditional — the tap's two chords and `onWisprRawChord` are wired in
    /// `init` and in `AppDelegate` whatever `dictationSource` says. The
    /// CoreAudio watch was the one witness that was not: it is started by
    /// `prepare()`, which `AppDelegate.wireDictationSource` calls on the
    /// **selected** source only, so with the engine on ElevenLabs or the local
    /// Whisper it never ran. The consequence was a hole exactly the shape of
    /// *every way of starting Wispr that is neither of those two chords* — the
    /// F18 Scratchpad hold, a rebound shortcut, Wispr's own window — for which
    /// nothing at all appeared on screen.
    ///
    /// `WisprWatch.start()` is idempotent, so `prepare()` may still call it and
    /// the source that is wired up loses nothing. This is deliberately **only**
    /// the watch: the Scratchpad sweep and the front-restore in `prepare()` are
    /// wrap machinery, and the relay wraps nothing it did not start.
    func watchMicrophone() {
        watch.start()
    }

    func prepare() {
        watch.start()
        // **The orphan sweep runs for the life of the app** (2026-09-14). It was
        // armed for twelve seconds after each capture and that is exactly when
        // it cannot work: the orphan it is looking for is made by a toggle that
        // lands late, so the window does not exist yet while the sweep is
        // looking, and by +3 s and +15 s — where the runner found it standing —
        // nothing was watching at all. One AX existence read every half second,
        // and only while this source says nothing is going on.
        WisprScratchpad.startIdleSweep { [weak self] in
            guard let self else { return true }
            return self.state.phase == .idle && !self.capturing
                && !self.isRecording && !self.speculative
        }
        // **And whose front it is, given back after every close.** The close is
        // a chord posted at Wispr and Wispr answers it by activating itself —
        // see `putTheFrontBack`. A beat is left for the activation to land,
        // because the chord is posted on its own queue and the front changes
        // after it, not with it.
        //
        // **Twice, because the activation is not on the chord's clock.** The
        // close is a toggle whose effect lands when Wispr gets to it; the
        // second look costs one `frontmostApplication` read on a run where the
        // first one already put him back, and catches the run where Wispr came
        // forward a second after its own window went.
        WisprScratchpad.onCloseFinished = { [weak self] reason, _ in
            for delay in [0.45, 1.5] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    self?.putTheFrontBack(after: reason)
                }
            }
        }
        // Whose keyboard it is, kept current — see `lastFrontPid`.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier != Bundle.main.bundleIdentifier,
                      app.processIdentifier > 0 else { return }
                self?.frontBeforeLast = self?.lastFrontPid ?? 0
                self?.lastFrontPid = app.processIdentifier
                // The tap needs this too, and must not ask AppKit on its own
                // thread — see `HotkeyTap.noteFrontmost`.
                self?.hotkeys.noteFrontmost(app.processIdentifier)
            }
    }

    // MARK: - DictationSource

    @discardableResult
    func start() -> String? {
        guard !isRecording else { return nil }
        guard isReady else { return "Wispr Flow is not running" }
        // **W6 (2026-09-28): ask Wispr before toggling it.** The chord is a
        // toggle: posted over a Wispr that is already recording (his own right
        // ⌥⇧ sentence, a ghost left by a missed stop) it *stops* that one and
        // starts nothing. A microphone of Wispr's open while the relay has none
        // is not the relay's.
        if !HotkeyTap.wisprChordsMuted, watch.sampleIsRunningInput() {
            Log.error("wispr: start refused — Wispr Flow's microphone is already open (not the relay's sentence)")
            return "Wispr Flow is already listening — one engine at a time"
        }
        // **A stand-down is not a verdict.** If the window that would not close
        // is closed now — Victor clicked the menu row, Wispr was restarted — the
        // precondition holds again and there is no reason to go on using the
        // emergency path.
        if scratchpadBroken, HotkeyTap.scratchpadIsConfigured, !WisprScratchpad.windowIsOpen() {
            scratchpadBroken = false
            Log.info("🗒️ the Scratchpad window is closed again — scratchpad mode is back")
        }
        let mode = wrapMode
        // **The ring first, always.** Whatever the mode has to do to get Wispr
        // ready, Victor pressed a button and the beacon answers the button.
        gestureSeen("the relay asked for a dictation (\(mode.rawValue))", confident: true, relay: true)
        switch mode {
        case .scratchpad:
            holdScratchpad()
        case .sink:
            HotkeyTap.postWisprHandsFree()
            // The sink comes up now and takes the keyboard only at the stop —
            // Wispr picks its target at insertion time (measured 3/3), so there
            // is nothing to gain by holding his keyboard for the whole sentence
            // and everything to lose.
            WisprSink.shared.open()
            WisprSink.shared.clear()
        case .off:
            if startUnderHeldPair {
                HotkeyTap.postWisprHandsFreeUnderHeldPair()
            } else {
                HotkeyTap.postWisprHandsFree()
            }
        }
        startUnderHeldPair = false
        return nil
    }

    /// Set by the right ⌘⌥ hold for the next `start()` only: his fingers are on
    /// ⌘⌥, so the start goes out as right ⌘⌥ + F19 (`HotkeyTap.heldPairChordIsConfigured`).
    var startUnderHeldPair = false

    /// **Close the Scratchpad window if it is up, then hold the chord.**
    ///
    /// The order is the measurement (2026-09-13, four runs): with the window
    /// **closed** a held chord writes a note, 3/3; with it **open** Wispr
    /// transcribes normally and writes **no note at all**, and closing it
    /// afterwards does not commit one. The sentence is simply lost, silently, and
    /// the thing that leaves the window open is the *previous* dictation — Wispr
    /// opens it in the background at the end of every one. So the precondition is
    /// checked at the start as well as restored at the end: two chances to
    /// notice, because the failure shows up one sentence later than its cause.
    ///
    /// The common path costs nothing — the window is already closed, `windowIsOpen`
    /// is one window-server call, and the chord goes down in the same turn.
    private func holdScratchpad() {
        // **The window appears at the start of the hold, not at the end**
        // (2026-09-13, corrected by Victor and by the loop's first
        // `scratchpad-hold`). It is a floating panel and it sits on top of his
        // work for the whole sentence, which is the thing he objected to — so it
        // is watched from the chord, parked the moment it is seen, and closed
        // later. His keys are guarded for the same stretch and by the same flag.
        WisprScratchpad.beginDictation()
        guardTheKeyboard()
        guard WisprScratchpad.windowIsOpen() else {
            HotkeyTap.postWisprScratchpad(down: true)
            return
        }
        Log.info("🗒️ the Scratchpad window is open — a held chord writes no note while it is; closing it first")
        WisprScratchpad.closeWindow { [weak self] gone in
            guard let self, self.startedMode == .scratchpad,
                  self.isRecording || self.speculative else { return }
            if gone {
                Log.info("🗒️ the Scratchpad window is closed — holding the chord")
                HotkeyTap.postWisprScratchpad(down: true)
                return
            }
            // **Salvage the sentence rather than lose it.** Holding the chord
            // now would record into a window that writes no note; the hands-free
            // chord with the sink behind it is the emergency path and it works.
            Log.error("🗒️ the Scratchpad window would not close — this sentence goes through the sink instead, and so will the next one")
            WisprScratchpad.endWatch()
            self.scratchpadBroken = true
            self.startedMode = .sink
            HotkeyTap.postWisprHandsFree()
            WisprSink.shared.open()
            WisprSink.shared.clear()
        }
    }

    /// **Shut the window on sight, and hold the keyboard for him meanwhile.**
    ///
    /// Two halves of one answer to the loop's 2026-09-13 finding: a `z` typed
    /// 1.5 s after the stop gesture landed in Wispr's note and was delivered
    /// **inside the sentence**, with `NSWorkspace.frontmostApplication` reading
    /// TextEdit the whole time. The Scratchpad becomes key without its app
    /// becoming frontmost.
    ///
    /// So the window is closed the instant it is seen (50 ms poll, the press
    /// posted immediately), which cuts its life to the few hundred milliseconds
    /// the close itself takes; and for exactly that stretch every real keystroke
    /// is taken by the tap and re-posted to the app he was looking at when he
    /// stopped talking.
    /// **The owner of the frontmost window that is neither this app's nor
    /// Wispr's** — the fallback when `NSWorkspace` says the relay itself is in
    /// front, which a **spawn** guarantees: `startDictation(spawn:)` offers the
    /// folder menu on the gesture, and a menu makes its own app frontmost.
    ///
    /// The cached *last* frontmost app was the fallback before this and it is
    /// empty after a restart and stale after a relaunch of the victim — measured
    /// 2026-09-14, `wrap-spawn` aimed every keystroke at pid 56416, which had
    /// been dead for two builds. The window server's own front-to-back order
    /// cannot be stale: it is asked here and now, and the first window in it that
    /// belongs to somebody else *is* the app he is looking at.
    private static func frontWindowOwner() -> pid_t? {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        let mine = ProcessInfo.processInfo.processIdentifier
        for w in windows {
            guard let pid = w[kCGWindowOwnerPID as String] as? pid_t, pid != mine,
                  pid != WisprScratchpad.wisprPid,
                  // Layer 0 is an ordinary window; the menu bar, the Dock and
                  // Wispr's own floating pill all sit above it.
                  (w[kCGWindowLayer as String] as? Int) == 0
            else { continue }
            return pid
        }
        return nil
    }

    /// The window he was typing in, read once at the chord — `AXFocusedWindow`
    /// of the application that was frontmost then.
    private static func focusedWindow(of pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let w = value, CFGetTypeID(w) == AXUIElementGetTypeID() else { return nil }
        return (w as! AXUIElement)
    }

    private func guardTheKeyboard() {
        // `focusPid` was decided at the gesture, in every mode — see its note.
        guard let pid = focusPid, pid != 0 else {
            Log.error("⌨️ no application to give his keys back to — the keyboard is not guarded for this dictation")
            return
        }
        let name = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "pid \(pid)"
        // **Take the keyboard back rather than work around it.** The Scratchpad
        // becomes key without becoming frontmost, and an app that is frontmost
        // but not key has **no first responder** — so keys re-posted to it with
        // `postToPid` are simply dropped (measured 2026-09-14: five re-posted to
        // TextEdit, five lost). Re-activating the application he was using is
        // the only thing that actually puts the caret back where he left it. It
        // is one call, once per dictation, aimed at the app he is already in,
        // and the Scratchpad it takes the focus from is parked off the edge of
        // the screen by the time this runs.
        // **Give the victim its key WINDOW back, not just its application.**
        //
        // Re-activating the app was not enough and could not be: `activate` says
        // *be frontmost*, and the app was already frontmost — what it did not
        // have was a **key window**, because Wispr's non-activating panel had
        // taken that without taking the front. An application that is frontmost
        // with no key window has no first responder, so a plain character posted
        // to it is dropped, which is why five re-posted letters vanished.
        //
        // So the window itself is remembered at the chord and told, through
        // Accessibility, to be main and focused again. Cheap, and aimed at the
        // window he was actually typing in rather than at whatever the app would
        // pick for itself.
        let victimWindow = Self.focusedWindow(of: pid)
        if victimWindow == nil {
            Log.error("⌨️ could not read \(name)'s focused window — the keyboard cannot be handed back if Wispr takes it")
        }
        WisprScratchpad.onKeyStolen = {
            guard let app = NSRunningApplication(processIdentifier: pid) else { return }
            app.activate(options: [])
            if let w = victimWindow {
                AXUIElementSetAttributeValue(w, kAXMainAttribute as CFString, kCFBooleanTrue)
                AXUIElementSetAttributeValue(w, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            }
            let back = !WisprScratchpad.focusOwnerIsWispr()
            Log.info("⌨️ Wispr's Scratchpad took the keyboard — handed it back to \(name); the focus owner "
                     + (back ? "flipped back" : "is still Wispr"))
        }
        WisprScratchpad.onWindowGone = { [weak self] openMs in
            WisprScratchpad.onKeyStolen = nil
            self?.hotkeys.disarmKeyRedirect()
            if let openMs {
                Log.info(String(format: "🗒️ the Scratchpad existed for %.0f ms; his keys were watched throughout and went to %@",
                                openMs, name))
            }
        }
        hotkeys.armKeyRedirect(to: pid)
    }

    // MARK: - The front of the screen, and who took it

    /// **Wispr's application comes to the front when the wrap closes its note
    /// window, and the front is his.** Victor, 2026-09-14: *"in timpul dictarii
    /// la caret … am pierdut de 3 ori focusul pe aplicatia pe care eram. fix
    /// cand wisprflow pus sa transcrie"*.
    ///
    /// The log names the thief rather than guessing at it: on both of the caret
    /// dictations he lost — 05:56:01 and 05:58:38, out of Terminal — the line
    /// `the front app changed since the chord — his keys go to pid 92966, not
    /// 46446` lands in the same second as `scratchpad chord DOWN/UP`, and 92966
    /// is `com.electron.wispr-flow`. It is the close toggle doing it, not the
    /// transcription, and nothing was putting the front back: he clicked his way
    /// back by hand, three times.
    ///
    /// **This is a different loss from the one `dictation-source.md` calls the
    /// theft, and unlike that one it can be undone.** The theft takes the *key
    /// window* while the victim stays frontmost — `activate` has nothing to say
    /// to it, which is what "the theft cannot be undone" means. This takes the
    /// *front*, so the victim really is behind and activating it is exactly the
    /// right sentence.
    ///
    /// **Only after the close, never during the sentence.** Handing the front
    /// back while Wispr is still writing its note would be aiming Wispr's own
    /// insertion at his document — the failure `WisprHistory` exists because of.
    /// So it hangs off `WisprScratchpad.onCloseFinished`, which fires when the
    /// wrap is finished with the window, and it costs him nothing that the
    /// accepted "a second or two of the keyboard" did not already cost.
    private func putTheFrontBack(after reason: String) {
        guard let thief = NSWorkspace.shared.frontmostApplication,
              thief.bundleIdentifier?.hasPrefix("com.electron.wispr-flow") == true
        else { return }   // he is wherever he is; the close cost him nothing.
        let now = Date()
        frontHandbacks.removeAll { now.timeIntervalSince($0) > Self.frontHandbackWindow }
        guard frontHandbacks.count < Self.frontHandbackLimit else {
            Log.error("🪟 Wispr Flow is in front again after \(reason) — leaving it, \(Self.frontHandbackLimit) handbacks in a minute is a fight, not a fix")
            return
        }
        let mine = ProcessInfo.processInfo.processIdentifier
        let candidates = [frontBeforeLast, focusPid ?? 0, lastFrontPid]
        guard let victim = candidates.first(where: { pid in
            pid != 0 && pid != mine && pid != thief.processIdentifier
                && kill(pid, 0) == 0
                && NSRunningApplication(processIdentifier: pid)?
                    .bundleIdentifier?.hasPrefix("com.electron.wispr-flow") != true
        }), let app = NSRunningApplication(processIdentifier: victim) else {
            Log.error("🪟 Wispr Flow took the front at \(reason) and there is nobody to give it back to")
            return
        }
        frontHandbacks.append(now)
        let name = app.localizedName ?? "pid \(victim)"
        // **`activate` is not enough and measured not to be** (2026-09-14,
        // 06:13): with Wispr holding the front, `activate(options: [])` plus
        // `AXRaise`/`AXMain`/`AXFocused` on his window left Wispr exactly where
        // it was, twice — `it would not go back to Terminal — Wispr Flow is in
        // front`. A background application asking for somebody *else* to be
        // frontmost is the request macOS declines; **`AXFrontmost` on the
        // application element is the one that is granted**, because it is asked
        // with the Accessibility trust this app already has and that is the
        // grant the restriction defers to.
        let activated = app.activate(options: [])
        let axFront = AXUIElementSetAttributeValue(
            AXUIElementCreateApplication(victim), kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        // **The window, not only the application** — the same pair `onKeyStolen`
        // sets, plus the raise, because an application that comes forward with
        // no main window leaves him looking at a front with no caret in it.
        if let w = Self.focusedWindow(of: victim) {
            AXUIElementPerformAction(w, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(w, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(w, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let front = NSWorkspace.shared.frontmostApplication
            if front?.processIdentifier == victim {
                Log.info("🪟 the close took the front to Wispr Flow (\(reason)) — \(name) has it back")
            } else {
                Log.error("🪟 the close took the front to Wispr Flow (\(reason)) and it would not go back to \(name) — \(front?.localizedName ?? "?") is in front (activate=\(activated), AXFrontmost=\(axFront.rawValue))")
            }
        }
    }

    /// **Close it again when the sentence is over, and check that it went.**
    ///
    /// Mandatory rather than tidy: the window Wispr opens at the end of this
    /// dictation is the thing that would silently swallow the next one. Called
    /// from `endCapture`, so it runs on every way out — delivered, dismissed,
    /// empty, timed out.
    private func closeScratchpadAfterwards() {
        WisprScratchpad.closeWhenItAppears { [weak self] appeared, gone in
            guard let self else { return }
            WisprScratchpad.endWatch()
            if gone {
                Log.info(appeared
                    ? "🗒️ the Scratchpad window opened and has been closed — the next dictation can write a note"
                    : "🗒️ no Scratchpad window appeared — nothing to close")
                return
            }
            Log.error("🗒️ THE SCRATCHPAD WINDOW WOULD NOT CLOSE — the next dictation would be transcribed and written nowhere. Falling back to the sink until it does.")
            self.scratchpadBroken = true
        }
    }

    /// **The Scratchpad mode has failed its own precondition and stands down.**
    ///
    /// Not a permanent decision and not a silent one: `POST /test/wrap-mode
    /// {"mode": "auto"}` clears it, and so does a close that works. What it must
    /// not do is go on holding a chord that writes nothing.
    private var scratchpadBroken = false {
        didSet {
            guard scratchpadBroken, !oldValue else { return }
            Log.error("🗒️ scratchpad mode stood down — the wrap is the sink until the window closes again or /test/wrap-mode says otherwise")
        }
    }

    /// **The same chord again** — Wispr's hands-free shortcut is a toggle, and
    /// the relay has nothing else with which to say *stop*. The closing edge is
    /// still `WisprWatch`'s, never this call: a chord Wispr ignores must not
    /// end a dictation that is still running.
    /// **The same chord again, and since 2026-09-13 the relay's own stop is what
    /// closes the listening phase** — the 🔼 click, ⌘⌃D, the second 🔼→, the end
    /// of a `/test` run.
    ///
    /// It used to wait for `WisprWatch`'s closing edge, on the argument that a
    /// chord Wispr ignores must not end a dictation that is still running. The
    /// argument was right and the premise was false: that edge is 0–6 s late and
    /// on the Loopback device it never comes at all, so what the rule actually
    /// bought was a ring standing over a sentence that had already been pasted
    /// into Word, a swallow window armed too late to swallow anything, and a
    /// `speculativeGrace` announcing *Wispr ignored the chord* about a dictation
    /// that had been delivered twelve seconds earlier.
    ///
    /// The relay knows what it asked for. The edge now confirms and logs.
    func stop() {
        guard isRecording || speculative else { return }
        // **The last second of his sentence may still be in this app** (2026-09-14).
        // With the bridge up, what Wispr has heard lags what he said by whatever
        // is queued in the player — and a stop chord posted now ends the
        // dictation on a tail Wispr never received. So the chord waits for the
        // queue, bounded: a stuck player must not leave the microphone open.
        // Zero, and therefore a straight-through call, on every run with the
        // bridge down. → `AudioBridge.queuedSeconds`
        //
        // **The feed is cut first, and that is not an optimisation.** The meter
        // goes on capturing until `stopMeter`, which runs *after* this — so a
        // drain measured with the sink still attached is a queue being refilled
        // as fast as it empties, and the chord would never go out while he was
        // still making a sound. Detaching here also draws the line in the right
        // place: Wispr hears everything up to the stop gesture and nothing after
        // it. Idempotent, so the re-entry below costs nothing.
        //
        // **Cut at the bridge, never at the recorder** (2026-09-22). This line
        // was `meter.onBuffer = nil`, and that setter takes `MicRecorder.lock`
        // — the one `start(to:)` holds across its CoreAudio bind, which is the
        // freeze *Never open or close a microphone on the main thread* is
        // about. Measured this morning at 07:37: the recorder was still inside
        // `start(to:)` (no `mic: recording through …` line for that dictation),
        // the forward click came here, and the main thread waited on the lock
        // for good — the chip frozen, the stop chord never posted, Wispr left
        // recording, Force Quit the only way out. `closeInput` holds a lock
        // that is only ever taken for an addition. The recorder's own detach
        // still happens in `stopMeter`, on `meterQueue`, where it belongs.
        flushWaitingMarkers()
        bridge.closeInput()
        // **Wispr has not opened its input yet** (From Walkie, 2026-09-29): the
        // whole sentence is still held here, and a chord now would stop a Wispr
        // that never heard a word. Released if it is running this instant (the
        // 25 ms watch may not have ticked); otherwise waited for, bounded — past
        // it the chord goes out and Q14 carries the take on the relay's WAV.
        if bridge.isHolding, ownTakeOnly == nil {
            if watch.sampleIsRunningInput() {
                bridge.release("the relay's stop — Wispr's input is running")
            } else {
                let now = CFAbsoluteTimeGetCurrent()
                if stopHeldSince == 0 { stopHeldSince = now }
                let wisprTookIt = historyRow != nil || now - gestureAt < 1.0
                if wisprTookIt, now - stopHeldSince < Self.stopWaitsForInput {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.stop() }
                    return
                }
                Log.error(String(format: "🔀 the stop waited %.1f s and Wispr's input never ran — "
                                 + "stopping it; the relay's own recording carries the sentence",
                                 now - stopHeldSince))
            }
        }
        let drain = bridgeDrainSeconds
        if drain > 0.02 {
            let now = CFAbsoluteTimeGetCurrent()
            if drainMovedAt == 0 {
                Log.info(String(format: "🔀 holding the stop for %.0f ms of his voice still in the bridge",
                                drain * 1000))
            }
            if drainMovedAt == 0 || drain < drainSeen - 0.005 { drainSeen = drain; drainMovedAt = now }
            if now - drainMovedAt < Self.drainStall {
                // Re-checked every quarter second: at a catch-up rate above 1 the
                // queue empties faster than its own length in seconds.
                DispatchQueue.main.asyncAfter(deadline: .now() + min(drain, 0.25)) { [weak self] in self?.stop() }
                return
            }
            Log.error(String(format: "🔀 the bridge's queue has not moved for %.0f s (%.1f s still in it) — "
                             + "stopping anyway", Self.drainStall, drain))
        }
        drainMovedAt = 0
        // **Batch 4: Wispr is out of this sentence** (`holdOwnTake`) — no chord:
        // a toggle now would start a Wispr dictation nobody asked for.
        if ownTakeOnly != nil {
            closeListening("the relay's own stop — Wispr Flow was out of this sentence, no chord posted")
            return
        }
        // **W6: a stop over a Wispr that never took the start posts nothing.**
        // No row, no microphone, well past the 357 ms a row takes: Wispr did not
        // hear the start chord, and a second toggle now would *start* a ghost
        // recording of the room.
        //
        // **A relay sentence too, and then the local model at once** (2026-09-29,
        // 09:51): the check below asked `!isRecording`, which a relay start sets at
        // the gesture — so it never fired for one. The stop chord went out (at
        // 09:45 it *started* Wispr: a ghost), and with no row coming the sentence
        // sat out the 30 s `captureTimeout` before Q14. Now the relay's own take
        // is the sentence, closed here and handed to the local model (Q14's
        // path through `ownTakeOnly`); E still watches for a late start.
        if relayStarted, startWasLost {
            Log.error("wispr: stop without a chord — Wispr never took the start (no row, no microphone): "
                      + "the relay's own recording is the sentence, the local model now")
            ownTakeOnly = "Wispr Flow never took the start chord"
            ownTakeSince = CFAbsoluteTimeGetCurrent()
            closeListening("the relay's own stop — Wispr never took the start, no chord posted")
            return
        }
        if !isRecording, speculative, historyRow == nil, !watch.sampleIsRunningInput(),
           CFAbsoluteTimeGetCurrent() - gestureAt > 1.0, startedMode != .scratchpad {
            Log.info("wispr: stop without a chord — Wispr never took the start (no row, no microphone)")
            closeListening("the relay's own stop (Wispr never started)")
            return
        }
        // B-risk (TX6b): a stop for a sentence Wispr never answered may be read
        // as a start — a row it opens now is the relay's, not his.
        if historyRow == nil, startedMode != .scratchpad { WisprOwnership.noteRelayChord() }
        switch startedMode {
        case .scratchpad:
            HotkeyTap.postWisprScratchpad(down: false)
        case .sink:
            HotkeyTap.postWisprHandsFree()
            // **The keyboard, for the moment that matters and no longer.**
            // Wispr picks the app it will insert into at the *end*; taking key
            // 1–5 ms after the stop chord was enough, 3/3.
            WisprSink.shared.onArrival = { [weak self] text, route in
                DispatchQueue.main.async { self?.sinkArrived(text: text, route: route) }
            }
            WisprSink.shared.becomeKey()
        case .off:
            HotkeyTap.postWisprHandsFree()
        }
        if startedMode != .scratchpad, let row = historyRow { verifyStopTook(row: row, armed: armedAt, retried: false) }
        closeListening("the relay's own stop gesture")
    }

    /// **Check that Wispr took the stop chord, and do not leave it listening if
    /// it did not** (2026-10-01, Victor: *"s-a blocat adineauri wisprflow: a
    /// rămas în ascultare"* — `WisprState.stopWasLost`). `stopTakesWithin` after
    /// the chord: the row still NULL and Wispr's microphone open → the toggle is
    /// posted once more (a second chord over a Wispr that did take the first
    /// would start a dictation, which is why both witnesses are asked). Still
    /// so after that: the sentence ends on the relay's own recording (Q14, the
    /// local model) and **then** Wispr is dismissed — in that order, because a
    /// row that comes back `dismissed` to a live capture is read as his cancel.
    private func verifyStopTook(row: Int64, armed: CFAbsoluteTime, retried: Bool) {
        DispatchQueue.main.asyncAfter(deadline: .now() + WisprState.stopTakesWithin) { [weak self] in
            guard let self, self.capturing, self.armedAt == armed, self.historyRow == row,
                  !self.isRecording, !self.speculative, !self.cancelling, !self.discardOnArrival,
                  let e = WisprHistory.entry(rowid: row),
                  WisprState.stopWasLost(status: e.status, duration: e.duration,
                                         wisprMicOpen: self.watch.sampleIsRunningInput()) else { return }
            if !retried {
                Log.error(String(format: "wispr: the stop chord did not take — row %lld still NULL and Wispr's "
                                 + "microphone still open %.1f s on; posting the stop once more",
                                 row, WisprState.stopTakesWithin))
                WisprOwnership.noteRelayChord()
                HotkeyTap.postWisprHandsFree()
                self.verifyStopTook(row: row, armed: armed, retried: true)
                return
            }
            Log.error("wispr: the second stop did not take either — row \(row) still listening: the relay's own "
                      + "recording is the sentence (the local model), and Wispr is dismissed (⌃Escape)")
            self.endCapture(quiet: true)
            self.endWithRecording("Wispr Flow did not take the stop chord", row: row,
                                  dismissedAt: Date().timeIntervalSince1970)
            HotkeyTap.postWisprCancel()
        }
    }

    func cancel() {
        // **The ✕ during the wait counts too.** Between the microphone closing
        // and the words arriving there are seconds in which the sentence is
        // still this app's to throw away — and it is exactly the stretch in
        // which Victor realises he does not want it.
        if !isRecording, !speculative, capturing {
            // **A cancel during the settle must not disarm the swallow.**
            //
            // It used to `endCapture` here, and the adversarial run found what
            // that costs: a `forward-left` 200 ms after the stop tore the
            // capture down while Wispr's ⌘V was still 300 ms from arriving, and
            // the trace shows exactly what happened next —
            // `↓ key 9 pid 81316 flags 0x20100000 — passed`. Wispr's text went
            // into TextEdit, which is the one promise this whole wrap exists to
            // keep. **Never disarm while Wispr may still paste.**
            //
            // So the capture stays armed and the sentence is *discarded on
            // arrival*: Victor is told it is cancelled now, Wispr is told to
            // dismiss, and whatever still comes — a ⌘V, a row going terminal, a
            // note — is swallowed and dropped rather than let through. The
            // Scratchpad closes with the capture, which is to say after Wispr is
            // finished with it and not before.
            discardOnArrival = true
            dismissedAt = CFAbsoluteTimeGetCurrent()
            // Batch 3: the relay's own dismiss — a row still open 1 s on is dead
            // (Wispr abandons a dictation dismissed during processing), so the
            // swallow is not held for `captureTimeout` on it.
            relayDismissedAt = dismissedAt
            historyWatch.wake(after: WisprState.dismissGrace + 0.05)
            Log.info("🗑️ cancelled while the words were in flight — the swallow stays armed until Wispr is done, and the words are dropped")
            HotkeyTap.postWisprCancel()
            // **And nothing is being waited for any more** (2026-09-14). The
            // capture stays armed because Wispr may still paste; the *phase*
            // stayed `transcribing` with it, and that is a different claim and a
            // false one — `isWaitingForWords` is what `onPasteToggle` and the
            // settle read to decide whether a sentence is still on its way, and
            // for up to thirty seconds after the cancel it told them one was.
            // The next 🔼 click was answered with *nothing to start, nothing to
            // stop* and the relay measured **never listening (8.1 s)**. The
            // swallow is armed; the sentence is gone. The two are said
            // separately now, and `pollHistory` no longer feeds the machine from
            // a row it is only listening to in order to drop it.
            state.reset("cancelled while the words were in flight — the swallow stays armed, nothing is awaited")
            armDiscardClose()
            endCancelledWithRecording()
            return
        }
        guard isRecording || speculative else { return }
        cancelling = true
        // **Release first, then dismiss.** In Scratchpad mode the chord is held,
        // and a ⌃Escape posted with it still down is a dismiss Wispr reads while
        // it is still being told to record.
        if startedMode == .scratchpad { HotkeyTap.postWisprScratchpad(down: false) }
        if ownTakeOnly != nil {
            Log.info("🗑️ dictation cancelled — the relay's own recording (Wispr Flow was out of it: no ⌃Escape)")
        } else {
            Log.info("🗑️ Wispr Flow dictation cancelled — posting ⌃Escape")
            HotkeyTap.postWisprCancel()
        }
        // **The cancel closes it here too.** Same change as `stop()`, same
        // reason: waiting for a CoreAudio edge that may never come left the ring
        // up over a dictation Victor had already thrown away.
        closeListening("the relay's own cancel")
        state.reset("cancelled")
    }

    // MARK: - ⌘⌃X: the local model, now (2026-09-28)

    func handToLocal() -> Bool {
        // **Recording: Wispr is dismissed, not stopped** — a stop would have it
        // transcribe (and paste) words nobody is waiting for any more. The same
        // close the cancel makes, with the recording kept for the local model.
        if isRecording || speculative {
            cancelling = true
            handingToLocal = true
            if startedMode == .scratchpad { HotkeyTap.postWisprScratchpad(down: false) }
            if ownTakeOnly != nil {
                Log.info("💻 ⌘⌃X — the relay's own recording goes to the local model (Wispr Flow was out of it)")
            } else {
                Log.info("💻 ⌘⌃X — Wispr Flow dismissed (⌃Escape); the relay's own recording goes to the local model")
                HotkeyTap.postWisprCancel()
            }
            closeListening("⌘⌃X — the local model takes it")
            state.reset("handed to the local model (⌘⌃X)")
            return true
        }
        // **In flight: the wait is abandoned, Wispr is left to finish** — its
        // row and its ⌘V arrive into the discard (swallowed, logged, dropped),
        // exactly as after a cancel during the settle, minus the dismiss.
        guard capturing, intercepting, !discardOnArrival else { return false }
        discardOnArrival = true
        dismissedAt = CFAbsoluteTimeGetCurrent()
        Log.info("💻 ⌘⌃X — no longer waiting for Wispr's row; whatever it sends is only logged")
        // **A Wispr still listening is dismissed** (2026-10-01): the stop it
        // never took left it recording the room for 7 minutes after this ⌘⌃X.
        // Only that case — a Wispr already transcribing is left to finish.
        if let row = historyRow, let e = WisprHistory.entry(rowid: row),
           WisprState.stopWasLost(status: e.status, duration: e.duration, wisprMicOpen: watch.sampleIsRunningInput()) {
            Log.info("💻 ⌘⌃X — Wispr is still listening on row \(row) (its stop never took): dismissed (⌃Escape)")
            relayDismissedAt = dismissedAt
            HotkeyTap.postWisprCancel()
        }
        state.reset("handed to the local model (⌘⌃X) — Wispr's answer is only logged")
        armDiscardClose()
        endWithRecording(DictationEnd.localForced, row: historyRow, forced: true)
        return true
    }

    /// The relay's own recording of a relay sentence whose row is still owed —
    /// the speculative local decode reads it (2026-09-29). Not his own chord's
    /// sentence (nothing of it is the relay's to deliver), not a cancel, not a
    /// file already gone. **A 🔽 → plain sentence counts** (2026-10-06): it was
    /// armed and counted down, but `relayStarted` is false for the raw chord, so
    /// the decode never got its WAV — at 11:14 the countdown hit zero, nothing
    /// went in, and the words waited 33 s for Wispr's `error`.
    func closedTakeAudio(take: Int) -> TakeAudio? {
        guard let k = keptTake, walkieOwned, intercepting, !cancelling, !discardOnArrival,
              FileManager.default.fileExists(atPath: k.url.path) else { return nil }
        return k
    }

    // MARK: - The test routes

    /// `POST /test/wispr` — the CoreAudio edge with no CoreAudio behind it.
    /// `measured: false` keeps the latency line honest: this enters below the
    /// watcher and would otherwise print the age of the last real dictation.
    func simulatePoll(_ on: Bool) {
        Log.info("🧪 POST /test/wispr {via: poll} — the 100 ms poll reads the microphone \(on ? "open" : "closed")")
        testPollSays = on
    }

    func simulateEdge(_ on: Bool) {
        guard isRecording != on || (on && speculative) else { return }
        Log.info("wispr flow \(on ? "opened" : "closed") the microphone (simulated)")
        edge(on, measured: false)
    }

    /// `POST /test/wispr-handsfree` — the **real** chord on the wire, which is
    /// the one input the end-to-end harness is allowed to cause. Deliberately
    /// not `start()`: the harness has to be able to post the chord a second time
    /// to stop the dictation, and `start()` refuses while one is running.
    /// **And it drives the machine**, because since 2026-09-13 this app's own
    /// posts are stamped out of its tap (`backButtonStamp` on the hands-free
    /// branch of `HotkeyTap`) — otherwise every chord this route posts would come
    /// back through the tap as though Victor had pressed it. The toggle's two
    /// presses are the dictation's two ends, so the second call stops.
    ///
    /// - Parameter byHand: post it **as though Victor had pressed it** — `relay:
    ///   false`, so the dictation is Wispr's from the chord: ring only, nothing
    ///   swallowed, nothing delivered, `intercepting` and `relayStarted` both
    ///   false. Without it the route keeps its old behaviour, which is the
    ///   transcribe primitive the harness is written against.
    ///
    ///   The adversarial round found the two being conflated (Finding 3): the
    ///   route promised a hand-started dictation and `gestureSeen(relay: true)`
    ///   made the relay swallow Wispr's ⌘V and re-deliver the sentence itself —
    ///   `lastDelivery={via:wispr-cmdv,kind:route,to:caret}` on a run whose whole
    ///   point was that the relay would only watch. They are two different
    ///   questions and they get two different calls.
    func postStartChord(byHand: Bool = false) {
        HotkeyTap.postWisprHandsFree()
        if isRecording || speculative {
            closeListening("POST /test/wispr-handsfree — the toggle's second press")
        } else if byHand {
            gestureSeen("POST /test/wispr-handsfree {hand}", confident: true, relay: false, mode: .off)
        } else {
            // **`mode: .off`, and the wrap still on.** This route posts Wispr's
            // *hands-free* chord, so there is no held key for `stop()` to release
            // and no sink to take — but the ⌘V it will produce is the relay's to
            // swallow exactly as it was yesterday, which is the behaviour the
            // loop is written against.
            gestureSeen("POST /test/wispr-handsfree", confident: true, relay: true, mode: .off)
        }
    }

    /// **A chord this app posted for a gesture — 🔽 →, or the back click that
    /// stops it** (2026-09-18).
    ///
    /// The tap's keyboard branch cannot report these: it filters this app's own
    /// posts out by design (`backButtonStamp`), so a 🔽 → sentence reached
    /// `WisprState` through **no** witness at all — no chord, therefore no row
    /// poll, therefore never `listening`, therefore no `hearingChanged` and no
    /// ⚡ ring. With the Engine on the local model or ElevenLabs there is no
    /// second witness either: this source's `watch` is only started by
    /// `prepare()`, which is never called for a source that is not wired.
    ///
    /// **`relay: false`, always.** The sentence is Wispr's own — the relay rings
    /// for it and routes nothing, which is the 09-12 contract for this flick and
    /// is what `relayStarted` carries. `confident: true`, because this app
    /// posted the chord itself: there is no gesture to have misread. The
    /// toggle's two halves are told apart by `gestureSeen` from its own state,
    /// exactly as they are for his keyboard, so `closing` is a *description* of
    /// what the tap believed rather than an instruction.
    /// **W6's question: did Wispr ever take this sentence's start?** No row, no
    /// microphone, well past the 357 ms a row takes (p99 of 5395: 838 ms after the
    /// chord) — a toggle posted now would *start* a ghost recording of the room.
    private var startWasLost: Bool {
        historyRow == nil && !micSeen && !watch.sampleIsRunningInput()
            && CFAbsoluteTimeGetCurrent() - gestureAt > 1.0 && startedMode != .scratchpad
    }

    /// **The raw toggle's stop (🔽 →, F5, the back click) asks W6 first**
    /// (2026-10-02, Victor: *"nu se închide dictarea în Wispr, e deschis"*). At
    /// 11:07:00 F5 opened a plain sentence and Wispr never took the start chord —
    /// no row, no microphone for 7 s. The tap posted the stop straight onto the
    /// wire, past `stop()`'s W6, and that chord *started* Wispr: row 18220,
    /// written at the stop, left listening while the relay ended the sentence on
    /// its own recording. On main, before anything goes on the wire: a lost start
    /// gets no chord, and the relay's own recording is the sentence (Q14).
    func rawStop() {
        if isRecording || speculative, startWasLost {
            Log.error("wispr: 🔽 → stop without a chord — Wispr never took the start (no row, no microphone): "
                      + "the relay's own recording is the sentence, the local model now")
            ownTakeOnly = "Wispr Flow never took the start chord"
            ownTakeSince = CFAbsoluteTimeGetCurrent()
            closeListening("Victor's own 🔽 → (the stop) — Wispr never took the start, no chord posted")
            return
        }
        HotkeyTap.postWisprHandsFree()
        noteRawChord(closing: true)
    }

    func noteRawChord(closing: Bool) {
        gestureSeen(closing ? "🔽 → (the stop) — Wispr's chord, posted raw"
                            : "🔽 → — Wispr's chord, posted raw",
                    confident: true, relay: false, mode: .off, walkiePosted: true)
    }

    /// **`POST /test/wispr-chord` (H4, 2026-09-28): the chord and the relay's
    /// belief about it, decoupled.** `post` puts the toggle on the wire without
    /// touching this source's state (`on`｜`off` are the same fn ⌃ Space — the
    /// word records the intent; `cancel` = ⌃Escape); `state` moves the state
    /// without posting (`start` = the relay's own gesture, `stop` = its close,
    /// `cancel` = `cancel()` with the chord muted). Emulates a lost stop, an
    /// extra toggle, a Wispr that never heard the start.
    func testChord(post: String, state stateVerb: String) -> [String: Any] {
        switch post {
        case "on", "off", "toggle": HotkeyTap.postWisprHandsFree(ignoringMute: true)
        case "cancel": HotkeyTap.postWisprCancel(ignoringMute: true)
        default: break
        }
        switch stateVerb {
        case "start":
            gestureSeen("POST /test/wispr-chord {state: start}", confident: true, relay: true, mode: .off)
        case "stop":
            closeListening("POST /test/wispr-chord {state: stop}")
        case "cancel":
            let was = HotkeyTap.wisprChordsMuted
            HotkeyTap.muteWisprChords(for: 2)
            cancel()
            if !was { HotkeyTap.muteWisprChords(for: 0) }
        default: break
        }
        Log.info("🧪 POST /test/wispr-chord — post \(post), state \(stateVerb)")
        return testDescribe()
    }

    /// **Wispr's microphone, sampled now** — the restart gate's question
    /// (`RestartGate`): is he saying a Wispr sentence the relay is not tracking.
    var wisprMicOpenNow: Bool { watch.sampleIsRunningInput() }

    /// When the tap last reported a Wispr ⌘V (`injected(from:)`), any capture.
    private var lastCmdVAt: CFAbsoluteTime = 0

    /// **`GET /test/state.wisprLive`** (H3 + C's `sawCmdV` / `wisprRelayOwned`,
    /// 2026-09-28): the relay's belief beside Wispr's truth, in one read —
    /// `micOpen` is the same CoreAudio sample the 100 ms poll takes,
    /// `newestRow*` the row on top of `History` (the fake's under `WT_WISPR_DB`).
    func testDescribe() -> [String: Any] {
        let newest = WisprHistory.newest()
        let owned = hotkeys.wisprRelayOwnedWindow()
        return ["micOpen": watch.sampleIsRunningInput(),
                "newestRowId": newest.map { NSNumber(value: $0.rowid) } ?? NSNull(),
                "newestRowStatus": newest.map { $0.status } ?? NSNull(),
                // The row's gesture (2026-09-28) — the restart gate's *fresh row*.
                "newestRowAt": newest.flatMap { $0.startedAt > 0 ? Outbox.iso(Date(timeIntervalSince1970: $0.startedAt)) : nil } ?? NSNull(),
                "newestRowText": newest.map { $0.text.count } ?? NSNull(),
                "captureOpen": capturing,
                "captureRow": historyRow.map { NSNumber(value: $0) } ?? NSNull(),
                "speculative": speculative,
                "isRecording": isRecording,
                "discarding": discardOnArrival,
                "meterRecording": meter.isRecording,
                "bridge": bridge.stats.merging(["feed": feedNow.rawValue]) { _, new in new },
                "sawCmdV": capturing ? lastCmdVAt >= armedAt : (lastCmdVAt > 0 && lastCmdVAt >= armedAt),
                "lastCmdVAt": lastCmdVAt > 0 ? Outbox.iso(Date(timeIntervalSinceReferenceDate: lastCmdVAt)) : NSNull(),
                "relayOwned": owned.active,
                "relayOwnedUntil": owned.until.map { Outbox.iso(Date(timeIntervalSinceReferenceDate: $0)) } ?? NSNull(),
                "ownedRow": ownedRow.map { NSNumber(value: $0) } ?? NSNull(),
                "ownedFloor": ownedFloor,
                "foreignRow": hotkeys.wisprForeignRowNoted,
                "tailWatch": tailWatch != nil,
                "wisprPid": Int(Self.wisprMainPid),
                "pidAtChord": Int(wisprPidAtChord),
                // Batch 4: the relay's own recording carrying the sentence, and since when.
                "ownTake": ownTakeOnly.map { ["why": $0, "for": CFAbsoluteTimeGetCurrent() - ownTakeSince] as [String: Any] } ?? NSNull(),
                // Item 5: the exit watch — which pid, and the last exit it saw.
                "exitWatchPid": Int(exitWatchPid),
                "exited": exitedAt.map { ["pid": Int(exitedPid), "at": Outbox.iso($0)] as [String: Any] } ?? NSNull(),
                "chordsMuted": HotkeyTap.wisprChordsMuted,
                // Batch 3 (2026-09-28): what woke the row readers, and when the
                // capture's reader saw its row change (wall clock, ms).
                "historyWake": historyWatch.describe(),
                "rowSeen": rowSeen.map { ["rowid": NSNumber(value: $0.rowid), "status": $0.status,
                                          "at": Outbox.iso($0.at), "epoch": $0.at.timeIntervalSince1970] as [String: Any] } ?? NSNull(),
                "lastForeignRow": lastForeignRow,
                "lastForeignClaim": lastForeignClaim ?? NSNull(),
                "db": WisprFlowDB.overridePath ?? NSNull()]
    }

    /// `POST /test/wispr-proc {"fakeExit": true}` — the sentence's Wispr reads as
    /// exited from now on (`wisprGone`), no signal sent. Answers the pid.
    func simulateWisprExit() -> [String: Any] {
        let pid = wisprPidAtChord != 0 ? wisprPidAtChord : Self.wisprMainPid
        fakeExitedPid = pid
        Log.info("🧪 POST /test/wispr-proc {fakeExit} — pid \(pid) reads as exited (no signal sent)")
        // Item 5: as the kernel's exit event would say it.
        wisprExited(pid, how: "POST /test/wispr-proc {fakeExit}")
        // The watch stays on the real, living process.
        watchWisprExit(Self.wisprMainPid)
        return ["ok": true, "pid": Int(pid), "fakeExit": true]
    }

    /// `POST /test/wispr {"hotkey": true}` — the speculative ring, one step
    /// earlier than the microphone.
    func simulateHotkey() {
        gestureSeen("POST /test/wispr {hotkey}", confident: true, relay: true, mode: .off)
    }

    // MARK: - Edges

    /// **Wispr's own start gesture, seen on the wire — the dictation starts
    /// here, not when CoreAudio catches up.**
    ///
    /// Measured on Victor's desk 2026-09-12: 5–6 seconds between the chord and
    /// `wispr flow opened the microphone` on a cold Wispr, against 324–674 ms
    /// warm. For those seconds the relay used to have a ring and nothing else —
    /// no chip, no context shot, no music pause — and then everything arrived at
    /// once, behind a ring that had already shrunk away and come back. What he
    /// sees now is one opening: *"the lightning starts fast, but only later the
    /// yellow bubble appears"* is the whole bug report and this is the whole fix.
    ///
    /// - Parameter confident: whether the gesture is unambiguous.
    ///   **fn ⌃ Space is** — it is a chord nothing else on this Mac claims, and
    ///   `postWisprHandsFree` is this app posting exactly it. **Push-to-talk is
    ///   not**: it is two modifiers held (right ⌘ + right ⌥) and nothing else, so
    ///   it fires on a chord Victor may have pressed for something entirely
    ///   different. A false `didBegin` costs a screenshot and a ⌘C probe posted
    ///   into whatever he is working in, which is far too much to spend on a
    ///   guess — so an unconfident gesture raises the beacon and nothing else,
    ///   and its microphone edge does the opening a moment later.
    /// - Parameter relay: whether **this app** asked for the dictation. A
    ///   dictation Victor starts himself is Wispr's: ring only, never
    ///   intercepted, never routed.
    /// - Parameter mode: **how the chord was posted**, which is what `stop()`
    ///   will have to undo. Nil means *the mode in force* — every gesture except
    ///   the loopback's hands-free routes, which post Wispr's own chord and so
    ///   have no key held and no sink to take.
    /// (`heldPair` — the right ⌘⌥ hold read as Wispr's push-to-talk — went with
    /// Q9 step 2, 2026-09-28.)
    private func gestureSeen(_ why: String, confident: Bool, relay: Bool, mode: WrapMode? = nil,
                             walkiePosted: Bool = false) {
        // **The chord is a toggle and the second press is the stop** (2026-09-13).
        // Only for a confident gesture: `fn ⌃ Space` is unambiguous and this
        // app's own posts no longer come back through the tap, so a hands-free
        // chord seen here while a dictation is open is Victor ending it from his
        // keyboard — which the relay used to learn only from a CoreAudio edge
        // that may be six seconds late or absent.
        if confident, isRecording || speculative {
            // Q9: his own chord never ends the relay's sentence — it is Wispr's
            // second sentence, not a stop.
            if !relay, !walkiePosted {
                hisChordAt = Date().timeIntervalSince1970
                Log.info("⚡ \(why) — Wispr's own chord (standalone, Q9); the relay's sentence goes on")
                return
            }
            closeListening("Victor's own \(why)")
            return
        }
        guard !isRecording, !speculative else { return }
        // **Standalone (Q9, 2026-09-26): a dictation he starts with Wispr's own
        // chord is Wispr's alone** — not adopted, not firewalled, not delivered.
        // The back click's raw chord (`walkiePosted`) is Walkie's gesture, not his
        // Wispr chord — still the relay's plain sentence.
        if !relay, !walkiePosted {
            hisChordAt = Date().timeIntervalSince1970
            Log.info("⚡ \(why) — Wispr's own dictation; left to Wispr (Q9)")
            feedOwnSentence(why)
            return
        }
        stopHeldSince = 0
        drainMovedAt = 0
        hotkeys.setWisprRelayOwned(true)
        testPollSays = nil
        // B-risk (TX6b): a row Wispr opens within 1 s of this start is the relay's.
        WisprOwnership.noteRelayChord()
        // **E-FP (lab wave 4, 2026-09-29): a new relay chord disarms the ghost
        // watch.** TW4's unanswered chord armed it; TW8a's relay sentence opened
        // Wispr's microphone 11 s later, and 1 s after TW8a's own stop — Wispr
        // still finishing its row — the watch dismissed it as TW4's ghost: row 227
        // declared dead, the words saved only by the auto p98 fallback.
        relayChordAt = Date().timeIntervalSince1970
        if ghostWatch != nil {
            ghostWatch?.invalidate()
            ghostWatch = nil
            Log.info("👻 the ghost watch for the last unanswered chord is disarmed — a new relay chord (E-FP)")
        }
        unansweredChordAt = 0
        // B: this sentence's rows — the floor is the row on top at the chord.
        tailWatch?.invalidate(); tailWatch = nil
        ownedRow = nil
        ownedFloor = WisprHistory.newest()?.rowid ?? 0
        relayClosedWall = 0
        tailArmed = true
        micSeen = false
        speculative = true
        // **The relay's own recording starts at the gesture** (Q14, 2026-09-28),
        // not at Wispr's confirmation: it is what stands in when Wispr fails,
        // including when Wispr never answers the chord (W3) — and a cold Wispr's
        // deaf first seconds are on it too (W11).
        startMeter()
        // **A chord still waiting for a bare wire belongs to the sentence that
        // asked for it, and that sentence is over.** The epoch moves here and at
        // every `closeListening`; `HotkeyTap.emitScratchpad` drops a hold whose
        // epoch has moved on rather than pressing a key for a dictation nobody
        // is having.
        HotkeyTap.retireDictationEpoch()
        // The guard's counters belong to this dictation and start at zero, armed
        // or not — see `HotkeyTap.resetKeyRedirect`.
        hotkeys.resetKeyRedirect()
        // **Whose keyboard, decided here and in every mode.** The relay's own
        // menu can be in front at this instant (a spawn offers its folder list
        // on the gesture), so the frontmost application is taken only when it is
        // somebody else's, and the last one that was is the fallback.
        let front = NSWorkspace.shared.frontmostApplication
        let frontPid = front?.bundleIdentifier == Bundle.main.bundleIdentifier
            ? 0 : (front?.processIdentifier ?? 0)
        focusPid = frontPid != 0 ? frontPid
            : (Self.frontWindowOwner() ?? (lastFrontPid != 0 ? lastFrontPid : nil))
        relayStarted = relay
        walkieOwned = relay || walkiePosted
        startedMode = relay ? (mode ?? wrapMode) : .off
        // **Every Wispr sentence is the relay's to deliver** (2026-09-22). Until
        // today a dictation Victor started with Wispr's own chord was watched
        // and left to Wispr to paste; with the firewall dropping that paste at
        // the tap there is nobody else to put the words anywhere. `relayStarted`
        // still says whose gesture it was — `AppDelegate` sends his own chord's
        // words to the caret rather than the bound agent.
        intercepting = wrapWispr
        gestureAt = CFAbsoluteTimeGetCurrent()
        openedAt = Date().timeIntervalSince1970
        state.startChord(why)
        if !relay {
            Log.info("⚡ \(why) — Victor's own dictation; the ring is all the relay does with it")
        }
        // **A capture still standing whose row is not terminal is a sentence
        // still in flight**, and this new one does not get to disarm it — that
        // is precisely what happened on 2026-09-13 when a phantom second
        // dictation called `endCapture(quiet:)` and Wispr's ⌘V for the *first*
        // sentence went into whatever Terminal was in front.
        retireCaptureIfSettled()
        if confident {
            isRecording = true
            Log.info("⚡ \(why) — opening the dictation on the gesture")
            didBegin?()
        } else {
            didMaybeBegin?(why)
        }
        // **A guess that is never taken back is a lie.** A chord Wispr ignored
        // — it was not running, the shortcut had been changed, the key went to
        // something else — must not leave a beacon claiming a microphone.
        // **It may only fire when Wispr never created a row** (2026-09-13).
        //
        // The retraction is for a chord Wispr *ignored* — it was not running, the
        // shortcut had been changed — and until today the only evidence it had
        // was *no microphone was seen*, which is exactly the thing this app has
        // stopped being able to see. Twice that day it announced *Wispr ignored
        // the chord* about sentences Wispr had transcribed and pasted. Wispr
        // creates the `History` row at the gesture, so the row's absence is the
        // honest test, and the two outcomes get two different sentences because
        // they call for two different fixes.
        let drop = DispatchWorkItem { [weak self] in
            guard let self, self.speculative else { return }
            if self.historyRow != nil {
                self.confirmSpeculative(by: "Wispr's own row (the relay saw no microphone)")
                return
            }
            // **F1 (lab wave 4, 2026-09-29): he has not stopped — he is still
            // talking.** Twelve seconds with no row and no microphone used to end
            // the sentence here: the relay's recording was cut mid-word, the Q14
            // answer was decoded while `listening` stood with nothing under it,
            // the close was never latched (Q2), and his own stop 🔼→ four seconds
            // later met a sentence that had gone on without him — its words went
            // to the caret the previous sentence had latched (TW4, 77 chars at the
            // caret instead of ttys001). Now the relay's recording carries the
            // sentence to HIS stop, which latches the recipient as every close does,
            // then this Mac transcribes it.
            if self.relayStarted, self.holdOwnTake("Wispr Flow did not answer the chord") {
                self.armGhostWatch()   // E: the start may still land, late, as a ghost
                return
            }
            self.speculative = false
            self.isRecording = false
            // **Nothing else is going to release it.** This is the one path out
            // of a dictation that does not go through `closeListening`, and in
            // Scratchpad mode the chord is still down — twelve seconds of a
            // held key, then a hundred and twenty until the dead-man's switch.
            if HotkeyTap.scratchpadIsHeld { HotkeyTap.postWisprScratchpad(down: false) }
            // Q14: the relay's recording of those seconds is kept and judged.
            let relays = self.relayStarted
            if relays { self.armGhostWatch() }   // E: a start Wispr never answered
            self.stopMeter(keep: relays)
            self.state.timedOut("no row and no microphone within \(Int(Self.speculativeGrace)) s")
            let why = "Wispr never created a row within \(Int(Self.speculativeGrace)) s of the chord — it ignored it"
            RingDown.note(why)
            Log.info("⚡ ring down: \(why)")
            self.endCapture(quiet: true)
            if relays { self.endWithRecording("Wispr Flow did not answer the chord", row: nil) }
            else { self.didEnd?(.silent("")) }
        }
        speculativeDrop?.cancel()
        speculativeDrop = drop
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.speculativeGrace, execute: drop)
        if relay { armChordAnswerProbe(chord: gestureAt); armMicOpenWatch(chord: gestureAt) }
        // **The swallow window and the row poll are armed here, at the start
        // chord** (2026-09-13). They used to be armed at the microphone's close,
        // which is the single decision both failures of that day came out of: a
        // 2.5 s dictation produced no close edge at all, so nothing was ever
        // armed and Wispr pasted straight into Word. Armed at the gesture, a
        // missing edge costs nothing — the window is simply open for the whole
        // sentence, which is one flag.
        beginCapture()
        // The meter comes up with the guess, so the ring breathes from the first
        // syllable rather than from whenever CoreAudio gets round to the edge.
        // `start(to:)` is a no-op on a session already open, so the confirming
        // edge costs nothing when it arrives.
        startMeter()
        syncInputPoll()
    }

    /// **A guess confirmed by something other than the ring's own patience.**
    ///
    /// Three things can confirm it and they are three different facts: the 100 ms
    /// poll and the CoreAudio notification both say *a microphone is open*, and
    /// Wispr's own row says *Wispr took the chord*, which is the one that still
    /// works when nothing can hear the microphone at all.
    private func confirmSpeculative(by what: String) {
        guard speculative else { return }
        speculativeDrop?.cancel()
        speculativeDrop = nil
        speculative = false
        Log.info(String(format: "⚡ %@ confirms the ring %.0f ms after the gesture",
                        what, (CFAbsoluteTimeGetCurrent() - gestureAt) * 1000))
        isRecording = true
        startMeter()
    }

    /// **The microphone is shut as far as this app is concerned** — by the
    /// relay's own stop gesture, by the poll, by the notification, or by Victor's
    /// own chord. Whoever said so, this is the one place the sentence stops being
    /// heard and starts being waited for.
    /// **Did Wispr take the relay's start chord? Asked at 1.5 s, said once**
    /// (2026-09-29). Six forward-button starts in a row went unanswered that
    /// morning (09:43–09:52) and the log said so only at 12 s — *did not answer
    /// the chord* — with nothing about why. Wispr makes its row ~100 ms after a
    /// chord it took (357 ms cold), so 1.5 s with no row and no microphone is a
    /// lost start; this line keeps what can still be read then: how the chord
    /// left, the modifiers on the wire now, Secure Input, Wispr's age and input,
    /// the row on top, and who is in front. Diagnosis only — nothing changes.
    private static let chordAnswerProbe: TimeInterval = 1.5

    /// **A Wispr whose microphone has not opened by `micOpenGrace` is out of
    /// this sentence** (2026-10-08, Victor: *"dictation hangs with «opening
    /// wispr flow». why? + that should autofall back to local model not hang"*).
    /// At 14:33:54 Wispr (up 29 h) made its row and never opened its
    /// microphone; at 14:34:34 it did not answer the chord at all. The chip
    /// said `Opening Wispr Flow...` for the whole sentence, and the only way
    /// out was F1's 12 s `speculativeGrace` — which also never fires once a row
    /// exists. A warm Wispr opens in ~0.4–0.7 s (the bridge's release lines);
    /// a cold one is already handed to the local model at the start (`AutoLocal.
    /// wisprStartupGrace`). So past 3 s with no microphone, row or not, the
    /// relay's own recording carries the sentence (`holdOwnTake`: the chip stops
    /// saying `Opening`, his stop posts no chord, the local model transcribes
    /// it), Wispr's open row is dismissed (⌃Escape) so it is free for the next
    /// one, and a microphone it opens late is a ghost (`armGhostWatch`).
    static let micOpenGrace: TimeInterval = 3
    private func armMicOpenWatch(chord: CFAbsoluteTime) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.micOpenGrace) { [weak self] in
            guard let self, self.gestureAt == chord, self.relayStarted, self.isRecording || self.speculative,
                  self.ownTakeOnly == nil, !self.micSeen, !self.cancelling,
                  self.startedMode != .scratchpad, !self.watch.sampleIsRunningInput() else { return }
            let hadRow = self.historyRow
            let why = hadRow == nil ? "Wispr Flow did not answer the chord in \(Int(Self.micOpenGrace)) s"
                                    : "Wispr Flow's microphone did not open in \(Int(Self.micOpenGrace)) s"
            guard self.holdOwnTake(why) else { return }
            if let row = hadRow {
                Log.error("💻 dismissing Wispr's row \(row) (⌃Escape) — it never opened its microphone, so it is free for the next sentence")
                HotkeyTap.postWisprCancel()
            }
            self.armGhostWatch()
        }
    }
    private func armChordAnswerProbe(chord: CFAbsoluteTime) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.chordAnswerProbe) { [weak self] in
            guard let self, self.gestureAt == chord, self.relayStarted,
                  self.isRecording || self.speculative, self.ownTakeOnly == nil,
                  self.historyRow == nil, !self.micSeen else { return }
            let posted: String
            if let p = HotkeyTap.lastWisprChordPost(), p.at >= chord - 0.05 {
                posted = String(format: "%@, %.0f ms after the gesture", p.what, (p.at - chord) * 1000)
            } else {
                posted = "NO chord posted for this gesture"
                    + (HotkeyTap.lastWisprChordPost().map { " (the last one: \($0.what))" } ?? "")
            }
            let pid = Self.wisprMainPid
            let wispr = pid > 0
                ? "Wispr pid \(pid), " + (ProcessClock.age(pid).map { String(format: "%.0f s old", $0) } ?? "age unknown")
                    + ", input " + (self.watch.sampleIsRunningInput() ? "running" : "idle")
                : "Wispr is not running"
            let top = WisprHistory.newest().map { e in
                String(format: "row on top %lld '%@', opened %.1f s %@ the gesture", e.rowid, e.status,
                       abs(e.startedAt - self.openedAt), e.startedAt >= self.openedAt ? "after" : "before")
            } ?? "no row readable"
            let watched: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift, .maskSecondaryFn]
            let session = CGEventSource.flagsState(.combinedSessionState).intersection(watched).rawValue
            let hid = CGEventSource.flagsState(.hidSystemState).intersection(watched).rawValue
            let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
            Log.error(String(format: "📮 Wispr has not answered the start chord %.1f s after it — no row, no microphone. "
                             + "Chord: %@. %@. %@. Modifiers now: session 0x%llx, HID 0x%llx. %@. Front: %@",
                             Self.chordAnswerProbe, posted, wispr, top, session, hid,
                             HotkeyTap.keyboardHidden() ?? "keys visible to the tap", front))
        }
    }

    /// **A Wispr-side close that was not Wispr's end** (2026-09-29, 12:20 and
    /// 12:34): under the right ⌘⌥ + F19 hold the 100 ms poll saw Wispr's input
    /// stop ~1 s in, the grace saw Wispr alive and the relay closed its take at
    /// 2.6–2.8 s — then Wispr's input came back, it went on recording to 8.7 and
    /// 10 s and the row landed 8–9 s "late". Stamped here, checked when Wispr's
    /// input reopens (`noteInputReopened`) and when the row lands (`duration`).
    private var wisprSideCloseAt: CFAbsoluteTime = 0
    private var wisprSideCloseRow: Int64?
    private func noteWisprSideClose() {
        guard !cancelling else { return }
        wisprSideCloseAt = CFAbsoluteTimeGetCurrent()
        wisprSideCloseRow = historyRow
    }
    private func noteInputReopened() {
        let since = CFAbsoluteTimeGetCurrent() - wisprSideCloseAt
        guard wisprSideCloseAt > 0, since < 8, let row = wisprSideCloseRow else { return }
        wisprSideCloseAt = 0
        let status = WisprHistory.entry(rowid: row)?.status ?? "unreadable"
        guard WisprState.intermediateStatuses.contains(status) else { return }
        Log.error(String(format: "🎙️ Wispr's input reopened %.1f s after the relay took its close as the end of row %lld — "
                         + "the row is still '%@': Wispr is still on this sentence, a blip, not its end; "
                         + "the relay's own take (the Q14 stand-in) stopped at %.1f s",
                         since, row, status, spokenFor))
    }

    private func closeListening(_ why: String) {
        guard isRecording || speculative else { return }
        // Batch 4: a sentence the relay's own recording carried (Wispr out of it)
        // closes here too, at his stop — and ends on that recording.
        let ownTake = ownTakeOnly
        ownTakeOnly = nil
        dropPendingWisprClose()
        if relayStarted, relayClosedWall == 0 { relayClosedWall = Date().timeIntervalSince1970 }
        // E (lab wave 3): a relay sentence Wispr's microphone never opened for —
        // its start may still land, late, as a ghost microphone.
        if relayStarted, !micSeen { armGhostWatch() }
        // **The machine closes here too, and only here.** It used to be told
        // separately at each call site, and the one site that forgot was the
        // CoreAudio edge — so a dictation the relay had settled sat in `warming`
        // for ever as far as the phase was concerned, which is precisely the
        // kind of disagreement between two records of the same fact this file
        // exists to remove.
        state.stopChord(why)
        // **Belt on the hold.** Every ordinary path releases the chord before it
        // gets here; this is for the ones that do not exist yet and for the one
        // that already does — Victor's own hands-free chord, read as a stop for
        // a dictation the relay opened by holding a different key.
        if HotkeyTap.scratchpadIsHeld { HotkeyTap.postWisprScratchpad(down: false) }
        // …and after the release, because the release is the one chord that must
        // still go out: any hold still queued for this sentence is now for a
        // sentence that is over, and pressing it would open Wispr's window
        // behind everything — the 57 s orphan of the adversarial round.
        HotkeyTap.retireDictationEpoch()
        // **When the relay itself stopped the last dictation**, which is what a
        // late CoreAudio *open* edge has to be told from a new one.
        lastStopAt = CFAbsoluteTimeGetCurrent()
        isRecording = false
        speculativeDrop?.cancel()
        speculativeDrop = nil
        speculative = false
        stopMeter(keep: true)   // a cancel keeps it too — Recover (W3, 2026-09-28)
        captureFrom = CFAbsoluteTimeGetCurrent()
        spokenFor = cancelling ? 0 : captureFrom - gestureAt
        Log.info(String(format: "🎙️ the microphone is closed — %@ (%.0f ms of speech)",
                        why, (captureFrom - gestureAt) * 1000))
        // The sentence is over, so the window may go — and the ten seconds the
        // keyboard guard is allowed to outlive it start counting here.
        if startedMode == .scratchpad {
            WisprScratchpad.armCloseOnSight()
            // **And nothing else may ask again.** The close is a *toggle*: a
            // second tap behind the first one closes the window and opens it
            // straight back up. `wrap-cancel` left `['Status', 'Scratchpad']`
            // behind for exactly that reason (2026-09-14) — the cancel path ran
            // `closeListening`'s close and then `endCapture`'s, three seconds
            // apart, and the second undid the first. One owner per close.
            scratchpadWindowHandled = true
            hotkeys.startKeyRedirectCountdown()
        }
        // Before the relay hears the close — see `DecodeRate.activeEngine`.
        // Whichever engine is picked: a sentence Wispr's own chord opened is
        // Wispr's to transcribe (2026-09-23). One the relay's own recording
        // carried is the local model's at once: no Wispr budget is armed for it.
        DecodeRate.activeEngine = ownTake == nil ? DecodeRate.wisprFlow : DecodeRate.whisperLocal
        didStopListening?()
        if cancelling {
            cancelling = false
            if handingToLocal {
                handingToLocal = false
                // The row Wispr opened for it is held owned until it goes
                // terminal (Q14's `watchLateRow`): a paste that slips past the
                // dismiss is dropped, never a second copy.
                let row = historyRow
                endCapture(quiet: true)
                // Batch 3: ⌃Escape went out just now — a row still open 1 s on is dead.
                endWithRecording(DictationEnd.localForced, row: row, forced: true,
                                 dismissedAt: Date().timeIntervalSince1970)
                return
            }
            endCapture(quiet: true)
            endCancelledWithRecording()
            return
        }
        if let ownTake {
            // Wispr was out of it: nothing is coming from Wispr, the take is Q14's.
            endCapture(quiet: true)
            if !isRecording, !speculative { state.reset("the relay's own recording closed (\(ownTake))") }
            syncInputPoll()
            let row = ownTakeRow
            ownTakeRow = nil
            endWithRecording(ownTake, row: row)
            return
        }
        // The capture was armed at the gesture; what starts here is only its
        // deadline, because *how long may the words take* is counted from the
        // last word and not from the first.
        armCaptureDeadline()
        // Batch 3: the NULL rules (W2, the dead-row verdict) are clocks, not
        // commits — a pass at their instant rather than at the next safety tick.
        historyWatch.wake(after: WisprState.nullStopCeiling + 0.05)
        syncInputPoll()
    }

    // MARK: - The 100 ms poll

    /// On between the chord and the words, off the rest of the day.
    private func syncInputPoll() {
        let wanted = state.wantsPoll
        if wanted, inputPoll == nil {
            lastPollSaw = isRecording
            let t = Timer(timeInterval: Self.pollTick, repeats: true) { [weak self] _ in self?.pollInput() }
            inputPoll = t
            RunLoop.main.add(t, forMode: .common)
        } else if !wanted, inputPoll != nil {
            inputPoll?.invalidate()
            inputPoll = nil
        }
    }

    private func pollInput() {
        // Wispr is out of the sentence the relay's recording carries: its
        // microphone is not this sentence's (a late ghost is E's to dismiss).
        guard ownTakeOnly == nil else { return }
        let on = testPollSays ?? watch.sampleIsRunningInput()
        guard on != lastPollSaw else { return }
        lastPollSaw = on
        // **A relay sentence's microphone closing on Wispr's side is not his
        // stop** (batch 4, item 3): a quit closes it too. Asked before the
        // machine hears it, so a quit leaves the phase — and the music, and the
        // ring — where they were. **Batch 5: every such close, credential or
        // not** — wave 5's kill closed the take through the grace running out,
        // and a close with no `pollMs` used to tell the machine at once. What
        // "Wispr ended it" does is exactly what this poll did before item 3.
        // **His own 🔽 → too** (2026-09-30, 17:13:40 and :47): the input blipped
        // off 1.4 s and 0.4 s in, this poll closed the take at once — no grace,
        // it was not `relayStarted` — while Wispr recorded on to 3.1 and 7.1 s;
        // the budget ran out on a sentence still being spoken and he cancelled
        // both. A plain dictation is delivered by the relay like any other.
        if !on, isRecording, !cancelling {
            let why = "the 100 ms poll saw the microphone close"
            return closeFromWisprSide(why) { [weak self] in
                guard let self else { return }
                self.state.poll(false)
                guard self.state.pollMs != nil else { return }
                self.closeListening(why)
            }
        }
        // **Back before the close was decided: a blip, not its end** (2026-09-29,
        // 12:20 and 12:34 — Wispr's input went off ~1 s into a right ⌘⌥ + F19
        // hold and came back; the relay had closed its take at 2.8 s while Wispr
        // recorded on to 8.7 s). The machine was never told the close.
        if on, pendingWisprEnded != nil {
            let since = state.wisprCloseAt.map { CFAbsoluteTimeGetCurrent() - $0 } ?? 0
            dropPendingWisprClose()
            state.wisprInputReopened()
            Log.error(String(format: "🎙️ Wispr's input is back %.1f s after it went off — a blip, not the end of the sentence: it goes on", since))
        }
        state.poll(on)
        if on {
            noteMicSeen()
            confirmSpeculative(by: "the 100 ms poll")
        } else if isRecording {
            // The same credential the notification needs, for the same reason:
            // a poll that never saw this dictation's microphone open is
            // reporting the end of somebody else's.
            guard state.pollMs != nil else { return }
            // Victor ended the dictation from Wispr's own window, or Wispr ended
            // it itself. At most one tick late, against a notification measured
            // at up to six seconds.
            closeListening("the 100 ms poll saw the microphone close")
        }
    }

    /// **Victor pressed Wispr's own dismiss (⌃Escape).** The sentence is over
    /// on Wispr's side and nothing will be pasted, so nothing here may go on
    /// waiting for it: a capture standing is closed and the ring goes down now,
    /// not at `settleTimeout`. While the microphone is still open the closing
    /// edge is still `WisprWatch`'s — `cancelling` makes it report a cancel
    /// rather than arm a capture, exactly as `cancel()` does after posting the
    /// same key.
    private func dismissSeen() {
        // A guess the microphone never confirmed has no closing edge to wait
        // for: it is over here and now. Should Wispr open the microphone after
        // all, that edge opens a fresh dictation, which is what it would be.
        if isRecording || speculative {
            Log.info("🗑️ ⌃Escape — Wispr Flow's dismiss, pressed by hand")
            cancelling = true
            closeListening("Victor's own ⌃Escape")
            state.reset("dismissed by hand")
            return
        }
        guard capturing else { return }
        Log.info("🗑️ ⌃Escape — Wispr Flow's dismiss, pressed by hand while the words were in flight")
        endCapture(quiet: true)
        endCancelledWithRecording()
    }

    /// **The CoreAudio notification — a second witness now, not the witness.**
    ///
    /// It still opens a dictation nothing else knew about (Victor's own chord, on
    /// a build whose tap missed it), because a microphone that is open is a
    /// dictation whatever asked for it. What it no longer does is *end* one on
    /// its own authority while the relay's own stop, the 100 ms poll and Wispr's
    /// row all have something to say first.
    private func edge(_ on: Bool, measured: Bool) {
        if ownTakeOnly != nil {
            Log.info("⚡ a mic edge (\(on ? "open" : "closed")) while the relay's own recording carries the sentence (\(ownTakeOnly ?? "")) — not this sentence's")
            return
        }
        // **Asked before the machine is told**, because `WisprState.notify(true)`
        // takes an `idle` machine into `listening`, and a late open edge would
        // therefore put the phase back into a sentence that is over.
        if on, !speculative, !isRecording, let why = lateOpenEdge() {
            Log.info("⚡ \(why) — a late confirmation of the sentence that is over, not a new dictation")
            return
        }
        // **Q9: a microphone nobody here asked for is Wispr's own sentence** —
        // no ring, no capture, no delivery; and its close is not ours.
        if !speculative, !isRecording {
            if on { Log.info("⚡ Wispr opened its microphone for a sentence of its own — left to Wispr (Q9)") }
            return
        }
        // Batch 4, item 3: the same question as the poll's — a quit, or Wispr's own end?
        // Batch 5: credential or not; "Wispr ended it" is what the edge did before.
        if !on, isRecording, !cancelling {
            return closeFromWisprSide("the CoreAudio edge") { [weak self] in
                guard let self else { return }
                self.state.notify(false)
                if self.state.notifyMs == nil {
                    Log.info("⚡ a mic edge closed with no matching open — it belongs to the previous dictation, ignored")
                    return
                }
                self.closeListening("the CoreAudio edge")
            }
        }
        state.notify(on)
        if on { noteMicSeen() }
        if on {
            // **The edge confirms; it never re-opens.** A guess that is standing
            // is *this* dictation — the ring, the chip and the context shot are
            // already up — and firing `didBegin` again would take them all down
            // and put them back, which is precisely the flicker Victor reported
            // on 2026-09-12.
            if speculative {
                confirmSpeculative(by: "the mic edge")
                return
            }
            guard !isRecording else { return }
            isRecording = true
            openedAt = Date().timeIntervalSince1970
            // No chord was seen for this one — Victor's own, on a build whose
            // tap missed it — so the edge is the only clock there is.
            if gestureAt == 0 || state.chordAt == 0 { gestureAt = CFAbsoluteTimeGetCurrent() }
            // Nobody's gesture but his: `relayStarted` would otherwise be the
            // previous sentence's answer, and the dress reads it.
            relayStarted = false
            walkieOwned = false
            beginCapture()
            startMeter()
            didBegin?()
            syncInputPoll()
            if measured, watch.edgeAt > 0 {
                Log.info(String(format: "⚡ ring up %.0f ms after Wispr Flow opened the microphone",
                                (CFAbsoluteTimeGetCurrent() - watch.edgeAt) * 1000))
            }
        } else {
            // **A witness that never saw the microphone open cannot report it
            // closing** (2026-09-13, 23:56). The notification is 0–6 s late, and
            // a close belonging to the *previous* sentence arrived six seconds
            // afterwards, 600 ms into the next one, and ended it — the dictation
            // was over before a word of it was spoken. `notifyMs` is nil unless
            // this notification saw *this* dictation start, which is exactly the
            // credential the report needs.
            if isRecording, state.notifyMs == nil {
                Log.info("⚡ a mic edge closed with no matching open — it belongs to the previous dictation, ignored")
                return
            }
            guard isRecording else {
                // The ordinary case since the relay closes on its own gesture:
                // the edge arrives seconds later with nothing left to say. Said
                // anyway, because *how much later* is the number that made all
                // of this necessary.
                if captureFrom > 0 {
                    Log.info(String(format: "⚡ the mic edge closed %.0f ms after the relay had already stopped",
                                    (CFAbsoluteTimeGetCurrent() - captureFrom) * 1000))
                }
                return
            }
            closeListening("the CoreAudio edge")
        }
    }

    /// **Is this open edge the last sentence's, arriving late?**
    ///
    /// Two credentials, and it needs both — the second is what keeps a dictation
    /// Victor really did start by hand from being ignored:
    ///
    /// 1. **The relay stopped the last dictation itself and nothing has been
    ///    asked for since** (`lastStopAt >= gestureAt`). A microphone that opens
    ///    after the relay closed the sentence it opened for is describing that
    ///    sentence.
    /// 2. **Wispr has created no newer row.** Wispr writes the `History` row at
    ///    the gesture, 357 ms measured, so a dictation that has really started
    ///    has a row of its own; a late notification about the old one does not.
    ///
    /// Bounded by `lateOpenGrace` — the notification has measured 0–6 s late and
    /// nothing has ever been later, so beyond twice that an open edge is a new
    /// dictation whatever the rows say. The cost of being wrong in that
    /// direction is a missing ring over a dictation the relay would not have
    /// touched anyway (*a dictation Victor starts himself is Wispr's*); the cost
    /// of being wrong the other way is the phantom cycle this exists to remove.
    private func lateOpenEdge() -> String? {
        let now = CFAbsoluteTimeGetCurrent()
        guard lastStopAt > 0, lastStopAt >= gestureAt, now - lastStopAt < Self.lateOpenGrace
        else { return nil }
        let since = (now - lastStopAt) * 1000
        // **The plainest case, and the one both attacks actually took**: the
        // capture for the sentence the relay has just stopped is still open, so
        // the words are still in flight and this edge is about them. It arrived
        // *before* the delivery in Attack 7, which is why a test written only on
        // the finished row would have missed it.
        if capturing {
            return String(format: "the mic edge opened %.0f ms after the relay's own stop, with that sentence's capture still open", since)
        }
        guard let last = historyRow ?? lastRow else { return nil }
        guard let newest = WisprHistory.newest() else {
            return String(format: "the mic edge opened %.0f ms after the relay had already stopped, and Wispr has no row at all", since)
        }
        guard newest.rowid <= last else { return nil }
        return String(format: "the mic edge opened %.0f ms after the relay had already stopped, and row %d is still Wispr's newest",
                      since, newest.rowid)
    }

    /// When the relay's own stop closed the last dictation's listening.
    private var lastStopAt: CFAbsoluteTime = 0
    /// The `History` row the last capture belonged to, kept past `endCapture` —
    /// which clears `historyRow` — because *has Wispr started anything since* is
    /// a question asked after the capture is over.
    private var lastRow: Int64?
    private static let lateOpenGrace: TimeInterval = 12

    // MARK: - Feeding From Walkie (2026-09-29)

    /// **Whose voice the bridge is carrying.** Wispr's microphone is From Walkie
    /// while the relay runs, so *every* Wispr sentence needs a feed, not only the
    /// relay's: `.relay` is the meter of a relay sentence (`startMeter`), `.own`
    /// a metering-only session for a sentence he started with Wispr's own keys
    /// or window — without it Wispr hears silence (`NoAudio`). Under `feedLock`.
    enum Feed: String { case none, relay, own }
    private let feedLock = NSLock()
    private var feed: Feed = .none
    private var feedSince: CFAbsoluteTime = 0
    private var feedSawOpen = false
    private var feedLastOpen: CFAbsoluteTime = 0
    /// When the last feed ended — Wispr's input still closing after it is not a
    /// new sentence of his.
    private var feedEndedAt: CFAbsoluteTime = 0
    private var feedTick = 0
    private let feedQueue = DispatchQueue(label: "ro.victorrentea.wispr-relay.feed-watch")
    private var feedTimer: DispatchSourceTimer?
    /// Main-only: when a stop first found the bridge still holding.
    private var stopHeldSince: CFAbsoluteTime = 0
    /// How long the relay's stop waits for Wispr's input to start running.
    private static let stopWaitsForInput: TimeInterval = 2.5
    /// A key or chord of his that Wispr never answered with its input.
    private static let ownFeedNoShow: TimeInterval = 3

    var feedNow: Feed { feedLock.lock(); defer { feedLock.unlock() }; return feed }

    /// Sets the feed; with `ifNow`, only from that value. True when it changed.
    @discardableResult
    private func setFeed(_ next: Feed, ifNow: Feed? = nil) -> Bool {
        feedLock.lock(); defer { feedLock.unlock() }
        if let ifNow, feed != ifNow { return false }
        guard feed != next else { return false }
        let now = CFAbsoluteTimeGetCurrent()
        if next == .none { feedEndedAt = now }
        feed = next
        feedSince = now
        feedSawOpen = false
        return true
    }

    /// **One watch, 25 ms, for the life of the source** — Wispr's input
    /// (`WisprWatch.sampleIsRunningInput`, the poll's own sample) is what
    /// releases a held bridge. While no feed is up it samples every 200 ms, to
    /// catch a sentence he started from Wispr's own window, which no key shows.
    private func startFeedWatch() {
        feedQueue.async { [weak self] in
            guard let self, self.feedTimer == nil else { return }
            let t = DispatchSource.makeTimerSource(queue: self.feedQueue)
            t.schedule(deadline: .now() + 1, repeating: .milliseconds(25), leeway: .milliseconds(5))
            t.setEventHandler { [weak self] in self?.feedWatchTick() }
            self.feedTimer = t
            t.resume()
        }
    }

    private func feedWatchTick() {
        feedTick &+= 1
        feedLock.lock()
        let feed = self.feed, since = feedSince, ended = feedEndedAt
        feedLock.unlock()
        let now = CFAbsoluteTimeGetCurrent()
        if feed == .none {
            guard AudioBridge.isEnabled, feedTick % 8 == 0, now - ended > 1,
                  watch.sampleIsRunningInput() else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isRecording, !self.speculative else { return }
                self.noteInputReopened()
                self.feedOwnSentence("Wispr opened its input on its own")
            }
            return
        }
        let open = watch.sampleIsRunningInput()
        feedLock.lock()
        if open { feedSawOpen = true; feedLastOpen = now }
        let saw = feedSawOpen, last = feedLastOpen
        feedLock.unlock()
        if open, bridge.isHolding { bridge.release("Wispr's input is running") }
        guard feed == .own else { return }
        if saw ? now - last >= 0.3 : now - since >= Self.ownFeedNoShow {
            endOwnFeed(saw ? "Wispr closed its input" : "Wispr never opened its input")
        }
    }

    /// **His own Wispr sentence, carried** — metering only (nothing written, no
    /// corpus, no delivery: Q9 stands), held from his key until Wispr's input
    /// runs, paced back to live like the relay's. Its tail is Wispr's to cut: a
    /// released push-to-talk stops Wispr at once, so what is still queued then
    /// (the catch-up not yet finished) is not heard.
    func feedOwnSentence(_ why: String) {
        guard AudioBridge.isEnabled else { return }
        meterQueue.async { [weak self] in
            guard let self, self.feedNow == .none, !self.meter.isRecording else { return }
            guard self.bridge.start(format: MicRecorder.fileFormat, holding: true) else { return }
            self.meter.onBuffer = { [weak self] buffer in self?.bridge.schedule(buffer) }
            if let failed = self.meter.startMetering() {
                Log.error("🔀 his own Wispr sentence (\(why)) — no microphone: \(failed)")
                self.meter.onBuffer = nil
                self.bridge.stop()
                return
            }
            self.setFeed(.own)
            Log.info("🔀 his own Wispr sentence (\(why)) — his microphone carried to From Walkie")
        }
    }

    private func endOwnFeed(_ why: String) {
        meterQueue.async { [weak self] in
            guard let self, self.setFeed(.none, ifNow: .own) else { return }
            self.meter.onBuffer = nil
            self.meter.stopMetering()
            self.bridge.stop()
            Log.info("🔀 his own Wispr sentence is over — \(why)")
        }
    }

    // MARK: - The meter, which is also the corpus's recording

    /// The last take's `MicRecorder.Health` (A), read by `endWithRecording`.
    private var recordingHealth: MicRecorder.Health?
    /// `WT_KEEP_TAKES=1` (environment or `elevenlabs.env`, the file read per take —
    /// `fileValue` is cached at launch, so a line added for a run was never seen).
    private static var keepTakes: Bool {
        if ProcessInfo.processInfo.environment["WT_KEEP_TAKES"] == "1" { return true }
        let text = (try? String(contentsOf: ElevenLabsSource.configURL, encoding: .utf8)) ?? ""
        return text.split(separator: "\n").contains { $0.trimmingCharacters(in: .whitespaces) == "WT_KEEP_TAKES=1" }
    }

    private func startMeter() {
        let wav = Outbox.shotsDir.appendingPathComponent("wispr-\(Int(Date().timeIntervalSince1970)).wav")
        keptTake = nil
        meterQueue.async { [weak self] in
            guard let self else { return }
            // His own Wispr sentence's feed gives the microphone up to the relay's.
            if self.setFeed(.none, ifNow: .own) {
                self.meter.onBuffer = nil
                self.meter.stopMetering()
                self.bridge.stop()
                Log.info("🔀 the relay's sentence takes the microphone over from his own Wispr feed")
            }
            guard !self.meter.isRecording else { return }
            // **Before the recorder opens**, so no buffer is produced that the
            // bridge has not been told about: the first syllable is the one most
            // often worth carrying. **Held** until Wispr's input runs — From
            // Walkie drops what nobody reads (2026-09-29).
            self.markersInAudio = false
            self.markerLock.lock(); self.waitingMarkers = []; self.said = []; self.markerLock.unlock()
            if AudioBridge.isEnabled, self.bridge.start(format: MicRecorder.fileFormat, holding: true) {
                self.meter.onBuffer = { [weak self] buffer in self?.bridge.schedule(buffer) }
                self.setFeed(.relay)
            }
            if let why = self.meter.start(to: wav) {
                // The ring is already up — at rest, not breathing. Said out loud
                // because a ring that does not move looks exactly like a broken
                // swell and is not one.
                Log.error("wispr halo: no level — \(why)")
                return
            }
            self.recording = nil
        }
    }

    /// - Parameter keep: whether the WAV is wanted. A cancelled sentence's audio
    ///   is Victor's voice with nothing to label it, and the corpus files pairs.
    private func stopMeter(keep: Bool) {
        meterQueue.async { [weak self] in
            guard let self else { return }
            self.setFeed(.none, ifNow: .relay)
            self.meter.onBuffer = nil
            self.recordingVoiced = self.meter.voicedSeconds
            let taken = self.meter.stop()
            // A (2026-09-28): what the device gave this take, always said.
            let health = self.meter.lastHealth
            self.recordingHealth = health
            if let health {
                Log.info(String(format: "wispr meter: %.1f s voiced — %@%@", self.recordingVoiced, health.line,
                                health.deaf ? " — DEAF (no audio reached the recorder)" : ""))
            }
            if let taken, Self.keepTakes {
                // `WT_KEEP_TAKES=1`: every relay Wispr take copied out before any delete.
                let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".walkie-talkie/kept-takes")
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let dest = dir.appendingPathComponent(taken.url.lastPathComponent)
                try? FileManager.default.removeItem(at: dest)
                try? FileManager.default.copyItem(at: taken.url, to: dest)
                Log.info("🧪 WT_KEEP_TAKES — \(dest.path) (\(String(format: "%.1f", self.recordingVoiced)) s voiced)")
            }
            // **After the recorder, and after whatever it had left.** Tearing the
            // bridge down with audio still queued throws away the end of his
            // sentence — the part Wispr has not heard yet. `bridgeDrainSeconds`
            // is what the stop chord waits on for the same reason; this is the
            // same wait on the way out, ended by a stuck player rather than a
            // clock, so it cannot hold the meter's queue for ever.
            if self.bridge.isRunning {
                // Unbounded like the stop chord's wait, and ended the same way: by
                // a queue that has not moved for `drainStall`.
                var seen = self.bridge.queuedSeconds, movedAt = Date()
                while seen > 0.02, Date().timeIntervalSince(movedAt) < Self.drainStall {
                    Thread.sleep(forTimeInterval: 0.02)
                    let now = self.bridge.queuedSeconds
                    if now < seen - 0.005 { movedAt = Date() }
                    seen = now
                }
                self.bridge.stop()
            }
            if keep {
                self.recording = taken
                let voiced = self.recordingVoiced
                if let taken {
                    DispatchQueue.main.async {
                        self.keptTake = TakeAudio(url: taken.url, duration: taken.duration, voiced: voiced)
                    }
                }
            }
            else if let taken { try? FileManager.default.removeItem(at: taken.url) }
        }
    }

    // MARK: - Catching the transcript

    /// **Armed at the start chord since 2026-09-13**, not at the microphone's
    /// close — see `gestureSeen`. What is armed here is the whole of the wrap's
    /// listening apparatus: the ⌘V swallow, the pasteboard watch and Wispr's own
    /// row. What is *not* armed here is the deadline, because how long the words
    /// may take is counted from the last word (`armCaptureDeadline`).
    private func beginCapture() {
        guard !capturing else { return }
        capturing = true
        // A new sentence: nothing of the last one's length may be filed against it.
        spokenFor = 0
        // **A dictation Victor started is watched and never taken.** The row
        // poll still runs — the chip and the ring want to know when Wispr is
        // done — but nothing is swallowed, nothing is read off the pasteboard
        // and nothing is delivered.
        let takes = intercepting
        sawWisprGone = 0
        wisprPidAtChord = Self.wisprMainPid
        fakeExitedPid = 0
        watchWisprExit(wisprPidAtChord)
        armedAt = CFAbsoluteTimeGetCurrent()
        captureFrom = armedAt
        askedForCopy = false
        // **The change count, and deliberately not the string** (2026-09-14).
        //
        // This line used to read the pasteboard's *text* as well, to keep a
        // baseline to compare a later read against. It crashed the app on the
        // main thread, at the start of a dictation:
        //
        //     EXC_BAD_ACCESS — objc_msgSend → -[NSPasteboard _updateTypeCacheIfNeeded]
        //       → stringForType: → beginCapture → gestureSeen → start()
        //
        // Reading a pasteboard that another process is rewriting is not safe,
        // and this one runs on **every** dictation. The baseline was only ever
        // the belt behind the 2026-09-13 clipboard-restore bug — arming at the
        // start chord is what actually fixed that — so it goes, and the change
        // count, which is an integer and cannot fault, stays.
        clipboardAt = Clipboard.changeCount
        clipboardMoved = nil
        // **Armed whether or not the relay is going to take it.** The probe half
        // — which process posted what key, how long after the microphone shut —
        // is the only record of how Wispr delivers, and it is worth the same two
        // log lines in either mode. Only `swallow` differs.
        // **The ⌘V is taken in every mode, and Scratchpad mode is not the
        // exception it looked like** (2026-09-13, settled at 23:54).
        //
        // It was let through for one build, on the reasoning that Wispr's paste
        // belongs to Wispr's own note and swallowing it is this app reaching
        // into another app's conversation with itself. True while the note was
        // the delivery; false the moment the row took over and the window
        // started being closed on sight. Measured: with the window shut at the
        // release, Wispr's paste arrives ~450 ms later with nowhere of its own
        // to go, and it lands in **Victor's document** — every sentence appeared
        // twice, once lowercased from Wispr and once properly from the relay.
        //
        // With the row as the delivery there is nothing the paste is needed for,
        // so the invariant the whole wrap exists to keep — *Wispr never inserts
        // anywhere* — is simply restored. The note becomes a thinner cross-check
        // and says so when it is empty.
        if takes { hotkeys.armInjectionCapture(swallow: true) }

        // The pasteboard is the other half of the answer, and the only half in
        // the cases where the ⌘V never arrives: an Accessibility insertion, a
        // focus Wispr refuses to paste into, a keystroke that went somewhere
        // else. Polled at 20 Hz and **only while capturing** — a permanent
        // pasteboard poll is a different and much worse thing than a six-second
        // one.
        clipboardWatch?.invalidate()
        // **No pasteboard watch in Scratchpad mode.** Wispr writes the clipboard
        // and puts it straight back there too, and with nothing pasted anywhere
        // the only thing a watcher could report is the restore — which is the
        // bug that filed a Word contract as a dictation three times.
        let watchesBoard = takes && startedMode != .scratchpad && !hotkeys.wisprFirewallOn
        let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            guard watchesBoard else { return }
            guard let self, self.capturing else { return }
            guard Clipboard.changeCount != self.clipboardAt else { return }
            self.clipboardWatch?.invalidate()
            self.clipboardWatch = nil
            // **Read the string now, not in 250 ms.** Wispr writes the
            // transcript, presses ⌘V and puts the previous clipboard back, and
            // the restore lands inside exactly that gap — three sentences on
            // 2026-09-13 were delivered as the clipboard Wispr had just restored.
            self.clipboardMoved = Self.pasteboardString()
            // Give the ⌘V a beat to arrive behind the write: Wispr sets the
            // pasteboard *then* presses the key, so a poll that fires in between
            // must not conclude the key is never coming.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self, self.capturing else { return }
                self.deliver(reason: "the pasteboard moved but no ⌘V was seen",
                             via: "pasteboard", delivery: .alreadyInserted)
            }
        }
        clipboardWatch = t
        RunLoop.main.add(t, forMode: .common)

        // **And Wispr's own row**, the third witness and the only one that works
        // when nothing can hear the microphone.
        //
        // It used to be read **once**, at the microphone's close, and kept only
        // if its `startedAt` was this dictation's. Polled from the gesture
        // instead, because the row is *created* at the gesture: its appearance is
        // itself the confirmation that Wispr took the chord, which is the fact
        // `speculativeGrace` needs and the CoreAudio edge stopped being able to
        // give. What has to be guarded against is the opposite mistake — reading
        // the *previous* dictation's finished row as this one's answer and ending
        // every settle on the first tick — so the row that was on top when this
        // was armed is remembered and refused, unless it was still open.
        let prior = WisprHistory.newest()
        priorRow = prior?.rowid
        priorRowWasOpen = prior.map { !WisprState.isTerminal($0.status) } ?? false
        historyRow = nil
        historyFormattedAt = 0
        relayDismissedAt = 0
        pidAtAdoption = 0
        // **The note as it stood before he started talking**, so a Scratchpad
        // that is appended to rather than added to is still recognisable.
        scratchpadWindowHandled = false
        if startedMode == .scratchpad, let note = WisprNotes.newest() {
            priorNoteId = note.id
            priorNoteStamp = max(note.createdAt, note.modifiedAt)
            priorNoteText = note.content
        } else {
            priorNoteId = nil
            priorNoteStamp = 0
            priorNoteText = nil
        }
        // Batch 3 (2026-09-28): woken by Wispr's commits, not a 150 ms timer.
        historyWatch.subscribe(Self.captureWatchKey) { [weak self] in self?.pollHistory() }
        historyWatch.wake(after: 0)
    }

    /// **How long the words may take, counted from the last one.** The capture
    /// window opened at the gesture; this is the 30 s it is allowed to stand
    /// after the microphone shuts.
    private func armCaptureDeadline(after seconds: TimeInterval = captureTimeout) {
        captureDeadline?.cancel()
        let giveUp = DispatchWorkItem { [weak self] in self?.captureExpired() }
        captureDeadline = giveUp
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: giveUp)
    }

    /// **A capture whose row is not terminal belongs to a sentence still in
    /// flight**, and a new gesture does not get to disarm it.
    ///
    /// This is the second failure of 2026-09-13 in one method. A 🔼 click landed
    /// inside a settle, `onPasteToggle` asked only about `listening` and started
    /// a phantom dictation, and `gestureSeen`'s unconditional `endCapture` threw
    /// away the *first* sentence's swallow window — so Wispr's ⌘V, a second
    /// later, went into whatever Terminal happened to be in front. The click is
    /// now a stop (`AppDelegate.onPasteToggle`); this is the guard behind it, for
    /// the dictation Victor starts from his own keyboard while the last one is
    /// still being transcribed.
    private func retireCaptureIfSettled() {
        guard capturing else { return }
        // **A cancelled capture is not a sentence in flight, and a new gesture
        // supersedes it at once** (2026-09-14, the regression the
        // `discardOnArrival` fix left behind). The words of the old sentence
        // were thrown away by Victor; what is still owed is only that Wispr's
        // late ⌘V lands nowhere, and that survives the retirement on its own.
        if discardOnArrival { return retireDiscardedCapture() }
        if let row = historyRow, !WisprState.isTerminal(status(of: row)) {
            Log.info("wispr: a capture is still standing for row \(row) (\(status(of: row).isEmpty ? "no status yet" : status(of: row))) — the new gesture does not disarm it")
            return
        }
        endCapture(quiet: true)
    }

    /// **Retire a cancelled capture and keep only its swallow, keyed by its row.**
    ///
    /// Everything the capture *holds* goes back with it — the Scratchpad window,
    /// the keyboard guard, the sink's key window, the row poll, the deadline —
    /// because `endCapture` is the one place that lets all of them go, and the
    /// new dictation then arms its own inside the same call. What outlives it is
    /// the one promise the cancel made: Wispr may still press ⌘V for the
    /// sentence Victor threw away, and that key belongs to nobody.
    private func retireDiscardedCapture() {
        retiredDiscardRow = historyRow
        retiredDiscardPid = pidAtAdoption
        retiredDiscardUntil = CFAbsoluteTimeGetCurrent() + Self.retiredDiscardCeiling
        retiredDiscardTerminalAt = 0
        Log.info("🗑️ a new gesture supersedes the cancelled sentence — its capture is retired now"
                 + (retiredDiscardRow.map { ", and the swallow stays armed for row \($0)'s ⌘V" }
                    ?? "; Wispr never created a row for it, so there is no ⌘V to wait for"))
        endCapture(quiet: true)
        // **Armed again, because `endCapture` disarmed it and the dictation that
        // follows may not want one.** A capture the relay is not intercepting —
        // Victor's own chord, a moment after his cancel — arms no swallow at
        // all, and the old row's ⌘V would then land in his document, which is
        // the whole failure the cancel path exists to prevent.
        if retiredDiscardRow != nil { hotkeys.armInjectionCapture(swallow: true) }
        armRetiredDiscardWatch()
    }

    /// The claim is let go on the row's own evidence: terminal, plus the
    /// `pasteGrace` in which the ⌘V that follows `formatted` would have arrived.
    private static let retiredWatchKey = "retired-discard"

    private func armRetiredDiscardWatch() {
        historyWatch.unsubscribe(Self.retiredWatchKey)
        guard retiredDiscardRow != nil else { return }
        // Batch 3: on Wispr's commits (`WisprHistoryWatch`), plus the ceiling's own wake.
        historyWatch.subscribe(Self.retiredWatchKey) { [weak self] in self?.pollRetiredDiscard() }
        historyWatch.wake(after: Self.retiredDiscardCeiling + 0.05)
    }

    private func pollRetiredDiscard() {
        guard let row = retiredDiscardRow else { return letRetiredDiscardGo("there was no row to wait for") }
        let now = CFAbsoluteTimeGetCurrent()
        guard now < retiredDiscardUntil else {
            return letRetiredDiscardGo("row \(row) produced no ⌘V within \(Int(Self.retiredDiscardCeiling)) s")
        }
        // **Asked about the row itself**, not about the newest one: by now the
        // next dictation has a row of its own on top of it.
        guard let e = WisprHistory.entry(rowid: row) else { return }
        guard WisprState.isTerminal(e.status) else {
            // Batch 3: a row Wispr will never finish produces no ⌘V either.
            if let dead = WisprState.deadRow(.init(rowid: row, status: e.status, duration: e.duration,
                                                   newestRowid: WisprHistory.newest()?.rowid ?? row,
                                                   pidNow: Self.wisprMainPid, pidAtAdoption: retiredDiscardPid,
                                                   closedAt: lastStopAt, now: now)) {
                letRetiredDiscardGo(dead)
            }
            return
        }
        if retiredDiscardTerminalAt == 0 {
            retiredDiscardTerminalAt = now
            historyWatch.wake(after: Self.pasteGrace + 0.02)
            return
        }
        guard now - retiredDiscardTerminalAt >= Self.pasteGrace else { return }
        letRetiredDiscardGo("row \(row) is \(e.status) and no ⌘V followed it")
    }

    private func letRetiredDiscardGo(_ why: String) {
        historyWatch.unsubscribe(Self.retiredWatchKey)
        retiredDiscardTerminalAt = 0
        guard retiredDiscardRow != nil else { return }
        retiredDiscardRow = nil
        Log.info("🗑️ the cancelled sentence's claim on the swallow is let go — \(why)")
        // The swallow belongs to the running capture again — or to nobody.
        if !(capturing && intercepting) { hotkeys.disarmInjectionCapture() }
    }

    /// **Close the Scratchpad as soon as the cancel has had its answer, not when
    /// the capture ends** (2026-09-14).
    ///
    /// `closeListening` already asked for the close at the stop and the window
    /// went; Wispr then **reopens** it when it writes its note, ~2 s later, and
    /// nothing was watching for that second window until `endCapture` — which a
    /// cancelled sentence does not reach until Wispr has finished transcribing
    /// the words nobody wants. Measured **3.2 s** with the window standing over
    /// his work and taking his keystrokes throughout. So the moment the cancel
    /// has its answer — the row is terminal, or the dismiss is old enough that
    /// no ⌘V can still follow it — the close is armed again.
    ///
    /// **Exactly once while one is in flight**: the close is a toggle, and the
    /// second ask re-opens what the first shut.
    private func armDiscardClose() {
        guard startedMode == .scratchpad else { return }
        // Batch 3: on Wispr's commits, plus a wake at the grace's end.
        historyWatch.subscribe(Self.discardCloseKey) { [weak self] in self?.pollDiscardClose() }
        historyWatch.wake(after: Self.pasteGrace + 0.02)
    }

    private func pollDiscardClose() {
        guard capturing, discardOnArrival else { return endDiscardClose() }
        guard !WisprScratchpad.closeIsInFlight else { return }
        let waited = CFAbsoluteTimeGetCurrent() - dismissedAt
        var why: String?
        if let row = historyRow, let e = WisprHistory.entry(rowid: row), WisprState.isTerminal(e.status) {
            why = "Wispr's row \(row) is \(e.status)"
        } else if waited >= Self.pasteGrace {
            why = "the dismiss went out and no ⌘V can follow it"
        }
        guard let why else { return }
        endDiscardClose()
        scratchpadWindowHandled = true
        Log.info(String(format: "🗒️ %@ — closing the Scratchpad now rather than at the end of the capture (%.0f ms after the cancel)",
                        why, waited * 1000))
        WisprScratchpad.armCloseOnSight()
    }

    private func endDiscardClose() {
        historyWatch.unsubscribe(Self.discardCloseKey)
    }

    private func status(of row: Int64) -> String {
        WisprHistory.entry(rowid: row)?.status ?? ""
    }

    /// **What Wispr says about this dictation.** `status` stays empty while it
    /// works; the first non-empty value is the end of the round trip, whatever
    /// the tap saw. `formatted` waits `pasteGrace` for the ⌘V that usually
    /// follows — the ordinary paths deliver and close the capture underneath
    /// this timer — and only then takes the words from the row: Wispr put them
    /// where the focus was, by a route no tap sees, and `insertedElsewhere`
    /// lets the router decide whether that was the destination.
    private func pollHistory() {
        guard capturing else { return }
        // **The recogniser has quit and nothing is coming** (2026-09-14,
        // adversarial round 2, Finding 5). Wispr killed mid-settle left the
        // relay holding `Transcribing...` for the full 30 s of `captureTimeout`
        // before it said `No words came back` — thirty seconds of a chip
        // promising words from a process that no longer exists. Two consecutive
        // ticks, because `runningApplications` is KVO-updated and a single blank
        // reading during Wispr's own relaunch is not a death.
        let pid = Self.wisprMainPid
        if pid == 0 {
            sawWisprGone += 1
            if sawWisprGone >= 2 { return abandonForDeadWispr("it is not running") }
        } else if wisprPidAtChord != 0, pid != wisprPidAtChord {
            return abandonForDeadWispr("it is pid \(pid) now, and this sentence was given to pid \(wisprPidAtChord)")
        } else {
            sawWisprGone = 0
        }
        let wasDiscarding = discardOnArrival
        // **The note is never the delivered text in Scratchpad mode, and that is
        // now a rule rather than a default** (2026-09-14). Two runs delivered
        // `added 'qz'` — a pair of probe *keystrokes* that had landed in the note
        // — as though they were the sentence. A note that has had his typing in
        // it is not a transcript, and the row is the only thing that ever was.
        // `WT_SCRATCHPAD_DELIVER=note` is kept for the non-Scratchpad modes and
        // for looking at the other record by hand; it no longer decides anything
        // in the mode that ships.
        //
        // It was read unconditionally for one build, and that build delivered a
        // stray `z` (2026-09-13, 23:52): the window is open for the whole
        // sentence, a keystroke that lands in the note changes it, and the note
        // poll fired **13 ms after the microphone closed** — before the row was
        // even `formatted` — and shipped the one character it found. The note
        // has to be a cross-check or it is a second delivery racing the first.
        if startedMode == .scratchpad, Self.deliverFromNote, Self.noteMayDeliver,
           intercepting, !isRecording, pollNote() { return }
        // **After adoption the capture reads its own row, never the newest**
        // (W4, 2026-09-28): his own right ⌥⇧ sentence makes a newer row, which
        // used to hide the relay's — its sentence then waited out the timeout.
        guard let e = historyRow.flatMap({ WisprHistory.entry(rowid: $0) }) ?? WisprHistory.newest() else { return }

        // **Adopting the row.** Anything that is not the row that was on top when
        // this was armed, and was created at or after the gesture, is this
        // dictation's — unless that top row was still open, in which case it is
        // this dictation's and was simply created before the first tick.
        if historyRow == nil {
            let isNew = e.rowid != priorRow || priorRowWasOpen
            guard isNew, e.startedAt >= openedAt - 2 else { return }
            historyRow = e.rowid
            pidAtAdoption = pid
            // Rowids only grow in one file: lower than a row already pasted for
            // him means another file (a `WT_WISPR_DB` switch) — its guard is void.
            if e.rowid < lastForeignRow { lastForeignRow = 0 }
            if relayStarted { ownedRow = e.rowid }
            namedMic = ""
            Log.info(String(format: "wispr history: row %d is this dictation's — %.0f ms after the chord (%@)",
                            e.rowid, (CFAbsoluteTimeGetCurrent() - armedAt) * 1000,
                            e.micDevice.isEmpty ? "no device named yet" : e.micDevice))
            // The row exists, so Wispr took the chord — whatever the microphone
            // signals did or did not see.
            confirmSpeculative(by: "Wispr's own row")
        }
        guard e.rowid == historyRow else { return }
        // Batch 5: a close waiting on the exit, and Wispr's row moved — its stop
        // path ran, so Wispr is alive and ended the dictation itself.
        if pendingWisprEnded != nil, !e.status.isEmpty, wisprGone() == nil {
            resolveWisprClose(rowMoved: true)
            guard capturing else { return }
        }
        if !e.micDevice.isEmpty, e.micDevice != namedMic {
            namedMic = e.micDevice
            micNamed?(e.micDevice)
        }
        // **Only while this capture is the current chord's.** A capture left
        // standing for the previous sentence (`retireCaptureIfSettled`) goes on
        // polling its own row, and feeding that row's terminal status into a
        // machine that is describing the *new* dictation would put it straight
        // into `done` before Wispr had heard a word of it.
        // …and **not for a sentence that has been cancelled**: the poll goes on
        // running so the ⌘V can be swallowed, but a row fed into the machine
        // would put the phase back into `transcribing` a tick after the cancel
        // reset it, and the next gesture would be refused all over again.
        if armedAt >= state.chordAt, !discardOnArrival { state.sawRow(e.rowid, status: e.status) }

        let took = (CFAbsoluteTimeGetCurrent() - captureFrom) * 1000
        // `wisprLive.rowSeen`: when the reader saw this row change (the desk
        // measures the WAL watch's latency against its own write with it).
        if rowSeen?.rowid != e.rowid || rowSeen?.status != e.status {
            rowSeen = (e.rowid, e.status, Date())
        }
        switch e.status {
        // **Intermediate, and they are progress rather than silence** — `""`
        // (NULL, the row as created at the gesture) and `processing` (after the
        // stop). Bounded by the dead-row verdict below and by `workingCeiling`.
        // **W2 (2026-09-28): a row with no microphone behind it is not a
        // recording.** Wispr sometimes takes the chord, writes its row and never
        // opens the microphone (100 NULL rows in September); the relay waited
        // the whole 30 s for it. Closed, still NULL, never a microphone:
        // Wispr heard nothing — the relay's own recording stands in (Q14).
        case let s where s.isEmpty && !isRecording && !micSeen && took >= Self.nullNoMicCeiling * 1000:
            Log.error(String(format: "wispr history: row %lld is still NULL %.1f s after the close and Wispr never opened its microphone — Wispr did not hear this sentence", e.rowid, took / 1000))
            let row = e.rowid
            endCapture(quiet: true)
            if !wasDiscarding { endWithRecording("Wispr Flow never opened its microphone", row: row) }
            // **…and a Wispr listening on that row now is dismissed** (2026-10-02,
            // 11:07): its start was lost and the stop chord started it — row 18220,
            // written at the stop, still NULL with Wispr's microphone open, and
            // nothing else would ever end it. After the sentence ended, as in
            // `verifyStopTook`. Only the row on top: a newer one is his own.
            if WisprHistory.newest()?.rowid == row, watch.sampleIsRunningInput() {
                Log.error("wispr: Wispr is listening on row \(row), which the relay has given up on — "
                          + "its stop chord started it; dismissed (⌃Escape)")
                relayDismissedAt = CFAbsoluteTimeGetCurrent()
                HotkeyTap.postWisprCancel()
            }
            return
        case let s where WisprState.intermediateStatuses.contains(s):
            // **Batch 3 (2026-09-28): a row Wispr will never finish is dead now,
            // not at 30 s — nor, under Q24, never.** Superseded by a newer row,
            // another Wispr pid, still open 1 s after the relay's own dismiss, or
            // NULL with no `duration` 3 s after the close (`WisprState.deadRow`,
            // from Wispr's own code). The relay's recording stands in (Q14).
            guard !isRecording, !speculative else { return }
            let closed = Date().timeIntervalSince1970 - (CFAbsoluteTimeGetCurrent() - captureFrom)
            let facts = WisprState.RowFacts(
                rowid: e.rowid, status: s, duration: e.duration,
                newestRowid: WisprHistory.newest()?.rowid ?? e.rowid,
                pidNow: pid, pidAtAdoption: pidAtAdoption,
                dismissedAt: relayDismissedAt > 0
                    ? Date().timeIntervalSince1970 - (CFAbsoluteTimeGetCurrent() - relayDismissedAt) : 0,
                closedAt: closed,
                // Asked only when the rest of the NULL rule already holds: one CoreAudio read.
                wisprMicOpen: s.isEmpty && e.duration == nil && took > WisprState.nullStopCeiling * 1000
                    ? watch.sampleIsRunningInput() : false,
                now: Date().timeIntervalSince1970)
            guard let dead = WisprState.deadRow(facts) else { return }
            Log.error(String(format: "wispr history: %@ — the sentence ends now, %.1f s after the close (batch 3)", dead, took / 1000))
            let row = e.rowid
            endCapture(quiet: true)
            if !wasDiscarding { endWithRecording("Wispr Flow will not finish row \(row)", row: row, dismissedAt: facts.dismissedAt) }
            return

        case let s where WisprState.pasteableStatuses.contains(s)
                && e.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && startedMode != .scratchpad && intercepting:
            // **Batch 3 (2026-09-28): a final row with no words is `empty`, not
            // a wait.** `raw_transcript` was read as progress and an empty one
            // sat out `silenceCeiling` (8 s); a `formatted` with no text went
            // out as *No words detected*. Both are Wispr having heard nothing:
            // the relay's own recording stands in (Q14) — local model or Recover.
            Log.info(String(format: "wispr history: %@ with no words %.0f ms after the microphone closed — Wispr heard nothing; the relay's recording stands in (Q14)",
                            s, took))
            let row = e.rowid
            endCapture(quiet: true)
            if !wasDiscarding { endWithRecording("Wispr Flow reported \(s) with no words", row: row) }
            return

        case let s where WisprState.pasteableStatuses.contains(s):
            // **A dictation the relay did not start is over here and nothing
            // else happens.** It was Wispr's from the chord; the row is how the
            // ring and the chip find out it is finished, and `.silent("")` is
            // *nothing worth a banner* rather than a failure.
            guard intercepting else {
                Log.info(String(format: "wispr history: %@ — Victor's own dictation, delivered by Wispr (%.0f ms)",
                                e.status, took))
                endCapture(quiet: true)
                didEnd?(.silent(""))
                return
            }
            // **Wispr's take against the relay's** (2026-09-29): a row that
            // recorded seconds past the relay's close means that close was not
            // Wispr's end — the relay's own take, and anything decoded ahead from
            // it, is short by that much (12:20: 8.7 s against 2.8 s).
            if let d = e.duration, spokenFor > 0, d - spokenFor > 2 {
                Log.error(String(format: "wispr history: row %lld recorded %.1f s, the relay closed its take at %.1f s — "
                                 + "Wispr went on %.1f s past the relay's close",
                                 e.rowid, d, spokenFor, d - spokenFor))
            }
            // **In Scratchpad mode the row is the delivery and the note is the
            // cross-check** (2026-09-13, after the first working run).
            //
            // Measured on that run: the row said `formatted` **531 ms** after
            // the microphone closed, and the note was not readable until
            // **2627 ms** — Wispr writes the note when it opens its window, two
            // seconds later, and closing that window cost another 663 ms on top.
            // Waiting for the note therefore made the mode 2.8 s slower than the
            // ⌘V it replaced, for a copy of the same sentence.
            //
            // The note is where Wispr *pastes*; the row is where Wispr *writes
            // what it heard*. So the words come from the row the instant it is
            // terminal, the window is dealt with afterwards on its own time, and
            // the note is read at the end only to say whether the two agree.
            // `WT_SCRATCHPAD_DELIVER=note` goes back to waiting for the note.
            if startedMode == .scratchpad, !Self.deliverFromNote {
                deliverFromRow(e, took: took)
                return
            }
            if startedMode == .scratchpad {
                if historyFormattedAt == 0 {
                    historyFormattedAt = CFAbsoluteTimeGetCurrent()
                    Log.info(String(format: "wispr history: %@ %.0f ms after the microphone closed (Wispr's own e2e %.0f ms) — waiting for the Scratchpad note",
                                    e.status, took, e.e2eLatency))
                }
                return
            }
            // **The row as the delivery, with no ⌘V ever arriving.** Nothing to
            // wait for when Wispr cannot insert: the words are in the row, and
            // the relay is the only one who is going to put them anywhere.
            if historyIsTheRoute {
                Log.info(String(format: "wispr history: %@ %.0f ms after the microphone closed (Wispr's own e2e %.0f ms) — the row is the delivery",
                                e.status, took, e.e2eLatency))
                deliver(reason: "Wispr's History row", via: "wispr-history",
                        delivery: .route, text: e.text)
                return
            }
            if historyFormattedAt == 0 {
                historyFormattedAt = CFAbsoluteTimeGetCurrent()
                Log.info(String(format: "wispr history: %@ %.0f ms after the microphone closed (Wispr's own e2e %.0f ms) — giving the ⌘V %.1f s",
                                e.status, took, e.e2eLatency, Self.pasteGrace))
                historyWatch.wake(after: Self.pasteGrace + 0.02)
                return
            }
            guard CFAbsoluteTimeGetCurrent() - historyFormattedAt >= Self.pasteGrace else { return }
            Log.info("wispr history: no ⌘V and no pasteboard after \(e.status) — Wispr inserted it into \(e.app) by a route the tap cannot see")
            deliver(reason: "Wispr's History row", via: "wispr-history",
                    delivery: .insertedElsewhere, text: e.text)
        case "dismissed":
            Log.info(String(format: "wispr history: dismissed — %.0f ms after the microphone closed", took))
            endCapture(quiet: true)
            // A sentence already cancelled has had its ending; a second one
            // would clear the *next* dictation's state from under it.
            if !wasDiscarding { endCancelledWithRecording() }
            return
        case "empty", "no_audio":
            Log.info(String(format: "wispr history: %@ — %.0f ms after the microphone closed", e.status, took))
            let row = e.rowid
            endCapture(quiet: true)
            if !wasDiscarding { endWithRecording("Wispr Flow reported \(e.status)", row: row) }
        default:
            // A status nobody has seen ends the dictation rather than hanging it
            // — today's behaviour, kept — but it says so, because the alternative
            // reading (unknown = progress) turns one new Wispr status into every
            // sentence waiting out thirty seconds.
            Log.error(String(format: "wispr history: %@ — %.0f ms after the microphone closed", e.status, took))
            let row = e.rowid
            endCapture(quiet: true)
            if !wasDiscarding { endWithRecording("Wispr Flow reported \(e.status)", row: row) }
        }
    }

    /// **A NULL row with no microphone ever seen gives up after this**, counted
    /// from the close (W2; Q2 keeps it fast). A real sentence's row leaves NULL
    /// within ~0.5 s of the close (`processing`); 3 s is six times that.
    private static let nullNoMicCeiling: TimeInterval = 3

    private func noteMicSeen() {
        guard !micSeen, isRecording || speculative else { return }
        micSeen = true
        micOpened?()
    }

    /// **Wispr is out of this sentence; the relay's own recording carries it to
    /// HIS stop** (batch 4, 2026-09-29). Two ways in: Wispr never answered the
    /// chord (the 12 s `speculativeGrace`, F1) and Wispr quit mid-sentence (item
    /// 3 — TQ2's recording was cut at the kill, 1.0 s voiced, Recover only).
    /// Neither is his stop, so neither may end what he is saying: the capture
    /// (row poll, ⌘V swallow) is let go — Wispr has nothing more to give — while
    /// the meter goes on recording, `isRecording` stays true and `phase` says
    /// `.listening`. His stop (`stop()` → `closeListening`, no chord posted)
    /// closes it the way every close does — the recipient latched then (Q2) —
    /// and `endWithRecording` hands the take to the local model (Q14). A cancel
    /// or ⌘⌃X still works on it. True when it took the sentence.
    @discardableResult
    private func holdOwnTake(_ why: String) -> Bool {
        guard ownTakeOnly == nil, relayStarted, isRecording || speculative, !cancelling, !handingToLocal
        else { return false }
        speculativeDrop?.cancel()
        speculativeDrop = nil
        dropPendingWisprClose()
        if HotkeyTap.scratchpadIsHeld { HotkeyTap.postWisprScratchpad(down: false) }
        // Set before the capture's end, which then neither re-arms a capture for
        // this sentence nor puts the machine to rest under it: the machine stays
        // where it was (the music stays paused, the relay keeps owning Wispr's
        // ⌘V) until his stop moves it on.
        ownTakeOnly = why
        ownTakeSince = CFAbsoluteTimeGetCurrent()
        speculative = false
        isRecording = true
        endCapture(quiet: true)
        Log.error(String(format: "💻 %@ — %.1f s into the sentence: the relay's own recording carries it on until his stop, then this Mac transcribes it (Q14; batch 4)",
                         why, ownTakeSince - gestureAt))
        onOwnTake?(why)
        return true
    }
    /// The Wispr-side close (poll, CoreAudio edge) of any sentence waits up
    /// to `WisprState.quitCloseGrace` for the exit before it is taken as Wispr
    /// ending the dictation: a quit closes the microphone too (item 3, batch 5).
    private var pendingWisprClose: DispatchWorkItem?

    /// **Q14 (2026-09-28): a Wispr failure is not the end of the sentence** —
    /// the relay recorded it too (`startMeter`). ≥ `fallbackVoicedFloor` voiced
    /// (the Q8/Q13 floor, 1.5 s) → `.failed` with the WAV, which
    /// `AppDelegate.fallBackToLocal` hands to the local model and delivers to
    /// the latched destination (`via: local-fallback`); some speech under the
    /// floor → Recover (`heardNothing`); none → *No speech was heard*, the only
    /// time that is said (the meter agrees). The row it gave up on is watched,
    /// owned, until it goes terminal, so a late row is logged and its ⌘V
    /// dropped — never a second delivery (Q2).
    private func endWithRecording(_ why: String, row: Int64?, forced: Bool = false, dismissedAt: Double = 0) {
        // Read now, on main: the next sentence's gesture moves them.
        let pid = pidAtAdoption
        // **Wispr never heard a word of it** (2026-10-08): then the floor is only
        // *some speech* (0.3 s), not 1.5 s — the 14:33:54 sentence had 1.2 s
        // voiced, Recover decoded 40 chars from it, and it was dropped. The
        // 1.5 s floor guards a sentence Wispr did hear and mangled.
        let floor = micSeen ? ElevenLabsSource.fallbackVoicedFloor : 0.3
        let closed = lastStopAt > 0 ? Date().timeIntervalSince1970 - (CFAbsoluteTimeGetCurrent() - lastStopAt) : 0
        meterQueue.async { [weak self] in
            guard let self else { return }
            let taken = self.recording
            self.recording = nil
            let voiced = self.recordingVoiced
            let recHealth = self.recordingHealth
            DispatchQueue.main.async {
                if let row { self.watchLateRow(row, pid: pid, closedAt: closed, dismissedAt: dismissedAt) }
                guard let taken, FileManager.default.fileExists(atPath: taken.url.path) else {
                    Log.error("wispr: \(why) — and the relay has no recording of it")
                    self.didEnd?(.silent(why))
                    return
                }
                if voiced >= floor {
                    Log.error(String(format: "wispr: %@ — %.1f s voiced on the relay's own recording: the local model %@",
                                     why, voiced, forced ? "takes it" : "stands in (Q14)"))
                    self.didEnd?(.failed(why: why, audio: taken.url, duration: taken.duration))
                } else if let health = recHealth, health.deaf {
                    // **A: nobody listened — not "no speech".** Kept for Recover.
                    Log.error(String(format: "wispr: %@ — the relay's own recording got NO AUDIO (%@): not 'no speech'; kept for Recover", why, health.line))
                    self.didEnd?(.failed(why: "\(DictationEnd.recorderDeaf) (\(health.device))", audio: taken.url, duration: taken.duration))
                } else if voiced < 0.3 {
                    // **A (2026-09-28): Wispr failed too, so the take is kept** —
                    // the meter's *no speech* is a judgement, and the lab showed it
                    // wrong 4× in a row; Recover costs nothing.
                    Log.info(String(format: "wispr: %@ — %.1f s voiced on the relay's own recording too (%@): kept for Recover", why, voiced, recHealth?.line ?? "no health"))
                    self.didEnd?(.failed(why: DictationEnd.heardNothing, audio: taken.url, duration: taken.duration))
                } else {
                    Log.error(String(format: "wispr: %@ — only %.1f s voiced (under %.1f s): no local fallback, the audio is kept for Recover", why, voiced, ElevenLabsSource.fallbackVoicedFloor))
                    self.didEnd?(.failed(why: DictationEnd.heardNothing, audio: taken.url, duration: taken.duration))
                }
            }
        }
    }

    /// **The row the relay gave up on stays owned until Wispr finishes it**
    /// (Q2/Q14): its ⌘V is dropped by the firewall and the row is only logged.
    ///
    /// **Batch 3 (2026-09-28): a dead row is let go at once.** A row Wispr will
    /// never finish (`WisprState.deadRow`: superseded, another pid, still open
    /// 1 s after the relay's dismiss, NULL with no duration 3 s after the close)
    /// produces no ⌘V; held for the whole `lateRowWatch` it made every Wispr ⌘V
    /// the relay's (`WisprOwnership.verdict`, `rowsHeld`) for five minutes.
    private func watchLateRow(_ row: Int64, pid: pid_t = 0, closedAt: Double = 0, dismissedAt: Double = 0) {
        hotkeys.holdWisprOwned(true)
        lateRow = row
        let until = Date().addingTimeInterval(Self.lateRowWatch)
        func tick() {
            if let e = WisprHistory.entry(rowid: row) {
                if WisprState.isTerminal(e.status) {
                    if lateRow == row { lateRow = nil }
                    Log.info("wispr history: late row \(row) came back \(e.status) (\(e.text.count) chars) after the relay had given up on it — only logged, never a second delivery (Q2)")
                    DispatchQueue.main.asyncAfter(deadline: .now() + Self.pasteGrace) { self.hotkeys.holdWisprOwned(false) }
                    return
                }
                let now = Date().timeIntervalSince1970
                let nullLong = e.status.isEmpty && e.duration == nil && closedAt > 0
                    && now - closedAt > WisprState.nullStopCeiling
                if let dead = WisprState.deadRow(.init(rowid: row, status: e.status, duration: e.duration,
                                                       newestRowid: WisprHistory.newest()?.rowid ?? row,
                                                       pidNow: Self.wisprMainPid, pidAtAdoption: pid,
                                                       dismissedAt: dismissedAt, closedAt: closedAt,
                                                       wisprMicOpen: nullLong ? watch.sampleIsRunningInput() : false,
                                                       now: now)) {
                    Log.info("wispr history: the row the relay gave up on is dead — \(dead); its hold on Wispr's ⌘V is let go (batch 3)")
                    hotkeys.holdWisprOwned(false)
                    if lateRow == row { lateRow = nil }
                    return
                }
            }
            guard Date() < until else {
                hotkeys.holdWisprOwned(false)
                if lateRow == row { lateRow = nil }
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { tick() }
        }
        tick()
    }
    private static let lateRowWatch: TimeInterval = 300

    /// The row the relay gave up on, while `watchLateRow` still owns it.
    private var lateRow: Int64?

    /// **Wispr Flow is still working on a take the relay gave up on** — the row,
    /// or nil (2026-10-06). It takes one sentence at a time: on 10:25:11 a start
    /// chord posted while row 18414 (handed to the local model by ⌘⌃X six seconds
    /// before) was still `processing` was ignored, and the sentence learnt so only
    /// 12 s later (`holdOwnTake`) — the local model by the back door. Read live
    /// off `History`: a row gone terminal or dead is not busy.
    var stillFinishingAbandonedRow: Int64? {
        guard let row = lateRow, let e = WisprHistory.entry(rowid: row),
              !WisprState.isTerminal(e.status) else { return nil }
        return row
    }

    /// **A cancelled Wispr sentence keeps the relay's recording for Recover**
    /// (W3, 2026-09-28) — it used to be deleted at the close (*nothing had been
    /// recorded yet*) or orphaned in Caches.
    private func endCancelledWithRecording() {
        meterQueue.async { [weak self] in
            guard let self else { return }
            let taken = self.recording
            self.recording = nil
            DispatchQueue.main.async {
                self.didEnd?(.cancelled(audio: taken?.url, duration: taken?.duration ?? 0))
            }
        }
    }

    // MARK: - E: the ghost microphone (lab wave 3, 2026-09-28)

    /// His own last Wispr chord the tap saw (unix time) — his, not a ghost.
    private var hisChordAt: Double = 0
    private var unansweredChordAt: Double = 0
    /// The relay's own last start chord (unix time) — `WisprOwnership.ghostMic`'s disarm.
    private var relayChordAt: Double = 0
    private var ghostWatch: Timer?
    /// A chip notice (English), wired to `overlay.flash` by `AppDelegate`.
    var onNotice: ((String) -> Void)?

    /// **After a relay chord Wispr never answered, watch 25 s for its microphone
    /// opening by itself** (E, lab wave 3: three times in one night, once held
    /// > 14 min, blocking every start and the restart gate). No sentence of the
    /// relay's open, no push-to-talk of his held (right ⌥⇧ `61+60`), no chord of
    /// his since (`WisprOwnership.ghostMic`) → it is the relay's own start,
    /// arriving late: dismissed with ⌃Escape, and the chip says so.
    private func armGhostWatch() {
        unansweredChordAt = Date().timeIntervalSince1970
        ghostWatch?.invalidate()
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let now = Date().timeIntervalSince1970
            guard now - self.unansweredChordAt < Self.ghostWindow else {
                timer.invalidate(); self.ghostWatch = nil; return
            }
            // A sentence of the relay's own is open: its microphone is not a ghost —
            // unless Wispr is out of it and the relay's own recording carries it
            // (batch 4): then a microphone of Wispr's is the late start itself.
            guard !self.speculative, !(self.isRecording && self.ownTakeOnly == nil) else { return }
            let his = CGEventSource.keyState(.combinedSessionState, key: 61)
                && CGEventSource.keyState(.combinedSessionState, key: 60)
            // E-FP: the relay's own capture still waiting for Wispr — that
            // microphone may be its sentence finishing after the relay's stop.
            let inFlight = self.capturing && self.relayStarted && !self.discardOnArrival
            guard let why = WisprOwnership.ghostMic(now: now, micOpen: self.watch.sampleIsRunningInput(),
                                                    relayRecording: false, unansweredAt: self.unansweredChordAt,
                                                    hisKeysHeld: his, hisChordAt: self.hisChordAt,
                                                    window: Self.ghostWindow, relayChordAt: self.relayChordAt,
                                                    relayCaptureInFlight: inFlight) else { return }
            timer.invalidate(); self.ghostWatch = nil
            self.unansweredChordAt = 0
            Log.error("👻 \(why) — dismissing it (⌃Escape)")
            HotkeyTap.postWisprCancel()
            self.onNotice?("👻 Wispr Flow opened its microphone late for a start it never answered — dismissed")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self else { return }
                Log.info("👻 the ghost microphone 1.5 s after the dismiss: " + (self.watch.sampleIsRunningInput() ? "STILL OPEN" : "closed"))
            }
        }
        ghostWatch = t
        RunLoop.main.add(t, forMode: .common)
    }
    private static let ghostWindow: Double = 25

    /// **Q19 (2026-09-28, Victor's Q7 = A): a dropped ⌘V may be his own
    /// sentence.** Q9 leaves his right ⌥⇧ sentences to Wispr, but while the
    /// relay's row is in flight the firewall cannot tell whose ⌘V it is. If the
    /// newest row is *newer than the relay's*, terminal with words, and fresh,
    /// it is his: pasted at the caret, where Wispr would have put it. Polled
    /// briefly — Wispr's ⌘V and its `formatted` land in no fixed order.
    ///
    /// **Batch 3 (2026-09-28): the pasteboard, once, as the last resort.** The
    /// row is read first, at the drop. Wispr pastes *before* its final write
    /// (p50 74 ms, p90 135 ms, max 1 s), so the row is often still NULL /
    /// `processing` then — while Wispr's own item is on the pasteboard, a
    /// delayed-render promise that is gone at its restore 500 ms later. So when
    /// the row has no words at the drop, `pasteboardString()` is read **then,
    /// once** (off main: the read runs Wispr's provider), and kept: the row's
    /// words still win if they arrive within the claim's 5 s; the pasteboard's
    /// are pasted only if they do not. Refused when the clipboard is still at
    /// the relay's own last write (Q17's sentence, not Wispr's). Whatever is
    /// pasted marks the row (`lastForeignRow`): never twice.
    private func claimForeignPaste(floor: Int64? = nil, relayHadRow: Bool = true, relayClosedAt: Double = 0) {
        guard let own = floor ?? historyRow ?? priorRow else {
            Log.info("🛡️ the dropped ⌘V: the relay has no row yet to tell his from — nothing claimed")
            return
        }
        // **Only a row that already exists can be the one this ⌘V pastes** —
        // Wispr creates the row at the gesture, long before its paste. A row
        // made *after* the drop is a later sentence whose own ⌘V is still to
        // come (and may pass the tap): claiming it here would paste it twice.
        guard let top = WisprHistory.newest() else {
            Log.info("🛡️ the dropped ⌘V: History could not be read — nothing claimed")
            return
        }
        guard top.rowid > own else {
            Log.info("🛡️ the dropped ⌘V is not his: the newest row \(top.rowid) is the relay's or older (floor \(own)) — the relay's own late ⌘V, nothing of his lost")
            return
        }
        guard top.rowid > lastForeignRow else {
            Log.info("🛡️ the dropped ⌘V is not his to paste: row \(top.rowid) was already pasted (by Wispr through the tap, or by the relay)")
            return
        }
        guard Date().timeIntervalSince1970 - top.startedAt < 120 else {
            Log.info("🛡️ the dropped ⌘V is not his: row \(top.rowid) is older than 120 s")
            return
        }
        if WisprOwnership.madeByRelayChord(startedAt: top.startedAt, chords: WisprOwnership.relayChordTimes) {
            Log.info("🛡️ the dropped ⌘V is not his: row \(top.rowid) opened within 1 s of one of the relay's own chords — the relay's (TX6b)")
            return
        }
        if !relayHadRow, top.startedAt < relayClosedAt.rounded(.down) {
            Log.info("🛡️ the dropped ⌘V is not his: row \(top.rowid) started before the relay's sentence closed — it may be the relay's own, created late (Q2 logs it)")
            return
        }
        let candidate = top.rowid
        let dry = CFAbsoluteTimeGetCurrent() < foreignClaimDryUntil
        func paste(_ text: String, from source: String, status: String) {
            guard candidate > lastForeignRow else { return }
            lastForeignRow = candidate
            Log.info("🛡️ the dropped ⌘V is row \(candidate) (\(status)), newer than the relay's \(own) — his own Wispr sentence (Q19), \(text.count) chars from \(source)")
            if dry {
                lastForeignClaim = ["row": candidate, "source": source, "chars": text.count, "at": Outbox.iso(Date())]
                Log.info("🧪 dry claim (POST /test/wispr-paste {dryClaim}) — row \(candidate)'s \(text.count) chars from \(source) NOT pasted")
                return
            }
            foreignSentence?(text)
        }
        let atDrop = WisprHistory.entry(rowid: candidate)
        let rowText = atDrop.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
        if let e = atDrop, WisprState.isTerminal(e.status), !rowText.isEmpty {
            return paste(rowText, from: "the row", status: e.status)
        }
        // The row has no words yet: Wispr's promised item is on the pasteboard
        // now and only now. One read, off main, kept for the end of the claim.
        var board: String?
        var boardRead = false
        let ownCount = PasteboardTimeline.lastOwnCount
        DispatchQueue.global(qos: .userInitiated).async {
            let count = Clipboard.changeCount
            let text = count == ownCount ? nil : Self.pasteboardString()
            DispatchQueue.main.async {
                board = text?.trimmingCharacters(in: .whitespacesAndNewlines)
                boardRead = true
                Log.info("🛡️ the dropped ⌘V: row \(candidate) has no words yet — the pasteboard read once: "
                         + (count == ownCount ? "still the relay's own write (Q17), not used"
                            : "\(board?.count ?? 0) chars kept as the last resort"))
            }
        }
        var tries = 0
        func attempt() {
            tries += 1
            if let e = WisprHistory.entry(rowid: candidate), WisprState.isTerminal(e.status) {
                let text = e.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { return paste(text, from: "the row", status: e.status) }
                if boardRead, let b = board, !b.isEmpty {
                    return paste(b, from: "the pasteboard (row \(e.status) with no words)", status: e.status)
                }
                if boardRead || tries >= Self.claimTries {
                    Log.info("🛡️ the dropped ⌘V is row \(e.rowid) (\(e.status)), his — and empty: nothing to paste")
                    return
                }
            }
            if tries < Self.claimTries {
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.claimTick, execute: attempt)
                return
            }
            if let b = board, !b.isEmpty {
                return paste(b, from: "the pasteboard (the row still unfinished after \(String(format: "%.0f", Double(tries) * Self.claimTick)) s)", status: "unfinished")
            }
            Log.error("🛡️ the dropped ⌘V is his row \(candidate), still unfinished after \(String(format: "%.0f", Double(tries) * Self.claimTick)) s — left in Wispr's History (⌘⌃W pastes it)")
        }
        attempt()
    }
    /// **`POST /test/wispr-paste {"dryClaim": true}`** (batch 3): for 10 s the
    /// claim decides and logs but pastes nothing — the desk has no caret to
    /// spare. `wisprLive.lastForeignClaim` says what it would have pasted.
    var foreignClaimDryUntil: CFAbsoluteTime = 0
    private(set) var lastForeignClaim: [String: Any]?
    /// Wispr's ⌘V and its `formatted` land in no fixed order, and under load the
    /// row lags by seconds: 5 s of looking.
    private static let claimTries = 20
    private static let claimTick: TimeInterval = 0.25

    // MARK: - B: the tail watch (lab wave 2, 2026-09-28)

    /// This relay sentence's adopted row, and the row on top at its chord.
    private var ownedRow: Int64?
    private var ownedFloor: Int64 = 0
    /// Unix time the relay's sentence closed (its stop), 0 while open.
    private var relayClosedWall: Double = 0
    /// Set at the relay's gesture, spent by the idle transition that follows.
    private var tailArmed = false
    private var tailWatch: Timer?
    /// The last relay sentence's rows, kept for a ⌘V dropped after it (`injected`).
    private var tailFloor: (floor: Int64, hadRow: Bool, closedAt: Double)?
    private static let tailWatchFor: TimeInterval = 10.5

    /// **After the relay's sentence goes idle, watch for his newer row** (B).
    /// The firewall's 10 s tail drops Wispr's ⌘V as the relay's late paste; the
    /// moment the newest row is his (`WisprOwnership.rowIsHis`), the tap is told
    /// and his ⌘V passes — Wispr pastes it at the caret, as Q9 says.
    private func startTailWatch() {
        guard tailArmed else { return }
        tailArmed = false
        tailWatch?.invalidate()
        let floor = max(ownedRow ?? 0, ownedFloor)
        let hadRow = ownedRow != nil
        let closed = relayClosedWall > 0 ? relayClosedWall : Date().timeIntervalSince1970
        tailFloor = (floor, hadRow, closed)
        let released = CFAbsoluteTimeGetCurrent()
        let sentenceArmedAt = armedAt
        let t = Timer(timeInterval: 0.2, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let since = CFAbsoluteTimeGetCurrent() - released
            guard since < Self.tailWatchFor else { timer.invalidate(); self.tailWatch = nil; return }
            // A row the relay already pasted for him (a claim) must not pass the tap too.
            guard let e = WisprHistory.newest(), e.rowid > self.lastForeignRow,
                  WisprOwnership.rowIsHis(rowid: e.rowid, startedAt: e.startedAt, floor: floor, relayHadRow: hadRow,
                                          relayClosedAt: closed, relayCmdVSeen: self.lastCmdVAt >= sentenceArmedAt,
                                          sinceRelease: since,
                                          relayChords: WisprOwnership.relayChordTimes) else { return }
            self.hotkeys.noteForeignWisprRow(e.rowid)
            Log.info(String(format: "🛡️ row %lld (%@) is his, not the relay's (%@), %.1f s into the tail — a Wispr ⌘V passes now (B)",
                            e.rowid, e.status.isEmpty ? "open" : e.status,
                            hadRow ? "its row \(floor)" : "it had no row; newest at its chord \(floor)", since))
            timer.invalidate()
            self.tailWatch = nil
        }
        tailWatch = t
        RunLoop.main.add(t, forMode: .common)
    }
    private var lastForeignRow: Int64 = 0

    // `rawTextSettled` (2026-09-22) read a `raw_transcript` row with words in
    // it as `formatted` after 0.8 s of stillness. Batch 3 (2026-09-28) deleted
    // it: Wispr writes `raw_transcript` only in its final update
    // (`integration-surfaces.md`, item 3), so it is terminal — delivered at once.


    /// **Wispr Flow's own process, matched on the anchored executable path.**
    ///
    /// Not the bundle identifier and not the name: LaunchServices resolves both
    /// to the nested Accessibility helper at
    /// `…/Contents/Resources/swift-helper-app-dist/Wispr Flow.app` as well, so a
    /// check written on either reports Wispr running when only the helper is —
    /// the same trap `open -a "Wispr Flow"` is in *Never reintroduce* for.
    static var wisprMainPid: pid_t {
        NSWorkspace.shared.runningApplications.first {
            $0.executableURL?.path == mainExecutable
        }?.processIdentifier ?? 0
    }
    private static var wisprMainIsRunning: Bool { wisprMainPid != 0 }
    private static let mainExecutable = "/Applications/Wispr Flow.app/Contents/MacOS/Wispr Flow"
    private var sawWisprGone = 0
    /// **Which Wispr this sentence was given to**, read at the chord.
    ///
    /// Absence is not the only way a recogniser dies, and on this rig it is not
    /// even the likely one: the harness relaunches Wispr **200 ms** after killing
    /// it, so a rule built on two consecutive absences 300 ms apart never sees
    /// the death at all — which is why `wispr-dies-mid-settle` still waited out
    /// its 30 s on the build that was supposed to have fixed it. A **different
    /// pid** is the same fact and it cannot be missed: the process this sentence
    /// was dictated into is gone, whatever is running now has never heard of it.
    private var wisprPidAtChord: pid_t = 0

    /// **Wispr's microphone closed under a relay sentence — a quit, or Wispr
    /// ending the dictation itself?** (batch 4, item 3; batch 5.) TQ2 / TW20 in
    /// the lab: the kill closed Wispr's microphone and the relay's own recording
    /// stopped there — Recover only, the rest of what he said never recorded.
    /// Wave 5 (batch 4 in): the same, because the exit event came 0.35–0.39 s
    /// after the poll's close and the 0.3 s grace had already closed the take.
    ///
    /// Now: a process the kernel already says is exiting (`P_WEXIT`) is a quit at
    /// once; otherwise **nothing is told** — not the machine, not the recorder —
    /// until `WisprState.wisprCloseDue` decides: the exit event (or a dying
    /// process) inside `WisprState.quitCloseGrace` → `abandonForDeadWispr` →
    /// `holdOwnTake`, the relay records on to his stop; Wispr's row moving, or
    /// the grace running out with Wispr alive → `wisprEnded`, which is what this
    /// close path did before item 3. Several close paths during one grace share
    /// it; his own stop, a cancel or the take being held drop it.
    private func closeFromWisprSide(_ why: String, wisprEnded: @escaping () -> Void) {
        guard !cancelling, ownTakeOnly == nil else { return wisprEnded() }
        let gone = wisprGone()
        switch state.wisprSideClose(by: why, processGone: gone != nil) {
        case .quit:
            abandonForDeadWispr("\(gone ?? "its exit came first") — its microphone closed with it (\(why))")
        case .wisprEnded:
            noteWisprSideClose()
            wisprEnded()
        case .pending(let until):
            if let earlier = pendingWisprEnded {
                // A second witness of the same close: one grace, both answers.
                pendingWisprEnded = { earlier(); wisprEnded() }
                Log.info("⏳ \(why) too — the same close, the same grace")
                return
            }
            pendingWisprEnded = wisprEnded
            Log.info(String(format: "⏳ %@ under a relay sentence, Wispr pid %d still alive — up to %.1f s for its exit before this is Wispr ending the dictation (batch 5)",
                            why, wisprPidAtChord, WisprState.quitCloseGrace))
            armWisprCloseDue(until)
        }
    }

    private func armWisprCloseDue(_ until: CFAbsoluteTime) {
        pendingWisprClose?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.resolveWisprClose() }
        pendingWisprClose = w
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, until - CFAbsoluteTimeGetCurrent()) + 0.005, execute: w)
    }

    /// **The waiting close, decided** — at its deadline, or early when Wispr's row
    /// moved (`rowMoved`: its stop path ran, so it is alive).
    private func resolveWisprClose(rowMoved: Bool = false) {
        guard let ended = pendingWisprEnded else { return }
        guard isRecording || speculative, ownTakeOnly == nil else { return dropPendingWisprClose() }
        if rowMoved { state.wisprAliveAfterClose() }
        let gone = wisprGone()
        switch state.wisprCloseDue(processGone: gone != nil) {
        case .pending(let until):
            armWisprCloseDue(until)
        case .quit:
            dropPendingWisprClose()
            abandonForDeadWispr("\(gone ?? "its exit came") — its microphone closed with it (\(state.wisprCloseBy))")
        case .wisprEnded where !rowMoved && nullRowHold():
            return
        case .wisprEnded:
            dropPendingWisprClose()
            Log.info(rowMoved
                     ? "⏳ Wispr's row moved after the close — Wispr is alive and ended the dictation itself"
                     : String(format: "⏳ Wispr outlived the %.1f s grace — it ended the dictation itself (%@)",
                              WisprState.quitCloseGrace, state.wisprCloseBy))
            noteWisprSideClose()
            ended()
        }
    }

    private func dropPendingWisprClose() {
        pendingWisprClose?.cancel()
        pendingWisprClose = nil
        pendingWisprEnded = nil
        nullRowHoldSaid = false
    }

    /// **A close Wispr's row does not confirm is not Wispr's end** (2026-09-29).
    /// When Wispr ends a dictation its stop path writes `duration` and
    /// `processing` into the row at once (≈ 0.1 s after the microphone closes —
    /// that is `rowMoved`). An input that went off with the row still NULL and
    /// no duration past the 1 s grace is a blip — 12:20 and 12:34 under the F19
    /// hold, back within ~2 s. So the close waits, up to `nullRowCloseCeiling`
    /// from the moment the input went off: the input coming back drops it
    /// (`pollInput`), the row moving ends it as before, and past the ceiling
    /// Wispr is out of the sentence — the relay's own recording carries it to his
    /// stop, then the local model (Q14), never a take cut at the blip.
    /// True while it holds the close (re-armed), or when it gave the take over.
    private static let nullRowCloseCeiling: TimeInterval = 4.0
    private var nullRowHoldSaid = false
    private func nullRowHold() -> Bool {
        guard let row = historyRow, let at = state.wisprCloseAt,
              let e = WisprHistory.entry(rowid: row),
              WisprState.intermediateStatuses.contains(e.status), e.duration == nil else { return false }
        let until = at + Self.nullRowCloseCeiling
        if CFAbsoluteTimeGetCurrent() < until {
            if !nullRowHoldSaid {
                nullRowHoldSaid = true
                Log.error(String(format: "⏳ Wispr's input went off (%@) but row %lld is still '%@' with no duration — "
                                 + "not Wispr's end; waiting up to %.0f s for its input to come back",
                                 state.wisprCloseBy, row, e.status, Self.nullRowCloseCeiling))
            }
            armWisprCloseDue(until)
            return true
        }
        ownTakeRow = row
        if holdOwnTake("Wispr Flow stopped listening mid-sentence (row \(row) never finished)") { return true }
        ownTakeRow = nil
        return false
    }
    /// The Wispr row a held take gave up on — watched to its end at his stop
    /// (`watchLateRow`), so a late ⌘V from it is dropped, never a second copy.
    private var ownTakeRow: Int64?
    /// What "Wispr ended it itself" does for the close that is waiting.
    private var pendingWisprEnded: (() -> Void)?

    /// Why the Wispr this sentence was given to is gone — nil while it lives.
    /// The kernel's table, not `NSWorkspace` (KVO-updated, it lags a kill).
    private func wisprGone() -> String? {
        let pid = wisprPidAtChord
        guard pid > 0 else { return nil }
        if fakeExitedPid == pid { return "pid \(pid) exited (POST /test/wispr-proc {fakeExit})" }
        if !ProcessClock.isAlive(pid) { return "pid \(pid) is gone" }
        // Batch 5: SIGKILLed and tearing down — `p_stat` still says running.
        if ProcessClock.isDyingOrGone(pid) { return "pid \(pid) is exiting (P_WEXIT)" }
        return nil
    }
    /// `POST /test/wispr-proc {"fakeExit": true}` — the sentence's Wispr reads as
    /// exited, no signal sent (a desk must never kill his real Wispr). Cleared at
    /// the next capture.
    private var fakeExitedPid: pid_t = 0

    // MARK: - Item 5 (batch 4): Wispr's exit, watched — not polled

    /// **The kernel says when Wispr's process exits** (`EVFILT_PROC`/`NOTE_EXIT`
    /// through a dispatch process source, on main). Lab wave 4, TW20: the quit
    /// was noticed 1.48 s after the kill (wave 3: 0.34 s) — the quit check lives
    /// in `pollHistory`, and since batch 3 that runs on the WAL watch's commits
    /// and its 1 s safety tick, not the 150 ms poll it used to ride. Armed at
    /// every capture on the pid the sentence was given to; one at a time.
    private var exitWatch: ProcessExitWatch?
    private var exitWatchPid: pid_t { exitWatch?.pid ?? 0 }
    /// The last Wispr pid the watch saw exit, and when (for `wisprLive`).
    private var exitedPid: pid_t = 0
    private var exitedAt: Date?

    private func watchWisprExit(_ pid: pid_t) {
        guard pid > 0, exitWatchPid != pid else { return }
        exitWatch?.cancel()
        exitWatch = ProcessExitWatch(pid: pid) { [weak self] pid in
            self?.wisprExited(pid, how: "the kernel's exit event")
        }
    }

    /// **Wispr's process is gone — the sentence given to it is told now**: still
    /// recording → the relay's own recording carries it to his stop (item 3);
    /// its words in flight → Q14 on the relay's recording at once
    /// (`abandonForDeadWispr`), not at the next WAL commit or safety tick.
    private func wisprExited(_ pid: pid_t, how: String) {
        if exitWatchPid == pid {
            exitWatch?.cancel()
            exitWatch = nil
        }
        exitedPid = pid
        exitedAt = Date()
        // Batch 5: the exit wins over a close still waiting, whichever came first.
        if pid == wisprPidAtChord { state.wisprProcessExited() }
        guard pid == wisprPidAtChord, capturing || isRecording || speculative, ownTakeOnly == nil else {
            Log.info("⚡ Wispr Flow's process \(pid) exited (\(how)) — no sentence of the relay's is on it")
            return
        }
        Log.info("⚡ Wispr Flow's process \(pid) exited — \(how); the sentence given to it is told at once")
        abandonForDeadWispr("pid \(pid) exited, \(how)")
    }

    /// **Wispr is gone and the sentence went with it.** Everything this capture
    /// holds is handed back on the way out: `closeListening` releases the chord
    /// and asks the Scratchpad close, `endCapture` disarms the keyboard guard
    /// and takes the window down for good.
    private func abandonForDeadWispr(_ why: String) {
        sawWisprGone = 0
        wisprPidAtChord = 0
        dropPendingWisprClose()
        // Already carried by the relay's own recording: nothing of Wispr's left to end.
        guard ownTakeOnly == nil else { return }
        // **And the window the dead instance left behind.** It belongs to a
        // process that no longer exists, so nothing else is going to ask.
        WisprScratchpad.ensureClosed(reason: "Wispr Flow quit mid-sentence")
        // **Item 3 (batch 4): while he is still talking, a quit is not his stop.**
        // The relay's recording goes on to his stop, then Q14 transcribes all of it.
        if relayStarted, isRecording || speculative, !cancelling {
            Log.error("⚠️ Wispr Flow quit mid-sentence (\(why)) — not his stop: the relay's own recording goes on")
            if holdOwnTake("Wispr Flow quit") { return }
        }
        Log.error("⚠️ Wispr Flow quit mid-sentence (\(why)) — the relay's own recording stands in (Q14)")
        if isRecording || speculative { closeListening("Wispr Flow quit") }
        // After the close, or `stopChord` would transition out of the `done`
        // this puts the machine in and the phase would say the sentence ended
        // normally.
        state.timedOut("Wispr Flow quit")
        let wasDiscarding = discardOnArrival
        endCapture(quiet: true)
        if !wasDiscarding { endWithRecording("Wispr Flow quit", row: nil) }
    }

    /// **`WT_SCRATCHPAD_DELIVER=note`** — wait for the note rather than taking
    /// the row, which is 2.8 s slower and the behaviour of the first working
    /// build. Kept because the row and the note are two different records and
    /// the day they disagree this is how to look at the other one.
    /// Long enough for Wispr to have written the note and for the window to have
    /// been shut again — measured at 2.1 s and 0.1–0.4 s respectively.
    private static let crossCheckDelay: TimeInterval = 3.5

    /// **The note may never be delivered as text in Scratchpad mode.** A
    /// second flag rather than a deleted branch, because the note path is still
    /// the way to read Wispr's other record by hand — and because a rule that is
    /// one `guard` is a rule somebody removes by accident.
    /// `WT_SCRATCHPAD_NOTE_MAY_DELIVER=1` for a deliberate experiment.
    private static let noteMayDeliver =
        ProcessInfo.processInfo.environment["WT_SCRATCHPAD_NOTE_MAY_DELIVER"] == "1"

    private static let deliverFromNote =
        ProcessInfo.processInfo.environment["WT_SCRATCHPAD_DELIVER"]?.lowercased() == "note"

    /// **The row, delivered at `formatted`, with the window dealt with after.**
    ///
    /// The one thing that must not race is the caret paste against the
    /// Scratchpad window's keyboard grab: that window takes the key when it
    /// opens, and a paste made while it has it goes **into the note** — measured
    /// on 2026-09-13, 70 characters of the relay's own delivery appended to
    /// Wispr's notepad while the document Victor was looking at stayed empty. At
    /// `formatted` the window is normally not open yet (it opens ~2 s later with
    /// the note), so the ordinary path pastes straight away; if it *is* open —
    /// left over, or Wispr being quick — it is closed first and the words follow.
    private func deliverFromRow(_ e: WisprHistory.Entry, took: Double) {
        // **`formattedText` first in this mode**, where every other path prefers
        // `pastedText`. What Wispr *pasted* here is what it appended to its own
        // note, and an append arrives lowercased and run on — `commit and push
        // the fix.` where the recogniser's own reading is `Commit and push the
        // fix.`. The row's formatted text is the sentence; the pasted text is a
        // record of what happened to a text view.
        let words = e.formattedText.isEmpty ? e.text : e.formattedText
        guard !words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Log.error(String(format: "wispr history: %@ with no text — waiting for the Scratchpad note instead", e.status))
            return
        }
        stopHistoryPoll()
        scratchpadWindowHandled = true
        // Everything the cross-check needs, before `endCapture` clears it.
        let priorId = priorNoteId
        let priorText = priorNoteText
        let since = openedAt

        Log.info(String(format: "wispr history: %@ %.0f ms after the microphone closed (Wispr's own e2e %.0f ms) — the row is the delivery",
                        e.status, took, e.e2eLatency))
        // **Who holds the keyboard is a log line now, not a gate** (2026-09-14).
        //
        // It used to be both: the delivery waited for Wispr's window to close,
        // because a ⌘V posted at the session while the Scratchpad has the key
        // focus lands in its note. That cost 488 ms on a good close and 3337 ms
        // on one that needed a retry, for a round trip the row had finished at
        // 400 ms. The paste is **addressed** now — `postToPid` to the app he was
        // looking at when he asked — so who holds the focus stops being this
        // delivery's business and becomes something worth saying and nothing
        // more.
        if WisprScratchpad.windowIsOpen() {
            Log.info("🗒️ the Scratchpad window is open at the delivery"
                     + (WisprScratchpad.focusOwnerIsWispr() ? " and holds the key focus" : "")
                     + " — the paste is addressed to pid \(focusPid.map(String.init) ?? "the caret"), so it goes to him either way")
        }
        deliver(reason: "Wispr's History row (scratchpad)", via: "wispr-history",
                delivery: .route, text: words)
        // The window is already being shut on sight — armed at the release. All
        // that is left here is the second opinion, once the note has had time to
        // be written.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.crossCheckDelay) {
            Self.crossCheckNote(delivered: words, priorId: priorId, priorText: priorText, since: since)
        }
    }

    /// **Did Wispr's note say the same thing as Wispr's row?**
    ///
    /// They are two records of one sentence and they are not the same record:
    /// the row is what the recogniser produced, the note is what its paste put
    /// on screen — and the paste has been seen to arrive lowercased and without
    /// the final stop (` commit and push the fix ` against
    /// `Commit and push the fix.`). Punctuation and case are therefore normalised
    /// away before comparing, and only a **material** difference is worth a line:
    /// a disagreement about the words is the wrap delivering something other
    /// than what Wispr heard, which is the failure this whole mode exists to
    /// avoid.
    private static func crossCheckNote(delivered: String, priorId: String?, priorText: String?,
                                       since: TimeInterval) {
        guard let note = WisprNotes.newest(since: since - 2) else {
            Log.info("🗒️ cross-check: Wispr wrote no note for this dictation")
            return
        }
        var added = note.content
        if note.id == priorId, let prior = priorText, !prior.isEmpty {
            var cut = added.startIndex
            var p = prior.startIndex
            while cut < added.endIndex, p < prior.endIndex, added[cut] == prior[p] {
                cut = added.index(after: cut)
                p = prior.index(after: p)
            }
            added = String(added[cut...])
        }
        func plain(_ s: String) -> String {
            s.lowercased().filter { $0.isLetter || $0.isNumber }
        }
        let a = plain(added)
        let b = plain(delivered)
        if a == b {
            Log.info("🗒️ cross-check: the note and the row agree (\(added.trimmingCharacters(in: .whitespacesAndNewlines).count) chars in the note)")
        } else if a.isEmpty {
            // The ordinary case since the ⌘V is swallowed: Wispr's paste never
            // reached its own note, so there is nothing to compare against.
            Log.info("🗒️ cross-check: the note added nothing — the paste that would have filled it was taken, and the row is the record")
        } else {
            Log.error("🗒️ cross-check: the note and the row DISAGREE — note \(added.debugDescription) vs row \(delivered.debugDescription)")
        }
    }

    /// **Wispr's Scratchpad note, which under `WT_SCRATCHPAD_DELIVER=note` is
    /// the whole delivery.**
    ///
    /// - Returns: whether the sentence was delivered, so the caller can stop.
    private func pollNote() -> Bool {
        guard let note = WisprNotes.newest(since: openedAt - 2) else { return false }
        let stamp = max(note.createdAt, note.modifiedAt)
        // A **new** note, or the one that was there written to again — the
        // Scratchpad is a notepad and nothing promises Wispr will keep adding
        // files rather than lines.
        let isThisOne = note.id != priorNoteId || stamp > priorNoteStamp
        let text = newPortion(of: note)
        guard isThisOne, !text.isEmpty else { return false }
        Log.info(String(format: "🗒️ wispr scratchpad: note %@ (%@) — %d chars, %.0f ms after the microphone closed",
                        String(note.id.prefix(8)),
                        note.versionSource.isEmpty ? "no version" : note.versionSource,
                        text.count, (CFAbsoluteTimeGetCurrent() - captureFrom) * 1000))
        // **Close the window before delivering, not after** (2026-09-13, 23:29).
        // Wispr's Scratchpad window takes the keyboard when it opens, and it
        // opens when the note is written — so a `pasteText` fired the moment the
        // note appears goes **into the note**, which is exactly what happened:
        // the relay's own 70 characters were appended to the Scratchpad and the
        // TextEdit document Victor was looking at stayed empty. The words are
        // already read; the window goes first and the caret gets them after.
        stopHistoryPoll()
        scratchpadWindowHandled = true
        WisprScratchpad.closeWhenItAppears { [weak self] appeared, closed in
            guard let self, self.capturing else { return WisprScratchpad.endWatch() }
            WisprScratchpad.endWatch()
            if closed {
                Log.info(appeared
                    ? "🗒️ the Scratchpad window is closed — delivering the words to the caret"
                    : "🗒️ no Scratchpad window to close — delivering the words to the caret")
            } else {
                Log.error("🗒️ THE SCRATCHPAD WINDOW WOULD NOT CLOSE — it has the keyboard, so these words would land in the note. Falling back to the sink for the next dictation.")
                self.scratchpadBroken = true
            }
            self.deliver(reason: "Wispr's Scratchpad note", via: "wispr-notes",
                         delivery: .route, text: text)
        }
        return true
    }

    /// **Only what this dictation added.**
    ///
    /// A new note is the whole sentence; a note Wispr appended to is the
    /// notepad, and the sentence is what is on the end of it. Compared against
    /// the text captured at the gesture rather than against the version row,
    /// because a `typed` version carries the accumulated note and not the
    /// increment.
    private func newPortion(of note: WisprNotes.Note) -> String {
        let full = note.content
        if note.id == priorNoteId, let prior = priorNoteText, !prior.isEmpty {
            // The common prefix rather than `hasPrefix`, so a note Wispr
            // reformatted at the front still yields its tail instead of the lot.
            var cut = full.startIndex
            var p = prior.startIndex
            while cut < full.endIndex, p < prior.endIndex, full[cut] == prior[p] {
                cut = full.index(after: cut)
                p = prior.index(after: p)
            }
            let tail = String(full[cut...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !tail.isEmpty { return tail }
        }
        let version = note.versionContent.trimmingCharacters(in: .whitespacesAndNewlines)
        return version.isEmpty ? full.trimmingCharacters(in: .whitespacesAndNewlines) : version
    }

    /// **The sink caught it** — the emergency path, and the only one in which
    /// this app holds Victor's keyboard for a moment.
    private func sinkArrived(text: String, route: String) {
        guard capturing, startedMode == .sink else { return }
        WisprSink.shared.restoreFocus()
        WisprSink.shared.onArrival = nil
        Log.info(String(format: "🧪 wispr sink caught the delivery via %@ — %d chars, %.0f ms after the microphone closed",
                        route, text.count, (CFAbsoluteTimeGetCurrent() - captureFrom) * 1000))
        deliver(reason: "the sink (\(route))", via: "wispr-sink", delivery: .route, text: text)
    }

    /// Wispr pressed ⌘V. Under the wrap the tap has already eaten it, so the
    /// words are nowhere yet and this is the whole delivery.
    private func injected(from process: String) {
        // `GET /test/state.wisprLive.sawCmdV` — the ⌘V this capture's firewall caught (W-C8).
        lastCmdVAt = CFAbsoluteTimeGetCurrent()
        // **The cancelled sentence's ⌘V, arriving after its capture was
        // retired** (2026-09-14). It is keyed by the row it was armed for, and
        // it is checked before `capturing` on purpose: the capture running now
        // belongs to the *next* dictation, and this key is not its delivery.
        if let row = retiredDiscardRow {
            Log.info(String(format: "🗑️ ⌘V from %@ belongs to cancelled row %d — swallowed and dropped", process, row))
            letRetiredDiscardGo("its ⌘V arrived and went nowhere")
            return
        }
        guard capturing else {
            // **No capture at all — a sentence this app never saw start.** Under
            // Q9 the tap lets such a ⌘V through (it is Wispr's own sentence);
            // one dropped here fell inside the relay-owned tail. The unclaimed-
            // paste rescue (`rescueFromRow`) went with Q9 step 2 (2026-09-28): it
            // had no freshness check and could deliver an hours-old row (W17).
            // **B (lab wave 2, 2026-09-28): never dropped silently.** The tap
            // drops a ⌘V here only inside the relay's tail or while a row it
            // gave up on is watched; whose it was is asked of the rows — his
            // newer row is pasted at the caret (Q19), the relay's own late ⌘V is
            // said to be the relay's.
            guard let tail = tailFloor else {
                Log.info("🛡️ ⌘V from \(process) with no capture open and no relay sentence to compare its row with — nothing delivered")
                return
            }
            Log.info("🛡️ ⌘V from \(process) with no capture open — asking the rows whose it is (the relay's floor is row \(tail.floor))")
            claimForeignPaste(floor: tail.floor, relayHadRow: tail.hadRow, relayClosedAt: tail.closedAt)
            return
        }
        if discardOnArrival {
            Log.info("🗑️ ⌘V from \(process) after the cancel — swallowed and dropped; the capture closes now")
            endCapture(quiet: true)
            return
        }
        guard intercepting else { return }
        // **Under the firewall the ⌘V is only a dropped key, never the words**
        // (2026-09-22). The pasteboard it points at is Wispr's and is about to
        // be restored; the sentence is read from the `History` row and nowhere
        // else, which is one source of truth instead of two racing.
        if hotkeys.wisprFirewallOn {
            Log.info(String(format: "🛡️ ⌘V from %@ dropped — %.0f ms after the microphone closed; the History row delivers",
                            process, (CFAbsoluteTimeGetCurrent() - captureFrom) * 1000))
            claimForeignPaste()
            return
        }
        // **Taken and dropped.** In Scratchpad mode the words are already the
        // row's; this key exists only so that it cannot land anywhere, and the
        // line is the probe's record of Wispr still delivering the way it did.
        guard startedMode != .scratchpad else {
            Log.info(String(format: "⌘V from %@ — %.0f ms after the microphone closed (taken and dropped; the row is the delivery)",
                            process, (CFAbsoluteTimeGetCurrent() - captureFrom) * 1000))
            return
        }
        Log.info(String(format: "⌘V from %@ — %.0f ms after the microphone closed%@",
                        process, (CFAbsoluteTimeGetCurrent() - captureFrom) * 1000,
                        wrapWispr ? " (taken)" : " (let through)"))
        deliver(reason: "Wispr's ⌘V", via: "wispr-cmdv",
                delivery: wrapWispr ? .route : .alreadyInserted)
    }

    private func captureExpired() {
        guard capturing else { return }
        // **The fallback, and it is Wispr's own shortcut.** `55+59+8` =
        // `copy_last_text` (⌘⌃C) puts the last transcript on the pasteboard
        // without a microphone. Posted once, and only when nothing has been seen
        // at all: a pasteboard that never moved and a ⌘V that never came means
        // the delivery went somewhere this tap cannot see.
        // Nothing was ever going to come back for a dictation this app did not
        // start, and a banner about it would be the relay complaining that
        // another app's tool worked.
        guard intercepting else {
            Log.info("wispr: Victor's own dictation is over and the relay took nothing from it")
            endCapture(quiet: true)
            didEnd?(.silent(""))
            return
        }
        if !askedForCopy, Self.copyFallbackEnabled {
            askedForCopy = true
            Log.info("no delivery seen — asking Wispr for it with ⌘⌃C (copy_last_text)")
            clipboardAt = Clipboard.changeCount
            HotkeyTap.postWisprCopyLast()
            let again = DispatchWorkItem { [weak self] in self?.captureExpired() }
            captureDeadline = again
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.copyGrace, execute: again)
            return
        }
        // **The pasteboard is an answer only when the relay asked it one**
        // (2026-09-22). `changeCount` moving is not evidence of anything: this
        // is a thirty-second window in which Victor copies things, and with
        // `copyFallbackEnabled` off — which is the default, and has been since
        // the day it was written — no ⌘⌃C was ever posted, so nothing on that
        // board has any claim to be the sentence. It was read all the same, and
        // labelled `copy_last_text`: **1 character** routed into a spawned
        // session at 18:24 and **25** pasted at the caret at 18:27, while the
        // two real sentences (779 and 434 characters) sat finished in Wispr's
        // row. *A dictation that silently becomes an older one is a sentence he
        // cannot trust* — the rule the fallback was switched off for — and this
        // was the same bug with no fallback switched on at all.
        if askedForCopy, Clipboard.changeCount != clipboardAt {
            deliver(reason: "copy_last_text", via: "pasteboard",
                    delivery: wrapWispr ? .route : .alreadyInserted)
            return
        }
        // **The row, one last look, before the sentence is called lost.**
        // `rawTextSettled` catches the stalled row during the capture; this is
        // the same read for a row that went terminal in a tick the poll missed,
        // or that was still `processing` when the 30 s ran out and has finished
        // since. Wispr's own record is the only place the words can be, and
        // reading it is free.
        if intercepting, !discardOnArrival, let row = historyRow,
           let e = WisprHistory.entry(rowid: row),
           !e.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Log.info("wispr: nothing came back within \(Int(Self.captureTimeout)) s, but row \(row) (\(e.status.isEmpty ? "∅" : e.status)) carries \(e.text.count) chars — delivering it")
            deliver(reason: "Wispr's History row at the timeout", via: "wispr-history",
                    delivery: historyIsTheRoute ? .route : .insertedElsewhere, text: e.text)
            return
        }
        if discardOnArrival {
            Log.info("🗑️ nothing came back for the cancelled sentence within \(Int(Self.captureTimeout)) s — closing the capture")
            endCapture(quiet: true)
            return
        }
        // **Q2 (2026-09-28, Victor: A): while Wispr's row is still being worked
        // on, the relay waits past 30 s.** Wispr's own fallback ASR finishes
        // at 24–36 s and its `error` lands at ~33 s; giving up at 30 s dropped
        // those sentences (W12). **Batch 3 (2026-09-28): no longer blind** —
        // a row Wispr will never finish is called dead by `pollHistory` on the
        // commit that shows it (`WisprState.deadRow`), so what is still
        // `processing` / `recording` here may still finish, and it gets up to
        // `workingCeiling` (40 s from the close; Wispr's e2e max is 36 s).
        if let row = historyRow {
            let st = status(of: row)
            let working = !st.isEmpty && WisprState.intermediateStatuses.contains(st)
            let elapsed = CFAbsoluteTimeGetCurrent() - captureFrom
            if working, elapsed < Self.workingCeiling {
                Log.info(String(format: "wispr: %.0f s and row %lld is still %@ — Wispr may still finish it; waiting on to %.0f s (Q2, batch 3)",
                                elapsed, row, st, Self.workingCeiling))
                armCaptureDeadline(after: Self.workingCeiling - elapsed)
                return
            }
        }
        let waiting = historyRow.map { "Wispr's row \($0) is still \(status(of: $0).isEmpty ? "empty" : status(of: $0))" }
            ?? "Wispr never created a row"
        let row = historyRow
        state.timedOut("nothing came back within \(Int(Self.captureTimeout)) s")
        Log.error("wispr: nothing came back within \(Int(Self.captureTimeout)) s — \(waiting)")
        endCapture(quiet: true)
        endWithRecording("Wispr Flow returned no words (\(waiting))", row: row)
    }
    /// The longest a row still `processing` is waited for (Q2), counted from
    /// the close — a net behind the dead-row verdict: Wispr's e2e p99 is 4.4 s,
    /// its max 36 s (`integration-surfaces.md`). 300 s until batch 3.
    private static let workingCeiling: CFAbsoluteTime = 40

    /// - Parameter via: the route, in the one word `outbox.jsonl` and
    ///   `GET /test/state` record it under. `reason` above is prose for the log;
    ///   this is the same fact in a form a test can assert on — see
    ///   `DictationResult.via`.
    /// - Parameter text: the words, when they did not come through the
    ///   pasteboard — Wispr's own row. The pasteboard otherwise.
    private func deliver(reason: String, via: String, delivery: DictationDelivery,
                         text given: String? = nil) {
        guard capturing else { return }
        // **Cancelled, and the words arrived anyway.** They were swallowed on
        // the way in, so they are nowhere; this is the moment to say so and let
        // the capture — and the Scratchpad with it — go.
        if discardOnArrival {
            let count = (given ?? clipboardMoved ?? "").count
            Log.info("🗑️ \(reason) arrived after the cancel — \(count) chars dropped, and the capture can close now")
            endCapture(quiet: true)
            return
        }
        // The one gate that says *these words are the relay's to route*. Every
        // caller is already behind it; it is here because the cost of one of
        // them ever not being is a sentence Victor spoke into another app
        // arriving in an agent's terminal.
        guard intercepting else { return }
        // **The markers this take carried, and what the recogniser heard**
        // (2026-09-30): the row's `asrText` is where `ShotMarker.resolveStrict`
        // reads their numbers and places them — Wispr's formatter moves and
        // deletes them, its recogniser does not. Read before `endCapture`
        // forgets the row.
        let saidNow = saidThisTake
        let rawNow = historyRow.flatMap { WisprHistory.entry(rowid: $0)?.asrText }
        let asrNow: String? = saidNow.isEmpty ? nil : rawNow
        // The string as it stood when the pasteboard first moved, when that is
        // what this delivery is about — see `clipboardMoved`.
        let fromBoard = clipboardMoved ?? Self.pasteboardString()
        let text = (given ?? fromBoard ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let took = CFAbsoluteTimeGetCurrent() - captureFrom
        // Before `endCapture` resets it, or the machine goes `transcribing` →
        // `idle` and the transition log never says this one finished.
        if armedAt >= state.chordAt { state.delivered(via: via) }
        endCapture(quiet: true)
        guard !text.isEmpty else {
            Log.error("wispr: \(reason) carried nothing")
            didEnd?(.silent("No words detected"))
            return
        }
        Log.info(String(format: "🗣️ wispr transcript via %@ — %d chars, %.0f ms after the microphone closed",
                        reason, text.count, took * 1000))
        // **Wispr's round trip is learnt too** (2026-09-23): it never was, so the
        // relay promised a 0.7 s Wispr sentence the local model's 2.7 s.
        if spokenFor > 0 {
            DecodeRate.record(audio: spokenFor, decode: took, engine: DecodeRate.wisprFlow, chars: text.count)
            spokenFor = 0
        }
        meterQueue.async { [weak self] in
            guard let self else { return }
            let taken = self.recording
            self.recording = nil
            DispatchQueue.main.async {
                self.didTranscribe?(DictationResult(
                    text: text,
                    language: nil,
                    audio: taken?.url,
                    duration: taken?.duration ?? 0,
                    // Stamped so a sample labelled by Wispr's own recogniser is
                    // never mistaken for one the local model read. The text has
                    // been through Wispr's formatting pass — punctuation, its
                    // custom dictionary — which is a fact a later evaluation has
                    // to know, and the engine name is where it is said.
                    engine: "wispr-flow",
                    warning: nil,
                    delivery: delivery,
                    via: via,
                    // Only where the recogniser may have moved the focus under
                    // the sentence; every other path means *the caret*.
                    focusPid: self.startedMode == .scratchpad ? self.focusPid : nil,
                    markersInAudio: self.markersInAudio,
                    engineLabel: Self.engineLabel,
                    said: saidNow,
                    asr: asrNow,
                    unformatted: rawNow))
                self.didEnd?(.delivered)
            }
        }
    }

    private func endCapture(quiet: Bool) {
        guard capturing else { return }
        capturing = false
        // **Unless a cancelled row still has a claim on it** — the swallow is
        // the one thing that outlives a retired capture, and disarming it here
        // for even the turn it takes to arm the next one is a window in which
        // Wispr's ⌘V for the sentence Victor cancelled reaches his document.
        if retiredDiscardRow == nil { hotkeys.disarmInjectionCapture() }
        clipboardWatch?.invalidate()
        clipboardWatch = nil
        clipboardMoved = nil
        stopHistoryPoll()
        // **Kept past the capture**, because *has Wispr started anything since*
        // is asked after it — see `lateOpenEdge`.
        if let row = historyRow { lastRow = row }
        historyRow = nil
        priorRow = nil
        priorRowWasOpen = false
        priorNoteId = nil
        priorNoteStamp = 0
        priorNoteText = nil
        discardOnArrival = false
        endDiscardClose()
        // **Never leave the sink holding his keyboard.** Every ordinary sink
        // delivery restores focus on arrival; this is the path where nothing
        // arrived and the capture timed out.
        if startedMode == .sink {
            WisprSink.shared.onArrival = nil
            if WisprSink.shared.isKey { WisprSink.shared.restoreFocus() }
            WisprSink.shared.close()
        }
        // **And the window Wispr just opened**, which is the next dictation's
        // precondition and not this one's housekeeping.
        //
        // **Whatever happened**, and that word is the fix (2026-09-14). This
        // read `!scratchpadWindowHandled`, and the flag is claimed at the
        // *release* — so a dictation that came back with nothing had already
        // marked the window as somebody else's problem, and nobody else picked
        // it up: the runner watched it stand open for three seconds after
        // `No words came back`, with his keystrokes going into the note the
        // whole time. A sentence Wispr never finished is exactly when the window
        // and the keyboard are most owed back, not least.
        if startedMode == .scratchpad {
            // Idempotent, and the guard must never outlive the capture.
            hotkeys.disarmKeyRedirect()
            // **A capture retired by a gesture leaves the window to that
            // gesture** (2026-09-14). `holdScratchpad` owns the precondition —
            // it checks the window and closes it before it holds the chord — and
            // a close started here would be the second half of a toggle behind
            // that one, which re-opens what the first shut.
            if isRecording || speculative {
                scratchpadWindowHandled = true
                Log.info("🗒️ the next dictation is already opening — its own precondition closes the window, not this capture")
            }
            // **Unless one is already being asked for**, which the cancel path
            // now does as soon as Wispr is finished rather than here — and a
            // second ask behind the first is the toggle re-opening the window.
            else if WisprScratchpad.closeIsInFlight {
                scratchpadWindowHandled = true
                Log.info("🗒️ a close is already in flight — not asking a second time (it is a toggle)")
            } else if !scratchpadWindowHandled || WisprScratchpad.windowIsUp {
                scratchpadWindowHandled = true
                closeScratchpadAfterwards()
            }
        }
        captureDeadline?.cancel()
        captureDeadline = nil
        // The machine goes back to rest with the capture, which is also what
        // takes the 100 ms poll off CoreAudio.
        if !isRecording, !speculative { state.reset("the capture is over") }
        // **A sentence that is still being spoken gets its own window now.**
        // The capture that just ended belonged to the *previous* one — kept by
        // `retireCaptureIfSettled` because its row was not terminal — and
        // leaving this one with no swallow, no pasteboard watch and no row poll
        // is the 2026-09-13 Word failure with extra steps.
        if isRecording || speculative, ownTakeOnly == nil {
            Log.info("wispr: the standing capture is retired — arming this dictation's own")
            beginCapture()
        }
        syncInputPoll()
    }
}
