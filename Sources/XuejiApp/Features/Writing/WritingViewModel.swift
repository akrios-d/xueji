import AppKit
import Foundation
import Observation
import XuejiCore

@Observable
final class WritingViewModel: IWritingView, IWritingController {
    private let store: AppStore
    private(set) var selectedID: UUID?
    private(set) var justCopied = false
    private var copyToken = 0
    private(set) var sourceHits: [SourceHit] = []
    private(set) var isSearchingSources = false
    private(set) var searchedPhrase = ""
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var searchToken = 0

    /// Wired by the composition root: shows a card on the board.
    var openCard: (UUID) -> Void = { _ in }
    /// Wired by the composition root: reads a source's PDF at a page (zero-based) with a phrase marked.
    var openSource: (UUID, Int?, String?) -> Void = { _, _, _ in }

    init(store: AppStore) { self.store = store }

    // MARK: IWritingView

    var drafts: [Draft] { store.drafts.sorted { $0.updatedAt > $1.updatedAt } }

    var selectedDraft: Draft? {
        guard let id = selectedID else { return nil }
        return store.drafts.first { $0.id == id }
    }

    func wordCount(of draft: Draft) -> Int {
        draft.text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    func characterCount(of draft: Draft) -> Int {
        draft.text.filter { !$0.isWhitespace && !$0.isNewline }.count
    }

    func linkedCards(of draft: Draft) -> [Item] {
        draft.linkedItemIDs.compactMap { id in
            store.workspace.items[id].flatMap { $0.approval == .approved ? $0 : nil }
        }
    }

    func candidateCards(for draft: Draft, matching query: String) -> [Item] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.workspace.items.values
            .filter { item in
                item.trackID == store.trackID && item.approval == .approved
                    && !draft.linkedItemIDs.contains(item.id)
                    && (text.isEmpty || item.title.localizedCaseInsensitiveContains(text))
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            .prefix(100).map { $0 }
    }

    private func typeName(of item: Item) -> String {
        store.workspace.types[item.typeID]?.name ?? ""
    }

    func detail(of item: Item) -> String {
        guard item.kind == .source else { return typeName(of: item) }
        var parts: [String] = []
        if case .text(let authors)? = item.values["authors"], !authors.isEmpty { parts.append(authors) }
        if case .number(let year)? = item.values["year"] { parts.append(String(Int(year))) }
        return parts.isEmpty ? typeName(of: item) : parts.joined(separator: " · ")
    }

    // MARK: IWritingController

    func newDraft() { selectedID = store.addDraft() }
    func select(draftID: UUID?) {
        if draftID != selectedID { clearSourceSearch() }
        selectedID = draftID
        justCopied = false
    }
    func setTitle(_ title: String, draftID: UUID) { store.updateDraft(draftID, title: title) }
    func setText(_ text: String, draftID: UUID) { store.updateDraft(draftID, text: text) }

    func setBasis(_ text: String, draftID: UUID) { store.updateDraft(draftID, basis: text) }

    func notes(of draft: Draft) -> [String] {
        draft.basis.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    func opensInReader(_ item: Item) -> Bool { item.kind == .source && item.url?.isFileURL == true }

    func addNote(_ text: String, draftID: UUID) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let draft = store.drafts.first(where: { $0.id == draftID }) else { return }
        store.updateDraft(draftID, basis: (notes(of: draft) + [clean]).joined(separator: "\n"))
    }

    func removeNote(at index: Int, draftID: UUID) {
        guard let draft = store.drafts.first(where: { $0.id == draftID }) else { return }
        var list = notes(of: draft)
        guard list.indices.contains(index) else { return }
        list.remove(at: index)
        store.updateDraft(draftID, basis: list.joined(separator: "\n"))
    }

    func link(cardID: UUID, draftID: UUID) {
        guard let draft = store.drafts.first(where: { $0.id == draftID }),
              !draft.linkedItemIDs.contains(cardID) else { return }
        store.updateDraft(draftID, linkedItemIDs: draft.linkedItemIDs + [cardID])
    }

    func unlink(cardID: UUID, draftID: UUID) {
        guard let draft = store.drafts.first(where: { $0.id == draftID }) else { return }
        store.updateDraft(draftID, linkedItemIDs: draft.linkedItemIDs.filter { $0 != cardID })
    }

    func showCard(itemID: UUID) { openCard(itemID) }

    // MARK: Searching the basis

    func searchSources(_ query: String, draftID: UUID) {
        searchTask?.cancel()
        let phrase = TextSearch.normalized(query)
        guard !phrase.isEmpty, let draft = store.drafts.first(where: { $0.id == draftID }) else {
            clearSourceSearch()
            return
        }
        searchToken += 1
        let token = searchToken
        let notes = notes(of: draft)
        let title = L("writing.search.notes")
        let sources = searchableSources(for: draft)
        isSearchingSources = true
        searchTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            if Task.isCancelled { return }
            let work = Task.detached(priority: .userInitiated) {
                SourceSearcher.search(phrase, notes: notes, notesTitle: title, sources: sources)
            }
            let hits = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
            guard let self, !Task.isCancelled, self.searchToken == token else { return }
            self.sourceHits = hits
            self.searchedPhrase = phrase
            self.isSearchingSources = false
        }
    }

