import Foundation
import PDFKit
import XuejiCore

/// One place where the searched phrase was found among the things a draft is based on.
struct SourceHit: Identifiable, Equatable, Sendable {
    enum Origin: Equatable, Sendable {
        /// The card's title, description, notes or a text field.
        case card
        /// The text of the PDF itself.
        case pdf
        /// A note the student wrote on a highlight in the reader.
        case readerNote
        /// One of the free notes in "Based on".
        case basisNote
    }

    let id: String
    /// nil for the free notes of "Based on".
    let itemID: UUID?
    let sourceTitle: String
    let origin: Origin
    /// Zero-based, for PDF hits and reader notes.
    let pageIndex: Int?
    let pageLabel: String?
    let excerpt: String
}

/// What to look through for one card.
struct SearchableSource: Sendable {
    let itemID: UUID
    let title: String
    /// Text of the card: title, description, notes, text fields.
    let texts: [String]
    /// The PDF on this Mac, when the source has one.
    let original: URL?
    /// Copies the student made for a topic; only their highlight notes are searched.
    let versions: [URL]
}

enum SourceSearcher {
    static let perSource = 8
    static let total = 100

    /// Looks for `query` in the free notes and in every source. Reads PDFs, so call it away from the main thread.
    static func search(
        _ query: String, notes: [String], notesTitle: String, sources: [SearchableSource]
    ) -> [SourceHit] {
        let phrase = TextSearch.normalized(query)
        guard !phrase.isEmpty else { return [] }
        var hits: [SourceHit] = []

        for (index, note) in notes.enumerated() {
            for (n, excerpt) in TextSearch.excerpts(of: phrase, in: note, limit: 1).enumerated() {
                hits.append(SourceHit(
                    id: "note-\(index)-\(n)", itemID: nil, sourceTitle: notesTitle, origin: .basisNote,
                    pageIndex: nil, pageLabel: nil, excerpt: excerpt
                ))
            }
        }

        for source in sources {
            if Task.isCancelled || hits.count >= total { break }
            var found: [SourceHit] = []
            for (index, text) in source.texts.enumerated() {
                for (n, excerpt) in TextSearch.excerpts(of: phrase, in: text, limit: 1).enumerated() {
                    found.append(SourceHit(
                        id: "\(source.itemID)-card-\(index)-\(n)", itemID: source.itemID, sourceTitle: source.title,
                        origin: .card, pageIndex: nil, pageLabel: nil, excerpt: excerpt
                    ))
                }
            }
            if let url = source.original, let document = PDFDocument(url: url) {
                found += pdfHits(phrase, in: document, source: source, includeText: true)
            }
            for url in source.versions {
                if let document = PDFDocument(url: url) {
                    found += pdfHits(phrase, in: document, source: source, includeText: false)
                }
            }
            hits += found.prefix(perSource)
        }
        return Array(hits.prefix(total))
    }

    private static func pdfHits(
        _ phrase: String, in document: PDFDocument, source: SearchableSource, includeText: Bool
    ) -> [SourceHit] {
        var hits: [SourceHit] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let label = page.label ?? String(index + 1)
            if includeText, let text = page.string {
                for (n, excerpt) in TextSearch.excerpts(of: phrase, in: text, limit: 3).enumerated() {
                    hits.append(SourceHit(
                        id: "\(source.itemID)-pdf-\(index)-\(n)", itemID: source.itemID, sourceTitle: source.title,
                        origin: .pdf, pageIndex: index, pageLabel: label, excerpt: excerpt
                    ))
                }
            }
            for (n, annotation) in page.annotations.enumerated() {
                guard annotation.userName?.hasPrefix(ReadingFiles.markPrefix) == true,
                      let note = annotation.contents, TextSearch.contains(phrase, in: note) else { continue }
                hits.append(SourceHit(
                    id: "\(source.itemID)-note-\(index)-\(n)-\(note.hashValue)", itemID: source.itemID,
                    sourceTitle: source.title, origin: .readerNote, pageIndex: index, pageLabel: label,
                    excerpt: TextSearch.excerpts(of: phrase, in: note, limit: 1).first ?? note
                ))
            }
            if hits.count >= perSource * 4 { break }
        }
        return hits
    }
}
