import Foundation
import PDFKit
import XuejiCore

/// What the counts table shows for one source.
struct SourceCount: Equatable, Sendable {
    var words = 0
    var term = 0
    var modifier = 0
    /// False when the PDF has no text layer (a scan) or could not be opened.
    var hasText = false
}

/// Reads the text of a PDF and counts a term in it. Reads files, so call it away from the main thread.
enum SourceCounter {
    static func text(of url: URL) -> String {
        PDFDocument(url: url)?.string ?? ""
    }

    static func count(term: String, modifier: String, in text: String) -> SourceCount {
        SourceCount(
            words: TermCounter.words(in: text),
            term: TermCounter.count(term, in: text),
            modifier: TermCounter.count(term, after: modifier, in: text),
            hasText: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
    }
}
