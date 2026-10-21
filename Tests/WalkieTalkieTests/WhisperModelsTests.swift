import XCTest
@testable import WalkieTalkie

/// The local model picker (2026-10-03): Turbo before the full-size Large since
/// 2026-10-21, the original before a LoRA on it, titled from each `model-card.json`.
final class WhisperModelsTests: XCTestCase {

    private let card = """
    {"name": "whisper-turbo-victor", "label": "Large V3-turbo Victor LoRA", "short": "Turbo LoRA Victor", "base": "openai/whisper-large-v3-turbo",
     "method": "LoRA r=32", "data": "3,086 clips / 9.3 h", "trained": "2026-10-03 on Runpod H100 SXM",
     "cost_usd": 3.6, "held-out": "733 Wispr dictations: WER 20.4% → 15.3%",
     "wer": {"before": 20.4, "after": 15.3}}
    """

    func testTitleIsReadFromTheCard() throws {
        let c = try XCTUnwrap(WhisperModels.Card.parse(Data(card.utf8)))
        let option = WhisperModels.Option(id: "/x/whisper-turbo-victor", card: c)
        // The card's old `label` / `short` no longer name it (2026-10-07).
        XCTAssertEqual(StatusItem.localRowTitle(option, loading: false), "💻 Local Turbo LoRA")
        // An old flat card still renders, in sections (2026-10-21).
        XCTAssertTrue(option.details.hasPrefix("Local Turbo LoRA\n\nWHAT\nBase: openai/whisper-large-v3-turbo\n"))
        XCTAssertTrue(option.details.contains("Method: LoRA r=32"))
        XCTAssertTrue(option.details.contains("ACCURACY\nWord error rate: 20.4 % → 15.3 %  (25 % fewer errors)"))
        XCTAssertTrue(option.details.contains("TRAINING\nTrained: 2026-10-03 on Runpod H100 SXM\nCost: $3.6"))
        XCTAssertTrue(option.details.hasSuffix("\n\nWeights: /x/whisper-turbo-victor"))
    }

    func testOriginalIsNamedAsSuch() {
        XCTAssertEqual(StatusItem.localRowTitle(WhisperModels.Option(id: WhisperModels.original, card: nil),
                                                loading: false),
                       "💻 Local Turbo")
        XCTAssertEqual(WhisperModels.displayName(WhisperModels.original), "Local Turbo")
        let noLabel = WhisperModels.Card(name: "x-model")
        XCTAssertEqual(WhisperModels.Option(id: "/m/x", card: noLabel).title, "x-model")
    }

