import Foundation

/// A way to choose a stretch of time for the Progress screen.
public enum ProgressPreset: String, CaseIterable, Sendable {
    case thisWeek, lastWeek, thisMonth, lastMonth, last30Days, last90Days, allTime
    /// The stretch right before the other period, as long as that one (for comparing).
    case previous
    case custom
}

public struct ProgressPeriod: Equatable, Sendable {
    public var preset: ProgressPreset
    /// The first and last day of a custom period (both included).
    public var from: Date
    public var to: Date

    public init(_ preset: ProgressPreset, from: Date = Date(), to: Date = Date()) {
        self.preset = preset
        self.from = from
        self.to = to
    }

    /// The period as a stretch of time that starts at `start` and ends before `end`.
    /// `reference` is the period a `.previous` one comes before.
    public func interval(now: Date = Date(), calendar: Calendar = .current, reference: DateInterval? = nil) -> DateInterval {
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        func make(_ start: Date, _ end: Date) -> DateInterval { DateInterval(start: start, end: max(start, end)) }
        switch preset {
        case .thisWeek:
            return calendar.dateInterval(of: .weekOfYear, for: now) ?? make(today, tomorrow)
        case .lastWeek:
            let this = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? today
            let start = calendar.date(byAdding: .weekOfYear, value: -1, to: this) ?? this
            return make(start, this)
        case .thisMonth:
            return calendar.dateInterval(of: .month, for: now) ?? make(today, tomorrow)
        case .lastMonth:
            let this = calendar.dateInterval(of: .month, for: now)?.start ?? today
            let start = calendar.date(byAdding: .month, value: -1, to: this) ?? this
            return make(start, this)
        case .last30Days:
            return make(calendar.date(byAdding: .day, value: -29, to: today) ?? today, tomorrow)
        case .last90Days:
            return make(calendar.date(byAdding: .day, value: -89, to: today) ?? today, tomorrow)
        case .allTime:
            return make(Date(timeIntervalSince1970: 0), tomorrow)
        case .previous:
            guard let reference else { return make(today, today) }
            let length = reference.duration
            return make(reference.start.addingTimeInterval(-length), reference.start)
        case .custom:
            let first = calendar.startOfDay(for: min(from, to))
            let last = calendar.startOfDay(for: max(from, to))
            return make(first, calendar.date(byAdding: .day, value: 1, to: last) ?? last)
        }
    }
}

/// What happened in a stretch of time.
public struct ProgressTotals: Equatable, Sendable {
    public var finished = 0
    public var sourcesFinished = 0
    public var created = 0
    /// Of the cards finished in the period that had a deadline.
    public var finishedOnTime = 0
    public var finishedLate = 0
    public var approvedOwn = 0
    public var approvedByAgents = 0
    public var rejectedOwn = 0
    public var rejectedByAgents = 0
    /// Every decision on a proposal in the period, newest first.
    public var decisions: [ProgressDecision] = []

    public var approved: Int { approvedOwn + approvedByAgents }
    public var rejected: Int { rejectedOwn + rejectedByAgents }
}

extension Workspace {
    /// The numbers for one project in `interval` (its end is not included).
    public func progressTotals(trackID: UUID, in interval: DateInterval, calendar: Calendar = .current) -> ProgressTotals {
        var totals = ProgressTotals()
        let byID = Dictionary(uniqueKeysWithValues: items.values.filter { $0.trackID == trackID }.map { ($0.id, $0) })
        func inside(_ date: Date) -> Bool { date >= interval.start && date < interval.end }

        var finishedAt: [UUID: Date] = [:]
        for event in events where event.kind == .moved && event.detail == Stage.done.rawValue {
            guard let item = byID[event.itemID], item.stage == .done, item.approval == .approved else { continue }
            if let known = finishedAt[event.itemID], known >= event.at { continue }
            finishedAt[event.itemID] = event.at
        }
        for (id, date) in finishedAt where inside(date) {
            guard let item = byID[id] else { continue }
            totals.finished += 1
            if item.kind == .source { totals.sourcesFinished += 1 }
            if let due = item.dueDay {
                if CalendarDay(date, calendar: calendar) <= due { totals.finishedOnTime += 1 } else { totals.finishedLate += 1 }
            }
        }

        for event in events where inside(event.at) {
            guard let item = byID[event.itemID] else { continue }
            switch event.kind {
            case .created:
                if item.approval != .rejected { totals.created += 1 }
            case .approved, .rejected:
                if event.detail == "restored" || event.detail == "discarded" { continue }
                let approved = event.kind == .approved
                let byAgent = members[item.creatorID]?.kind == .agent
                switch (approved, byAgent) {
                case (true, false): totals.approvedOwn += 1
                case (true, true): totals.approvedByAgents += 1
                case (false, false): totals.rejectedOwn += 1
                case (false, true): totals.rejectedByAgents += 1
                }
                totals.decisions.append(ProgressDecision(
                    id: event.id, itemID: item.id, title: item.title, approved: approved, proposedByAgent: byAgent, at: event.at
                ))
            default:
                break
            }
        }
        totals.decisions.sort { $0.at > $1.at }
        return totals
    }
}
