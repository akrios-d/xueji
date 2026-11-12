import XCTest
@testable import XuejiCore

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

/// Builds a word at a position, the way the PDF reader reports it.
private func word(_ text: String, x: Double, top: Double) -> ImportWord {
    ImportWord(x0: x, x1: x + Double(text.count) * 5, top: top, bottom: top + 8, text: text)
}

/// Several words that start at the same x and flow to the right, on one line.
private func words(_ text: String, x: Double, top: Double) -> [ImportWord] {
    var cursor = x
    return text.split(separator: " ").map { piece in
        defer { cursor += Double(piece.count) * 5 + 3 }
        return word(String(piece), x: cursor, top: top)
    }
}

// MARK: - Source triage

private func triageHeader(top: Double) -> [ImportWord] {
    [
        word("#", x: 40, top: top), word("Period", x: 70, top: top), word("Source", x: 130, top: top),
        word("Link", x: 280, top: top), word("Classificati", x: 400, top: top),
        word("Triage", x: 470, top: top), word("Note", x: 505, top: top),
        word("on", x: 400, top: top + 10),
    ]
}

private func triagePages(repeatHeader: Bool = true) -> [ImportPage] {
    var first = triageHeader(top: 50)
    // Row 1.
    first += [word("1", x: 40, top: 80)] + words("Theory", x: 70, top: 80)
    first += words("Alpha Paper", x: 130, top: 80) + words("(2021) (Journal of X /", x: 130, top: 90) + words("Wiley)", x: 130, top: 100)
    first += words("example.org ›", x: 280, top: 80) + words("alpha-paper", x: 280, top: 90)
    first += words("ESSENTIAL", x: 400, top: 80)
    first += words("Needed first.", x: 470, top: 80)
    // Row 2 starts at the bottom of the page and continues on the next one.
    first += [word("2", x: 40, top: 140)] + words("Phase 1", x: 70, top: 140)
    first += words("Beta Study", x: 130, top: 140)
    first += words("other.org › beta", x: 280, top: 140)
    first += words("COMPLEMEN", x: 400, top: 140) + words("TARY", x: 400, top: 150)
    first += words("Gives depth,", x: 470, top: 140)

    var second = repeatHeader ? triageHeader(top: 50) : []
    second += words("(Press, 2019)", x: 130, top: 80)
    second += words("which is useful.", x: 470, top: 80)
    second += [word("3", x: 40, top: 110)] + words("Phase 2", x: 70, top: 110)
    second += words("Gamma Report (2020) (RUSI)", x: 130, top: 110)
    second += words("rusi.org › gamma", x: 280, top: 110)
    second += words("SECONDARY", x: 400, top: 110)
    second += words("Context only.", x: 470, top: 110)
    // The title of the next table ends this one.
    second += words("Perceptions by Period", x: 40, top: 180)
    second += [word("5", x: 40, top: 200), word("not", x: 470, top: 200), word("a", x: 480, top: 200), word("row", x: 490, top: 200)]

    return [ImportPage(height: 612, words: first), ImportPage(height: 612, words: second)]
}

final class TriageImportTests: XCTestCase {
    func testReadsRowsAcrossAPageBreak() throws {
        let document = try PDFImporter.parse(triagePages())
        guard case .sourceTriage(let sources) = document else { return XCTFail("expected a triage table") }
        XCTAssertEqual(sources.map(\.title), ["Alpha Paper", "Beta Study", "Gamma Report"])

        let first = sources[0]
        XCTAssertEqual(first.venue, "Journal of X / Wiley")
        XCTAssertEqual(first.year, 2021)
        XCTAssertEqual(first.phase, "Theory")
        XCTAssertEqual(first.classification, .essential)
        XCTAssertEqual(first.url, URL(string: "https://example.org"))
        XCTAssertEqual(first.triageNote, "Needed first.")

        // The classification and the note of row 2 are split over two pages and stay in reading order.
        let second = sources[1]
        XCTAssertEqual(second.classification, .complementary)
        XCTAssertEqual(second.triageNote, "Gives depth, which is useful.")
        XCTAssertEqual(second.venue, "Press, 2019")
        XCTAssertEqual(second.year, 2019)
        XCTAssertEqual(second.phase, "Phase 1")
    }

    func testContinuesOverAPageThatDoesNotRepeatTheHeading() throws {
        let document = try PDFImporter.parse(triagePages(repeatHeader: false))
        guard case .sourceTriage(let sources) = document else { return XCTFail() }
        XCTAssertEqual(sources.map(\.title), ["Alpha Paper", "Beta Study", "Gamma Report"])
        XCTAssertEqual(sources[1].triageNote, "Gives depth, which is useful.")
    }

