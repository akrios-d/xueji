import AppKit
import Foundation
import Observation
import XuejiCore

@Observable
final class KanbanViewModel: IKanbanView, IKanbanController {
    private let store: AppStore

    private(set) var searchText = ""
    private(set) var filter: KanbanFilter = .all
    private(set) var sort: KanbanSort = .oldest
    private(set) var isPanelShown = false
    private(set) var visibleStage: Stage?

    /// Wired by the composition root: reads a source's PDF in the app.
    var readInApp: (UUID) -> Void = { _ in }

    init(store: AppStore) { self.store = store }

    func read(itemID: UUID) { readInApp(itemID) }

    // MARK: IKanbanView

    var selectedItemID: UUID? { store.focusedItemID }

    var trackName: String { store.workspace.tracks[store.trackID]?.name ?? "" }

    var columns: [KanbanColumn] {
        let board = store.workspace.kanban(trackID: store.trackID)
        return Stage.allCases.filter { visibleStage == nil || $0 == visibleStage }
            .map { KanbanColumn(stage: $0, items: arranged(board[$0] ?? [])) }
    }

    var completedCount: Int {
        store.workspace.kanban(trackID: store.trackID)[.done]?.count ?? 0
    }

    var totalCount: Int {
        store.workspace.kanban(trackID: store.trackID).values.reduce(0) { $0 + $1.count }
    }

    func assigneeName(of item: Item) -> String? {
        item.assigneeID.map { store.name(of: $0) }
    }

    func isAgentProposed(_ item: Item) -> Bool {
        store.workspace.members[item.creatorID]?.kind == .agent
    }

    func dueBadge(for item: Item) -> DueBadge? {
        guard let due = item.dueDay else { return nil }
        // A finished card is never late.
        if item.stage == .done { return DueBadge(text: Self.shortDate(due), tone: .later) }
        let today = store.today
        switch Workspace.bucket(of: due, today: today) {
        case .overdue:
            let days = due.days(until: today)
            return DueBadge(text: days == 1 ? L("due.overdueDay") : Lf("due.overdueDays", days), tone: .overdue)
        case .today:
            return DueBadge(text: L("due.today"), tone: .today)
        case .upcoming:
            let days = today.days(until: due)
            return DueBadge(text: days == 1 ? L("due.tomorrow") : Lf("due.inDays", days), tone: .soon)
        case .later:
            return DueBadge(text: Self.shortDate(due), tone: .later)
        }
    }

    // MARK: IKanbanController

    func move(itemID: UUID, to stage: Stage) {
        store.move(itemID, to: stage)
    }

    func select(itemID: UUID?) {
        store.focus(itemID)
    }

    func moveSelection(_ direction: BoardDirection) {
        let ids = columns.map { $0.items.map(\.id) }
        store.focus(BoardNavigation.neighbor(of: selectedItemID, in: ids, toward: direction))
    }

    func moveSelected(to stage: Stage) {
        guard let id = selectedItemID else { return }
        store.move(id, to: stage)
    }

    func moveSelectedToNextStage() {
        guard let stage = stageOfSelected()?.next else { return }
        moveSelected(to: stage)
    }

    func moveSelectedToPreviousStage() {
        guard let stage = stageOfSelected()?.previous else { return }
        moveSelected(to: stage)
    }

    func openSelectedLink() {
        guard let id = selectedItemID else { return }
        for column in columns {
            if let url = column.items.first(where: { $0.id == id })?.url {
                if url.isFileURL { readInApp(id) } else { NSWorkspace.shared.open(url) }
                return
            }
        }
    }

    var discardNotice: String? {
        store.lastDiscardedID.flatMap { store.workspace.items[$0]?.title }.map { Lf("board.discarded", $0) }
    }

    var undoLabel: String? { store.undoLabel }
    var redoLabel: String? { store.redoLabel }
    func undo() { store.undo() }
    func redo() { store.redo() }

    func undoDiscard() { store.undoDiscard() }
    func dismissDiscardNotice() { store.dismissDiscard() }

    func rename(itemID: UUID, title: String) { store.rename(itemID, title: title) }

    var otherProjects: [ProjectInfo] { store.otherProjects }
    func copy(itemID: UUID, toProject projectID: UUID) { store.copyCard(itemID, toProject: projectID) }

    func discard(itemID: UUID) {
        store.discard(itemID)
    }

    func discardSelected() {
        guard let id = selectedItemID else { return }
        discard(itemID: id)
    }

    func setDue(itemID: UUID, day: CalendarDay?) {
        store.setDue(itemID, day: day)
    }

    func setDue(itemID: UUID, inDays days: Int?) {
        store.setDue(itemID, day: days.map { store.today.adding(days: $0) })
    }

    func setSelectedDue(inDays days: Int?) {
        guard let id = selectedItemID else { return }
        setDue(itemID: id, inDays: days)
    }

    func setSearchText(_ text: String) { searchText = text }
    func setFilter(_ filter: KanbanFilter) { self.filter = filter }
    func setSort(_ sort: KanbanSort) { self.sort = sort }
    func setPanelShown(_ isShown: Bool) { isPanelShown = isShown }
    func setVisibleStage(_ stage: Stage?) { visibleStage = stage }

    // MARK: Private

    private func stageOfSelected() -> Stage? {
        guard let id = selectedItemID else { return nil }
        return columns.first { column in column.items.contains { $0.id == id } }?.stage
    }

    private func arranged(_ items: [Item]) -> [Item] {
        let query = Self.clean(searchText)
        let visible = items.filter { item in
            matchesFilter(item) && (query.isEmpty
                || item.title.localizedCaseInsensitiveContains(query)
                || item.details.localizedCaseInsensitiveContains(query))
        }
        switch sort {
        case .oldest:
            return visible.sorted { $0.createdAt < $1.createdAt }
        case .newest:
            return visible.sorted { $0.createdAt > $1.createdAt }
        case .relevance:
            return visible.sorted { (rank($0), $1.createdAt) < (rank($1), $0.createdAt) }
        case .title:
            return visible.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .due:
            // Earliest deadline first; cards without a deadline go last.
            return visible.sorted { a, b in
                switch (a.dueDay, b.dueDay) {
                case let (x?, y?): return x != y ? x < y : a.createdAt < b.createdAt
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return a.createdAt < b.createdAt
                }
            }
        }
    }

    private func matchesFilter(_ item: Item) -> Bool {
        switch filter {
        case .all: return true
        case .essential: return item.classification == .essential
        case .complementary: return item.classification == .complementary
        case .secondary: return item.classification == .secondary
        case .notes: return item.kind == .note
        case .overdue:
            guard let due = item.dueDay, item.stage != .done else { return false }
            return due < store.today
        }
    }

    /// Essential first, then complementary, secondary, and unclassified items last.
    private func rank(_ item: Item) -> Int {
        switch item.classification {
        case .essential: return 0
        case .complementary: return 1
        case .secondary: return 2
        case nil: return 3
        }
    }

    private static func shortDate(_ day: CalendarDay) -> String {
        day.date().formatted(.dateTime.day().month(.abbreviated).locale(Localization.locale))
    }

    private static func clean(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
