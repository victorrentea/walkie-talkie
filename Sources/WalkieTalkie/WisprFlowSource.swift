import AppKit
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

    let name = "Wispr Flow"

    /// **The whole of the wrap, in one flag.** On: the relay takes Wispr's
    /// paste and delivers the words itself, so Wispr looks exactly like the
    /// local recogniser to everything downstream. Off: Wispr inserts its own
    /// text wherever the focus is and the relay only draws the ring — the
    /// behaviour of every build before 2026-09-12, kept because it is the one
    /// thing to fall back to if a Wispr update changes how it delivers.
    var wrapWispr = true {
        didSet { Log.info("wispr wrap \(wrapWispr ? "on — the relay takes the paste" : "off — Wispr pastes where the focus is")") }
    }

    // MARK: - Events

    var didMaybeBegin: ((String) -> Void)?
    var didBegin: (() -> Void)?
    var didStopListening: (() -> Void)?
    var didTranscribe: ((DictationResult) -> Void)?
    var didEnd: ((DictationEnd) -> Void)?

    // MARK: - State

    private(set) var isRecording = false
    /// Wispr Flow is running at all. Asked of the process list rather than
    /// remembered: it is quit and relaunched like any other app.
    var isReady: Bool { NSWorkspace.shared.runningApplications.contains {
        $0.bundleIdentifier?.hasPrefix(Self.bundlePrefix) == true } }

    let meter = MicRecorder()

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
    private var capturing = false
    private var captureFrom: CFAbsoluteTime = 0
    private var captureDeadline: DispatchWorkItem?
    private var clipboardWatch: Timer?
    private var clipboardAt = 0
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

    private static let bundlePrefix = "com.electron.wispr-flow"

    // MARK: - Life

    init(hotkeys: HotkeyTap) {
        self.hotkeys = hotkeys
        watch.onChange = { [weak self] on in self?.edge(on, measured: true) }
        hotkeys.onWisprMaybeStarting = { [weak self] why, confident in
            DispatchQueue.main.async { self?.gestureSeen(why, confident: confident) }
        }
        hotkeys.onInjectedPaste = { [weak self] from in
            DispatchQueue.main.async { self?.injected(from: from) }
        }
    }

    func prepare() {
        watch.start()
    }

    // MARK: - DictationSource

    @discardableResult
    func start() -> String? {
        guard !isRecording else { return nil }
        guard isReady else { return "Wispr Flow is not running" }
        HotkeyTap.postWisprHandsFree()
        // **The relay asked for this one**, so there is nothing to guess about:
        // the dictation opens now and the microphone edge confirms it. The tap
        // will *also* see the chord this posts and call `gestureSeen`, which is
        // a no-op once `speculative` is set.
        gestureSeen("the relay asked for a dictation", confident: true)
        return nil
    }

    /// **The same chord again** — Wispr's hands-free shortcut is a toggle, and
    /// the relay has nothing else with which to say *stop*. The closing edge is
    /// still `WisprWatch`'s, never this call: a chord Wispr ignores must not
    /// end a dictation that is still running.
    func stop() {
        guard isRecording else { return }
        HotkeyTap.postWisprHandsFree()
    }

    func cancel() {
        // **The ✕ during the wait counts too.** Between the microphone closing
        // and the words arriving there are seconds in which the sentence is
        // still this app's to throw away — and it is exactly the stretch in
        // which Victor realises he does not want it.
        if !isRecording, !speculative, capturing {
            Log.info("🗑️ Wispr Flow's transcript abandoned before it arrived")
            endCapture(quiet: true)
            didEnd?(.cancelled(audio: nil, duration: 0))
            return
        }
        guard isRecording || speculative else { return }
        cancelling = true
        Log.info("🗑️ Wispr Flow dictation cancelled — posting ⌃Escape")
        HotkeyTap.postWisprCancel()
        endCapture(quiet: true)
        if speculative {
            speculativeDrop?.cancel()
            speculativeDrop = nil
            speculative = false
            stopMeter(keep: false)
        }
        if !isRecording {
            // Nothing will arrive to close it — the microphone never opened.
            cancelling = false
            didEnd?(.cancelled(audio: nil, duration: 0))
        }
    }

    // MARK: - The test routes

    /// `POST /test/wispr` — the CoreAudio edge with no CoreAudio behind it.
    /// `measured: false` keeps the latency line honest: this enters below the
    /// watcher and would otherwise print the age of the last real dictation.
    func simulateEdge(_ on: Bool) {
        guard isRecording != on || (on && speculative) else { return }
        Log.info("wispr flow \(on ? "opened" : "closed") the microphone (simulated)")
        edge(on, measured: false)
    }

    /// `POST /test/wispr-handsfree` — the **real** chord on the wire, which is
    /// the one input the end-to-end harness is allowed to cause. Deliberately
    /// not `start()`: the harness has to be able to post the chord a second time
    /// to stop the dictation, and `start()` refuses while one is running.
    func postStartChord() { HotkeyTap.postWisprHandsFree() }

    /// `POST /test/wispr {"hotkey": true}` — the speculative ring, one step
    /// earlier than the microphone.
    func simulateHotkey() { gestureSeen("POST /test/wispr {hotkey}", confident: true) }

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
    private func gestureSeen(_ why: String, confident: Bool) {
        guard !isRecording, !speculative else { return }
        speculative = true
        gestureAt = CFAbsoluteTimeGetCurrent()
        // **A capture still standing belongs to a sentence that is over.** Left
        // armed it would take the *next* sentence's ⌘V as this one's answer.
        endCapture(quiet: true)
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
        let drop = DispatchWorkItem { [weak self] in
            guard let self, self.speculative else { return }
            self.speculative = false
            self.isRecording = false
            self.stopMeter(keep: false)
            Log.info(String(format: "⚡ ring down: no microphone within %.0f s of the hotkey — Wispr ignored the chord",
                            Self.speculativeGrace))
            self.didEnd?(.silent(""))
        }
        speculativeDrop?.cancel()
        speculativeDrop = drop
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.speculativeGrace, execute: drop)
        // The meter comes up with the guess, so the ring breathes from the first
        // syllable rather than from whenever CoreAudio gets round to the edge.
        // `start(to:)` is a no-op on a session already open, so the confirming
        // edge costs nothing when it arrives.
        startMeter()
    }

    private func edge(_ on: Bool, measured: Bool) {
        if on {
            // **The microphone edge confirms; it never re-opens.** A guess that
            // is standing is *this* dictation — the ring, the chip and the
            // context shot are already up — and firing `didBegin` again would
            // take them all down and put them back, which is precisely the
            // flicker Victor reported on 2026-09-12.
            if speculative {
                speculativeDrop?.cancel()
                speculativeDrop = nil
                speculative = false
                Log.info(String(format: "⚡ mic edge confirms the ring %.0f ms after the gesture",
                                (CFAbsoluteTimeGetCurrent() - gestureAt) * 1000))
                isRecording = true
                startMeter()
                return
            }
            guard !isRecording else { return }
            isRecording = true
            startMeter()
            didBegin?()
            if measured, watch.edgeAt > 0 {
                Log.info(String(format: "⚡ ring up %.0f ms after Wispr Flow opened the microphone",
                                (CFAbsoluteTimeGetCurrent() - watch.edgeAt) * 1000))
            }
        } else {
            guard isRecording else { return }
            isRecording = false
            speculativeDrop?.cancel()
            speculativeDrop = nil
            speculative = false
            stopMeter(keep: !cancelling)
            didStopListening?()
            // A cancel has nothing to wait for: Wispr's Escape discards the
            // audio and pastes nothing, so the ring goes at once.
            if cancelling {
                cancelling = false
                didEnd?(.cancelled(audio: nil, duration: 0))
            } else {
                beginCapture()
            }
        }
    }

    // MARK: - The meter, which is also the corpus's recording

    private func startMeter() {
        let wav = Outbox.shotsDir.appendingPathComponent("wispr-\(Int(Date().timeIntervalSince1970)).wav")
        meterQueue.async { [weak self] in
            guard let self else { return }
            guard !self.meter.isRecording else { return }
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
            let taken = self.meter.stop()
            if keep { self.recording = taken }
            else if let taken { try? FileManager.default.removeItem(at: taken.url) }
        }
    }

    // MARK: - Catching the transcript

    private func beginCapture() {
        capturing = true
        captureFrom = CFAbsoluteTimeGetCurrent()
        askedForCopy = false
        clipboardAt = NSPasteboard.general.changeCount
        // **Armed whether or not the relay is going to take it.** The probe half
        // — which process posted what key, how long after the microphone shut —
        // is the only record of how Wispr delivers, and it is worth the same two
        // log lines in either mode. Only `swallow` differs.
        hotkeys.armInjectionCapture(swallow: wrapWispr)

        // The pasteboard is the other half of the answer, and the only half in
        // the cases where the ⌘V never arrives: an Accessibility insertion, a
        // focus Wispr refuses to paste into, a keystroke that went somewhere
        // else. Polled at 20 Hz and **only while capturing** — a permanent
        // pasteboard poll is a different and much worse thing than a six-second
        // one.
        clipboardWatch?.invalidate()
        let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, self.capturing else { return }
            guard NSPasteboard.general.changeCount != self.clipboardAt else { return }
            self.clipboardWatch?.invalidate()
            self.clipboardWatch = nil
            // Give the ⌘V a beat to arrive behind the write: Wispr sets the
            // pasteboard *then* presses the key, so a poll that fires in between
            // must not conclude the key is never coming.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self, self.capturing else { return }
                self.deliver(reason: "the pasteboard moved but no ⌘V was seen",
                             delivery: .alreadyInserted)
            }
        }
        clipboardWatch = t
        RunLoop.main.add(t, forMode: .common)

        captureDeadline?.cancel()
        let giveUp = DispatchWorkItem { [weak self] in self?.captureExpired() }
        captureDeadline = giveUp
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.captureTimeout, execute: giveUp)
    }

    /// Wispr pressed ⌘V. Under the wrap the tap has already eaten it, so the
    /// words are nowhere yet and this is the whole delivery.
    private func injected(from process: String) {
        guard capturing else { return }
        Log.info(String(format: "⌘V from %@ — %.0f ms after the microphone closed%@",
                        process, (CFAbsoluteTimeGetCurrent() - captureFrom) * 1000,
                        wrapWispr ? " (taken)" : " (let through)"))
        deliver(reason: "Wispr's ⌘V", delivery: wrapWispr ? .route : .alreadyInserted)
    }

    private func captureExpired() {
        guard capturing else { return }
        // **The fallback, and it is Wispr's own shortcut.** `55+59+8` =
        // `copy_last_text` (⌘⌃C) puts the last transcript on the pasteboard
        // without a microphone. Posted once, and only when nothing has been seen
        // at all: a pasteboard that never moved and a ⌘V that never came means
        // the delivery went somewhere this tap cannot see.
        if !askedForCopy, Self.copyFallbackEnabled {
            askedForCopy = true
            Log.info("no delivery seen — asking Wispr for it with ⌘⌃C (copy_last_text)")
            clipboardAt = NSPasteboard.general.changeCount
            HotkeyTap.postWisprCopyLast()
            let again = DispatchWorkItem { [weak self] in self?.captureExpired() }
            captureDeadline = again
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.copyGrace, execute: again)
            return
        }
        if NSPasteboard.general.changeCount != clipboardAt {
            deliver(reason: "copy_last_text", delivery: wrapWispr ? .route : .alreadyInserted)
            return
        }
        endCapture(quiet: true)
        didEnd?(.silent("No words came back"))
    }

    private func deliver(reason: String, delivery: DictationDelivery) {
        guard capturing else { return }
        let text = (NSPasteboard.general.string(forType: .string) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let took = CFAbsoluteTimeGetCurrent() - captureFrom
        endCapture(quiet: true)
        guard !text.isEmpty else {
            Log.error("wispr: \(reason) carried nothing")
            didEnd?(.silent("No words detected"))
            return
        }
        Log.info(String(format: "🗣️ wispr transcript via %@ — %d chars, %.0f ms after the microphone closed",
                        reason, text.count, took * 1000))
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
                    delivery: delivery))
                self.didEnd?(.delivered)
            }
        }
    }

    private func endCapture(quiet: Bool) {
        guard capturing else { return }
        capturing = false
        hotkeys.disarmInjectionCapture()
        clipboardWatch?.invalidate()
        clipboardWatch = nil
        captureDeadline?.cancel()
        captureDeadline = nil
    }
}
