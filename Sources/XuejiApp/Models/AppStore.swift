import Foundation
import AppKit
import Observation
import PDFKit
import XuejiCore

enum ImportOutcome {
    /// The PDF was one of the two tables; its rows wait in the Inbox.
    case table(ImportedResult)
    /// The PDF is not one of the tables, so it went to the Library as a source.
    case addedToLibrary(UUID)
    /// The PDF was a quote triage report; it was brought into the Triage screen.
    case triage(TriageImportSummary)
    /// Nothing was added; the reason is shown to the user.
    case failed
}

/// What an import added, and which table it was.
struct ImportedResult {
    let kind: ImportKind
    let summary: ImportSummary
}

/// The model layer the view models talk to. It owns the workspace and applies every change through
/// the core rules. Data lives in memory only for now; persistence will plug in here.
@Observable
final class AppStore {
    private(set) var workspace: Workspace
    let meID: UUID
    /// The project (track) being worked on; everything the screens show belongs to it.
    private(set) var trackID: UUID
    private(set) var errorMessage: String?
    /// A short confirmation of something that just happened (a card created, a PDF imported).
    private(set) var notice: String?
    /// Shown on the Library screen (a PDF that went there on its own).
    private(set) var libraryNotice: String?
    /// The card the user is looking at; shared by the board and the card panel.
    private(set) var focusedItemID: UUID?
    /// The card last dropped from the board, so it can be brought back.
    private(set) var lastDiscardedID: UUID?
    /// Free text the student writes (see `Draft`). In memory only, like the rest for now.
    private(set) var allDrafts: [Draft] = []
    /// The drafts of the current project.
    var drafts: [Draft] { allDrafts.filter { $0.trackID == trackID } }
    /// The draft deleted last, kept so the deletion can be undone.
    private(set) var lastDeletedDraft: Draft?
    /// The versions of each PDF (by source card) besides the original file. In memory only for now.
    private(set) var readingVersions: [UUID: [ReadingVersion]] = [:]

    /// How the drafts are assembled into one document.
    private(set) var compilations: [UUID: Compilation] = [:]
    /// The compilation of the current project.
    var compilation: Compilation { compilations[trackID] ?? Compilation() }

    /// The quote triages of each project (a project may have several, for different terms).
    private(set) var triageSets: [UUID: [Triage]] = [:]
    /// The one being shown in each project.
    private var activeTriageIDs: [UUID: UUID] = [:]
    /// The triages of the current project.
    var triages: [Triage] { triageSets[trackID] ?? [] }
    /// The triage being worked on in the current project.
    var triage: Triage {
        let list = triages
        return list.first { $0.id == activeTriageIDs[trackID] } ?? list.first ?? Triage()
    }

    /// Called with the colours of the highlights found in an imported PDF, so they join the palette.
    @ObservationIgnored var markColorsFound: ([String]) -> Void = { _ in }
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var quitObserver: NSObjectProtocol?

