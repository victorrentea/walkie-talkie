import AppKit
import Foundation

/// 🧾 **How much of the ElevenLabs plan is left** — the last row under `Engine`
/// (2026-09-28). Victor: *"Eleven labs should show remaining/total and reset
/// date"*, first built into Victor Mac and moved here the same morning —
/// *"quota lui 11labs are sens doar in walkie - addons nu foloseste eleven labs
/// de loc."* The plan runs out silently; the first sign used to be a dictation
/// that came back empty.
///
/// `ElevenLabsCost` beside it is the other half and a different question: what
/// *this Mac* has sent, priced at the published rates. This one is what the
/// *account* says is left, read from the API.
///
/// **Where each number comes from**, in order:
/// 1. `GET /v1/user/subscription` — `character_count`, `character_limit` and
///    `next_character_count_reset_unix`, all three at once. It needs the key's
///    `user_read` permission; on 2026-09-28 the key in `elevenlabs.env` answered
///    `401 missing_permissions`.
/// 2. Without it, *used* is `GET /v1/usage/character-stats` summed over the
///    last 30 days (works with the scoped key) and *total* is `WT_ELEVEN_QUOTA`
///    from `elevenlabs.env`, else 10 000 — the same default the harness's
///    credit cap uses.
///
/// **The reset date is never guessed**: without `user_read` the row ends in
/// `/ ?` and the tooltip says how to fix the key. A made-up date reads as a
/// promise.
enum ElevenLabsQuotaPolicy {

    /// Rolling window for the fallback sum — the billing period is unknown
    /// without `user_read`, so this is the honest stand-in, and the tooltip
    /// names it.
    static let fallbackWindowDays = 30
    static let defaultQuota = 10_000

    struct Snapshot: Equatable {
        var used: Int
        var total: Int
        var reset: Date?
        /// Which endpoint each number came from — in the tooltip and in
        /// `/test/state.elevenQuota`, because *the number is wrong* is first a
        /// question of which of the two sources produced it.
        var usedSource: String
        var totalSource: String
        /// Raw HTTP status of `/v1/user/subscription` (nil = never answered).
        var subscriptionStatus: Int?
        var missingUserRead: Bool

        var remaining: Int { total - used }
        var exhausted: Bool { remaining <= 0 }
        /// `subscription` or `character-stats` — the short form `/test/state` carries.
        var source: String { usedSource.hasPrefix("/v1/user/subscription") ? "subscription" : "character-stats" }
    }

    enum SubscriptionRead: Equatable {
        case ok(used: Int?, limit: Int?, reset: Date?)
        case missingUserRead
        case failed(String)
    }

    static func quota(from raw: String?) -> Int? {
        guard let raw else { return nil }
        return Int(raw.replacingOccurrences(of: "_", with: "").replacingOccurrences(of: " ", with: ""))
    }

    // MARK: - Responses

    static func parseSubscription(status: Int, body: Data) -> SubscriptionRead {
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        if status == 200, let json {
            let reset = (json["next_character_count_reset_unix"] as? NSNumber)
                .map { Date(timeIntervalSince1970: $0.doubleValue) }
            return .ok(used: (json["character_count"] as? NSNumber)?.intValue,
                       limit: (json["character_limit"] as? NSNumber)?.intValue,
                       reset: reset)
        }
        let detail = json?["detail"] as? [String: Any]
        if status == 401 || status == 403, detail?["status"] as? String == "missing_permissions" {
            return .missingUserRead
        }
        let message = detail?["message"] as? String
            ?? String(data: body.prefix(200), encoding: .utf8) ?? ""
        return .failed("HTTP \(status) \(message)")
    }

    /// `{"time":[…],"usage":{"All":[…]}}` → the sum of every series.
    static func sumCharacterStats(_ body: Data) -> Int? {
        guard let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let usage = json["usage"] as? [String: Any] else { return nil }
        var total = 0.0
        for case let series as [Any] in usage.values {
            for case let n as NSNumber in series { total += n.doubleValue }
        }
        return Int(total.rounded())
    }

    // MARK: - Drawing

