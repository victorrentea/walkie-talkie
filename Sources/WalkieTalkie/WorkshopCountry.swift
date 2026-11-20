import Foundation

/// **The country of today's workshop, when it is not Romania** (2026-11-19,
/// Victor, in a workshop in Portugal: *"Whenever I ask a question during a
/// workshop which is done for a country different than Romania, you can tell
/// the country I've selected in the tool here … Please answer me in English"*).
///
/// "The tool" is Victor Mac' ☕️ Break country (🌍 in its menu, the flag under
/// the menu bar clock): `BreakTimer.country.tz` + `BreakTimer.country.day` in
/// its defaults (`ro.victorrentea.macos-addons`), a pick that holds for one day
/// only. Walkie reads it and never writes it; the zone becomes a country through
/// `/usr/share/zoneinfo/zone.tab`, so no list is copied from Addons.
/// Nothing picked today, or Romania → nil, and the ⚡ question is as before.
struct WorkshopCountry: Equatable {
    let name: String
    let iso: String

    static let addonsDomain = "ro.victorrentea.macos-addons"

    /// Today's pick, read fresh at each question (he can change it mid-day).
    static func today() -> WorkshopCountry? {
        let d = UserDefaults(suiteName: addonsDomain)
        return from(tz: d?.string(forKey: "BreakTimer.country.tz"),
                    day: d?.string(forKey: "BreakTimer.country.day"),
                    today: dayKey(Date()), zoneTab: zoneTab)
    }

    /// Pure: the pick's zone, its day, today's `yyyy-MM-dd`, zone → ISO code.
    static func from(tz: String?, day: String?, today: String, zoneTab: [String: String]) -> WorkshopCountry? {
        guard let tz, day == today, let iso = zoneTab[tz], iso != "RO" else { return nil }
        let name = Locale(identifier: "en_US").localizedString(forRegionCode: iso) ?? iso
        return WorkshopCountry(name: name, iso: iso)
    }

    /// **The row the question carries**: write in English (his words are often
    /// Romanian, the room is not), and the country is the place a question
    /// depends on (prices, laws, holidays, the hour) unless he names another.
    var clause: String {
        "[I am giving a workshop in \(name) today: write in English, whatever language I asked in, "
            + "and when the question depends on a place, it is \(name) unless I name another.]"
    }

    /// Google's own knobs for the same thing: English page and AI answer
    /// (`hl=en` — the account's Romanian won before), results from the country.
    var googleItems: [URLQueryItem] {
        [URLQueryItem(name: "hl", value: "en"), URLQueryItem(name: "gl", value: iso.lowercased())]
    }

    static func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// `zone.tab`: `PT\t+3843-00908\tEurope/Lisbon\t…` → `Europe/Lisbon: PT`. Read once.
    static let zoneTab: [String: String] = parseZoneTab(
        (try? String(contentsOfFile: "/usr/share/zoneinfo/zone.tab", encoding: .utf8)) ?? "")

    static func parseZoneTab(_ text: String) -> [String: String] {
        var map: [String: String] = [:]
        for line in text.split(separator: "\n") where !line.hasPrefix("#") {
            let cols = line.split(separator: "\t")
            if cols.count >= 3 { map[String(cols[2])] = String(cols[0]) }
        }
        return map
    }
}
