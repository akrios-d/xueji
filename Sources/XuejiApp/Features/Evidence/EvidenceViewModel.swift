import AppKit
import Foundation
import Observation
import PDFKit
import UniformTypeIdentifiers
import XuejiCore

@Observable
final class EvidenceViewModel: IEvidenceView, IEvidenceController {
    private let store: AppStore
    private(set) var counts: [UUID: SourceCount] = [:]
    private(set) var isCounting = false
    private(set) var justCopied = false
    /// Where the term appears, by source. Filled when a row is opened and cleared when the term changes.
    private(set) var scans: [UUID: OccurrenceScan] = [:]
    @ObservationIgnored private var scanning: Set<UUID> = []
    private var foundGeneration = 0
    var scanGeneration: Int { foundGeneration }

    /// PDF texts already read, so a new term does not read the files again.
    @ObservationIgnored private var texts: [UUID: String] = [:]
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var lastScanKey = ""
    @ObservationIgnored private var copyToken = 0
    @ObservationIgnored private var shownTrack: UUID?

    /// Wired by the composition root: opens a source in the reader.
    var readInApp: (UUID) -> Void = { _ in }
    /// Wired by the composition root: opens a source on a page with a phrase marked.
    var readAt: (UUID, Int, String) -> Void = { _, _, _ in }

    init(store: AppStore) { self.store = store }

    private var evidence: EvidenceSet { store.evidence }

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

    // MARK: IEvidenceView

    var evidenceList: [EvidenceInfo] {
        let active = evidence.id
        return store.triages.map { item in
            let name = !item.title.isEmpty ? item.title : (item.term.isEmpty ? L("evidence.untitled") : "“\(item.term)”")
            return EvidenceInfo(id: item.id, name: name, isActive: item.id == active)
        }
    }

    var title: String { evidence.title }
    var term: String { evidence.term }
    var modifier: String { evidence.modifier }
    var corpusNote: String { evidence.corpusNote }
    var caution: String { evidence.caution }
    var findings: String { evidence.findings }
    var quotes: [EvidenceQuote] { evidence.quotes }
    var events: [EvidenceEvent] { evidence.sortedEvents }
    var eras: [EvidenceEra] { evidence.sortedEras }
    var eraOutline: [EraNode] { evidence.outline() }
    var masterTitle: String { evidence.masterName.isEmpty ? L("evidence.timeline.master") : evidence.masterName }
    func events(in era: UUID?) -> [EvidenceEvent] { evidence.events(in: era) }

