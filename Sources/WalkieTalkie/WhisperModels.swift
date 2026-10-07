import Foundation

/// **Which weights the local model loads — a choice in the Engine list** (2026-10-03).
///
/// Victor, after the LoRA trained on his own dictations came back from the GPU:
/// both models visible in the menu, the original still the default, and he
/// switches himself. The original is the published `mlx-community/whisper-large-v3-turbo`;
/// every other option is a folder under `~/.walkie-talkie/models/` holding MLX
/// weights (`config.json` + `weights.safetensors`, what `mlx_whisper.transcribe(
/// path_or_hf_repo=<dir>)` loads) and a `model-card.json` beside them.
///
/// **The card is the one place the facts are written.** The row's date, cost and
/// WER and the tooltip's method and data are read from it at every menu build, so
/// a model retrained tomorrow is a new folder and a new card — no code change, no
/// second copy of the numbers to drift.
///
/// **How it reaches the helper:** `LocalWhisper.helperEnvironment` sets
/// `RELAY_WHISPER_MODEL` to `selected`, which `whisper_helper.py` reads as its
/// `MODEL`. A pick while the helper is up replaces the helper — but only at the
/// next idle moment (`AppDelegate.applyWhisperModelWhenIdle`), never under a sentence.
enum WhisperModels {

    /// The published weights — what the app loaded before there was a choice.
    static let original = "mlx-community/whisper-large-v3-turbo"

    /// The `UserDefaults` key holding the pick (a repo id or an absolute folder).
    static let defaultsKey = "localWhisperModel"

    /// Machine-level, not per `--home`: a desk run on a scratch home still sees
    /// the weights that are installed.
    static var modelsDir: URL { Outbox.defaultHome.appendingPathComponent("models") }

    struct Card: Equatable {
        var name: String
        var base: String?
        var method: String?
        var data: String?
        var trained: String?
        var costUSD: Double?
        var heldOut: String?
        var comparedWith: String?
        var werBefore: Double?
        var werAfter: Double?

        /// Parsed from `model-card.json`; nil when there is no usable `name`.
        static func parse(_ data: Data) -> Card? {
            guard let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let name = j["name"] as? String, !name.isEmpty else { return nil }
            let wer = j["wer"] as? [String: Any]
            return Card(name: name,
                        base: j["base"] as? String,
                        method: j["method"] as? String,
                        data: j["data"] as? String,
                        trained: j["trained"] as? String,
                        costUSD: (j["cost_usd"] as? NSNumber)?.doubleValue,
                        heldOut: j["held-out"] as? String,
                        comparedWith: j["compared_with"] as? String,
                        werBefore: (wer?["before"] as? NSNumber)?.doubleValue,
                        werAfter: (wer?["after"] as? NSNumber)?.doubleValue)
        }

        /// `2026-10-03 on Runpod H100 SXM` → `3 Oct 2026`; the raw text if it
        /// does not start with an ISO date.
        var trainedDay: String? {
            guard let trained else { return nil }
            let iso = String(trained.prefix(10))
            let inFmt = DateFormatter()
            inFmt.locale = Locale(identifier: "en_US_POSIX")
            inFmt.dateFormat = "yyyy-MM-dd"
            guard let day = inFmt.date(from: iso) else { return trained }
            let out = DateFormatter()
            out.locale = Locale(identifier: "en_GB")
            out.dateFormat = "d MMM yyyy"
            return out.string(from: day)
        }
    }

    struct Option: Equatable {
        /// What `RELAY_WHISPER_MODEL` is set to: a repo id or a folder path.
        var id: String
        var card: Card?

        var isOriginal: Bool { id == WhisperModels.original }

        /// **The model's one name, wherever it is shown** — the Engine list,
        /// the top-level `Engine:` row, the menu bar's launch tab, About and the
        /// prompt panel's `Local Whisper (…)` line: `v3-turbo`, `v3-victor`,
        /// `v3-turbo-victor` (2026-10-07, Victor: *"I want to unify them all …
        /// V3 Turbo Victor. No LoRA, it just takes space … small caps with kebab
        /// case … everywhere the same name"*). Until then the row said `Large
        /// V3-turbo Victor LoRA`, the top-level row `Turbo LoRA Victor` and the
        /// panel `whisper-turbo-victor` — three names for one set of weights.
        /// Derived from the card's `name` (else the folder or repo id), so the
        /// card's old `label` / `short` no longer say anything.
        var title: String {
            WhisperModels.name(card?.name ?? (id as NSString).lastPathComponent)
        }

