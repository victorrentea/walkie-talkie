import XCTest
@testable import WalkieTalkie

/// The permissions' pure parts (2026-11-22): what the ❗ counts, the row's
/// title, the two status codes read, the fakes, and what the page says.
final class PermissionsTests: XCTestCase {

    private func readings(_ states: [Permissions.Kind: Permissions.State]) -> [Permissions.Reading] {
        Permissions.catalogue.map { Permissions.Reading(kind: $0.kind, state: states[$0.kind] ?? .granted) }
    }

    func testOnlyRequiredOnesThatAreKnownLackingCount() {
        XCTAssertEqual(Permissions.missingRequired(readings([:])), 0)
        XCTAssertEqual(Permissions.missingRequired(readings([.accessibility: .missing, .automationTerminal: .notAsked])), 2)
        // Optional ones never raise the ❗; neither does an answer nobody could get.
        XCTAssertEqual(Permissions.missingRequired(readings([.camera: .missing, .systemAudio: .notAsked,
                                                             .loginItem: .missing, .automationTerminal: .unknown])), 0)
    }

    func testTheRowIsTheBuildStampUntilSomethingIsMissing() {
        XCTAssertEqual(Permissions.rowTitle(missing: 0, build: "Nov 22, 10:12"), "Built Nov 22, 10:12")
        XCTAssertEqual(Permissions.rowTitle(missing: 1, build: "x"), "❗ 1 permission missing")
        XCTAssertEqual(Permissions.rowTitle(missing: 3, build: "x"), "❗ 3 permissions missing")
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
        XCTAssertTrue(page.contains("1 required permission is missing"))
        XCTAssertEqual(page.components(separatedBy: "Open Settings").count - 1, 2)
        XCTAssertTrue(page.contains("Privacy_Accessibility"))
        XCTAssertFalse(page.contains("Privacy_Microphone"))
        XCTAssertFalse(page.contains("simulated"))

        let fine = PermissionsPage.html(readings([:]), build: "b")
        XCTAssertTrue(fine.contains("Every required permission is granted"))
        XCTAssertFalse(fine.contains("Open Settings"))
    }
}
