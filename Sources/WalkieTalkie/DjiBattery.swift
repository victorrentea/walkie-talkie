import Foundation

/// **The DJI transmitter's battery on the `Mic:` row, as Victor Addons shows it**
/// (2026-10-07, Victor: *"should display also the battery … of my DJI the same
/// way macOS add-ons does it"*) — `Mic: 🎤 DJI 80 %`, or `— no TX` when no
/// transmitter is linked; nothing when the receiver's status is not live.
///
/// **Asked of Victor Addons, never read off the receiver.** The status comes over
/// the receiver's vendor USB interface, which is exclusive — Addons holds it
/// (`DjiReceiverMonitor`), and a second reader would take it away from Addons'
/// own low-battery banner. So this asks Addons' `GET /test/dji/state` on 55123
/// (the port `DesktopEffects` already talks to) and words the answer exactly as
/// `DjiReceiverProtocol.menuSuffix` does over there.
///
/// Asked when the menu opens, answered into the open menu: the row first shows
/// the last reading, then repaints. Addons not running, or the receiver
/// unplugged, is the row without a battery.
enum DjiBattery {
    /// The last answer — the suffix itself, or nil. Main thread.
    private(set) static var suffix: String?

    /// Ask Addons now; `done` runs on the main thread with the new suffix.
    static func refresh(done: @escaping (String?) -> Void) {
        guard let url = URL(string: "http://127.0.0.1:55123/test/dji/state") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 1.0
        URLSession.shared.dataTask(with: req) { data, _, _ in
            let s = data.flatMap(menuSuffix(json:))
            DispatchQueue.main.async {
                suffix = s
                done(s)
            }
        }.resume()
    }

    /// Addons' answer → Addons' own wording: `80 %` (one per linked
    /// transmitter, ` / ` between), `— no TX`, or nil when not live.
    static func menuSuffix(json data: Data) -> String? {
        guard let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              j["live"] as? Bool == true else { return nil }
        guard (j["linked_mask"] as? Int ?? 0) != 0 else { return "— no TX" }
        let pcts = (j["transmitters"] as? [[String: Any]] ?? [])
            .compactMap { $0["percent"] as? Int }.map { "\($0) %" }
        return pcts.isEmpty ? nil : pcts.joined(separator: " / ")
    }
}
