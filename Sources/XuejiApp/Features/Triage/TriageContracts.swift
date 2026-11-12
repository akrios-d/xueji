import Foundation
import XuejiCore

/// A source the quotes and the timeline can point to.
struct TriageSourceOption: Identifiable, Equatable {
    let id: UUID
    let title: String
}

/// One of the triages of the project, for the menu at the top.
struct TriageInfo: Identifiable, Equatable {
    let id: UUID
    let name: String
    let isActive: Bool
}

/// What the triage screen may read.
protocol ITriageView {
    /// The triages of the project, in the order they were made.
    var triageList: [TriageInfo] { get }
    var title: String { get }
    var term: String { get }
    var modifier: String { get }
    var corpusNote: String { get }
    var caution: String { get }
    var findings: String { get }
    /// Every approved source of the project, in the order of the table.
    var rows: [TriageSourceRow] { get }
    /// True while the PDFs are being read.
    var isCounting: Bool { get }
    var quotes: [TriageQuote] { get }
    var events: [TriageEvent] { get }
    /// For the pickers in the quote and timeline forms.
    var sourceOptions: [TriageSourceOption] { get }
    func sourceTitle(_ id: UUID?) -> String
    /// The report, rebuilt from the current choices.
    var report: [ReportBlock] { get }
    var justCopied: Bool { get }
}

/// What the triage screen may trigger.
protocol ITriageController {
    func selectTriage(id: UUID)
    func addTriage()
    /// Deletes the triage being shown.
    func deleteCurrentTriage()
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
    func save(quote: TriageQuote)
    func deleteQuote(id: UUID)
    func moveQuote(id: UUID, by offset: Int)
    func save(event: TriageEvent)
    func deleteEvent(id: UUID)
    func moveEvent(id: UUID, by offset: Int)
    func openSource(id: UUID)
    func copyReport()
    @MainActor func export(format: TriageFormat)
}

/// The files the report can be saved as.
enum TriageFormat: String, CaseIterable, Identifiable {
    case word, plainText
    var id: String { rawValue }
}

typealias ITriageViewModel = ITriageView & ITriageController
