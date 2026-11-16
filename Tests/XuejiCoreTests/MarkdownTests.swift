import XCTest
@testable import XuejiCore

final class MarkdownTests: XCTestCase {
    func testBoldItalicAndPlain() {
        XCTAssertEqual(MarkdownInline.pieces("a **b** and *c*"), [
            .text("a ", bold: false, italic: false), .text("b", bold: true, italic: false),
            .text(" and ", bold: false, italic: false), .text("c", bold: false, italic: true),
        ])
    }

    func testFormulaAndMoney() {
        XCTAssertEqual(MarkdownInline.pieces("so $x^2$ holds"), [
            .text("so ", bold: false, italic: false), .math("x^2"), .text(" holds", bold: false, italic: false),
        ])
        XCTAssertEqual(MarkdownInline.pieces("it costs $5 and $10"), [.text("it costs $5 and $10", bold: false, italic: false)])
    }

    func testSnakeCaseAndLoneStarStayText() {
        XCTAssertEqual(MarkdownInline.stripped("my_file_name and 2 * 3"), "my_file_name and 2 * 3")
    }

    func testListsAndDisplayFormula() {
        XCTAssertEqual(MarkdownBlocks.parts(of: "Intro\n- one\n- two\n1. first"), [
            .lines(["Intro"]), .bullet("one"), .bullet("two"), .numbered(1, "first"),
        ])
        XCTAssertEqual(MarkdownBlocks.parts(of: "$$ a+b $$"), [.display("a+b")])
    }

    func testLatexBecomesEquationMarkup() {
        let xml = LatexMath.omml("\\frac{a}{b} + x^2 + \\sqrt{y} + \\sum_{i=1}^{n} x_i")
        for tag in ["<m:f>", "<m:sSup>", "<m:rad>", "<m:nary>", "<m:sSub>"] { XCTAssertTrue(xml.contains(tag), tag) }
        XCTAssertTrue(LatexMath.omml("\\alpha").contains("α"))
    }

    func testDocxCarriesFormattingAndEquations() {
        let xml = DocxWriter.document(for: [.paragraph("**Bold** and $E=mc^2$\n\n- item")])
        XCTAssertTrue(xml.contains("<w:b/>"))
        XCTAssertTrue(xml.contains("<m:oMath>"))
        XCTAssertTrue(xml.contains("xmlns:m="))
        let plain = DocxWriter.document(for: [.paragraph("Just text")])
        XCTAssertTrue(plain.contains("<w:p><w:r><w:t xml:space=\"preserve\">Just text</w:t></w:r></w:p>"))
    }
}
