import XCTest
@testable import XuejiCore

final class CitationsTests: XCTestCase {
    private func ref(
        _ authors: String, _ year: Int?, _ title: String, venue: String = "", doi: String = "", url: String = "",
        kind: String = "", created: Double
    ) -> Reference {
        Reference(
            id: UUID(), authors: authors, year: year, title: title, venue: venue, doi: doi, url: url,
            kind: kind, created: Date(timeIntervalSince1970: created)
        )
    }

    private var silva: Reference {
        ref("Silva, João; Jones, Karl", 2020, "Steel policy in Britain", venue: "Journal of Industry",
            doi: "10.1000/abc", kind: "journalArticle", created: 1)
    }
    private var lee: Reference {
        ref("Lee, Min", 2019, "Global supply chains", venue: "Penguin", url: "https://example.com/book",
            kind: "book", created: 2)
    }

    private func run(
        _ text: String, _ references: [Reference], _ style: CitationStyle,
        linked: [UUID] = [], uncited: Bool = false
    ) -> CitationOutput {
        Citations.process(texts: [text], linked: linked, references: references, style: style, includeUncited: uncited)
    }

    func testParsesAuthorFormats() {
        let exact = Authors.parse("Silva, João; Jones, Karl")
        XCTAssertEqual(exact.people, [Person(family: "Silva", given: "João"), Person(family: "Jones", given: "Karl")])
        XCTAssertEqual(Authors.parse("João Silva and Karl Jones").people, exact.people)
        XCTAssertEqual(Authors.parse("Silva, J., Jones, K.").people.map(\.family), ["Silva", "Jones"])
        let etAl = Authors.parse("Silva, J. et al.")
        XCTAssertEqual(etAl.people.count, 1)
        XCTAssertTrue(etAl.etAl)
        XCTAssertFalse(Authors.parse("Chet Alexander").etAl)
        XCTAssertEqual(Authors.parse("OECD").people, [Person(family: "OECD", given: "")])
        XCTAssertEqual(Authors.initials("João Pedro"), "J. P.")
    }

    func testKeysAreStableAndUnique() {
        let a = silva, b = lee
        let c = ref("Silva, João; Jones, Karl", 2020, "A second paper", created: 4)
        let keys = Citations.keys(for: [c, b, a])
        XCTAssertEqual(keys[a.id], "Silva2020")
        XCTAssertEqual(keys[b.id], "Lee2019")
        XCTAssertEqual(keys[c.id], "Silva2020b")
        XCTAssertEqual(Citations.marker(key: "Lee2019", page: " 12 "), "[@Lee2019, 12]")
    }

    func testHarvard() {
        let output = run("As shown [@Silva2020, 12] and [@Lee2019].", [silva, lee], .harvard)
        XCTAssertEqual(output.texts, ["As shown (Silva and Jones, 2020, p. 12) and (Lee, 2019)."])
        XCTAssertEqual(output.bibliography.map(\.text), [
            "Lee, M. (2019) Global supply chains. Penguin. Available at: https://example.com/book.",
            "Silva, J. and Jones, K. (2020) 'Steel policy in Britain', Journal of Industry. Available at: https://doi.org/10.1000/abc.",
        ])
        XCTAssertTrue(output.unknownKeys.isEmpty)
    }

    func testApa() {
        let output = run("[@Silva2020, 12]", [silva], .apa)
        XCTAssertEqual(output.texts, ["(Silva & Jones, 2020, p. 12)"])
        XCTAssertEqual(
            output.bibliography.first?.text,
            "Silva, J., & Jones, K. (2020). Steel policy in Britain. Journal of Industry. https://doi.org/10.1000/abc"
        )
    }

    func testAbnt() {
        let output = run("[@Silva2020, 12]", [silva], .abnt)
        XCTAssertEqual(output.texts, ["(SILVA; JONES, 2020, p. 12)"])
        XCTAssertEqual(
            output.bibliography.first?.text,
            "SILVA, João; JONES, Karl. Steel policy in Britain. Journal of Industry, 2020. Disponível em: https://doi.org/10.1000/abc."
        )
    }

    func testNumberedFollowsFirstCitation() {
        let output = run("First [@Lee2019] then [@Silva2020] and again [@Lee2019, 5]", [silva, lee], .ieee)
        XCTAssertEqual(output.texts, ["First [1] then [2] and again [1, p. 5]"])
        XCTAssertEqual(output.bibliography.map(\.number), [1, 2])
        XCTAssertEqual(
            output.bibliography.first?.text,
            "[1] M. Lee, \"Global supply chains,\" Penguin, 2019. [Online]. Available: https://example.com/book"
        )
    }

