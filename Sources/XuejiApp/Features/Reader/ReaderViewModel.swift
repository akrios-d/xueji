import AppKit
import Foundation
import Observation
import PDFKit
import XuejiCore

@Observable
final class ReaderViewModel: IReaderView, IReaderController {
    private let store: AppStore
    private(set) var itemID: UUID?
    private(set) var currentVersionID: UUID?
    private(set) var document: PDFDocument?
    private(set) var marks: [ReaderMark] = []
    private(set) var hasSelection = false
    private var selectedColorHex = UserDefaults.standard.string(forKey: "markColorHex") ?? ""
    private let library: ColorLibrary
    private(set) var searchText = ""
    private(set) var searchStatus: String?
    private(set) var message: String?
    private(set) var followScroll = UserDefaults.standard.object(forKey: "readerFollowScroll") as? Bool ?? true
    private(set) var visiblePages: Set<Int> = []
    private(set) var focusedMarkID: String?
    private(set) var markQuery = ""

    @ObservationIgnored private weak var pdfView: PDFView?
    @ObservationIgnored private var matches: [PDFSelection] = []
    @ObservationIgnored private var matchIndex = 0
    /// Where to land once the PDF is on screen (set when a search result opens the reader).
    @ObservationIgnored private var pendingPage: Int?
    @ObservationIgnored private var pendingSearch: String?
    @ObservationIgnored private var flashToken = 0

    /// Wired by the composition root: goes back to the Library.
    var onClose: () -> Void = {}

    init(store: AppStore, colors: ColorLibrary) {
        self.store = store
        self.library = colors
    }

    // MARK: Opening

    /// Opens the original PDF of a source; with `page` (zero-based) and `search` it lands there with the phrase marked.
    func open(itemID: UUID, page: Int? = nil, search: String? = nil) {
        self.itemID = itemID
        currentVersionID = itemID
        resetSearch()
        searchText = search ?? ""
        pendingPage = page
        pendingSearch = search
        loadDocument()
    }

    // MARK: IReaderView

    var title: String { itemID.flatMap { store.workspace.items[$0]?.title } ?? "" }

    var versions: [ReadingVersion] {
        guard let itemID, let item = store.workspace.items[itemID], let url = item.url, url.isFileURL else { return [] }
        let original = ReadingVersion(
            id: itemID, itemID: itemID, name: L("reader.original"), fileURL: url,
            createdAt: item.createdAt, isOriginal: true
        )
        return [original] + (store.readingVersions[itemID] ?? [])
    }

    var currentVersion: ReadingVersion? {
        versions.first { $0.id == currentVersionID } ?? versions.first
    }

    var drafts: [Draft] { store.drafts.sorted { $0.updatedAt > $1.updatedAt } }

    // MARK: IReaderController

    func attach(_ view: PDFView) {
        pdfView = view
        guard pendingPage != nil || pendingSearch != nil, view.document === document, let document else { return }
        let page = pendingPage.flatMap { document.page(at: $0) }
        let phrase = pendingSearch
        pendingPage = nil
        pendingSearch = nil
        DispatchQueue.main.async { [weak self, weak view] in
            if let page { view?.go(to: page) }
            if let phrase, let self {
                self.searchText = phrase
                self.search()
                if let page { view?.go(to: page) }
            }
        }
    }
    func selectionChanged(hasSelection: Bool) { self.hasSelection = hasSelection }

    func visiblePagesChanged(_ pages: [Int]) {
        let set = Set(pages)
        if set != visiblePages { visiblePages = set }
        updateFocus()
    }

    var shownMarks: [ReaderMark] {
        let words = markQuery.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return marks }
        // Every word has to be in the quote, the note or the page label, whatever the case or the accents.
        return marks.filter { mark in
            let text = [mark.quote, mark.note, mark.pageLabel].joined(separator: " ")
            return words.allSatisfy { text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }

    func setMarkQuery(_ text: String) { markQuery = text }

    func setFollowScroll(_ follow: Bool) {
        followScroll = follow
        UserDefaults.standard.set(follow, forKey: "readerFollowScroll")
        updateFocus()
    }

    func selectVersion(id: UUID) {
        currentVersionID = id
        resetSearch()
        loadDocument()
    }

    func createVersion(named name: String, keepHighlights: Bool) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let itemID, let current = currentVersion, !clean.isEmpty else { return }
        do {
            let url = try ReadingFiles.makeVersion(from: current.fileURL, itemID: itemID, keepHighlights: keepHighlights)
            let version = ReadingVersion(
                id: UUID(), itemID: itemID, name: clean, fileURL: url, createdAt: Date(), isOriginal: false
            )
            store.addVersion(version)
            selectVersion(id: version.id)
        } catch {
            message = L("reader.error.version")
        }
    }

    func renameCurrentVersion(to name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let itemID, let current = currentVersion, !current.isOriginal, !clean.isEmpty else { return }
        store.renameVersion(itemID: itemID, id: current.id, to: clean)
    }

