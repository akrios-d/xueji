import Foundation

public enum MemberKind: String, Codable, Sendable { case human, agent }

/// Fixed kanban stages (spec RF-04).
public enum Stage: String, Codable, CaseIterable, Sendable { case toRead, reading, inReview, done }

public enum Approval: String, Codable, Sendable { case pending, approved, rejected }

/// The built-in behaviour of an item type. User-created types are `.custom` and follow no special rules.
public enum ItemKind: String, Codable, Sendable { case researchRequest, source, note, statement, custom }

public enum Classification: String, Codable, Sendable { case essential, complementary, secondary }

public enum ReviewResult: String, Codable, Sendable { case approved, changesRequested }

public enum EventKind: String, Codable, Sendable {
    case created, approved, rejected, moved, claimed, completed
    case reviewRequested, reviewResolved, escalated, commented, rescheduled, edited
}

public struct Member: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var kind: MemberKind
    public var role: String
    /// Human owner. Required for agents, nil for humans.
    public var ownerID: UUID?
    public var isActive: Bool

    public init(id: UUID = UUID(), name: String, kind: MemberKind, role: String, ownerID: UUID? = nil, isActive: Bool = true) {
        self.id = id
        self.name = name
        self.kind = kind
        self.role = role
        self.ownerID = ownerID
        self.isActive = isActive
    }
}

public struct Track: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var details: String
    public var isArchived: Bool

    public init(id: UUID = UUID(), name: String, details: String = "", isArchived: Bool = false) {
        self.id = id
        self.name = name
        self.details = details
        self.isArchived = isArchived
    }
}

public struct Item: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let trackID: UUID
    public var kind: ItemKind
    /// The item type (built-in or user-created) that defines this item's extra fields.
    public let typeID: UUID
    public var title: String
    public var details: String
    public var stage: Stage
    public var approval: Approval
    public var assigneeID: UUID?
    public let creatorID: UUID
    public var url: URL?
    public var classification: Classification?
    public var linkVerifiedAt: Date?
    /// Set when review rounds are exhausted and a human must step in.
    public var needsHuman: Bool
    /// Optional deadline; a calendar day, with no time of day.
    public var dueDay: CalendarDay?
    /// Values of the type's extra fields, keyed by `FieldDefinition.key`.
    public var values: [String: FieldValue]
    /// The student's own notes. Agents never write here.
    public var notes: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        trackID: UUID,
        kind: ItemKind,
        typeID: UUID? = nil,
        title: String,
        details: String = "",
        stage: Stage = .toRead,
        approval: Approval,
        assigneeID: UUID? = nil,
        creatorID: UUID,
        url: URL? = nil,
        classification: Classification? = nil,
        linkVerifiedAt: Date? = nil,
        needsHuman: Bool = false,
        dueDay: CalendarDay? = nil,
        values: [String: FieldValue] = [:],
        notes: String = "",
        createdAt: Date
    ) {
        self.id = id
        self.trackID = trackID
        self.kind = kind
        self.typeID = typeID ?? ItemType.builtInID(for: kind) ?? ItemType.noteID
        self.title = title
        self.details = details
        self.stage = stage
        self.approval = approval
        self.assigneeID = assigneeID
        self.creatorID = creatorID
        self.url = url
        self.classification = classification
        self.linkVerifiedAt = linkVerifiedAt
        self.needsHuman = needsHuman
        self.dueDay = dueDay
        self.values = values
        self.notes = notes
        self.createdAt = createdAt
    }
}

public struct ReviewRequest: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let itemID: UUID
    public let requesterID: UUID
    public let reviewerID: UUID
    public var instructions: String
    public let round: Int
    public var result: ReviewResult?
    public var comment: String?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        itemID: UUID,
        requesterID: UUID,
        reviewerID: UUID,
        instructions: String,
        round: Int,
        result: ReviewResult? = nil,
        comment: String? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.itemID = itemID
        self.requesterID = requesterID
        self.reviewerID = reviewerID
        self.instructions = instructions
        self.round = round
        self.result = result
        self.comment = comment
        self.createdAt = createdAt
    }
}

/// Time-limited claim on a research request, so two agents don't take the same one.
public struct Lease: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let agentID: UUID
    public let expiresAt: Date

    public init(requestID: UUID, agentID: UUID, expiresAt: Date) {
        self.requestID = requestID
        self.agentID = agentID
        self.expiresAt = expiresAt
    }

    public func isActive(at date: Date) -> Bool { date < expiresAt }
}

public struct Comment: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let itemID: UUID
    public let authorID: UUID
    public let text: String
    public let createdAt: Date

    public init(id: UUID = UUID(), itemID: UUID, authorID: UUID, text: String, createdAt: Date) {
        self.id = id
        self.itemID = itemID
        self.authorID = authorID
        self.text = text
        self.createdAt = createdAt
    }
}

public struct Event: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let itemID: UUID
    public let actorID: UUID
    public let kind: EventKind
    public let at: Date
    public let detail: String

    public init(id: UUID = UUID(), itemID: UUID, actorID: UUID, kind: EventKind, at: Date, detail: String = "") {
        self.id = id
        self.itemID = itemID
        self.actorID = actorID
        self.kind = kind
        self.at = at
        self.detail = detail
    }
}

public enum ReviewOutcome: Equatable, Sendable {
    case requested(ReviewRequest)
    /// Review rounds exhausted: the item was flagged for a human.
    case escalated
}
