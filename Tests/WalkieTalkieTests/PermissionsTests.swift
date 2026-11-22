import XCTest
@testable import WalkieTalkie

/// The permissions' pure parts (2026-11-22): what the ❌ counts, the row's
/// title, the two status codes read, the fakes, and what the page says.
final class PermissionsTests: XCTestCase {

    private func readings(_ states: [Permissions.Kind: Permissions.State]) -> [Permissions.Reading] {
        Permissions.catalogue.map { Permissions.Reading(kind: $0.kind, state: states[$0.kind] ?? .granted) }
    }

    func testOnlyRequiredOnesThatAreKnownLackingCount() {
        XCTAssertEqual(Permissions.missingRequired(readings([:])), 0)
        XCTAssertEqual(Permissions.missingRequired(readings([.accessibility: .missing, .automationTerminal: .notAsked])), 2)
        // Optional ones never raise the ❌; neither does an answer nobody could get.
        XCTAssertEqual(Permissions.missingRequired(readings([.camera: .missing, .systemAudio: .notAsked,
                                                             .loginItem: .missing, .automationTerminal: .unknown])), 0)
    }

    func testTheRowIsTheBuildStampUntilSomethingIsMissing() {
        XCTAssertEqual(Permissions.rowTitle(missing: 0, build: "Nov 22, 10:12"), "Built Nov 22, 10:12")
        XCTAssertEqual(Permissions.rowTitle(missing: 1, build: "x"), "❌ 1 permission missing")
        XCTAssertEqual(Permissions.rowTitle(missing: 3, build: "x"), "❌ 3 permissions missing")
    }

    func testStatusCodes() {
        XCTAssertEqual(Permissions.automationState(status: 0), .granted)
        XCTAssertEqual(Permissions.automationState(status: -1743), .missing)
        XCTAssertEqual(Permissions.automationState(status: -1744), .notAsked)
        XCTAssertEqual(Permissions.automationState(status: -600), .unknown)
        XCTAssertEqual(Permissions.tccState(preflight: 0), .granted)
        XCTAssertEqual(Permissions.tccState(preflight: 1), .missing)
        XCTAssertEqual(Permissions.tccState(preflight: 2), .notAsked)
    }

    func testFakesAreParsedAndLaidOver() {
        let parsed = Permissions.parseFakes(["accessibility": "missing", "camera": "not-asked"])
        XCTAssertTrue(parsed.errors.isEmpty)
        let over = Permissions.overlay(readings([:]), fakes: parsed.fakes)
        XCTAssertEqual(over.first { $0.kind == .accessibility }, Permissions.Reading(kind: .accessibility, state: .missing, faked: true))
        XCTAssertEqual(over.first { $0.kind == .microphone }, Permissions.Reading(kind: .microphone, state: .granted))
        XCTAssertEqual(Permissions.parseFakes(["nope": "missing", "camera": "gone"]).errors.count, 2)
    }

    func testHintsAreRateLimitedAndNameThePermission() {
        let t0 = Date(timeIntervalSince1970: 1000)
        XCTAssertTrue(Permissions.hintDue(last: nil, now: t0, every: 60))
        XCTAssertFalse(Permissions.hintDue(last: t0, now: t0.addingTimeInterval(59), every: 60))
        XCTAssertTrue(Permissions.hintDue(last: t0, now: t0.addingTimeInterval(60), every: 60))
        XCTAssertEqual(Permissions.hintText(.microphone), "❌ Microphone permission missing — the menu's ❌ row says why")
        XCTAssertEqual(Permissions.launchHint(["Accessibility"]), "❌ Missing permission: Accessibility — the menu's ❌ row says why")
        XCTAssertTrue(Permissions.launchHint(["Accessibility", "Microphone"]).hasPrefix("❌ Missing permissions: Accessibility, Microphone"))
    }

    func testEveryEntryExplainsItselfAndLinksToSettings() {
        XCTAssertEqual(Permissions.catalogue.map(\.kind), Permissions.Kind.allCases)
        for e in Permissions.catalogue {
            XCTAssertFalse(e.why.isEmpty)
            XCTAssertFalse(e.without.isEmpty)
            XCTAssertTrue(e.settings.hasPrefix("x-apple.systempreferences:"), e.title)
            // Public UI: the third-party dictation app is never named.
            XCTAssertFalse((e.title + e.why + e.without + e.path).lowercased().contains("wispr"))
        }
    }

