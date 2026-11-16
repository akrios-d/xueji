import XCTest
@testable import XuejiCore

private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.firstWeekday = 2
    return calendar
}

/// Wednesday 11 November 2026, noon, UTC.
private let now = Date(timeIntervalSince1970: 1_794_398_400)
private func ago(days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

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

    /// A note the student made, already on the board.
    mutating func note(_ title: String, due: CalendarDay? = nil, at date: Date) throws -> Item {
        try ws.createItem(trackID: track.id, kind: .note, title: title, dueDay: due, by: human.id, at: date)
    }
}

final class ProgressTests: XCTestCase {
    func testWeeksEndWithTheCurrentWeekAndCountFinishedCards() throws {
        var f = try Fixture()
        let a = try f.note("A", at: ago(days: 10))
        let b = try f.note("B", at: ago(days: 10))
        _ = try f.ws.move(itemID: a.id, to: .done, by: f.human.id, at: ago(days: 1))
        _ = try f.ws.move(itemID: b.id, to: .done, by: f.human.id, at: ago(days: 8))
        let stats = f.ws.progress(trackID: f.track.id, now: now, weekCount: 4, calendar: utc)
        XCTAssertEqual(stats.weeks.count, 4)
        XCTAssertEqual(stats.current?.finished, 1)
        XCTAssertEqual(stats.weeks[2].finished, 1)
        XCTAssertEqual(stats.totalFinished, 2)
        XCTAssertEqual(stats.stageCounts[.done], 2)
    }

    func testACardThatLeftDoneIsNotCountedAsFinished() throws {
        var f = try Fixture()
        let a = try f.note("A", at: ago(days: 5))
        _ = try f.ws.move(itemID: a.id, to: .done, by: f.human.id, at: ago(days: 2))
        _ = try f.ws.move(itemID: a.id, to: .reading, by: f.human.id, at: ago(days: 1))
        let stats = f.ws.progress(trackID: f.track.id, now: now, calendar: utc)
        XCTAssertEqual(stats.totalFinished, 0)
        XCTAssertEqual(stats.stageCounts[.reading], 1)
    }

    func testDeadlinesAreSplitIntoOnTimeLateAndOverdue() throws {
        var f = try Fixture()
        let today = CalendarDay(now, calendar: utc)
        let onTime = try f.note("on time", due: today.adding(days: 1, in: utc), at: ago(days: 5))
        let late = try f.note("late", due: today.adding(days: -3, in: utc), at: ago(days: 5))
        _ = try f.note("overdue", due: today.adding(days: -1, in: utc), at: ago(days: 5))
        _ = try f.note("soon", due: today.adding(days: 3, in: utc), at: ago(days: 5))
        _ = try f.note("far", due: today.adding(days: 30, in: utc), at: ago(days: 5))
        _ = try f.ws.move(itemID: onTime.id, to: .done, by: f.human.id, at: ago(days: 1))
        _ = try f.ws.move(itemID: late.id, to: .done, by: f.human.id, at: ago(days: 1))
        let stats = f.ws.progress(trackID: f.track.id, now: now, calendar: utc)
        XCTAssertEqual(stats.finishedOnTime, 1)
        XCTAssertEqual(stats.finishedLate, 1)
        XCTAssertEqual(stats.overdue, 1)
        XCTAssertEqual(stats.dueThisWeek, 1)
    }

    func testDecisionsOnProposalsAreCountedByWhoProposedAndWhen() throws {
        var f = try Fixture()
        let url = URL(string: "https://example.org/paper")!
        let one = try f.ws.createItem(trackID: f.track.id, kind: .source, title: "One", url: url, by: f.agent.id, at: ago(days: 9))
        let two = try f.ws.createItem(trackID: f.track.id, kind: .source, title: "Two", url: url, by: f.agent.id, at: ago(days: 9))
        let three = try f.ws.createItem(trackID: f.track.id, kind: .source, title: "Three", url: url, by: f.agent.id, at: ago(days: 9))
        _ = try f.ws.approve(itemID: one.id, by: f.human.id, at: ago(days: 8))
        _ = try f.ws.reject(itemID: two.id, by: f.human.id, at: ago(days: 1))
        _ = try f.ws.approve(itemID: three.id, by: f.human.id, at: ago(days: 0.5))
        let mine = try f.note("Mine", at: ago(days: 2))
        _ = try f.ws.discard(itemID: mine.id, by: f.human.id, at: ago(days: 1))

        let stats = f.ws.progress(trackID: f.track.id, now: now, calendar: utc)
        XCTAssertEqual(stats.approvedByAgents, 2)
        XCTAssertEqual(stats.rejectedByAgents, 1)
        XCTAssertEqual(stats.approvedOwn + stats.rejectedOwn, 0, "dropping a card from the board is not a decision on a proposal")
        XCTAssertEqual(stats.current?.approvedByAgents, 1)
        XCTAssertEqual(stats.current?.rejectedByAgents, 1)
        XCTAssertEqual(stats.recentDecisions.map(\.title), ["Three", "Two", "One"])
        XCTAssertEqual(stats.lastDecisionAt, ago(days: 0.5))
        XCTAssertEqual(stats.recentDecisions.first?.proposedByAgent, true)
    }