    func testKeepsARowThatSitsInTheBottomMarginAndDropsThePageNumber() throws {
        var page = triageHeader(top: 50)
        page += [word("1", x: 40, top: 80)] + words("Theory", x: 70, top: 80) + words("Alpha Paper (Journal)", x: 130, top: 80)
        page += words("example.org ›", x: 280, top: 80) + words("ESSENTIAL", x: 400, top: 80) + words("Note.", x: 470, top: 80)
        // Close to the bottom edge of a 612-point page, where a fixed margin would have cut it.
        page += [word("2", x: 40, top: 595)] + words("Theory", x: 70, top: 595) + words("Beta Study (Journal)", x: 130, top: 595)
        page += words("other.org ›", x: 280, top: 595) + words("SECONDARY", x: 400, top: 595) + words("Note.", x: 470, top: 595)
        page += [word("3", x: 300, top: 640)] // page number
        let document = try PDFImporter.parse([ImportPage(height: 700, words: page)])
        guard case .sourceTriage(let sources) = document else { return XCTFail() }
        XCTAssertEqual(sources.map(\.title), ["Alpha Paper", "Beta Study"])
    }

    func testReadsTheSuggestedReadingOrder() throws {
        var page = triageHeader(top: 50)
        page += [word("1", x: 40, top: 80)] + words("Theory", x: 70, top: 80) + words("Alpha Paper (Journal)", x: 130, top: 80)
        page += words("example.org ›", x: 280, top: 80) + words("ESSENTIAL", x: 400, top: 80) + words("Note.", x: 470, top: 80)
        page += [word("2", x: 40, top: 110)] + words("Theory", x: 70, top: 110) + words("Beta Study (Journal)", x: 130, top: 110)
        page += words("other.org ›", x: 280, top: 110) + words("ESSENTIAL", x: 400, top: 110) + words("Note.", x: 470, top: 110)
        page += words("Suggested Reading Order", x: 40, top: 160) + words("Read in this sequence:", x: 40, top: 175)
        page += words("1. [2] Beta Study — it frames", x: 60, top: 190) + words("everything", x: 78, top: 202)
        page += words("2.[1] Alpha Paper — then the evidence", x: 60, top: 214)
        page += words("After the essential sources, add the rest.", x: 40, top: 240)
        let document = try PDFImporter.parse([ImportPage(height: 700, words: page)])
        guard case .sourceTriage(let sources) = document else { return XCTFail() }
        XCTAssertEqual(sources.map(\.title), ["Alpha Paper", "Beta Study"])
        XCTAssertEqual(sources[1].readingOrder, 1)
        XCTAssertEqual(sources[1].readingReason, "it frames everything")
        XCTAssertEqual(sources[0].readingOrder, 2)
    }

    func testTextThatFollowsTheTableIsNotARow() throws {
        let document = try PDFImporter.parse(triagePages())
        guard case .sourceTriage(let sources) = document else { return XCTFail() }
        XCTAssertEqual(sources.count, 3)
        XCTAssertEqual(sources[2].classification, .secondary)
    }

    func testSplitSourceKeepsTheTitleWhenThereIsNoVenue() {
        let parts = TriageTableParser.splitSource("A plain title")
        XCTAssertEqual(parts.title, "A plain title")
        XCTAssertEqual(parts.venue, "")
        XCTAssertNil(parts.year)
    }

    func testOnlyTheSiteOfAShortenedLinkIsUsed() {
        XCTAssertEqual(TriageTableParser.siteURL(from: "journals.sagepub.com ›securitization"), URL(string: "https://journals.sagepub.com"))
        XCTAssertEqual(TriageTableParser.siteURL(from: "researchbriefings.files.parliament.uk › x"), URL(string: "https://researchbriefings.files.parliament.uk"))
        XCTAssertNil(TriageTableParser.siteURL(from: "no link here"))
    }

    func testAPageWithoutAKnownTableIsRefused() {
        let page = ImportPage(height: 792, words: words("Just some text about nothing", x: 40, top: 100))
        XCTAssertThrowsError(try PDFImporter.parse([page])) { XCTAssertEqual($0 as? XuejiError, .unrecognizedImport) }
    }
}

// MARK: - Who said what

private func statementsHeader(top: Double) -> [ImportWord] {
    [
        word("Date", x: 40, top: top), word("Who", x: 90, top: top), word("(and", x: 110, top: top), word("where)", x: 130, top: top),
        word("Position", x: 220, top: top), word("taken", x: 260, top: top),
        word("Where", x: 340, top: top), word("to", x: 370, top: top), word("find", x: 380, top: top),
        word("Ref", x: 480, top: top),
        word("phrase)", x: 340, top: top + 10),
    ]
}