    func testThePageOffersSettingsOnlyForWhatIsLacking() {
        let page = PermissionsPage.html(readings([.accessibility: .missing, .camera: .missing]), build: "Nov 22, 10:12")
        XCTAssertTrue(page.contains("❌ 1 required permission is missing"))
        XCTAssertEqual(page.components(separatedBy: "Open Settings").count - 1, 2)
        XCTAssertTrue(page.contains("❌ Missing"))
        XCTAssertTrue(page.contains("⚠️ Not granted"))
        XCTAssertTrue(page.contains("Privacy_Accessibility"))
        XCTAssertFalse(page.contains("Privacy_Microphone"))
        XCTAssertFalse(page.contains("simulated"))

        let fine = PermissionsPage.html(readings([:]), build: "b")
        XCTAssertTrue(fine.contains("Every required permission is granted"))
        XCTAssertFalse(fine.contains("Open Settings"))
    }

    /// 2026-11-22, Victor: *"arată un ❌ pentru astea 2, un ⚠️ pentru celelalte"* — the four
    /// required ones ❌, the optional ones ⚠️, and nothing for one whose feature is off.
    func testRequiredOnesAreMissingOptionalOnesAWarningIdleOnesNeither() {
        func mark(_ kind: Permissions.Kind, _ state: Permissions.State, idle: Set<Permissions.Kind> = []) -> Permissions.Mark {
            Permissions.mark(Permissions.Reading(kind: kind, state: state), idle: idle)
        }
        for kind in [Permissions.Kind.accessibility, .microphone, .screenRecording, .automationTerminal] {
            XCTAssertEqual(mark(kind, .missing), .missing, kind.rawValue)
            XCTAssertEqual(mark(kind, .notAsked), .missing, kind.rawValue)
            XCTAssertEqual(mark(kind, .granted), .granted)
        }
        for kind in [Permissions.Kind.systemAudio, .camera, .loginItem] {
            XCTAssertEqual(mark(kind, .missing), .warning, kind.rawValue)
            XCTAssertEqual(mark(kind, .notAsked), .warning, kind.rawValue)
        }
        XCTAssertEqual(mark(.automationTerminal, .unknown), .unknown)
        // 🙂 Read my face unticked: the camera is nobody's business.
        XCTAssertEqual(mark(.camera, .missing, idle: [.camera]), .idle)
        XCTAssertEqual(mark(.camera, .granted, idle: [.camera]), .granted)
        // A required one is never idle, whatever the set says.
        XCTAssertEqual(mark(.microphone, .missing, idle: [.microphone]), .missing)

        let all = readings([.camera: .missing, .loginItem: .missing, .systemAudio: .notAsked])
        XCTAssertEqual(Permissions.optionalOff(all, idle: []), 3)
        XCTAssertEqual(Permissions.optionalOff(all, idle: [.camera]), 2)
        XCTAssertEqual(Permissions.missingRequired(all), 0, "the menu row never moves for an optional one")
    }

    func testThePageSaysTheOptionalOnesQuietlyAndAnIdleOneNotAtAll() {
        let states: [Permissions.Kind: Permissions.State] = [.camera: .missing, .loginItem: .missing]
        let page = PermissionsPage.html(readings(states), build: "b")
        XCTAssertTrue(page.contains("Every required permission is granted"))
        XCTAssertTrue(page.contains("⚠️ 2 optional ones are off."))
        XCTAssertFalse(page.contains("❌"))

        let idle = PermissionsPage.html(readings(states), build: "b", idle: [.camera])
        XCTAssertTrue(idle.contains("⚠️ 1 optional one is off."))
        XCTAssertTrue(idle.contains("Not needed: 🙂 Read my face is off"))
        XCTAssertFalse(idle.contains("Privacy_Camera"), "no Open Settings for a permission nobody asks for")
        XCTAssertEqual(idle.components(separatedBy: "Open Settings").count - 1, 1)

        // With a required one missing the banner is about that alone.
        let bad = PermissionsPage.html(readings([.microphone: .missing, .camera: .missing]), build: "b")
        XCTAssertFalse(bad.contains("optional one"))
    }
}
