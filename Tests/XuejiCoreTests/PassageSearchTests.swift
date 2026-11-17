import XCTest
@testable import XuejiCore

final class PassageSearchTests: XCTestCase {
    func testReadsWordsAndQuotedPhrases() {
        XCTAssertEqual(PassageSearch.terms("security \"national security\" state"), ["security", "national security", "state"])
        XCTAssertEqual(PassageSearch.terms("  Security   security "), ["Security"])
        XCTAssertEqual(PassageSearch.terms("\u{201C}rare earths\u{201D}"), ["rare earths"])
        XCTAssertEqual(PassageSearch.terms("国家安全"), ["国家安全"])
        XCTAssertTrue(PassageSearch.terms("   ").isEmpty)
    }

    func testOneTermListsEveryPlaceWithItsPage() {
        let pages = ["Nothing here.", "The state acts. The state waits.", "Another state."]
        let hits = PassageSearch.hits(for: ["state"], inPages: pages)
        XCTAssertEqual(hits.map(\.page), [1, 1, 2])
        XCTAssertEqual(hits.first?.text, "state")
    }

    func testSeveralTermsOnlyCountOnPagesThatHaveAllOfThem() {
        let pages = ["Supply chains matter.", "Supply chains and security together.", "Only security here."]
        let hits = PassageSearch.hits(for: ["supply chains", "security"], inPages: pages)
        XCTAssertEqual(Set(hits.map(\.page)), [1])
        XCTAssertEqual(hits.map(\.term), ["supply chains", "security"])
    }

    func testWholeWordsOnlyAndTheLimitStopsTheList() {
        let pages = ["securitisation is not security", "security security security"]
        XCTAssertEqual(PassageSearch.hits(for: ["security"], inPages: pages).count, 4)
        XCTAssertEqual(PassageSearch.hits(for: ["security"], inPages: pages, limit: 2).count, 2)
    }
}
