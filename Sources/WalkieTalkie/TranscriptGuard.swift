import Foundation
import NaturalLanguage

/// **Words in a language nobody spoke** (2026-11-04). Victor: *"se mai întâmplă
/// uneori să vină prompt-ul în altă limbă, de caracter chinezesc sau arabă"*.
///
/// Measured on `voice-corpus/corpus.jsonl`, 1 Oct – 3 Nov: 35 of 3,566 sentences,
/// nearly all Wispr's, 18 of them in the week of 26 Oct — with `ro` and `en` the
/// only languages ticked in Wispr. Two shapes, and they take different cures:
///
/// - **The whole take** is another language, on either side of the alphabet
///   (`مغربية.`, `Dá uma dá pra tirar critério desse`) — the audio was Romanian:
///   the local model, pinned to `ro`/`en`, answers *Mă grăbesc.* on the same WAV.
///   Its words replace the engine's.
/// - **Romanian with a foreign tail** — 13 of 14 such takes carry the run in their
///   last 17 %, 11 of 14 last 30–43 s, which looks like a short second 30 s
///   window guessing its own language. The first half minute is fine and better
///   than the local model's, so only the run is replaced (`repair`).
///
/// Nothing here spends a token: `foreignLetters` is a walk over the scalars and
/// `NLLanguageRecognizer` answers on this Mac in 0.9 ms a sentence. The retry is
/// checked as hard as the original, because the local model has its own failure:
/// on three 32–40 s takes it answered `Thank you.` and nothing else (`accepts`).
/// → journal: *Words in a language nobody spoke*
enum TranscriptGuard {

    /// **What is wrong with a transcript.**
    enum Verdict: Equatable {
        /// Most of it: the local words replace it.
        case wholeTake(String)
        /// A run inside Romanian or English, between these two character offsets
        /// of the text as given (whole words).
        case foreignRun(start: Int, end: Int, String)

        var why: String {
            switch self {
            case .wholeTake(let why), .foreignRun(_, _, let why): return why
            }
        }
    }

    /// One letter is a `π` or a `λ` he asked for; **two in a row** is the smallest
    /// run in the corpus (`Το`, `да`, `少し`).
    static let minForeignRun = 2
    /// Romanian + English together, as `NLLanguageRecognizer` weighs them. At
    /// 0.5 it took *JDBC connection pool starvation* (0.39) and *Stop asking me
    /// to test myself…* (0.47); at 0.2 they pass and *Kare chama lungu eche
    /// lule?* (0.13) does not.
    static let roEnFloor = 0.2
    /// Under four words the recogniser's answer is noise.
    static let minWords = 4
    /// `test, test, test, test` scored 0 for Romanian and English both.
    static let minDistinctWords = 3
    /// **The local answer has to be a transcript of this much talking**: `Thank
    /// you.` on 33 s is a hallucination, whatever language it is in. The slowest
    /// honest take among the 55 was *Screenshot one.* — 3 words in 6.8 s; speech
    /// runs at 2–3 a second.
    static let minRetryWordsPerSecond = 0.3
    /// Where the local words are looked for around a run.
    static let anchorWindow = 12
    /// See `splice`.
    static let maxOrphanTail = 5

