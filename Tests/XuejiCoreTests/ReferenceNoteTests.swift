import XCTest
@testable import XuejiCore

/// Footnote and national-standard reference lists, as they come out of a Chinese or bilingual paper.
final class ReferenceNoteTests: XCTestCase {
    private let sample = """
    1. 胡仕胜，王珏：《印度对华示强外交的行为逻辑》，载《现代国际关系》，2020 年第 7期，第 25-34 页。
    2. 阎学通：《世界权力的转移：政治领导与战略竞争》，北京大学出版社，2015 年版，第3-34 页。
    3.Surupa Gupta, et al. “Indian Foreign Policy Under Modi: A New Brand or JustRepackaging?.” International Studies Perspectives, Vol.20, No.1, 2019, pp.1-45
    4.Thomas Christensen. Useful Adversaries: Grand Strategy, Domestic Mobilization, and Sino-American Conflict, 1947-1958. Princeton University Press, 1996.pp.11-13.
    5.  Craig Kafura & Dina Smeltz, “Cooperation, Competition, or Confrontation? Republicans and Democrats Split on China Policy,” The Council Global Affairs, December 2021, https://globalaffairs.org/sites/default/fil es/2021-12/Final%20China%20Brief.pdf, 访问时间：2024 年 7 月 1 日。
    6. Harsh V. Pant. “Changing Contours of Indian Diplomacy Under Narendra Modi.” The Routledge Handbook of Diplomacy and Statecraft. Routledge, 2022. pp.135-145.
    """

    private func references() -> [ImportedReference] { ReferenceParser.parseList(sample) }

    func testEveryEntryOfTheListIsFound() {
        XCTAssertEqual(references().map(\.number), [1, 2, 3, 4, 5, 6])
    }

    func testChineseJournalArticle() {
        let r = references()[0]
        XCTAssertEqual(r.authors, "胡仕胜; 王珏")
        XCTAssertEqual(r.title, "印度对华示强外交的行为逻辑")
        XCTAssertEqual(r.venue, "现代国际关系")
        XCTAssertEqual(r.year, 2020)
    }

    func testChineseBookTakesThePublisherAsVenue() {
        let r = references()[1]
        XCTAssertEqual(r.authors, "阎学通")
        XCTAssertEqual(r.title, "世界权力的转移：政治领导与战略竞争")
        XCTAssertEqual(r.venue, "北京大学出版社")
        XCTAssertEqual(r.year, 2015)
    }

    func testEnglishJournalArticleWithQuotedTitle() {
        let r = references()[2]
        XCTAssertEqual(r.authors, "Surupa Gupta, et al")
        XCTAssertEqual(r.title, "Indian Foreign Policy Under Modi: A New Brand or JustRepackaging?")
        XCTAssertEqual(r.venue, "International Studies Perspectives")
        XCTAssertEqual(r.year, 2019)
    }

    func testEnglishBookWithoutQuotes() {
        let r = references()[3]
        XCTAssertEqual(r.authors, "Thomas Christensen")
        XCTAssertEqual(r.title, "Useful Adversaries: Grand Strategy, Domestic Mobilization, and Sino-American Conflict, 1947-1958")
        XCTAssertEqual(r.venue, "Princeton University Press")
        XCTAssertEqual(r.year, 1996)
    }

    func testWebReportKeepsTheLinkTheDateAndTheAccessDate() {
        let r = references()[4]
        XCTAssertEqual(r.authors, "Craig Kafura; Dina Smeltz")
        XCTAssertEqual(r.title, "Cooperation, Competition, or Confrontation? Republicans and Democrats Split on China Policy")
        XCTAssertEqual(r.year, 2021)
        XCTAssertEqual(r.accessed, "2024-07-01")
        XCTAssertEqual(r.url?.host, "globalaffairs.org")
    }

    func testChapterInAnEditedBookKeepsAnInitialInTheAuthorName() {
        let r = references()[5]
        XCTAssertEqual(r.authors, "Harsh V. Pant")
        XCTAssertEqual(r.title, "Changing Contours of Indian Diplomacy Under Narendra Modi")
        XCTAssertEqual(r.venue, "The Routledge Handbook of Diplomacy and Statecraft")
        XCTAssertEqual(r.year, 2022)
    }

    func testNumberedStartsAcceptTheCommonWaysOfNumbering() {
        XCTAssertEqual(ReferenceParser.numberedStart("[3] Text")?.number, 3)
        XCTAssertEqual(ReferenceParser.numberedStart("3.Text")?.text, "Text")
        XCTAssertEqual(ReferenceParser.numberedStart("12．文本")?.number, 12)
        XCTAssertNil(ReferenceParser.numberedStart("2019. Not a number of the list"))
    }

    func testHarvardEntriesAreReadAsBefore() {
        let r = ReferenceParser.parse(number: 1, text: "Silva, J. (2020) ‘A title’, Journal of Things, 3(2), pp. 1-9. DOI: 10.1000/abc.")
        XCTAssertEqual(r.year, 2020)
        XCTAssertEqual(r.title, "A title")
        XCTAssertEqual(r.doi, "10.1000/abc")
    }

    // MARK: APA, Chicago and Springer

    func testApaEntryHasThePeopleSplitAndTheTitleAfterTheFullStop() {
        let r = ReferenceParser.parse(
            number: 1,
            text: "Buzan, B., Wæver, O., & De Wilde, J. (1998). Security: A new framework for analysis. Lynne Rienner Publishers."
        )
        XCTAssertEqual(r.year, 1998)
        XCTAssertEqual(r.title, "Security: A new framework for analysis")
        XCTAssertEqual(r.venue, "Lynne Rienner Publishers")
        let people = Authors.parse(r.authors).people
        XCTAssertEqual(people.map(\.family), ["Buzan", "Wæver", "De Wilde"])
        XCTAssertEqual(people.map(\.given), ["B.", "O.", "J."])
    }

    func testChicagoNoteWithSingleQuotesAndAnEditedBook() {
        let r = ReferenceParser.parse(
            number: 2,
            text: "Ole Wæver, ‘Securitization and Desecuritization’, in On Security, ed. R. D Lipschutz (New York: Columbia University Press, 1995), pp. 46–86."
        )
        XCTAssertEqual(r.authors, "Ole Wæver")
        XCTAssertEqual(r.title, "Securitization and Desecuritization")
        XCTAssertEqual(r.venue, "On Security")
        XCTAssertEqual(r.year, 1995)
    }

    func testSpringerEntryWithInitialsAndASeriesNumber() {
        let r = ReferenceParser.parse(
            number: 3,
            text: "Buzan B, Wæver O (2003) Regions and powers: the structure of international security (No. 91). Cambridge University Press, Cambridge."
        )
        XCTAssertEqual(r.year, 2003)
        XCTAssertEqual(r.title, "Regions and powers: the structure of international security")
        XCTAssertEqual(r.venue, "Cambridge University Press, Cambridge")
        let people = Authors.parse(r.authors).people
        XCTAssertEqual(people.map(\.family), ["Buzan", "Wæver"])
        XCTAssertEqual(people.map(\.given), ["B", "O"])
    }

    func testAnApostropheInATitleDoesNotCloseASingleQuote() {
        let r = ReferenceParser.parse(number: 4, text: "Jane Roe, ‘Modi’s China policy’, Asian Survey, 2020, pp. 1-9.")
        XCTAssertEqual(r.title, "Modi’s China policy")
        XCTAssertEqual(r.venue, "Asian Survey")
    }
}
