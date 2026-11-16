import XCTest
@testable import XuejiCore

final class ReferenceConverterTests: XCTestCase {
    private func reference(_ kind: String = "", authors: String = "", year: Int? = nil, title: String = "", venue: String = "",
                           volume: String = "", issue: String = "", pages: String = "", publisher: String = "") -> Reference {
        Reference(id: UUID(), authors: authors, year: year, title: title, venue: venue, kind: kind,
                  volume: volume, issue: issue, pages: pages, publisher: publisher)
    }

    func testOfficialChineseJournalArticle() {
        let r = reference("journalArticle", authors: "胡仕胜; 王珏", year: 2020, title: "印度对华示强外交的行为逻辑",
                          venue: "现代国际关系", issue: "7", pages: "25-34")
        XCTAssertEqual(Citations.entry(r, style: .official, letter: ""),
                       "胡仕胜，王珏：《印度对华示强外交的行为逻辑》，载《现代国际关系》，2020 年第 7期，第 25-34 页。")
    }

    func testOfficialEnglishJournalArticle() {
        let r = reference("journalArticle", authors: "Surupa Gupta; Rani Mullen", year: 2019, title: "Indian Foreign Policy Under Modi",
                          venue: "International Studies Perspectives", volume: "20", issue: "1", pages: "1-45")
        XCTAssertEqual(Citations.entry(r, style: .official, letter: ""),
                       "Surupa Gupta & Rani Mullen. “Indian Foreign Policy Under Modi.” International Studies Perspectives, Vol.20, No.1, 2019, pp.1-45")
    }

    func testOfficialIsNumberedWithAPoint() {
        let out = ReferenceConverter.convert("1. 阎学通：《世界权力的转移》，北京大学出版社，2015 年版，第3-34 页。", to: .official)
        XCTAssertEqual(out.count, 1)
        XCTAssertTrue(out[0].text.hasPrefix("1. "))
    }

    func testConvertingAnApaEntryToHarvardKeepsAuthorsAndYear() {
        let out = ReferenceConverter.convert("Buzan, B., Wæver, O., & De Wilde, J. (1998). Security: A new framework for analysis. Lynne Rienner.", to: .harvard)
        XCTAssertEqual(out.count, 1)
        XCTAssertTrue(out[0].text.contains("1998"))
        XCTAssertTrue(out[0].text.contains("Buzan"))
        XCTAssertTrue(out[0].missing.isEmpty)
    }

    func testEntriesThatCannotBeReadAreFlagged() {
        let out = ReferenceConverter.convert("something without structure", to: .official)
        XCTAssertEqual(out.count, 1)
        XCTAssertFalse(out[0].missing.isEmpty)
    }

    func testPagesGluedToThePublisherAndAllThreeAuthorsSurvive() {
        let out = ReferenceConverter.convert(
            "Buzan, B., Wæver, O., & De Wilde, J. (1998). Security: A new framework for analysis. Lynne Rienner Publishers.pp23–28", to: .official)
        XCTAssertEqual(out[0].text,
                       "1. B. Buzan, O. Wæver & J. De Wilde. Security: A new framework for analysis. Lynne Rienner Publishers, 1998. pp.23-28.")
    }

    func testAnOfficialChapterConvertsToItself() {
        let line = "6. Harsh V. Pant. “Changing Contours of Indian Diplomacy Under Narendra Modi.” The Routledge Handbook of Diplomacy and Statecraft. Routledge, 2022. pp.135-145."
        XCTAssertEqual(ReferenceConverter.convert(line, to: .official)[0].text, line)
    }

    func testCommaOnlyChicagoNoteWithCommasInTheTitle() {
        let line = "Barry Buzan, People, States, and Fear: The National Security Problem in International Relations, University of North Carolina Press, 1983, pp. 73–88;"
        let out = ReferenceConverter.convert(line, to: .official)
        XCTAssertEqual(out[0].text,
                       "1. Barry Buzan. People, States, and Fear: The National Security Problem in International Relations. University of North Carolina Press, 1983. pp.73-88.")
        XCTAssertTrue(out[0].missing.isEmpty)
    }

    func testATrailingBlankLineDoesNotMergeTheListIntoOneEntry() {
        let list = "Ole Wæver, ‘Securitization and Desecuritization’, in On Security, 1995, pp. 46–86.\n  Buzan, B. (1998). Security. Lynne Rienner.\n\n"
        XCTAssertEqual(ReferenceParser.splitEntries(list).count, 2)
    }

    func testBlankLinesBetweenEntriesStillSeparateWrappedOnes() {
        let list = "Buzan, B. (1998). Security: A new framework\nfor analysis. Lynne Rienner.\n\nWæver, O. (1995). Securitization. Columbia."
        XCTAssertEqual(ReferenceParser.splitEntries(list).count, 2)
    }
}
