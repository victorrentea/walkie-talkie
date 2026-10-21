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

    /// **The published weights have a card too** (2026-10-21) — not in a folder,
    /// since they are fetched by repo id: `models/whisper-large-v3-turbo.model-card.json`
    /// holds what Victor measured on them (the baseline WER, the speed on this
    /// Mac). Missing, `builtInOriginal` says what OpenAI published.
    static let originalCardFile = "whisper-large-v3-turbo.model-card.json"

    static let builtInOriginal = Card(name: "whisper-large-v3-turbo",
                                      tagline: "OpenAI's published model, as downloaded",
                                      base: "openai/whisper-large-v3-turbo",
                                      params: "809M", layers: "32 encoder + 4 decoder")

    /// **One `model-card.json`, every field optional but `name`** — the old
    /// flat fields (`method`, `data`, `trained`, `cost_usd`, `held-out`,
    /// `wer.before/after`) still render; the structured ones added 2026-10-21
    /// (`params`, `layers`, `lora{}`, `wer.ro/en/vocab_recall`, `speed{}`,
    /// `training{}`, `recommended`) are what the sectioned tooltip is built from.
    struct Card: Equatable {
        var name: String
        var tagline: String?
        /// The ★ (2026-10-21): the model Victor recommends, set on its card.
        var recommended = false
        var base: String?
        var params: String?
        var layers: String?
        var turboNote: String?
        var build: String?
        var license: String?
        var method: String?
        var lora: Lora?
        var data: String?
        var trained: String?
        var costUSD: Double?
        var heldOut: String?
        var comparedWith: String?
        var werBefore: Double?
        var werAfter: Double?
        var wer: Wer?
        var speed: Speed?
        var training: Training?

        struct Lora: Equatable {
            var rank: Int?, on: String?, trainable: String?, epochs: String?, lr: String?
        }
        /// `[before, after]` pairs; a one-element pair is a baseline.
        struct Wer: Equatable {
            var ro: [Double] = [], en: [Double] = [], vocabRecall: [Double] = []
            var heldOutSet: String?, beforeIs: String?, note: String?
        }
        /// Measured on this Mac. `x_audio` alone is enough: the 10 s and
        /// 1 min figures are derived from it when the card has no medians.
        struct Speed: Equatable {
            var mac: String?, per10s: Double?, perMin: Double?, xAudio: Double?, source: String?
            var tenSeconds: Double? { per10s ?? xAudio.map { $0 * 10 } }
            var oneMinute: Double? { perMin ?? xAudio.map { $0 * 60 } }
        }
        struct Training: Equatable {
            var machine: String?, usdPerHour: Double?, rentedMin: Double?, trainMin: Double?
            var session: String?, buy: String?, buySource: String?
        }

        init(name: String, tagline: String? = nil, base: String? = nil,
             params: String? = nil, layers: String? = nil) {
            self.name = name; self.tagline = tagline; self.base = base
            self.params = params; self.layers = layers
        }

        /// Parsed from `model-card.json`; nil when there is no usable `name`.
        static func parse(_ data: Data) -> Card? {
            guard let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let name = j["name"] as? String, !name.isEmpty else { return nil }
            func num(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue }
            func nums(_ v: Any?) -> [Double] { (v as? [Any])?.compactMap(num) ?? [] }
            func text(_ v: Any?) -> String? {
                if let s = v as? String, !s.isEmpty { return s }
                return num(v).map { String(format: "%g", $0) }
            }
            var c = Card(name: name, tagline: text(j["tagline"]), base: text(j["base"]),
                         params: text(j["params"]), layers: text(j["layers"]))
            c.recommended = (j["recommended"] as? Bool) ?? false
            c.turboNote = text(j["turbo_note"])
            c.build = text(j["build"])
            c.license = text(j["license"])
            c.method = text(j["method"])
            c.data = text(j["data"])
            c.trained = text(j["trained"])
            c.costUSD = num(j["cost_usd"])
            c.heldOut = text(j["held-out"])
            c.comparedWith = text(j["compared_with"])
            if let l = j["lora"] as? [String: Any] {
                c.lora = Lora(rank: (l["rank"] as? NSNumber)?.intValue, on: text(l["on"]),
                              trainable: text(l["trainable"]), epochs: text(l["epochs"]), lr: text(l["lr"]))
            }
            if let w = j["wer"] as? [String: Any] {
                c.werBefore = num(w["before"])
                c.werAfter = num(w["after"])
                c.wer = Wer(ro: nums(w["ro"]), en: nums(w["en"]), vocabRecall: nums(w["vocab_recall"]),
                            heldOutSet: text(w["held_out"]), beforeIs: text(w["before_is"]), note: text(w["note"]))
            }
            if let s = j["speed"] as? [String: Any] {
                c.speed = Speed(mac: text(s["mac"]), per10s: num(s["s_per_10s"]), perMin: num(s["s_per_min"]),
                                xAudio: num(s["x_audio"]), source: text(s["source"]))
            }
            if let t = j["training"] as? [String: Any] {
                c.training = Training(machine: text(t["machine"]), usdPerHour: num(t["usd_per_hour"]),
                                      rentedMin: num(t["rented_min"]), trainMin: num(t["train_min"]),
                                      session: text(t["session"]), buy: text(t["buy"]),
                                      buySource: text(t["buy_source"]))
            }
            return c
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
        /// prompt panel's `Local Whisper …` line: `Local Turbo`, `Local Turbo
        /// LoRA`, `Local Large LoRA` since 2026-10-21 (`name(_:)`). Derived from
        /// the card's `name` (else the folder or repo id), so the card's old
        /// `label` / `short` say nothing.
        var title: String {
            WhisperModels.name(card?.name ?? (id as NSString).lastPathComponent)
        }

        /// Turbo before the full-size V3; within a base, the published weights
        /// before a LoRA on them.
        fileprivate var turbo: Bool { isOriginal || (card?.base ?? id).lowercased().contains("turbo") }

        /// **The row's tooltip, in sections** (2026-10-21, Victor: *"the tooltip
        /// should be cleaner to read … explain the model, the machine I've used,
        /// its cost if I would buy it, the time I rented it for and for how much,
        /// the word error ratio improvement, the expected latency"* — *"I'm
        /// showing that part often to people"*). A headline, then WHAT /
        /// ACCURACY / SPEED ON THIS MAC / TRAINING (or COST), one fact per line,
        /// a blank line between sections. A section the card has nothing for is
        /// left out. Plain text: `NSMenuItem.toolTip` draws no attributes.
        var details: String {
            WhisperModels.tooltip(title: title, card: card, id: id)
        }
    }

    static func tooltip(title: String, card: Card?, id: String) -> String {
        let weights = "Weights: " + (id.hasPrefix("/") ? abbreviated(id) : "\(id) (Hugging Face)")
        guard let c = card else { return "\(title)\n\n\(weights)" }
        // WER keeps its decimal (`14.0 %`, not `14 %`); a recall is whole.
        func pct(_ v: Double) -> String { String(format: "%.1f %%", v) }
        func secs(_ v: Double) -> String { String(format: v < 10 ? "%.1f s" : "%.0f s", v) }
        func pair(_ p: [Double], _ f: (Double) -> String = pct) -> String? {
            switch p.count {
            case 0: return nil
            case 1: return f(p[0])
            default: return "\(f(p[0])) → \(f(p[1]))"
            }
        }
        var sections: [[String]] = []

        var head = title + (c.recommended ? " ★" : "")
        if let t = c.tagline { head += " — " + t }
        sections.append([head])

        var what: [String] = []
        if let base = c.base {
            what.append("Base: \(base)" + (c.params.map { " · \($0) params" } ?? ""))
        }
        if let layers = c.layers { what.append("Layers: \(layers)") }
        if let note = c.turboNote { what.append("Turbo: \(note)") }
        if let build = c.build { what.append("Build: \(build)") }
        if let l = c.lora {
            var line = "LoRA: " + (l.rank.map { "rank \($0)" } ?? "adapter")
            if let on = l.on { line += " on \(on)" }
            what.append(line)
            if let t = l.trainable { what.append("Trainable: \(t) of the weights") }
            if let e = l.epochs { what.append("Epochs: \(e)" + (l.lr.map { " · learning rate \($0)" } ?? "")) }
        } else if let m = c.method {
            what.append("Method: \(m)")
        }
        if let d = c.data { what.append("Data: \(d)") }
        if !what.isEmpty { sections.append(["WHAT"] + what) }

        var acc: [String] = []
        if let b = c.werBefore {
            if let a = c.werAfter {
                let cut = b > 0 ? String(format: "  (%.0f %% fewer errors)", (b - a) / b * 100) : ""
                acc.append("Word error rate: \(pct(b)) → \(pct(a))" + cut)
            } else {
                acc.append("Word error rate: \(pct(b))")
            }
            if let w = c.wer {
                if let ro = pair(w.ro) { acc.append("Romanian: \(ro)") }
                if let en = pair(w.en) { acc.append("English: \(en)") }
                if let v = pair(w.vocabRecall, { String(format: "%g %%", $0) }) { acc.append("Vocabulary terms caught: \(v)") }
                if let before = w.beforeIs, c.werAfter != nil { acc.append("Before = \(before)") }
                if let note = w.note { acc.append(note.prefix(1).uppercased() + note.dropFirst()) }
            }
        } else if let h = c.heldOut {
            acc.append(h)
        }
        if !acc.isEmpty {
            let set = c.wer?.heldOutSet.map { " — \($0)" } ?? ""
            sections.append(["ACCURACY" + set] + acc)
        }

        if let s = c.speed, s.tenSeconds != nil || s.oneMinute != nil {
            var speed = ["SPEED ON THIS MAC" + (s.mac.map { " — \($0)" } ?? "")]
            if let t = s.tenSeconds { speed.append("10 s of speech → ≈ \(secs(t)) to text") }
            if let m = s.oneMinute { speed.append("1 min of speech → ≈ \(secs(m)) to text") }
            if let src = s.source { speed.append("Measured: \(src)") }
            sections.append(speed)
        }

        var train: [String] = []
        if let t = c.training {
            if let m = t.machine { train.append("Machine: \(m)") }
            if let buy = t.buy { train.append("To buy one: \(buy)" + (t.buySource.map { " (\($0))" } ?? "")) }
            if let rate = t.usdPerHour {
                var line = String(format: "Rented: $%.2f/h", rate)
                if let min = t.rentedMin { line += String(format: " × ≈ %.0f min", min) }
                if let cost = c.costUSD { line += String(format: " = $%.2f", cost) }
                train.append(line)
            } else if let cost = c.costUSD {
                train.append(String(format: "Cost: $%.2f", cost))
            }
            if let s = t.session { train.append("Session: \(s)") }
            if let g = t.trainMin { train.append(String(format: "GPU time for this model: %.1f min", g)) }
        } else {
            if let tr = c.trained { train.append("Trained: \(tr)") }
            if let cost = c.costUSD { train.append(String(format: "Cost: $%g", cost)) }
        }
        if !train.isEmpty {
            sections.append(["TRAINING" + (c.training != nil ? c.trainedDay.map { " — \($0)" } ?? "" : "")] + train)
        } else if let lic = c.license {
            sections.append(["COST", lic])
        }

        sections.append([weights])
        return sections.map { $0.joined(separator: "\n") }.joined(separator: "\n\n")
    }

    /// Every installed folder that has MLX weights, plus the original. **Turbo
    /// first, the published weights before the LoRA on them, then the full-size
    /// Large** (2026-10-21, Victor: *"emphasize the turbo side of things"* —
    /// reverses 2026-10-04's Large-first order), then by name. Read from disk on
    /// every call — the list is built when the menu opens, and a folder copied
    /// in while the app runs shows up there.
    static func options(in dir: URL = modelsDir) -> [Option] {
        let originalCard = (try? Data(contentsOf: dir.appendingPathComponent(originalCardFile)))
            .flatMap(Card.parse) ?? builtInOriginal
        var out = [Option(id: original, card: originalCard)]
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
            if a.element.turbo != b.element.turbo { return a.element.turbo }
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
    /// `whisper-large-v3-turbo` → `Local Turbo`, `whisper-turbo-victor` →
    /// `Local Turbo LoRA`, `whisper-large-victor` → `Local Large LoRA`
    /// (2026-10-21, Victor: *"call the first one Local Turbo … emphasize the
    /// turbo side of things"* — the architecture leads, the LoRA follows;
    /// supersedes 2026-10-14's `Local` / `Local LoRA` / `Local LoRA Large`,
    /// where Turbo went unsaid). A word that is not Whisper's own (`victor`)
    /// means weights trained on top of it, a LoRA. A name that is not a
    /// Whisper V3 at all is left as it is.
    static func name(_ raw: String) -> String {
        let tokens = raw.lowercased().split(separator: "-").map(String.init)
        let whispers = ["whisper", "large", "v3", "turbo", "lora"]
        guard tokens.contains(where: { ["whisper", "large", "v3", "turbo"].contains($0) }) else { return raw }
        let lora = tokens.contains("lora") || tokens.contains { !whispers.contains($0) }
        let size = tokens.contains("turbo") ? "Turbo" : "Large"
        return (["Local", size] + (lora ? ["LoRA"] : [])).joined(separator: " ")
    }

    static func abbreviated(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
