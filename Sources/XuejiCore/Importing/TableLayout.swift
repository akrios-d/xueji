import Foundation

/// Small helpers to read tables out of positioned words.
enum TableLayout {
    /// Words whose tops are this close (in points) sit on the same line.
    static let lineTolerance = 3.0

    static func lines(_ words: [ImportWord]) -> [[ImportWord]] {
        let sorted = words.sorted { ($0.top, $0.x0) < ($1.top, $1.x0) }
        var groups: [(top: Double, words: [ImportWord])] = []
        for word in sorted {
            if let last = groups.last, abs(word.top - last.top) <= lineTolerance {
                groups[groups.count - 1].words.append(word)
            } else {
                groups.append((word.top, [word]))
            }
        }
        return groups.map { $0.words.sorted { $0.x0 < $1.x0 } }
    }

    /// Drops a page number at the foot of the page: a last line made of a lone number ("3", "Page 3", "3 of 8"),
    /// set apart from the text above it. Real text in the bottom margin is kept.
    static func removingFooter(_ words: [ImportWord]) -> [ImportWord] {
        let all = lines(words)
        guard all.count > 1, let last = all.last, last.count <= 3, let lastTop = last.first?.top,
              let previousTop = all[all.count - 2].first?.top, lastTop - previousTop > 8 else { return words }
        let text = last.map(\.text).joined(separator: " ")
        let pattern = #"^(page\s+)?\d{1,4}(\s*(of|/)\s*\d{1,4})?$"#
        guard text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil else { return words }
        return words.filter { !last.contains($0) }
    }

    /// The text of a table cell. A cell that continues on another page is a list of chunks, in reading order.
    /// A line that ends with a hyphen continues straight into the next one.
    static func text(of chunks: [[ImportWord]], joiner: String = " ") -> String {
        var result = ""
        for chunk in chunks {
            for line in lines(chunk) {
                let lineText = line.map(\.text).joined(separator: " ")
                if result.isEmpty {
                    result = lineText
                } else if joiner.isEmpty || result.hasSuffix("-") {
                    result += lineText
                } else {
                    result += joiner + lineText
                }
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Index of the column a word belongs to, given where each column starts.
    static func columnIndex(of x: Double, starts: [Double], tolerance: Double = 2.5) -> Int {
        var column = 0
        for (index, start) in starts.enumerated() where x >= start - tolerance { column = index }
        return column
    }

    /// The line that holds every one of these heading words (matched by prefix), if there is one.
    static func headerLine(in words: [ImportWord], containing prefixes: [String]) -> [ImportWord]? {
        lines(words).first { line in
            prefixes.allSatisfy { prefix in line.contains { $0.text.hasPrefix(prefix) } }
        }
    }

    static func start(of prefix: String, in header: [ImportWord]) -> Double? {
        header.first { $0.text.hasPrefix(prefix) }?.x0
    }
}

/// Text helpers shared by the parsers.
enum ImportText {
    /// Splits "Some title (inside)" into the text inside the last pair of brackets and what comes before it.
    static func trailingParenthetical(in text: String) -> (inner: String, rest: String)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix(")") else { return nil }
        var depth = 0
        var index = trimmed.endIndex
        while index > trimmed.startIndex {
            index = trimmed.index(before: index)
            switch trimmed[index] {
            case ")":
                depth += 1
            case "(":
                depth -= 1
                if depth == 0 {
                    let inner = trimmed[trimmed.index(after: index)..<trimmed.index(before: trimmed.endIndex)]
                    let rest = trimmed[..<index]
                    return (
                        inner.trimmingCharacters(in: .whitespaces),
                        rest.trimmingCharacters(in: .whitespaces)
                    )
                }
            default:
                break
            }
        }
        return nil
    }

    /// Four-digit years (1900–2099) in the order they appear.
    static func years(in text: String) -> [Int] {
        guard let regex = try? NSRegularExpression(pattern: #"\b(?:19|20)\d{2}\b"#) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).flatMap { Int(text[$0]) }
        }
    }

    /// The capture groups of the first match, with "" for a group that did not take part.
    static func captures(_ pattern: String, in text: String, options: NSRegularExpression.Options = []) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        return (1..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
        }
    }
}
