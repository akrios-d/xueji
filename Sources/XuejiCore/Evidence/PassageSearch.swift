import Foundation

/// Free search over the pages of several documents: words, or phrases between quotes.
/// Uses the same matching rule as `TermCounter` (whole words, ignoring case).
public enum PassageSearch {
    /// The words and quoted phrases of a query, in the order they were typed, without repeats.
    /// `security "national security" state` gives `security`, `national security`, `state`.
    public static func terms(_ query: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuote = false

        func flush() {
            let word = current.trimmingCharacters(in: .whitespacesAndNewlines)
            current = ""
            guard !word.isEmpty else { return }
            if !result.contains(where: { $0.caseInsensitiveCompare(word) == .orderedSame }) { result.append(word) }
        }

        for character in query {
            if character == "\"" || character == "\u{201C}" || character == "\u{201D}" {
                flush()
                inQuote.toggle()
            } else if character.isWhitespace && !inQuote {
                flush()
            } else {
                current.append(character)
            }
        }
        flush()
        return result
    }

    /// One place that matched, with the words around it.
    public struct Hit: Equatable, Sendable {
        /// Zero-based, as PDFKit counts.
        public let page: Int
        /// The word or phrase of the query that matched here.
        public let term: String
        public let before: String
        public let text: String
        public let after: String
        public let cutBefore: Bool
        public let cutAfter: Bool
    }

    /// The places where the query matches in the pages of one document, in reading order.
    /// With several terms, only pages that have every one of them count, so the list shows where the ideas meet.
    public static func hits(for terms: [String], inPages pages: [String], context: Int = 120, limit: Int = 300) -> [Hit] {
        guard !terms.isEmpty, limit > 0 else { return [] }
        var result: [Hit] = []
        for (index, text) in pages.enumerated() {
            if terms.count > 1, terms.contains(where: { TermCounter.count($0, in: text) == 0 }) { continue }
            for term in terms {
                for match in TermCounter.matches(term, in: text, context: context, limit: limit - result.count) {
                    result.append(Hit(
                        page: index, term: term, before: match.before, text: match.text, after: match.after,
                        cutBefore: match.cutBefore, cutAfter: match.cutAfter
                    ))
                    if result.count >= limit { return result }
                }
            }
        }
        return result
    }
}