    func deleteCurrentVersion() {
        guard let itemID, let current = currentVersion, !current.isOriginal else { return }
        store.removeVersion(itemID: itemID, id: current.id)
        try? FileManager.default.removeItem(at: current.fileURL)
        selectVersion(id: itemID)
    }

    func mark(_ kind: MarkKind) {
        guard let pdfView, let selection = pdfView.currentSelection,
              selection.string?.isEmpty == false else {
            message = L("reader.selectFirst")
            return
        }
        let group = UUID().uuidString
        var touched: [PDFPage] = []
        for line in selection.selectionsByLine() {
            for page in line.pages {
                let bounds = line.bounds(for: page)
                guard bounds.width > 0, bounds.height > 0 else { continue }
                let annotation = PDFAnnotation(
                    bounds: bounds, forType: kind == .highlight ? .highlight : .underline, withProperties: nil
                )
                let w = bounds.width, h = bounds.height
                annotation.quadrilateralPoints = [
                    CGPoint(x: 0, y: h), CGPoint(x: w, y: h), CGPoint(x: 0, y: 0), CGPoint(x: w, y: 0),
                ].map { NSValue(point: $0) }
                let chosen = markColor
                let base = chosen.nsColor
                annotation.color = kind == .highlight ? base.withAlphaComponent(0.45) : base
                annotation.userName = "\(ReadingFiles.markPrefix)\(group):\(kind.rawValue):\(chosen.hex)"
                page.addAnnotation(annotation)
                touched.append(page)
            }
        }
        guard !touched.isEmpty else {
            message = L("reader.markFailed")
            return
        }
        message = nil
        for page in touched { pdfView.annotationsChanged(on: page) }
        pdfView.clearSelection()
        hasSelection = false
        saveAndReload()
    }

    var colors: [MarkColor] { library.colors }

    /// The colour in use; the first of the palette when the chosen one was removed.
    var markColor: MarkColor {
        library.color(forHex: selectedColorHex) ?? library.colors[0]
    }

    func setMarkColor(_ color: MarkColor) { choose(color.hex) }

    func addColor(name: String, hex: String) { choose(library.add(name: name, hex: hex).hex) }
    func renameColor(hex: String, to name: String) { library.rename(hex: hex, to: name) }
    func removeColor(hex: String) { library.remove(hex: hex) }
    func resetColors() { library.reset() }

    private func choose(_ hex: String) {
        selectedColorHex = hex
        UserDefaults.standard.set(hex, forKey: "markColorHex")
    }

    func setNote(_ note: String, markID: String) {
        let found = annotations(of: markID)
        guard !found.isEmpty else { return }
        for (index, item) in found.enumerated() { item.annotation.contents = index == 0 ? note : "" }
        saveAndReload()
    }

    func deleteMark(id: String) {
        for item in annotations(of: id) {
            item.page.removeAnnotation(item.annotation)
            pdfView?.annotationsChanged(on: item.page)
        }
        saveAndReload()
    }

    /// Goes to the marked text and makes it blink, so it is easy to spot among the rest of the page.
    func show(markID: String) {
        let found = annotations(of: markID)
        guard let first = found.first, let pdfView else { return }
        let selections = found.compactMap { item -> PDFSelection? in
            let bounds = item.annotation.bounds
            return item.page.selection(for: bounds.insetBy(dx: 1, dy: bounds.height * 0.25))
        }
        guard let selection = selections.first else {
            pdfView.go(to: first.annotation.bounds, on: first.page)
            return
        }
        for other in selections.dropFirst() { selection.add(other) }
        pdfView.go(to: selection)
        flashToken += 1
        let token = flashToken
        Task { @MainActor [weak self] in
            for step in 0..<6 {
                guard let self, self.flashToken == token, let view = self.pdfView else { return }
                view.setCurrentSelection(step % 2 == 0 ? selection : nil, animate: step == 0)
                try? await Task.sleep(for: .milliseconds(240))
            }
            guard let self, self.flashToken == token else { return }
            self.pdfView?.clearSelection()
        }
    }

    func copyQuote(markID: String) {
        guard let line = citation(of: markID) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(line, forType: .string)
    }

    func addQuote(markID: String, toDraft draftID: UUID?) {
        guard let line = citation(of: markID), let itemID else { return }
        let id = draftID ?? store.addDraft()
        guard let draft = store.drafts.first(where: { $0.id == id }) else { return }
        if draftID == nil { store.updateDraft(id, title: Lf("reader.draftTitle", title)) }
        let text = draft.text.isEmpty ? line : draft.text + "\n\n" + line
        let linked = draft.linkedItemIDs.contains(itemID) ? draft.linkedItemIDs : draft.linkedItemIDs + [itemID]
        store.updateDraft(id, text: text, linkedItemIDs: linked)
        message = L("reader.addedToDraft")
    }