    /// Spoken markers (`Screenshot 1`, `Selected text one`) are this app's own,
    /// in English inside Romanian: they say nothing about the language, and in a
    /// four-word sentence they can be half of it.
    private static let marker = try! NSRegularExpression(
        pattern: #"(?i)\b(screenshot|selected text|select the text)[ :]+(\d+|one|two|three|four|five|six|seven|eight|nine|ten)\b"#)

    static func withoutMarkers(_ text: String) -> String {
        marker.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
    }

    /// **`nil` is a transcript in Romanian and/or English.**
    static func judge(_ text: String) -> Verdict? {
        let bare = withoutMarkers(text)
        let letters = bare.unicodeScalars.filter { $0.properties.isAlphabetic }
        let foreign = letters.filter { !isLatin($0) }
        if longestForeignRun(bare) >= minForeignRun {
            let why = "\(foreign.count) of \(letters.count) letters are not in the Latin alphabet"
            if foreign.count * 2 >= letters.count { return .wholeTake(why) }
            guard let run = foreignSpan(in: text) else { return .wholeTake(why) }
            return .foreignRun(start: run.0, end: run.1, why)
        }
        let words = tokens(bare)
        guard words.count >= minWords, Set(words).count >= minDistinctWords else { return nil }
        let share = roEnShare(bare)
        guard share < roEnFloor else { return nil }
        return .wholeTake(String(format: "Romanian + English read as %.0f %%", share * 100))
    }

    private static func longestForeignRun(_ text: String) -> Int {
        var longest = 0, run = 0
        for s in text.unicodeScalars {
            run = s.properties.isAlphabetic && !isLatin(s) ? run + 1 : 0
            longest = max(longest, run)
        }
        return longest
    }

    /// The Latin script, combining marks and the modifier letters a formatter
    /// may leave — anything else alphabetic is what he does not speak.
    private static func isLatin(_ s: Unicode.Scalar) -> Bool {
        switch s.value {
        case 0x41...0x5A, 0x61...0x7A, 0xAA, 0xBA, 0xC0...0x24F, 0x250...0x2FF,
             0x300...0x36F, 0x1E00...0x1EFF, 0x2C60...0x2C7F, 0xA720...0xA7FF, 0xFB00...0xFB06:
            return true
        default:
            return false
        }
    }

    /// Romanian + English in `NLLanguageRecognizer`'s hypotheses.
    static func roEnShare(_ text: String) -> Double {
        let r = NLLanguageRecognizer()
        r.processString(text)
        let h = r.languageHypotheses(withMaximum: 6)
        return (h[.romanian] ?? 0) + (h[.english] ?? 0)
    }

    /// First to last foreign letter, widened to whole words, in `Character`s.
    private static func foreignSpan(in text: String) -> (Int, Int)? {
        let chars = Array(text)
        func foreign(_ c: Character) -> Bool {
            c.unicodeScalars.contains { $0.properties.isAlphabetic && !isLatin($0) }
        }
        guard var a = chars.firstIndex(where: foreign),
              var b = chars.lastIndex(where: foreign) else { return nil }
        while a > 0, !chars[a - 1].isWhitespace { a -= 1 }
        b += 1
        while b < chars.count, !chars[b].isWhitespace { b += 1 }
        return (a, b)
    }

    // MARK: - The retry

    /// **Is the local answer a transcript of this take?** It passes the same
    /// judge — and is the length of something said (`minRetryWordsPerSecond`).
    static func accepts(retry: String, duration: TimeInterval) -> Bool {
        guard judge(retry) == nil else { return false }
        return Double(tokens(retry).count) >= max(1, duration * minRetryWordsPerSecond)
    }

    /// **What goes out for a run inside good words.**
    enum Repair: Equatable {
        /// The engine's words around the run, the local model's inside it.
        case spliced(String)
        /// No place to splice, and the local words as a whole do: replace it.
        case replaced
        /// The local words are no use: the engine's, with the run taken out.
        case cut(String)
    }

    static func repair(_ text: String, start: Int, end: Int, retry: String, duration: TimeInterval) -> Repair {
        let chars = Array(text)
        let head = String(chars[..<start]).trimmingCharacters(in: .whitespacesAndNewlines)
        let tail = String(chars[end...]).trimmingCharacters(in: .whitespacesAndNewlines)
        let good = accepts(retry: retry, duration: duration)
        if good, let s = splice(head: head, tail: tail, retry: retry) {
            let joined = [head, s.middle, s.keepsTail ? tail : ""].filter { !$0.isEmpty }.joined(separator: " ")
            if judge(joined) == nil { return .spliced(joined) }
        }
        return good ? .replaced : .cut([head, tail].filter { !$0.isEmpty }.joined(separator: " "))
    }

    /// **The local words that stand where the run stood.** The last words of
    /// `head` are found in the local text; as many local words as `head` still
    /// had after that match are skipped, 1:1, or the seam would say them twice.
    /// Nil when nothing near the seam matches: a splice there would be a guess.
    ///
    /// **Words after the run that the local model never said** are part of the
    /// run when they are few (`Το territorio corriere loro”`, where the local
    /// text goes on to *teritoriul cortierilor*): the local words stand for them
    /// too. Past `maxOrphanTail` they are a sentence the engine heard and the
    /// local model did not, and they stay, with nothing between.
    static func splice(head: String, tail: String, retry: String) -> (middle: String, keepsTail: Bool)? {
        let local = localWords(retry)
        let keys = local.map(key)
        let h = head.split(whereSeparator: \.isWhitespace).map { key(String($0)) }.filter { !$0.isEmpty }
        var from = 0
        if !h.isEmpty {
            let window = Array(h.suffix(anchorWindow))
            guard let (i, j) = lastCommon(window, keys) else { return nil }
            from = j + 1 + (window.count - 1 - i)
        }
        guard from <= local.count else { return ("", true) }
        var to = local.count
        let t = tail.split(whereSeparator: \.isWhitespace).map { key(String($0)) }.filter { !$0.isEmpty }
        if !t.isEmpty {
            let window = Array(t.prefix(anchorWindow))
            guard let (i, j) = firstCommon(window, Array(keys[from...])) else {
                return t.count <= maxOrphanTail ? (local[from...].joined(separator: " "), false) : ("", true)
            }
            to = max(from, from + j - i)
        }
        return (local[from..<to].joined(separator: " "), true)
    }

    /// The local text word by word. **A sentence glued to the next** (`pornit.Sci.`,
    /// 9 of the 55: two windows joined with no space) is two words.
    static func localWords(_ text: String) -> [String] {
        text.replacingOccurrences(of: #"([\p{Ll}\d][.?!])(\p{Lu})"#, with: "$1 $2", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// A word as the two recognisers can agree on it: lower case, no diacritics,
    /// no punctuation.
    private static func key(_ word: String) -> String {
        word.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .unicodeScalars.filter { $0.properties.isAlphabetic || $0.properties.numericType != nil }
            .map(String.init).joined()
    }

    /// The last pair of a longest common subsequence — where the two texts were
    /// last saying the same thing.
    private static func lastCommon(_ a: [String], _ b: [String]) -> (Int, Int)? {
        guard !a.isEmpty, !b.isEmpty else { return nil }
        var dp = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 1...a.count {
            for j in 1...b.count {
                dp[i][j] = a[i - 1] == b[j - 1] ? dp[i - 1][j - 1] + 1 : max(dp[i - 1][j], dp[i][j - 1])
            }
        }
        var i = a.count, j = b.count
        while i > 0, j > 0 {
            if a[i - 1] == b[j - 1] { return (i - 1, j - 1) }
            if dp[i - 1][j] >= dp[i][j - 1] { i -= 1 } else { j -= 1 }
        }
        return nil
    }

    /// The first pair of one, for the words after the run.
    private static func firstCommon(_ a: [String], _ b: [String]) -> (Int, Int)? {
        lastCommon(a.reversed(), b.reversed()).map { (a.count - 1 - $0.0, b.count - 1 - $0.1) }
    }

    /// Letters and digits in a row, of any alphabet.
    static func tokens(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    // MARK: - The sentence

    /// **On unless he says otherwise**: `defaults write ro.victorrentea.wispr-relay
    /// transcriptGuard -bool false`, or `POST /test/transcript-guard {"on": false}`.
    static var isOn: Bool {
        get { UserDefaults.standard.object(forKey: "transcriptGuard") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "transcriptGuard") }
    }

    /// The chip, once a sentence has been fixed.
    static let notice = "💻 Foreign words fixed locally"
    /// `DictationResult.via` of a sentence the local model rewrote whole.
    static let via = "local-guard"
    /// Under the words, when nothing better could be found: they go out as they
    /// came, because a wrong sentence he can see beats one that never arrives.
    static let unfixed = "⚠️ These words may be in the wrong language — the local model could not do better"

    /// The sentence's verdict: its worst across what a plain sentence sends
    /// (`text`) and what a prompt sends (`unformatted`).
    static func judge(_ r: DictationResult) -> Verdict? {
        let all = [judge(r.text), r.unformatted.flatMap { judge($0) }].compactMap { $0 }
        return all.first { if case .wholeTake = $0 { return true } else { return false } } ?? all.first
    }

    /// **What goes out**, the engine's sentence and the local one in hand. A
    /// `retry` of nil is a local model that heard nothing or failed.
    ///
    /// Timed words (`ElevenLabs`) cannot be spliced — `ShotMarker.place` rebuilds
    /// the text from them, so a run mended in `text` would come straight back:
    /// such a sentence takes the local words whole, or stays as it was.
    static func resolve(_ held: DictationResult, retry: DictationResult?) -> (sentence: DictationResult, outcome: String) {
        func replaced() -> (DictationResult, String)? {
            guard var r = retry, accepts(retry: r.text, duration: held.duration) else { return nil }
            r.via = via
            return (r, "replaced")
        }
        var whole = held.words != nil
        var fields = [String: Verdict]()
        for (name, text) in [("text", Optional(held.text)), ("unformatted", held.unformatted)] {
            guard let text, let v = judge(text) else { continue }
            if case .wholeTake = v { whole = true }
            fields[name] = v
        }
        func kept() -> (DictationResult, String) {
            var r = held
            r.warning = unfixed
            return (r, "kept")
        }
        if whole { return replaced() ?? kept() }
        var out = held
        var outcome = "spliced"
        for (name, v) in fields {
            guard case .foreignRun(let a, let b, _) = v else { continue }
            let text = name == "text" ? held.text : held.unformatted ?? ""
            let fixed: String
            switch repair(text, start: a, end: b, retry: retry?.text ?? "", duration: held.duration) {
            case .replaced: return replaced() ?? kept()
            case .spliced(let t): fixed = t
            case .cut(let t): fixed = t; outcome = "cut"
            }
            if name == "text" { out.text = fixed } else { out.unformatted = fixed }
        }
        return (out, outcome)
    }

    // MARK: - The record

    /// **Every intervention, both sides of it** — the corpus keeps one text per
    /// clip, so the one that was thrown away lives here. Beside the corpus,
    /// appended forever, the way `fallback.jsonl` is.
    static var logURL: URL { Outbox.home.appendingPathComponent("transcript-guard.jsonl") }

    static func record(engine: String, duration: TimeInterval, why: String, outcome: String,
                       original: String, retry: String?, sent: String) {
        var row: [String: Any] = ["at": ISO8601DateFormatter().string(from: Date()), "engine": engine,
                                  "duration": duration, "why": why, "outcome": outcome,
                                  "original": original, "sent": sent]
        if let retry { row["retry"] = retry }
        guard var line = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys, .withoutEscapingSlashes]) else { return }
        line.append(0x0A)
        if let h = try? FileHandle(forWritingTo: logURL) {
            defer { try? h.close() }
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: line)
        } else {
            try? line.write(to: logURL)
        }
    }
}
