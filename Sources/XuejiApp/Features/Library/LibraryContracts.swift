import Foundation
import XuejiCore

enum LibraryFilter: String, CaseIterable, Identifiable {
    case all, pdfs, links
    var id: String { rawValue }
}

/// What the library screen may read.
protocol ILibraryView {
    /// Approved sources, newest first, after the search and filter.
    var sources: [Item] { get }
    var totalCount: Int { get }
    /// The other projects, as targets for "Copy to project".
    var otherProjects: [ProjectInfo] { get }
    var searchText: String { get }
    var filter: LibraryFilter { get }
    var selectedItemID: UUID? { get }
    var isChoosingFile: Bool { get }
    /// A message to show above the list (for example, a PDF that was added here on its own).
    var notice: String? { get }
    /// "Authors · year · venue", or where the file or link is.
    func subtitle(of item: Item) -> String
    /// A PDF kept on this Mac (as opposed to a web link).
    func isFile(_ item: Item) -> Bool
}

/// What the library screen may trigger.
protocol ILibraryController {
    func setSearchText(_ text: String)
    func copy(itemID: UUID, toProject projectID: UUID)
    func setFilter(_ filter: LibraryFilter)
    func select(itemID: UUID?)
    /// Opens the source in the app: a PDF in the reader, a link in the browser.
    func read(itemID: UUID)
    /// Opens it outside the app (Preview for a PDF, the browser for a link).
    func open(itemID: UUID)
    func remove(itemID: UUID)
    func requestAdd()
    func dismissNotice()
    func setChoosingFile(_ isChoosing: Bool)
    func addPDF(at url: URL)
}

typealias ILibraryViewModel = ILibraryView & ILibraryController
