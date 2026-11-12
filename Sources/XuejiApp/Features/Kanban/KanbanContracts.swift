import Foundation
import XuejiCore

struct KanbanColumn: Identifiable {
    let stage: Stage
    let items: [Item]
    var id: Stage { stage }
}

enum KanbanFilter: String, CaseIterable, Identifiable {
    case all, essential, complementary, secondary, notes, overdue
    var id: String { rawValue }
}

enum KanbanSort: String, CaseIterable, Identifiable {
    case oldest, newest, relevance, title, due
    var id: String { rawValue }
}

/// How a card's deadline is shown: a short text and how urgent it is.
struct DueBadge: Equatable {
    enum Tone { case overdue, today, soon, later }
    let text: String
    let tone: Tone
}

/// What the board screen may read.
protocol IKanbanView {
    var trackName: String { get }
    /// Columns after the search, filter and sort are applied.
    var columns: [KanbanColumn] { get }
    var completedCount: Int { get }
    var totalCount: Int { get }
    var selectedItemID: UUID? { get }
    var searchText: String { get }
    var filter: KanbanFilter { get }
    var sort: KanbanSort { get }
    var isPanelShown: Bool { get }
    /// The other projects, as targets for "Copy to project".
    var otherProjects: [ProjectInfo] { get }
    /// When set, the board shows only this stage.
    var visibleStage: Stage? { get }
    /// "Discarded “…”", while the last discard can still be undone.
    var discardNotice: String? { get }
    /// What undo / redo would act on ("Move card"); nil when there is nothing to do.
    var undoLabel: String? { get }
    var redoLabel: String? { get }
    func assigneeName(of item: Item) -> String?
    func isAgentProposed(_ item: Item) -> Bool
    func dueBadge(for item: Item) -> DueBadge?
}

/// What the board screen may trigger.
protocol IKanbanController {
    func move(itemID: UUID, to stage: Stage)
    func select(itemID: UUID?)
    func moveSelection(_ direction: BoardDirection)
    func moveSelected(to stage: Stage)
    func moveSelectedToNextStage()
    func moveSelectedToPreviousStage()
    func openSelectedLink()
    /// Reads a source whose PDF is on this Mac inside the app.
    func read(itemID: UUID)
    func discard(itemID: UUID)
    func rename(itemID: UUID, title: String)
    func copy(itemID: UUID, toProject projectID: UUID)
    func undo()
    func redo()
    func undoDiscard()
    func dismissDiscardNotice()
    func discardSelected()
    func setDue(itemID: UUID, day: CalendarDay?)
    /// Sets the deadline to today plus `days`; `nil` removes it.
    func setDue(itemID: UUID, inDays days: Int?)
    func setSelectedDue(inDays days: Int?)
    func setSearchText(_ text: String)
    func setFilter(_ filter: KanbanFilter)
    func setSort(_ sort: KanbanSort)
    func setPanelShown(_ isShown: Bool)
    func setVisibleStage(_ stage: Stage?)
}

typealias IKanbanViewModel = IKanbanView & IKanbanController
