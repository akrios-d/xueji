import XCTest
@testable import XuejiCore

final class QuoteTriageParserTests: XCTestCase {
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
        let report = try XCTUnwrap(ImportedQuoteTriage.parse([page]))
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

    func testOtherPdfIsNotAReport() {
        let words = line(30, [(40, "Just"), (80, "some"), (120, "text")])
        XCTAssertNil(ImportedQuoteTriage.parse([ImportPage(height: 800, words: words)]))
    }
}