private func statementsPages() -> [ImportPage] {
    var first = words("Period 1 (2010 – 2016)", x: 40, top: 40)
    first += statementsHeader(top: 60)
    // Exact date over two lines, one reference.
    first += words("13 Jul", x: 40, top: 90) + words("2011", x: 40, top: 100)
    first += words("Pew Research Center (C)", x: 90, top: 90) + words("Global survey", x: 90, top: 100)
    first += words("59% favourable.", x: 220, top: 90)
    first += words("Ch. 4 ¶2.", x: 340, top: 90)
    first += [word("[28]", x: 480, top: 90)]
    // Approximate date (year only), two references on two lines.
    first += [word("2025", x: 40, top: 130)]
    first += words("Zhang (S) and", x: 90, top: 130) + words("Breslin (S)", x: 90, top: 140)
    first += words("Securitised.", x: 220, top: 130)
    first += words("Abstract.", x: 340, top: 130)
    first += [word("[3]", x: 480, top: 130), word("[45]", x: 480, top: 140)]
    // A note and the reference list.
    first += words("Caveats: check the quotes.", x: 40, top: 200)

    var second = words("References", x: 40, top: 40)
    second += words("[3] Breslin, S. (2025) ‘Bundling threats: why perceptions changed’, Journal, 18(2). DOI:", x: 40, top: 60)
    second += words("10.1093/cjip/poaf003.", x: 60, top: 70)
    second += words("[28] Pew Research Center (2011) ‘Chapter 4: Views of China’, Global Attitudes Project, 13 July. Available at:", x: 40, top: 90)
    second += words("https://www.pewresearch.org/global/2011/07/13/chapter-4-", x: 60, top: 100)
    second += words("views-of-china/", x: 60, top: 110)
    second += words("[45] Zhang, C. (2025) Market-security tensions. London: Press. Available at: https://example.org/zhang", x: 40, top: 130)
    second += [word("2", x: 300, top: 760)] // page number

    return [ImportPage(height: 792, words: first), ImportPage(height: 792, words: second)]
}

final class StatementsImportTests: XCTestCase {
    func testReadsRowsFieldsAndReferences() throws {
        let document = try PDFImporter.parse(statementsPages())
        guard case .statements(let statements, let references) = document else { return XCTFail("expected statements") }
        XCTAssertEqual(statements.count, 2)

        let pew = statements[0]
        XCTAssertEqual(pew.actor, "Pew Research Center")
        XCTAssertEqual(pew.actorKind, "citizens")
        XCTAssertEqual(pew.context, "Global survey")
        XCTAssertEqual(pew.date, CalendarDay(year: 2011, month: 7, day: 13))
        XCTAssertFalse(pew.isApproximate)
        XCTAssertEqual(pew.phase, "Period 1 (2010 – 2016)")
        XCTAssertEqual(pew.position, "59% favourable.")
        XCTAssertEqual(pew.locator, "Ch. 4 ¶2.")
        XCTAssertEqual(pew.referenceNumbers, [28])

        let zhang = statements[1]
        XCTAssertEqual(zhang.actor, "Zhang (S) and Breslin")
        XCTAssertEqual(zhang.actorKind, "scholar")
        XCTAssertEqual(zhang.date, CalendarDay(year: 2025, month: 1, day: 1))
        XCTAssertTrue(zhang.isApproximate)
        XCTAssertEqual(zhang.referenceNumbers, [3, 45])

        XCTAssertEqual(references.count, 3)
        XCTAssertEqual(references[28]?.title, "Chapter 4: Views of China")
        XCTAssertEqual(references[28]?.year, 2011)
        XCTAssertEqual(references[28]?.url, URL(string: "https://www.pewresearch.org/global/2011/07/13/chapter-4-views-of-china/"))
        XCTAssertEqual(references[3]?.doi, "10.1093/cjip/poaf003")
        XCTAssertEqual(references[3]?.url, URL(string: "https://doi.org/10.1093/cjip/poaf003"))
        XCTAssertEqual(references[45]?.title, "Market-security tensions")
    }

    func testDatesAreExactOnlyWhenDayMonthAndYearAreKnown() {
        func parse(_ label: String) -> (CalendarDay?, Bool) { StatementsTableParser.parseDate(label) }
        XCTAssertEqual(parse("13 Jul 2011").0, CalendarDay(year: 2011, month: 7, day: 13))
        XCTAssertFalse(parse("13 Jul 2011").1)
        XCTAssertEqual(parse("Nov 2016").0, CalendarDay(year: 2016, month: 11, day: 1))
        XCTAssertTrue(parse("Nov 2016").1)
        XCTAssertTrue(parse("c. 31 Jul 2016").1)
        XCTAssertTrue(parse("2016 (month not confirme d)").1)
        XCTAssertNil(parse("sometime").0)
    }
}

