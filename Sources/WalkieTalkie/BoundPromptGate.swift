import Foundation

/// **A bound prompt needs a bound terminal** (2026-11-22) — the two decisions
/// and the two sentences of that rule, as pure functions so they are tested
/// without an app (`BoundPromptGateTests`).
///
/// Victor: *"Dacă n-am niciun terminal legat … nu pot să pornesc o dictare
/// bound. Ideea asta de «bind to send/paste» e stupidă. Să nici nu pornească în
/// modul de bound dacă n-am terminal legat. … dacă mi se închide terminalul
/// legat în timp ce vorbesc, nu trebuie să mi se oprească dictarea, dar când o
/// închid, să mi se spună: terminalul a murit, o poți recupera din istorie."*
///
/// It supersedes 2026-09-11's `holdsForBind` and 2026-09-26's Q1 (*held 5 min
/// for the next bind*, the `📨 N waiting — bind to send` row) and Q4 (*a dead
/// terminal at delivery → pasted at the caret*).
enum BoundPromptGate {

    // MARK: The start

    enum Start: Equatable {
        /// Open the microphone.
        case open
        /// ⌘⌃B was pressed a moment ago and is still resolving: remember the
        /// press, the bind's landing opens the microphone.
        case bank
        /// Nothing bound: no microphone, no ring, no edge — `nothingBound`.
        case refuse
    }

    /// Only the bound prompt asks (`spawn` = 🔼 ↑ / the wake word, `paste` =
    /// the caret prompt, the plain dictation, the ⚡ question — each carries its
    /// own destination).
    static func start(spawn: Bool, paste: Bool, bound: Bool, bindInFlight: Bool) -> Start {
        if spawn || paste || bound { return .open }
        return bindInFlight ? .bank : .refuse
    }

    // MARK: 🔼 → mid-sentence

    enum Flip: Equatable {
        /// A caret sentence, something bound: to the bound terminal.
        case toBound
        /// A terminal sentence: to the caret — whether or not its terminal is
        /// still bound (unbound under him is when he most needs the caret).
        case toCaret
        /// A caret sentence, nothing bound: it stays as it is — `nothingBound`.
        case stay
        /// The gesture is this sentence's stop (a spawn, an *Active Terminals*
        /// pick still binding, the wheel's toggle on a terminal sentence).
        case end
    }

    /// `gesture`: 🔼 → itself (`toggleDictation(flipsDestination:)`); false for
    /// the wheel's toggle, which redirects a caret sentence to a bound terminal
    /// and otherwise stops.
    static func flip(gesture: Bool, atCaret: Bool, spawn: Bool, pickInFlight: Bool, bound: Bool) -> Flip {
        if atCaret { return bound ? .toBound : (gesture ? .stay : .end) }
        if gesture, !spawn, !pickInFlight { return .toCaret }
        return .end
    }

    // MARK: The two sentences

    /// The refusal: why, and the key that answers it.
    static let nothingBound = "📍 Nothing bound — ⌘⌃B binds the terminal in front"

    /// A prompt that reached nobody: what happened, then the two places it is
    /// (`AppDelegate.keepUndelivered` writes both before this shows). Short on
    /// purpose: a flash is one line of ~60 characters, and the first wording
    /// (*your prompt is in Prompt History and on the clipboard*) lost its end.
    static func undelivered(_ lost: String) -> String {
        "⚠️ \(lost) — find the prompt in Prompt History or ⌘V"
    }

    /// `lastDelivery.to` and the outbox row's `delivery.to` for such a prompt.
    /// It was `held` until 2026-11-22.
    static let undeliveredTo = "undelivered"
}
