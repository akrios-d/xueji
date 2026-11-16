import XCTest
@testable import XuejiCore

final class ReferenceFinderTests: XCTestCase {
    private let crossref = """
    {"message":{"items":[{"title":["Indian Foreign Policy Under Modi"],"author":[{"given":"Surupa","family":"Gupta"},{"given":"Rani","family":"Mullen"}],
    "issued":{"date-parts":[[2019,3]]},"container-title":["International Studies Perspectives"],"volume":"20","issue":"1","page":"1–45",
    "DOI":"10.1093/isp/ekz001","type":"journal-article","publisher":"Oxford University Press"},{"author":[]}]}}
    """

    private let library = """
    {"docs":[{"key":"/works/OL1W","title":"Security","author_name":["Barry Buzan","Ole Wæver"],"first_publish_year":1998,"publisher":["Lynne Rienner Publishers"]}]}
    """

    func testCrossrefAnswerBecomesAJournalArticle() {
        let found = ReferenceFinder.parseCrossref(Data(crossref.utf8))
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found[0].authors, "Gupta, Surupa; Mullen, Rani")
        XCTAssertEqual(found[0].year, 2019)
        XCTAssertEqual(found[0].pages, "1-45")
        XCTAssertEqual(found[0].kind, "journalArticle")
        XCTAssertEqual(found[0].url, "https://doi.org/10.1093/isp/ekz001")
    }

    func testOpenLibraryAnswerBecomesABook() {
        let found = ReferenceFinder.parseOpenLibrary(Data(library.utf8))
        XCTAssertEqual(found.first?.kind, "book")
        XCTAssertEqual(found.first?.publisher, "Lynne Rienner Publishers")
        XCTAssertEqual(found.first?.url, "https://openlibrary.org/works/OL1W")
    }

    func testFindMergesBothCataloguesAndSurvivesOneBeingDown() async {
        let finder = ReferenceFinder { url in
            if url.host == "api.crossref.org" { return Data(self.crossref.utf8) }
            throw URLError(.notConnectedToInternet)
        }
        let found = await finder.find("modi")
        XCTAssertEqual(found.map(\.source), ["Crossref"])
    }

    func testAFoundBookPrintsInTheOfficialStyle() {
        let found = ReferenceFinder.parseOpenLibrary(Data(library.utf8))[0]
        XCTAssertEqual(
            Citations.entry(found.reference, style: .official, letter: ""),
            "Barry Buzan & Ole Wæver. Security. Lynne Rienner Publishers, 1998."
        )
    }
}