    func clearSourceSearch() {
        searchTask?.cancel()
        searchToken += 1
        sourceHits = []
        searchedPhrase = ""
        isSearchingSources = false
    }

    func open(hit: SourceHit) {
        guard let id = hit.itemID, let item = store.workspace.items[id] else { return }
        if opensInReader(item) {
            openSource(id, hit.pageIndex, searchedPhrase)
        } else {
            openCard(id)
        }
    }

    func canCite(_ item: Item) -> Bool { item.kind == .source }

    func copyCitation(cardID: UUID) {
        guard let key = Citations.keys(for: store.references())[cardID] else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Citations.marker(key: key), forType: .string)
        store.announce(L("writing.cite.copied"))
    }

    func insertQuote(hit: SourceHit, draftID: UUID) {
        guard let draft = store.drafts.first(where: { $0.id == draftID }) else { return }
        let key = hit.itemID.flatMap { Citations.keys(for: store.references())[$0] }
        let line: String
        if let key {
            line = "“\(hit.excerpt)” " + Citations.marker(key: key, page: hit.pageLabel)
        } else {
            let page = hit.pageLabel.map { ", p. " + $0 } ?? ""
            line = "“\(hit.excerpt)” (\(hit.sourceTitle)\(page))"
        }
        store.updateDraft(draftID, text: draft.text.isEmpty ? line : draft.text + "\n\n" + line)
    }

    private func searchableSources(for draft: Draft) -> [SearchableSource] {
        linkedCards(of: draft).map { item in
            var texts = [item.title, item.details, item.notes]
            for value in item.values.values {
                if case .text(let text) = value { texts.append(text) }
            }
            let original = opensInReader(item) ? item.url : nil
            let versions = original == nil ? [] : (store.readingVersions[item.id] ?? []).map(\.fileURL)
            return SearchableSource(
                itemID: item.id, title: item.title, texts: texts.filter { !$0.isEmpty },
                original: original, versions: versions
            )
        }
    }

    func copyWithSources(draftID: UUID) {
        guard let draft = store.drafts.first(where: { $0.id == draftID }) else { return }
        let block = basisBlock(for: draft)
        put(draft.text + (block.isEmpty ? "" : "\n\n" + block))
    }

    func copy(draftID: UUID) {
        guard let draft = store.drafts.first(where: { $0.id == draftID }) else { return }
        put(draft.text)
    }

    private func put(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        justCopied = true
        copyToken += 1
        let token = copyToken
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            if self?.copyToken == token { self?.justCopied = false }
        }
    }

    @MainActor
    func export(draftID: UUID, format: DraftFormat) {
        guard let draft = store.drafts.first(where: { $0.id == draftID }) else { return }
        if !DraftExporter.export(draft, basedOn: basisBlock(for: draft), as: format) { store.announce(L("writing.exportFailed")) }
    }

    /// "Based on:" followed by the student's note and one line per linked card (with the link for web sources).
    private func basisBlock(for draft: Draft) -> String {
        var lines: [String] = []
        let note = draft.basis.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { lines.append(note) }
        for item in linkedCards(of: draft) {
            var line = "• " + item.title
            let detail = item.kind == .source ? detail(of: item) : ""
            if !detail.isEmpty, detail != typeName(of: item) { line += " (" + detail + ")" }
            if let url = item.url, !url.isFileURL { line += " — " + url.absoluteString }
            lines.append(line)
        }
        return lines.isEmpty ? "" : L("writing.basis.heading") + "\n" + lines.joined(separator: "\n")
    }

    var deletedDraftTitle: String? {
        store.lastDeletedDraft.map { $0.title.isEmpty ? L("writing.untitled") : $0.title }
    }

    func undoDelete() { selectedID = store.restoreDraft() ?? selectedID }
    func dismissDeleteNotice() { store.forgetDeletedDraft() }

    func delete(draftID: UUID) {
        store.deleteDraft(draftID)
        if selectedID == draftID { selectedID = drafts.first?.id }
    }
}
