import Foundation

/// One reference after conversion.
public struct ConvertedReference: Equatable, Sendable, Identifiable {
    public var id: Int { number }
    public let number: Int
    /// The text as it was pasted.
    public let original: String
    /// The reference in the target style (numbered styles already start with their number).
    public let text: String
    /// Fields the target style would print but that could not be read from the original: "authors", "year", "title", "venue".
    public let missing: [String]
}

/// Converts a pasted list of references from whatever style it is in to another style.
public enum ReferenceConverter {
    public static func convert(_ input: String, to style: CitationStyle) -> [ConvertedReference] {
        ReferenceParser.splitEntries(input).map { entry in
            let parsed = ReferenceParser.parse(number: entry.number, text: entry.text)
            let reference = Reference(
                id: UUID(), authors: parsed.authors, year: parsed.year, title: parsed.title, venue: parsed.venue,
                doi: parsed.doi, url: parsed.url?.absoluteString ?? "", kind: parsed.kind,
                volume: parsed.volume, issue: parsed.issue, pages: parsed.pages, accessed: parsed.accessed,
                publisher: parsed.publisher, date: parsed.date
            )
            var body = Citations.entry(reference, style: style, letter: "")
            if style.isNumbered {
                body = (style == .official ? "\(entry.number). " : "[\(entry.number)] ") + body
            }
            var missing: [String] = []
            if reference.authors.isEmpty { missing.append("authors") }
            if reference.year == nil, reference.date.isEmpty { missing.append("year") }
            if reference.title.isEmpty { missing.append("title") }
            if reference.venue.isEmpty, reference.publisher.isEmpty, reference.url.isEmpty { missing.append("venue") }
            return ConvertedReference(number: entry.number, original: entry.text, text: body, missing: missing)
        }
    }
}
