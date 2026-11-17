import Foundation

/// A document the search can look in.
struct SearchDocument: Identifiable, Equatable {
    let id: UUID
    let title: String
    let isOn: Bool
}

/// One place found by the search.
struct SearchHit: Identifiable, Equatable {
    let id = UUID()
    let sourceID: UUID
    let place: TermOccurrence
    /// The word or phrase of the query that matched here.
    let term: String
}

/// How far the reading of the documents has gone.
struct SearchProgress: Equatable {
    var read = 0
    var total = 0
}

/// What the search tab may read.
protocol IEvidenceSearchView {
    var query: String { get }
    /// Every approved source of the project with a PDF, in the order of the table.
    var documents: [SearchDocument] { get }
    var hits: [SearchHit] { get }
    var isSearching: Bool { get }
    /// A search has finished for the current query.
    var searched: Bool { get }
    var hitLimit: Int { get }
    var progress: SearchProgress { get }
}

/// What the search tab may trigger.
protocol IEvidenceSearchController {
    func setQuery(_ value: String)
    func setOn(_ on: Bool, id: UUID)
    func setAll(_ on: Bool)
    /// Looks for the query in the documents that are on.
    func search()
    /// Forgets what belongs to a project that is no longer open.
    func refresh()
    /// Opens the PDF on the page of the hit, with the matched words marked.
    func open(_ hit: SearchHit)
}

typealias IEvidenceSearchViewModel = IEvidenceSearchView & IEvidenceSearchController
