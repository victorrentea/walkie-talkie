import AppKit

/// **What a prompt picks up without being asked** (2026-10-15) — three switches
/// under the menu's `Auto-attach` row. Victor: *"Să fie opțiune în meniu dacă
/// vreau să preiei selecția textului automat, dacă vrea să faci poză la
/// începutul unui promptări … și … care să preia ori de câte ori apăs ⌘C …
/// Dacă copiez în clipboard ceva, de unde aș copia, să ajungă automat la agent."*
///
/// All three default **on**: the first two are what the app already did, the
/// third is the one he asked to have ticked from the start. `UserDefaults`,
/// beside `autosend` — preferences, not data, so `--home` does not move them.
///
/// What each one does **not** touch: the shutter (🔽 press, ⌃⌥P) still reads
/// the highlight and takes its frame — a deliberate press is not *automatic*.
enum AutoAttach {

    enum Kind: String, CaseIterable {
        /// The highlight he made ≤ 5 s before the prompt, the 1 s watcher, the
        /// drag-release probe, the read at the close.
        case selection
        /// Whatever lands on the pasteboard while a prompt records — text, an
        /// image, files copied in Finder.
        case clipboard
        /// 📸0, the frame taken when a prompt opens.
        case screenshot

        /// **`Anything I Select`, `Anything I Copy`, `Screenshot at Start`, in
        /// that order** (2026-10-20, Victor: *"Anything I select. Anything I
        /// copy. And a screenshot at start"*) — the case order is the menu's.
        var title: String {
            switch self {
            case .selection: return "Anything I Select"
            case .clipboard: return "Anything I Copy"
            case .screenshot: return "Screenshot at Start"
            }
        }

        var tooltip: String {
            switch self {
            case .selection:
                return "Text you highlight just before or during a prompt rides along with it. "
                    + "The 🔽 shutter still takes the highlight under it when this is off."
            case .screenshot:
                return "A picture of the screen (📸0) when a prompt starts."
            case .clipboard:
                return "Anything copied while a prompt records — ⌘C, Copy Image, files in Finder — "
                    + "goes to the agent: text as [copied: …], an image as a numbered picture."
            }
        }

        var defaultsKey: String { "autoAttach." + rawValue }
    }

    static func isOn(_ kind: Kind) -> Bool {
        UserDefaults.standard.object(forKey: kind.defaultsKey) as? Bool ?? true
    }

    static func set(_ kind: Kind, _ on: Bool) {
        UserDefaults.standard.set(on, forKey: kind.defaultsKey)
        Log.info("📎 auto-attach \(kind.rawValue) \(on ? "on" : "off")")
    }

    static var describe: [String: Bool] {
        Dictionary(uniqueKeysWithValues: Kind.allCases.map { ($0.rawValue, isOn($0)) })
    }
}

/// **One thing copied, read off the general pasteboard** — for the clipboard
/// half of `AutoAttach`.
enum CopiedItem {
    case image(CGImage)
    case files([String])
    case text(String)

    /// Read what another app just wrote. **Off the main thread** — a promised
    /// item (Chrome's *Copy Image*) is rendered by its owner when asked, and the
    /// main thread must not wait on it. Through `Clipboard`'s lock, `types`
    /// first and sandwiched in `changeCount` (`WisprFlowSource.pasteboardString`
    /// says why): a board that moved during the read hands back nothing.
    ///
    /// Order: files before an image (a PNG copied in Finder carries its icon as
    /// TIFF — the file is what he meant), an image before text (Chrome's Copy
    /// Image carries the URL as text too).
    static func read(expecting count: Int) -> CopiedItem? {
        Clipboard.with { board -> CopiedItem? in
            guard board.changeCount == count, let types = board.types else { return nil }
            var item: CopiedItem?
            if types.contains(.fileURL),
               let urls = board.readObjects(forClasses: [NSURL.self],
                                            options: [.urlReadingFileURLsOnly: true]) as? [URL],
               !urls.isEmpty {
                item = .files(urls.map(\.path))
            } else if types.contains(.png) || types.contains(.tiff),
                      let data = board.data(forType: types.contains(.png) ? .png : .tiff),
                      let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                item = .image(image)
            } else if types.contains(.string),
                      let text = board.string(forType: .string)?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                      !text.isEmpty {
                item = .text(text)
            }
            return board.changeCount == count ? item : nil
        }
    }
}