    init(
        workspace: Workspace, meID: UUID, trackID: UUID,
        drafts: [Draft] = [], readingVersions: [UUID: [ReadingVersion]] = [:], compilations: [UUID: Compilation] = [:],
        triageSets: [UUID: [Triage]] = [:], startupMessage: String? = nil
    ) {
        self.workspace = workspace
        self.meID = meID
        self.trackID = trackID
        self.allDrafts = drafts
        self.readingVersions = readingVersions
        self.compilations = compilations
        self.triageSets = triageSets
        self.errorMessage = startupMessage
        quitObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.saveNow() }
    }

    // MARK: Saving

    /// Writes everything to disk shortly after the last change (and always when the app quits).
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        saveTask?.cancel()
        let snapshot = Persistence.Snapshot(
            workspace: workspace, meID: meID, trackID: trackID, drafts: allDrafts,
            versions: readingVersions.values.flatMap { $0 }.sorted { $0.createdAt < $1.createdAt },
            compilation: nil, compilations: compilations, triages: nil, triageSets: triageSets
        )
        do { try Persistence.save(snapshot) } catch { errorMessage = L("persistence.saveFailed") }
    }

    // MARK: Reading

    func name(of id: UUID) -> String {
        workspace.members[id]?.name ?? "—"
    }

    // MARK: Actions (all go through Workspace rules; a failed rule leaves the state untouched)

    func approve(_ itemID: UUID) {
        perform(L("undo.approve")) { ws in _ = try ws.approve(itemID: itemID, by: meID) }
    }

    /// Decides many cards at once; either all of them or none (a rule that refuses one leaves everything as it was).
    func approve(all itemIDs: [UUID]) {
        perform(L("undo.approveAll")) { ws in for id in itemIDs { _ = try ws.approve(itemID: id, by: meID) } }
    }

    func reject(all itemIDs: [UUID]) {
        perform(L("undo.discardAll")) { ws in for id in itemIDs { _ = try ws.reject(itemID: id, by: meID) } }
    }

    func reject(_ itemID: UUID) {
        perform(L("undo.discard")) { ws in _ = try ws.reject(itemID: itemID, by: meID) }
    }

    /// Drops an approved card from the board.
    func discard(_ itemID: UUID) {
        perform(L("undo.discard")) { ws in _ = try ws.discard(itemID: itemID, by: meID) }
        if workspace.items[itemID]?.approval == .rejected { lastDiscardedID = itemID }
    }

    func undoDiscard() {
        lastDiscardedID = nil
        undo()
    }

    func dismissDiscard() { lastDiscardedID = nil }

    // MARK: Drafts

    @discardableResult
    func addDraft() -> UUID {
        let draft = Draft(trackID: trackID)
        allDrafts.append(draft)
        scheduleSave()
        return draft.id
    }

    func updateDraft(
        _ id: UUID, title: String? = nil, text: String? = nil, basis: String? = nil, linkedItemIDs: [UUID]? = nil
    ) {
        guard let index = allDrafts.firstIndex(where: { $0.id == id }) else { return }
        if let title { allDrafts[index].title = title }
        if let text { allDrafts[index].text = text }
        if let basis { allDrafts[index].basis = basis }
        if let linkedItemIDs { allDrafts[index].linkedItemIDs = linkedItemIDs }
        allDrafts[index].updatedAt = Date()
        scheduleSave()
    }

    func deleteDraft(_ id: UUID) {
        lastDeletedDraft = allDrafts.first { $0.id == id }
        allDrafts.removeAll { $0.id == id }
        scheduleSave()
    }

    /// Brings back the draft deleted last; returns its id.
    @discardableResult
    func restoreDraft() -> UUID? {
        guard let draft = lastDeletedDraft else { return nil }
        allDrafts.append(draft)
        lastDeletedDraft = nil
        scheduleSave()
        return draft.id
    }

    func forgetDeletedDraft() { lastDeletedDraft = nil }

    // MARK: Compilation

    func updateCompilation(_ change: (inout Compilation) -> Void) {
        var copy = compilation
        change(&copy)
        guard copy != compilation else { return }
        compilations[trackID] = copy
        scheduleSave()
    }

    // MARK: Triage

    /// Changes the triage being worked on (the first one is created when there is none yet).
    func updateTriage(_ change: (inout Triage) -> Void) {
        var list = triageSets[trackID] ?? []
        if list.isEmpty { list = [Triage()] }
        let index = list.firstIndex { $0.id == activeTriageIDs[trackID] } ?? 0
        var copy = list[index]
        change(&copy)
        guard copy != list[index] else { return }
        list[index] = copy
        triageSets[trackID] = list
        activeTriageIDs[trackID] = copy.id
        scheduleSave()
    }

    @discardableResult
    func addTriage() -> UUID {
        let created = Triage()
        triageSets[trackID, default: []].append(created)
        activeTriageIDs[trackID] = created.id
        scheduleSave()
        return created.id
    }

    func selectTriage(_ id: UUID) {
        guard triages.contains(where: { $0.id == id }) else { return }
        activeTriageIDs[trackID] = id
    }

    func deleteTriage(_ id: UUID) {
        triageSets[trackID]?.removeAll { $0.id == id }
        if activeTriageIDs[trackID] == id { activeTriageIDs[trackID] = triageSets[trackID]?.first?.id }
        scheduleSave()
    }

    // MARK: Reading versions

    func addVersion(_ version: ReadingVersion) {
        readingVersions[version.itemID, default: []].append(version)
        scheduleSave()
    }

    func renameVersion(itemID: UUID, id: UUID, to name: String) {
        guard let index = readingVersions[itemID]?.firstIndex(where: { $0.id == id }) else { return }
        readingVersions[itemID]?[index].name = name
        scheduleSave()
    }

    func removeVersion(itemID: UUID, id: UUID) {
        readingVersions[itemID]?.removeAll { $0.id == id }
        scheduleSave()
    }

    func stageCount(_ stage: Stage) -> Int {
        workspace.kanban(trackID: trackID)[stage]?.count ?? 0
    }

    func move(_ itemID: UUID, to stage: Stage) {
        perform(L("undo.move")) { ws in _ = try ws.move(itemID: itemID, to: stage, by: meID) }
    }

    /// Creates a card of any type as the student and returns its id, or nil when a rule refused it.
    @discardableResult
    func addCard(
        typeID: UUID, title: String, url: URL?, classification: Classification? = nil,
        values: [String: FieldValue] = [:]
    ) -> UUID? {
        var created: UUID?
        perform(L("undo.add")) { ws in
            created = try ws.createItem(
                trackID: trackID, typeID: typeID, title: title, url: url, classification: classification,
                values: values, by: meID
            ).id
        }
        return created
    }

    /// Adds any PDF to the library as a source card for study. The file is copied into the app's own folder, so
    /// the card keeps working if the original is moved or deleted. Returns the new card's id, or nil on failure.
    func addReferencePDF(at url: URL) -> UUID? {
        let folder: URL
        do {
            folder = try FileManager.default
                .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("Xueji/Library", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            report(.unreadableImport)
            return nil
        }
        guard let document = PDFDocument(url: url), document.pageCount > 0 else {
            report(.unreadableImport)
            return nil
        }
        let attributes = document.documentAttributes ?? [:]
        let fileTitle = url.deletingPathExtension().lastPathComponent
        let metadataTitle = (attributes[PDFDocumentAttribute.titleAttribute] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = metadataTitle.isEmpty ? fileTitle : metadataTitle
        let author = (attributes[PDFDocumentAttribute.authorAttribute] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let copy = folder.appendingPathComponent("\(UUID().uuidString)-\(url.lastPathComponent)")
        do {
            try FileManager.default.copyItem(at: url, to: copy)
        } catch {
            report(.unreadableImport)
            return nil
        }
        // Highlights the PDF already has become Xueji marks, with their colours. Only the copy is changed.
        let highlights = HighlightImporter.convert(at: copy)
        var createdID: UUID?
        perform { ws in
            var values: [String: FieldValue] = [:]
            if !author.isEmpty { values["authors"] = .text(author) }
            createdID = try ws.createItem(
                trackID: trackID, typeID: ItemType.sourceID, title: title, url: copy, values: values, by: meID
            ).id
        }
        if createdID == nil { try? FileManager.default.removeItem(at: copy) }
        if createdID != nil, highlights.count > 0 {
            markColorsFound(highlights.colors)
            announce(Lf(highlights.leftPainted ? "library.highlightsPainted" : "library.highlightsImported", highlights.count))
        }
        return createdID
    }

    /// Reads a PDF and adds its rows as cards that wait in the Inbox. Returns what was added, or nil when the
    /// file could not be read or is not one of the known tables (the reason is shown to the user).
    func importPDF(at url: URL, expecting kind: ImportKind? = nil) -> ImportOutcome {
        let pages: [ImportPage]
        do {
            pages = try PDFPageReader.pages(of: url)
        } catch {
            report(.unreadableImport)
            return .failed
        }
        if kind == nil || kind == .quoteTriage, let report = ImportedQuoteTriage.parse(pages) {
            return .triage(applyQuoteTriage(report))
        }
        if kind == .quoteTriage {
            self.report(.unrecognizedImport)
            return .failed
        }
        let document: ImportedDocument
        do {
            document = try PDFImporter.parse(pages)
        } catch {
            // Not one of the two tables. When the kind was left to Xueji, the PDF is simply a PDF to read.
            guard kind == nil else {
                report(.unrecognizedImport)
                return .failed
            }
            guard let id = addReferencePDF(at: url) else { return .failed }
            libraryNotice = L("library.notATable")
            return .addedToLibrary(id)
        }
        let detected: ImportKind
        switch document {
        case .sourceTriage: detected = .sourceTriage
        case .statements: detected = .statements
        }
        if let kind, kind != detected {
            report(kind == .sourceTriage ? .importIsStatements : .importIsSourceTriage)
            return .failed
        }
        var summary: ImportSummary?
        perform(L("undo.import")) { ws in
            summary = try ws.importDocument(document, trackID: trackID, by: meID, fileName: url.lastPathComponent)
        }
        return summary.map { .table(ImportedResult(kind: detected, summary: $0)) } ?? .failed
    }

    /// The file a card was imported from, if it came from an import.
    func importedFileName(of item: Item) -> String? {
        guard let detail = workspace.events.first(where: { $0.itemID == item.id && $0.kind == .created })?.detail,
              detail.hasPrefix("import:") else { return nil }
        return String(detail.dropFirst("import:".count))
    }

    /// Today as a calendar day, in the Mac's current time zone.
    var today: CalendarDay { CalendarDay(Date()) }

    func setDue(_ itemID: UUID, day: CalendarDay?) {
        perform(L("undo.due")) { ws in _ = try ws.setDueDay(itemID: itemID, to: day, by: meID) }
    }

    func addMilestone(title: String, day: CalendarDay) {
        perform { ws in _ = try ws.addMilestone(trackID: trackID, title: title, day: day, by: meID) }
    }

    func removeMilestone(_ id: UUID) {
        perform { ws in try ws.removeMilestone(id: id, by: meID) }
    }

    func focus(_ id: UUID?) {
        focusedItemID = id
    }

    func rename(_ id: UUID, title: String) {
        perform(L("undo.rename")) { ws in _ = try ws.renameItem(itemID: id, to: title, by: meID) }
    }

    func setNotes(_ id: UUID, text: String) {
        perform { ws in _ = try ws.setNotes(itemID: id, to: text, by: meID) }
    }

    func setClassification(_ id: UUID, _ classification: Classification?) {
        perform { ws in _ = try ws.setClassification(itemID: id, to: classification, by: meID) }
    }

    func setLink(_ id: UUID, url: URL?) {
        perform { ws in _ = try ws.setLink(itemID: id, to: url, by: meID) }
    }

    func setValue(_ id: UUID, key: String, value: FieldValue?) {
        perform { ws in _ = try ws.setFieldValue(itemID: id, key: key, to: value, by: meID) }
    }

    func addComment(_ id: UUID, text: String) {
        perform { ws in _ = try ws.addComment(itemID: id, by: meID, text: text) }
    }

    /// Shows an error for input the model never saw (for example text that is not a valid link).
    func report(_ error: XuejiError, detail: String? = nil) {
        let message = Lf("error.prefix", error.localizedMessage)
        errorMessage = detail.map { message + "\n" + $0 } ?? message
    }

    func announce(_ message: String) { notice = message }
    func dismissNotice() { notice = nil }
    func dismissLibraryNotice() { libraryNotice = nil }

    func dismissError() {
        errorMessage = nil
    }

    // MARK: Switching project

    /// Opens another project. What belonged to the one on screen (focus, undo history) does not carry over.
    func switchTrack(to id: UUID) {
        guard workspace.tracks[id] != nil else { return }
        trackID = id
        focusedItemID = nil
        lastDiscardedID = nil
        lastDeletedDraft = nil
        libraryNotice = nil
        undoStack.removeAll()
        redoStack.removeAll()
        scheduleSave()
    }

    // MARK: Undo

    private struct Snapshot {
        let label: String
        let workspace: Workspace
    }

    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []

    /// What ⌘Z would undo ("Move card"), or nil when there is nothing to undo.
    var undoLabel: String? { undoStack.last?.label }
    var redoLabel: String? { redoStack.last?.label }

    func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        redoStack.append(Snapshot(label: snapshot.label, workspace: workspace))
        workspace = snapshot.workspace
        lastDiscardedID = nil
        errorMessage = nil
        scheduleSave()
    }

    func redo() {
        guard let snapshot = redoStack.popLast() else { return }
        undoStack.append(Snapshot(label: snapshot.label, workspace: workspace))
        workspace = snapshot.workspace
        errorMessage = nil
        scheduleSave()
    }

    /// Applies a change through the core rules. Every successful change can be undone as a whole
    /// (the workspace is a value, so the state before it is simply kept).
    func perform(_ label: String = L("undo.change"), _ body: (inout Workspace) throws -> Void) {
        var copy = workspace
        do {
            try body(&copy)
            undoStack.append(Snapshot(label: label, workspace: workspace))
            if undoStack.count > 100 { undoStack.removeFirst() }
            redoStack.removeAll()
            workspace = copy
            scheduleSave()
            errorMessage = nil
        } catch {
            let reason = (error as? XuejiError)?.localizedMessage ?? L("error.unknown")
            errorMessage = Lf("error.prefix", reason)
        }
    }
}
