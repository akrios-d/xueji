import PDFKit
import XuejiCore

/// Reads the words of each PDF page together with where they sit on it. This is the only place that knows
/// about PDFKit: the parsers in XuejiCore only see words and numbers.
enum PDFPageReader {
    struct Unreadable: Error {}

    static func pages(of url: URL) throws -> [ImportPage] {
        guard let document = PDFDocument(url: url), document.pageCount > 0 else { throw Unreadable() }
        return (0..<document.pageCount).compactMap { index in document.page(at: index).map(readPage) }
    }

    /// The words come from the page text (split on whitespace) and each word's box from a PDFKit selection of
    /// exactly that range. Per-character boxes are not used: on some files (bold or white header text,
    /// ligatures) they do not line up with the text and words get cut or lose letters.
    private static func readPage(_ page: PDFPage) -> ImportPage {
        let bounds = page.bounds(for: .mediaBox)
        let text = (page.string ?? "") as NSString
        var words: [ImportWord] = []

        var start = -1
        func emit(upTo end: Int) {
            guard start >= 0, end > start else { start = -1; return }
            let range = NSRange(location: start, length: end - start)
            start = -1
            guard let selection = page.selection(for: range) else { return }
            let rect = selection.bounds(for: page)
            guard rect.width > 0, rect.height > 0 else { return }
            words.append(ImportWord(
                x0: Double(rect.minX - bounds.minX),
                x1: Double(rect.maxX - bounds.minX),
                top: Double(bounds.maxY - rect.maxY),
                bottom: Double(bounds.maxY - rect.minY),
                text: text.substring(with: range)
            ))
        }

        for index in 0..<text.length {
            let unit = text.character(at: index)
            let isSpace = Unicode.Scalar(unit).map { CharacterSet.whitespacesAndNewlines.contains($0) } ?? false
            if isSpace {
                emit(upTo: index)
            } else if start < 0 {
                start = index
            }
        }
        emit(upTo: text.length)
        return ImportPage(height: Double(bounds.height), words: words)
    }
}
