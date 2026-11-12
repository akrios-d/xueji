import Foundation

/// How much a quote matters to the argument.
enum TriageKind: String, Codable, CaseIterable, Identifiable {
    /// Directly evidences (or directly refutes) the claim.
    case essential
    /// Builds the surrounding argument.
    case supporting
    /// Cuts against the claim and must be addressed.
    case counter

    var id: String { rawValue }
}

/// A quote taken from a source, with where it comes from and why it matters.
struct TriageQuote: Codable, Equatable, Identifiable {
    var id = UUID()
    var text = ""
    /// The source card the quote comes from, when there is one.
    var sourceID: UUID?
    var speaker = ""
    /// Page, question number, paragraph…
    var locator = ""
    var kind: TriageKind = .essential
    var why = ""
}

/// One line of the timeline.
struct TriageEvent: Codable, Equatable, Identifiable {
    var id = UUID()
    /// Written as it should appear ("Feb 2019", "4–5 Nov 2019").
    var date = ""
    /// Its term count is shown when a source is linked.
    var sourceID: UUID?
    var event = ""
    var who = ""
    var frame = ""
    /// A document that is missing from the corpus: shaded, with no count.
    var isGap = false
}

/// A document of the counts table that has no source card here (it came from an imported report). Its numbers are
/// the ones the report showed; they are not counted again.
struct TriageDocument: Codable, Equatable, Identifiable {
    var id = UUID()
    var title = ""
    var date = ""
    var usage = ""
    var words = 0
    var term = 0
    var modifier = 0
}

/// What the student wrote about one source in the counts table.
struct TriageSourceNote: Codable, Equatable {
    /// Empty means the card's year.
    var date = ""
    var usage = ""
}

/// A quote triage of one project: how often a term appears in each source, the strongest quotes sorted by
/// importance, a timeline and the findings. One per project.
struct Triage: Codable, Equatable, Identifiable {
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
    var sourceNotes: [UUID: TriageSourceNote] = [:]
    var quotes: [TriageQuote] = []
    var events: [TriageEvent] = []
    var documents: [TriageDocument] = []

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
        sourceNotes = try values.decodeIfPresent([UUID: TriageSourceNote].self, forKey: .sourceNotes) ?? [:]
        quotes = try values.decodeIfPresent([TriageQuote].self, forKey: .quotes) ?? []
        events = try values.decodeIfPresent([TriageEvent].self, forKey: .events) ?? []
        documents = try values.decodeIfPresent([TriageDocument].self, forKey: .documents) ?? []
    }

    /// Nothing has been put in it yet.
    var isBlank: Bool {
        term.isEmpty && title.isEmpty && quotes.isEmpty && events.isEmpty && documents.isEmpty
            && findings.isEmpty && corpusNote.isEmpty && caution.isEmpty
    }
}
