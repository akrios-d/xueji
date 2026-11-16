import XCTest
@testable import XuejiCore

final class EvidenceReportParserTests: XCTestCase {
    /// One line of words: (x, text) pairs at a given top.
    private func line(_ top: Double, _ items: [(Double, String)]) -> [ImportWord] {
        items.map { ImportWord(x0: $0.0, x1: $0.0 + Double($0.1.count) * 6, top: top, bottom: top + 10, text: $0.1) }
    }

    /// Words running across the page, a few points apart, like a paragraph.
    private func paragraph(_ top: Double, _ words: [String]) -> [ImportWord] {
        words.enumerated().map { index, text in
            ImportWord(x0: 40 + Double(index) * 36, x1: 40 + Double(index) * 36 + 30, top: top, bottom: top + 10, text: text)
        }
    }

    private var page: ImportPage {
        var words: [ImportWord] = []
        words += line(30, [(40, "Quote"), (80, "Triage")])
        words += line(48, [(40, "2"), (52, "documents"), (110, "·"), (120, "Search"), (160, "term:"), (190, "security"), (240, "(whole"), (280, "word)")])
        words += line(100, [(40, "1."), (60, "How"), (90, "often?")])
        words += line(130, [(40, "#"), (70, "Document"), (250, "Date"), (300, "Words"), (350, "“security”"), (410, "per"), (430, "1,000"), (500, "How"), (520, "the"), (540, "word")])
        words += line(141, [(430, "words")])
        words += line(160, [(40, "1"), (70, "Report"), (250, "Feb"), (275, "2019"), (300, "6,710"), (350, "5"), (410, "0.75"), (500, "Footnotes")])
        words += line(190, [(40, "2"), (70, "Hearing"), (250, "3"), (258, "Sep"), (300, "10,108"), (350, "1"), (410, "0.10"), (500, "Arguing")])
        words += paragraph(230, ["Read", "the", "counts", "with", "care", "here"])
        words += line(260, [(40, "2."), (60, "Strongest"), (120, "quotes")])
        words += line(300, [(40, "#"), (70, "Quote"), (300, "Speaker"), (350, "/"), (360, "locator"), (420, "Class."), (500, "Why")])
        words += line(320, [(40, "1"), (70, "“First"), (110, "quote”"), (300, "Kate"), (330, "White"), (420, "ESSENTIAL"), (500, "Strong")])
        words += line(331, [(300, "HC"), (320, "109,"), (350, "Q77")])
        words += line(360, [(40, "2"), (70, "“Second”"), (300, "Chair"), (420, "COUNTER-EVID"), (500, "Cuts")])
        words += line(371, [(420, "ENCE")])
        words += line(400, [(40, "Date"), (110, "Event"), (250, "Who"), (340, "What"), (500, "“security”")])
        words += line(420, [(40, "Feb"), (65, "2019"), (110, "Report"), (250, "Commission"), (340, "Framed"), (500, "5")])
        words += line(450, [(40, "5"), (55, "Jun"), (75, "2019"), (110, "Session"), (250, "Missing"), (340, "Unmeasured"), (500, "—")])
        words += paragraph(480, ["Shaded", "rows", "are", "gaps", "in", "the", "corpus"])
        words += line(520, [(40, "4."), (60, "Recap"), (100, "—"), (110, "what")])
        words += line(540, [(40, "Two"), (70, "findings:")])
        words += line(560, [(40, "1."), (60, "First"), (100, "finding.")])
        words += line(580, [(40, "2."), (60, "Second"), (110, "one."), (150, "More")])
        words += line(610, [(40, "Method."), (100, "Text")])
        return ImportPage(height: 800, words: words)
    }

