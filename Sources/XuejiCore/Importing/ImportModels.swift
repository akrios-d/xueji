import Foundation

/// One word of a PDF page and where it sits. `top` and `bottom` count down from the top edge of the page,
/// in points. The app reads these from PDFKit; the parsers here only see the numbers, so they can be tested
/// without a PDF.
public struct ImportWord: Equatable, Sendable {
    public var x0: Double
    public var x1: Double
    public var top: Double
    public var bottom: Double
    public var text: String

    public init(x0: Double, x1: Double, top: Double, bottom: Double, text: String) {
        self.x0 = x0
        self.x1 = x1
        self.top = top
        self.bottom = bottom
        self.text = text
    }
}

public struct ImportPage: Equatable, Sendable {
    public var height: Double
    public var words: [ImportWord]

    public init(height: Double, words: [ImportWord]) {
        self.height = height
        self.words = words
    }
}

/// A row of a source triage table.
public struct ImportedSource: Equatable, Sendable {
    public var title: String
    public var venue: String
    public var year: Int?
    public var phase: String
    public var classification: Classification?
    public var triageNote: String
    /// The site of the link. Triage tables show a shortened link, so only the site is exact.
    public var url: URL?
    /// The link exactly as the table showed it.
    public var linkAsShown: String
    /// The row number ("#") in the table; the suggested reading order refers to it.
    public var number: Int?
    /// Position in the PDF's suggested reading order (1 = read first), when the PDF has one.
    public var readingOrder: Int?
    /// Why the PDF puts it there.
    public var readingReason: String

    public init(
        title: String, venue: String = "", year: Int? = nil, phase: String = "",
        classification: Classification? = nil, triageNote: String = "", url: URL? = nil, linkAsShown: String = "",
        number: Int? = nil, readingOrder: Int? = nil, readingReason: String = ""
    ) {
        self.title = title
        self.venue = venue
        self.year = year
        self.phase = phase
        self.classification = classification
        self.triageNote = triageNote
        self.url = url
        self.linkAsShown = linkAsShown
        self.number = number
        self.readingOrder = readingOrder
        self.readingReason = readingReason
    }
}

/// An entry of the reference list at the end of a who-said-what table.
public struct ImportedReference: Equatable, Sendable {
    public var number: Int
    public var authors: String
    public var year: Int?
    public var title: String
    public var venue: String
    public var doi: String
    public var url: URL?
    /// journalArticle, book, bookChapter or webPage when it can be told; empty otherwise.
    public var kind: String
    public var volume: String
    public var issue: String
    public var pages: String
    /// "2024-07-01".
    public var accessed: String
    public var publisher: String
    public var date: String

    public init(
        number: Int, authors: String = "", year: Int? = nil, title: String, venue: String = "", doi: String = "", url: URL? = nil,
        kind: String = "", volume: String = "", issue: String = "", pages: String = "", accessed: String = "",
        publisher: String = "", date: String = ""
    ) {
        self.kind = kind
        self.volume = volume
        self.issue = issue
        self.pages = pages
        self.accessed = accessed
        self.publisher = publisher
        self.date = date
        self.number = number
        self.authors = authors
        self.year = year
        self.title = title
        self.venue = venue
        self.doi = doi
        self.url = url
    }

    /// The venue followed by volume, issue and pages, for a card that has no fields for them.
    public var venueWithDetails: String {
        var detail = ""
        if !volume.isEmpty { detail = volume + (issue.isEmpty ? "" : "(\(issue))") } else if !issue.isEmpty { detail = "no. " + issue }
        if !pages.isEmpty { detail += (detail.isEmpty ? "" : ", ") + "pp. " + pages }
        if detail.isEmpty || venue.isEmpty { return venue.isEmpty ? detail : venue }
        return venue + ", " + detail
    }
}

/// A row of a who-said-what-and-when table.
public struct ImportedStatement: Equatable, Sendable {
    public var actor: String
    /// The key of one of the "Kind of actor" choices.
    public var actorKind: String?
    public var dateLabel: String
    public var date: CalendarDay?
    public var isApproximate: Bool
    public var phase: String
    public var position: String
    public var locator: String
    /// Where the actor spoke or wrote ("Speech, Shanghai Stock Exchange").
    public var context: String
    public var referenceNumbers: [Int]

    public init(
        actor: String, actorKind: String? = nil, dateLabel: String = "", date: CalendarDay? = nil, isApproximate: Bool = false,
        phase: String = "", position: String, locator: String = "", context: String = "", referenceNumbers: [Int] = []
    ) {
        self.actor = actor
        self.actorKind = actorKind
        self.dateLabel = dateLabel
        self.date = date
        self.isApproximate = isApproximate
        self.phase = phase
        self.position = position
        self.locator = locator
        self.context = context
        self.referenceNumbers = referenceNumbers
    }
}

public enum ImportedDocument: Equatable, Sendable {
    case sourceTriage([ImportedSource])
    case statements([ImportedStatement], references: [Int: ImportedReference])
}

public struct ImportSummary: Equatable, Sendable {
    public var sourcesAdded = 0
    public var statementsAdded = 0
    /// Rows that were already in the track.
    public var skippedDuplicates = 0
    /// Of those, the ones that are still waiting for the student's approval in the Inbox (so not on the other screens yet).
    public var skippedPending = 0
    /// Source rows whose link could not be read.
    public var skippedWithoutLink = 0

    public init() {}

    public var skipped: Int { skippedDuplicates + skippedWithoutLink }
}

/// Reads a PDF that was laid out as one of the known tables.
public enum PDFImporter {
    /// - Throws: `XuejiError.unrecognizedImport` when the pages hold neither a source triage table nor a
    ///   who-said-what table.
    public static func parse(_ pages: [ImportPage]) throws -> ImportedDocument {
        if let sources = TriageTableParser.parse(pages), !sources.isEmpty {
            return .sourceTriage(sources)
        }
        if let result = StatementsTableParser.parse(pages), !result.statements.isEmpty {
            return .statements(result.statements, references: result.references)
        }
        throw XuejiError.unrecognizedImport
    }

    /// A short, plain description of what the reader saw, for when a PDF is not recognised: how many words it
    /// found, and how close the best line came to each table's heading, with the position of its words.
    public static func describe(_ pages: [ImportPage]) -> String {
        let total = pages.reduce(0) { $0 + $1.words.count }
        var parts = ["Read \(pages.count) pages and \(total) words."]
        if total == 0 {
            parts.append("The PDF has no readable text (a scan, or the text could not be read).")
            return parts.joined(separator: "\n")
        }
        let headings: [(name: String, prefixes: [String])] = [
            ("triage", ["#", "Source", "Link", "Triage"]),
            ("statements", ["Date", "Who", "Position", "Ref"]),
        ]
        for heading in headings {
            var best: (hits: Int, line: [ImportWord], page: Int)?
            for (index, page) in pages.enumerated() {
                for line in TableLayout.lines(TableLayout.removingFooter(page.words)) {
                    let hits = heading.prefixes.filter { prefix in line.contains { $0.text.hasPrefix(prefix) } }.count
                    if hits > (best?.hits ?? 0) { best = (hits, line, index + 1) }
                }
            }
            if let best {
                let words = best.line.prefix(24).map { "\($0.text)@\(Int($0.x0)),\(Int($0.top))" }.joined(separator: " ")
                parts.append("\(heading.name): best line has \(best.hits) of \(heading.prefixes.count) heading words (page \(best.page)): \(words)")
            } else {
                parts.append("\(heading.name): no heading word found")
            }
        }
        return parts.joined(separator: "\n")
    }
}
