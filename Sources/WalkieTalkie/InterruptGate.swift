import Foundation

/// **🛑 Interrupt: a bound sentence that must not wait in the agent's queue** (2026-11-22)
/// — the decisions of that rule as pure functions (`InterruptGateTests`).
///
/// Victor: *"la gestul de back cu swipe stânga în timpul dictării, dacă e dictare bound,
/// doar dacă e bound dictarea, să însemne interrupt. Și să apară un tag nou în tooltip și
/// să se manifeste ca și cum ți-aș da Control X, Control S în Claude. Adică să-ți
/// injecteze repede ceea ce am spus eu, să nu stea în coadă. Uneori se întâmplă să aștept
/// minute grele."*
///
/// ⌃X ⌃S is Claude Code's default `chat:sendNow` (2.1.275+; nothing in his
/// `keybindings.json` touches it): the queued messages go out right away — work that can
/// move to the background does and the turn reads them, a turn only writing is
/// interrupted. Every bound sentence has had it since 2026-11-05, but only on the hint
/// `ctrl+x ctrl+s to send now` in the tab's last 600 characters; the interrupt presses it
/// on the queue itself (`TerminalBinding.sendsNow`).
enum InterruptGate {

    /// What 🔽 ← does while a microphone is open (`HotkeyTap`, ⌃⌥⌘F3).
    enum Flick: Equatable {
        /// The open sentence goes to the bound terminal: mark it / take the mark back.
        case interrupt
        /// Anything else — a caret prompt, a new session, a ⚡ question, a plain
        /// dictation, Wispr's own sentence: swallowed, nothing (🔼 ← cancels).
        case nothing
    }

    static func flick(boundOpen: Bool, ownDictation: Bool, quick: Bool) -> Flick {
        boundOpen && ownDictation && !quick ? .interrupt : .nothing
    }

    /// Whether the open sentence goes to the bound terminal. `caret` = the 🔼 caret
    /// prompt or one flipped there by 🔼 →; `plainAtCaret` = a plain dictation that
    /// nothing redirected (the auto-bind over a Claude Code tab did redirect it).
    static func bound(listening: Bool, isBound: Bool, quick: Bool, spawn: Bool,
                      caret: Bool, plainAtCaret: Bool) -> Bool {
        listening && isBound && !quick && !spawn && !caret && !plainAtCaret
    }

    /// The flash after an interrupt sentence was delivered; nil = nothing to say (a
    /// tab that reads back, and Claude Code had not queued it — it went in at once).
    /// `readsBack`: a Terminal.app tab or an Orca pane — the only targets whose screen
    /// is read, so the only ones where the queue is seen and the chord pressed. tmux,
    /// an IDE terminal or chat, a pasted-into app: the words went with their Return.
    static func receipt(sentNow: Bool, readsBack: Bool) -> String? {
        if sentNow { return sent }
        return readsBack ? nil : unsupported
    }

    static let sent = "🛑 Interrupt — sent now"
    static let unsupported = "🛑 Interrupt works only in Claude Code in Terminal — sent as usual"
    /// The chip's row.
    static let row = "Interrupt"
}

extension TerminalBinding.Handle {
    /// The delivery reads this target's screen back (Return watch, ⌃X ⌃S).
    var readsBack: Bool {
        switch self {
        case .terminalApp, .orca: return true
        default: return false
        }
    }
}
