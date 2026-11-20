import Foundation

/// **What goes on the spawn menu: the ones he pinned, and every folder in
/// `~/workspace` he has touched lately.**
///
/// `SpawnFolderMenu` used to name six folders hardcoded in Swift — the projects
/// Victor happened to be working on the afternoon it was written. That list is
/// wrong the week after and wrong *silently*: a project missing from it costs
/// the first sentence of every session started in it, spoken out loud to tell
/// the agent where it is, which is the exact cost the menu exists to remove.
///
/// | where | source | who decides |
/// |---|---|---|
/// | the menu itself | `PinnedProjects` — a file he edits by clicking a star | him, explicitly |
/// | the *Workspace ›* submenu | `WorkspaceFolders` — the folders with a file changed this month | the disk |
///
/// **The two are read the same way and written very differently**, and that is
/// the point of keeping them in one file: a pin is a decision and survives
/// everything, while the workspace listing is an observation and is replaced
/// wholesale by every scan.
///
/// The five most-worked repos of the fortnight, ranked off Claude Code's
/// transcripts (`RecentProjects`, 2026-09-08), sat under the pinned ones until
/// 2026-10-15 — Victor: *"I never used the last section of projects under the
/// last line … instead, put a menu called Workspace"*.

// MARK: - Workspace

/// **Every folder in `~/workspace` with a file changed in the last month**, in
/// three sections — the last day, the last week, the last month — each sorted
/// by name. Victor, 2026-10-15: *"all the folders in the workspace, except those
/// already present in the list … sorted descending by the last modified date of
/// any file within them … group them in sections … over the last day, then …
/// the last week, and the last month. And then inside each section … ascending
/// by name … with a star to get them onto the main list"*.
///
/// **Scanned in the background, never at the gesture.** Walking ~150 folders
/// for their newest file reads ~290 000 entries and takes ~9 s (measured
/// 2026-10-15), so the menu shows the last scan and asks for a new one when it
/// is older than `maxAge`; the very first opening after a launch may say
/// `Looking…` until the launch's own scan lands.
enum WorkspaceFolders {

    struct Folder: Equatable {
        let name: String
        let path: String
        let modified: Date
    }

    /// The submenu's sections, newest first.
    enum Section: CaseIterable {
        case day, week, month

        var title: String {
            switch self {
            case .day: return "Last day"
            case .week: return "Last week"
            case .month: return "Last month"
            }
        }

        /// The oldest change that still lands in this section.
        var maxAge: TimeInterval {
            switch self {
            case .day: return 24 * 3600
            case .week: return 7 * 24 * 3600
            case .month: return 31 * 24 * 3600
            }
        }
    }

