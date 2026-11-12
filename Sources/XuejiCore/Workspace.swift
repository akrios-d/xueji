import Foundation

/// Domain state plus every business rule from the spec. The type has no I/O; it is `Codable` so the app can
/// store it, and the app decides where.
public struct Workspace: Sendable, Codable {
    public static let maxReviewRounds = 3

    public private(set) var members: [UUID: Member] = [:]
    public private(set) var tracks: [UUID: Track] = [:]
    public internal(set) var items: [UUID: Item] = [:]
    public private(set) var reviews: [UUID: ReviewRequest] = [:]
    public private(set) var leases: [UUID: Lease] = [:]
    public private(set) var comments: [Comment] = []
    public private(set) var events: [Event] = []
    public internal(set) var milestones: [UUID: Milestone] = [:]
    /// Built-in item types plus the ones people create.
    public internal(set) var types: [UUID: ItemType] = [:]

    public init() {
        for type in ItemType.builtIns { types[type.id] = type }
    }

    /// After loading a stored workspace: gives the built-in types the fields the current version of the app
    /// defines (a new version may add some), keeping everything the person changed or added.
    public mutating func mergeBuiltInTypes() {
        for builtIn in ItemType.builtIns {
            guard var stored = types[builtIn.id] else {
                types[builtIn.id] = builtIn
                continue
            }
            for field in builtIn.fields where !stored.fields.contains(where: { $0.key == field.key }) {
                stored.fields.append(field)
            }
            types[builtIn.id] = stored
        }
    }

    // MARK: - Members and tracks

    public mutating func addMember(_ member: Member) throws {
        switch member.kind {
        case .agent:
            guard let ownerID = member.ownerID, members[ownerID]?.kind == .human else {
                throw XuejiError.agentRequiresHumanOwner
            }
        case .human:
            break
        }
        members[member.id] = member
    }

    public mutating func addTrack(_ track: Track) {
        tracks[track.id] = track
    }

