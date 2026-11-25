import Foundation

/// **`POST /question/toggle` — the ⚡ quick question without the mouse** (2026-11-25).
/// Victor Mac calls it on the DJI receiver's Link button pressed twice, so a
/// question can be asked from across the room: at rest it opens the question
/// 🔼 ← opens (`AppDelegate.openQuickQuestion`), pressed again while that
/// question records it ends it as 🔼 does (`endDictation`) and it is answered.
/// Any other sentence recording is left alone and the caller is told why (409).
///
/// The decision is pure, so it is tested without an app (`QuestionToggleTests`).
enum QuestionToggle {

    enum Verdict: Equatable {
        case start
        case end
        case refuse(String)
    }

    /// - `open`: a microphone is open (`listening || source.isRecording`).
    /// - `quick`: the open sentence is a ⚡ question (the 🔽 ← Codex question is one too).
    /// - `wordsInFlight`: the last sentence's words are not in yet — where 🔼 ← at
    ///   rest starts nothing either.
    /// - `blocked`: why a start would be refused now (`startBlocker`), else nil.
    static func decide(open: Bool, quick: Bool, wordsInFlight: Bool, blocked: String?) -> Verdict {
        if open {
            return quick ? .end : .refuse("another dictation is recording — Link ×2 only starts or ends a ⚡ question")
        }
        if wordsInFlight { return .refuse("the last sentence's words are still in flight") }
        if let blocked { return .refuse("a start would be refused now — \(blocked)") }
        return .start
    }

    /// The route's answer: 200 `{result: started|ended, why}`, 409 `{result: refused, why}`.
    static func answer(_ verdict: Verdict) -> (status: Int, body: [String: Any]) {
        switch verdict {
        case .start: return (200, ["result": "started", "why": "nothing was recording — a ⚡ question opened, as 🔼 ← at rest"])
        case .end: return (200, ["result": "ended", "why": "the ⚡ question was recording — ended as 🔼 ends it, it is being answered"])
        case .refuse(let why): return (409, ["result": "refused", "why": why])
        }
    }
}