    func testOptionsListV3ThenTurboOriginalFirst() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let good = dir.appendingPathComponent("whisper-turbo-victor")
        let noWeights = dir.appendingPathComponent("half-copied")
        for d in [good, noWeights] { try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true) }
        for f in ["config.json", "weights.safetensors"] {
            try Data("{}".utf8).write(to: good.appendingPathComponent(f))
        }
        try Data(card.utf8).write(to: good.appendingPathComponent("model-card.json"))
        try Data("{}".utf8).write(to: noWeights.appendingPathComponent("config.json"))

        // Turbo first since 2026-10-21: the published Turbo, its LoRA, then the Large LoRA.
        let large = dir.appendingPathComponent("whisper-large-victor")
        try FileManager.default.createDirectory(at: large, withIntermediateDirectories: true)
        for f in ["config.json", "weights.safetensors"] {
            try Data("{}".utf8).write(to: large.appendingPathComponent(f))
        }
        try Data(#"{"name": "whisper-large-victor", "base": "openai/whisper-large-v3"}"#.utf8)
            .write(to: large.appendingPathComponent("model-card.json"))

        let ids = WhisperModels.options(in: dir).map(\.id)
        XCTAssertEqual(ids, [WhisperModels.original, good.path, large.path])
        XCTAssertEqual(WhisperModels.options(in: dir)[1].card?.name, "whisper-turbo-victor")
        // No card file for the published weights: the built-in one names them.
        XCTAssertEqual(WhisperModels.options(in: dir).first?.card?.params, "809M")
    }

    func testOneNameEverywhere() {
        XCTAssertEqual(WhisperModels.name("whisper-large-v3-turbo"), "Local Turbo")
        XCTAssertEqual(WhisperModels.name("whisper-turbo-victor"), "Local Turbo LoRA")
        XCTAssertEqual(WhisperModels.name("whisper-large-victor"), "Local Large LoRA")
        XCTAssertEqual(WhisperModels.name("whisper-large-v3"), "Local Large")
        XCTAssertEqual(WhisperModels.name("Whisper-Turbo-Victor-LoRA"), "Local Turbo LoRA")
        XCTAssertEqual(WhisperModels.name("some-model"), "some-model")
    }

    /// The structured card (2026-10-21): sections, the ★, speed derived from `x_audio`.
    func testStructuredCardRendersSections() throws {
        let json = """
        {"name": "whisper-turbo-victor", "tagline": "Whisper Turbo, fine-tuned on my voice", "recommended": true,
         "base": "openai/whisper-large-v3-turbo", "params": "809M", "layers": "32 encoder + 4 decoder",
         "lora": {"rank": 32, "on": "attention + MLP", "trainable": "27.9M (3.3 %)", "epochs": "2 (best of 5)", "lr": "1e-4"},
         "data": "3,086 clips · 9.3 h", "trained": "2026-10-03 on Runpod H100 SXM", "cost_usd": 3.6,
         "wer": {"before": 20.4, "after": 15.3, "ro": [25.2, 19.7], "en": [9.4, 5.2], "vocab_recall": [79, 98],
                 "held_out": "733 held-out dictations", "before_is": "published Turbo"},
         "speed": {"mac": "M1 Max", "x_audio": 0.05, "source": "test"},
         "training": {"machine": "Runpod H100 SXM 80 GB", "usd_per_hour": 3.49, "rented_min": 62,
                      "train_min": 10.8, "buy": "≈ $35–40k new"}}
        """
        let c = try XCTUnwrap(WhisperModels.Card.parse(Data(json.utf8)))
        XCTAssertTrue(c.recommended)
        let tip = WhisperModels.Option(id: "/m/whisper-turbo-victor", card: c).details
        XCTAssertTrue(tip.hasPrefix("Local Turbo LoRA ★ — Whisper Turbo, fine-tuned on my voice\n\nWHAT\n"))
        XCTAssertTrue(tip.contains("Base: openai/whisper-large-v3-turbo · 809M params\nLayers: 32 encoder + 4 decoder"))
        XCTAssertTrue(tip.contains("LoRA: rank 32 on attention + MLP"))
        XCTAssertTrue(tip.contains("ACCURACY — 733 held-out dictations\nWord error rate: 20.4 % → 15.3 %"))
        XCTAssertTrue(tip.contains("Romanian: 25.2 % → 19.7 %\nEnglish: 9.4 % → 5.2 %\nVocabulary terms caught: 79 % → 98 %"))
        XCTAssertTrue(tip.contains("SPEED ON THIS MAC — M1 Max\n10 s of speech → ≈ 0.5 s to text\n1 min of speech → ≈ 3.0 s to text"))
        XCTAssertTrue(tip.contains("TRAINING — 3 Oct 2026\nMachine: Runpod H100 SXM 80 GB\nTo buy one: ≈ $35–40k new"))
        XCTAssertTrue(tip.contains("Rented: $3.49/h × ≈ 62 min = $3.60"))
        XCTAssertFalse(tip.contains("Method:"))
    }

    /// The ★ follows the card's `recommended`, else the lowest WER (2026-10-21).
    func testStarFollowsTheRecommendedCard() {
        var turbo = WhisperModels.Card(name: "whisper-turbo-victor"); turbo.werAfter = 15.3
        var large = WhisperModels.Card(name: "whisper-large-victor"); large.werAfter = 14.0
        let options = [WhisperModels.Option(id: "/t", card: turbo), WhisperModels.Option(id: "/l", card: large)]
        XCTAssertEqual(StatusItem.starred(options), "/l")
        turbo.recommended = true
        XCTAssertEqual(StatusItem.starred([WhisperModels.Option(id: "/t", card: turbo),
                                           WhisperModels.Option(id: "/l", card: large)]), "/t")
    }

    func testABadCardFallsBackToTheFolderName() {
        XCTAssertNil(WhisperModels.Card.parse(Data("{\"base\": \"x\"}".utf8)))
        XCTAssertEqual(WhisperModels.Option(id: "/m/some-model", card: nil).title, "some-model")
    }
}

/// The DJI battery on the `Mic:` row, worded as Victor Addons words it (2026-10-07).
final class DjiBatteryTests: XCTestCase {
    private func suffix(_ json: String) -> String? { DjiBattery.menuSuffix(json: Data(json.utf8)) }

    func testLinkedTransmittersShowTheirPercent() {
        XCTAssertEqual(suffix(#"{"present":true,"live":true,"linked_mask":2,"transmitters":[{"unit":2,"level":2,"percent":80}]}"#), "80 %")
        XCTAssertEqual(suffix(#"{"live":true,"linked_mask":3,"transmitters":[{"percent":100},{"percent":20}]}"#), "100 % / 20 %")
    }

    func testNoTransmitterAndNotLive() {
        XCTAssertEqual(suffix(#"{"live":true,"linked_mask":0,"transmitters":[]}"#), "— no TX")
        XCTAssertNil(suffix(#"{"live":false,"linked_mask":2,"transmitters":[{"percent":80}]}"#))
        XCTAssertNil(suffix("not json"))
    }
}