    var rows: [EvidenceSourceRow] {
        let current = evidence
        let fixed = current.documents.map { document in
            EvidenceSourceRow(
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
            return EvidenceSourceRow(
                id: item.id, title: item.title, hasPDF: pdfURL(of: item) != nil,
                included: !current.excluded.contains(item.id), date: date, usage: note?.usage ?? "",
                count: counts[item.id]
            )
        }
    }

    var sourceOptions: [EvidenceSourceOption] {
        evidence.documents.map { EvidenceSourceOption(id: $0.id, title: $0.title) }
            + sources.map { EvidenceSourceOption(id: $0.id, title: $0.title) }
    }

    func sourceTitle(_ id: UUID?) -> String {
        guard let id else { return "" }
        if let document = evidence.documents.first(where: { $0.id == id }) { return document.title }
        return store.workspace.items[id]?.title ?? ""
    }

    var report: [ReportBlock] {
        var titles: [UUID: String] = [:]
        for item in sources { titles[item.id] = item.title }
        for document in evidence.documents { titles[document.id] = document.title }
        return EvidenceReport.blocks(evidence: evidence, rows: rows, titles: titles)
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
        let term = evidence.term.trimmingCharacters(in: .whitespacesAndNewlines)
        let modifier = evidence.modifier
        // The places stay while the term does not change, so coming back to the screen costs nothing.
        let key = shownTrack.map { $0.uuidString } ?? ""
        let scanKey = key + "|" + term + "|" + modifier
        if scanKey != lastScanKey {
            lastScanKey = scanKey
            scans = [:]
            scanning = []
            foundGeneration += 1
        }
        let excluded = Set(evidence.excluded)
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

    // MARK: IEvidenceController

    func selectEvidence(id: UUID) {
        store.selectEvidence(id)
        refresh()
    }

    func addEvidence() {
        store.addEvidence()
        refresh()
    }

    func deleteCurrentEvidence() {
        store.deleteEvidence(store.evidence.id)
        refresh()
    }

    func setTitle(_ value: String) { store.updateEvidence { $0.title = value } }
    func setCorpusNote(_ value: String) { store.updateEvidence { $0.corpusNote = value } }
    func setCaution(_ value: String) { store.updateEvidence { $0.caution = value } }
    func setFindings(_ value: String) { store.updateEvidence { $0.findings = value } }

    func setTerm(_ value: String) {
        store.updateEvidence { $0.term = value }
        refreshSoon()
    }

    func setModifier(_ value: String) {
        store.updateEvidence { $0.modifier = value }
        refreshSoon()
    }

    func setIncluded(_ included: Bool, sourceID: UUID) {
        store.updateEvidence { evidence in
            evidence.excluded.removeAll { $0 == sourceID }
            if !included { evidence.excluded.append(sourceID) }
        }
        refresh()
    }

    func setDate(_ value: String, sourceID: UUID) {
        store.updateEvidence { evidence in
            if let index = evidence.documents.firstIndex(where: { $0.id == sourceID }) {
                evidence.documents[index].date = value
            } else {
                evidence.sourceNotes[sourceID, default: EvidenceSourceNote()].date = value
            }
        }
    }

    func setUsage(_ value: String, sourceID: UUID) {
        store.updateEvidence { evidence in
            if let index = evidence.documents.firstIndex(where: { $0.id == sourceID }) {
                evidence.documents[index].usage = value
            } else {
                evidence.sourceNotes[sourceID, default: EvidenceSourceNote()].usage = value
            }
        }
    }

    func deleteDocument(id: UUID) {
        store.updateEvidence { evidence in
            evidence.documents.removeAll { $0.id == id }
            evidence.excluded.removeAll { $0 == id }
        }
    }

    func savedQuote(sourceID: UUID?, text: String, excluding id: UUID?) -> EvidenceQuote? {
        func normalized(_ value: String) -> String {
            value.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        let wanted = normalized(text)
        guard !wanted.isEmpty else { return nil }
        return evidence.quotes.first { quote in
            guard quote.id != id, quote.sourceID == sourceID else { return false }
            let have = normalized(quote.text)
            if have == wanted { return true }
            // One passage inside the other (a longer or shorter cut of the same words).
            return min(have.count, wanted.count) >= 40 && (have.contains(wanted) || wanted.contains(have))
        }
    }

    func save(quote: EvidenceQuote) {
        // The same passage of a document is never saved twice.
        if !evidence.quotes.contains(where: { $0.id == quote.id }),
           savedQuote(sourceID: quote.sourceID, text: quote.text, excluding: nil) != nil { return }
        store.updateEvidence { evidence in
            if let index = evidence.quotes.firstIndex(where: { $0.id == quote.id }) {
                evidence.quotes[index] = quote
            } else {
                evidence.quotes.append(quote)
            }
        }
    }

    func deleteQuote(id: UUID) {
        store.updateEvidence { evidence in
            evidence.quotes.removeAll { $0.id == id }
            for index in evidence.events.indices where evidence.events[index].quoteID == id {
                evidence.events[index].quoteID = nil
            }
            for index in evidence.eras.indices { evidence.eras[index].quoteIDs.removeAll { $0 == id } }
        }
    }

    func moveQuote(id: UUID, by offset: Int) {
        store.updateEvidence { evidence in
            guard let index = evidence.quotes.firstIndex(where: { $0.id == id }),
                  evidence.quotes.indices.contains(index + offset) else { return }
            evidence.quotes.swapAt(index, index + offset)
        }
    }

    func importReport(at url: URL) {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
        if case .evidence(let summary) = store.importPDF(at: url, expecting: .evidenceReport) {
            store.announce(Lf("evidence.import.result", summary.documents + summary.linked, summary.quotes, summary.periods, summary.events))
            refresh()
        }
    }

    @discardableResult
    func generateTimeline() -> Int {
        let current = evidence
        let onTimeline = Set(current.events.compactMap(\.sourceID))
        let outline = current.outline()
        var created: [EvidenceEvent] = []
        for row in rows where row.included && !onTimeline.contains(row.id) {
            guard let when = EvidenceDate.parse(row.date) else { continue }
            let quotes = current.quotes.filter { $0.sourceID == row.id }
            // The innermost period that holds the date; the master when none does.
            let era = outline.compactMap { node -> (id: UUID, depth: Int)? in
                guard let era = node.era, when.start >= era.from.start, when.end <= era.until.end else { return nil }
                return (era.id, node.depth)
            }.max { $0.depth < $1.depth }
            created.append(EvidenceEvent(
                date: when.label, when: when, sourceID: row.id, quoteID: quotes.count == 1 ? quotes[0].id : nil,
                eraID: era?.id, event: row.title
            ))
        }
        guard !created.isEmpty else {
            store.announce(L("evidence.timeline.generatedNone"))
            return 0
        }
        store.updateEvidence { $0.events.append(contentsOf: created) }
        store.announce(Lf("evidence.timeline.generated", created.count))
        return created.count
    }

    func save(event: EvidenceEvent) {
        store.updateEvidence { evidence in
            if let index = evidence.events.firstIndex(where: { $0.id == event.id }) {
                evidence.events[index] = event
            } else {
                evidence.events.append(event)
            }
        }
    }

    func deleteEvent(id: UUID) { store.updateEvidence { $0.events.removeAll { $0.id == id } } }

    func save(era: EvidenceEra) {
        store.updateEvidence { evidence in
            if let index = evidence.eras.firstIndex(where: { $0.id == era.id }) {
                evidence.eras[index] = era
            } else {
                evidence.eras.append(era)
            }
        }
    }

    /// What was inside the period moves up to the period that held it.
    func deleteEra(id: UUID) {
        store.updateEvidence { evidence in
            guard let era = evidence.eras.first(where: { $0.id == id }) else { return }
            for index in evidence.eras.indices where evidence.eras[index].parentID == id {
                evidence.eras[index].parentID = era.parentID
            }
            for index in evidence.events.indices where evidence.events[index].eraID == id {
                evidence.events[index].eraID = era.parentID
            }
            evidence.eras.removeAll { $0.id == id }
        }
    }

    func setMasterName(_ value: String) {
        store.updateEvidence { $0.masterName = value.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    func openSource(id: UUID) { readInApp(id) }

    func openSource(id: UUID, page: Int) {
        readAt(id, page, evidence.term.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func occurrenceScan(of id: UUID) -> OccurrenceScan? { scans[id] }

    func checkedPlaces(of id: UUID) -> Set<String> { Set(evidence.checkedPlaces[id] ?? []) }

    func setChecked(_ checked: Bool, key: String, sourceID: UUID) {
        store.updateEvidence { evidence in
            var keys = evidence.checkedPlaces[sourceID] ?? []
            keys.removeAll { $0 == key }
            if checked { keys.append(key) }
            evidence.checkedPlaces[sourceID] = keys.isEmpty ? nil : keys
        }
    }

    /// Reads the PDF a few pages at a time and shows each place as soon as it is found. The pages are read on the
    /// main thread (PDFKit is meant for it), a few at a time with a pause in between, so the screen stays alive.
    func loadOccurrences(of id: UUID) {
        guard scans[id] == nil, !scanning.contains(id) else { return }
        let term = evidence.term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty, let item = store.workspace.items[id], let url = pdfURL(of: item) else {
            scans[id] = OccurrenceScan(isDone: true)
            return
        }
        scanning.insert(id)
        scans[id] = OccurrenceScan()
        let token = foundGeneration
        let limit = 400
        let lead = evidence.modifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        Task { @MainActor [weak self] in
            guard let document = PDFDocument(url: url) else {
                self?.receive(OccurrenceBatch(places: [], pagesRead: 0, pageCount: 0, isDone: true), id: id, token: token)
                return
            }
            let total = document.pageCount
            var pending: [TermOccurrence] = []
            var count = 0
            for index in 0..<total {
                let text = document.page(at: index)?.string ?? ""
                for match in TermCounter.matches(term, in: text, context: 120) where count < limit {
                    let withLead = !lead.isEmpty && match.before.lowercased().hasSuffix(lead + " ")
                    pending.append(TermOccurrence(
                        page: index, before: match.before, text: match.text, after: match.after, withModifier: withLead,
                        cutBefore: match.cutBefore, cutAfter: match.cutAfter
                    ))
                    count += 1
                }
                let isLast = index == total - 1 || count >= limit
                if isLast || (index + 1) % 2 == 0 {
                    let batch = OccurrenceBatch(places: pending, pagesRead: index + 1, pageCount: total, isDone: isLast)
                    pending = []
                    // False when the term or the project changed meanwhile: stop reading.
                    guard self?.receive(batch, id: id, token: token) == true else { return }
                    if isLast { return }
                    // A short pause lets the screen draw what was found so far.
                    try? await Task.sleep(for: .milliseconds(10))
                }
            }
            // A PDF with no pages.
            self?.receive(OccurrenceBatch(places: [], pagesRead: 0, pageCount: 0, isDone: true), id: id, token: token)
        }
    }

    /// Adds what the reader found. Returns false when the reading is out of date.
    @MainActor
    @discardableResult
    private func receive(_ batch: OccurrenceBatch, id: UUID, token: Int) -> Bool {
        guard foundGeneration == token else { return false }
        var scan = scans[id] ?? OccurrenceScan()
        scan.places += batch.places
        scan.pagesRead = batch.pagesRead
        scan.pageCount = batch.pageCount
        scan.isDone = batch.isDone
        scans[id] = scan
        if batch.isDone { scanning.remove(id) }
        return true
    }

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
    func export(format: EvidenceFormat) {
        let blocks = report
        let name = evidence.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format == .word ? DraftFormat.word.contentType : DraftFormat.plainText.contentType]
        let ext = format == .word ? DraftFormat.word.fileExtension : DraftFormat.plainText.fileExtension
        panel.nameFieldStringValue = (name.isEmpty ? L("evidence.defaultName") : name) + "." + ext
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let data = format == .word ? DocxWriter.reportData(for: blocks) : Data(ReportBlock.plainText(blocks).utf8)
        do { try data.write(to: url, options: .atomic) } catch { store.announce(L("compile.exportFailed")) }
    }
}
