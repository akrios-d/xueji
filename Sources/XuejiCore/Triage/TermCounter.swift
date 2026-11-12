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