    static var root: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("workspace")
    }

    /// **Not looked into: what a build, an IDE or git rewrites on its own.** A
    /// `git fetch`, an IntelliJ opening a project or a Gradle daemon touch files
    /// in folders he did not work in; and `node_modules` / `.build` are most of
    /// the 290 000 entries.
    static let skipped: Set<String> = [".git", "node_modules", ".build", "build", "target", ".gradle",
                                       ".idea", "dist", "out", "__pycache__", ".venv", "venv",
                                       "DerivedData", ".next", ".angular"]

    /// A scan older than this is redone, in the background, at the next gesture.
    static let maxAge: TimeInterval = 5 * 60

    /// The last scan, nil until one has landed.
    private(set) static var last: [Folder]?
    private static var scannedAt: Date?
    private static var scanning = false
    private static var waiting: [([Folder]) -> Void] = []

    /// **The pure half** (`swift test`): drop the pinned and what is older than a
    /// month, bucket the rest, sort each bucket by name. Empty sections are left
    /// out.
    static func sections(_ folders: [Folder], excluding pinned: Set<String>,
                         now: Date = Date()) -> [(section: Section, folders: [Folder])] {
        let offered = folders.filter { !pinned.contains($0.path) }
        var out: [(section: Section, folders: [Folder])] = []
        var lower: TimeInterval = -.infinity
        for section in Section.allCases {
            let these = offered
                .filter { let age = now.timeIntervalSince($0.modified); return age > lower && age <= section.maxAge }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            if !these.isEmpty { out.append((section, these)) }
            lower = section.maxAge
        }
        return out
    }

    /// Scan if the last one is older than `maxAge` (or there is none), and call
    /// `done` on the main thread with the result — at once with nothing when the
    /// scan is fresh, since `last` is already the answer.
    static func refreshIfStale(_ done: (([Folder]) -> Void)? = nil) {
        if let at = scannedAt, Date().timeIntervalSince(at) < maxAge { return }
        if let done { waiting.append(done) }
        guard !scanning else { return }
        scanning = true
        DispatchQueue.global(qos: .utility).async {
            let t0 = Date()
            let found = scan()
            DispatchQueue.main.async {
                adopt(found)
                scanning = false
                Log.info("workspace: \(found.count) folders changed this month (\(String(format: "%.1f", Date().timeIntervalSince(t0))) s)")
                let calls = waiting
                waiting = []
                calls.forEach { $0(found) }
            }
        }
    }

    /// Take `found` as the answer, as of now.
    static func adopt(_ found: [Folder]) {
        last = found
        scannedAt = Date()
    }

    /// The folders of `~/workspace` (not hidden, not symlinks) with their newest
    /// file, kept only when that is within the last month. A folder stops being
    /// walked the moment a file younger than a day turns up — it cannot get any
    /// newer than its section.
    static func scan(now: Date = Date()) -> [Folder] {
        let fm = FileManager.default
        let tops = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                                                options: [.skipsHiddenFiles])) ?? []
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey]
        let month = Section.month.maxAge, day = Section.day.maxAge
        return tops.compactMap { top in
            let kind = try? top.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard kind?.isDirectory == true, kind?.isSymbolicLink != true,
                  let walk = fm.enumerator(at: top, includingPropertiesForKeys: keys, options: [],
                                           errorHandler: { _, _ in true })
            else { return nil }
            var newest = Date.distantPast
            for case let url as URL in walk {
                guard let v = try? url.resourceValues(forKeys: Set(keys)) else { continue }
                if v.isDirectory == true {
                    if skipped.contains(url.lastPathComponent) { walk.skipDescendants() }
                    continue
                }
                guard let m = v.contentModificationDate, m > newest else { continue }
                newest = m
                if now.timeIntervalSince(m) < day { break }
            }
            guard now.timeIntervalSince(newest) <= month else { return nil }
            return Folder(name: top.lastPathComponent, path: top.path, modified: newest)
        }
    }
}

// MARK: - Pins

/// The projects he put above the line himself, by clicking the star.
///
/// **A pin is the answer to a question measurement cannot answer**: a repo he is
/// about to start working in has no transcripts behind it yet, and one he keeps
/// coming back to between long gaps drops out of a fortnight's ranking exactly
/// when he needs it. The star is how he overrules the measurement in both
/// directions — and unpinning is not a delete: *"acel proiect să apară în lista
/// de proiecte recente, doar dacă am deschis recent în acel folder vreo muncă"*,
/// which is what falling back into `WorkspaceFolders` already does, with the
/// qualification built in.
enum PinnedProjects {

    static var url: URL { Outbox.home.appendingPathComponent("pinned-projects.json") }

    /// **What the menu held before the star existed**, and what a fresh install
    /// starts with. Seeding rather than starting empty is the continuity call:
    /// this list is the folders the menu has named for days, and the first
    /// spawn after an update should show him the menu he knows, with a star
    /// beside each row explaining how it got that way.
    private static let seed = ["victor-mac", "training-assistant",
                              "walkie-talkie", "victor-vsc", "petclinic", "human-review",
                              "victor-effects"]

    private static var cached: [String]?

    /// The pinned paths, in the order they were written. Order does not matter —
    /// the menu sorts — but rewriting the file on every read would.
    static func paths() -> [String] {
        if let cached { return cached }
        let stored: [String]
        if let data = try? Data(contentsOf: url),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let rows = root["pinned"] as? [String] {
            stored = rows
        } else {
            stored = seed.map {
                FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("workspace").appendingPathComponent($0).path
            }
        }
        // A folder that is gone is dropped on the way out but left in the file:
        // an external disk or a checkout he will make again should not cost him
        // the pin. Only a click takes one off.
        let live = stored.filter { FileManager.default.fileExists(atPath: $0) }
        cached = live
        return live
    }

    static func isPinned(_ path: String) -> Bool { paths().contains(path) }

    /// Star or unstar, and write it down. Returns the new state.
    @discardableResult
    static func toggle(_ path: String) -> Bool {
        var live = paths()
        let pinning = !live.contains(path)
        if pinning { live.append(path) } else { live.removeAll { $0 == path } }
        cached = live
        save(live)
        return pinning
    }

    private static func save(_ paths: [String]) {
        let payload: [String: Any] = ["pinned": paths]
        guard let data = try? JSONSerialization.data(withJSONObject: payload,
                                                     options: [.prettyPrinted, .sortedKeys])
        else { return }
        try? FileManager.default.createDirectory(at: Outbox.home,
                                                 withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
