import AppKit
import Foundation
import Observation
import XuejiCore

@Observable
final class LibraryViewModel: ILibraryView, ILibraryController {
    private let store: AppStore
    private(set) var searchText = ""
    private(set) var filter: LibraryFilter = .all
    private(set) var isChoosingFile = false

    /// Wired by the composition root: opens a PDF in the reader.
    var readInApp: (UUID) -> Void = { _ in }

    init(store: AppStore) { self.store = store }

    // MARK: ILibraryView

    private var allSources: [Item] {
        store.workspace.items.values.filter {
            $0.trackID == store.trackID && $0.kind == .source && $0.approval == .approved
        }
    }

    var totalCount: Int { allSources.count }
    var notice: String? { store.libraryNotice }
    func dismissNotice() { store.dismissLibraryNotice() }
    var selectedItemID: UUID? { store.focusedItemID }

    var sources: [Item] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return allSources
            .filter { item in
                switch filter {
                case .all: return true
                case .pdfs: return isFile(item)
                case .links: return !isFile(item)
                }
            }
            .filter { item in
                query.isEmpty
                    || item.title.localizedCaseInsensitiveContains(query)
                    || item.details.localizedCaseInsensitiveContains(query)
                    || text(item, "authors").localizedCaseInsensitiveContains(query)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func subtitle(of item: Item) -> String {
        var parts: [String] = []
        let authors = text(item, "authors")
        if !authors.isEmpty { parts.append(authors) }
        if case .number(let year)? = item.values["year"] { parts.append(String(Int(year))) }
        let venue = text(item, "venue")
        if !venue.isEmpty { parts.append(venue) }
        if parts.isEmpty {
            parts.append(isFile(item) ? L("library.localPDF") : (item.url?.host ?? ""))
        }
        return parts.joined(separator: " · ")
    }

    func isFile(_ item: Item) -> Bool { item.url?.isFileURL == true }

    // MARK: ILibraryController

    func setSearchText(_ text: String) { searchText = text }
    func setFilter(_ filter: LibraryFilter) { self.filter = filter }
    func select(itemID: UUID?) { store.focus(itemID) }

    func read(itemID: UUID) {
        guard let item = store.workspace.items[itemID] else { return }
        if isFile(item) { readInApp(itemID) } else { open(itemID: itemID) }
    }

    func open(itemID: UUID) {
        guard let url = store.workspace.items[itemID]?.url else { return }
        NSWorkspace.shared.open(url)
    }

    func remove(itemID: UUID) { store.discard(itemID) }

    var otherProjects: [ProjectInfo] { store.otherProjects }
    func copy(itemID: UUID, toProject projectID: UUID) { store.copyCard(itemID, toProject: projectID) }

    func requestAdd() { isChoosingFile = true }
    func setChoosingFile(_ isChoosing: Bool) { isChoosingFile = isChoosing }

    func addPDF(at url: URL) {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
        if let id = store.addReferencePDF(at: url) { store.focus(id) }
    }

    // MARK: Private

    private func text(_ item: Item, _ key: String) -> String {
        if case .text(let value)? = item.values[key] { return value }
        return ""
    }
}
