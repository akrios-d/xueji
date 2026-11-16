import Foundation
import XuejiCore

/// How much a quote matters to the argument.
enum EvidenceKind: String, Codable, CaseIterable, Identifiable {
    /// Directly evidences (or directly refutes) the claim.
    case essential
    /// Builds the surrounding argument.
    case supporting
    /// Cuts against the claim and must be addressed.
    case counter

    var id: String { rawValue }
}

/// A quote taken from a source, with where it comes from and why it matters.
struct EvidenceQuote: Codable, Equatable, Identifiable {
    var id = UUID()
    var text = ""
    /// The source card the quote comes from, when there is one.
    var sourceID: UUID?
    var speaker = ""
    /// Page, question number, paragraph…
    var locator = ""
    var kind: EvidenceKind = .essential
    var why = ""
}

/// One line of the timeline.
struct EvidenceEvent: Codable, Equatable, Identifiable {
    var id = UUID()
    /// Written as it should appear ("Feb 2019", "4–5 Nov 2019"). Kept in step with `when`, and the only date of
    /// events imported from a report until they are edited.
    var date = ""
    /// The date as it was chosen: a year, a month or a day.
    var when: EvidenceDate?
    /// When the event lasted for a period, where it ended (`when` is where it began).
    var until: EvidenceDate?
    /// Its term count is shown when a source is linked.
    var sourceID: UUID?
    /// The quote that shows it, when there is one. Its document is the source of the event.
    var quoteID: UUID?
    /// The period it belongs to; nil is the whole timeline (the master period).
    var eraID: UUID?
    var event = ""
    var who = ""
    var frame = ""
    /// A document that is missing from the corpus: shaded, with no count.
    var isGap = false
}

extension EvidenceEvent {
    /// Where the event stands in time: the chosen date, or the one read from the text.
    var position: EvidenceDate? { when ?? EvidenceDate.parse(date) }
    var dateLabel: String { when.map { EvidenceDate.label(from: $0, until: until) } ?? date }
}

/// A named stretch of time of the timeline ("the 2019–2023 expansion") with the quotes that belong to it.
struct EvidenceEra: Codable, Equatable, Identifiable {
    var id = UUID()
    var name = ""
    var from = EvidenceDate(year: Calendar.current.component(.year, from: Date()))
    var until = EvidenceDate(year: Calendar.current.component(.year, from: Date()))
    var quoteIDs: [UUID] = []
    /// The period it sits inside; nil is the whole timeline (the master period).
    var parentID: UUID?

    var dateLabel: String { EvidenceDate.label(from: from, until: until) }
}

extension EvidenceSet {
    /// The timeline in date order; events with no readable date keep their order at the end.
    var sortedEvents: [EvidenceEvent] {
        let indexed = events.enumerated().map { (index: $0.offset, event: $0.element, date: $0.element.position?.start) }
        return indexed.sorted { a, b in
            switch (a.date, b.date) {
            case let (x?, y?): return x != y ? x < y : a.index < b.index
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.index < b.index
            }
        }.map(\.event)
    }

    /// The periods, the earliest first.
    var sortedEras: [EvidenceEra] {
        eras.enumerated().sorted { a, b in
            a.element.from.start != b.element.from.start ? a.element.from.start < b.element.from.start : a.offset < b.offset
        }.map(\.element)
    }
}

/// A document of the counts table that has no source card here (it came from an imported report). Its numbers are
/// the ones the report showed; they are not counted again.
struct EvidenceDocument: Codable, Equatable, Identifiable {
    var id = UUID()
    var title = ""
    var date = ""
    var usage = ""
    var words = 0
    var term = 0
    var modifier = 0
}

/// What the student wrote about one source in the counts table.
struct EvidenceSourceNote: Codable, Equatable {
    /// Empty means the card's year.
    var date = ""
    var usage = ""
}

/// A quote triage of one project: how often a term appears in each source, the strongest quotes sorted by
/// importance, a timeline and the findings. One per project.
struct EvidenceSet: Codable, Equatable, Identifiable {
    var id = UUID()
    var title = ""
    var term = ""
    /// A word that may come before the term; "national" counts "national security" separately.
    var modifier = ""
    /// Shown at the top of the report, for example that a document is missing.
    var corpusNote = ""
    /// Shown under the counts table.
    var caution = ""
    /// One finding per line.
    var findings = ""
    /// Sources left out of the counts.
    var excluded: [UUID] = []
    var sourceNotes: [UUID: EvidenceSourceNote] = [:]
    var quotes: [EvidenceQuote] = []
    var events: [EvidenceEvent] = []
    var documents: [EvidenceDocument] = []
    /// The places of each source that the student already checked (see `TermOccurrence.key`).
    var checkedPlaces: [UUID: [String]] = [:]
    /// Named periods of the timeline.
    var eras: [EvidenceEra] = []
    /// The name of the master period, which covers the whole timeline; empty uses the default name.
    var masterName = ""

    init() {}

    /// Missing values take their defaults, so files written by an older version still load.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try values.decodeIfPresent(String.self, forKey: .title) ?? ""
        term = try values.decodeIfPresent(String.self, forKey: .term) ?? ""
        modifier = try values.decodeIfPresent(String.self, forKey: .modifier) ?? ""
        corpusNote = try values.decodeIfPresent(String.self, forKey: .corpusNote) ?? ""
        caution = try values.decodeIfPresent(String.self, forKey: .caution) ?? ""
        findings = try values.decodeIfPresent(String.self, forKey: .findings) ?? ""
        excluded = try values.decodeIfPresent([UUID].self, forKey: .excluded) ?? []
        sourceNotes = try values.decodeIfPresent([UUID: EvidenceSourceNote].self, forKey: .sourceNotes) ?? [:]
        quotes = try values.decodeIfPresent([EvidenceQuote].self, forKey: .quotes) ?? []
        events = try values.decodeIfPresent([EvidenceEvent].self, forKey: .events) ?? []
        documents = try values.decodeIfPresent([EvidenceDocument].self, forKey: .documents) ?? []
        checkedPlaces = try values.decodeIfPresent([UUID: [String]].self, forKey: .checkedPlaces) ?? [:]
        eras = try values.decodeIfPresent([EvidenceEra].self, forKey: .eras) ?? []
        masterName = try values.decodeIfPresent(String.self, forKey: .masterName) ?? ""
    }

    /// Nothing has been put in it yet.
    var isBlank: Bool {
        term.isEmpty && title.isEmpty && quotes.isEmpty && events.isEmpty && eras.isEmpty && documents.isEmpty
            && findings.isEmpty && corpusNote.isEmpty && caution.isEmpty
    }
}
