import Foundation

/// **Finding a session by something that was said in it** — the search behind
/// the field at the top of `RebindPanel`.
///
/// **Why the transcripts and not a list this app keeps.** `RebindHistory` knows
/// the twelve destinations the relay has spoken to, which is the right answer
/// while the session is still on screen and no answer at all for the one from
/// Tuesday afternoon. The thing Victor remembers about that one is a sentence —
/// *"trebuie să fie un search peste mesajele scrise de mine sau de agent … ca să
/// pot găsi sesiunea care îmi trebuie"* — and the sentence is written down, in
/// `~/.claude/projects/<folder>/<session>.jsonl`, by Claude Code itself.
///
/// **Nothing is indexed and nothing is held.** The scan is
/// `helpers/session_search.py`, which ripgreps the window down to the files that
/// contain the word at all and then streams those line by line; this side never
/// sees a transcript, only the rows the helper prints. That is Victor's
/// constraint as he put it — *"fără să mai ții lucruri în memorie, ci direct pe
/// jurnalele de sesiuni"* — and it is also what makes the answer current: there
/// is no cache that can be out of date, because there is no cache.
///
/// **A scan is an object so that it can be thrown away.** Every keystroke past
/// the debounce supersedes the one before it, and the run that is no longer
/// wanted has to stop reading — not finish quietly into a callback nobody is
/// listening to. `cancel()` kills the process; a cancelled run never calls back.
final class SessionSearch {

    /// One session the scan matched. A copy of the helper's row, and everything
    /// the panel draws.
    struct Hit {
        let session: String
        let folder: String
        /// The folder the session ran in, whole — the icon is drawn from it, and
        /// not every project of his is under `~/workspace`.
        let cwd: String
        let branch: String
        /// The `/rename` title, else the topic title Claude Code generated —
        /// the same string, by the same precedence, that Victor's
        /// `terminal-title.sh` hook has been writing into the tab's title. That
        /// is not a coincidence, it is the join: see `RebindPanel.liveTTY`.
        let title: String
        /// The words around the match, one line, already trimmed by the helper.
        let snippet: String
        /// `me` or `claude` — who said the matching sentence.
        let role: String
        let hits: Int
        let when: Date
        /// **`/dev/ttysNNN` as the session last reported it**, from the cache the
        /// title hook keeps at `/tmp/claude-terminal-title-<id>.tty`.
        let tty: String?
        /// **Whether this is the newest session to have claimed that tty** — a
        /// tab is reused and every session that ever sat in it left a claim, so
        /// the latest one is the tenant and the rest are history. It is half the
        /// liveness answer; the other half, *is the tab open at all*, only
        /// Terminal.app can give. See `RebindPanel.liveTTY`.
        let ttyOwner: Bool

        /// `petclinic@main`, and just `workspace` where there is no branch to
        /// name. **`HEAD` is not a branch** — it is what `rev-parse` says in a
        /// detached checkout and in a folder that is not a repo, and printed in
        /// a row it is a word that carries nothing.
        var label: String {
            branch.isEmpty || branch == "HEAD" ? folder : "\(folder)@\(branch)"
        }
    }

    /// The search window and how many rows are worth showing.
    ///
    /// Three weeks rather than everything: 2.4 GB of transcripts go back months,
    /// and a session older than a fortnight is one he reopens by name, not by
    /// remembering a sentence from it. Twenty-five rows because the panel shows
    /// six at a time and nobody scrolls past four screens of results — past that
    /// the query is the thing to fix, not the list.
    static let days = 21.0
    static let limit = 25

    private let process = Process()
    private var cancelled = false
    private var buffer = Data()

    private init() {}

    /// **Start a scan.** `onRow` fires on the main queue as each session is
    /// found — the panel fills in while the disk is still being read, which is
    /// the whole reason the helper streams — and `onDone` once, at the end.
    /// Returns nil when the helper cannot be found, which is the one case where
    /// the panel simply has no session half.
    @discardableResult
    static func run(query: String,
                    onRow: @escaping (Hit) -> Void,
                    onDone: @escaping (Int) -> Void) -> SessionSearch? {
        guard let helper = helperPath else {
            Log.info("🔎 session_search.py not found beside the binary")
            return nil
        }
        let search = SessionSearch()
        let pipe = Pipe()
        // Apple's python3 for `RecentProjects`' reason: the helper is pure
        // standard library, and probing for an interpreter costs more process
        // launches than the scan itself.
        search.process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        search.process.arguments = [helper,
                                    "--query", query,
                                    "--days", String(Int(days)),
                                    "--limit", String(limit)]
        search.process.standardOutput = pipe
        search.process.standardError = FileHandle.nullDevice

        var found = 0
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            search.buffer.append(chunk)
            // Rows are newline-delimited JSON and a read can land mid-row, so
            // only whole lines are taken and the tail is kept for the next one.
            while let nl = search.buffer.firstIndex(of: 0x0A) {
                let line = search.buffer.subdata(in: search.buffer.startIndex..<nl)
                search.buffer.removeSubrange(search.buffer.startIndex...nl)
                guard let row = try? JSONSerialization.jsonObject(with: line) as? [String: Any]
                else { continue }
                if row["done"] as? Bool == true { continue }
                guard let hit = Hit(row) else { continue }
                found += 1
                DispatchQueue.main.async {
                    guard !search.cancelled else { return }
                    onRow(hit)
                }
            }
        }
        search.process.terminationHandler = { _ in
            pipe.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async {
                guard !search.cancelled else { return }
                onDone(found)
            }
        }
        do {
            try search.process.run()
        } catch {
            Log.info("🔎 could not start the session scan — \(error)")
            return nil
        }
        return search
    }

    /// **Stop reading.** Called on the next keystroke and when the panel closes:
    /// the run is superseded, so its rows must not arrive late into a list that
    /// has moved on.
    func cancel() {
        guard !cancelled else { return }
        cancelled = true
        if process.isRunning { process.terminate() }
    }

    /// Beside the binary in the installed `.app`, in `helpers/` for a
    /// `swift build` run — the same walk `RecentProjects` and `Transcriber` do,
    /// so both ways of running the app find the script without a switch.
    private static var helperPath: String? {
        var candidates: [URL] = []
        if let res = Bundle.main.resourcePath {
            candidates.append(URL(fileURLWithPath: res).appendingPathComponent("session_search.py"))
        }
        let exe = URL(fileURLWithPath: CommandLine.arguments[0],
                      relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            .standardizedFileURL.resolvingSymlinksInPath()
        var dir = exe.deletingLastPathComponent()
        for _ in 0..<4 {
            candidates.append(dir.appendingPathComponent("helpers/session_search.py"))
            candidates.append(dir.appendingPathComponent("session_search.py"))
            dir = dir.deletingLastPathComponent()
        }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }?.path
    }
}

extension SessionSearch.Hit {
    /// One row of the helper's output. A row missing its session id is not a row.
    init?(_ row: [String: Any]) {
        guard let session = row["session"] as? String else { return nil }
        self.init(session: session,
                  folder: row["folder"] as? String ?? "",
                  cwd: row["cwd"] as? String ?? "",
                  branch: row["branch"] as? String ?? "",
                  title: row["title"] as? String ?? "",
                  snippet: row["snippet"] as? String ?? "",
                  role: row["role"] as? String ?? "",
                  hits: (row["hits"] as? NSNumber)?.intValue ?? 0,
                  when: Date(timeIntervalSince1970: (row["mtime"] as? NSNumber)?.doubleValue ?? 0),
                  tty: row["tty"] as? String,
                  ttyOwner: row["ttyOwner"] as? Bool ?? false)
    }
}
