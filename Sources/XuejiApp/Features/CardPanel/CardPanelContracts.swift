import Foundation
import XuejiCore

struct CardPanelOption: Identifiable, Hashable {
    let id: String
    let label: String
}

struct CardPanelField: Identifiable {
    let key: String
    let label: String
    let kind: FieldKind
    let isRequired: Bool
    let value: FieldValue?
    /// The choices of a select field.
    let options: [CardPanelOption]
    /// The cards a relation field can point at (the id is the card's id).
    let candidates: [CardPanelOption]
    var id: String { key }
}

struct CardPanelLinkedCard: Identifiable {
    let id: UUID
    let title: String
    let typeName: String
    let symbol: String
}

struct CardPanelComment: Identifiable {
    let id: UUID
    let author: String
    let text: String
    let date: Date
}

struct CardPanelHistoryLine: Identifiable {
    let id: UUID
    let text: String
    let date: Date
}

/// Where a card came from: who made it (a person or an agent), and when.
struct CardPanelOrigin {
    let isAgent: Bool
    let name: String
    let role: String
    /// The human an agent works for.
    let ownerName: String?
    let createdAt: Date
    /// The PDF the card was imported from, if it was.
    let importedFrom: String?
    /// Who approved an agent's proposal, and when.
    let approvedByName: String?
    let approvedAt: Date?
}

/// Everything the panel shows about the focused card.
struct CardPanelContent {
    let itemID: UUID
    let typeName: String
    let typeSymbol: String
    let title: String
    let notes: String
    /// Text written by an agent; read-only.
    let agentDetails: String
    let stage: Stage
    let dueDay: CalendarDay?
    let showsClassification: Bool
    let classification: Classification?
    let showsLink: Bool
    let link: String
    /// The link is a PDF kept on this Mac (shown as a Read button, not as an address).
    let linkIsFile: Bool
    let origin: CardPanelOrigin
    let assigneeName: String?
    let fields: [CardPanelField]
    /// Cards that point at this one through a relation (for example the statements of a source).
    let linkedCards: [CardPanelLinkedCard]
    let comments: [CardPanelComment]
    let history: [CardPanelHistoryLine]
}

/// What the card panel may read.
protocol ICardPanelView {
    var content: CardPanelContent? { get }
}

/// What the card panel may trigger. Every action names its card, so a draft that is saved while the
/// selection changes still lands on the right card.
protocol ICardPanelController {
    func rename(itemID: UUID, title: String)
    func setNotes(itemID: UUID, text: String)
    func setStage(itemID: UUID, stage: Stage)
    func setDue(itemID: UUID, day: CalendarDay?)
    func setClassification(itemID: UUID, classification: Classification?)
    func setLink(itemID: UUID, text: String)
    /// Reads the source's PDF in the app.
    func read(itemID: UUID)
    func revealFile(itemID: UUID)
    /// For text, long text, number and link fields; an empty text clears the field.
    func setFieldText(itemID: UUID, key: String, text: String)
    /// For date, checkbox, choice and relation fields; `nil` clears the field.
    func setFieldValue(itemID: UUID, key: String, value: FieldValue?)
    func addComment(itemID: UUID, text: String)
    func focus(itemID: UUID)
}

typealias ICardPanelViewModel = ICardPanelView & ICardPanelController
