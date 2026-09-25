import Foundation

/// **What ElevenLabs has billed so far, kept on this Mac** (2026-09-26 —
/// Victor: *"vreau să contorizezi costul acumulat în meniu la Engine în
/// dreptul lui ElevenLabs"*). Seconds of audio, by product, since the day the
/// counter was born; the money is those seconds at the published rates the
/// engine rows already quote (`ElevenLabsSource.rate`, `ElevenLabsLive.rate`),
/// so the row and the invoice can only disagree if the rates do — **if they
/// disagree, the invoice is right.** Nothing here is read back from the API.
///
/// Counted at the moment the audio is *sent*: a batch upload that answered 200
/// (`ElevenLabsSource.transcribe`, final and rolling), and a live session at its
/// close (`ElevenLabsLive.stop`) for every second it streamed. Keyterms add
/// their published 20 % to the live seconds that carried them.
enum ElevenLabsCost {

    private static let batchKey = "elevenCostBatchSeconds"     // [model: seconds]
    private static let liveKey = "elevenCostLiveSeconds"
    private static let liveKeytermsKey = "elevenCostLiveKeytermSeconds"
    private static let sinceKey = "elevenCostSince"

    static let realtimeRate = 0.39          // $/h, elevenlabs.io/pricing/api, 2026-09-25
    static let keytermsPremium = 0.20

    static func addBatch(seconds: Double, model: String) {
        guard seconds > 0 else { return }
        let d = UserDefaults.standard
        var table = d.dictionary(forKey: batchKey) as? [String: Double] ?? [:]
        table[model, default: 0] += seconds
        d.set(table, forKey: batchKey)
        stamp()
    }

    static func addLive(seconds: Double, keyterms: Bool) {
        guard seconds > 0 else { return }
        let d = UserDefaults.standard
        d.set(d.double(forKey: liveKey) + seconds, forKey: liveKey)
        if keyterms { d.set(d.double(forKey: liveKeytermsKey) + seconds, forKey: liveKeytermsKey) }
        stamp()
    }

    private static func stamp() {
        let d = UserDefaults.standard
        if d.object(forKey: sinceKey) == nil { d.set(Date(), forKey: sinceKey) }
    }

    static var since: Date? { UserDefaults.standard.object(forKey: sinceKey) as? Date }

    /// Published $/h for a batch model; `nil` for one the rows do not price.
    static func batchRate(_ model: String) -> Double? {
        switch model {
        case "scribe_v1": return 0.40
        case "scribe_v2": return 0.22
        default: return nil
        }
    }

    /// Total in dollars, and the lines the tooltip explains it with.
    static func summary() -> (total: Double, lines: [String]) {
        let d = UserDefaults.standard
        let batch = d.dictionary(forKey: batchKey) as? [String: Double] ?? [:]
        let live = d.double(forKey: liveKey)
        let liveKeyterms = d.double(forKey: liveKeytermsKey)
        var total = 0.0
        var lines: [String] = []
        for (model, seconds) in batch.sorted(by: { $0.key < $1.key }) {
            let rate = batchRate(model)
            let cost = (rate ?? 0) * seconds / 3600
            total += cost
            lines.append(String(format: "%@: %@ of audio → %@", model, clock(seconds),
                                rate == nil ? "unpriced" : String(format: "$%.2f", cost)))
        }
        if live > 0 {
            let cost = realtimeRate * (live + keytermsPremium * liveKeyterms) / 3600
            total += cost
            lines.append(String(format: "%@ live: %@ streamed (%@ with keyterms, +20 %%) → $%.2f",
                                ElevenLabsLive.model, clock(live), clock(liveKeyterms), cost))
        }
        if let since {
            let f = DateFormatter(); f.dateFormat = "d MMM yyyy"
            lines.append("Counted on this Mac since \(f.string(from: since)), at the published rates; the invoice is right where they differ")
        }
        return (total, lines)
    }

    /// `$0.07` — what the menu row appends.
    static var label: String { String(format: "$%.2f", summary().total) }

    private static func clock(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return s >= 3600 ? String(format: "%dh%02dm", s / 3600, (s % 3600) / 60)
             : String(format: "%dm%02ds", s / 60, s % 60)
    }
}
