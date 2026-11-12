import XCTest
@testable import XuejiCore

final class TextSearchTests: XCTestCase {
    func testIgnoresCaseAndAccents() {
        XCTAssertTrue(TextSearch.contains("analise", in: "Uma Análise crítica"))
        XCTAssertFalse(TextSearch.contains("   ", in: "anything"))
    }

    func testExcerptKeepsContextAndMarksCuts() {
        let text = String(repeating: "a ", count: 100) + "needle" + String(repeating: " b", count: 100)
        let excerpts = TextSearch.excerpts(of: "NEEDLE", in: text, radius: 10)
        XCTAssertEqual(excerpts.count, 1)
        XCTAssertTrue(excerpts[0].hasPrefix("…"))
        XCTAssertTrue(excerpts[0].hasSuffix("…"))
        XCTAssertTrue(excerpts[0].contains("needle"))
    }

    func testNearbyOccurrencesShareOneExcerptAndLimitApplies() {
        XCTAssertEqual(TextSearch.excerpts(of: "go", in: "go go go", radius: 20).count, 1)
        let far = (0..<5).map { _ in "go" + String(repeating: " x", count: 60) }.joined(separator: " ")
        XCTAssertEqual(TextSearch.excerpts(of: "go", in: far, radius: 5, limit: 3).count, 3)
    }

    func testCollapsesWhitespace() {
        XCTAssertEqual(TextSearch.excerpts(of: "b", in: "a\n\n  b \t c").first, "a b c")
    }

    func testEmptyQueryFindsNothing() {
        XCTAssertTrue(TextSearch.excerpts(of: " ", in: "text").isEmpty)
    }
}
