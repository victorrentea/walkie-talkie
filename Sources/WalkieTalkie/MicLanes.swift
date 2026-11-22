import Foundation

/// **A microphone call that never comes back may not take the app with it**
/// (2026-11-22).
///
/// `MicRecorder.start(to:)` and `.stop()` are synchronous CoreAudio calls. The
/// sources run them on a serial queue of their own so the main thread never
/// waits on a device — and until this day that queue was the next thing to
/// wedge: at 13:47:48 `-[AVAudioEngine inputNode]` on a fresh engine spun for
/// ever inside `AVAudioIOUnit_OSX::_GetHWFormat` (`sample`d; `coreaudiod` at
/// 80 %), take 9's stop and take 10's start and stop queued behind it, and the
/// app said `Transcribing...` over two sentences it had never recorded until
/// it was force-restarted. A blocked CoreAudio call cannot be cancelled, so the
/// only way out is to **walk away from it**:
///
/// - A *lane* is one recorder plus the serial queue every call on it goes
///   through. `run` puts a piece of work on the current lane and gives it a
///   deadline.
/// - Work that has not finished by its deadline **abandons the lane**: every
///   piece of work on it that has not finished — the stuck one and all those
///   queued behind it, in order — is told `abandoned` on the main queue, and a
///   **fresh lane** (a new recorder, a new queue) takes its place before they
///   are told, so the next sentence records.
/// - If the stuck call does return, much later, its `late` handler runs on the
///   old lane's queue with the old recorder and the result — the place to
///   close a microphone nobody is waiting for. Work queued behind it on the
///   abandoned lane is skipped.
///
/// Main queue only, except the closures documented otherwise. Generic over the
/// recorder so the timing logic is unit-tested with a stub that never returns
/// (`MicLanesTests`).
final class MicLanes<Recorder: AnyObject> {

    /// **No fourth lane while three calls are still stuck.** Each stuck open is
    /// a thread asking `coreaudiod` questions in a loop; a start refused at
    /// once says the same thing to him and costs the Mac nothing.
    static var maxStuck: Int { 3 }

    private final class Lane {
        let recorder: Recorder
        let queue: DispatchQueue
        var ops: [Op] = []
        init(recorder: Recorder, queue: DispatchQueue) { self.recorder = recorder; self.queue = queue }
    }

    private final class Op {
        enum State { case pending, running, finished, abandoned }
        let lock = NSLock()
        var state = State.pending
        let what: String
        let abandoned: () -> Void
        init(what: String, abandoned: @escaping () -> Void) { self.what = what; self.abandoned = abandoned }
    }

    private let label: String
    private let make: () -> Recorder
    private var lane: Lane
    private var generation = 1
    /// Calls that were running when their lane was abandoned and have not
    /// returned yet.
    private(set) var stuck = 0
    /// Lanes abandoned since launch — `GET /test/state`.
    private(set) var abandonedLanes = 0
    /// Why the last lane was abandoned, for the log and the state route.
    private(set) var lastAbandonment: (what: String, at: Date)?

    /// The live lane's recorder. **Changes when a lane is abandoned** — never
    /// keep it across a hop; ask again.
    var recorder: Recorder { lane.recorder }

    /// True when a new open would only add a fourth spinning thread.
    var saturated: Bool { stuck >= Self.maxStuck }

    init(label: String, make: @escaping () -> Recorder) {
        self.label = label
        self.make = make
        self.lane = Lane(recorder: make(), queue: DispatchQueue(label: label))
    }

