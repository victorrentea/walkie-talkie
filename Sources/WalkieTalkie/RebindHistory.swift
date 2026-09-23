import Foundation

/// **Every destination the relay has been pointed at, most recent first** — the
/// list behind the menu's *Rebind to*.
///
/// **The problem it answers is Victor's, said plainly: *"nu mai știu în ce
/// terminal am făcut ce task"*.** A day's work is fifteen to twenty Claude Code
/// sessions in Terminal.app, and by the afternoon the window that was fixing the
/// Bluetooth keep-alive is somewhere in the pile behind PowerPoint. Everything
/// needed to find it again was already being computed and then thrown away: a
/// `Target` is built on every bind and replaced on the next one, and nothing
/// kept the one before.
///
/// **It is a log of bindings, not a scan of the machine.** Nothing here goes
/// looking for terminals — a session Victor never spoke to does not appear, by
/// design (*"strict ceva recent"*). What earns a row is having been a
/// destination, which is also what makes the list short enough to read.
///
/// **Keyed by `address`.** `ttys016`, `%3`, `IntelliJ IDEA` — the same string
/// the chip shows, and the only identifier stable across the whole life of a
/// binding. Pointing at the same terminal twice moves its row to the top rather
/// than growing a second one; two rows for one tty would be exactly the
/// confusion this is meant to end.
///
/// **It survives a restart, and that is the point rather than a nicety.** This
/// app is rebuilt and relaunched several times an hour while it is being worked
/// on, and a list that emptied every time would be empty precisely on the days
/// it is needed. `~/.walkie-talkie/rebind-history.json`, beside the outbox and
/// `bound-tty`.
final class RebindHistory {

    static let shared = RebindHistory()

    /// One destination the relay has spoken to.
    ///
    /// The fields are a **copy** of the `Target`, not a reference to it: a
    /// target is discarded the moment the binding moves, and half of what makes
    /// a row readable — which repo, which branch, what the agent was calling
    /// itself — exists nowhere else afterwards.
    struct Entry: Codable, Equatable {
        /// **What a rebind is made from**, and nil for the destinations that
        /// cannot be remade: `.keystroke` has no tty at all. Stored in the
        /// device-path spelling `bind(tty:)` wants, so a row is handed straight
        /// back to the call that created it.
        var tty: String?
        /// `ttys016`, `%3`, `IntelliJ IDEA` — the row's identity, and what the
        /// menu prints when two rows are otherwise the same repo.
        var address: String
        /// `petclinic@main` — folder and branch, the one thing a terminal title
        /// never carries.
        var label: String
        var appName: String
        var bundleID: String
        /// **The title as it read at the last moment we held the binding.** The
        /// menu prefers the *live* title when the tab is still open — an agent
        /// keeps rewriting it as it works — and falls back to this for a window
        /// that has since been closed, which is the only account of it left.
        var title: String?
        var boundAt: Date
        /// **When the binding moved off this destination**, nil while it is the
        /// one currently held. Stamped from three places, because a binding ends
        /// in three ways: `unbind()`, a bind that displaces it, and a delivery
        /// that finds the target gone — see `TerminalBinding.adopt`.
        var unboundAt: Date?
        /// **Whether this app opened the window itself** (`SpawnTerminal`) as
        /// opposed to being pointed at one already on screen. Victor's ask: a
        /// session he started by talking at nothing reads differently from one he
        /// had already been working in, and the menu marks it ✨.
        ///
        /// **Sticky.** Re-binding a spawned window later does not make it stop
        /// having been spawned, so the flag is kept rather than overwritten.
        var spawned: Bool

        /// The moment the row is sorted by: when we last let go, or — while it
        /// is the live binding — when we took it.
        var lastContact: Date { unboundAt ?? boundAt }
        var isCurrent: Bool { unboundAt == nil }
    }

    /// **How many rows the menu may grow to.** A submenu is scanned, not read,
    /// and past a dozen the thing being looked for is below the fold — at which
    /// point the list has recreated the problem it exists to solve.
    static let capacity = 12

    private let lock = NSLock()
    private var entries: [Entry]
    private let url: URL

    init(url: URL = Outbox.home.appendingPathComponent("rebind-history.json")) {
        self.url = url
        self.entries = Self.load(from: url)
    }

    // MARK: - Recording