// MARK: - Importing into a workspace

private struct ImportFixture {
    var ws = Workspace()
    let human: Member
    let agent: Member
    let track: Track

    init() throws {
        human = Member(name: "Nade", kind: .human, role: "owner")
        agent = Member(name: "Researcher", kind: .agent, role: "researcher", ownerID: human.id)
        track = Track(name: "Dissertation")
        try ws.addMember(human)
        try ws.addMember(agent)
        ws.addTrack(track)
    }
}

final class WorkspaceImportTests: XCTestCase {
    func testImportedSourcesWaitForApprovalInDocumentOrder() throws {
        var f = try ImportFixture()
        let document = try PDFImporter.parse(triagePages())
        let summary = try f.ws.importDocument(document, trackID: f.track.id, by: f.human.id, fileName: "triage.pdf", at: t0)

        XCTAssertEqual(summary.sourcesAdded, 3)
        let pending = f.ws.pendingApprovals()
        XCTAssertEqual(pending.map(\.title), ["Alpha Paper", "Beta Study", "Gamma Report"])
        XCTAssertEqual(pending[0].classification, .essential)
        XCTAssertEqual(pending[0].values["phase"], .text("Theory"))
        XCTAssertEqual(f.ws.events.first { $0.itemID == pending[0].id }?.detail, "import:triage.pdf")

        _ = try f.ws.approve(itemID: pending[0].id, by: f.human.id, at: t0)
        XCTAssertEqual(f.ws.items[pending[0].id]?.approval, .approved)
    }

    func testImportingTheSamePDFTwiceAddsNothing() throws {
        var f = try ImportFixture()
        let document = try PDFImporter.parse(triagePages())
        try f.ws.importDocument(document, trackID: f.track.id, by: f.human.id, fileName: "a.pdf", at: t0)
        let again = try f.ws.importDocument(document, trackID: f.track.id, by: f.human.id, fileName: "a.pdf", at: t0)
        XCTAssertEqual(again.sourcesAdded, 0)
        XCTAssertEqual(again.skippedDuplicates, 3)
        XCTAssertEqual(f.ws.items.count, 3)
    }

    func testStatementsAreLinkedToTheSourcesOfTheirReferences() throws {
        var f = try ImportFixture()
        let document = try PDFImporter.parse(statementsPages())
        let summary = try f.ws.importDocument(document, trackID: f.track.id, by: f.human.id, fileName: "who.pdf", at: t0)

        XCTAssertEqual(summary.statementsAdded, 2)
        XCTAssertEqual(summary.sourcesAdded, 3) // every cited reference becomes a source to approve
        let statements = f.ws.items.values.filter { $0.kind == .statement }
        let pew = try XCTUnwrap(statements.first { $0.title.hasPrefix("Pew") })
        guard case .relation(let sourceID)? = pew.values["source"] else { return XCTFail("no source linked") }
        XCTAssertEqual(f.ws.items[sourceID]?.title, "Chapter 4: Views of China")
        XCTAssertEqual(pew.values["verification"], .select("toVerify"))
        XCTAssertEqual(pew.values["dateApproximate"], .checkbox(false))
        XCTAssertEqual(pew.approval, .pending)

        let zhang = try XCTUnwrap(statements.first { $0.title.hasPrefix("Zhang") })
        XCTAssertTrue(zhang.details.contains("Also cited: Market-security tensions (2025)"))
    }

    func testOnlyAHumanCanImport() throws {
        var f = try ImportFixture()
        let document = try PDFImporter.parse(triagePages())
        XCTAssertThrowsError(try f.ws.importDocument(document, trackID: f.track.id, by: f.agent.id, fileName: "x.pdf")) {
            XCTAssertEqual($0 as? XuejiError, .notPermitted)
        }
    }

    func testASourceRowWithoutAUsableLinkIsSkippedAndCounted() throws {
        var f = try ImportFixture()
        let document = ImportedDocument.sourceTriage([ImportedSource(title: "No link", url: nil)])
        let summary = try f.ws.importDocument(document, trackID: f.track.id, by: f.human.id, fileName: "x.pdf", at: t0)
        XCTAssertEqual(summary.skippedWithoutLink, 1)
        XCTAssertTrue(f.ws.items.isEmpty)
    }
}