        /// Turbo after the full-size V3; within a base, the published weights
        /// before a LoRA on them.
        fileprivate var turbo: Bool { isOriginal || (card?.base ?? id).lowercased().contains("turbo") }

        /// The tooltip's first line: what the row stopped carrying.
        var summary: String? {
            guard let card else { return nil }
            var parts = [card.name]
            if let day = card.trainedDay { parts.append("trained \(day)") }
            if let cost = card.costUSD { parts.append(String(format: "$%g", cost)) }
            if let b = card.werBefore, let a = card.werAfter {
                parts.append(String(format: "WER %g→%g%%", b, a))
            }
            return parts.joined(separator: " · ")
        }

        /// The row's tooltip: the whole card, then where the weights are.
        var details: String {
            guard let card else {
                return isOriginal
                    ? "\(id) — the published weights, as downloaded from Hugging Face"
                    : id
            }
            return [summary,
                    card.base.map { "Base: \($0)" },
                    card.method.map { "Method: \($0)" },
                    card.data.map { "Data: \($0)" },
                    card.trained.map { "Trained: \($0)" },
                    card.costUSD.map { String(format: "Cost: $%g", $0) },
                    card.heldOut.map { "Held-out: \($0)" },
                    card.comparedWith.map { "Compared with: \($0)" },
                    "Weights: \(WhisperModels.abbreviated(id))"].compactMap { $0 }
                .joined(separator: "\n")
        }
    }

    /// Every installed folder that has MLX weights, plus the original. **Large
    /// V3 before turbo, and within each the published weights before the LoRA**
    /// (2026-10-04, Victor's order: *Large V3 Victor · Large V3-turbo · Large
    /// V3-turbo Victor LoRA*), then by name. Read from disk on every call — the
    /// list is built when the menu opens, and a folder copied in while the app
    /// runs shows up there.
    static func options(in dir: URL = modelsDir) -> [Option] {
        var out = [Option(id: original, card: nil)]
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
        for name in names.sorted() where !name.hasPrefix(".") {
            let folder = dir.appendingPathComponent(name)
            guard fm.fileExists(atPath: folder.appendingPathComponent("config.json").path),
                  fm.fileExists(atPath: folder.appendingPathComponent("weights.safetensors").path)
            else { continue }
            let card = (try? Data(contentsOf: folder.appendingPathComponent("model-card.json")))
                .flatMap(Card.parse)
            out.append(Option(id: folder.path, card: card))
        }
        return out.enumerated().sorted { a, b in
            if a.element.turbo != b.element.turbo { return !a.element.turbo }
            if a.element.isOriginal != b.element.isOriginal { return a.element.isOriginal }
            return a.offset < b.offset
        }.map(\.element)
    }

    /// What the helper is to load: the pick, if its weights are still there;
    /// else `RELAY_WHISPER_MODEL` from the environment; else the original.
    static var selected: String {
        if let pick = UserDefaults.standard.string(forKey: defaultsKey), isLoadable(pick) { return pick }
        return ProcessInfo.processInfo.environment["RELAY_WHISPER_MODEL"] ?? original
    }

    static func select(_ id: String) {
        UserDefaults.standard.set(id, forKey: defaultsKey)
    }

    /// A repo id (no leading `/`) is the helper's to fetch; a folder must exist.
    static func isLoadable(_ id: String) -> Bool {
        guard id.hasPrefix("/") else { return true }
        return FileManager.default.fileExists(atPath: (id as NSString).appendingPathComponent("weights.safetensors"))
    }

    /// The option for an id (what the helper reports it loaded), for its name.
    static func option(for id: String) -> Option? { options().first { $0.id == id } }

    /// How a model id is shown anywhere — `Option.title`, for an id the
    /// helper reports or the one configured.
    static func displayName(_ id: String) -> String {
        if id.hasPrefix("/"), let option = option(for: id) { return option.title }
        return name((id as NSString).lastPathComponent)
    }

    /// `whisper-large-v3-turbo` → `v3-turbo`, `whisper-turbo-victor` →
    /// `v3-turbo-victor`, `whisper-large-victor` → `v3-victor`: lower case,
    /// kebab, `whisper` / `large` / `lora` dropped and `v3` in front — for a
    /// name that is a Whisper V3 at all; anything else is left as it is.
    static func name(_ raw: String) -> String {
        let tokens = raw.lowercased().split(separator: "-").map(String.init)
        guard tokens.contains(where: { ["whisper", "large", "v3", "turbo"].contains($0) }) else { return raw }
        let rest = tokens.filter { !["whisper", "large", "v3", "lora"].contains($0) }
        return (["v3"] + rest).joined(separator: "-")
    }

    static func abbreviated(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
