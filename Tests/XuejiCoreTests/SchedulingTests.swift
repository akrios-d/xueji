import XCTest
@testable import XuejiCore

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

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

private func day(_ y: Int, _ m: Int, _ d: Int) -> CalendarDay { CalendarDay(year: y, month: m, day: d) }

final class SchedulingTests: XCTestCase {
    // MARK: CalendarDay

    func testAddingDaysCrossesMonthAndYearBoundaries() {
        XCTAssertEqual(day(2026, 12, 30).adding(days: 3, in: utc), day(2027, 1, 2))
        XCTAssertEqual(day(2026, 3, 1).adding(days: -1, in: utc), day(2026, 2, 28))
    }

    func testDaysUntilIsSignedAndStartOfMonthIsTheFirst() {
        XCTAssertEqual(day(2026, 11, 12).days(until: day(2026, 11, 15), in: utc), 3)
        XCTAssertEqual(day(2026, 11, 12).days(until: day(2026, 11, 10), in: utc), -2)
        XCTAssertEqual(day(2026, 11, 12).startOfMonth, day(2026, 11, 1))
    }

    func testDaysAreOrderedByYearMonthThenDay() {
        XCTAssertTrue(day(2026, 12, 31) < day(2027, 1, 1))
        XCTAssertTrue(day(2026, 2, 28) < day(2026, 3, 1))
    }

    func testDayRoundTripsThroughADate() {
        let original = day(2026, 11, 12)
        XCTAssertEqual(CalendarDay(original.date(in: utc), calendar: utc), original)
    }

    // MARK: Deadlines on cards

    func testHumanSetsAndClearsADeadline() throws {
        var f = try Fixture()
        let item = try f.ws.createItem(trackID: f.track.id, kind: .note, title: "Chapter 2", by: f.human.id, at: t0)
        try f.ws.setDueDay(itemID: item.id, to: day(2026, 11, 20), by: f.human.id, at: t0)
        XCTAssertEqual(f.ws.items[item.id]?.dueDay, day(2026, 11, 20))
        try f.ws.setDueDay(itemID: item.id, to: nil, by: f.human.id, at: t0)
        XCTAssertNil(f.ws.items[item.id]?.dueDay)
        XCTAssertEqual(f.ws.events.last?.kind, .rescheduled)
    }

    func testAgentCannotChangeADeadline() throws {
        var f = try Fixture()
        let item = try f.ws.createItem(trackID: f.track.id, kind: .note, title: "N", by: f.human.id, at: t0)
        XCTAssertThrowsError(try f.ws.setDueDay(itemID: item.id, to: day(2026, 11, 20), by: f.agent.id)) {
            XCTAssertEqual($0 as? XuejiError, .notPermitted)
        }
    }

    func testPendingCardCannotBeScheduledUntilApproved() throws {
        var f = try Fixture()
        let item = try f.ws.createItem(trackID: f.track.id, kind: .note, title: "N", by: f.agent.id, at: t0)
        XCTAssertThrowsError(try f.ws.setDueDay(itemID: item.id, to: day(2026, 11, 20), by: f.human.id)) {
            XCTAssertEqual($0 as? XuejiError, .itemNotApproved)
        }
    }

    func testAgentProposedDeadlineStaysOffTheCalendarUntilApproved() throws {
        var f = try Fixture()
        let item = try f.ws.createItem(
            trackID: f.track.id, kind: .note, title: "Proposed", dueDay: day(2026, 11, 20),
            by: f.agent.id, at: t0
        )
        XCTAssertTrue(f.ws.agenda(trackID: f.track.id, from: day(2026, 11, 1), through: day(2026, 11, 30)).isEmpty)
        try f.ws.approve(itemID: item.id, by: f.human.id, at: t0)
        XCTAssertEqual(f.ws.agenda(trackID: f.track.id, from: day(2026, 11, 1), through: day(2026, 11, 30)).map(\.title), ["Proposed"])
    }

    // MARK: Milestones

    func testOnlyHumansManageMilestones() throws {
        var f = try Fixture()
        XCTAssertThrowsError(try f.ws.addMilestone(trackID: f.track.id, title: "Defense", day: day(2027, 5, 1), by: f.agent.id)) {
            XCTAssertEqual($0 as? XuejiError, .notPermitted)
        }
        let milestone = try f.ws.addMilestone(trackID: f.track.id, title: "  Defense  ", day: day(2027, 5, 1), by: f.human.id, at: t0)
        XCTAssertEqual(milestone.title, "Defense")
        XCTAssertThrowsError(try f.ws.removeMilestone(id: milestone.id, by: f.agent.id)) {
            XCTAssertEqual($0 as? XuejiError, .notPermitted)
        }
        try f.ws.removeMilestone(id: milestone.id, by: f.human.id)
        XCTAssertTrue(f.ws.milestones.isEmpty)
        XCTAssertThrowsError(try f.ws.removeMilestone(id: milestone.id, by: f.human.id)) {
            XCTAssertEqual($0 as? XuejiError, .milestoneNotFound)
        }
    }

