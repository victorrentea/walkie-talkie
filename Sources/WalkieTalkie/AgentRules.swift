import Foundation

/// **The rules a dictation used to carry, held once by each agent instead**
/// (2026-11-12, Victor: *"I believe you're shoveling a lot of tokens in every of
/// your injected text into terminals … Everyone should know this instruction …
/// Walkie Talkie should have an installation process to set up these rules"*).
///
/// Two clauses rode under every sentence — `questionHint` (on a `?`) and
/// `dictionaryHint` (always), ~120 tokens a dictation — and neither changes
/// from one sentence to the next. They are instructions, not data, so they move
/// to where each harness reads its standing instructions, and the envelope keeps
/// only what does change: the engine and microphone, the folder, the frames.
///
/// | harness | where the rules live | how Walkie knows they are there |
/// |---|---|---|
/// | Claude Code | the `walkie-inbox` mod adds `rulesFile` as a system-prompt section (`prompt.compose`) | the mod's `.alive` beat on the tty says `rules: <version>`; a spawn reads `claudeStamp` |
/// | Codex CLI | a marked block in `~/.codex/AGENTS.md` | the block's version marker |
/// | Copilot CLI | a marked block in `~/.copilot/copilot-instructions.md` | the same |
///
/// **Anything else gets the whole envelope, as before** — the caret, an IDE chat,
/// a cloud session, a Claude whose mod is older, a harness Walkie cannot name.
/// A short envelope only ever goes where the version it relies on is proven
/// present, so raising `version` falls every agent back to the long form until
/// it has the new text.
enum AgentRules {
    /// Raise with any change to `text`.
    static let version = 1

    static var beginMarker: String { "<!-- walkie-talkie rules v\(version) -->" }
    static let beginPrefix = "<!-- walkie-talkie rules v"
    static let endMarker = "<!-- walkie-talkie rules end -->"

    static let text = """
    ## Walkie Talkie dictation (walkie-talkie rules v\(version))

    A prompt whose footer has a `[Transcribed in RO or EN by <engine> · <mic>]` clause \
    was dictated by Victor through Walkie Talkie: speech recognised in Romanian or English, \
    so expect misheard words. The bracketed lines under the words are metadata: `[📁=…]` the \
    folder of the screenshots, `[📸n = …]` a screenshot, `[📸n✂️…]` an area he cut out, \
    `[🎦n = …]` a screen recording, `[selected: …]` text he highlighted.

    - **He asked you a question** → besides answering, also run \
    `walkie-reply "<the answer in ≤2 short sentences>"` (add `--image <path>` when a small \
    picture says it better). Only to answer him — never to ask him something, never to report \
    work done.
    - **You are 100% sure a term he said came out misheard** (a name, a tool, a technical \
    word — not a Romanian ending) → also run \
    `walkie-dict add "<right spelling>" --heard "<as transcribed>"`. Silently, no need to tell him.
    """

    /// What the mod reads at its `session.start`: the marker line, then `text`.
    static var rulesFile: URL { Outbox.defaultHome.appendingPathComponent("agent-rules.md") }
    /// Written by the mod at its `session.start`: the version it loaded.
    static var claudeStamp: URL { Outbox.defaultHome.appendingPathComponent("agent-rules.claude") }

    static let harnessFiles: [(name: String, path: String)] = [
        ("codex", "~/.codex/AGENTS.md"),
        ("copilot", "~/.copilot/copilot-instructions.md"),
    ]

    // MARK: installing

    /// At launch, from the real instance only (a `--home` desk copy writes nothing).
    /// Idempotent: a file already holding this version's block is left untouched.
    static func install() {
        guard Outbox.home == Outbox.defaultHome else { return }
        let fm = FileManager.default
        let rules = beginMarker + "\n" + text + "\n"
        if (try? String(contentsOf: rulesFile, encoding: .utf8)) != rules {
            do {
                try rules.write(to: rulesFile, atomically: true, encoding: .utf8)
                Log.info("📜 agent rules v\(version) → \(rulesFile.path)")
            } catch { Log.error("📜 agent rules: \(rulesFile.path) not written — \(error)") }
        }
        for (name, raw) in harnessFiles {
            let path = (raw as NSString).expandingTildeInPath
            // A harness never installed here gets no folder made for it.
            guard fm.fileExists(atPath: (path as NSString).deletingLastPathComponent) else { continue }
            let old = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            let new = withBlock(old)
            guard new != old else { continue }
            do {
                try new.write(toFile: path, atomically: true, encoding: .utf8)
                Log.info("📜 agent rules v\(version) → \(name): \(path)")
            } catch { Log.error("📜 agent rules: \(path) not written — \(error)") }
        }
    }

    /// `file` with this version's block in place of any earlier one, or appended.
    static func withBlock(_ file: String) -> String {
        let block = beginMarker + "\n\n" + text + "\n\n" + endMarker
        if let start = file.range(of: beginPrefix),
           let end = file.range(of: endMarker, range: start.upperBound..<file.endIndex) {
            return file.replacingCharacters(in: start.lowerBound..<end.upperBound, with: block)
        }
        let trimmed = file.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
        return (trimmed.isEmpty ? "" : trimmed + "\n\n") + block + "\n"
    }

    // MARK: is the destination holding them?

    /// **Does the agent on `tty` hold this version of the rules?** False when in
    /// doubt — the long envelope is never wrong, only longer.
    static func known(onTTY tty: String) -> Bool {
        let device = (tty as NSString).lastPathComponent
        switch TerminalBinding.agentCLI(onTTY: device) {
        case "claude"?:
            return claudeBeat(onTTY: device).map { $0 >= version } ?? false
        case let cli?:
            return harnessHolds(cli)
        case nil:
            return false
        }
    }

    /// A new `claude` session is the mod as it loads now: the version the last
    /// `session.start` stamped.
    static func knownForSpawn() -> Bool {
        guard let s = try? String(contentsOf: claudeStamp, encoding: .utf8),
              let v = Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return v >= version
    }

    static func harnessHolds(_ cli: String) -> Bool {
        guard let raw = harnessFiles.first(where: { $0.name == cli })?.path,
              let file = try? String(contentsOfFile: (raw as NSString).expandingTildeInPath, encoding: .utf8)
        else { return false }
        return file.contains(beginMarker)
    }

    /// The `rules` the mod's `.alive` beat reports, when the beat is fresh (the
    /// mod writes it every 2 s; 10 s of silence is a session that is gone or
    /// a mod that stopped).
    static func claudeBeat(onTTY device: String) -> Int? {
        let url = Outbox.defaultHome.appendingPathComponent("inbox/\(device)/.alive")
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let at = (obj["at"] as? NSNumber)?.doubleValue,
              Date().timeIntervalSince1970 * 1000 - at < 10_000
        else { return nil }
        return (obj["rules"] as? NSNumber)?.intValue
    }
}
