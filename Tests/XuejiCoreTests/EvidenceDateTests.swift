import XCTest
@testable import XuejiCore

final class EvidenceDateTests: XCTestCase {
    func testParsesTheWaysDatesAreWritten() {
        XCTAssertEqual(EvidenceDate.parse("2019"), EvidenceDate(year: 2019))
        XCTAssertEqual(EvidenceDate.parse("Feb 2019"), EvidenceDate(year: 2019, month: 2))
        XCTAssertEqual(EvidenceDate.parse("5 Jun 2019"), EvidenceDate(year: 2019, month: 6, day: 5))
        XCTAssertEqual(EvidenceDate.parse("4–5 Nov 2019"), EvidenceDate(year: 2019, month: 11, day: 4))
        XCTAssertEqual(EvidenceDate.parse("2019-11-04"), EvidenceDate(year: 2019, month: 11, day: 4))
        XCTAssertEqual(EvidenceDate.parse("2019-11"), EvidenceDate(year: 2019, month: 11))
        XCTAssertNil(EvidenceDate.parse("no date here"))
    }

    func testADayThatDoesNotExistIsDropped() {
        XCTAssertEqual(EvidenceDate.parse("31 Feb 2019"), EvidenceDate(year: 2019, month: 2))
    }

    func testValidity() {
        XCTAssertTrue(EvidenceDate(year: 2020, month: 2, day: 29).isValid)
        XCTAssertFalse(EvidenceDate(year: 2019, month: 2, day: 29).isValid)
        XCTAssertFalse(EvidenceDate(year: 2019, month: 13).isValid)
        XCTAssertFalse(EvidenceDate(year: 2019, month: nil, day: 3).isValid)
        XCTAssertFalse(EvidenceDate(year: 1800).isValid)
    }

    func testParsesPeriodsWrittenAsText() {
        func period(_ text: String) -> (EvidenceDate, EvidenceDate?)? { EvidenceDate.parsePeriod(text).map { ($0.from, $0.until) } }
        XCTAssertEqual(period("2019–2023")?.0, EvidenceDate(year: 2019))
        XCTAssertEqual(period("2019–2023")?.1, EvidenceDate(year: 2023))
        XCTAssertEqual(period("2019-2023")?.1, EvidenceDate(year: 2023))
        XCTAssertEqual(period("4–5 Nov 2019")?.0, EvidenceDate(year: 2019, month: 11, day: 4))
        XCTAssertEqual(period("4–5 Nov 2019")?.1, EvidenceDate(year: 2019, month: 11, day: 5))
        XCTAssertEqual(period("Feb–Jun 2019")?.0, EvidenceDate(year: 2019, month: 2))
        XCTAssertEqual(period("Feb–Jun 2019")?.1, EvidenceDate(year: 2019, month: 6))
        XCTAssertEqual(period("Nov 2018 - Feb 2019")?.0, EvidenceDate(year: 2018, month: 11))
        XCTAssertEqual(period("Nov 2018 - Feb 2019")?.1, EvidenceDate(year: 2019, month: 2))
        XCTAssertEqual(period("Feb 2019")?.0, EvidenceDate(year: 2019, month: 2))
        XCTAssertNil(period("Feb 2019")?.1)
        // A date written the ISO way is one date, not a period.
        XCTAssertEqual(period("2019-11-04")?.0, EvidenceDate(year: 2019, month: 11, day: 4))
        XCTAssertNil(period("2019-11-04")?.1)
        XCTAssertNil(period("no date"))
    }

    func testPeriods() {
        let from = EvidenceDate(year: 2019)
        let until = EvidenceDate(year: 2023)
        XCTAssertEqual(EvidenceDate.label(from: from, until: until), "2019 – 2023")
        XCTAssertEqual(EvidenceDate.label(from: from, until: nil), "2019")
        XCTAssertEqual(EvidenceDate.label(from: from, until: from), "2019")
        // The period of a year ends where the next year begins.
        XCTAssertEqual(until.end, EvidenceDate(year: 2024).start)
        XCTAssertEqual(EvidenceDate(year: 2019, month: 12).end, EvidenceDate(year: 2020).start)
        XCTAssertGreaterThan(EvidenceDate(year: 2020).start, EvidenceDate(year: 2019, month: 12, day: 31).start)
    }

    func testLabelAndOrder() {
        XCTAssertEqual(EvidenceDate(year: 2019, month: 11, day: 4).label, "4 Nov 2019")
        XCTAssertEqual(EvidenceDate(year: 2019, month: 2).label, "Feb 2019")
        XCTAssertEqual(EvidenceDate(year: 2019).label, "2019")
        XCTAssertLessThan(EvidenceDate(year: 2019, month: 2).date, EvidenceDate(year: 2019).date)
        XCTAssertLessThan(EvidenceDate(year: 2019).date, EvidenceDate(year: 2019, month: 11, day: 4).date)
    }
}
