import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers
import XuejiCore

@Observable
final class TriageViewModel: ITriageView, ITriageController {
    private let store: AppStore
    private(set) var counts: [UUID: SourceCount] = [:]
    private(set) var isCounting = false
    private(set) var justCopied = false

    /// PDF texts already read, so a new term does not read the files again.
    @ObservationIgnored private var texts: [UUID: String] = [:]
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var copyToken = 0
    @ObservationIgnored private var shownTrack: UUID?

    /// Wired by the composition root: opens a source in the reader.
    var readInApp: (UUID) -> Void = { _ in }

    init(store: AppStore) { self.store = store }

    private var triage: Triage { store.triage }

    // MARK: Sources

    private var sources: [Item] {
        store.workspace.items.values
            .filter { $0.trackID == store.trackID && $0.kind == .source && $0.approval == .approved }
            .sorted {
                let left = (year(of: $0) ?? Int.max, $0.title.lowercased())
                let right = (year(of: $1) ?? Int.max, $1.title.lowercased())
                return left < right
            }
    }

    private func year(of item: Item) -> Int? {
        if case .number(let value)? = item.values["year"] { return Int(value) }
        return nil
    }

    private func pdfURL(of item: Item) -> URL? {
        guard let url = item.url, url.isFileURL, url.pathExtension.lowercased() == "pdf",
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    // MARK: ITriageView

    var triageList: [TriageInfo] {
        let active = triage.id
        return store.triages.map { item in
            let name = !item.title.isEmpty ? item.title : (item.term.isEmpty ? L("triage.untitled") : "“\(item.term)”")
            return TriageInfo(id: item.id, name: name, isActive: item.id == active)
        }
    }

    var title: String { triage.title }
    var term: String { triage.term }
    var modifier: String { triage.modifier }
    var corpusNote: String { triage.corpusNote }
    var caution: String { triage.caution }
    var findings: String { triage.findings }
    var quotes: [TriageQuote] { triage.quotes }
    var events: [TriageEvent] { triage.events }

    var rows: [TriageSourceRow] {
        let current = triage
        let fixed = current.documents.map { document in
            TriageSourceRow(
                id: document.id, title: document.title, hasPDF: true,
                included: !current.excluded.contains(document.id), date: document.date, usage: document.usage,
                count: SourceCount(words: document.words, term: document.term, modifier: document.modifier, hasText: true),
                isFixed: true
            )
        }
        return fixed + sources.map { item in
            let note = current.sourceNotes[item.id]
            let typed = note?.date ?? ""
            let date = typed.isEmpty ? (year(of: item).map(String.init) ?? "") : typed
            return TriageSourceRow(
                id: item.id, title: item.title, hasPDF: pdfURL(of: item) != nil,
                included: !current.excluded.contains(item.id), date: date, usage: note?.usage ?? "",
                count: counts[item.id]
            )
        }
    }

    var sourceOptions: [TriageSourceOption] {
        triage.documents.map { TriageSourceOption(id: $0.id, title: $0.title) }
            + sources.map { TriageSourceOption(id: $0.id, title: $0.title) }
    }

    func sourceTitle(_ id: UUID?) -> String {
        guard let id else { return "" }
        if let document = triage.documents.first(where: { $0.id == id }) { return document.title }
        return store.workspace.items[id]?.title ?? ""
    }

    var report: [ReportBlock] {
        var titles: [UUID: String] = [:]
        for item in sources { titles[item.id] = item.title }
        for document in triage.documents { titles[document.id] = document.title }
        return TriageReport.blocks(triage: triage, rows: rows, titles: titles)
    }

    // MARK: Counting

    /// Reads the PDFs of the included sources and counts the term. Safe to call whenever something changed.
    func refresh() {
        // Counts of the project just left do not belong here.
        if shownTrack != store.trackID {
            shownTrack = store.trackID
            counts = [:]
            texts = [:]
        }
        let term = triage.term.trimmingCharacters(in: .whitespacesAndNewlines)
        let modifier = triage.modifier
        let excluded = Set(triage.excluded)
        let candidates: [(id: UUID, url: URL)] = sources.compactMap { item in
            guard !excluded.contains(item.id), let url = pdfURL(of: item) else { return nil }
            return (item.id, url)
        }
        let known = texts
        generation += 1
        let token = generation
        isCounting = true
        Task { @MainActor [weak self] in
            let outcome = await Task.detached(priority: .userInitiated) { () -> ([UUID: String], [UUID: SourceCount]) in
                var loaded = known
                var result: [UUID: SourceCount] = [:]
                for candidate in candidates {
                    if loaded[candidate.id] == nil { loaded[candidate.id] = SourceCounter.text(of: candidate.url) }
                    result[candidate.id] = SourceCounter.count(term: term, modifier: modifier, in: loaded[candidate.id] ?? "")
                }
                return (loaded, result)
            }.value
            guard let self, self.generation == token else { return }
            self.texts = outcome.0
            self.counts = outcome.1
            self.isCounting = false
        }
    }

    /// Counts again a moment after the student stops typing.
    private func refreshSoon() {
        generation += 1
        let token = generation
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, self.generation == token else { return }
            self.refresh()
        }
    }

