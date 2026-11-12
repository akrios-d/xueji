import Foundation

/// Finds a phrase inside text and cuts short, readable excerpts around it.
/// Case and accents are ignored, so "analise" finds "Análise".
public enum TextSearch {
    static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    /// The phrase without surrounding whitespace.
    public static func normalized(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether `text` contains `query`.
    public static func contains(_ query: String, in text: String) -> Bool {
        let phrase = normalized(query)
        return !phrase.isEmpty && text.range(of: phrase, options: options) != nil
    }

    /// Excerpts around the occurrences of `query` in `text`: about `radius` characters on each side, whitespace
    /// collapsed, "…" where the text was cut. Occurrences that fall inside an earlier excerpt are not repeated.
    public static func excerpts(of query: String, in text: String, radius: Int = 70, limit: Int = 10) -> [String] {
        let phrase = normalized(query)
        guard !phrase.isEmpty, limit > 0 else { return [] }
        let clean = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
        var result: [String] = []
        var cursor = clean.startIndex
        while result.count < limit,
              cursor < clean.endIndex,
              let found = clean.range(of: phrase, options: options, range: cursor..<clean.endIndex) {
            let lower = clean.index(found.lowerBound, offsetBy: -radius, limitedBy: clean.startIndex) ?? clean.startIndex
            let upper = clean.index(found.upperBound, offsetBy: radius, limitedBy: clean.endIndex) ?? clean.endIndex
            var excerpt = String(clean[lower..<upper])
            if lower > clean.startIndex { excerpt = "…" + excerpt }
            if upper < clean.endIndex { excerpt += "…" }
            result.append(excerpt)
            cursor = upper
        }
        return result
    }
}