    /// **The binding moved onto `target`.** Called from `TerminalBinding.adopt`,
    /// on whatever background thread the bind ran on.
    func adopted(_ target: TerminalBinding.Target, spawned: Bool) {
        mutate { entries in
            var entry = Entry(tty: target.handle.deviceTTY,
                              address: target.address,
                              label: target.label,
                              appName: target.appName,
                              bundleID: target.bundleID,
                              title: target.title,
                              boundAt: target.boundAt,
                              unboundAt: nil,
                              spawned: spawned)
            if let i = entries.firstIndex(where: { $0.address == target.address }) {
                // Seen before: the row moves to the top, and the ✨ it earned the
                // first time comes with it.
                entry.spawned = entry.spawned || entries[i].spawned
                entry.title = entry.title ?? entries[i].title
                entries.remove(at: i)
            }
            entries.insert(entry, at: 0)
            if entries.count > Self.capacity {
                entries.removeLast(entries.count - Self.capacity)
            }
        }
    }

    /// **The binding let go of `target`.** The title is refreshed on the way out
    /// because this is the last instant anything knows it.
    func released(_ target: TerminalBinding.Target) {
        mutate { entries in
            guard let i = entries.firstIndex(where: { $0.address == target.address }) else { return }
            entries[i].unboundAt = Date()
            if let title = target.title { entries[i].title = title }
        }
    }

    // MARK: - Reading

    var all: [Entry] {
        lock.lock(); defer { lock.unlock() }
        return entries.sorted { $0.lastContact > $1.lastContact }
    }

    /// One menu row, already decided: AppKit's side of this only has to draw it.
    struct Row {
        /// Handed straight to `TerminalBinding.bind(tty:)`. nil when the row
        /// cannot be rebound at all.
        let tty: String?
        let title: String
        let bundleID: String
        /// False for the destination already bound (a rebind there is a no-op),
        /// for a window that has since been closed, and for the handles that
        /// never had a tty to be found by.
        let enabled: Bool
    }

    /// **The rows, resolved against the terminals that are actually open.**
    ///
    /// `live` maps `ttysNNN` to the title the tab is showing *now* — one
    /// AppleScript round trip for every window, made by the caller because it is
    /// the caller that knows when the submenu is about to be drawn. A tty absent
    /// from that map is a window that has been closed: the row stays, so the
    /// history does not quietly rewrite itself, but it cannot be clicked.
    func rows(live: [String: String], boundAddress: String?, now: Date = Date()) -> [Row] {
        all.map { entry in
            let short = entry.tty.map { ($0 as NSString).lastPathComponent }
            let liveTitle = short.flatMap { live[$0] }
            let isBound = entry.address == boundAddress
            let name = liveTitle ?? entry.title ?? entry.label
            var line = name
            if entry.spawned { line += " ✨" }
            line += "  —  \(entry.label) · \(entry.address) · "
            line += isBound ? "bound" : Self.elapsed(since: entry.lastContact, now: now)
            return Row(tty: entry.tty,
                       title: line,
                       bundleID: entry.bundleID,
                       enabled: !isBound && entry.tty != nil && liveTitle != nil)
        }
    }

    /// `42s ago`, `7 min ago`, `2 h ago`, `3 d ago`.
    ///
    /// **Seconds are spelled out below a minute** and not rounded away — Victor
    /// asked for *"câte secunde a trecut de când m-am deconectat"*, and the
    /// binding he wants back is very often the one he left ninety seconds ago.
    static func elapsed(since: Date, now: Date = Date()) -> String {
        let s = max(0, Int(now.timeIntervalSince(since)))
        if s < 60 { return "\(s)s ago" }
        if s < 3600 { return "\(s / 60) min ago" }
        if s < 86_400 { return "\(s / 3600) h ago" }
        return "\(s / 86_400) d ago"
    }

    // MARK: - Disk

    private func mutate(_ change: (inout [Entry]) -> Void) {
        lock.lock()
        change(&entries)
        let snapshot = entries
        lock.unlock()
        save(snapshot)
    }

    private func save(_ entries: [Entry]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try encoder.encode(entries).write(to: url, options: .atomic)
        } catch {
            // A history that cannot be written is worth a line and nothing more:
            // every binding it describes still works.
            Log.error("📜 could not write the rebind history — \(error)")
        }
    }

    private static func load(from url: URL) -> [Entry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let entries = try? decoder.decode([Entry].self, from: data) else {
            Log.error("📜 the rebind history on disk could not be read — starting empty")
            return []
        }
        // **Nothing is bound at launch.** An entry saved while it was the live
        // binding has no `unboundAt`, and left that way it would claim to be
        // current in an app that has just started with nothing pointed anywhere.
        // The app's own launch is when that binding ended.
        let launched = Date()
        return entries.map { entry in
            var entry = entry
            if entry.unboundAt == nil { entry.unboundAt = launched }
            return entry
        }
    }
}
