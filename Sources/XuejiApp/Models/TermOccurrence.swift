import Foundation

/// One place where the term appears in a PDF.
struct TermOccurrence: Identifiable, Equatable, Sendable {
    let id = UUID()
    /// Zero-based, as PDFKit counts.
    let page: Int
    let before: String
    let text: String
    let after: String
    /// The word typed as modifier comes right before the term here.
    var withModifier = false
    /// The words around were cut in the middle of the text.
    var cutBefore = false
    var cutAfter = false

    /// Names this place again in a later reading of the same PDF (the id changes every time).
    var key: String { "\(page)|\(before.suffix(40))|\(text)|\(after.prefix(40))" }

    /// The passage for a quote: the words around the term without the pieces of words the cut left at the ends.
    var quoteText: String {
        var head = before
        var tail = after
        if cutBefore, let space = head.firstIndex(of: " ") { head = String(head[head.index(after: space)...]) }
        if cutAfter, let space = tail.lastIndex(of: " ") { tail = String(tail[..<space]) }
        return (head + text + tail).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The places found so far in one PDF, which grows while the pages are being read.
struct OccurrenceScan: Equatable {
    var places: [TermOccurrence] = []
    var pagesRead = 0
    var pageCount = 0
    var isDone = false
}

/// What the page reader hands over every few pages.
struct OccurrenceBatch: Sendable {
    var places: [TermOccurrence]
    var pagesRead: Int
    var pageCount: Int
    var isDone: Bool
}
