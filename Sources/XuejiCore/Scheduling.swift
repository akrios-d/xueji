import Foundation

/// A date on its own, not tied to a card (chapter due, meeting with the supervisor, thesis defense).
public struct Milestone: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let trackID: UUID
    public var title: String
    public var day: CalendarDay
    /// Optional card this milestone relates to.
    public var itemID: UUID?
    public let creatorID: UUID
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        trackID: UUID,
        title: String,
        day: CalendarDay,
        itemID: UUID? = nil,
        creatorID: UUID,
        createdAt: Date
    ) {
        self.id = id
        self.trackID = trackID
        self.title = title
        self.day = day
        self.itemID = itemID
        self.creatorID = creatorID
        self.createdAt = createdAt
    }
}

public enum AgendaEntryKind: Sendable { case milestone, itemDue }

/// One line of the calendar: a milestone or a card with a deadline.
public struct AgendaEntry: Identifiable, Equatable, Sendable {
    /// The milestone's id or the card's id.
    public let id: UUID
    public let day: CalendarDay
    public let title: String
    public let kind: AgendaEntryKind
    public let itemID: UUID?
    /// True for a card that is already in the Done stage.
    public let isDone: Bool
}

public enum DueBucket: Sendable { case overdue, today, upcoming, later }

extension Workspace {
    // MARK: - Deadlines

    /// Only humans set deadlines on existing cards. An agent can propose one when it creates a card,
    /// and that card stays off the board and the calendar until a human approves it.
    @discardableResult
    public mutating func setDueDay(itemID: UUID, to day: CalendarDay?, by actorID: UUID, at now: Date = Date()) throws -> Item {
        let actor = try activeMember(actorID)
        guard actor.kind == .human else { throw XuejiError.notPermitted }
        var item = try existingItem(itemID)
        guard item.approval == .approved else { throw XuejiError.itemNotApproved }
        item.dueDay = day
        items[itemID] = item
        let detail = day.map { String(format: "%04d-%02d-%02d", $0.year, $0.month, $0.day) } ?? ""
        record(.rescheduled, itemID: itemID, actorID: actor.id, at: now, detail: detail)
        return item
    }

    // MARK: - Milestones (humans only)

    @discardableResult
    public mutating func addMilestone(
        trackID: UUID,
        title: String,
        day: CalendarDay,
        itemID: UUID? = nil,
        by actorID: UUID,
        at now: Date = Date()
    ) throws -> Milestone {
        let actor = try activeMember(actorID)
        guard actor.kind == .human else { throw XuejiError.notPermitted }
        guard tracks[trackID] != nil else { throw XuejiError.trackNotFound }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { throw XuejiError.emptyText }
        if let itemID {
            let related = try existingItem(itemID)
            guard related.trackID == trackID else { throw XuejiError.itemNotFound }
        }
        let milestone = Milestone(
            trackID: trackID, title: cleanTitle, day: day,
            itemID: itemID, creatorID: actor.id, createdAt: now
        )
        milestones[milestone.id] = milestone
        return milestone
    }

    @discardableResult
    public mutating func rescheduleMilestone(id: UUID, to day: CalendarDay, by actorID: UUID) throws -> Milestone {
        let actor = try activeMember(actorID)
        guard actor.kind == .human else { throw XuejiError.notPermitted }
        guard var milestone = milestones[id] else { throw XuejiError.milestoneNotFound }
        milestone.day = day
        milestones[id] = milestone
        return milestone
    }

    public mutating func removeMilestone(id: UUID, by actorID: UUID) throws {
        let actor = try activeMember(actorID)
        guard actor.kind == .human else { throw XuejiError.notPermitted }
        guard milestones.removeValue(forKey: id) != nil else { throw XuejiError.milestoneNotFound }
    }

    // MARK: - Queries

    /// Milestones and approved cards with a deadline in the range, in calendar order
    /// (earliest day first; on the same day milestones come before cards, then by title).
    public func agenda(
        trackID: UUID,
        from start: CalendarDay,
        through end: CalendarDay
    ) -> [AgendaEntry] {
        var entries: [AgendaEntry] = []
        for milestone in milestones.values where milestone.trackID == trackID {
            guard milestone.day >= start, milestone.day <= end else { continue }
            entries.append(AgendaEntry(
                id: milestone.id, day: milestone.day, title: milestone.title,
                kind: .milestone, itemID: milestone.itemID, isDone: false
            ))
        }
        for item in items.values where item.trackID == trackID && item.approval == .approved {
            guard let due = item.dueDay, due >= start, due <= end else { continue }
            entries.append(AgendaEntry(
                id: item.id, day: due, title: item.title,
                kind: .itemDue, itemID: item.id, isDone: item.stage == .done
            ))
        }
        return entries.sorted(by: Self.agendaOrder)
    }

    /// Cards whose deadline has passed and that are not done yet, oldest deadline first.
    public func overdue(trackID: UUID, today: CalendarDay) -> [AgendaEntry] {
        items.values
            .filter { $0.trackID == trackID && $0.approval == .approved && $0.stage != .done }
            .compactMap { item -> AgendaEntry? in
                guard let due = item.dueDay, due < today else { return nil }
                return AgendaEntry(id: item.id, day: due, title: item.title, kind: .itemDue, itemID: item.id, isDone: false)
            }
            .sorted(by: Self.agendaOrder)
    }

    /// Overdue, today, within the next seven days, or later.
    public static func bucket(of day: CalendarDay, today: CalendarDay, in calendar: Calendar = .current) -> DueBucket {
        if day < today { return .overdue }
        if day == today { return .today }
        return today.days(until: day, in: calendar) <= 7 ? .upcoming : .later
    }

    private static func agendaOrder(_ a: AgendaEntry, _ b: AgendaEntry) -> Bool {
        if a.day != b.day { return a.day < b.day }
        if a.kind != b.kind { return a.kind == .milestone }
        return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
    }
}
