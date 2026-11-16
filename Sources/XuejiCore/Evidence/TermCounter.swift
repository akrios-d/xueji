import Foundation

/// Counts how often a word or phrase appears in a text, the way a triage table reports it:
/// whole words only, ignoring case.
public enum TermCounter {
    /// Words in the text. Each Chinese character counts as one word.
    public static func words(in text: String) -> Int {
        guard let expression = wordExpression else { return 0 }
        let source = prepared(text)
        return expression.numberOfMatches(in: source, range: NSRange(source.startIndex..., in: source))
    }

    /// Whole-word matches of `term` ("security" does not match "securitisation"). A phrase may break across lines.
    public static func count(_ term: String, in text: String) -> Int {
        guard let expression = phraseExpression(term) else { return 0 }
        let source = prepared(text)
        return expression.numberOfMatches(in: source, range: NSRange(source.startIndex..., in: source))
    }

    /// Matches of `term` directly after `modifier`, for example "national security".
    public static func count(_ term: String, after modifier: String, in text: String) -> Int {
        let lead = modifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let word = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lead.isEmpty, !word.isEmpty else { return 0 }
        return count(lead + " " + word, in: text)
    }

    /// One place where the term appears, with the words around it.
    public struct Match: Equatable, Sendable {
        public let before: String
        public let text: String
        public let after: String
        /// The words before were cut: the context starts in the middle of the text.
        public let cutBefore: Bool
        public let cutAfter: Bool
    }

    /// The places where `term` appears, in reading order, each with some context on both sides.
    /// Uses the same rule as `count`, so the list and the number agree.
    public static func matches(_ term: String, in text: String, context: Int = 70, limit: Int = 500) -> [Match] {
        guard let expression = phraseExpression(term) else { return [] }
        let source = prepared(text) as NSString
        var result: [Match] = []
        expression.enumerateMatches(in: source as String, range: NSRange(location: 0, length: source.length)) { found, _, stop in
            guard let range = found?.range else { return }
            let start = max(0, range.location - context)
            let end = min(source.length, range.location + range.length + context)
            result.append(Match(
                before: flatten(source.substring(with: NSRange(location: start, length: range.location - start))),
                text: flatten(source.substring(with: range)),
                after: flatten(source.substring(with: NSRange(location: range.location + range.length, length: end - range.location - range.length))),
                cutBefore: start > 0,
                cutAfter: end < source.length
            ))
            if result.count >= limit { stop.pointee = true }
        }
        return result
    }

    private static func flatten(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    /// Occurrences per 1,000 words, rounded to two decimals.
    public static func perThousand(_ count: Int, words: Int) -> Double {
        guard words > 0 else { return 0 }
        return (Double(count) / Double(words) * 100_000).rounded() / 100
    }

    // MARK: Internals

    /// Words split by a hyphen at the end of a line are joined again.
    static func prepared(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{00AD}", with: "")
            .replacingOccurrences(of: "-\r\n", with: "")
            .replacingOccurrences(of: "-\n", with: "")
    }

    private static let wordExpression = try? NSRegularExpression(
        pattern: "\\p{Han}|[\\p{L}\\p{N}]+(?:['’\\-][\\p{L}\\p{N}]+)*"
    )

    private static func phraseExpression(_ phrase: String) -> NSRegularExpression? {
        let parts = phrase.split(whereSeparator: { $0.isWhitespace }).map { NSRegularExpression.escapedPattern(for: String($0)) }
        guard !parts.isEmpty else { return nil }
        var pattern = parts.joined(separator: "\\s+")
        // Chinese is written without spaces, so a word boundary would never match.
        if !phrase.unicodeScalars.contains(where: isHan) {
            pattern = "(?<![\\p{L}\\p{N}_])" + pattern + "(?![\\p{L}\\p{N}_])"
        }
        return try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    private static func isHan(_ scalar: Unicode.Scalar) -> Bool {
        (0x3400...0x4DBF).contains(scalar.value) || (0x4E00...0x9FFF).contains(scalar.value)
    }
}
