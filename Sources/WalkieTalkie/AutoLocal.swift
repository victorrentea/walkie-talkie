import Foundation

/// **Prepare local transcript (p95)** — the Engine submenu's checkbox
/// (2026-09-28 as *Auto fallback to local (p98)*; reshaped 2026-09-29).
///
/// 2026-09-28, 22:25, Victor: *"I don't think I will ever have the patience to
/// wait for 36 seconds. I will probably hit ⌘⌃X and use the local model
/// fallback."* That evening a sentence over its budget was **handed to this Mac
/// automatically** (`via: local-auto`).
///
/// 2026-09-29 morning, twice. First: *"We go with p95. But by the time p95
/// elapses from the start of the transcription, I must ALREADY have the local
/// model's transcription ready … Only when the local transcription is ready do
/// you show the 'insert local transcription' hint in the tooltip."* Then the
/// correction: *"the insertion of the local transcription must be done at the
/// human's request, never automatically. I only OFFER it: never insert the local
/// fallback automatically, only show when it is ready, and the human decides
/// when to insert."*
///
/// 2026-10-06, reversed again. Victor: *"put a countdown timer … and when the
/// timer expires, the local dictation is automatically injected"* (that
/// morning he had pressed ⌘⌃X twice, 11 s and 18 s past a 3.4 s budget, while
/// Wispr Flow sat on a row that never finished).
///
/// So, ON (the default): at the close of a sentence on ElevenLabs or Wispr Flow
/// the budget is read (`DecodeRate.budget`, the engine's p95 for that length,
/// clamped), the local model decodes the take **speculatively** from
/// `budget − localEta` (`specStart`) and holds the words. From one second into
/// the wait the chip counts down to the budget — `💻 local in 3s / ⌘⌃X ...`;
/// **at zero the local words go in** (`via: local-auto`; a decode still
/// running is waited for), unless the engine's words landed first (the local
/// ones are then discarded, logged `wasted`) or he pressed ⌘⌃X (inserted at
/// once, `via: local-forced`). The local weights are kept warm while another
/// engine is picked. OFF: no decode ahead, nothing inserted on a clock, the row
/// is ⌘⌃X's plain `Local now` from one second into the wait.
///
/// Not this checkbox's (unchanged, automatic, 2026-09-28 decisions): the hard
/// failures — the engine answered an error, Wispr made no row, its process went
/// (Q14) — still hand the take to this Mac on their own (and use the words
/// decoded ahead when there are some); and a Wispr sentence started while
/// Wispr Flow is not running (or still starting) borrows the local model.
enum AutoLocal {

    /// `UserDefaults` beside `dictationSource` and `autosend`: a preference,
    /// not data, so `--home` does not move it. The key keeps its 09-28 name so
    /// his setting survives the rename.
    static let defaultsKey = "autoLocalFallback"

