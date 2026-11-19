import XCTest
@testable import WalkieTalkie

final class WorkshopCountryTests: XCTestCase {
    let tab = WorkshopCountry.parseZoneTab("# comment\nPT\t+3843-00908\tEurope/Lisbon\tPortugal (mainland)\nRO\t+4426+02606\tEurope/Bucharest\n")

    func testZoneTabParsed() {
        XCTAssertEqual(tab, ["Europe/Lisbon": "PT", "Europe/Bucharest": "RO"])
    }

    func testTodaysForeignPickIsTheCountry() {
        let c = WorkshopCountry.from(tz: "Europe/Lisbon", day: "2026-11-19", today: "2026-11-19", zoneTab: tab)
        XCTAssertEqual(c, WorkshopCountry(name: "Portugal", iso: "PT"))
        XCTAssertTrue(c!.clause.contains("workshop in Portugal"))
        XCTAssertTrue(c!.clause.contains("English"))
        XCTAssertEqual(c!.googleItems.map(\.value), ["en", "pt"])
    }

    func testRomaniaYesterdayOrNothingIsNil() {
        XCTAssertNil(WorkshopCountry.from(tz: "Europe/Bucharest", day: "2026-11-19", today: "2026-11-19", zoneTab: tab))
        XCTAssertNil(WorkshopCountry.from(tz: "Europe/Lisbon", day: "2026-11-18", today: "2026-11-19", zoneTab: tab))
        XCTAssertNil(WorkshopCountry.from(tz: nil, day: nil, today: "2026-11-19", zoneTab: tab))
        XCTAssertNil(WorkshopCountry.from(tz: "Mars/Olympus", day: "2026-11-19", today: "2026-11-19", zoneTab: tab))
    }

    func testTheRealZoneTabKnowsLisbon() {
        XCTAssertEqual(WorkshopCountry.zoneTab["Europe/Lisbon"], "PT")
    }
}