    /// Runs `work` on the live lane, after everything already queued on it.
    ///
    /// - Parameters:
    ///   - what: a few words for the log (`open take 9`).
    ///   - timeout: seconds from now; nil = no deadline of its own (it is still
    ///     abandoned with its lane when an earlier call's deadline passes).
    ///   - work: **on the lane's queue**, handed the lane's recorder.
    ///   - done: on main, only when the work finished on a lane still in use.
    ///   - abandoned: on main, instead of `done`, when the lane was given up —
    ///     this call's own deadline or an earlier call's.
    ///   - late: **on the old lane's queue**, when work that was running at the
    ///     abandonment returns after all.
    func run<T>(_ what: String, timeout: TimeInterval?,
                work: @escaping (Recorder) -> T,
                done: @escaping (T) -> Void,
                abandoned: @escaping () -> Void,
                late: ((Recorder, T) -> Void)? = nil) {
        let lane = self.lane
        let op = Op(what: what, abandoned: abandoned)
        lane.ops.append(op)
        let started = Date()
        lane.queue.async { [weak self] in
            op.lock.lock()
            guard op.state == .pending else { op.lock.unlock(); return }   // its lane was abandoned
            op.state = .running
            op.lock.unlock()
            let result = work(lane.recorder)
            op.lock.lock()
            if op.state == .abandoned {
                op.lock.unlock()
                Log.error(String(format: "mic lane: %@ came back %.1f s after it was asked — nobody is waiting for it any more",
                                 what, Date().timeIntervalSince(started)))
                late?(lane.recorder, result)
                DispatchQueue.main.async { self?.stuck -= 1 }
                return
            }
            op.state = .finished
            op.lock.unlock()
            DispatchQueue.main.async {
                lane.ops.removeAll { $0 === op }
                done(result)
            }
        }
        guard let timeout else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self else { return }
            op.lock.lock(); let state = op.state; op.lock.unlock()
            guard state == .pending || state == .running, self.lane === lane else { return }
            self.abandon(lane, because: what, after: timeout)
        }
    }

    /// Walks away from `lane`: a fresh one first, then every unfinished call is told.
    private func abandon(_ lane: Lane, because what: String, after timeout: TimeInterval) {
        var told: [Op] = []
        var running: String?
        for op in lane.ops {
            op.lock.lock()
            switch op.state {
            case .running: running = op.what; op.state = .abandoned; told.append(op)
            case .pending: op.state = .abandoned; told.append(op)
            case .finished, .abandoned: break
            }
            op.lock.unlock()
        }
        lane.ops = []
        if running != nil { stuck += 1 }
        abandonedLanes += 1
        lastAbandonment = (what, Date())
        generation += 1
        self.lane = Lane(recorder: make(), queue: DispatchQueue(label: "\(label).\(generation)"))
        Log.error(String(format: "mic lane: %@ did not finish in %.0f s — %@; the recorder is abandoned with %d call(s) on it "
                         + "and a fresh one takes its place (%d call(s) still stuck in CoreAudio)",
                         what, timeout,
                         running.map { "\($0) is still inside CoreAudio" } ?? "nothing was running",
                         told.count, stuck))
        told.forEach { $0.abandoned() }
    }

    func describe() -> [String: Any] {
        var out: [String: Any] = ["stuck": stuck, "abandoned": abandonedLanes, "waiting": lane.ops.count]
        if let last = lastAbandonment {
            out["last"] = last.what
            out["lastAgo"] = (Date().timeIntervalSince(last.at) * 10).rounded() / 10
        }
        return out
    }
}

/// The words the chip and the log use for a microphone that did not answer.
enum MicFailure {
    /// The sentence's end when the open never came back.
    static let didNotOpen = "Microphone did not open — nothing was recorded"
    /// The sentence's end when the close never came back.
    static let didNotClose = "Microphone did not close — the recording is lost"
    /// A start refused while `MicLanes.maxStuck` opens are still stuck.
    static let notAnswering = "The microphone is not answering — restart Walkie Talkie"
    /// The chip's row from `openingAfter` into an open that has not confirmed.
    static let openingRow = "Opening microphone..."
    /// An ordinary open is under a second; past this the row says so.
    static let openingAfter: TimeInterval = 1.5
    /// **How long an open may take before the sentence is failed.** From
    /// `relay.log`: an ordinary open logs `mic: recording through …` in the
    /// same second as the gesture (≤ 1 s, hundreds of takes); the slowest one
    /// that still recorded took 4 s (13:47:03 → 13:47:07, after `could not
    /// switch to Elgato Wave XLR`). Twice that, so a slow device still records.
    /// A `var` for the tests only.
    static var openTimeout: TimeInterval = 8
    /// A close is a teardown of an engine that was running: `mic: closed` is
    /// in the same second as the stop in every take of the log.
    static var closeTimeout: TimeInterval = 8
}
