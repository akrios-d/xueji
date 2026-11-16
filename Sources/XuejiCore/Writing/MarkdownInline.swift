import Foundation

/// A piece of a line written with light Markdown: `**bold**`, `*italic*` (or `_italic_`) and `$formula$`.
public enum InlinePiece: Equatable, Sendable {
    case text(String, bold: Bool, italic: Bool)
    /// A formula written in LaTeX, without the dollar signs.
    case math(String)
}

public enum MarkdownInline {
    public static func pieces(_ line: String) -> [InlinePiece] {
        var output: [InlinePiece] = []
        parse(Array(line), bold: false, italic: false, into: &output)
        return output
    }

    /// The text without its markup (formulas keep their LaTeX source).
    public static func stripped(_ line: String) -> String {
        pieces(line).map { piece in
            switch piece {
            case .text(let text, _, _): return text
            case .math(let source): return source
            }
        }.joined()
    }

    private static func parse(_ chars: [Character], bold: Bool, italic: Bool, into output: inout [InlinePiece]) {
        var buffer = ""
        func flush() {
            if !buffer.isEmpty { output.append(.text(buffer, bold: bold, italic: italic)); buffer = "" }
        }
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            // A backslash in front of a marker writes the marker itself.
            if ch == "\\", i + 1 < chars.count, "*_$\\".contains(chars[i + 1]) {
                buffer.append(chars[i + 1]); i += 2; continue
            }
            if ch == "$", let end = next(chars, "$", from: i + 1), isFormula(chars, i + 1, end) {
                flush(); output.append(.math(String(chars[(i + 1)..<end]))); i = end + 1; continue
            }
            if ch == "*", i + 2 < chars.count, chars[i + 1] == "*", !chars[i + 2].isWhitespace,
               let end = nextDouble(chars, from: i + 2) {
                flush(); parse(Array(chars[(i + 2)..<end]), bold: true, italic: italic, into: &output)
                i = end + 2; continue
            }
            let opensItalic = ch == "*" || (ch == "_" && (i == 0 || !chars[i - 1].isLetter && !chars[i - 1].isNumber))
            if opensItalic, i + 1 < chars.count, !chars[i + 1].isWhitespace, chars[i + 1] != ch,
               let end = closingItalic(chars, marker: ch, from: i + 1) {
                flush(); parse(Array(chars[(i + 1)..<end]), bold: bold, italic: true, into: &output)
                i = end + 1; continue
            }
            buffer.append(ch); i += 1
        }
        flush()
    }

    private static func next(_ chars: [Character], _ marker: Character, from start: Int) -> Int? {
        var i = start
        while i < chars.count {
            if chars[i] == "\\" { i += 2; continue }
            if chars[i] == marker { return i }
            i += 1
        }
        return nil
    }

    private static func nextDouble(_ chars: [Character], from start: Int) -> Int? {
        var i = start
        while i + 1 < chars.count {
            if chars[i] == "\\" { i += 2; continue }
            if chars[i] == "*", chars[i + 1] == "*", i > start, !chars[i - 1].isWhitespace { return i }
            i += 1
        }
        return nil
    }

    private static func closingItalic(_ chars: [Character], marker: Character, from start: Int) -> Int? {
        var i = start
        while i < chars.count {
            if chars[i] == "\\" { i += 2; continue }
            if chars[i] == marker, !chars[i - 1].isWhitespace {
                let after = i + 1 < chars.count ? chars[i + 1] : " "
                if marker == "*", after == "*" { i += 2; continue }
                if marker == "_", after.isLetter || after.isNumber { i += 1; continue }
                return i
            }
            i += 1
        }
        return nil
    }

    /// "$5 and $10" is money, not a formula: the formula must not touch spaces, and the closing sign must not be
    /// followed by a digit.
    private static func isFormula(_ chars: [Character], _ start: Int, _ end: Int) -> Bool {
        guard end > start, !chars[start].isWhitespace, !chars[end - 1].isWhitespace else { return false }
        if end + 1 < chars.count, chars[end + 1].isNumber { return false }
        return true
    }
}

/// How a paragraph of the draft is laid out: lines of text, list items, or a display formula.
public enum ParagraphPart: Equatable, Sendable {
    case lines([String])
    case bullet(String)
    case numbered(Int, String)
    /// `$$ … $$` alone in its paragraph.
    case display(String)
}

public enum MarkdownBlocks {
    public static func parts(of paragraph: String) -> [ParagraphPart] {
        let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 4, trimmed.hasPrefix("$$"), trimmed.hasSuffix("$$") {
            let inner = trimmed.dropFirst(2).dropLast(2).trimmingCharacters(in: .whitespacesAndNewlines)
            if !inner.isEmpty, !inner.contains("$$") { return [.display(inner)] }
        }
        var parts: [ParagraphPart] = []
        var lines: [String] = []
        func flush() { if !lines.isEmpty { parts.append(.lines(lines)); lines = [] } }
        for raw in paragraph.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if let text = bulletText(line) {
                flush(); parts.append(.bullet(text))
            } else if let (number, text) = numberedText(line) {
                flush(); parts.append(.numbered(number, text))
            } else {
                lines.append(raw)
            }
        }
        flush()
        return parts
    }

    private static func bulletText(_ line: String) -> String? {
        for marker in ["- ", "* ", "• "] where line.hasPrefix(marker) {
            let text = line.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : text
        }
        return nil
    }

    private static func numberedText(_ line: String) -> (Int, String)? {
        let digits = line.prefix(while: { $0.isNumber })
        guard !digits.isEmpty, digits.count <= 3, let number = Int(digits) else { return nil }
        let rest = line.dropFirst(digits.count)
        guard let mark = rest.first, mark == "." || mark == ")", rest.dropFirst().first == " " else { return nil }
        let text = rest.dropFirst(2).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : (number, text)
    }
}
