import Foundation

/// What happened in one calendar week.
public struct ProgressWeek: Equatable, Identifiable, Sendable {
    public var id: Date { start }
    /// The first moment of the week.
    public let start: Date
    /// Cards that were started.
    public var created = 0
    /// Cards that reached the Done stage.
    public var finished = 0
    /// Sources that reached the Done stage.
    public var sourcesFinished = 0
    /// Proposals the student approved or rejected, by who proposed them.
    public var approvedOwn = 0
    public var approvedByAgents = 0
    public var rejectedOwn = 0
    public var rejectedByAgents = 0

    public var approved: Int { approvedOwn + approvedByAgents }
    public var rejected: Int { rejectedOwn + rejectedByAgents }
}

/// One decision on a proposal in the Inbox.
public struct ProgressDecision: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let itemID: UUID
    public let title: String
    public let approved: Bool
    /// True when an agent proposed the card.
    public let proposedByAgent: Bool
    public let at: Date
}

public struct ProgressStats: Equatable, Sendable {
    /// Oldest first; the last one is the current week.
    public var weeks: [ProgressWeek] = []
    /// Approved cards in each stage right now.
    public var stageCounts: [Stage: Int] = [:]
    public var overdue = 0
    /// Due today or in the next six days, not done yet.
    public var dueThisWeek = 0
    /// Done cards that had a deadline: finished on or before it, or after it.
    public var finishedOnTime = 0
    public var finishedLate = 0
    public var totalFinished = 0
    /// Every decision on a proposal, by who proposed it.
    public var approvedOwn = 0
    public var approvedByAgents = 0
    public var rejectedOwn = 0
    public var rejectedByAgents = 0
    public var lastDecisionAt: Date?
    /// The newest decisions first.
    public var recentDecisions: [ProgressDecision] = []

    public var approved: Int { approvedOwn + approvedByAgents }
    public var rejected: Int { rejectedOwn + rejectedByAgents }
    public var current: ProgressWeek? { weeks.last }
}

extension Workspace {
    /// Productivity numbers for one project, read from the history that is already kept
    /// (events, deadlines and who made each card). `weekCount` weeks end with the week of `now`.
    public func progress(
        trackID: UUID, now: Date = Date(), weekCount: Int = 8, recentLimit: Int = 10, calendar: Calendar = .current
    ) -> ProgressStats {
        var stats = ProgressStats()
        let mine = items.values.filter { $0.trackID == trackID }
        let byID = Dictionary(uniqueKeysWithValues: mine.map { ($0.id, $0) })

        // Weeks, oldest first.
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        let starts: [Date] = (0..<max(weekCount, 1)).reversed().compactMap {
            calendar.date(byAdding: .weekOfYear, value: -$0, to: thisWeek)
        }
        var weeks = starts.map { ProgressWeek(start: $0) }
        func index(of date: Date) -> Int? {
            guard let first = starts.first, date >= first else { return nil }
            let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
            return starts.firstIndex(of: start)
        }

        // Where the cards are now, and what is late.
        let today = CalendarDay(now, calendar: calendar)
        for item in mine where item.approval == .approved {
            stats.stageCounts[item.stage, default: 0] += 1
            guard item.stage != .done, let due = item.dueDay else { continue }
            if due < today {
                stats.overdue += 1
            } else if today.days(until: due, in: calendar) <= 6 {
                stats.dueThisWeek += 1
            }
        }

        // The last time each finished card reached Done.
        var finishedAt: [UUID: Date] = [:]
        for event in events where event.kind == .moved && event.detail == Stage.done.rawValue {
            guard let item = byID[event.itemID], item.stage == .done, item.approval == .approved else { continue }
            if let known = finishedAt[event.itemID], known >= event.at { continue }
            finishedAt[event.itemID] = event.at
        }
        for (id, date) in finishedAt {
            stats.totalFinished += 1
            if let due = byID[id]?.dueDay {
                if CalendarDay(date, calendar: calendar) <= due { stats.finishedOnTime += 1 } else { stats.finishedLate += 1 }
            }
            if let slot = index(of: date) {
                weeks[slot].finished += 1
                if byID[id]?.kind == .source { weeks[slot].sourcesFinished += 1 }
            }
        }

        // Cards started, and decisions on proposals.
        var decisions: [ProgressDecision] = []
        for event in events {
            guard let item = byID[event.itemID] else { continue }
            switch event.kind {
            case .created:
                if item.approval != .rejected, let slot = index(of: event.at) { weeks[slot].created += 1 }
            case .approved, .rejected:
                // A card brought back or dropped from the board is not a decision on a proposal.
                if event.detail == "restored" || event.detail == "discarded" { continue }
                let approved = event.kind == .approved
                let byAgent = members[item.creatorID]?.kind == .agent
                switch (approved, byAgent) {
                case (true, false): stats.approvedOwn += 1
                case (true, true): stats.approvedByAgents += 1
                case (false, false): stats.rejectedOwn += 1
                case (false, true): stats.rejectedByAgents += 1
                }
                if let slot = index(of: event.at) {
                    switch (approved, byAgent) {
                    case (true, false): weeks[slot].approvedOwn += 1
                    case (true, true): weeks[slot].approvedByAgents += 1
                    case (false, false): weeks[slot].rejectedOwn += 1
                    case (false, true): weeks[slot].rejectedByAgents += 1
                    }
                }
                decisions.append(ProgressDecision(
                    id: event.id, itemID: item.id, title: item.title, approved: approved, proposedByAgent: byAgent, at: event.at
                ))
            default:
                break
            }
        }
        decisions.sort { $0.at > $1.at }
        stats.lastDecisionAt = decisions.first?.at
        stats.recentDecisions = Array(decisions.prefix(recentLimit))
        stats.weeks = weeks
        return stats
    }
}