    func setSearchText(_ text: String) {
        searchText = text
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { resetSearch() }
    }

    func search() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let document, !query.isEmpty else { return resetSearch() }
        matches = document.findString(query, withOptions: .caseInsensitive)
        for match in matches { match.color = .systemYellow }
        pdfView?.highlightedSelections = matches
        matchIndex = 0
        focusMatch()
    }

    func nextMatch() {
        guard !matches.isEmpty else { return }
        matchIndex = (matchIndex + 1) % matches.count
        focusMatch()
    }

    func previousMatch() {
        guard !matches.isEmpty else { return }
        matchIndex = (matchIndex - 1 + matches.count) % matches.count
        focusMatch()
    }

    func dismissMessage() { message = nil }
    func close() { onClose() }

    // MARK: Private

    private struct Found {
        let group: String
        let kind: MarkKind
        let colorHex: String
        let annotation: PDFAnnotation
        let page: PDFPage
        let pageIndex: Int
    }

    private func loadDocument() {
        document = currentVersion.flatMap { PDFDocument(url: $0.fileURL) }
        if document == nil { message = L("reader.error.open") }
        reloadMarks()
    }

    private func resetSearch() {
        matches = []
        matchIndex = 0
        searchStatus = nil
        pdfView?.highlightedSelections = nil
    }

    private func focusMatch() {
        guard matches.indices.contains(matchIndex) else {
            searchStatus = L("reader.noMatches")
            return
        }
        let match = matches[matchIndex]
        pdfView?.setCurrentSelection(match, animate: true)
        pdfView?.go(to: match)
        searchStatus = Lf("reader.matches", matchIndex + 1, matches.count)
    }

    /// Every mark made in Xueji on the open document, in reading order.
    private func allFound() -> [Found] {
        guard let document else { return [] }
        var result: [Found] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let onPage: [Found] = page.annotations.compactMap { annotation in
                guard let name = annotation.userName, name.hasPrefix(ReadingFiles.markPrefix) else { return nil }
                let parts = name.split(separator: ":").map(String.init)
                guard parts.count >= 4, let kind = MarkKind(rawValue: parts[2]) else { return nil }
                let hex = ColorLibrary.legacyHex[parts[3]] ?? parts[3].uppercased()
                // A reloaded file can bring the colour back without its transparency, which would hide the text.
                if kind == .highlight, let base = NSColor(hex: hex), annotation.color.alphaComponent > 0.5 {
                    annotation.color = base.withAlphaComponent(0.45)
                }
                return Found(group: parts[1], kind: kind, colorHex: NSColor(hex: hex) == nil ? "FFD60A" : hex, annotation: annotation, page: page, pageIndex: index)
            }
            result += onPage.sorted { $0.annotation.bounds.maxY > $1.annotation.bounds.maxY }
        }
        return result
    }

    private func annotations(of group: String) -> [Found] { allFound().filter { $0.group == group } }

    private func reloadMarks() {
        var order: [String] = []
        var groups: [String: [Found]] = [:]
        for found in allFound() {
            if groups[found.group] == nil { order.append(found.group) }
            groups[found.group, default: []].append(found)
        }
        marks = order.compactMap { group in
            guard let parts = groups[group], let first = parts.first else { return nil }
            let quote = parts.map { self.text(of: $0) }.joined(separator: " ")
            let note = parts.compactMap { $0.annotation.contents }.first { !$0.isEmpty } ?? ""
            return ReaderMark(
                id: group, kind: first.kind, colorHex: first.colorHex,
                pageLabel: first.page.label ?? String(first.pageIndex + 1), pageIndex: first.pageIndex,
                quote: Self.clean(quote), note: note
            )
        }
        updateFocus()
    }

    /// The first mark on the pages on screen, or the next one below them (the last one at the end of the file).
    private func updateFocus() {
        guard let top = visiblePages.min(), !marks.isEmpty else {
            if focusedMarkID != nil { focusedMarkID = nil }
            return
        }
        let target = marks.first { visiblePages.contains($0.pageIndex) }
            ?? marks.first { $0.pageIndex > top }
            ?? marks.last
        if target?.id != focusedMarkID { focusedMarkID = target?.id }
    }

    private func text(of found: Found) -> String {
        let bounds = found.annotation.bounds
        return found.page.selection(for: bounds.insetBy(dx: 1, dy: bounds.height * 0.25))?.string ?? ""
    }

    private func citation(of group: String) -> String? {
        guard let mark = marks.first(where: { $0.id == group }), !mark.quote.isEmpty else { return nil }
        return "“\(mark.quote)” (\(title), p. \(mark.pageLabel))"
    }

    private func saveAndReload() {
        if let document, let url = currentVersion?.fileURL {
            do { try ReadingFiles.write(document, to: url) } catch { message = L("reader.error.save") }
        }
        reloadMarks()
    }

    private static func clean(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }
}
