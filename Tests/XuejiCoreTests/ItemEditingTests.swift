import XCTest
@testable import XuejiCore

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private let link = URL(string: "https://example.org/paper")!

private struct Fixture {
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

private func expect(
    _ expected: XuejiError,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ body: () throws -> Void
) {
    XCTAssertThrowsError(try body(), file: file, line: line) {
        XCTAssertEqual($0 as? XuejiError, expected, file: file, line: line)
    }
}

final class ItemEditingTests: XCTestCase {
    func testRenameTrimsAndRecordsHistory() throws {
        var f = try Fixture()
        let item = try f.ws.createItem(trackID: f.track.id, kind: .note, title: "Old", by: f.human.id, at: t0)
        try f.ws.renameItem(itemID: item.id, to: "  New title ", by: f.human.id, at: t0)
        XCTAssertEqual(f.ws.items[item.id]?.title, "New title")
        XCTAssertEqual(f.ws.events.last?.kind, .edited)
        expect(.emptyText) { _ = try f.ws.renameItem(itemID: item.id, to: "  ", by: f.human.id) }
    }

    func testAgentsCannotEditACard() throws {
        var f = try Fixture()
        let item = try f.ws.createItem(trackID: f.track.id, kind: .note, title: "N", by: f.human.id, at: t0)
        expect(.notPermitted) { _ = try f.ws.renameItem(itemID: item.id, to: "x", by: f.agent.id) }
        expect(.notPermitted) { _ = try f.ws.setNotes(itemID: item.id, to: "x", by: f.agent.id) }
        expect(.notPermitted) { _ = try f.ws.setClassification(itemID: item.id, to: .essential, by: f.agent.id) }
        expect(.notPermitted) { _ = try f.ws.setLink(itemID: item.id, to: link, by: f.agent.id) }
    }

    func testNotesAreKeptAsTypedAndLeaveNoHistoryEntry() throws {
        var f = try Fixture()
        let item = try f.ws.createItem(trackID: f.track.id, kind: .note, title: "N", by: f.human.id, at: t0)
        let events = f.ws.events.count
        try f.ws.setNotes(itemID: item.id, to: "  my own thoughts\n", by: f.human.id)
        XCTAssertEqual(f.ws.items[item.id]?.notes, "  my own thoughts\n")
        XCTAssertEqual(f.ws.events.count, events)
    }

    func testHumanCanCorrectAnAgentProposalBeforeApprovingIt() throws {
        var f = try Fixture()
        let item = try f.ws.createItem(trackID: f.track.id, kind: .source, title: "Paper", url: link, by: f.agent.id, at: t0)
        try f.ws.setClassification(itemID: item.id, to: .essential, by: f.human.id, at: t0)
        try f.ws.approve(itemID: item.id, by: f.human.id, at: t0)
        XCTAssertEqual(f.ws.items[item.id]?.classification, .essential)
    }

    func testChangingTheLinkClearsVerificationAndSourcesKeepALink() throws {
        var f = try Fixture()
        let source = try f.ws.createItem(
            trackID: f.track.id, kind: .source, title: "Paper", url: link, linkVerifiedAt: t0,
            by: f.human.id, at: t0
        )
        try f.ws.setLink(itemID: source.id, to: URL(string: "https://example.org/other")!, by: f.human.id, at: t0)
        XCTAssertNil(f.ws.items[source.id]?.linkVerifiedAt)
        expect(.sourceRequiresValidURL) { _ = try f.ws.setLink(itemID: source.id, to: nil, by: f.human.id) }
        expect(.invalidFieldValue) { _ = try f.ws.setLink(itemID: source.id, to: URL(string: "ftp://example.org")!, by: f.human.id) }

        let note = try f.ws.createItem(trackID: f.track.id, kind: .note, title: "N", url: link, by: f.human.id, at: t0)
        try f.ws.setLink(itemID: note.id, to: nil, by: f.human.id, at: t0)
        XCTAssertNil(f.ws.items[note.id]?.url)
    }

    func testClassificationCanBeClearedAndUnknownItemsFail() throws {
        var f = try Fixture()
        let item = try f.ws.createItem(trackID: f.track.id, kind: .note, title: "N", by: f.human.id, at: t0)
        try f.ws.setClassification(itemID: item.id, to: .secondary, by: f.human.id, at: t0)
        try f.ws.setClassification(itemID: item.id, to: nil, by: f.human.id, at: t0)
        XCTAssertNil(f.ws.items[item.id]?.classification)
        expect(.itemNotFound) { _ = try f.ws.setNotes(itemID: UUID(), to: "x", by: f.human.id) }
    }
}
