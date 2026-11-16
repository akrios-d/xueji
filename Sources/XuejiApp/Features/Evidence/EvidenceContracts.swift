import Foundation
import XuejiCore

/// A source the quotes and the timeline can point to.
struct EvidenceSourceOption: Identifiable, Equatable {
    let id: UUID
    let title: String
}

/// One of the triages of the project, for the menu at the top.
struct EvidenceInfo: Identifiable, Equatable {
    let id: UUID
    let name: String
    let isActive: Bool
}

/// What the triage screen may read.
protocol IEvidenceView {
    /// The triages of the project, in the order they were made.
    var evidenceList: [EvidenceInfo] { get }
    var title: String { get }
    var term: String { get }
    var modifier: String { get }
    var corpusNote: String { get }
    var caution: String { get }
    var findings: String { get }
    /// Every approved source of the project, in the order of the table.
    var rows: [EvidenceSourceRow] { get }
    /// True while the PDFs are being read.
    var isCounting: Bool { get }
    var quotes: [EvidenceQuote] { get }
    var events: [EvidenceEvent] { get }
    var eras: [EvidenceEra] { get }
    /// The periods as a tree, the master (the whole timeline) first.
    var eraOutline: [EraNode] { get }
    var masterTitle: String { get }
    /// The events of one period in date order; nil is the master.
    func events(in era: UUID?) -> [EvidenceEvent]
    /// The quote already saved for this passage of this document (another one than `id`), if any.
    func savedQuote(sourceID: UUID?, text: String, excluding id: UUID?) -> EvidenceQuote?
    /// For the pickers in the quote and timeline forms.
    var sourceOptions: [EvidenceSourceOption] { get }
    func sourceTitle(_ id: UUID?) -> String
    /// The places where the term appears in a source, as far as the PDF has been read; nil before it starts.
    func occurrenceScan(of id: UUID) -> OccurrenceScan?
    /// Keys of the places of a source that the student marked as checked.
    func checkedPlaces(of id: UUID) -> Set<String>
    /// Changes whenever the places have to be looked for again (new term, new project).
    var scanGeneration: Int { get }
    /// The report, rebuilt from the current choices.
    var report: [ReportBlock] { get }
    var justCopied: Bool { get }
}

/// What the triage screen may trigger.
protocol IEvidenceController {
    func selectEvidence(id: UUID)
    func addEvidence()
    /// Deletes the triage being shown.
    func deleteCurrentEvidence()
    func setTitle(_ value: String)
    func setTerm(_ value: String)
    func setModifier(_ value: String)
    func setCorpusNote(_ value: String)
    func setCaution(_ value: String)
    func setFindings(_ value: String)
    func setIncluded(_ included: Bool, sourceID: UUID)
    func setDate(_ value: String, sourceID: UUID)
    func setUsage(_ value: String, sourceID: UUID)
    func refresh()
    /// Removes a document that came from an imported report.
    func deleteDocument(id: UUID)
    /// Adds the quote, or replaces the one with the same id.
    func save(quote: EvidenceQuote)
    func deleteQuote(id: UUID)
    func moveQuote(id: UUID, by offset: Int)
    func save(event: EvidenceEvent)
    /// Reads an evidence report written as a PDF and adds what it holds to this report.
    func importReport(at url: URL)
    func deleteEvent(id: UUID)
    /// Puts every document that has a readable date and is not on the timeline yet on it. Returns how many.
    @discardableResult func generateTimeline() -> Int
    func save(era: EvidenceEra)
    func deleteEra(id: UUID)
    func setMasterName(_ value: String)
    func openSource(id: UUID)
    /// Opens the PDF on a page, with the term marked.
    func openSource(id: UUID, page: Int)
    /// Reads the PDF page by page to find where the term appears. Safe to call again.
    func loadOccurrences(of id: UUID)
    func setChecked(_ checked: Bool, key: String, sourceID: UUID)
    func copyReport()
    @MainActor func export(format: EvidenceFormat)
}

/// The files the report can be saved as.
enum EvidenceFormat: String, CaseIterable, Identifiable {
    case word, plainText
    var id: String { rawValue }
}

typealias IEvidenceViewModel = IEvidenceView & IEvidenceController
