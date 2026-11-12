import Foundation
import Observation
import XuejiCore

@Observable
final class InboxViewModel: IInboxView, IInboxController {
    private let store: AppStore
    private(set) var selectedItemID: UUID?
    private(set) var isChoosingFile = false
    /// What the open file chooser is for.
    private var addsToLibrary = false
    private var importKind: ImportKind?

    /// Wired by the composition root: takes the user to the Library after a PDF was added.
    var showLibrary: () -> Void = {}
    var showTriage: () -> Void = {}

    init(store: AppStore) { self.store = store }

    // MARK: IInboxView

    private(set) var searchText = ""
    private(set) var kindFilter: InboxKind = .all
    private(set) var classificationFilter: Classification?
    private(set) var originFilter: String?
    private(set) var sort: InboxSort = .documentOrder

    var totalPending: Int { store.workspace.pendingApprovals().count }

    var isFiltering: Bool {
        !searchText.isEmpty || kindFilter != .all || classificationFilter != nil || originFilter != nil
    }

    var origins: [String] {
        Set(store.workspace.pendingApprovals().compactMap { store.importedFileName(of: $0) }).sorted()
    }

    var pendingApprovals: [Item] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let visible = store.workspace.pendingApprovals().filter { item in
            kindFilter.includes(item.kind)
                && (classificationFilter == nil || item.classification == classificationFilter)
                && (originFilter == nil || store.importedFileName(of: item) == originFilter)
                && (query.isEmpty
                    || item.title.localizedCaseInsensitiveContains(query)
                    || item.details.localizedCaseInsensitiveContains(query))
        }
        func rank(_ item: Item) -> Int {
            switch item.classification {
            case .essential?: return 0
            case .complementary?: return 1
            case .secondary?: return 2
            case nil: return 3
            }
        }
        func order(_ item: Item) -> Int { readingOrder(of: item) ?? Int.max }
        switch sort {
        case .documentOrder: return visible.sorted { $0.createdAt < $1.createdAt }
        case .newest: return visible.sorted { $0.createdAt > $1.createdAt }
        case .readingOrder:
            return visible.sorted { (order($0), $0.createdAt) < (order($1), $1.createdAt) }
        case .classification:
            return visible.sorted { (rank($0), order($0), $0.createdAt) < (rank($1), order($1), $1.createdAt) }
        case .title:
            return visible.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }

    func readingOrder(of item: Item) -> Int? {
        if case .number(let value)? = item.values["readingOrder"] { return Int(value) }
        return nil
    }
    var itemsNeedingHuman: [Item] { store.workspace.itemsNeedingHuman() }
    var notice: String? { store.notice }
    var isEmpty: Bool { totalPending == 0 && itemsNeedingHuman.isEmpty }

    func originLine(of item: Item) -> String {
        let date = item.createdAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Localization.locale))
        if let file = store.importedFileName(of: item) { return Lf("inbox.importedFrom", file, date) }
        return Lf("inbox.proposedByAt", store.name(of: item.creatorID), date)
    }

    // MARK: IInboxController

    func approve(itemID: UUID) { store.approve(itemID) }
    func reject(itemID: UUID) { store.reject(itemID) }

    func select(itemID: UUID?) { selectedItemID = itemID }

    func moveSelection(by offset: Int) {
        let items = pendingApprovals
        guard !items.isEmpty else {
            selectedItemID = nil
            return
        }
        guard let id = selectedItemID, let index = items.firstIndex(where: { $0.id == id }) else {
            selectedItemID = items.first?.id
            return
        }
        selectedItemID = items[min(max(index + offset, 0), items.count - 1)].id
    }

    func requestImport(_ kind: ImportKind?) {
        addsToLibrary = false
        importKind = kind
        isChoosingFile = true
    }

    func requestAddPDF() {
        importKind = nil
        addsToLibrary = true
        isChoosingFile = true
    }

    func setChoosingFile(_ isChoosing: Bool) { isChoosingFile = isChoosing }
    func dismissNotice() { store.dismissNotice() }

    func dropPDF(at url: URL) {
        addsToLibrary = false
        importKind = nil
        importPDF(at: url)
    }

    func importPDF(at url: URL) {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
        if addsToLibrary {
            addsToLibrary = false
            if let id = store.addReferencePDF(at: url) {
                store.focus(id)
                showLibrary()
            }
            return
        }
        let expected = importKind
        importKind = nil
        switch store.importPDF(at: url, expecting: expected) {
        case .table(let result):
            let summary = result.summary
            switch result.kind {
            case .sourceTriage:
                store.announce(Lf("inbox.import.result.triage", summary.sourcesAdded, summary.skipped))
            case .statements:
                store.announce(Lf("inbox.import.result.statements", summary.statementsAdded, summary.sourcesAdded, summary.skipped))
            case .quoteTriage:
                break
            }
            moveSelection(by: 0)
        case .addedToLibrary(let id):
            store.focus(id)
            showLibrary()
        case .triage(let summary):
            store.announce(Lf("inbox.import.result.quoteTriage", summary.documents + summary.linked, summary.quotes, summary.events))
            showTriage()
        case .failed:
            break
        }
    }

    func approveShown() {
        let ids = pendingApprovals.map(\.id)
        store.approve(all: ids)
        store.announce(Lf("inbox.bulk.approved", ids.count))
        selectedItemID = pendingApprovals.first?.id
    }

    func rejectShown() {
        let ids = pendingApprovals.map(\.id)
        store.reject(all: ids)
        store.announce(Lf("inbox.bulk.discarded", ids.count))
        selectedItemID = pendingApprovals.first?.id
    }

    func setSearchText(_ text: String) { searchText = text; keepSelectionVisible() }
    func setKindFilter(_ kind: InboxKind) { kindFilter = kind; keepSelectionVisible() }
    func setClassificationFilter(_ classification: Classification?) { classificationFilter = classification; keepSelectionVisible() }
    func setOriginFilter(_ origin: String?) { originFilter = origin; keepSelectionVisible() }
    func setSort(_ sort: InboxSort) { self.sort = sort }

    var undoLabel: String? { store.undoLabel }
    var redoLabel: String? { store.redoLabel }
    func undo() { store.undo(); keepSelectionVisible() }
    func redo() { store.redo(); keepSelectionVisible() }

    func clearFilters() {
        searchText = ""
        kindFilter = .all
        classificationFilter = nil
        originFilter = nil
        keepSelectionVisible()
    }

    func approveSelected() { decideSelected { store.approve($0) } }
    func rejectSelected() { decideSelected { store.reject($0) } }

    // MARK: Private

    private func keepSelectionVisible() {
        if let id = selectedItemID, pendingApprovals.contains(where: { $0.id == id }) { return }
        selectedItemID = pendingApprovals.first?.id
    }

    /// Applies a decision to the selected item (or the first one), then selects its neighbour.
    private func decideSelected(_ decide: (UUID) -> Void) {
        let items = pendingApprovals
        guard let id = selectedItemID ?? items.first?.id,
              let index = items.firstIndex(where: { $0.id == id }) else { return }
        decide(id)
        let remaining = pendingApprovals
        if remaining.contains(where: { $0.id == id }) { return }
        selectedItemID = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id
    }
}