    func testTheSameWorkTwiceIsListedOnce() {
        let copy = ref("Silva, João", 2020, "Steel policy in Britain", doi: "https://doi.org/10.1000/ABC", created: 3)
        let output = run("[@Silva2020] and [@Silva2020b]", [silva, copy], .harvard)
        XCTAssertEqual(output.texts, ["(Silva and Jones, 2020) and (Silva and Jones, 2020)"])
        XCTAssertEqual(output.bibliography.count, 1)
    }

    func testSameAuthorsAndYearGetLetters() {
        let second = ref("Silva, João; Jones, Karl", 2020, "A second paper", created: 4)
        let output = run("[@Silva2020] [@Silva2020b]", [silva, second], .harvard)
        XCTAssertEqual(output.texts, ["(Silva and Jones, 2020b) (Silva and Jones, 2020a)"])
        XCTAssertTrue(output.bibliography[0].text.hasPrefix("Silva, J. and Jones, K. (2020a)"))
    }

    func testUnknownKeysStayInTheText() {
        let output = run("see [@Nobody1999]", [silva], .harvard)
        XCTAssertEqual(output.texts, ["see [@Nobody1999]"])
        XCTAssertEqual(output.unknownKeys, ["Nobody1999"])
        XCTAssertTrue(output.bibliography.isEmpty)
    }

    func testUncitedSourcesAreListedOnRequestAndIncompleteOnesFlagged() {
        let bare = ref("", nil, "Untitled report", created: 5)
        XCTAssertTrue(run("no cites", [bare], .harvard, linked: [bare.id]).bibliography.isEmpty)
        let output = run("no cites", [bare], .harvard, linked: [bare.id], uncited: true)
        XCTAssertEqual(output.bibliography.count, 1)
        XCTAssertEqual(output.incomplete, [IncompleteReference(id: bare.id, missing: ["authors", "year"])])
    }

    func testChineseNationalStandard() {
        let article = silva
        let book = ref("王某; 赵某; 钱某; 孙某", 2018, "示例书名", venue: "示例出版社", kind: "book", created: 6)
        let keys = Citations.keys(for: [article, book])
        let text = "见 \(Citations.marker(key: keys[book.id]!, page: "29")) 和 \(Citations.marker(key: keys[article.id]!))"
        let output = run(text, [article, book], .gbt7714)
        XCTAssertEqual(output.texts, ["见 [1]29 和 [2]"])
        XCTAssertEqual(output.bibliography.map(\.text), [
            "[1] 王某, 赵某, 钱某, 等. 示例书名[M]. 示例出版社, 2018.",
            "[2] SILVA J, JONES K. Steel policy in Britain[J]. Journal of Industry, 2020. DOI:10.1000/abc.",
        ])
    }

    func testPageText() {
        XCTAssertEqual(Citations.pageText("12"), "p. 12")
        XCTAssertEqual(Citations.pageText("12-14"), "pp. 12-14")
        XCTAssertEqual(Citations.pageText("p. 3"), "p. 3")
        XCTAssertEqual(Citations.pageText("ch. 2"), "ch. 2")
        XCTAssertNil(Citations.pageText("  "))
    }

    func testCompilingSectionsInOrder() {
        let sections = [
            CompileSection(heading: "Introduction", level: 1, text: "First.\n\nSecond [@Lee2019].", linked: []),
            CompileSection(heading: "Method", level: 2, text: "Third", linked: []),
        ]
        let document = DocumentCompiler.compile(
            title: "Thesis", sections: sections, references: [lee], style: .harvard, includeUncited: false,
            includeBibliography: true, contents: nil, referencesHeading: "References"
        )
        XCTAssertEqual(document.blocks.first, .title("Thesis"))
        XCTAssertEqual(document.blocks[1], .heading(level: 1, text: "Introduction"))
        XCTAssertEqual(document.blocks[3], .paragraph("Second (Lee, 2019)."))
        XCTAssertEqual(document.blocks[4], .heading(level: 2, text: "Method"))
        XCTAssertEqual(document.blocks[6], .heading(level: 1, text: "References"))
        XCTAssertEqual(document.wordCount, 5)
        XCTAssertTrue(DocumentBlock.plainText(document.blocks).hasPrefix("Thesis\n\nIntroduction\n\nFirst."))
    }

    func testWordFileHasHeadingStylesAndValidZipParts() {
        let data = DocxWriter.data(for: [
            .title("T & T"), .heading(level: 1, text: "Intro"), .paragraph("a < b"), .reference("Ref"),
        ])
        XCTAssertEqual(Array(data.prefix(4)), [0x50, 0x4B, 0x03, 0x04])
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("[Content_Types].xml"))
        XCTAssertTrue(text.contains("w:pStyle w:val=\"Heading1\""))
        XCTAssertTrue(text.contains("T &amp; T"))
        XCTAssertTrue(text.contains("a &lt; b"))
        XCTAssertEqual(ZipArchive.crc32(Data("123456789".utf8)), 0xCBF43926)
    }
}
