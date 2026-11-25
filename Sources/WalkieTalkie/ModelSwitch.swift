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
/// is kept per session, so the next flick starts from there (until 2026-11-25 a session never
/// switched counted as Opus / high — see below).
///
/// **Only what he picks is sent, and nothing is assumed** (2026-11-25, after the Fable review
/// found the per-tty memory outliving the session — an app restart forgot it, a reused tty
/// inherited it). Victor: *"dacă îl modific explicit, injectezi model effort; dacă nu ating,
/// nu reinjectezi"*. A sentence whose ring was not moved sends no `/model` and no `/effort`.
/// The ring starts from a known model only for the very session Walkie switched in this run
/// (its tty **and** its Claude process, pid + start time); any other session's model is
/// unknown, and its ring is its own → Opus / high → Fable / medium → Sonnet / high → its own.
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
    /// tty → what Walkie last switched that session to, and which session that was (its Claude
    /// process — `TerminalBinding.agentProcess(onTTY:)`). Main thread. In memory on purpose: after a
    /// restart nothing is known, and nothing is assumed.
    private static var sessions: [String: (pick: ModelPick, session: TerminalBinding.TTYOwner)] = [:]

    /// The model Walkie switched **this** session to in this run; nil — unknown — for a session it
    /// never switched, one on a tty whose earlier session it did switch, a spawn, or no tty.
    static func current(tty: String?, session: TerminalBinding.TTYOwner?) -> ModelPick? {
        guard let tty, let session, let known = sessions[tty], known.session == session else { return nil }
        return known.pick
    }

    /// Whether anything is remembered for this tty — so the caller asks `ps` for the session only then.
    static func knows(tty: String?) -> Bool { tty.map { sessions[$0] != nil } ?? false }

    /// After `/model` + `/effort` landed in a session. Without the session's identity nothing is
    /// kept: a pick that cannot be tied to its session must not be read back as another's.
    static func remember(_ pick: ModelPick, tty: String, session: TerminalBinding.TTYOwner?) {
        guard let session else { sessions[tty] = nil; return }
        sessions[tty] = (pick, session)
    }

    static func forgetAll() { sessions = [:] }

    /// **What one more 🔽 → flick marks the sentence with**: the model after the one marked; nil —
    /// the mark taken off, nothing sent — when the ring is back at the session's own. A session
    /// whose model is known (Walkie switched it) starts after it and skips it: on Fable, Sonnet →
    /// Opus → none. An unknown one starts at the top: Opus → Fable → Sonnet → none.
    static func flick(marked: ModelPick?, session: ModelPick?) -> ModelPick? {
        guard let session else {
            let all = ModelPick.allCases
            guard let marked else { return all.first }
            return marked == all.last ? nil : marked.next
        }
        let next = (marked ?? session).next
        return next == session ? nil : next
    }

    /// **What a delivered sentence types before its words**: `/model` + `/effort` only when the ring
    /// was moved for it — never a remembered or assumed model.
    static func commands(for pick: ModelPick?) -> [String] { pick?.commands ?? [] }
}