    func testOtherProjectsAreLeftOut() throws {
        var f = try Fixture()
        let other = Track(name: "Other")
        f.ws.addTrack(other)
        let a = try f.ws.createItem(trackID: other.id, kind: .note, title: "Elsewhere", by: f.human.id, at: ago(days: 3))
        _ = try f.ws.move(itemID: a.id, to: .done, by: f.human.id, at: ago(days: 1))
        XCTAssertEqual(f.ws.progress(trackID: f.track.id, now: now, calendar: utc).totalFinished, 0)
        XCTAssertEqual(f.ws.progress(trackID: other.id, now: now, calendar: utc).totalFinished, 1)
    }

    // MARK: Periods

    func testPresetsResolveToWeeksMonthsAndRollingStretches() {
        let week = ProgressPeriod(.thisWeek).interval(now: now, calendar: utc)
        XCTAssertEqual(week.start, Date(timeIntervalSince1970: 1_794_182_400)) // Monday 9 November, 00:00 UTC
        XCTAssertEqual(ProgressPeriod(.lastWeek).interval(now: now, calendar: utc).end, week.start)
        let month = ProgressPeriod(.thisMonth).interval(now: now, calendar: utc)
        XCTAssertEqual(ProgressPeriod(.lastMonth).interval(now: now, calendar: utc).end, month.start)
        let rolling = ProgressPeriod(.last30Days).interval(now: now, calendar: utc)
        XCTAssertEqual(rolling.duration, 30 * 86_400)
    }

    func testPreviousComesRightBeforeTheOtherPeriodAndIsAsLong() {
        let a = ProgressPeriod(.last30Days).interval(now: now, calendar: utc)
        let b = ProgressPeriod(.previous).interval(now: now, calendar: utc, reference: a)
        XCTAssertEqual(b.end, a.start)
        XCTAssertEqual(b.duration, a.duration)
    }

    func testACustomPeriodIncludesBothDaysEvenIfGivenBackwards() {
        let first = Date(timeIntervalSince1970: 1_793_750_400) // 4 November 2026, UTC
        let last = first.addingTimeInterval(2 * 86_400)
        let interval = ProgressPeriod(.custom, from: last, to: first).interval(now: now, calendar: utc)
        XCTAssertEqual(interval.start, first)
        XCTAssertEqual(interval.duration, 3 * 86_400)
    }

    func testTotalsOnlyCountWhatHappenedInsideThePeriod() throws {
        var f = try Fixture()
        let url = URL(string: "https://example.org/paper")!
        let old = try f.ws.createItem(trackID: f.track.id, kind: .source, title: "Old", url: url, by: f.agent.id, at: ago(days: 40))
        let recent = try f.ws.createItem(trackID: f.track.id, kind: .source, title: "Recent", url: url, by: f.agent.id, at: ago(days: 5))
        _ = try f.ws.approve(itemID: old.id, by: f.human.id, at: ago(days: 39))
        _ = try f.ws.reject(itemID: recent.id, by: f.human.id, at: ago(days: 4))
        let done = try f.note("Done", at: ago(days: 3))
        _ = try f.ws.move(itemID: done.id, to: .done, by: f.human.id, at: ago(days: 2))

        let a = ProgressPeriod(.last30Days).interval(now: now, calendar: utc)
        let b = ProgressPeriod(.previous).interval(now: now, calendar: utc, reference: a)
        let inA = f.ws.progressTotals(trackID: f.track.id, in: a, calendar: utc)
        let inB = f.ws.progressTotals(trackID: f.track.id, in: b, calendar: utc)
        XCTAssertEqual(inA.finished, 1)
        XCTAssertEqual(inA.rejectedByAgents, 1)
        XCTAssertEqual(inA.approved, 0)
        XCTAssertEqual(inA.decisions.map(\.title), ["Recent"])
        XCTAssertEqual(inB.approvedByAgents, 1)
        XCTAssertEqual(inB.finished, 0)
        XCTAssertEqual(inB.created, 1)
    }
}
