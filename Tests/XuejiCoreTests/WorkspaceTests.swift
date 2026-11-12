import XCTest
@testable import XuejiCore

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private let paperURL = URL(string: "https://example.org/paper")!

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

final class WorkspaceTests: XCTestCase {
    private func expect(
        _ expected: XuejiError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () throws -> Void
    ) {
        XCTAssertThrowsError(try body(), file: file, line: line) { error in
            XCTAssertEqual(error as? XuejiError, expected, file: file, line: line)
        }
    }

    // MARK: Approval

    func testAgentItemIsPendingAndHiddenFromKanban() throws {
        var f = try Fixture()
        let item = try f.ws.createItem(trackID: f.track.id, kind: .source, title: "Paper", url: paperURL, classification: .essential, by: f.agent.id, at: t0)

        XCTAssertEqual(item.approval, .pending)
        XCTAssertEqual(f.ws.pendingApprovals().map { $0.id }, [item.id])
        XCTAssertTrue(f.ws.kanban(trackID: f.track.id).values.allSatisfy { $0.isEmpty })
    }

    func testHumanItemIsApprovedAndStartsInToRead() throws {
        var f = try Fixture()
        let item = try f.ws.createItem(trackID: f.track.id, kind: .note, title: "Idea", by: f.human.id, at: t0)

        XCTAssertEqual(item.approval, .approved)
        XCTAssertEqual(f.ws.kanban(trackID: f.track.id)[.toRead]?.map { $0.id }, [item.id])
    }

    func testAgentCannotApproveItem() throws {
        var f = try Fixture()
        let item = try f.ws.createItem(trackID: f.track.id, kind: .note, title: "N", by: f.agent.id, at: t0)

        expect(.notPermitted) { _ = try f.ws.approve(itemID: item.id, by: f.agent.id, at: t0) }
    }

    func testHumanApprovalMakesItemVisible() throws {
        var f = try Fixture()
        let item = try f.ws.createItem(trackID: f.track.id, kind: .note, title: "N", by: f.agent.id, at: t0)
        try f.ws.approve(itemID: item.id, by: f.human.id, at: t0)

        XCTAssertTrue(f.ws.pendingApprovals().isEmpty)
        XCTAssertEqual(f.ws.kanban(trackID: f.track.id)[.toRead]?.map { $0.id }, [item.id])
    }

    func testRejectedItemStaysHiddenAndCannotBeApprovedLater() throws {
        var f = try Fixture()
        let item = try f.ws.createItem(trackID: f.track.id, kind: .note, title: "N", by: f.agent.id, at: t0)
        try f.ws.reject(itemID: item.id, by: f.human.id, reason: "irrelevant", at: t0)

        XCTAssertTrue(f.ws.kanban(trackID: f.track.id).values.allSatisfy { $0.isEmpty })
        expect(.invalidApprovalState) { _ = try f.ws.approve(itemID: item.id, by: f.human.id, at: t0) }
    }

    // MARK: Validation

    func testSourceNeedsAValidWebURL() throws {
        var f = try Fixture()
        let bad: [URL?] = [nil, URL(string: "ftp://example.org/x"), URL(string: "not a url")]
        for url in bad {
            expect(.sourceRequiresValidURL) {
                _ = try f.ws.createItem(trackID: f.track.id, kind: .source, title: "S", url: url, by: f.agent.id, at: t0)
            }
        }
    }

    func testStudentMayAddAPDFFromTheirComputerButAgentsMayNot() throws {
        var f = try Fixture()
        let file = URL(fileURLWithPath: "/Users/me/Library/Xueji/paper.pdf")
        let item = try f.ws.createItem(trackID: f.track.id, kind: .source, title: "Paper", url: file, by: f.human.id, at: t0)
        XCTAssertEqual(item.url, file)
        expect(.sourceRequiresValidURL) {
            _ = try f.ws.createItem(trackID: f.track.id, kind: .source, title: "Paper 2", url: file, by: f.agent.id, at: t0)
        }
    }

    func testEmptyTitleIsRejected() throws {
        var f = try Fixture()
        expect(.emptyText) { _ = try f.ws.createItem(trackID: f.track.id, kind: .note, title: "   ", by: f.human.id, at: t0) }
    }

    func testAgentNeedsAHumanOwner() throws {
        var ws = Workspace()
        let human = Member(name: "Nade", kind: .human, role: "owner")
        try ws.addMember(human)
        let orphan = Member(name: "A", kind: .agent, role: "researcher")
        expect(.agentRequiresHumanOwner) { try ws.addMember(orphan) }

        let agent = Member(name: "B", kind: .agent, role: "researcher", ownerID: human.id)
        try ws.addMember(agent)
        let agentOwned = Member(name: "C", kind: .agent, role: "researcher", ownerID: agent.id)
        expect(.agentRequiresHumanOwner) { try ws.addMember(agentOwned) }
    }

