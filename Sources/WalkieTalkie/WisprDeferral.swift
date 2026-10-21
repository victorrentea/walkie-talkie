import Foundation

/// **Q12 for Wispr Flow — the next sentence is recorded at once and handed to
/// Wispr when it is free** (2026-10-21, Victor: *"the ability to record
/// immediately another [prompt] even though you are currently transcribing the
/// old snippet … this should also work if you are transcribing with Wispr …
/// just buffer the wav and then hand it to Wispr whenever it's ready"*).
///
/// Wispr takes one sentence at a time: a start chord posted while it is still
/// finishing the last row is ignored (10:25:11 on 2026-10-06), and a toggle
/// posted over its open microphone *stops* that one (W6). So a start that meets
/// a Wispr still busy is **deferred**: the relay's meter and the bridge open at
/// the gesture (held — the WAV and From Walkie's backlog keep every word), and
/// the real start — the chord, the capture, the 3 s microphone watch — runs
/// when the sentence before it has ended and Wispr is free.
///
/// The pure half — what the deferred take does next, from the facts
/// `WisprFlowSource.deferredTick` reads — so the rules are pinned by
/// `WisprDeferralTests` rather than by a lab run.
enum WisprDeferral {

    /// The sentence before it may take this long from the deferred gesture —
    /// past it the deferred take stops waiting (Q14: the relay's own recording,
    /// the local model). A net only: the sentence before ends by its own
    /// ceilings first (`captureTimeout` 30 s, then `workingCeiling` 40 s from
    /// its close, and the dead-row verdicts long before either).
    static let olderCeiling: TimeInterval = 60

    /// Once the sentence before has ended **and** he has stopped, Wispr must be
    /// free (its row finished, its microphone shut) within this — else the take
    /// is the local model's. While he is still talking there is no clock: Wispr
    /// has until his stop.
    static let freeCeiling: TimeInterval = 10

    /// Why a start now cannot be Wispr's at once — nil when Wispr can take the
    /// chord. Read by `WisprFlowSource.start()` (a non-nil answer defers it).
    static func startBusy(machineRecording: Bool, speculative: Bool, capturing: Bool,
                          discarding: Bool, finishingRow: Int64?, endingInFlight: Int,
                          take: String) -> String? {
        if machineRecording || speculative { return "take \(take) is still being handed to Wispr Flow" }
        if capturing, !discarding { return "Wispr Flow is still transcribing take \(take)" }
        if let row = finishingRow { return "Wispr Flow is still finishing row \(row)" }
        if endingInFlight > 0 { return "take \(take) is still ending" }
        return nil
    }

    /// **The sentence the machine was on when the take was deferred is over** —
    /// answered, or with nothing of it left anywhere (no microphone, no capture,
    /// no end on its way, the relay's own recording not carrying it). The
    /// second half is the belt for a sentence that ended without a word to the
    /// relay: it must not hold the next one until `olderCeiling`.
    static func olderDone(owes: Bool, machineRecording: Bool, speculative: Bool, capturing: Bool,
                          endingInFlight: Int, ownTake: Bool) -> Bool {
        if !owes { return true }
        return !machineRecording && !speculative && !capturing && endingInFlight == 0 && !ownTake
    }

    struct Facts: Equatable {
        var now: CFAbsoluteTime
        /// His gesture — the deferred take's start.
        var gestureAt: CFAbsoluteTime
        /// His stop has come (0 while he is still talking).
        var stoppedAt: CFAbsoluteTime = 0
        /// The recorder's close for his stop has landed (the WAV is known).
        var closedKnown = false
        /// Wispr is already out of this take: the relay's recording carries it.
        var ownTake = false
        var wisprRunning = true
        var olderDone = false
        /// When the sentence before was first seen over (0 until then).
        var olderDoneAt: CFAbsoluteTime = 0
        /// Why Wispr cannot take a chord right now — still finishing a row,
        /// its microphone open — nil when it can.
        var busy: String?

        var stopped: Bool { stoppedAt > 0 }
    }

    enum Verdict: Equatable {
        /// Nothing to do yet — and why, for the log and `/test/state`.
        case wait(String)
        /// Wispr is free: post the start chord now.
        case release
        /// Wispr will not get this take: the relay's own recording carries it
        /// (to his stop, if he is still talking), then the local model (Q14).
        case giveUp(String)
        /// Wispr was already out of it and his stop has closed the recording:
        /// end it on the relay's WAV now.
        case endOwnTake
    }

    static func verdict(_ f: Facts) -> Verdict {
        if f.ownTake {
            return f.stopped && f.closedKnown ? .endOwnTake : .wait("the relay's own recording carries it")
        }
        if !f.wisprRunning { return .giveUp("Wispr Flow is not running") }
        if !f.olderDone {
            let waited = f.now - f.gestureAt
            if waited > olderCeiling {
                return .giveUp(String(format: "the sentence before it is still not over %.0f s after this one began", waited))
            }
            return .wait("the sentence before it is still in flight")
        }
        if let busy = f.busy {
            if f.stopped {
                let from = max(f.olderDoneAt, f.stoppedAt)
                if f.now - from > freeCeiling {
                    return .giveUp(String(format: "%@ — %.0f s after the sentence before it ended and he stopped", busy, f.now - from))
                }
            }
            return .wait(busy)
        }
        if f.stopped, !f.closedKnown { return .wait("the recording of his stop is still closing") }
        return .release
    }
}
