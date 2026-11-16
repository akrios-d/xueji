import Foundation
import XuejiCore

/// What the Reference finder screen may read.
protocol IFinderView {
    var query: String { get }
    var style: CitationStyle { get }
    var isSearching: Bool { get }
    /// False when the Mac has no internet connection; the search is then off.
    var isOnline: Bool { get }
    /// True once a search has finished, so "nothing found" is not shown before the first search.
    var hasSearched: Bool { get }
    var results: [FoundReference] { get }
    /// The result printed in the chosen style.
    func formatted(_ result: FoundReference) -> String
}

/// What the Reference finder screen may trigger.
protocol IFinderController {
    func setQuery(_ text: String)
    func setStyle(_ style: CitationStyle)
    func search()
    func copy(_ result: FoundReference)
    func addToLibrary(_ result: FoundReference)
    func openLink(_ result: FoundReference)
}

typealias IFinderViewModel = IFinderView & IFinderController
