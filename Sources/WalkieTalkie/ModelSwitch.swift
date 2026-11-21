import Foundation

/// **🧠 The model a prompt's session answers with, switched by a gesture** (2026-11-21).
/// Victor: *"în timpul dictării să dau cu butonul de back și să-mi facă swipe dreapta …
/// să se schimbe modelul pentru acea sesiune … voi alterna între Opus High și Fable
/// Medium … în tooltip să-mi scrie un creier în față și apoi fable/med. Dacă repet
/// gestul, să bucleze … să mă întorc înapoi la ce am avut înainte"*.
///
/// 🔽 → while a prompt records marks the sentence with the other of the two; again takes
/// it back. At delivery a bound session is typed `/model …` and `/effort …` before the
/// prompt (Claude Code's own slash commands), a new one is launched with `--model …
/// --effort …`. What each session was last switched to is kept per tty, so the next
/// flick offers the other one; a session never switched counts as Opus / high.
enum ModelPick: String {
    case opusHigh, fableMedium

    var model: String { self == .opusHigh ? "opus" : "fable" }
    var effort: String { self == .opusHigh ? "high" : "medium" }
    /// What the chip writes after the 🧠.
    /// Capitalised (same evening, Victor: *"Fable cu F mare"*).
    var label: String { self == .opusHigh ? "Opus/high" : "Fable/med" }
    var other: ModelPick { self == .opusHigh ? .fableMedium : .opusHigh }
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
}