    // MARK: Moving

    func testPendingItemCannotBeMoved() throws {
        var f = try Fixture()
        let item = try f.ws.createItem(trackID: f.track.id, kind: .note, title: "N", by: f.agent.id, at: t0)

        expect(.itemNotApproved) { _ = try f.ws.move(itemID: item.id, to: .reading, by: f.human.id, at: t0) }
    }

    func testAgentMayOnlySendOwnAssignedItemToReview() throws {
        var f = try Fixture()
        let mine = try f.ws.createItem(trackID: f.track.id, kind: .note, title: "Mine", assigneeID: f.agent.id, by: f.human.id, at: t0)
        let other = try f.ws.createItem(trackID: f.track.id, kind: .note, title: "Other", by: f.human.id, at: t0)

        expect(.notPermitted) { _ = try f.ws.move(itemID: mine.id, to: .reading, by: f.agent.id, at: t0) }
        expect(.notPermitted) { _ = try f.ws.move(itemID: other.id, to: .inReview, by: f.agent.id, at: t0) }
        let moved = try f.ws.move(itemID: mine.id, to: .inReview, by: f.agent.id, at: t0)
        XCTAssertEqual(moved.stage, .inReview)
    }

    // MARK: Leases

    func testLeaseBlocksSecondAgentUntilItExpires() throws {
        var f = try Fixture()
        let other = Member(name: "Other", kind: .agent, role: "researcher", ownerID: f.human.id)
        try f.ws.addMember(other)
        let request = try f.ws.createItem(trackID: f.track.id, kind: .researchRequest, title: "Find papers", by: f.human.id, at: t0)
        try f.ws.claimRequest(itemID: request.id, by: f.agent.id, ttl: 60, at: t0)

        expect(.requestAlreadyClaimed) {
            _ = try f.ws.claimRequest(itemID: request.id, by: other.id, ttl: 60, at: t0.addingTimeInterval(10))
        }
        let lease = try f.ws.claimRequest(itemID: request.id, by: other.id, ttl: 60, at: t0.addingTimeInterval(61))
        XCTAssertEqual(lease.agentID, other.id)
    }

    func testCompleteNeedsAnActiveLease() throws {
        var f = try Fixture()
        let request = try f.ws.createItem(trackID: f.track.id, kind: .researchRequest, title: "Search", by: f.human.id, at: t0)

        expect(.leaseNotHeld) { _ = try f.ws.completeRequest(itemID: request.id, by: f.agent.id, summary: "x", at: t0) }

        try f.ws.claimRequest(itemID: request.id, by: f.agent.id, ttl: 60, at: t0)
        expect(.leaseExpired) {
            _ = try f.ws.completeRequest(itemID: request.id, by: f.agent.id, summary: "x", at: t0.addingTimeInterval(61))
        }
    }

    func testCompletingMarksDoneReleasesLeaseAndBlocksNewClaims() throws {
        var f = try Fixture()
        let request = try f.ws.createItem(trackID: f.track.id, kind: .researchRequest, title: "Search", by: f.human.id, at: t0)
        try f.ws.claimRequest(itemID: request.id, by: f.agent.id, ttl: 60, at: t0)
        let done = try f.ws.completeRequest(itemID: request.id, by: f.agent.id, summary: "12 sources", at: t0.addingTimeInterval(30))

        XCTAssertEqual(done.stage, .done)
        XCTAssertNil(f.ws.leases[request.id])
        expect(.requestAlreadyCompleted) {
            _ = try f.ws.claimRequest(itemID: request.id, by: f.agent.id, ttl: 60, at: t0.addingTimeInterval(40))
        }
    }

    func testRequestAssignedToAnotherAgentCannotBeClaimed() throws {
        var f = try Fixture()
        let other = Member(name: "Other", kind: .agent, role: "researcher", ownerID: f.human.id)
        try f.ws.addMember(other)
        let request = try f.ws.createItem(trackID: f.track.id, kind: .researchRequest, title: "Search", assigneeID: f.agent.id, by: f.human.id, at: t0)

        expect(.requestNotAssignedToAgent) { _ = try f.ws.claimRequest(itemID: request.id, by: other.id, ttl: 60, at: t0) }
    }

    func testHumanCannotClaimRequests() throws {
        var f = try Fixture()
        let request = try f.ws.createItem(trackID: f.track.id, kind: .researchRequest, title: "Search", by: f.human.id, at: t0)

        expect(.notPermitted) { _ = try f.ws.claimRequest(itemID: request.id, by: f.human.id, ttl: 60, at: t0) }
    }

    // MARK: Reviews