    /// `10000` → `10 000`, `-33` → `−33`.
    static func group(_ n: Int) -> String {
        let digits = String(abs(n))
        var out = ""
        for (i, c) in digits.enumerated() {
            if i > 0, (digits.count - i) % 3 == 0 { out.append(" ") }
            out.append(c)
        }
        return (n < 0 ? "−" : "") + out
    }

    /// `10000` → `10k`, `1500` → `1.5k`, `100000` → `100k`; under 1000 as is.
    static func kilo(_ n: Int) -> String {
        guard abs(n) >= 1000 else { return String(n) }
        let k = Double(n) / 1000
        let text = k == k.rounded() ? String(Int(k)) : String(format: "%.1f", k)
        return text.replacingOccurrences(of: ".0", with: "") + "k"
    }

    /// `Oct 30`, or `?` when the reset date is unknown.
    static func resetText(_ date: Date?, timeZone: TimeZone = .current) -> String {
        guard let date else { return "?" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }

    /// Compact on purpose (Victor: *"33 / 10k / Oct 30"*): **used** / total /
    /// reset — used, not remaining, since 2026-09-28 08:50 (*"afișează
    /// consumat, nu rămas înainte de /"*). The words live in the tooltip.
    static func title(_ s: Snapshot?, error: String?, timeZone: TimeZone = .current) -> String {
        guard let s else {
            return error == nil ? "🧾 ElevenLabs …" : "🧾 ElevenLabs ?"
        }
        return "🧾 ElevenLabs \(group(s.used)) / \(kilo(s.total)) / \(resetText(s.reset, timeZone: timeZone))"
    }

    // MARK: - Pace

    /// The row's colour is a **trend**, not a level (2026-09-28: *"verde când
    /// mai e mult, portocaliu sau roșu când ard mai mult decât trebuie ca
    /// trend, proporțional cu zilele rămase"*): the plan is being spent at
    /// some rate, and the question is whether that rate lands inside the
    /// total by the reset, not how much is left today.
    enum Pace: String { case green, orange, red }

    /// The billing period is a month; the API only says when it ends.
    static let periodDays = 30.0
    /// Over trend by less than this → orange; more → red.
    static let orangeAbove = 1.0
    static let redAbove = 1.5

    /// `used / (total × elapsed)`: 1 means exactly on trend, 2 means burning
    /// twice what the days so far allow. `elapsed` is the share of the period
    /// gone by, from the reset date, floored at one day so the first hour of a
    /// new period does not paint a single dictation red. With no reset date
    /// the used figure is a rolling 30-day sum (`fallbackWindowDays`), i.e.
    /// a full period, so `elapsed` is 1 and the trend is simply used / total.
    static func burnRate(_ s: Snapshot, now: Date = Date()) -> Double {
        guard s.total > 0 else { return s.used > 0 ? .infinity : 0 }
        var elapsed = 1.0
        if let reset = s.reset {
            let daysLeft = max(0, reset.timeIntervalSince(now) / 86_400)
            elapsed = min(1, max(1 / periodDays, (periodDays - daysLeft) / periodDays))
        }
        return Double(s.used) / (Double(s.total) * elapsed)
    }

    static func pace(_ s: Snapshot, now: Date = Date()) -> Pace {
        if s.exhausted { return .red }
        let rate = burnRate(s, now: now)
        if rate > redAbove { return .red }
        if rate > orangeAbove { return .orange }
        return .green
    }

    /// One line for the tooltip: what the trend says the period ends at.
    static func paceText(_ s: Snapshot, now: Date = Date()) -> String {
        let rate = burnRate(s, now: now)
        guard rate.isFinite else { return "No plan total to measure the trend against." }
        let projected = Int((Double(s.total) * rate).rounded())
        let verdict: String
        switch pace(s, now: now) {
        case .green: verdict = "on trend"
        case .orange: verdict = "over trend"
        case .red: verdict = s.exhausted ? "spent" : "far over trend"
        }
        return "Trend: \(group(projected)) of \(group(s.total)) by the reset (×\(String(format: "%.2f", rate)), \(verdict))."
    }

    static func tooltip(_ s: Snapshot?, error: String?, fetchedAt: Date?, now: Date = Date()) -> String {
        var lines: [String] = []
        if let s {
            lines.append("Used \(group(s.used)) of \(group(s.total)) credits — \(group(s.remaining)) left.")
            if let reset = s.reset { lines.append("Resets \(resetText(reset)).") }
            lines.append(paceText(s, now: now))
            lines.append("Used: \(s.usedSource). Total: \(s.totalSource).")
            if s.missingUserRead {
                lines.append("Reset date unknown: the API key lacks the user_read permission "
                             + "(/v1/user/subscription answered \(s.subscriptionStatus.map(String.init) ?? "?")). "
                             + "Add it to the key at elevenlabs.io → API keys, and the real period and reset date appear here.")
            } else if s.reset == nil {
                lines.append("Reset date unknown: /v1/user/subscription gave none.")
            }
        }
        if let error { lines.append("Last check failed: \(error)") }
        if let fetchedAt {
            let mins = Int(now.timeIntervalSince(fetchedAt) / 60)
            lines.append(mins < 1 ? "Checked just now." : "Checked \(mins) min ago.")
        }
        lines.append("Click to open ElevenLabs.")
        return lines.joined(separator: "\n")
    }
}

/// Fetches off the main thread, caches, and hands the menu a finished title.
/// Refreshed on menu open when older than 5 min, and every 30 min regardless.
/// `@unchecked Sendable`: every stored property is touched on the main thread
/// only — the key and the quota are read there and handed to the detached
/// fetch, which reads nothing else and lands its result back on main.
final class ElevenLabsQuota: @unchecked Sendable {
    static let shared = ElevenLabsQuota()