    func testReadsAllSections() throws {
        let report = try XCTUnwrap(ImportedEvidenceReport.parse([page]))
        XCTAssertEqual(report.title, "Quote Triage")
        XCTAssertEqual(report.term, "security")
        XCTAssertEqual(report.documents.map(\.title), ["Report", "Hearing"])
        XCTAssertEqual(report.documents.map(\.date), ["Feb 2019", "3 Sep"])
        XCTAssertEqual(report.documents.map(\.words), [6710, 10108])
        XCTAssertEqual(report.documents.map(\.term), [5, 1])
        XCTAssertEqual(report.documents[0].usage, "Footnotes")
        XCTAssertEqual(report.caution, "Read the counts with care here")
        XCTAssertEqual(report.quotes.count, 2)
        XCTAssertEqual(report.quotes[0].text, "First quote")
        XCTAssertEqual(report.quotes[0].originLines, ["Kate White", "HC 109, Q77"])
        XCTAssertEqual(report.quotes[0].kind, .essential)
        XCTAssertEqual(report.quotes[0].why, "Strong")
        XCTAssertEqual(report.quotes[1].kind, .counter)
        XCTAssertEqual(report.events.count, 2)
        XCTAssertEqual(report.events[0].date, "Feb 2019")
        XCTAssertFalse(report.events[0].isGap)
        XCTAssertEqual(report.events[1].date, "5 Jun 2019")
        XCTAssertTrue(report.events[1].isGap)
        XCTAssertEqual(report.findings, ["First finding.", "Second one. More"])
    }

    /// A report whose timeline comes with a table of periods, and whose events name their period and their quote.
    private var pageWithPeriods: ImportPage {
        var words: [ImportWord] = []
        words += line(10, [(40, "Report")])
        words += line(30, [(40, "Search"), (80, "term:"), (120, "security"), (180, "(2"), (200, "documents)")])
        words += line(100, [(40, "2."), (60, "Strongest")])
        words += line(130, [(40, "#"), (70, "Quote"), (300, "Speaker"), (350, "/"), (360, "locator"), (420, "Class"), (500, "Why")])
        words += line(150, [(40, "1"), (70, "“Alpha”"), (300, "Kate"), (420, "ESSENTIAL"), (500, "Strong")])
        words += line(170, [(40, "2"), (70, "“Beta”"), (300, "Chair"), (420, "SUPPORTING"), (500, "Fine")])
        words += line(210, [(40, "3."), (60, "Timeline")])
        words += line(240, [(40, "Period"), (200, "From"), (260, "Until"), (320, "Inside"), (420, "Quotes")])
        words += line(260, [(40, "Expansion"), (200, "2019"), (260, "2023"), (420, "1,"), (435, "2")])
        words += line(280, [(40, "Boom"), (200, "2020"), (260, "2021"), (320, "Expansion"), (420, "2")])
        words += line(320, [(40, "Date"), (110, "Event"), (250, "Who"), (340, "What"), (430, "Period"), (500, "Quote"), (540, "#")])
        words += line(340, [(40, "2019"), (110, "Report"), (250, "Commission"), (340, "Framed"), (430, "Expansion"), (500, "1")])
        words += line(360, [(40, "2020"), (110, "Hearing"), (250, "Chair"), (340, "Frame"), (430, "Boom"), (500, "2")])
        words += line(380, [(40, "Mar"), (60, "2022"), (110, "Missing"), (250, "Nobody"), (340, "None"), (430, "Expansion"), (500, "—")])
        return ImportPage(height: 800, words: words)
    }

    func testReadsPeriodsAndTheLinksOfTheTimeline() throws {
        let report = try XCTUnwrap(ImportedEvidenceReport.parse([pageWithPeriods]))
        XCTAssertEqual(report.quotes.map(\.number), [1, 2])
        XCTAssertEqual(report.periods.map(\.name), ["Expansion", "Boom"])
        XCTAssertEqual(report.periods[0].from, "2019")
        XCTAssertEqual(report.periods[0].until, "2023")
        XCTAssertEqual(report.periods[0].parent, "")
        XCTAssertEqual(report.periods[0].quotes, [1, 2])
        XCTAssertEqual(report.periods[1].parent, "Expansion")
        XCTAssertEqual(report.periods[1].quotes, [2])
        XCTAssertEqual(report.events.count, 3)
        XCTAssertEqual(report.events.map(\.period), ["Expansion", "Boom", "Expansion"])
        XCTAssertEqual(report.events.map(\.quoteNumber), [1, 2, nil])
        XCTAssertEqual(report.events.map(\.isGap), [false, false, true])
    }

    func testOtherPdfIsNotAReport() {
        let words = line(30, [(40, "Just"), (80, "some"), (120, "text")])
        XCTAssertNil(ImportedEvidenceReport.parse([ImportPage(height: 800, words: words)]))
    }
}
