import Foundation

/// **🧠 The model a prompt's session answers with, switched by a gesture** (2026-11-21).
/// Victor: *"în timpul dictării să dau cu butonul de back și să-mi facă swipe dreapta …
/// să se schimbe modelul pentru acea sesiune … voi alterna între Opus High și Fable
/// Medium … în tooltip să-mi scrie un creier în față și apoi fable/med. Dacă repet
/// gestul, să bucleze … să mă întorc înapoi la ce am avut înainte"*.
///
/// 🔽 → while a prompt records marks the sentence with the next model of the ring; a flick
/// that comes back to the session's own takes the mark off. At delivery a bound session is
/// typed `/model …` and `/effort …` before the prompt (Claude Code's own slash commands), a
/// new one is launched with `--model … --effort …`. What each session was last switched to
/// is kept per tty, so the next flick starts from there; a session never switched counts as
/// Opus / high.
///
/// **Three in the ring since 2026-11-22** — Victor: *"Mai pune încă un model în listă.
/// Normal pleacă de pe Opus, apoi Fable. Dacă nu, Sonnet High"*: Opus / high (where a
/// session starts) → Fable / medium → Sonnet / high → back to its own (no switch).
enum ModelPick: String, CaseIterable {
    /// In the ring's order.
    case opusHigh, fableMedium, sonnetHigh

    var model: String {
        switch self {
        case .opusHigh: return "opus"
        case .fableMedium: return "fable"
        case .sonnetHigh: return "sonnet"
        }
    }
    var effort: String { self == .fableMedium ? "medium" : "high" }
    /// What the chip writes after the 🧠.
    /// Capitalised (2026-11-21 evening, Victor: *"Fable cu F mare"*).
    var label: String {
        switch self {
        case .opusHigh: return "Opus/high"
        case .fableMedium: return "Fable/med"
        case .sonnetHigh: return "Sonnet/high"
        }
    }
    /// The next one round the ring.
    var next: ModelPick {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
    /// Typed into a running session, one line each, before the prompt.
    var commands: [String] { ["/model \(model)", "/effort \(effort)"] }
    /// On a new session's command line.
    var cliFlags: String { "--model \(model) --effort \(effort)" }
}

enum ModelSwitch {
    /// tty → what Walkie last switched that session to. Main thread.
    private static var sessions: [String: ModelPick] = [:]
    static let standard: ModelPick = .opusHigh

    static func current(tty: String?) -> ModelPick {
        guard let tty else { return standard }
        return sessions[tty] ?? standard
    }

    static func remember(_ pick: ModelPick, tty: String) {
        sessions[tty] = pick
    }

    /// **What one more 🔽 → flick marks the sentence with**: the model after the one marked
    /// (after the session's own when nothing is marked yet); nil — the mark taken off — when
    /// the ring is back at the session's own. On Opus: Fable → Sonnet → none.
    static func flick(marked: ModelPick?, session: ModelPick) -> ModelPick? {
        let next = (marked ?? session).next
        return next == session ? nil : next
    }
}
