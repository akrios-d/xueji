import Foundation

public enum FieldKind: String, Codable, Sendable {
    case text, longText, number, date, url, checkbox, select, multiSelect, relation
}

public struct FieldOption: Codable, Equatable, Identifiable, Sendable {
    /// Stable machine name, unique within the field.
    public let key: String
    /// Built-in options carry an English default; the app translates them. Custom ones are the user's own text.
    public var label: String
    public var id: String { key }

    public init(key: String, label: String) {
        self.key = key
        self.label = label
    }
}

public struct FieldDefinition: Codable, Equatable, Identifiable, Sendable {
    /// Stable machine name, unique within the type; this is what the REST API and stored values use.
    public let key: String
    public var label: String
    public let kind: FieldKind
    public let isRequired: Bool
    /// The choices of a `select` or `multiSelect` field.
    public var options: [FieldOption]
    /// For a `relation` field: the type the target item must have (`nil` accepts any item in the track).
    public let relatedTypeID: UUID?
    public var id: String { key }

    public init(
        key: String,
        label: String,
        kind: FieldKind,
        isRequired: Bool = false,
        options: [FieldOption] = [],
        relatedTypeID: UUID? = nil
    ) {
        self.key = key
        self.label = label
        self.kind = kind
        self.isRequired = isRequired
        self.options = options
        self.relatedTypeID = relatedTypeID
    }
}

public enum FieldValue: Codable, Equatable, Sendable {
    case text(String)
    case number(Double)
    case date(CalendarDay)
    case url(URL)
    case checkbox(Bool)
    /// The key of one option.
    case select(String)
    case multiSelect([String])
    /// The id of another item.
    case relation(UUID)
}

/// Defines what an item holds: a name, an icon and extra fields. Built-in types keep their special
/// rules (a source needs a valid link, a research request has a lease); types people create are plain.
public struct ItemType: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    /// Non-nil only for built-in types.
    public let key: String?
    /// Built-in types carry an English default; the app translates them.
    public var name: String
    /// An SF Symbol name.
    public var symbol: String
    public let behavior: ItemKind
    public var fields: [FieldDefinition]
    /// Whether agents may create items of this type (always pending until a human approves).
    public var agentsMayPropose: Bool

    public var isBuiltIn: Bool { key != nil }

    public init(
        id: UUID = UUID(),
        key: String? = nil,
        name: String,
        symbol: String,
        behavior: ItemKind,
        fields: [FieldDefinition] = [],
        agentsMayPropose: Bool = false
    ) {
        self.id = id
        self.key = key
        self.name = name
        self.symbol = symbol
        self.behavior = behavior
        self.fields = fields
        self.agentsMayPropose = agentsMayPropose
    }
}

// MARK: - Built-in types

extension ItemType {
    public static let noteID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    public static let researchRequestID = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
    public static let sourceID = UUID(uuidString: "00000000-0000-4000-8000-000000000003")!
    public static let statementID = UUID(uuidString: "00000000-0000-4000-8000-000000000004")!

    public static func builtInID(for kind: ItemKind) -> UUID? {
        switch kind {
        case .note: return noteID
        case .researchRequest: return researchRequestID
        case .source: return sourceID
        case .statement: return statementID
        case .custom: return nil
        }
    }

    public static let builtIns: [ItemType] = [note, researchRequest, source, statement]

    public static let note = ItemType(
        id: noteID, key: "note", name: "Note", symbol: "note.text",
        behavior: .note, agentsMayPropose: true
    )

    public static let researchRequest = ItemType(
        id: researchRequestID, key: "researchRequest", name: "Research request", symbol: "magnifyingglass",
        behavior: .researchRequest, agentsMayPropose: true
    )

    /// A reference to read: what the source triage document lists.
    public static let source = ItemType(
        id: sourceID, key: "source", name: "Source", symbol: "doc.text",
        behavior: .source,
        fields: [
            FieldDefinition(key: "authors", label: "Authors", kind: .text),
            FieldDefinition(key: "venue", label: "Venue", kind: .text),
            FieldDefinition(key: "phase", label: "Period", kind: .text),
            FieldDefinition(key: "readingOrder", label: "Reading order", kind: .number),
            FieldDefinition(key: "year", label: "Year", kind: .number),
            FieldDefinition(key: "doi", label: "DOI", kind: .text),
            FieldDefinition(key: "sourceKind", label: "Kind of source", kind: .select, options: [
                FieldOption(key: "journalArticle", label: "Journal article"),
                FieldOption(key: "thinkTankReport", label: "Think-tank report"),
                FieldOption(key: "governmentDocument", label: "Government document"),
                FieldOption(key: "press", label: "Press"),
                FieldOption(key: "poll", label: "Poll"),
                FieldOption(key: "book", label: "Book"),
                FieldOption(key: "webPage", label: "Web page"),
            ]),
            FieldDefinition(key: "readLevel", label: "How much was read", kind: .select, options: [
                FieldOption(key: "abstractOnly", label: "Abstract only"),
                FieldOption(key: "fullText", label: "Full text available"),
                FieldOption(key: "read", label: "Read"),
            ]),
            FieldDefinition(key: "triageNote", label: "Triage note", kind: .longText),
            FieldDefinition(key: "caveats", label: "Caveats", kind: .longText),
            FieldDefinition(key: "supersededBy", label: "Replaced by", kind: .relation, relatedTypeID: sourceID),
        ],
        agentsMayPropose: true
    )

    /// A position someone took, with where to find it: what "who said what, and when" lists.
    public static let statement = ItemType(
        id: statementID, key: "statement", name: "Statement", symbol: "quote.bubble",
        behavior: .statement,
        fields: [
            FieldDefinition(key: "source", label: "Source", kind: .relation, relatedTypeID: sourceID),
            FieldDefinition(key: "statementDate", label: "Date", kind: .date),
            FieldDefinition(key: "dateApproximate", label: "Date is approximate", kind: .checkbox),
            FieldDefinition(key: "phase", label: "Period", kind: .text),
            FieldDefinition(key: "actor", label: "Who", kind: .text, isRequired: true),
            FieldDefinition(key: "actorKind", label: "Kind of actor", kind: .select, options: [
                FieldOption(key: "scholar", label: "Scholar"),
                FieldOption(key: "thinkTank", label: "Think tank"),
                FieldOption(key: "media", label: "Media"),
                FieldOption(key: "citizens", label: "Citizens (polls)"),
                FieldOption(key: "government", label: "Government or Parliament"),
            ]),
            FieldDefinition(key: "position", label: "Position taken", kind: .longText, isRequired: true),
            FieldDefinition(key: "quote", label: "Direct quote", kind: .text),
            FieldDefinition(key: "locator", label: "Where to find it", kind: .text),
            // A missing value means "to verify".
            FieldDefinition(key: "verification", label: "Verification", kind: .select, options: [
                FieldOption(key: "toVerify", label: "To verify"),
                FieldOption(key: "verified", label: "Verified"),
            ]),
        ],
        agentsMayPropose: true
    )
}