    static var isOn: Bool {
        get { UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    /// The Engine submenu's row title.
    static let menuTitle = "Backup Local Pre-Transcribe"

    /// **The chip's ⌘⌃X row.** With a decode ahead armed for this sentence it
    /// counts down to the budget — `💻 local in 3s / ⌘⌃X ...` (2026-10-07,
    /// Victor's wording, replacing 10-06's `⌘⌃X - 💻 fallback, auto in 3s...`;
    /// the 💻 is the row's glyph column, not in the text), whole seconds rounded
    /// up, `local now` at zero while the local words are still being decoded. **No engine's name** (same day:
    /// *"don't leak the name of any tool, only the icon"* — the logo on the
    /// `Transcribing via` row says which). Otherwise ⌘⌃X's own `Local now`,
    /// `(loading)` while the weights are down.
    static func rowText(countdown: TimeInterval? = nil, loading: Bool, keys: String) -> String {
        if let c = countdown {
            let s = Int(c.rounded(.up))
            return "local " + (s > 0 ? "in \(s)s" : "now") + " / " + keys + " ..."
        }
        return "Local now" + (loading ? " (loading)" : "") + "  " + keys
    }

    /// **A plain sentence on Wispr waits for Wispr's own words** (2026-10-10,
    /// Victor: *"in dictare curata cu wispr ca motor, ia te rog varianta
    /// redactata"*). That evening two clean sentences went in as the local
    /// model's unpunctuated words: Wispr took 2.4 s on a 7 s take, the p95
    /// budget was the 1.5 s floor, and its formatted row came 0.9 s after the
    /// local words had landed. A plain sentence is read by a human at the caret,
    /// where the formatter's rewrite is the point; Wispr's e2e p99 is 4.4 s.
    /// The local words are still decoded ahead and still go in past this.
    static let wisprCleanFloor: TimeInterval = 5

    /// The budget for this close: `seconds`, raised to `wisprCleanFloor` for a
    /// clean sentence on Wispr Flow.
    static func budgetSeconds(_ seconds: TimeInterval, clean: Bool, wispr: Bool) -> TimeInterval {
        clean && wispr ? max(seconds, wisprCleanFloor) : seconds
    }

    /// **The budget ran out: are the local words to go in now?** (2026-10-06,
    /// Victor: *"when the timer expires, the local dictation is automatically
    /// injected"* — the 2026-09-29 *offered, never inserted* reversed.) Only
    /// words in hand: a decode still running is waited for (the tick asks again),
    /// and one that gave nothing leaves the sentence to the engine.
    static func shouldHandOver(expired: Bool, phase: SpecPhase, handedOver: Bool) -> Bool {
        expired && !handedOver && phase == .ready
    }

    // MARK: - The speculative local decode (2026-09-29)

    /// **The local words are ready by the budget, not started at it.** The local
    /// model's typical decode for the take (`DecodeRate.typical`) plus this margin
    /// is `localEta`; the decode starts `localEta` before the budget runs out, at
    /// the close when that is already too late.
    static let specMargin: TimeInterval = 0.3

    /// How long the local model is expected to take on this take, margin included.
    static func localEta(typical: TimeInterval) -> TimeInterval { max(0, typical) + specMargin }

    /// Seconds after the close at which the speculative decode starts —
    /// `max(0, budget − localEta)`: at the close when `localEta ≥ budget`.
    static func specStart(budget: TimeInterval, localEta: TimeInterval) -> TimeInterval {
        max(0, budget - localEta)
    }

    /// Where one sentence's speculative decode is.
    enum SpecPhase: String {
        /// Scheduled, not started (waiting for `specStart`, or for the WAV).
        case planned
        case running
        /// Words in hand, offered on the chip, not inserted.
        case ready
        /// The local model gave no words (or its helper could not be brought up).
        case failed
        /// Never to run: under the voiced floor — the local model would invent a sentence.
        case skipped
        /// Thrown away: the engine answered first, a cancel, a newer sentence, ⌘⌃X consumed it.
        case discarded
    }

    /// **Start the decode now?** — pure (`SpecScheduleTests`), read by
    /// `AppDelegate.syncLocalNow` every 0.1 s while the words are out. Only a
    /// planned decode whose WAV is known starts, at `startAt`; nothing here ever
    /// inserts — the budget's expiry is only a fact for the row and the log.
    static func shouldStart(elapsed: TimeInterval, startAt: TimeInterval, phase: SpecPhase, wavKnown: Bool) -> Bool {
        phase == .planned && wavKnown && elapsed >= startAt
    }

    /// **Is the row up, and what does it say?** — pure. With a decode armed for
    /// this sentence (planned, running or ready) the row is the countdown to the
    /// budget from `localNowRowDelay` into the wait (2026-10-06 — it waited for
    /// the words until then), `left` seconds to go; nothing when the local model
    /// had nothing to give (failed / skipped / discarded — the engine's words are
    /// the only ones coming). With no decode planned (OFF, or a sentence that was
    /// never armed) it is ⌘⌃X's plain row from `localNowRowDelay` into the wait.
    static func row(waiting: Bool, pastDelay: Bool, spec: SpecPhase?,
                    left: TimeInterval = 0) -> (shown: Bool, countdown: TimeInterval?) {
        guard waiting else { return (false, nil) }
        guard let spec else { return (pastDelay, nil) }
        switch spec {
        case .planned, .running, .ready: return (pastDelay, max(0, left))
        case .failed, .skipped, .discarded: return (false, nil)
        }
    }

    // MARK: - One line per sentence, for reading back (2026-09-29)

    /// **What happened to one sentence's wait**, all seconds from the mic close.
    /// Victor: *"I want clear logging to understand the actual behaviour
    /// retroactively."* One `📊 fallback:` line in `relay.log` and one JSON
    /// object in `~/.walkie-talkie/fallback.jsonl` per armed sentence, written
    /// at its outcome; `evals/fallback-report.py` reads the file.
    struct Trace {
        var engine: String
        var audio: TimeInterval
        var budget: TimeInterval
        var unclamped: TimeInterval
        var cap: TimeInterval
        var samples: Int
        var localEta: TimeInterval
        /// When the decode was scheduled to start.
        var specPlanned: TimeInterval
        var specStart: TimeInterval?
        var localReady: TimeInterval?
        /// The engine's words (or its failure) reached the relay.
        var engineAnswer: TimeInterval?
        var engineFailed = false
        /// The budget ran out with the words still out (the local words go in — 2026-10-06).
        var budgetExpired: TimeInterval?
        /// When the countdown first went up on the chip.
        var rowShown: TimeInterval?
        /// `engine` · `local-forced` (⌘⌃X) · `local-auto` (the budget ran out,
        /// 2026-10-06) · `local-fallback` (Q14, a hard
        /// failure) · `recover` (staged for Recover) · `cancelled` · `silent`.
        var outcome: String?
        /// A local decode ran (or was running) whose words were not the ones delivered.
        var wasted = false
        var toWords: TimeInterval?
        /// Why no decode ran ahead (under the voiced floor, no WAV, failed).
        var specNote: String?
        /// A desk run's sentence (the fake Scribe, a fake `History`, a forced
        /// budget) — written with `"test": true`, which `fallback-report.py` skips.
        var test = false
        let at: Date

        init(budget b: DecodeRate.Budget, localEta: TimeInterval, at: Date = Date()) {
            engine = b.engine; audio = b.audio; budget = b.seconds; unclamped = b.unclamped
            cap = b.cap; samples = b.samples; self.localEta = localEta
            specPlanned = AutoLocal.specStart(budget: b.seconds, localEta: localEta)
            self.at = at
        }

        private static func s(_ v: TimeInterval?) -> String {
            v.map { String(format: "%.2f", $0) } ?? "never"
        }

        /// `📊 fallback: engine=… audio=… budget=…(p95,n=…) localEta=… specStart=… localReady=… engineAnswer=… budgetExpired=… outcome=… wasted=… toWords=…`
        var logLine: String {
            "📊 fallback: engine=\(engine) audio=\(String(format: "%.1f", audio)) "
                + "budget=\(String(format: "%.2f", budget))(\(DecodeRate.Budget.quantileName),n=\(samples)) "
                + "localEta=\(String(format: "%.2f", localEta)) specStart=\(Self.s(specStart)) "
                + "localReady=\(Self.s(localReady)) engineAnswer=\(Self.s(engineAnswer)) "
                + "budgetExpired=\(Self.s(budgetExpired)) outcome=\(outcome ?? "?") wasted=\(wasted) "
                + "toWords=\(Self.s(toWords))"
                + (test ? " [test]" : "")
                + (specNote.map { " — \($0)" } ?? "")
        }

        /// The same, as one JSON object (numbers, null for *never*).
        var json: [String: Any] {
            func n(_ v: TimeInterval?) -> Any { v.map { ($0 * 1000).rounded() / 1000 } ?? NSNull() }
            return ["at": Outbox.iso(at), "engine": engine, "audio": n(audio), "budget": n(budget),
                    "quantile": DecodeRate.budgetQuantile, "samples": samples, "unclamped": n(unclamped),
                    "cap": n(cap), "localEta": n(localEta), "specPlanned": n(specPlanned),
                    "specStart": n(specStart), "localReady": n(localReady), "engineAnswer": n(engineAnswer),
                    "engineFailed": engineFailed, "budgetExpired": n(budgetExpired), "rowShown": n(rowShown),
                    "outcome": outcome ?? NSNull(), "wasted": wasted, "toWords": n(toWords),
                    "note": specNote ?? NSNull(), "test": test]
        }

        /// `wasted` from what ran: a decode that started, for a sentence whose
        /// words were not the local ones.
        static func wasted(specStarted: Bool, outcome: String) -> Bool {
            specStarted && !outcome.hasPrefix("local-")
        }

        /// The outcome a delivery's `via` means.
        static func outcome(via: String?) -> String {
            switch via {
            case "local-forced": return "local-forced"
            case "local-auto": return "local-auto"
            case "local-fallback": return "local-fallback"
            default: return "engine"
            }
        }
    }

    /// Where the traces go — beside `decode-rate.jsonl`, appended forever.
    static var traceURL: URL { Outbox.home.appendingPathComponent("fallback.jsonl") }

    /// One `write(2)` on `O_APPEND`, as `DecodeRate.append` does.
    static func append(_ trace: Trace) {
        guard let data = try? JSONSerialization.data(withJSONObject: trace.json, options: [.sortedKeys]) else { return }
        var line = data
        line.append(0x0A)
        try? FileManager.default.createDirectory(at: Outbox.home, withIntermediateDirectories: true)
        let fd = open(traceURL.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard fd >= 0 else { return }
        defer { close(fd) }
        _ = line.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
    }

    /// The flash when a Wispr sentence starts while Wispr Flow still works on the
    /// take handed to this Mac (2026-10-06) — no engine's name on the chip.
    static let wisprBusyFlash = "💻 Local — the last take is still being transcribed"

    /// The flash when a Wispr sentence starts with Wispr Flow down (or just launched).
    static let wisprStartingFlash = "💻 Local — Wispr Flow is starting"

    /// A Wispr Flow the relay launched itself counts as *starting* this long —
    /// Victor: *"10 s startup time is killing"*. The process is up well before
    /// its microphone answers a chord.
    /// **Since batch 4 (2026-09-29) any Wispr Flow this young counts, whoever
    /// launched it** — its process age, read from the kernel.
    static let wisprStartupGrace: TimeInterval = 12

    /// **Why a Wispr sentence should not wait for Wispr Flow now** — nil when it
    /// can take it. Pure (`AutoLocalWisprStartTests`).
    ///
    /// Item 4 (lab wave 4): the borrow covered only a Wispr **the relay** had
    /// launched (`launchedByRelayAgo`). TX9 relaunched Wispr from outside and
    /// dictated 1 s later: Wispr ignored the chord, and each sentence paid Q14's
    /// 4.3–6.3 s instead of the borrow's 1.3–1.6 s. The process's own age is
    /// the same fact for any launcher.
    ///
    /// - Parameters:
    ///   - running: Wispr Flow's main process is up.
    ///   - processAge: seconds since that process started (nil: unknown).
    ///   - launchedByRelayAgo: seconds since the relay last asked for a launch (nil: never).
    static func wisprNotUp(running: Bool, processAge: TimeInterval?, launchedByRelayAgo: TimeInterval?,
                           grace: TimeInterval = wisprStartupGrace) -> String? {
        guard running else { return "is not running" }
        if let a = launchedByRelayAgo, a >= 0, a < grace {
            return String(format: "is still starting (launched %.1f s ago)", a)
        }
        if let a = processAge, a >= 0, a < grace {
            return String(format: "is still starting (its process is %.1f s old)", a)
        }
        return nil
    }
}
