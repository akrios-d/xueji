import Foundation
import Observation
import PDFKit
import XuejiCore

@Observable
final class EvidenceSearchViewModel: IEvidenceSearchView, IEvidenceSearchController {
    private let store: AppStore
    private(set) var query = ""
    private(set) var hits: [SearchHit] = []
    private(set) var isSearching = false
    private(set) var searched = false
    private(set) var progress = SearchProgress()
    let hitLimit = 300

    /// Documents the student switched off. A new document is on until switched off.
    private var off: Set<UUID> = []
    /// The text of each page already read, so a new query does not read the files again.
    @ObservationIgnored private var pages: [UUID: [String]] = [:]
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var shownTrack: UUID?

    /// Wired by the composition root: opens a source on a page with a phrase marked.
    var readAt: (UUID, Int, String) -> Void = { _, _, _ in }

    init(store: AppStore) { self.store = store }

    // MARK: Documents

    private var sources: [(id: UUID, title: String, url: URL)] {
        store.workspace.items.values
            .filter { $0.trackID == store.trackID && $0.kind == .source && $0.approval == .approved }
            .sorted {
                let left = (year(of: $0) ?? Int.max, $0.title.lowercased())
                let right = (year(of: $1) ?? Int.max, $1.title.lowercased())
                return left < right
            }
            .compactMap { item in
                guard let url = item.url, url.isFileURL, url.pathExtension.lowercased() == "pdf",
                      FileManager.default.fileExists(atPath: url.path) else { return nil }
                return (item.id, item.title, url)
            }
    }

    private func year(of item: Item) -> Int? {
        if case .number(let value)? = item.values["year"] { return Int(value) }
        return nil
    }

    var documents: [SearchDocument] {
        sources.map { SearchDocument(id: $0.id, title: $0.title, isOn: !off.contains($0.id)) }
    }

    // MARK: Controller

    func setQuery(_ value: String) {
        query = value
        // A new query is not searched until the student asks, so the old list does not claim to answer it.
        if PassageSearch.terms(value).isEmpty {
            generation += 1
            hits = []
            searched = false
            isSearching = false
        }
    }

    func setOn(_ on: Bool, id: UUID) {
        if on { off.remove(id) } else { off.insert(id) }
        if searched { search() }
    }

    func setAll(_ on: Bool) {
        off = on ? [] : Set(sources.map(\.id))
        if searched { search() }
    }

    func refresh() {
        guard shownTrack != store.trackID else { return }
        shownTrack = store.trackID
        generation += 1
        pages = [:]
        off = []
        hits = []
        searched = false
        isSearching = false
        query = ""
    }

    func open(_ hit: SearchHit) { readAt(hit.sourceID, hit.place.page, hit.term) }

    func search() {
        generation += 1
        let token = generation
        let terms = PassageSearch.terms(query)
        let chosen = sources.filter { !off.contains($0.id) }
        hits = []
        guard !terms.isEmpty, !chosen.isEmpty else {
            isSearching = false
            searched = !terms.isEmpty
            return
        }
        searched = false
        isSearching = true
        progress = SearchProgress(read: 0, total: chosen.count)
        Task { @MainActor [weak self] in
            var found: [SearchHit] = []
            for (index, source) in chosen.enumerated() {
                guard let self, self.generation == token else { return }
                self.progress = SearchProgress(read: index + 1, total: chosen.count)
                guard let text = await self.loadPages(id: source.id, url: source.url, token: token) else { return }
                let room = self.hitLimit - found.count
                for hit in PassageSearch.hits(for: terms, inPages: text, limit: room) {
                    found.append(SearchHit(
                        sourceID: source.id,
                        place: TermOccurrence(
                            page: hit.page, before: hit.before, text: hit.text, after: hit.after,
                            cutBefore: hit.cutBefore, cutAfter: hit.cutAfter
                        ),
                        term: hit.term
                    ))
                }
                self.hits = found
                if found.count >= self.hitLimit { break }
            }
            guard let self, self.generation == token else { return }
            self.isSearching = false
            self.searched = true
        }
    }

    /// The text of every page of a PDF. PDFKit is meant for the main thread, so a few pages are read at a time
    /// with a pause in between, and the screen stays alive. Nil when a newer search took over.
    @MainActor
    private func loadPages(id: UUID, url: URL, token: Int) async -> [String]? {
        if let cached = pages[id] { return cached }
        guard let document = PDFDocument(url: url) else {
            pages[id] = []
            return []
        }
        var result: [String] = []
        result.reserveCapacity(document.pageCount)
        for index in 0..<document.pageCount {
            result.append(document.page(at: index)?.string ?? "")
            if index % 8 == 7 {
                try? await Task.sleep(for: .milliseconds(4))
                if generation != token { return nil }
            }
        }
        pages[id] = result
        return result
    }
}