    func testReviewerCannotReviewOwnWork() throws {
        var f = try Fixture()
        let item = try f.ws.createItem(trackID: f.track.id, kind: .note, title: "N", by: f.agent.id, at: t0)
        try f.ws.approve(itemID: item.id, by: f.human.id, at: t0)

        expect(.reviewerCannotReviewOwnWork) {
            _ = try f.ws.requestReview(itemID: item.id, requestedBy: f.human.id, reviewerID: f.agent.id, at: t0)
        }
    }

    func testRequestingReviewMovesItemToInReview() throws {
        var f = try Fixture()
        let item = try f.ws.createItem(trackID: f.track.id, kind: .note, title: "N", by: f.human.id, at: t0)
        let outcome = try f.ws.requestReview(itemID: item.id, requestedBy: f.human.id, reviewerID: f.agent.id, instructions: "check sources", at: t0)

        guard case .requested(let review) = outcome else { return XCTFail("expected a review request") }
        XCTAssertEqual(review.round, 1)
        XCTAssertEqual(f.ws.items[item.id]?.stage, .inReview)
        XCTAssertEqual(f.ws.openReviews(for: f.agent.id).map { $0.id }, [review.id])
    }

    func testFourthReviewRoundEscalatesToAHuman() throws {
        var f = try Fixture()
        let item = try f.ws.createItem(trackID: f.track.id, kind: .note, title: "N", by: f.human.id, at: t0)

        for round in 1...Workspace.maxReviewRounds {
            let outcome = try f.ws.requestReview(itemID: item.id, requestedBy: f.human.id, reviewerID: f.agent.id, at: t0)
            guard case .requested(let review) = outcome else { return XCTFail("round \(round) should be requested") }
            XCTAssertEqual(review.round, round)
        }

        let fourth = try f.ws.requestReview(itemID: item.id, requestedBy: f.human.id, reviewerID: f.agent.id, at: t0)
        XCTAssertEqual(fourth, .escalated)
        XCTAssertEqual(f.ws.itemsNeedingHuman().map { $0.id }, [item.id])
    }

    func testOnlyTheAssignedReviewerResolvesAndOnlyOnce() throws {
        var f = try Fixture()
        let item = try f.ws.createItem(trackID: f.track.id, kind: .note, title: "N", by: f.human.id, at: t0)
        let outcome = try f.ws.requestReview(itemID: item.id, requestedBy: f.human.id, reviewerID: f.agent.id, at: t0)
        guard case .requested(let review) = outcome else { return XCTFail("expected a review request") }

        expect(.notTheReviewer) { _ = try f.ws.resolveReview(reviewID: review.id, by: f.human.id, result: .approved, at: t0) }
        try f.ws.resolveReview(reviewID: review.id, by: f.agent.id, result: .changesRequested, comment: "missing sources", at: t0)
        expect(.reviewAlreadyResolved) { _ = try f.ws.resolveReview(reviewID: review.id, by: f.agent.id, result: .approved, at: t0) }
        XCTAssertTrue(f.ws.openReviews(for: f.agent.id).isEmpty)
    }

    // MARK: Comments and history

    func testCommentsAreRecordedAndEmptyOnesRejected() throws {
        var f = try Fixture()
        let item = try f.ws.createItem(trackID: f.track.id, kind: .note, title: "N", by: f.human.id, at: t0)

        try f.ws.addComment(itemID: item.id, by: f.agent.id, text: "  found one more source  ", at: t0)
        XCTAssertEqual(f.ws.comments.map { $0.text }, ["found one more source"])
        expect(.emptyText) { _ = try f.ws.addComment(itemID: item.id, by: f.agent.id, text: " ", at: t0) }
    }

    func testEventsRecordWhoDidWhat() throws {
        var f = try Fixture()
        let item = try f.ws.createItem(trackID: f.track.id, kind: .note, title: "N", by: f.agent.id, at: t0)
        try f.ws.approve(itemID: item.id, by: f.human.id, at: t0)

        XCTAssertEqual(f.ws.events.map { $0.kind }, [.created, .approved])
        XCTAssertEqual(f.ws.events.map { $0.actorID }, [f.agent.id, f.human.id])
    }

    func testRenamingAndArchivingATrack() throws {
        var ws = Workspace()
        let track = Track(name: "Thesis")
        ws.addTrack(track)
        try ws.renameTrack(track.id, to: "  Dissertation ")
        XCTAssertEqual(ws.tracks[track.id]?.name, "Dissertation")
        XCTAssertThrowsError(try ws.renameTrack(track.id, to: "  "))
        XCTAssertThrowsError(try ws.renameTrack(UUID(), to: "x"))
        try ws.setTrackArchived(track.id, true)
        XCTAssertEqual(ws.tracks[track.id]?.isArchived, true)
        try ws.setTrackArchived(track.id, false)
        XCTAssertEqual(ws.tracks[track.id]?.isArchived, false)
    }
}