    public mutating func renameTrack(_ id: UUID, to name: String) throws {
        guard var track = tracks[id] else { throw XuejiError.trackNotFound }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw XuejiError.emptyText }
        track.name = clean
        tracks[id] = track
    }

    /// An archived track keeps all its cards; the app just stops offering it.
    public mutating func setTrackArchived(_ id: UUID, _ archived: Bool) throws {
        guard var track = tracks[id] else { throw XuejiError.trackNotFound }
        track.isArchived = archived
        tracks[id] = track
    }

    // MARK: - Items

    /// Items created by agents are born `pending` and stay off the kanban until a human approves (RF-09).
    /// Creates an item of a built-in type.
    @discardableResult
    public mutating func createItem(
        trackID: UUID,
        kind: ItemKind,
        title: String,
        details: String = "",
        url: URL? = nil,
        classification: Classification? = nil,
        linkVerifiedAt: Date? = nil,
        dueDay: CalendarDay? = nil,
        assigneeID: UUID? = nil,
        by actorID: UUID,
        at now: Date = Date()
    ) throws -> Item {
        guard let typeID = ItemType.builtInID(for: kind) else { throw XuejiError.typeNotFound }
        return try createItem(
            trackID: trackID, typeID: typeID, title: title, details: details, url: url,
            classification: classification, linkVerifiedAt: linkVerifiedAt, dueDay: dueDay,
            assigneeID: assigneeID, by: actorID, at: now
        )
    }

    /// Creates an item of any type. `values` are checked against the type's fields, and required
    /// fields must be present. Agents may only create types that allow it (`agentsMayPropose`).
    @discardableResult
    public mutating func createItem(
        trackID: UUID,
        typeID: UUID,
        title: String,
        details: String = "",
        url: URL? = nil,
        classification: Classification? = nil,
        linkVerifiedAt: Date? = nil,
        dueDay: CalendarDay? = nil,
        assigneeID: UUID? = nil,
        values: [String: FieldValue] = [:],
        by actorID: UUID,
        at now: Date = Date()
    ) throws -> Item {
        let actor = try activeMember(actorID)
        guard tracks[trackID] != nil else { throw XuejiError.trackNotFound }
        let type = try existingType(typeID)
        if actor.kind == .agent, !type.agentsMayPropose { throw XuejiError.notPermitted }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { throw XuejiError.emptyText }
        if type.behavior == .source, !(actor.kind == .human ? Self.isSourceLocation(url) : Self.isWebURL(url)) { throw XuejiError.sourceRequiresValidURL }
        if let assigneeID { _ = try activeMember(assigneeID) }
        // A student may capture a card quickly and fill the required fields later; agents must send them all.
        try validate(values, for: type, trackID: trackID, requireAll: actor.kind == .agent)

        let item = Item(
            trackID: trackID,
            kind: type.behavior,
            typeID: type.id,
            title: cleanTitle,
            details: details,
            approval: actor.kind == .agent ? .pending : .approved,
            assigneeID: assigneeID,
            creatorID: actor.id,
            url: url,
            classification: classification,
            linkVerifiedAt: linkVerifiedAt,
            dueDay: dueDay,
            values: values,
            createdAt: now
        )
        items[item.id] = item
        record(.created, itemID: item.id, actorID: actor.id, at: now)
        return item
    }

    @discardableResult
    public mutating func approve(itemID: UUID, by actorID: UUID, at now: Date = Date()) throws -> Item {
        var item = try pendingItemForHuman(itemID: itemID, actorID: actorID)
        item.approval = .approved
        items[itemID] = item
        record(.approved, itemID: itemID, actorID: actorID, at: now)
        return item
    }

    @discardableResult
    public mutating func reject(itemID: UUID, by actorID: UUID, reason: String = "", at now: Date = Date()) throws -> Item {
        var item = try pendingItemForHuman(itemID: itemID, actorID: actorID)
        item.approval = .rejected
        items[itemID] = item
        record(.rejected, itemID: itemID, actorID: actorID, at: now, detail: reason)
        return item
    }

    /// A human drops an approved card from the board. It is kept as rejected (like a card refused in the Inbox),
    /// not erased, so the history stays.
    @discardableResult
    public mutating func discard(itemID: UUID, by actorID: UUID, at now: Date = Date()) throws -> Item {
        guard try activeMember(actorID).kind == .human else { throw XuejiError.notPermitted }
        var item = try existingItem(itemID)
        guard item.approval == .approved else { throw XuejiError.invalidApprovalState }
        item.approval = .rejected
        items[itemID] = item
        record(.rejected, itemID: itemID, actorID: actorID, at: now, detail: "discarded")
        return item
    }

    /// Brings back a card dropped from the board (undo of `discard`).
    @discardableResult
    public mutating func restore(itemID: UUID, by actorID: UUID, at now: Date = Date()) throws -> Item {
        guard try activeMember(actorID).kind == .human else { throw XuejiError.notPermitted }
        var item = try existingItem(itemID)
        guard item.approval == .rejected else { throw XuejiError.invalidApprovalState }
        item.approval = .approved
        items[itemID] = item
        record(.approved, itemID: itemID, actorID: actorID, at: now, detail: "restored")
        return item
    }

    /// Humans can move any approved item. Agents can only send their own assigned item to review.
    @discardableResult
    public mutating func move(itemID: UUID, to stage: Stage, by actorID: UUID, at now: Date = Date()) throws -> Item {
        let actor = try activeMember(actorID)
        var item = try existingItem(itemID)
        guard item.approval == .approved else { throw XuejiError.itemNotApproved }
        if actor.kind == .agent {
            guard item.assigneeID == actor.id, stage == .inReview else { throw XuejiError.notPermitted }
        }
        item.stage = stage
        items[itemID] = item
        record(.moved, itemID: itemID, actorID: actor.id, at: now, detail: stage.rawValue)
        return item
    }

    // MARK: - Queries

    /// Only approved items appear on the board.
    public func kanban(trackID: UUID) -> [Stage: [Item]] {
        var board: [Stage: [Item]] = [:]
        for stage in Stage.allCases { board[stage] = [] }
        for item in items.values where item.trackID == trackID && item.approval == .approved {
            board[item.stage, default: []].append(item)
        }
        for stage in Stage.allCases {
            board[stage]?.sort { $0.createdAt < $1.createdAt }
        }
        return board
    }

    public func pendingApprovals() -> [Item] {
        items.values.filter { $0.approval == .pending }.sorted { $0.createdAt < $1.createdAt }
    }

    public func itemsNeedingHuman() -> [Item] {
        items.values.filter { $0.needsHuman }.sorted { $0.createdAt < $1.createdAt }
    }

    public func openReviews(for memberID: UUID) -> [ReviewRequest] {
        reviews.values
            .filter { $0.reviewerID == memberID && $0.result == nil }
            .sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: - Research requests (leases)

    /// An agent claims a research request for `ttl` seconds. Expired leases can be taken over.
    @discardableResult
    public mutating func claimRequest(itemID: UUID, by actorID: UUID, ttl: TimeInterval, at now: Date = Date()) throws -> Lease {
        let actor = try activeMember(actorID)
        guard actor.kind == .agent else { throw XuejiError.notPermitted }
        let request = try existingItem(itemID)
        guard request.kind == .researchRequest else { throw XuejiError.notAResearchRequest }
        guard request.approval == .approved else { throw XuejiError.itemNotApproved }
        guard request.stage != .done else { throw XuejiError.requestAlreadyCompleted }
        if let assignee = request.assigneeID, assignee != actor.id {
            throw XuejiError.requestNotAssignedToAgent
        }
        if let current = leases[itemID], current.agentID != actor.id, current.isActive(at: now) {
            throw XuejiError.requestAlreadyClaimed
        }

        let lease = Lease(requestID: itemID, agentID: actor.id, expiresAt: now.addingTimeInterval(ttl))
        leases[itemID] = lease
        record(.claimed, itemID: itemID, actorID: actor.id, at: now)
        return lease
    }

    @discardableResult
    public mutating func completeRequest(itemID: UUID, by actorID: UUID, summary: String, at now: Date = Date()) throws -> Item {
        let actor = try activeMember(actorID)
        guard actor.kind == .agent else { throw XuejiError.notPermitted }
        guard let lease = leases[itemID], lease.agentID == actor.id else { throw XuejiError.leaseNotHeld }
        guard lease.isActive(at: now) else { throw XuejiError.leaseExpired }

        var request = try existingItem(itemID)
        request.stage = .done
        items[itemID] = request
        leases[itemID] = nil
        record(.completed, itemID: itemID, actorID: actor.id, at: now, detail: summary)
        return request
    }

    // MARK: - Reviews

    /// Requests a review and moves the item to `inReview`.
    /// After `maxReviewRounds` rounds the item is flagged for a human instead (RF-17).
    @discardableResult
    public mutating func requestReview(
        itemID: UUID,
        requestedBy requesterID: UUID,
        reviewerID: UUID,
        instructions: String = "",
        at now: Date = Date()
    ) throws -> ReviewOutcome {
        let requester = try activeMember(requesterID)
        let reviewer = try activeMember(reviewerID)
        var item = try existingItem(itemID)
        guard item.approval == .approved else { throw XuejiError.itemNotApproved }
        guard reviewer.id != item.creatorID else { throw XuejiError.reviewerCannotReviewOwnWork }

        let previousRounds = reviews.values.filter { $0.itemID == itemID }.count
        if previousRounds >= Self.maxReviewRounds {
            item.needsHuman = true
            items[itemID] = item
            record(.escalated, itemID: itemID, actorID: requester.id, at: now)
            return .escalated
        }

        let review = ReviewRequest(
            itemID: itemID,
            requesterID: requester.id,
            reviewerID: reviewer.id,
            instructions: instructions,
            round: previousRounds + 1,
            createdAt: now
        )
        reviews[review.id] = review
        item.stage = .inReview
        items[itemID] = item
        record(.reviewRequested, itemID: itemID, actorID: requester.id, at: now, detail: "round \(review.round)")
        return .requested(review)
    }

    @discardableResult
    public mutating func resolveReview(
        reviewID: UUID,
        by actorID: UUID,
        result: ReviewResult,
        comment: String = "",
        at now: Date = Date()
    ) throws -> ReviewRequest {
        let actor = try activeMember(actorID)
        guard var review = reviews[reviewID] else { throw XuejiError.reviewNotFound }
        guard review.reviewerID == actor.id else { throw XuejiError.notTheReviewer }
        guard review.result == nil else { throw XuejiError.reviewAlreadyResolved }

        review.result = result
        review.comment = comment
        reviews[reviewID] = review
        record(.reviewResolved, itemID: review.itemID, actorID: actor.id, at: now, detail: result.rawValue)
        return review
    }

    // MARK: - Comments

    @discardableResult
    public mutating func addComment(itemID: UUID, by actorID: UUID, text: String, at now: Date = Date()) throws -> Comment {
        let actor = try activeMember(actorID)
        _ = try existingItem(itemID)
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw XuejiError.emptyText }

        let comment = Comment(itemID: itemID, authorID: actor.id, text: clean, createdAt: now)
        comments.append(comment)
        record(.commented, itemID: itemID, actorID: actor.id, at: now)
        return comment
    }

    // MARK: - Helpers

    func activeMember(_ id: UUID) throws -> Member {
        guard let member = members[id] else { throw XuejiError.memberNotFound }
        guard member.isActive else { throw XuejiError.memberInactive }
        return member
    }

    func existingItem(_ id: UUID) throws -> Item {
        guard let found = items[id] else { throw XuejiError.itemNotFound }
        return found
    }

    private func pendingItemForHuman(itemID: UUID, actorID: UUID) throws -> Item {
        let actor = try activeMember(actorID)
        guard actor.kind == .human else { throw XuejiError.notPermitted }
        let found = try existingItem(itemID)
        guard found.approval == .pending else { throw XuejiError.invalidApprovalState }
        return found
    }

    mutating func record(_ kind: EventKind, itemID: UUID, actorID: UUID, at date: Date, detail: String = "") {
        events.append(Event(itemID: itemID, actorID: actorID, kind: kind, at: date, detail: detail))
    }

    /// A source points at a web page, or at a PDF the student added from their own computer.
    static func isSourceLocation(_ url: URL?) -> Bool {
        guard let url else { return false }
        return url.isFileURL || isWebURL(url)
    }

    static func isWebURL(_ url: URL?) -> Bool {
        guard let url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        return !(url.host ?? "").isEmpty
    }
}