    func testMilestoneNeedsATitleAndACardFromTheSameTrack() throws {
        var f = try Fixture()
        XCTAssertThrowsError(try f.ws.addMilestone(trackID: f.track.id, title: " ", day: day(2027, 5, 1), by: f.human.id)) {
            XCTAssertEqual($0 as? XuejiError, .emptyText)
        }
        let other = Track(name: "Other")
        f.ws.addTrack(other)
        let foreign = try f.ws.createItem(trackID: other.id, kind: .note, title: "N", by: f.human.id, at: t0)
        XCTAssertThrowsError(try f.ws.addMilestone(trackID: f.track.id, title: "M", day: day(2027, 5, 1), itemID: foreign.id, by: f.human.id)) {
            XCTAssertEqual($0 as? XuejiError, .itemNotFound)
        }
    }

    func testRescheduleMovesAMilestone() throws {
        var f = try Fixture()
        let milestone = try f.ws.addMilestone(trackID: f.track.id, title: "M", day: day(2026, 12, 1), by: f.human.id, at: t0)
        try f.ws.rescheduleMilestone(id: milestone.id, to: day(2026, 12, 5), by: f.human.id)
        XCTAssertEqual(f.ws.milestones[milestone.id]?.day, day(2026, 12, 5))
    }

    // MARK: Agenda and overdue

    func testAgendaIsOrderedAndLimitedToTheRange() throws {
        var f = try Fixture()
        let card = try f.ws.createItem(trackID: f.track.id, kind: .note, title: "Card", by: f.human.id, at: t0)
        try f.ws.setDueDay(itemID: card.id, to: day(2026, 11, 10), by: f.human.id)
        try f.ws.addMilestone(trackID: f.track.id, title: "Meeting", day: day(2026, 11, 10), by: f.human.id, at: t0)
        try f.ws.addMilestone(trackID: f.track.id, title: "Early", day: day(2026, 11, 2), by: f.human.id, at: t0)
        try f.ws.addMilestone(trackID: f.track.id, title: "Outside", day: day(2026, 12, 1), by: f.human.id, at: t0)

        let titles = f.ws.agenda(trackID: f.track.id, from: day(2026, 11, 1), through: day(2026, 11, 30)).map(\.title)
        XCTAssertEqual(titles, ["Early", "Meeting", "Card"])
    }

    func testOverdueSkipsDoneCardsAndFutureDeadlines() throws {
        var f = try Fixture()
        let late = try f.ws.createItem(trackID: f.track.id, kind: .note, title: "Late", by: f.human.id, at: t0)
        let done = try f.ws.createItem(trackID: f.track.id, kind: .note, title: "Done", by: f.human.id, at: t0)
        let future = try f.ws.createItem(trackID: f.track.id, kind: .note, title: "Future", by: f.human.id, at: t0)
        try f.ws.setDueDay(itemID: late.id, to: day(2026, 11, 1), by: f.human.id)
        try f.ws.setDueDay(itemID: done.id, to: day(2026, 11, 1), by: f.human.id)
        try f.ws.setDueDay(itemID: future.id, to: day(2026, 11, 30), by: f.human.id)
        try f.ws.move(itemID: done.id, to: .done, by: f.human.id)

        let overdue = f.ws.overdue(trackID: f.track.id, today: day(2026, 11, 12))
        XCTAssertEqual(overdue.map(\.title), ["Late"])
    }

    func testDoneCardsStayOnTheAgendaMarkedDone() throws {
        var f = try Fixture()
        let card = try f.ws.createItem(trackID: f.track.id, kind: .note, title: "Card", by: f.human.id, at: t0)
        try f.ws.setDueDay(itemID: card.id, to: day(2026, 11, 10), by: f.human.id)
        try f.ws.move(itemID: card.id, to: .done, by: f.human.id)
        let entry = f.ws.agenda(trackID: f.track.id, from: day(2026, 11, 1), through: day(2026, 11, 30)).first
        XCTAssertEqual(entry?.isDone, true)
    }

    func testBuckets() {
        let today = day(2026, 11, 12)
        XCTAssertEqual(Workspace.bucket(of: day(2026, 11, 11), today: today, in: utc), .overdue)
        XCTAssertEqual(Workspace.bucket(of: today, today: today, in: utc), .today)
        XCTAssertEqual(Workspace.bucket(of: day(2026, 11, 19), today: today, in: utc), .upcoming)
        XCTAssertEqual(Workspace.bucket(of: day(2026, 11, 20), today: today, in: utc), .later)
    }
}
