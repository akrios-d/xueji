import AppKit
import Observation
import XuejiCore

@Observable
final class FinderViewModel: IFinderView, IFinderController {
    private let store: AppStore
    private let finder: ReferenceFinder
    @ObservationIgnored private var task: Task<Void, Never>?

    private(set) var query = ""
    private(set) var style: CitationStyle = .official
    private(set) var isSearching = false
    private(set) var hasSearched = false
    private(set) var results: [FoundReference] = []

    private let network: NetworkMonitor

    init(store: AppStore, finder: ReferenceFinder = ReferenceFinder(), network: NetworkMonitor = .shared) {
        self.store = store
        self.finder = finder
        self.network = network
    }

    var isOnline: Bool { network.isOnline }

    // MARK: IFinderView

    func formatted(_ result: FoundReference) -> String {
        Citations.formatted(result.reference, style: style)
    }

    // MARK: IFinderController

    func setQuery(_ text: String) { query = text }

    func setStyle(_ style: CitationStyle) { self.style = style }

    func search() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, network.isOnline else { return }
        task?.cancel()
        isSearching = true
        task = Task { @MainActor [finder, weak self] in
            let found = await finder.find(text)
            guard !Task.isCancelled, let self else { return }
            self.results = found
            self.hasSearched = true
            self.isSearching = false
        }
    }

    func copy(_ result: FoundReference) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(formatted(result), forType: .string)
    }

    func addToLibrary(_ result: FoundReference) {
        guard let url = URL(string: result.url), url.scheme?.hasPrefix("http") == true else {
            store.announce(L("finder.noLink"))
            return
        }
        var values: [String: FieldValue] = [:]
        if !result.authors.isEmpty { values["authors"] = .text(result.authors) }
        if let year = result.year { values["year"] = .number(Double(year)) }
        let venue = result.kind == "book" ? result.publisher : result.venue
        if !venue.isEmpty { values["venue"] = .text(venue) }
        if !result.doi.isEmpty { values["doi"] = .text(result.doi) }
        if store.addCard(typeID: ItemType.sourceID, title: result.title, url: url, values: values) != nil {
            store.announce(Lf("inbox.created", result.title))
        }
    }

    func openLink(_ result: FoundReference) {
        if let url = URL(string: result.url) { NSWorkspace.shared.open(url) }
    }
}
