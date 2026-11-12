import XCTest
@testable import XuejiCore

final class TriageTests: XCTestCase {
    func testWholeWordsOnly() {
        let text = "Security matters. The security council, SECURITY, and securitisation. Insecurity is not security's twin."
        // "Security", "security", "SECURITY" and "security's" count; "securitisation" and "Insecurity" do not.
        XCTAssertEqual(TermCounter.count("security", in: text), 4)
    }

    func testPhraseAndModifier() {
        let text = "The National Security Council met. National\nsecurity grounds apply. Security alone, and homeland security."
        XCTAssertEqual(TermCounter.count("security", after: "national", in: text), 2)
        XCTAssertEqual(TermCounter.count("security", in: text), 4)
        XCTAssertEqual(TermCounter.count("security", after: "", in: text), 0)
    }

    func testHyphenatedLineBreakIsJoined() {
        XCTAssertEqual(TermCounter.count("security", in: "the secu-\nrity services"), 1)
    }

    func testWordsAndDensity() {
        XCTAssertEqual(TermCounter.words(in: "Five words in this sentence."), 5)
        XCTAssertEqual(TermCounter.words(in: "state-owned firms"), 2)
        XCTAssertEqual(TermCounter.words(in: "孔子学院 report"), 5)
        XCTAssertEqual(TermCounter.perThousand(5, words: 6710), 0.75)
        XCTAssertEqual(TermCounter.perThousand(1, words: 10108), 0.1)
        XCTAssertEqual(TermCounter.perThousand(3, words: 0), 0)
    }

    func testChineseTermHasNoWordBoundary() {
        XCTAssertEqual(TermCounter.count("安全", in: "国家安全与安全问题"), 2)
    }

    func testEmptyTermCountsNothing() {
        XCTAssertEqual(TermCounter.count("  ", in: "anything"), 0)
    }

    func testReportDocxIsLandscapeWithTable() {
        let blocks: [ReportBlock] = [
            .title("Report & <more>"),
            .table(columns: [ReportColumn("A", weight: 1), ReportColumn("B", weight: 3)],
                   rows: [["1", ReportCell("two\nlines", shade: .essential)], ["3"]]),
        ]
        let xml = DocxWriter.reportDocument(for: blocks)
        XCTAssertTrue(xml.contains("w:orient=\"landscape\""))
        XCTAssertTrue(xml.contains("Report &amp; &lt;more&gt;"))
        XCTAssertEqual(xml.components(separatedBy: "<w:tr><w:trPr>").count - 1, 3)
        XCTAssertTrue(xml.contains("w:fill=\"D5E8D4\""))
        XCTAssertTrue(xml.contains("<w:tblHeader/>"))
        XCTAssertFalse(DocxWriter.reportData(for: blocks).isEmpty)
    }

    func testReportPlainText() {
        let text = ReportBlock.plainText([.heading("1. Counts"), .table(columns: [ReportColumn("Doc"), ReportColumn("n")], rows: [["A", "5"]])])
        XCTAssertEqual(text, "1. Counts\n\nDoc\tn\nA\t5")
    }
}
