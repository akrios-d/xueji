import Foundation
import PDFKit

/// File work for reading versions. Highlights live inside the PDF files themselves, so they also show up in
/// Preview and survive on their own.
enum ReadingFiles {
    /// Marks made in Xueji carry this prefix in the annotation's name: "xueji:<group>:<kind>:<color>".
    static let markPrefix = "xueji:"

    struct Failure: Error {}

    /// Copies `source` into the versions folder of the card. Without `keepHighlights` the copy is clean.
    static func makeVersion(from source: URL, itemID: UUID, keepHighlights: Bool) throws -> URL {
        let folder = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Xueji/Versions/\(itemID.uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent(UUID().uuidString + ".pdf")
        try FileManager.default.copyItem(at: source, to: destination)
        if !keepHighlights { try stripMarks(from: destination) }
        return destination
    }

    /// Removes every mark made in Xueji from the file.
    static func stripMarks(from url: URL) throws {
        guard let document = PDFDocument(url: url) else { throw Failure() }
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            for annotation in page.annotations where annotation.userName?.hasPrefix(markPrefix) == true {
                page.removeAnnotation(annotation)
            }
        }
        try write(document, to: url)
    }

    /// Writes through a temporary file, so a failed write never damages the PDF.
    static func write(_ document: PDFDocument, to url: URL) throws {
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).pdf")
        guard document.write(to: temporary) else { throw Failure() }
        _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
    }
}
