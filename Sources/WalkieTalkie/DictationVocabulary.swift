import Foundation

/// **The English inside his Romanian, written down once** — the words every
/// recogniser in this app gets wrong in the same way, kept in one file instead of
/// one per vendor (2026-09-18).
///
/// It started as `speechmatics-vocab.txt`, because Speechmatics is where the
/// need was sharp: a real-time session there is pinned to **one** language, so
/// `git rebase` inside a Romanian sentence is being heard by a recogniser that
/// has been told the sentence is Romanian. But the list itself is not a fact
/// about Speechmatics. It is a fact about **Victor** — the same forty words come
/// back wrong on every engine, and a second copy of them under another vendor's
/// name is a second copy that goes stale.
///
/// So: `~/.walkie-talkie/vocab.txt`, and two ways of asking for it, because the
/// two engines that use it do not take vocabulary the same way:
///
/// | | how it is handed over | what `sounds_like` does |
/// |---|---|---|
/// | `SpeechmaticsSource` | `additional_vocab`, a structured field | pronunciations, used |
/// | `GeminiSource` | a line inside the prompt | ignored — an LLM does not need told |
///
/// **Re-read on every dictation, deliberately.** It is a list he edits the
/// moment a word comes back wrong, and a restart between noticing and fixing is
/// how a list like this stops being maintained.
enum DictationVocabulary {

    /// One term, plus how it is said when that was worth writing down.
    struct Entry {
        let content: String
        let soundsLike: [String]
    }

    /// **`vocab.txt`, with the old name still honoured.** The file was
    /// `speechmatics-vocab.txt` for the few hours between the two engines
    /// landing, and his copy may still be under that name with his own edits in
    /// it — which are the only edits that matter. Renaming a file out from under
    /// somebody's edits is how a list silently reverts to the shipped default.
    static var url: URL {
        let canonical = Outbox.home.appendingPathComponent("vocab.txt")
        if FileManager.default.fileExists(atPath: canonical.path) { return canonical }
        let legacy = Outbox.home.appendingPathComponent("speechmatics-vocab.txt")
        if FileManager.default.fileExists(atPath: legacy.path) { return legacy }
        return canonical
    }

    /// `term` or `term: sounds like, also like this`; `#` comments and blank
    /// lines ignored. Never throws and never logs: it is read at the start of
    /// every dictation, and a missing file means *no vocabulary*, which is a
    /// perfectly good answer.
    static func entries() -> [Entry] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var out: [Entry] = []
        for line in text.split(separator: "\n") {
            let row = line.trimmingCharacters(in: .whitespaces)
            guard !row.isEmpty, !row.hasPrefix("#") else { continue }
            guard let colon = row.firstIndex(of: ":") else {
                out.append(Entry(content: row, soundsLike: []))
                continue
            }
            let content = String(row[row.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
            guard !content.isEmpty else { continue }
            let sounds = String(row[row.index(after: colon)...])
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            out.append(Entry(content: content, soundsLike: sounds))
        }
        return out
    }

    /// **Speechmatics' shape.** Their ceiling is 20,000 and their own advice is
    /// under 1000; a list past that is not a dictionary any more, and sending it
    /// silently would turn a good session into a rejected one.
    static func speechmaticsVocab() -> [[String: Any]] {
        var entries = self.entries()
        if entries.count > 1000 {
            Log.error("\(url.lastPathComponent) has \(entries.count) entries — "
                      + "sending the first 1000, which is the vendor's own advice")
            entries = Array(entries.prefix(1000))
        }
        return entries.map { entry in
            entry.soundsLike.isEmpty ? ["content": entry.content]
                                     : ["content": entry.content, "sounds_like": entry.soundsLike]
        }
    }

    /// **A prompt's shape: the words, comma-separated, and nothing else.**
    ///
    /// The `sounds_like` column is dropped on purpose. It exists to tell an
    /// acoustic model what a word sounds like in Romanian mouth; a language
    /// model already knows, and handing it `comit, camit` as if they were terms
    /// would teach it two misspellings it did not have.
    ///
    /// Truncated by characters rather than by entries because what it is
    /// competing for is a prompt, and a prompt that crowds out the instruction
    /// above it is worse than a short list.
    static func promptTerms(limit: Int = 1500) -> String {
        var line = ""
        for entry in entries() {
            let next = line.isEmpty ? entry.content : line + ", " + entry.content
            if next.count > limit { break }
            line = next
        }
        return line
    }
}