    // MARK: ITriageController

    func selectTriage(id: UUID) {
        store.selectTriage(id)
        refresh()
    }

    func addTriage() {
        store.addTriage()
        refresh()
    }

    func deleteCurrentTriage() {
        store.deleteTriage(store.triage.id)
        refresh()
    }

    func setTitle(_ value: String) { store.updateTriage { $0.title = value } }
    func setCorpusNote(_ value: String) { store.updateTriage { $0.corpusNote = value } }
    func setCaution(_ value: String) { store.updateTriage { $0.caution = value } }
    func setFindings(_ value: String) { store.updateTriage { $0.findings = value } }

    func setTerm(_ value: String) {
        store.updateTriage { $0.term = value }
        refreshSoon()
    }

    func setModifier(_ value: String) {
        store.updateTriage { $0.modifier = value }
        refreshSoon()
    }

    func setIncluded(_ included: Bool, sourceID: UUID) {
        store.updateTriage { triage in
            triage.excluded.removeAll { $0 == sourceID }
            if !included { triage.excluded.append(sourceID) }
        }
        refresh()
    }

    func setDate(_ value: String, sourceID: UUID) {
        store.updateTriage { triage in
            if let index = triage.documents.firstIndex(where: { $0.id == sourceID }) {
                triage.documents[index].date = value
            } else {
                triage.sourceNotes[sourceID, default: TriageSourceNote()].date = value
            }
        }
    }

    func setUsage(_ value: String, sourceID: UUID) {
        store.updateTriage { triage in
            if let index = triage.documents.firstIndex(where: { $0.id == sourceID }) {
                triage.documents[index].usage = value
            } else {
                triage.sourceNotes[sourceID, default: TriageSourceNote()].usage = value
            }
        }
    }

    func deleteDocument(id: UUID) {
        store.updateTriage { triage in
            triage.documents.removeAll { $0.id == id }
            triage.excluded.removeAll { $0 == id }
        }
    }

    func save(quote: TriageQuote) {
        store.updateTriage { triage in
            if let index = triage.quotes.firstIndex(where: { $0.id == quote.id }) {
                triage.quotes[index] = quote
            } else {
                triage.quotes.append(quote)
            }
        }
    }

    func deleteQuote(id: UUID) { store.updateTriage { $0.quotes.removeAll { $0.id == id } } }

    func moveQuote(id: UUID, by offset: Int) {
        store.updateTriage { triage in
            guard let index = triage.quotes.firstIndex(where: { $0.id == id }),
                  triage.quotes.indices.contains(index + offset) else { return }
            triage.quotes.swapAt(index, index + offset)
        }
    }

    func save(event: TriageEvent) {
        store.updateTriage { triage in
            if let index = triage.events.firstIndex(where: { $0.id == event.id }) {
                triage.events[index] = event
            } else {
                triage.events.append(event)
            }
        }
    }

    func deleteEvent(id: UUID) { store.updateTriage { $0.events.removeAll { $0.id == id } } }

    func moveEvent(id: UUID, by offset: Int) {
        store.updateTriage { triage in
            guard let index = triage.events.firstIndex(where: { $0.id == id }),
                  triage.events.indices.contains(index + offset) else { return }
            triage.events.swapAt(index, index + offset)
        }
    }

    func openSource(id: UUID) { readInApp(id) }

    func copyReport() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ReportBlock.plainText(report), forType: .string)
        justCopied = true
        copyToken += 1
        let token = copyToken
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            if self?.copyToken == token { self?.justCopied = false }
        }
    }

    @MainActor
    func export(format: TriageFormat) {
        let blocks = report
        let name = triage.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format == .word ? DraftFormat.word.contentType : DraftFormat.plainText.contentType]
        let ext = format == .word ? DraftFormat.word.fileExtension : DraftFormat.plainText.fileExtension
        panel.nameFieldStringValue = (name.isEmpty ? L("triage.defaultName") : name) + "." + ext
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let data = format == .word ? DocxWriter.reportData(for: blocks) : Data(ReportBlock.plainText(blocks).utf8)
        do { try data.write(to: url, options: .atomic) } catch { store.announce(L("compile.exportFailed")) }
    }
}