    static let menuMaxAge: TimeInterval = 5 * 60
    static let backgroundEvery: TimeInterval = 30 * 60

    private(set) var snapshot: ElevenLabsQuotaPolicy.Snapshot?
    private(set) var lastError: String?
    private(set) var fetchedAt: Date?
    private var inFlight = false
    private var timer: Timer?

    /// Main thread, after every fetch.
    var onChange: (() -> Void)?

    var title: String { ElevenLabsQuotaPolicy.title(snapshot, error: lastError) }
    var tooltip: String { ElevenLabsQuotaPolicy.tooltip(snapshot, error: lastError, fetchedAt: fetchedAt) }
    var exhausted: Bool { snapshot?.exhausted ?? false }
    /// The row's colour; nil before the first answer (plain menu text).
    var pace: ElevenLabsQuotaPolicy.Pace? { snapshot.map { ElevenLabsQuotaPolicy.pace($0) } }

    /// The key page when the fix is a permission there, the subscription page
    /// otherwise.
    var clickURL: URL {
        URL(string: snapshot?.missingUserRead == true
            ? "https://elevenlabs.io/app/settings/api-keys"
            : "https://elevenlabs.io/app/subscription")!
    }

    func start() {
        guard timer == nil else { return }
        refresh()
        let t = Timer(timeInterval: Self.backgroundEvery, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func refreshIfStale() {
        if let fetchedAt, Date().timeIntervalSince(fetchedAt) < Self.menuMaxAge { return }
        refresh()
    }

    /// Main thread. The key is read the way `ElevenLabsSource.reloadKey` reads
    /// it — the environment first, then `elevenlabs.env` (which follows
    /// `--home`, so a scratch relay does not query his account).
    func refresh() {
        guard !inFlight else { return }
        let key = ProcessInfo.processInfo.environment["ELEVENLABS_API_KEY"]
            ?? ElevenLabsSource.fileValue("ELEVENLABS_API_KEY")
        let quota = ElevenLabsQuotaPolicy.quota(from: ProcessInfo.processInfo.environment["WT_ELEVEN_QUOTA"]
                                                ?? ElevenLabsSource.fileValue("WT_ELEVEN_QUOTA"))
        inFlight = true
        Task.detached(priority: .utility) {
            let (snap, error) = await Self.fetch(key: key, quota: quota)
            // `.common`, not `DispatchQueue.main.async`: the menu is usually
            // open while this lands, and its tracking loop does not drain the
            // main queue — the row would only update after it closed.
            RunLoop.main.perform(inModes: [.common]) { [weak self] in
                guard let self else { return }
                self.inFlight = false
                if let snap { self.snapshot = snap }
                self.lastError = error
                self.fetchedAt = Date()
                if let error { Log.info("🧾 ElevenLabs quota: \(error)") }
                self.onChange?()
            }
        }
    }

    /// `GET /test/state.elevenQuota` — `{used, total, remaining, reset, source}`
    /// plus the row as drawn; `NSNull` before the first answer.
    func describe() -> Any {
        guard let s = snapshot else { return NSNull() }
        return [
            "used": s.used, "total": s.total, "remaining": s.remaining,
            "reset": s.reset.map { Outbox.iso($0) } ?? NSNull(),
            "source": s.source,
            "subscriptionStatus": s.subscriptionStatus ?? NSNull(),
            "missingUserRead": s.missingUserRead,
            "pace": ElevenLabsQuotaPolicy.pace(s).rawValue,
            "burnRate": ElevenLabsQuotaPolicy.burnRate(s),
            "title": title,
            "error": lastError ?? NSNull(),
            "fetchedAt": fetchedAt.map { Outbox.iso($0) } ?? NSNull(),
        ] as [String: Any]
    }

    // MARK: - Network (off the main thread)

    private static func get(_ url: URL, key: String) async -> (Int?, Data) {
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue(key, forHTTPHeaderField: "xi-api-key")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            return ((resp as? HTTPURLResponse)?.statusCode, data)
        } catch {
            return (nil, Data(error.localizedDescription.utf8))
        }
    }

    static func fetch(key: String?, quota: Int?) async -> (ElevenLabsQuotaPolicy.Snapshot?, String?) {
        guard let key, !key.isEmpty else {
            return (nil, "no ELEVENLABS_API_KEY in ~/.walkie-talkie/elevenlabs.env")
        }
        let base = "https://api.elevenlabs.io/v1"
        let (subStatus, subBody) = await get(URL(string: "\(base)/user/subscription")!, key: key)

        var used: Int?, limit: Int?, reset: Date?
        var missingUserRead = false
        var subError: String?
        if let subStatus {
            switch ElevenLabsQuotaPolicy.parseSubscription(status: subStatus, body: subBody) {
            case let .ok(u, l, r): used = u; limit = l; reset = r
            case .missingUserRead: missingUserRead = true
            case let .failed(msg): subError = msg
            }
        } else {
            subError = String(data: subBody, encoding: .utf8)
        }

        var usedSource = "/v1/user/subscription"
        if used == nil {
            let end = Date()
            let start = end.addingTimeInterval(-Double(ElevenLabsQuotaPolicy.fallbackWindowDays) * 86_400)
            var c = URLComponents(string: "\(base)/usage/character-stats")!
            c.queryItems = [
                URLQueryItem(name: "start_unix", value: String(Int64(start.timeIntervalSince1970 * 1000))),
                URLQueryItem(name: "end_unix", value: String(Int64(end.timeIntervalSince1970 * 1000))),
                URLQueryItem(name: "breakdown_type", value: "none"),
            ]
            let (status, body) = await get(c.url!, key: key)
            guard status == 200, let sum = ElevenLabsQuotaPolicy.sumCharacterStats(body) else {
                let msg = String(data: body.prefix(200), encoding: .utf8) ?? ""
                return (nil, "character-stats HTTP \(status.map(String.init) ?? "—") \(msg)"
                        + (subError.map { "; subscription: \($0)" } ?? ""))
            }
            used = sum
            usedSource = "/v1/usage/character-stats, last \(ElevenLabsQuotaPolicy.fallbackWindowDays) days"
        }

        let total: Int
        let totalSource: String
        if let limit, limit > 0 {
            total = limit; totalSource = "/v1/user/subscription"
        } else if let quota, quota > 0 {
            total = quota; totalSource = "WT_ELEVEN_QUOTA"
        } else {
            total = ElevenLabsQuotaPolicy.defaultQuota; totalSource = "default 10 000"
        }

        let snap = ElevenLabsQuotaPolicy.Snapshot(
            used: used ?? 0, total: total, reset: reset,
            usedSource: usedSource, totalSource: totalSource,
            subscriptionStatus: subStatus, missingUserRead: missingUserRead)
        return (snap, subError)
    }
}
