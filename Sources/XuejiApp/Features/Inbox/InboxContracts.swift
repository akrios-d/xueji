import Foundation
import XuejiCore

/// The two tables a PDF can be imported as.
enum ImportKind {
    case sourceTriage, statements, evidenceReport
}

/// Which kind of card the Inbox shows.
enum InboxKind: String, CaseIterable, Identifiable {
    case all, source, statement, researchRequest, note, custom
    var id: String { rawValue }

    func includes(_ kind: ItemKind) -> Bool {
        switch self {
        case .all: return true
        case .source: return kind == .source
        case .statement: return kind == .statement
        case .researchRequest: return kind == .researchRequest
        case .note: return kind == .note
        case .custom: return kind == .custom
        }
    }
}

enum InboxSort: String, CaseIterable, Identifiable {
    /// The order the cards were created in: for an import, the order of the document.
    case documentOrder, readingOrder, classification, newest, title
    var id: String { rawValue }
}

/// What the the Inbox screen may read.
protocol IInboxView {
    /// Cards waiting for a decision, after the search, filters and sort are applied.
    var pendingApprovals: [Item] { get }
    /// All cards waiting, whatever the filters.
    var totalPending: Int { get }
    var isFiltering: Bool { get }
    var searchText: String { get }
    var kindFilter: InboxKind { get }
    var classificationFilter: Classification? { get }
    /// Which PDF the cards came from; nil for all.
    var originFilter: String? { get }
    /// The imported files that still have cards waiting.
    var origins: [String] { get }
    var sort: InboxSort { get }
    var undoLabel: String? { get }
    var redoLabel: String? { get }
    /// Position in the PDF's suggested reading order, if the card has one.
    func readingOrder(of item: Item) -> Int?
    var itemsNeedingHuman: [Item] { get }
    var isEmpty: Bool { get }
    var selectedItemID: UUID? { get }
    /// Who made the card and when ("Proposed by Researcher · …", or "Imported from file.pdf · …").
    func originLine(of item: Item) -> String
    /// A confirmation of what just happened (a card created, a PDF imported), until it is dismissed.
    var notice: String? { get }
    /// Whether the file chooser for a PDF import is open.
    var isChoosingFile: Bool { get }
}

/// What the the Inbox screen may trigger.
protocol IInboxController {
    func approve(itemID: UUID)
    func reject(itemID: UUID)
    func select(itemID: UUID?)
    /// Moves the selection up (negative) or down (positive); selects the first item when none is selected.
    func moveSelection(by offset: Int)
    func approveSelected()
    func rejectSelected()
    /// Approves or discards every card the filters show.
    func approveShown()
    func rejectShown()
    func setSearchText(_ text: String)
    func setKindFilter(_ kind: InboxKind)
    func setClassificationFilter(_ classification: Classification?)
    func setOriginFilter(_ origin: String?)
    func setSort(_ sort: InboxSort)
    func clearFilters()
    func undo()
    func redo()
    /// Opens the file chooser to import a PDF as one of the two tables; `nil` lets Xueji detect which one it is.
    func requestImport(_ kind: ImportKind?)
    /// Opens the file chooser to add any PDF to the library as a source for study.
    func requestAddPDF()
    func setChoosingFile(_ isChoosing: Bool)
    /// The file chosen in the chooser (as a table or for the library, whichever was asked for).
    func importPDF(at url: URL)
    /// A PDF dropped on the Inbox: the kind of table is detected.
    func dropPDF(at url: URL)
    func dismissNotice()
}

typealias IInboxViewModel = IInboxView & IInboxController
